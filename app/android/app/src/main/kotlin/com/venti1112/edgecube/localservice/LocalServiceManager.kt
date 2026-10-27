package com.venti1112.edgecube.localservice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.Executors

/**
 * 本地服务（proot 里的 daemon）的生命周期管理器。
 *
 * 单例、进程级：Activity 重建、Flutter 引擎重启都不影响已启动的 daemon；
 * 所有耗时步骤（解压 rootfs、等待就绪、停止）都在单线程后台队列里串行执行，
 * UI 只通过 EventChannel 收状态与日志。
 *
 * 状态机：
 * ```
 * stopped → preparing → starting → running → stopping → stopped
 *              └────────── failed ←──────────┘
 * ```
 */
class LocalServiceManager private constructor(private val appContext: Context) {

    companion object {
        const val STATE_STOPPED = "stopped"
        const val STATE_PREPARING = "preparing"
        const val STATE_STARTING = "starting"
        const val STATE_RUNNING = "running"
        const val STATE_STOPPING = "stopping"
        const val STATE_FAILED = "failed"

        private const val MAX_LOG_LINES = 2000
        private const val READY_TIMEOUT_MS = 60_000L
        private const val STOP_TIMEOUT_MS = 12_000L

        private val ANSI = Regex("\\x1B\\[[0-?]*[ -/]*[@-~]")

        @Volatile
        private var instance: LocalServiceManager? = null

        fun getInstance(context: Context): LocalServiceManager =
            instance ?: synchronized(this) {
                instance ?: LocalServiceManager(context.applicationContext).also { instance = it }
            }

        /** 当前设备/安装包是否具备本地服务能力（目前仅 arm64 + 打包了 proot）。 */
        fun isSupported(context: Context): Boolean {
            if (!android.os.Build.SUPPORTED_ABIS.contains("arm64-v8a")) return false
            val proot = File(
                context.applicationInfo.nativeLibraryDir,
                "lib__bin__proot-classic__.so",
            )
            return proot.isFile
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "edgecube-local-service").apply { isDaemon = true }
    }

    private val logLock = Any()
    private val logs = ArrayDeque<String>()

    @Volatile private var state: String = STATE_STOPPED
    @Volatile private var message: String? = null
    @Volatile private var host: String? = null
    @Volatile private var port: Int? = null
    @Volatile private var wsPath: String? = null
    @Volatile private var token: String? = null
    @Volatile private var daemonPid: Int? = null
    @Volatile private var daemonVersion: String? = null

    @Volatile private var process: Process? = null
    @Volatile private var stopRequested = false
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var rootfsPrepared = false
    @Volatile private var rootfsVersion: String? = null

    private class Cancelled : Exception()

    init {
        // 状态查询要能在主线程立刻返回，环境检查放到后台做一次
        worker.execute { refreshPreparedState() }
    }

    // ──────────────────────────────────────────────────────────────────
    // 对外：状态 / 启停 / 日志
    // ──────────────────────────────────────────────────────────────────

    fun status(): Map<String, Any?> {
        return mapOf(
            "state" to state,
            "message" to message,
            "host" to host,
            "port" to port,
            "wsPath" to wsPath,
            "token" to token,
            "pid" to daemonPid,
            "version" to daemonVersion,
            "prepared" to rootfsPrepared,
            "rootfsVersion" to rootfsVersion,
        )
    }

    fun logsSnapshot(): List<String> = synchronized(logLock) { logs.toList() }

    fun clearLogs() {
        synchronized(logLock) { logs.clear() }
        try {
            LocalServicePaths.logFile(appContext).delete()
        } catch (_: Throwable) {
        }
    }

