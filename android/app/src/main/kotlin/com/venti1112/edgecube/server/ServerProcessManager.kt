package com.venti1112.edgecube.server

import android.content.Context
import android.os.Environment
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

        /**
         * PHP CLI 内置 php.ini 内容（与 PMMP 官方构建产物的 php.ini 一致）。
         * 首次启动 PHP 时写入 filesDir/php/php.ini，通过 PHPRC 环境变量指定路径。
         * PHP CLI 随 APK 静态打包，--with-config-file-path 指向的构建机器路径在
         * 运行时不存在，故必须用 PHPRC 显式指定。
         */
        private const val DEFAULT_PHP_INI = """memory_limit=1024M
date.timezone=UTC
short_open_tag=0
asp_tags=0
phar.require_hash=1
igbinary.compact_strings=0
zend.assertions=-1
error_reporting=-1
display_errors=1
display_startup_errors=1
recursionguard.enabled=0"""

        const val STATUS_PREPARING = "preparing"
        const val STATUS_STARTING  = "starting"
        const val STATUS_RUNNING   = "running"

        // —— PTY 初始窗口尺寸；界面布局完成后会通过 resize() 校正为真实值。 ——
        private const val DEFAULT_ROWS = 24
        private const val DEFAULT_COLS = 80
        private const val DEFAULT_CELL_W = 8
        private const val DEFAULT_CELL_H = 16

        /** 服务端初始化完成标志：匹配
         *  - 英文 "Done (Xs)!"（Velocity/Paper）
         *  - 中文 "启动完成 (Xs)"（Paper 中文）
         *  - 中文 "加载完成 (X 秒)！"（PocketMine-MP）
         *  - "Network interface started at <ip>:<port> [(... )] (<ms> ms)"（Allay，
         *    IPv4-only 与 IPv6 双栈两种变体的公共前缀与尾缀）。 */
        private val DONE_PATTERN =
            Regex("""Done\s*\([0-9.]+s\)!|启动完成\s*\([0-9.]+s\)|加载完成\s*\([0-9.]+\s*秒\)！?|Network interface started at .+\([0-9]+\s*ms\)""")

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
    /** 当前启动是否为 proot 模式（顶层进程是 proot，实际服务端在其子进程中）。 */
    @Volatile private var runningIsProot: Boolean = false

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

    /** 当前启动是否为 proot 模式（顶层进程是 proot，服务端在其子进程中）。 */
    val isProotLaunch: Boolean get() = running && runningIsProot

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
     *  - php ：直接 exec 随 APK 打包的 libphp-cli.so（PMMP 官方 musl 静态链接 PHP CLI）。
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
        directExecute: Boolean = false,
    ) {
        if (isRunning) throw IllegalStateException("已有服务端正在运行，请先停止")

        // 重置上一次运行的 proot 标记（防止误读旧值）
        runningIsProot = false

        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        // 清理 PMMP 留下的过期 server.lock：Android 外部存储（/storage/emulated/0，
        // FUSE/sdcardfs）对 flock() 的支持不完整，进程崩溃后排他锁可能不被释放，
        // 导致下次启动时 PMMP 误判"另一个实例正在运行"。启动前删除锁文件，
        // 让 PMMP 重新创建。此清理同样适用于 JRE 服务器（同样用 server.lock）。
        File(work, "server.lock").let { lock ->
            if (lock.exists()) lock.delete()
        }

        // 清理 PMMP 的 phar 解压缓存目录：PMMP 的 server-phar-stub.php 在
        // sys_get_temp_dir()（= appContext.cacheDir）下创建
        // PocketMine-MP-phar-cache.N 目录存放解压后的 phar。FUSE 文件系统上
        // is_dir() 可能因缓存延迟返回错误结果，导致 stub 的 mkdir 容错判断失败
        // （mkdir 返回 false && is_dir 返回 false → 抛 RuntimeException）。
        // 启动前清空这些缓存目录，让 PMMP 干净创建。
        if (runtime == "php") {
            val cacheDir = appContext.cacheDir
            cacheDir.listFiles { f -> f.name.startsWith("PocketMine-MP-phar-cache.") }
                ?.forEach { dir ->
                    if (dir.isDirectory) {
                        dir.listFiles()?.forEach { it.delete() }
                        dir.delete()
                    } else {
                        dir.delete()
                    }
                }
        }

        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        // LD_PRELOAD 标签修复库：拦截 malloc/free 恢复指针标签再释放，解决 Android 15+ MTE 崩溃
        val tagfixLib = "$nativeDir/libtagfix.so"

        // 子进程会 clearenv 后重建环境，故须传入「继承自本进程的环境 + 覆盖项」的完整集合。
        val env = HashMap(System.getenv())
        val cmd: String
        val argv = ArrayList<String>()

        if (runtime == "php") {
            // PHP CLI 随 APK 静态打包到 lib/<abi>/libphp-cli.so（PMMP 官方 musl 静态
            // 链接构建，自包含 musl libc，不依赖 Bionic 与任何外部 .so）。
            // 直接 exec 即可：PHP_BINARY / proc_open / cli_set_process_title / php://stderr
            // 等在 CLI SAPI 下均原生可用。
            val phpBin = File(nativeDir, "libphp-cli.so")
            if (!phpBin.exists()) {
                throw IllegalStateException("未找到 libphp-cli.so，请确认其已随 APK 打包到 lib 目录")
            }

            // php.ini：首次启动写入 filesDir/php/php.ini。PHP CLI 的
            // --with-config-file-path 指向构建机器路径（运行时不存在），须用 PHPRC
            // 显式指定。ConsoleReaderChildProcessDaemon 用 proc_open([PHP_BINARY, '-r', ...])
            // fork 子进程时会继承 PHPRC，确保子进程也用同一 php.ini。
            val phpIniDir = File(appContext.filesDir, "php")
            phpIniDir.mkdirs()
            val phpIni = File(phpIniDir, "php.ini")
            if (!phpIni.exists()) {
                phpIni.writeText(DEFAULT_PHP_INI)
            }

            // DNS：PMMP 的 musl libc patch（sdcard-resolv-conf.diff）把 resolv.conf
            // 路径从 /etc/resolv.conf 改到 /sdcard/resolv.conf（Android /etc 不可写）。
            // curl 用 --enable-threaded-resolver（系统 getaddrinfo 在独立线程），不走
            // c-ares，故同样受 musl patch 影响。启动前把当前 DNS 服务器写入
            // /sdcard/resolv.conf，让 PHP 的所有网络解析都能找到 DNS。
            writeResolvConf()

            cmd = phpBin.absolutePath
            argv.add(phpBin.absolutePath)
            argv.addAll(programArgs) // 即 [phar, --no-wizard]

            env["PHPRC"] = phpIniDir.absolutePath
            env["HOME"] = workingDir
            env["TMPDIR"] = appContext.cacheDir.absolutePath
            env["LANG"] = "en_US.UTF-8"
            env["TERM"] = "xterm-256color"
            // PHP 是 musl 静态链接，不依赖 Bionic，故不需要 LD_PRELOAD=libtagfix.so
            // （MTE 标签问题不存在），也不需要 LD_LIBRARY_PATH。
        } else if (runtime == "proot") {
            // proot：在用户导入的 Linux rootfs 内运行服务端。
            runningIsProot = true
            // runtimeId 此处为 rootfs id（如 "debian-12-jdk21"）。
            // 根据 rootfs 内嵌清单（edgecube-rootfs.json）决定启动方式：
            //  - 带元数据且 envMainBin 非空：按清单声明的 envType/envArgs 启动主程序
            //    （java/php/node/python…），jvmArgs 作为运行时参数追加，programArgs
            //    作为程序参数追加（如 server.jar nogui）。
            //  - 无清单或 envType=generic（纯容器）：programArgs 拼接为完整启动命令，
            //    由 buildGenericCommand 用 sh -c 包裹执行，支持 shell 语法。
            // proot 进程不继承 Android 系统环境变量（ANDROID_DATA/BOOTCLASSPATH 等
            // 会泄漏进容器造成干扰），改用 ProotEnvironment 返回的干净环境。
            val rootfs = ProotEnvironment.installedRootfs(appContext, runtimeId)
                ?: throw IllegalStateException("proot rootfs '$runtimeId' 未安装，请先在「管理 → 运行环境」导入 rootfs.tar.zst")
            // directExecute=true 时（如 Survivalcraft 直接运行容器内二进制），
            // 无论 rootfs 是否带元数据都走 buildGenericCommand（sh -c 包裹执行）。
            val prootCmd = if (rootfs.isGeneric || directExecute) {
                // 纯容器或直接执行模式：programArgs 各元素以空格拼接为完整命令行
                // （如 ["/opt/{id}/Survivalcraft"] 或 ["/usr/bin/python3", "main.py"]）。
                val command = programArgs.joinToString(" ").trim()
                ProotEnvironment.buildGenericCommand(
                    appContext,
                    runtimeId,
                    workingDir,
                    command,
                )
            } else {
                ProotEnvironment.buildServerCommand(
                    appContext,
                    runtimeId,
                    workingDir,
                    jvmArgs,
                    programArgs,
                )
            }
            cmd = prootCmd.cmd
            argv.addAll(prootCmd.argv)
            env.clear()
            env.putAll(prootCmd.env)
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
            // 用户自定义 DNS：Android 无 /etc/resolv.conf，JVM 默认 DNS 解析可能
            // 失败或使用系统 DNS。通过该属性显式注入用户配置的 DNS 服务器列表。
            val dnsServers = ProotEnvironment.loadCustomDnsServers(appContext)
            if (dnsServers.isNotEmpty()) {
                argv.add("-Dsun.net.spi.nameserver.nameservers=${dnsServers.joinToString(",")}")
            }
            argv.addAll(expandArgfiles(jvmArgs, workingDir))
            argv.addAll(expandArgfiles(programArgs, workingDir))

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
                    runningIsProot = false
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

    /** 强制结束进程。 */
    fun forceStop() {
        val p = processId
        if (p <= 0) return
        try {
            if (runningIsProot) {
                // proot 模式：顶层 proot 进程不向子孙传播信号，且其子进程
                //（sh / 容器内二进制）会变孤儿继续运行、占用端口。PTY 子进程
                // 已 setsid 成为新进程组首（PGID = pid），杀整个进程组才能连子进程
                // 一起清理。用 SIGKILL 确保彻底结束（SIGTERM 可能被忽略或不传播）。
                Os.kill(-p, OsConstants.SIGKILL)
            } else {
                // 普通模式：SIGTERM，与原 Process.destroy() 语义一致，给进程清理机会。
                Os.kill(p, OsConstants.SIGTERM)
            }
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
     * 展开 JVM @argfile 引用。
     *
     * 标准 Java 启动器（bin/java）的 main() 会在调用 JLI_Launch 之前展开 @argfile
     * 参数。EdgeCube 通过 liblaunch.so 直接调用 JLI_Launch，绕过了该展开步骤，
     * 导致 JVM 将 @路径 当作主类名处理而报 ClassNotFoundException。
     *
     * 该函数在构建 argv 前读取 @argfile 的内容，将每一行（跳过 # 注释与空行）
     * 展开为独立的 JVM 参数。argfile 中的嵌套 @ 引用（如 @user_jvm_args.txt）
     * 也递归展开。
     *
     * @param args  原始参数列表（可能含 @argfile 引用）
     * @param workDir  工作目录（argfile 相对路径的基准）
     */
    private fun expandArgfiles(args: List<String>, workDir: String): List<String> {
        val result = mutableListOf<String>()
        val seen = mutableSetOf<String>()  // 防循环引用
        for (arg in args) {
            if (arg.startsWith("@")) {
                val file = File(workDir, arg.substring(1))
                if (file.isFile) {
                    expandArgfile(file, workDir, result, seen)
                } else {
                    result.add(arg)
                }
            } else {
                result.add(arg)
            }
        }
        return result
    }

    /**
     * 递归展开单个 argfile。
     *
     * 每行可包含多个以空白符分隔的参数（JVM @argfile 规范允许在一行中放置
     * 多个参数）。跳过 # 开头的注释行与空行。嵌套 @ 引用按 JVM 规范以 CWD
     * 为基准解析路径。
     */
    private fun expandArgfile(
        file: File,
        workDir: String,
        result: MutableList<String>,
        seen: MutableSet<String>,
    ) {
        val canonical = file.canonicalPath
        if (!seen.add(canonical)) return  // 已展开过，防循环
        try {
            val tokens = mutableListOf<String>()
            for (rawLine in file.readLines()) {
                val trimmed = rawLine.trim()
                if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
                // JVM argfile 允许一行内多个空白分隔的参数，逐 token 展开
                tokens.addAll(trimmed.split(Regex("\\s+")))
            }
            for (token in tokens) {
                if (token.startsWith("@")) {
                    val nestedPath = token.substring(1)
                    val nestedFile = File(nestedPath).let {
                        if (it.isAbsolute) it else File(workDir, nestedPath)
                    }
                    if (nestedFile.isFile) {
                        expandArgfile(nestedFile, workDir, result, seen)
                    }
                } else {
                    result.add(token)
                }
            }
        } catch (_: Exception) {
            // 文件不可读时直接跳过
        }
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

    /**
     * 把用户配置的 DNS 服务器写入 /sdcard/resolv.conf。
     *
     * PMMP 的 musl libc patch（sdcard-resolv-conf.diff）把 resolv.conf 路径从
     * /etc/resolv.conf 改到 /sdcard/resolv.conf（Android /etc 不可写）。PHP 静态
     * 链接 musl，所有 getaddrinfo 调用都从该路径读取 DNS 服务器。Android 不维护
     * 这个文件，故须在启动 PHP 前主动写入用户配置的 DNS。
     *
     * DNS 来源：用户在「网络设置」中配置的自定义 DNS（默认 8.8.8.8,1.1.1.1），
     * 通过 [ProotEnvironment.loadCustomDnsServers] 从 config/network.json 读取。
     */
    private fun writeResolvConf() {
        val dnsServers = ProotEnvironment.loadCustomDnsServers(appContext)
        val sb = StringBuilder()
        sb.append("# Generated by EdgeCube for PocketMine-MP (musl libc resolv.conf)\n")
        for (dns in dnsServers) {
            sb.append("nameserver ").append(dns).append('\n')
        }
        val content = sb.toString()

        // /sdcard 是 /storage/emulated/0 的符号链接，需 MANAGE_EXTERNAL_STORAGE 权限。
        // 写到临时文件再重命名，避免 PHP 在写入过程中读到半截内容。
        val resolvFile = File(Environment.getExternalStorageDirectory(), "resolv.conf")
        val tmpFile = File(resolvFile.parentFile, "resolv.conf.tmp")
        try {
            tmpFile.writeText(content)
            tmpFile.renameTo(resolvFile)
        } catch (e: Exception) {
            // 即使写失败也不阻断启动——PHP 启动后仍可访问 IP 直连的服务。
            emitNotice("[EdgeCube] 写入 resolv.conf 失败：${e.message}，DNS 解析可能不可用")
        }
    }
}
