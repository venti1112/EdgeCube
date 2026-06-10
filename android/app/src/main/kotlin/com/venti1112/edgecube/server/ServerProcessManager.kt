package com.venti1112.edgecube.server

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * 用 ProcessBuilder 把服务端 JVM 作为独立子进程拉起，并管理其生命周期。应用级单例，
 * 不绑定 Activity——这样 Activity 因切后台被销毁重建时，进程与日志仍在。
 *
 * 关键点：
 *  - 执行 nativeLibraryDir 下的 liblaunch.so（lib 目录是 Android 允许执行 ELF 的特例），
 *    由它 dlopen 数据目录里的 libjli.so 启动 JVM，绕开 API 29+ 对 data 目录 execve 的限制。
 *  - 进程级隔离：服务端崩溃不影响应用；可独立 kill。
 *  - 启动时拉起前台 [ServerService] 保活，退出时撤下。
 *  - 维护日志环形缓冲；界面（重新）连接事件流时回放历史日志与当前状态。
 */
class ServerProcessManager private constructor(private val appContext: Context) {

    companion object {
        private const val MAX_LOG_LINES = 2000

        @Volatile
        private var instance: ServerProcessManager? = null

        fun getInstance(context: Context): ServerProcessManager =
            instance ?: synchronized(this) {
                instance ?: ServerProcessManager(context.applicationContext).also { instance = it }
            }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val logLock = Any()
    private val logBuffer = ArrayDeque<String>()

    @Volatile private var process: Process? = null
    @Volatile private var stdin: OutputStream? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var runningInstanceId: String? = null
    @Volatile private var runningInstanceName: String? = null

    val isRunning: Boolean get() = process?.isAlive == true
    val activeInstanceId: String? get() = runningInstanceId

    /**
     * 设置/解除事件接收端。设置时回放历史日志与当前状态，使重建的界面能恢复（含正在运行的实例）。
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) return
        val snapshot = synchronized(logLock) { logBuffer.toList() }
        val running = isRunning
        val id = runningInstanceId
        val name = runningInstanceName
        mainHandler.post {
            for (line in snapshot) {
                sink.success(mapOf("type" to "log", "line" to line))
            }
            sink.success(stateMap(running, id, name, null))
        }
    }

    /**
     * 启动服务端。含首次 JRE 解压，耗时，必须在后台线程调用。
     */
    @Synchronized
    fun start(
        instanceId: String,
        instanceName: String,
        workingDir: String,
        version: String,
        jvmArgs: List<String>,
        programArgs: List<String>,
    ) {
        if (isRunning) throw IllegalStateException("已有服务端正在运行，请先停止")

        if (!RuntimeInstaller.isInstalled(appContext, version)) {
            emitLog("[EdgeCube] 正在解压 $version 运行时，请稍候…")
            RuntimeInstaller.install(appContext, version)
            emitLog("[EdgeCube] $version 运行时就绪")
        }

        val jreDir = RuntimeInstaller.jreDir(appContext, version)
        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        val resolved = JreLayout.resolve(jreDir, nativeDir)
        val launchBin = File(nativeDir, "liblaunch.so")
        if (!launchBin.exists()) {
            throw IllegalStateException("未找到 liblaunch.so，请确认其已随 APK 打包到 lib 目录")
        }
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        val cmd = ArrayList<String>()
        cmd.add(launchBin.absolutePath)
        // JVM 崩溃时将 hs_err 输出到 stderr，父进程能收到
        cmd.add("-XX:ErrorFile=/proc/self/fd/2")
        cmd.addAll(jvmArgs)
        cmd.addAll(programArgs)

        val pb = ProcessBuilder(cmd)
        pb.directory(work)
        pb.redirectErrorStream(true) // stderr 合并进 stdout，统一一条日志流
        val env = pb.environment()
        env["JAVA_HOME"] = jreDir.absolutePath
        env["EC_LIBJLI"] = resolved.libjli.absolutePath
        env["LD_LIBRARY_PATH"] = resolved.ldLibraryPath
        env["HOME"] = workingDir
        env["TMPDIR"] = appContext.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        // FCL/Pojav 修改过的 JRE 需通过这些变量定位 app 的原生库目录
        env["FCL_NATIVEDIR"] = nativeDir
        env["POJAV_NATIVEDIR"] = nativeDir
        // 把 JRE bin 加入 PATH，供 JVM 内部查找工具
        env["PATH"] = "${jreDir.absolutePath}/bin:${System.getenv("PATH") ?: ""}"

        val p = pb.start()
        process = p
        stdin = p.outputStream
        runningInstanceId = instanceId
        runningInstanceName = instanceName
        emitState(true, instanceId, instanceName, null)

        // 拉起前台 Service 保活。
        ServerService.start(appContext, instanceName)

        thread(name = "server-stdout-$instanceId") {
            try {
                BufferedReader(InputStreamReader(p.inputStream, StandardCharsets.UTF_8)).use { reader ->
                    var line = reader.readLine()
                    while (line != null) {
                        emitLog(line)
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
                    stdin = null
                    val id = runningInstanceId
                    val name = runningInstanceName
                    runningInstanceId = null
                    runningInstanceName = null
                    emitState(false, id, name, code)
                }
            }
            // 进程结束，撤下前台 Service。
            ServerService.stop(appContext)
        }
    }

    /** 向服务端 stdin 写入一行命令（自动补换行）。 */
    fun sendCommand(line: String) {
        val out = stdin ?: return
        try {
            out.write((line + "\n").toByteArray(StandardCharsets.UTF_8))
            out.flush()
        } catch (e: Exception) {
            emitLog("[EdgeCube] 发送命令失败：${e.message}")
        }
    }

    /** 优雅停止：向 Minecraft 服务端发送 stop 命令。 */
    fun stop() {
        sendCommand("stop")
    }

    /** 强制结束进程（SIGTERM）。 */
    fun forceStop() {
        process?.destroy()
    }

    /** 清空日志缓冲（与界面的清屏保持一致）。 */
    fun clearLog() {
        synchronized(logLock) { logBuffer.clear() }
    }

    private fun emitLog(line: String) {
        synchronized(logLock) {
            logBuffer.addLast(line)
            while (logBuffer.size > MAX_LOG_LINES) logBuffer.removeFirst()
        }
        val sink = eventSink ?: return
        mainHandler.post { sink.success(mapOf("type" to "log", "line" to line)) }
    }

    private fun emitState(running: Boolean, id: String?, name: String?, exitCode: Int?) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(stateMap(running, id, name, exitCode)) }
    }

    private fun stateMap(
        running: Boolean,
        id: String?,
        name: String?,
        exitCode: Int?,
    ): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["type"] = "state"
        map["running"] = running
        map["instanceId"] = id
        map["instanceName"] = name
        if (exitCode != null) map["exitCode"] = exitCode
        return map
    }
}