    /** 设置/解除事件接收端；挂上时回放当前状态与日志。 */
    @Synchronized
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) return
        val snapshot = logsSnapshot()
        val current = status()
        mainHandler.post {
            sink.success(mapOf("type" to "status") + current)
            for (line in snapshot) {
                sink.success(mapOf("type" to "log", "line" to line))
            }
        }
    }

    fun start() {
        synchronized(this) {
            if (state == STATE_PREPARING || state == STATE_STARTING ||
                state == STATE_RUNNING || state == STATE_STOPPING
            ) {
                emitStatus()
                return
            }
            stopRequested = false
            state = STATE_PREPARING
            message = "正在检查本地环境…"
            emitStatus()
        }
        LocalServiceService.start(appContext)
        worker.execute { doStart() }
    }

    fun stop() {
        synchronized(this) {
            if (state == STATE_STOPPED) {
                emitStatus()
                return
            }
            stopRequested = true
            if (state != STATE_STOPPING) {
                state = STATE_STOPPING
                message = "正在停止本地服务…"
                emitStatus()
            }
        }
        worker.execute { doStop() }
    }

    // ──────────────────────────────────────────────────────────────────
    // 启动
    // ──────────────────────────────────────────────────────────────────

    private fun doStart() {
        try {
            if (stopRequested) throw Cancelled()
            appendLog("[EdgeCube] 检查本地环境…")
            ProotBootstrap.ensureBootstrap(appContext)

            val rootfs = BundledRootfs.ensureInstalled(
                appContext,
                onMessage = { text -> setPreparingMessage(text) },
                onLog = ::appendLog,
            )
            rootfsPrepared = true
            if (stopRequested) throw Cancelled()

            updateState(STATE_STARTING, "正在启动本地服务…")
            appendLog("[EdgeCube] 启动本地 daemon…")

            val token = randomToken()
            val readyFile = LocalServicePaths.readyFile(appContext)
            readyFile.delete()
            LocalServicePaths.logFile(appContext).writeText("")

            val spec = ProotCommandBuilder.buildDaemonCommand(
                appContext,
                rootfs,
                token,
                android.os.Process.myPid(),
            )
            val builder = ProcessBuilder(spec.argv)
                .directory(File(spec.cwd))
                .redirectErrorStream(true)
            builder.environment().clear()
            builder.environment().putAll(spec.env)

            val proc = builder.start()
            process = proc
            try {
                proc.outputStream.close()
            } catch (_: Throwable) {
            }
            startLogPump(proc)

            val info = awaitReady(proc, readyFile)
            if (stopRequested) throw Cancelled()

            this.token = token
            host = "127.0.0.1"
            port = info.port
            wsPath = info.wsPath
            daemonPid = info.pid
            daemonVersion = info.version
            updateState(STATE_RUNNING, null)
            appendLog("[EdgeCube] 本地服务已启动：127.0.0.1:${info.port}")
            startExitWatcher(proc)
        } catch (_: Cancelled) {
            finishStopped()
        } catch (e: Throwable) {
            cleanupAfterFailure()
            val text = e.message?.takeIf { it.isNotBlank() } ?: "本地服务启动失败"
            appendLog("[EdgeCube] $text")
            updateState(STATE_FAILED, text)
            LocalServiceService.stop(appContext)
        }
    }

    private data class ReadyInfo(
        val port: Int,
        val wsPath: String,
        val pid: Int?,
        val version: String?,
    )

    /** 轮询就绪文件；daemon 提前退出或超时都算启动失败。 */
    private fun awaitReady(proc: Process, readyFile: File): ReadyInfo {
        val deadline = System.currentTimeMillis() + READY_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (stopRequested) throw Cancelled()
            exitCodeOrNull(proc)?.let { code ->
                throw IllegalStateException("本地服务启动失败（daemon 退出码 $code）")
            }
            val info = runCatching { readReady(readyFile) }.getOrNull()
            if (info != null) return info
            Thread.sleep(100)
        }
        throw IllegalStateException("等待本地服务就绪超时（${READY_TIMEOUT_MS / 1000}s）")
    }

    private fun readReady(file: File): ReadyInfo? {
        if (!file.isFile) return null
        val json = JSONObject(file.readText())
        val port = json.optInt("port", 0)
        val wsPath = json.optString("ws_path")
        if (port <= 0 || wsPath.isBlank()) return null
        return ReadyInfo(
            port = port,
            wsPath = wsPath,
            pid = json.optInt("pid", -1).takeIf { it > 0 },
            version = json.optString("version").takeIf { it.isNotBlank() },
        )
    }

    private fun startLogPump(proc: Process) {
        Thread({
            try {
                proc.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        appendLog(line)
                    }
                }
            } catch (_: Throwable) {
            }
        }, "edgecube-local-log").apply { isDaemon = true }.start()
    }

    /** 运行期进程退出：区分「用户停止」与「意外崩溃」。 */
    private fun startExitWatcher(proc: Process) {
        Thread({
            val code = try {
                proc.waitFor()
            } catch (_: Throwable) {
                -1
            }
            val wasStopping = stopRequested
            var crashed = false
            synchronized(this) {
                if (process === proc) process = null
                if (!wasStopping && (state == STATE_RUNNING || state == STATE_STARTING)) {
                    updateStateLocked(
                        STATE_FAILED,
                        "本地服务意外退出（退出码 $code）",
                    )
                    crashed = true
                }
            }
            if (crashed) emitStatus()
            appendLog("[EdgeCube] 本地 daemon 已退出（退出码 $code）")
            try {
                LocalServicePaths.readyFile(appContext).delete()
            } catch (_: Throwable) {
            }
            if (!wasStopping) LocalServiceService.stop(appContext)
        }, "edgecube-local-exit").apply { isDaemon = true }.start()
    }

    // ──────────────────────────────────────────────────────────────────
    // 停止
    // ──────────────────────────────────────────────────────────────────

    private fun doStop() {
        val proc = process
        if (proc != null) {
            appendLog("[EdgeCube] 正在停止本地服务…")
            try {
                proc.destroy()
            } catch (_: Throwable) {
            }
            if (!waitForExit(proc, STOP_TIMEOUT_MS)) {
                appendLog("[EdgeCube] 优雅停止超时，强制结束")
                killDaemon()
                killProot()
                waitForExit(proc, 3000)
            }
        }
        process = null
        LocalServicePaths.readyFile(appContext).delete()
        LocalServicePaths.prootPidFile(appContext).delete()
        finishStopped()
    }

    private fun finishStopped() {
        synchronized(this) {
            state = STATE_STOPPED
            message = null
            host = null
            port = null
            wsPath = null
            token = null
            daemonPid = null
            daemonVersion = null
        }
        emitStatus()
        LocalServiceService.stop(appContext)
    }

    private fun cleanupAfterFailure() {
        val proc = process
        process = null
        if (proc != null) {
            try {
                proc.destroy()
            } catch (_: Throwable) {
            }
            if (!waitForExit(proc, 3000)) {
                killDaemon()
                killProot()
            }
        }
        LocalServicePaths.readyFile(appContext).delete()
        LocalServicePaths.prootPidFile(appContext).delete()
    }

    /** 优先按就绪文件里的 daemon PID 精确结束（proot 是看护进程，未必转发 SIGKILL）。 */
    private fun killDaemon() {
        val pid = daemonPid ?: runCatching {
            JSONObject(LocalServicePaths.readyFile(appContext).readText()).optInt("pid", -1)
        }.getOrDefault(-1)
        if (pid > 0) killPid(pid)
    }

    private fun killProot() {
        val pid = runCatching {
            LocalServicePaths.prootPidFile(appContext).readText().trim().toInt()
        }.getOrDefault(-1)
        if (pid > 0) killPid(pid)
    }

    private fun killPid(pid: Int) {
        try {
            Os.kill(pid, OsConstants.SIGKILL)
        } catch (_: Throwable) {
        }
    }

    private fun waitForExit(proc: Process, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (exitCodeOrNull(proc) != null) return true
            Thread.sleep(100)
        }
        return exitCodeOrNull(proc) != null
    }

    private fun exitCodeOrNull(proc: Process): Int? = try {
        proc.exitValue()
    } catch (_: IllegalThreadStateException) {
        null
    }

    // ──────────────────────────────────────────────────────────────────
    // 状态 / 日志广播
    // ──────────────────────────────────────────────────────────────────

    private fun setPreparingMessage(text: String) {
        synchronized(this) {
            if (state == STATE_PREPARING) {
                message = text
            }
        }
        emitStatus()
    }

    private fun updateState(newState: String, newMessage: String?) {
        synchronized(this) { updateStateLocked(newState, newMessage) }
    }

    private fun updateStateLocked(newState: String, newMessage: String?) {
        state = newState
        message = newMessage
        if (newState == STATE_FAILED || newState == STATE_STOPPED) {
            host = null
            port = null
            wsPath = null
            token = null
            daemonPid = null
            daemonVersion = null
        }
    }

    private fun emitStatus() {
        val snapshot = status()
        mainHandler.post {
            eventSink?.success(mapOf("type" to "status") + snapshot)
        }
    }

    private fun appendLog(raw: String) {
        val line = ANSI.replace(raw.replace("\r", ""), "")
        if (line.isBlank()) return
        synchronized(logLock) {
            logs.addLast(line)
            while (logs.size > MAX_LOG_LINES) logs.removeFirst()
        }
        try {
            LocalServicePaths.logFile(appContext).appendText(line + "\n")
        } catch (_: Throwable) {
        }
        mainHandler.post {
            eventSink?.success(mapOf("type" to "log", "line" to line))
        }
    }

    private fun refreshPreparedState() {
        val info = runCatching { BundledRootfs.readInfo(appContext) }.getOrNull()
        rootfsVersion = info?.version
        rootfsPrepared = info != null && BundledRootfs.isPrepared(appContext)
    }

    private fun randomToken(): String {
        val bytes = ByteArray(16)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
