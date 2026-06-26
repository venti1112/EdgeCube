package com.venti1112.edgecube.server

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * 把服务端 JVM 作为独立子进程拉起，并管理其生命周期。应用级单例，不绑定 Activity——
 * 这样 Activity 因切后台被销毁重建时，进程与日志仍在。
 *
 * 关键点：
 *  - 通过 [EcPty] 在 /dev/ptmx 上创建一对伪终端：服务端进程跑在真实 TTY 上（fork+
 *    execvp liblaunch.so，由它 dlopen libjli.so 启动 JVM），故支持 Tab 补全、命令历史、
 *    JLine 控制台与原生 ANSI 着色。父进程读写 PTY 主设备 fd 与之通信。
 *  - 主设备读出的原始字节有两个去向：① 作为 `term` 事件原样转发给 Flutter 的
 *    xterm.dart 渲染；② 按行去 ANSI 后作为 `log` 事件，喂给既有的状态识别 / 玩家解析 /
 *    崩溃检测逻辑，行为与改造前一致。
 *  - 进程级隔离：服务端崩溃不影响应用；可独立 kill。
 *  - 启动时拉起前台 [ServerService] 保活，退出时撤下。
 *  - 维护日志（行）与原始字节双缓冲；界面（重新）连接事件流时回放历史，使重建/被回收
 *    后的界面能恢复终端内容与运行状态。
 */
class ServerProcessManager private constructor(private val appContext: Context) {

