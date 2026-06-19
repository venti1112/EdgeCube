package com.venti1112.edgecube.shell

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import com.venti1112.edgecube.server.EcPty
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * 交互式 shell 的 PTY 进程管理器（应用级单例）。
 *
 * 是 [com.venti1112.edgecube.server.ServerProcessManager] 的裁剪版：复用 [EcPty] 在
 * /dev/ptmx 上拉起一个交互 shell（系统 sh 或自带 busybox/bash），父进程读写主设备 fd。
 * 与服务端管理器相比去掉了运行时解压、DONE 状态机、玩家解析与前台 Service——shell 在
 * 真实 TTY 上自带行编辑/历史/补全，界面只需把原始字节转发给 xterm 渲染、把按键写回 PTY。
 */
class ShellProcessManager private constructor(private val appContext: Context) {

    companion object {
        /** 原始字节回放缓冲上限（重连后恢复终端画面）。 */
        private const val MAX_RAW_BYTES = 256 * 1024

        private const val DEFAULT_ROWS = 24
        private const val DEFAULT_COLS = 80
        private const val DEFAULT_CELL_W = 8
        private const val DEFAULT_CELL_H = 16

        @Volatile
        private var instance: ShellProcessManager? = null

        fun getInstance(context: Context): ShellProcessManager =
            instance ?: synchronized(this) {
                instance ?: ShellProcessManager(context.applicationContext).also { instance = it }
            }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val rawLock = Any()
    private val rawBuffer = ArrayDeque<ByteArray>()
    private var rawBytesTotal = 0

    @Volatile private var masterFd: Int = -1
    @Volatile private var processId: Int = -1
    @Volatile private var ptyOutput: FileOutputStream? = null
    @Volatile private var running: Boolean = false
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var currentLabel: String? = null

    @Volatile private var lastRows = DEFAULT_ROWS
    @Volatile private var lastCols = DEFAULT_COLS
    @Volatile private var lastCellW = DEFAULT_CELL_W
    @Volatile private var lastCellH = DEFAULT_CELL_H

    val isRunning: Boolean get() = running

    /** 设置/解除事件接收端。设置时回放原始终端字节与当前状态，使重连界面恢复画面。 */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) return
        val rawSnapshot = synchronized(rawLock) {
            val total = ByteArray(rawBytesTotal)
            var off = 0
            for (chunk in rawBuffer) {
                System.arraycopy(chunk, 0, total, off, chunk.size)
                off += chunk.size
            }
            total
        }
        val label = currentLabel
        val isRun = running
        mainHandler.post {
            if (rawSnapshot.isNotEmpty()) {
                sink.success(mapOf("type" to "term", "bytes" to rawSnapshot))
            }
            sink.success(stateMap(if (isRun) "running" else null, label, null))
        }
    }

    /** 启动交互 shell。[cwd] 为初始工作目录（空/无效则用外部存储根或私有目录）。 */
    @Synchronized
    fun start(cwd: String?) {
        if (isRunning) return

        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        val workDir = cwd?.takeIf { File(it).isDirectory } ?: ShellResolver.defaultCwd(appContext)
        val spec = ShellResolver.resolveInteractive(nativeDir)
        val env = ShellResolver.baseEnv(appContext, nativeDir, workDir)

        val argv = ArrayList<String>()
        argv.add(spec.cmd)
        argv.addAll(spec.argvPrefix)
        val envp = env.map { "${it.key}=${it.value}" }.toTypedArray()

        val pidHolder = IntArray(1)
        val fd = EcPty.createSubprocess(
            spec.cmd,
            workDir,
            argv.toTypedArray(),
            envp,
            pidHolder,
            lastRows,
            lastCols,
            lastCellW,
            lastCellH,
        )
        if (fd < 0) throw IllegalStateException("创建 PTY 子进程失败")

        masterFd = fd
        processId = pidHolder[0]
        ptyOutput = FileOutputStream(EcPty.fdFromInt(fd))
        running = true
        currentLabel = spec.label
        emitState("running", spec.label, null)
        emitTerm("[EdgeCube] shell: ${spec.label} @ $workDir\r\n".toByteArray(StandardCharsets.UTF_8))

        thread(name = "shell-pty") {
            val input = FileInputStream(EcPty.fdFromInt(fd))
            val buf = ByteArray(8192)
            try {
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n == 0) continue
                    emitTerm(buf.copyOf(n))
                }
            } catch (_: Exception) {
                // PTY 主设备在子进程退出后 read 常返回 EIO，作正常结束处理。
            }

            val raw = try {
                EcPty.waitFor(processId)
            } catch (_: Exception) {
                -1
            }
            val code = if (raw < 0) 128 - raw else raw

            try {
                EcPty.close(fd)
            } catch (_: Exception) {
            }

            synchronized(this) {
                if (masterFd == fd) {
                    running = false
                    masterFd = -1
                    processId = -1
                    ptyOutput = null
                    currentLabel = null
                    emitTerm("\r\n[EdgeCube] shell 已退出（退出码 $code）\r\n".toByteArray(StandardCharsets.UTF_8))
                    emitState(null, null, code)
                }
            }
        }
    }

    /** 向 shell PTY 写入原始按键字节（来自 xterm 终端的直接输入）。 */
    fun writeInput(bytes: ByteArray) {
        val out = ptyOutput ?: return
        try {
            out.write(bytes)
            out.flush()
        } catch (_: Exception) {
        }
    }

    /** 向 shell PTY 写入一行命令（自动补换行）。 */
    fun sendCommand(line: String) {
        writeInput((line + "\n").toByteArray(StandardCharsets.UTF_8))
    }

    /** 界面终端尺寸变化时同步 PTY 窗口大小。 */
    fun resize(rows: Int, cols: Int, cellWidth: Int, cellHeight: Int) {
        if (rows <= 0 || cols <= 0) return
        lastRows = rows
        lastCols = cols
        if (cellWidth > 0) lastCellW = cellWidth
        if (cellHeight > 0) lastCellH = cellHeight
        val fd = masterFd
        if (fd < 0) return
        try {
            EcPty.setPtyWindowSize(fd, rows, cols, lastCellW, lastCellH)
        } catch (_: Exception) {
        }
    }

    /** 开关 PTY 回显（交互 shell 一般保持开启，由 tty/shell 自身回显）。 */
    fun setEcho(echo: Boolean) {
        val fd = masterFd
        if (fd < 0) return
        try {
            EcPty.setPtyEcho(fd, echo)
        } catch (_: Exception) {
        }
    }

    /** 优雅退出：向 shell 发送 exit。 */
    fun stop() {
        if (!running) return
        sendCommand("exit")
    }

    /** 强制结束 shell 进程（SIGTERM）。 */
    fun forceStop() {
        val p = processId
        if (p <= 0) return
        try {
            Os.kill(p, OsConstants.SIGTERM)
        } catch (_: Exception) {
        }
    }

    /** 清空原始字节回放缓冲（与界面清屏同步）。 */
    fun clearLog() {
        synchronized(rawLock) {
            rawBuffer.clear()
            rawBytesTotal = 0
        }
    }

    // ──────────────────────────────────────────────────────
    // 内部：原始字节转发 / 事件下发
    // ──────────────────────────────────────────────────────

    private fun emitTerm(bytes: ByteArray) {
        synchronized(rawLock) {
            rawBuffer.addLast(bytes)
            rawBytesTotal += bytes.size
            while (rawBytesTotal > MAX_RAW_BYTES && rawBuffer.isNotEmpty()) {
                rawBytesTotal -= rawBuffer.removeFirst().size
            }
        }
        val sink = eventSink ?: return
        mainHandler.post { sink.success(mapOf("type" to "term", "bytes" to bytes)) }
    }

    private fun emitState(status: String?, label: String?, exitCode: Int?) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(stateMap(status, label, exitCode)) }
    }

    private fun stateMap(status: String?, label: String?, exitCode: Int?): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["type"] = "state"
        map["status"] = status // null 表示已退出
        map["label"] = label
        if (exitCode != null) map["exitCode"] = exitCode
        return map
    }
}
