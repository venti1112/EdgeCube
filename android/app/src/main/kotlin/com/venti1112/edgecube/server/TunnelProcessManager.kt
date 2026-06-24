package com.venti1112.edgecube.server

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * 用 ProcessBuilder 把 frpc（内网穿透客户端）作为独立子进程拉起，管理其生命周期。
 * 应用级单例，与管理 Minecraft 服务端的 [ServerProcessManager] 完全独立——两者各自
 * 持有自己的进程字段，可同时运行（服务端 + 隧道是常见组合）。
 *
 * 关键点：
 *  - 执行 nativeLibraryDir 下的 libfrpcloader.so（lib 目录是 Android 允许执行 ELF
 *    的特例），由它 dlopen 数据目录里的 libfrpc.so（Go c-shared），绕开 API 29+ 对
 *    data 目录 execve 的限制。引擎本体在 data 目录，可独立于 APK 热更。
 *  - 优雅停止：stop() 调 Process.destroy() 发 SIGTERM，libfrpc.so 内部已监听该信号
 *    并执行 GracefulClose；forceStop() 调 destroyForcibly() 发 SIGKILL。
 *  - 配置热更：开启 frpc 的 webServer 后，reload() 调用 Admin API GET /api/reload，
 *    无需重启进程即可应用新配置。
 *
 * 前台保活：本管理器不自行拉起前台 Service。前台 Service 提升的是宿主 app 进程优先级，
 * 覆盖其全部子进程；当 Minecraft 服务端在运行时（[ServerService] 已前台化），隧道子进程
 * 同样受保护。若需"仅隧道"长期后台保活，后续可为前台 Service 引入引用计数。
 */
class TunnelProcessManager private constructor(private val appContext: Context) {