    companion object {
        private const val MAX_LOG_LINES = 2000

        /** 原始字节回放缓冲上限（约一屏多的历史，足够重连后恢复终端画面）。 */
        private const val MAX_RAW_BYTES = 256 * 1024

        /** 单行未遇换行时的最大累积字节，超出强制断行，防止异常输出撑爆内存。 */
        private const val MAX_LINE_BYTES = 16 * 1024

        const val STATUS_PREPARING = "preparing"
        const val STATUS_STARTING  = "starting"
        const val STATUS_RUNNING   = "running"

        // —— PTY 初始窗口尺寸；界面布局完成后会通过 resize() 校正为真实值。 ——
        private const val DEFAULT_ROWS = 24
        private const val DEFAULT_COLS = 80
        private const val DEFAULT_CELL_W = 8
        private const val DEFAULT_CELL_H = 16

        /** 服务端初始化完成标志：匹配英文 "Done (Xs)!"（Velocity/Paper）或中文 "启动完成 (Xs)"。 */
        private val DONE_PATTERN =
            Regex("""Done\s*\([0-9.]+s\)!|启动完成\s*\([0-9.]+s\)""")

        /** 日志中的 ANSI 转义序列（CSI，如颜色码 \x1B[36m）；按行解析前剔除。 */
        private val ANSI_PATTERN = Regex("\\x1B\\[[0-?]*[ -/]*[@-~]")

        @Volatile
        private var instance: ServerProcessManager? = null

        fun getInstance(context: Context): ServerProcessManager =
            instance ?: synchronized(this) {
                instance ?: ServerProcessManager(context.applicationContext).also { instance = it }
            }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // —— 清洗后的日志行缓冲（供复制/解析/回放）——
    private val logLock = Any()
    private val logBuffer = ArrayDeque<String>()

    // —— 原始字节缓冲（供 xterm 终端画面回放）——
    private val rawLock = Any()
    private val rawBuffer = ArrayDeque<ByteArray>()
    private var rawBytesTotal = 0

    // —— 按行组装 term 原始字节为清洗后的日志行 ——
    private val lineAssembler = ByteArrayOutputStream()

    @Volatile private var masterFd: Int = -1
    @Volatile private var processId: Int = -1
    @Volatile private var ptyOutput: FileOutputStream? = null
    @Volatile private var running: Boolean = false
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var runningInstanceId: String? = null
    @Volatile private var runningInstanceName: String? = null
    @Volatile private var runningRuntimeId: String? = null
    @Volatile private var currentStatus: String? = null

    // —— 最近一次由界面上报的终端尺寸；新进程沿用，避免一闪一变。 ——
    @Volatile private var lastRows = DEFAULT_ROWS
    @Volatile private var lastCols = DEFAULT_COLS
    @Volatile private var lastCellW = DEFAULT_CELL_W
    @Volatile private var lastCellH = DEFAULT_CELL_H

    val isRunning: Boolean get() = running
    val activeInstanceId: String? get() = runningInstanceId

    /** 当前正在使用的运行时 id（如 "jre21"/"php8.2"）；未运行时返回 null。 */
    val activeRuntimeId: String? get() = runningRuntimeId

    /** 子进程 PID；未运行时返回 -1。 */
    val pid: Int get() = if (running) processId else -1

    /**
     * 设置/解除事件接收端。设置时回放历史（清洗日志行 + 原始终端字节）与当前状态，
     * 使重建/被回收后重连的界面能恢复终端画面与正在运行的实例。
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) return
        val logSnapshot = synchronized(logLock) { logBuffer.toList() }
        val rawSnapshot = synchronized(rawLock) {
            val total = ByteArray(rawBytesTotal)
            var off = 0
            for (chunk in rawBuffer) {
                System.arraycopy(chunk, 0, total, off, chunk.size)
                off += chunk.size
            }
            total
        }
        val status = currentStatus
        val id = runningInstanceId
        val name = runningInstanceName
        mainHandler.post {
            for (line in logSnapshot) {
                sink.success(mapOf("type" to "log", "line" to line))
            }
            if (rawSnapshot.isNotEmpty()) {
                sink.success(mapOf("type" to "term", "bytes" to rawSnapshot))
            }
            sink.success(stateMap(status, id, name, null))
        }
    }

    /**
     * 启动服务端。含首次运行时（JRE / PHP）解压，耗时，必须在后台线程调用。
     *
     * [runtime] 为 [com.venti1112.edgecube.server] 约定的 "java"（默认）或 "php"：
     *  - java：执行 nativeLibraryDir 下的 liblaunch.so，由它 dlopen JRE 的 libjli.so 启动 JVM。
     *  - php ：执行 libphploader.so，dlopen libphpwrapper.so（→ libphp.so）运行脚本。
     *
     * 与改造前相比，唯一变化是用 [EcPty] 在 PTY 上拉起进程（取代 ProcessBuilder），
     * stdio 改为 PTY 从设备，因此进程认为自己连着真实终端。
     */
    @Synchronized
    fun start(
        instanceId: String,
        instanceName: String,
        workingDir: String,
        runtimeId: String,
        runtime: String,
        jvmArgs: List<String>,
        programArgs: List<String>,
    ) {
        if (isRunning) throw IllegalStateException("已有服务端正在运行，请先停止")

        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        // LD_PRELOAD 标签修复库：拦截 malloc/free 恢复指针标签再释放，解决 Android 15+ MTE 崩溃
        val tagfixLib = "$nativeDir/libtagfix.so"

        // 子进程会 clearenv 后重建环境，故须传入「继承自本进程的环境 + 覆盖项」的完整集合。
        val env = HashMap(System.getenv())
        val cmd: String
        val argv = ArrayList<String>()

        if (runtime == "php") {
            val manifest = RuntimeInstaller.installedRuntime(appContext, runtimeId)
                ?: throw IllegalStateException("PHP 运行时 $runtimeId 未安装，请先在「管理 → 运行环境」导入")
            val runtimeDir = RuntimeInstaller.runtimeDir(appContext, runtimeId)
            val launcherLib = File(runtimeDir, manifest.launcher.lib)
            if (!launcherLib.exists()) {
                throw IllegalStateException("未找到 PHP wrapper 库：${launcherLib.absolutePath}")
            }
            val loaderBin = File(nativeDir, "libphploader.so")
            if (!loaderBin.exists()) {
                throw IllegalStateException("未找到 libphploader.so，请确认其已随 APK 打包到 lib 目录")
            }
            cmd = loaderBin.absolutePath
            argv.add(loaderBin.absolutePath)
            argv.addAll(programArgs) // 即 [phar]

            env["EC_PHP_LIB"] = launcherLib.absolutePath
            env["LD_PRELOAD"] = tagfixLib
            env["LD_LIBRARY_PATH"] = "${launcherLib.parentFile?.absolutePath}:$nativeDir"
            env["HOME"] = workingDir
            env["TMPDIR"] = appContext.cacheDir.absolutePath
            env["LANG"] = "en_US.UTF-8"
            env["TERM"] = "xterm-256color"
            // 叠加清单中的 env（${RUNTIME_DIR} 替换）
            applyManifestEnv(env, manifest, runtimeDir)
        } else {
            val manifest = RuntimeInstaller.installedRuntime(appContext, runtimeId)
                ?: throw IllegalStateException("JRE 运行时 $runtimeId 未安装，请先在「管理 → 运行环境」导入")
            val runtimeDir = RuntimeInstaller.runtimeDir(appContext, runtimeId)
            val resolved = JreLayout.resolve(runtimeDir, nativeDir)
            val launchBin = File(nativeDir, "liblaunch.so")
            if (!launchBin.exists()) {
                throw IllegalStateException("未找到 liblaunch.so，请确认其已随 APK 打包到 lib 目录")
            }

            cmd = launchBin.absolutePath
            argv.add(launchBin.absolutePath)
            // JVM 崩溃时将 hs_err 输出到 stderr（PTY 从设备），父进程能收到
            argv.add("-XX:ErrorFile=/proc/self/fd/2")
            // Android 上 /tmp 不可写，全局指定可写的 tmpdir
            argv.add("-Djava.io.tmpdir=${appContext.cacheDir.absolutePath}")
            argv.addAll(jvmArgs)
            argv.addAll(programArgs)

            env["LD_PRELOAD"] = tagfixLib
            env["JAVA_HOME"] = runtimeDir.absolutePath
            env["EC_LIBJLI"] = resolved.libjli.absolutePath
            env["LD_LIBRARY_PATH"] = resolved.ldLibraryPath
            env["HOME"] = workingDir
            env["TMPDIR"] = appContext.cacheDir.absolutePath
            env["LANG"] = "en_US.UTF-8"
            // JLine/终端能力依赖 TERM；给一个广泛支持的 256 色终端类型。
            env["TERM"] = "xterm-256color"
            // FCL/Pojav 修改过的 JRE 需通过这些变量定位 app 的原生库目录
            env["FCL_NATIVEDIR"] = nativeDir
            env["POJAV_NATIVEDIR"] = nativeDir
            // 叠加清单中的 env（${RUNTIME_DIR} 替换；PATH/LD_LIBRARY_PATH 追加）
            applyManifestEnv(env, manifest, runtimeDir)
        }

        val envp = env.map { "${it.key}=${it.value}" }.toTypedArray()
        val pidHolder = IntArray(1)
        val fd = EcPty.createSubprocess(
            cmd,
            workingDir,
            argv.toTypedArray(),
            envp,
            pidHolder,
            lastRows,
            lastCols,
            lastCellW,
            lastCellH,
        )
        if (fd < 0) throw IllegalStateException("创建 PTY 子进程失败")

        // 新进程开始，重置按行组装器，避免上次的残留半行拼接进来。
        synchronized(lineAssembler) { lineAssembler.reset() }

        masterFd = fd
        processId = pidHolder[0]
        ptyOutput = FileOutputStream(EcPty.fdFromInt(fd))
        running = true
        runningInstanceId = instanceId
        runningInstanceName = instanceName
        runningRuntimeId = runtimeId
        currentStatus = STATUS_STARTING
        emitState(STATUS_STARTING, instanceId, instanceName, null)

        // 拉起前台 Service 保活。
        ServerService.start(appContext, instanceName)

        thread(name = "server-pty-$instanceId") {
            val input = FileInputStream(EcPty.fdFromInt(fd))
            val buf = ByteArray(8192)
            try {
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n == 0) continue
                    val chunk = buf.copyOf(n)
                    // ① 原样转发给终端渲染。
                    emitTerm(chunk)
                    // ② 按行去 ANSI，喂给状态识别 / 玩家解析。
                    assembleLines(chunk)
                }
            } catch (_: Exception) {
                // PTY 主设备在子进程退出后 read 常返回 EIO，作正常结束处理。
            }
            // 冲刷末尾未换行的残留行。
            flushAssembler()

            val raw = try {
                EcPty.waitFor(processId)
            } catch (_: Exception) {
                -1
            }
            // <0 表示被信号杀死，转成 128+signal 的惯例退出码；用户主动停止由 Dart 侧标记，不报崩溃。
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
                    val id = runningInstanceId
                    val name = runningInstanceName
                    runningInstanceId = null
                    runningInstanceName = null
                    runningRuntimeId = null
                    currentStatus = null
                    emitState(null, id, name, code)
                }
            }
            // 进程结束，撤下前台 Service。
            ServerService.stop(appContext)
        }
    }

    /** 向服务端 PTY 写入原始按键字节（来自 xterm 终端的直接输入）。 */
    fun writeInput(bytes: ByteArray) {
        val out = ptyOutput ?: return
        try {
            out.write(bytes)
            out.flush()
        } catch (e: Exception) {
            emitNotice("[EdgeCube] 写入终端失败：${e.message}")
        }
    }

    /** 向服务端 PTY 写入一行命令（自动补换行）。供程序化发送（如 stop）使用。 */
    fun sendCommand(line: String) {
        writeInput((line + "\n").toByteArray(StandardCharsets.UTF_8))
    }

    /** 界面终端尺寸变化时调用，同步 PTY 窗口大小，连接的程序会据此重排。 */
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

    /** 开关 PTY 回显。命令行编辑模式关闭（App 自行回显），原始终端模式开启。 */
    fun setEcho(echo: Boolean) {
        val fd = masterFd
        if (fd < 0) return
        try {
            EcPty.setPtyEcho(fd, echo)
        } catch (_: Exception) {
        }
    }

    /** 优雅停止：向 Minecraft 服务端发送 stop 命令。 */
    fun stop() {
        sendCommand("stop")
    }

    /** 强制结束进程（SIGTERM，与原 Process.destroy() 语义一致）。 */
    fun forceStop() {
        val p = processId
        if (p <= 0) return
        try {
            Os.kill(p, OsConstants.SIGTERM)
        } catch (e: Exception) {
            emitNotice("[EdgeCube] 强制结束失败：${e.message}")
        }
    }

    /** 清空日志与原始字节缓冲（与界面的清屏保持一致）。 */
    fun clearLog() {
        synchronized(logLock) { logBuffer.clear() }
        synchronized(rawLock) {
            rawBuffer.clear()
            rawBytesTotal = 0
        }
    }

    // ──────────────────────────────────────────────────────
    // 内部：原始字节 / 按行组装 / 事件下发
    // ──────────────────────────────────────────────────────

    /**
     * EdgeCube 自身的提示信息：这些不是 PTY 进程的输出，故须主动写入终端画面（term）
     * 才能被看到；同时进日志缓冲（log），让复制日志 / 崩溃报告也能包含它们。
     */
    private fun emitNotice(msg: String) {
        emitTerm((msg + "\r\n").toByteArray(StandardCharsets.UTF_8))
        emitLog(msg)
    }

    /** 转发原始终端字节并写入回放缓冲。 */
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

    /** 把原始字节按 '\n' 切成整行，逐行解码并交给 [emitLine]。 */
    private fun assembleLines(chunk: ByteArray) {
        synchronized(lineAssembler) {
            for (b in chunk) {
                if (b.toInt() == '\n'.code) {
                    emitLineFromAssembler()
                } else {
                    lineAssembler.write(b.toInt())
                    if (lineAssembler.size() >= MAX_LINE_BYTES) emitLineFromAssembler()
                }
            }
        }
    }

    /** 冲刷组装器中剩余的半行（进程结束时调用）。 */
    private fun flushAssembler() {
        synchronized(lineAssembler) {
            if (lineAssembler.size() > 0) emitLineFromAssembler()
        }
    }

    /** 调用方须持有 lineAssembler 锁。 */
    private fun emitLineFromAssembler() {
        val raw = lineAssembler.toByteArray()
        lineAssembler.reset()
        // 解码 + 去 '\r' + 去 ANSI，得到用于解析/复制的纯文本行。
        val decoded = String(raw, StandardCharsets.UTF_8).replace("\r", "")
        val clean = ANSI_PATTERN.replace(decoded, "")
        emitLog(clean)
        if (currentStatus == STATUS_STARTING && DONE_PATTERN.containsMatchIn(clean)) {
            currentStatus = STATUS_RUNNING
            emitState(STATUS_RUNNING, runningInstanceId, runningInstanceName, null)
        }
    }

    /** 追加一条清洗后的日志行并下发 `log` 事件。 */
    private fun emitLog(line: String) {
        synchronized(logLock) {
            logBuffer.addLast(line)
            while (logBuffer.size > MAX_LOG_LINES) logBuffer.removeFirst()
        }
        val sink = eventSink ?: return
        mainHandler.post { sink.success(mapOf("type" to "log", "line" to line)) }
    }

    /**
     * status: "preparing" | "starting" | "running" 表示对应阶段；null 表示已停止。
     */
    private fun emitState(status: String?, id: String?, name: String?, exitCode: Int?) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(stateMap(status, id, name, exitCode)) }
    }

    private fun stateMap(
        status: String?,
        id: String?,
        name: String?,
        exitCode: Int?,
    ): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["type"] = "state"
        map["status"] = status  // null 表示已停止
        map["instanceId"] = id
        map["instanceName"] = name
        if (exitCode != null) map["exitCode"] = exitCode
        return map
    }

    /**
     * 叠加清单中的 env 到基础环境。
     * - ${RUNTIME_DIR} 替换为运行时根目录绝对路径
     * - PATH / LD_LIBRARY_PATH 采用追加而非覆盖
     * - EC_* / LD_PRELOAD / TMPDIR 不允许被包覆盖
     */
    private fun applyManifestEnv(
        env: HashMap<String, String>,
        manifest: EcManifest,
        runtimeDir: File,
    ) {
        for ((key, rawValue) in manifest.env) {
            // App 内部加载器变量不可被包覆盖
            if (key.startsWith("EC_") || key == "LD_PRELOAD" || key == "TMPDIR") continue
            val value = rawValue.replace("\${RUNTIME_DIR}", runtimeDir.absolutePath)
            when (key) {
                "PATH" -> {
                    val existing = env["PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                "LD_LIBRARY_PATH" -> {
                    val existing = env["LD_LIBRARY_PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                else -> env[key] = value
            }
        }
    }
}