    companion object {
        private const val MAX_LOG_LINES = 2000

        const val STATUS_PREPARING = "preparing"
        const val STATUS_STARTING = "starting"
        const val STATUS_RUNNING = "running"

        /** frpc 主连接建立成功的标志日志，匹配后切换到"运行中"。 */
        private val DONE_PATTERN = Regex("""login to server success""")

        /** 日志中的 ANSI 转义序列（CSI，如颜色码）；缓存/显示前剔除。 */
        private val ANSI_PATTERN = Regex("\\x1B\\[[0-?]*[ -/]*[@-~]")

        @Volatile
        private var instance: TunnelProcessManager? = null

        fun getInstance(context: Context): TunnelProcessManager =
            instance ?: synchronized(this) {
                instance ?: TunnelProcessManager(context.applicationContext).also { instance = it }
            }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val logLock = Any()
    private val logBuffer = ArrayDeque<String>()

    @Volatile private var process: Process? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var runningName: String? = null
    @Volatile private var currentStatus: String? = null

    val isRunning: Boolean get() = process?.isAlive == true

    /** 子进程 PID；未运行时返回 -1。 */
    val pid: Int get() {
        val p = process ?: return -1
        return try {
            val field = p.javaClass.getDeclaredField("pid")
            field.isAccessible = true
            field.getInt(p)
        } catch (_: Exception) {
            -1
        }
    }

    /**
     * 设置/解除事件接收端。设置时回放历史日志与当前状态，使重建的界面能恢复。
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) return
        val snapshot = synchronized(logLock) { logBuffer.toList() }
        val status = currentStatus
        val name = runningName
        mainHandler.post {
            for (line in snapshot) {
                sink.success(mapOf("type" to "log", "line" to line))
            }
            sink.success(stateMap(status, name, null))
        }
    }

    /**
     * 启动 frpc。含首次运行时解压引擎，耗时，必须在后台线程调用。
     *
     * @param configPath frpc 配置文件（toml/yaml/json）的绝对路径。
     * @param name       隧道显示名（用于事件回传与通知）。
     * @param runtimeId  指定使用的 frpc 运行时 id；null 或空时自动选取首个已安装 frpc。
     */
    @Synchronized
    fun start(configPath: String, name: String, runtimeId: String? = null) {
        if (isRunning) throw IllegalStateException("隧道已在运行，请先停止")

        val cfg = File(configPath)
        if (!cfg.isFile) throw IllegalStateException("配置文件不存在：$configPath")

        val manifest = when {
            !runtimeId.isNullOrEmpty() -> RuntimeInstaller.installedRuntime(appContext, runtimeId)
                ?: throw IllegalStateException("frpc 运行时未安装：$runtimeId")
            else -> RuntimeInstaller.installedFrpc(appContext)
                ?: throw IllegalStateException("frpc 运行时未安装，请先在「管理 → 运行环境」导入")
        }
        val runtimeDir = RuntimeInstaller.runtimeDir(appContext, manifest.id)
        val launcherLib = File(runtimeDir, manifest.launcher.lib)
        if (!launcherLib.exists()) {
            throw IllegalStateException("未找到 frpc 引擎库：${launcherLib.absolutePath}")
        }

        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        val loaderBin = File(nativeDir, "libfrpcloader.so")
        if (!loaderBin.exists()) {
            throw IllegalStateException("未找到 libfrpcloader.so，请确认其已随 APK 打包到 lib 目录")
        }

        // 工作目录用配置文件所在目录，使配置中的相对路径（store、日志文件等）有确定基准。
        val workDir = cfg.parentFile ?: appContext.filesDir

        val pb = ProcessBuilder(loaderBin.absolutePath, cfg.absolutePath)
        pb.directory(workDir)
        pb.redirectErrorStream(true) // stderr 合并进 stdout，统一一条日志流
        val env = pb.environment()
        env["EC_FRPC_LIB"] = launcherLib.absolutePath
        env["LD_LIBRARY_PATH"] = "${launcherLib.parentFile?.absolutePath}:$nativeDir"
        env["HOME"] = workDir.absolutePath
        env["TMPDIR"] = appContext.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        // 叠加清单中的 env
        applyManifestEnv(env, manifest, runtimeDir)

        val p = pb.start()
        process = p
        runningName = name
        currentStatus = STATUS_STARTING
        emitState(STATUS_STARTING, name, null)

        thread(name = "frpc-stdout") {
            try {
                BufferedReader(InputStreamReader(p.inputStream, StandardCharsets.UTF_8)).use { reader ->
                    var line = reader.readLine()
                    while (line != null) {
                        val clean = ANSI_PATTERN.replace(line, "")
                        emitLog(clean)
                        if (currentStatus == STATUS_STARTING && DONE_PATTERN.containsMatchIn(clean)) {
                            currentStatus = STATUS_RUNNING
                            emitState(STATUS_RUNNING, runningName, null)
                        }
                        line = reader.readLine()
                    }
                }
            } catch (e: Exception) {
                emitLog("[EdgeCube] 读取输出失败：${e.message}")
            }
            val code = try {
                p.waitFor()
            } catch (e: InterruptedException) {
                -1
            }
            synchronized(this) {
                if (process === p) {
                    process = null
                    val name2 = runningName
                    runningName = null
                    currentStatus = null
                    emitState(null, name2, code)
                }
            }
        }
    }

    /**
     * 叠加清单中的 env 到基础环境。
     * - ${RUNTIME_DIR} 替换为运行时根目录绝对路径
     * - PATH / LD_LIBRARY_PATH 采用追加而非覆盖
     * - EC_* / LD_PRELOAD / TMPDIR 不允许被包覆盖
     */
    private fun applyManifestEnv(
        env: MutableMap<String, String>,
        manifest: EcManifest,
        runtimeDir: File,
    ) {
        for ((key, rawValue) in manifest.env) {
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

    /** 优雅停止：发送 SIGTERM，触发 frpc 的 GracefulClose。 */
    fun stop() {
        process?.destroy()
    }

    /** 强制结束进程：发送 SIGKILL。 */
    fun forceStop() {
        process?.destroyForcibly()
    }

    /** 清空日志缓冲（与界面清屏保持一致）。 */
    fun clearLog() {
        synchronized(logLock) { logBuffer.clear() }
    }

    /**
     * 通过 frpc 的 Admin API 热重载配置（需在配置里开启 webServer）。无需重启进程即可
     * 应用新的代理/访问者配置。必须在后台线程调用（涉及网络）。
     *
     * @return 重载是否成功（HTTP 200）。
     */
    fun reload(port: Int, user: String?, password: String?): Boolean {
        val url = URL("http://127.0.0.1:$port/api/reload")
        val conn = url.openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "GET"
            conn.connectTimeout = 3000
            conn.readTimeout = 5000
            if (!user.isNullOrEmpty() || !password.isNullOrEmpty()) {
                val raw = "${user ?: ""}:${password ?: ""}"
                val token = Base64.encodeToString(raw.toByteArray(StandardCharsets.UTF_8), Base64.NO_WRAP)
                conn.setRequestProperty("Authorization", "Basic $token")
            }
            val code = conn.responseCode
            if (code == 200) {
                emitLog("[EdgeCube] 配置已热重载")
                true
            } else {
                emitLog("[EdgeCube] 热重载失败：HTTP $code")
                false
            }
        } catch (e: Exception) {
            emitLog("[EdgeCube] 热重载请求失败：${e.message}")
            false
        } finally {
            conn.disconnect()
        }
    }

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
    private fun emitState(status: String?, name: String?, exitCode: Int?) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(stateMap(status, name, exitCode)) }
    }

    private fun stateMap(status: String?, name: String?, exitCode: Int?): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["type"] = "state"
        map["status"] = status // null 表示已停止
        map["name"] = name
        if (exitCode != null) map["exitCode"] = exitCode
        return map
    }
}
