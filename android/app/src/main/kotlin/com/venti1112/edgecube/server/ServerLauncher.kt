package com.venti1112.edgecube.server

import android.content.Context
import android.os.Environment
import com.venti1112.edgecube.proot.ProotCommandBuilder
import com.venti1112.edgecube.proot.ProotDns
import com.venti1112.edgecube.proot.RootfsStore
import java.io.File

/**
 * 服务端启动命令构造：把「实例配置」翻译成可直接交给 [EcPty] 的
 * cmd/argv/env 三元组。按 [build] 的 runtime 参数分派：
 *
 *  - java ：执行 nativeLibraryDir 下的 liblaunch.so，由它 dlopen JRE 的
 *    libjli.so 启动 JVM。
 *  - php  ：直接 exec 随 APK 打包的 libphp-cli.so（PMMP 官方 musl 静态链接
 *    PHP CLI，自包含 musl libc，不依赖 Bionic 与任何外部 .so）。
 *  - proot：在用户导入的 Linux rootfs 内运行服务端（委托
 *    [ProotCommandBuilder] 构造 proot 命令）。
 *
 * 进程生命周期与 PTY I/O 由 [ServerProcessManager] 负责，此处只管命令构造与
 * 启动前的工作目录清理。
 */
object ServerLauncher {

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

    /** 一次启动的完整描述：可执行文件、argv、环境变量与 proot 标记。 */
    data class LaunchSpec(
        val cmd: String,
        val argv: List<String>,
        val env: Map<String, String>,
        /** 是否为 proot 模式（顶层进程是 proot，实际服务端在其子进程中）。 */
        val isProot: Boolean,
    ) {
        /** 转为 [EcPty.createSubprocess] 需要的 "KEY=VALUE" 数组。 */
        fun envp(): Array<String> = env.map { "${it.key}=${it.value}" }.toTypedArray()
    }

    /**
     * 启动前清理工作目录中上一次运行的残留。
     *
     * - server.lock：Android 外部存储（/storage/emulated/0，FUSE/sdcardfs）对
     *   flock() 的支持不完整，进程崩溃后排他锁可能不被释放，导致下次启动时
     *   PMMP 误判"另一个实例正在运行"。启动前删除锁文件，让 PMMP 重新创建。
     *   此清理同样适用于 JRE 服务器（同样用 server.lock）。
     * - PMMP 的 phar 解压缓存目录：PMMP 的 server-phar-stub.php 在
     *   sys_get_temp_dir()（= cacheDir）下创建 PocketMine-MP-phar-cache.N 目录
     *   存放解压后的 phar。FUSE 文件系统上 is_dir() 可能因缓存延迟返回错误结果，
     *   导致 stub 的 mkdir 容错判断失败（mkdir 返回 false && is_dir 返回 false
     *   → 抛 RuntimeException）。启动前清空这些缓存目录，让 PMMP 干净创建。
     */
    fun prepareWorkingDir(context: Context, work: File, runtime: String) {
        File(work, "server.lock").let { lock ->
            if (lock.exists()) lock.delete()
        }

        if (runtime == "php") {
            val cacheDir = context.cacheDir
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
    }

    /**
     * 构造启动命令。含运行时校验（未安装时抛 [IllegalStateException]），不产生副作用
     * （除写入 php.ini / resolv.conf 等启动必需的配置文件外）。
     *
     * @param onNotice 非致命告警回调（如 resolv.conf 写入失败），由调用方转发到终端/日志。
     */
    fun build(
        context: Context,
        workingDir: String,
        runtimeId: String,
        runtime: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
        directExecute: Boolean,
        onNotice: (String) -> Unit,
    ): LaunchSpec = when (runtime) {
        "php" -> buildPhpSpec(context, workingDir, programArgs, onNotice)
        "proot" -> buildProotSpec(
            context, workingDir, runtimeId, runtimeArgs, programArgs, directExecute,
        )
        else -> buildJreSpec(context, workingDir, runtimeId, runtimeArgs, programArgs)
    }

    // ──────────────────────────────────────────────────────
    // 三种运行时的命令构造
    // ──────────────────────────────────────────────────────

    /**
     * PHP CLI 随 APK 静态打包到 lib/<abi>/libphp-cli.so。直接 exec 即可：
     * PHP_BINARY / proc_open / cli_set_process_title / php://stderr 等在
     * CLI SAPI 下均原生可用。
     */
    private fun buildPhpSpec(
        context: Context,
        workingDir: String,
        programArgs: List<String>,
        onNotice: (String) -> Unit,
    ): LaunchSpec {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val phpBin = File(nativeDir, "libphp-cli.so")
        if (!phpBin.exists()) {
            throw IllegalStateException("未找到 libphp-cli.so，请确认其已随 APK 打包到 lib 目录")
        }

        // php.ini：首次启动写入 filesDir/php/php.ini。PHP CLI 的
        // --with-config-file-path 指向构建机器路径（运行时不存在），须用 PHPRC
        // 显式指定。ConsoleReaderChildProcessDaemon 用 proc_open([PHP_BINARY, '-r', ...])
        // fork 子进程时会继承 PHPRC，确保子进程也用同一 php.ini。
        val phpIniDir = File(context.filesDir, "php")
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
        writeResolvConf(context, onNotice)

        val argv = mutableListOf(phpBin.absolutePath)
        argv.addAll(programArgs) // 即 [phar, --no-wizard]

        // 子进程会 clearenv 后重建环境，故须传入「继承自本进程的环境 + 覆盖项」的完整集合。
        val env = HashMap(System.getenv())
        env["PHPRC"] = phpIniDir.absolutePath
        env["HOME"] = workingDir
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        env["TERM"] = "xterm-256color"
        // PHP 是 musl 静态链接，不依赖 Bionic，故不需要 LD_PRELOAD=libtagfix.so
        // （MTE 标签问题不存在），也不需要 LD_LIBRARY_PATH。
        return LaunchSpec(phpBin.absolutePath, argv, env, isProot = false)
    }

    /**
     * proot：在用户导入的 Linux rootfs 内运行服务端。runtimeId 此处为
     * rootfs id（如 "debian-12-jdk21"）。
     *
     * 根据 rootfs 内嵌清单（edgecube-rootfs.json）决定启动方式：
     *  - 带元数据且 envMainBin 非空：按清单声明的 envType/envArgs 启动主程序
     *    （java/php/node/python…），runtimeArgs 作为运行时参数追加，programArgs
     *    作为程序参数追加（如 server.jar nogui）。
     *  - 无清单或 envType=generic（纯容器）：programArgs 拼接为完整启动命令，
     *    由 buildGenericCommand 用 sh -c 包裹执行，支持 shell 语法。
     *
     * proot 进程不继承 Android 系统环境变量（ANDROID_DATA/BOOTCLASSPATH 等
     * 会泄漏进容器造成干扰），改用 proot 包返回的干净环境。
     */
    private fun buildProotSpec(
        context: Context,
        workingDir: String,
        runtimeId: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
        directExecute: Boolean,
    ): LaunchSpec {
        val rootfs = RootfsStore.installedRootfs(context, runtimeId)
            ?: throw IllegalStateException("proot rootfs '$runtimeId' 未安装，请先在「管理 → 运行环境」导入 rootfs.tar.zst")
        // directExecute=true 时（如 Survivalcraft 直接运行容器内二进制），
        // 无论 rootfs 是否带元数据都走 buildGenericCommand（sh -c 包裹执行）。
        val prootCmd = if (rootfs.isGeneric || directExecute) {
            // 纯容器或直接执行模式：programArgs 各元素以空格拼接为完整命令行
            // （如 ["/opt/{id}/Survivalcraft"] 或 ["/usr/bin/python3", "main.py"]）。
            val command = programArgs.joinToString(" ").trim()
            ProotCommandBuilder.buildGenericCommand(context, runtimeId, workingDir, command)
        } else {
            ProotCommandBuilder.buildServerCommand(
                context, runtimeId, workingDir, runtimeArgs, programArgs,
            )
        }
        return LaunchSpec(prootCmd.cmd, prootCmd.argv, prootCmd.env, isProot = true)
    }

    /**
     * JRE：执行 nativeLibraryDir 下的 liblaunch.so，由它 dlopen JRE 的
     * libjli.so 启动 JVM，绕开 Android SELinux 对 data 目录的 execve 限制。
     */
    private fun buildJreSpec(
        context: Context,
        workingDir: String,
        runtimeId: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
    ): LaunchSpec {
        val manifest = RuntimeInstaller.installedRuntime(context, runtimeId)
            ?: throw IllegalStateException("JRE 运行时 $runtimeId 未安装，请先在「管理 → 运行环境」导入")
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val runtimeDir = RuntimeInstaller.runtimeDir(context, runtimeId)
        val resolved = JreLayout.resolve(runtimeDir, nativeDir)
        val launchBin = File(nativeDir, "liblaunch.so")
        if (!launchBin.exists()) {
            throw IllegalStateException("未找到 liblaunch.so，请确认其已随 APK 打包到 lib 目录")
        }

        val argv = mutableListOf(launchBin.absolutePath)
        // JVM 崩溃时将 hs_err 输出到 stderr（PTY 从设备），父进程能收到
        argv.add("-XX:ErrorFile=/proc/self/fd/2")
        // Android 上 /tmp 不可写，全局指定可写的 tmpdir
        argv.add("-Djava.io.tmpdir=${context.cacheDir.absolutePath}")
        // 用户自定义 DNS：Android 无 /etc/resolv.conf，JVM 默认 DNS 解析可能
        // 失败或使用系统 DNS。通过该属性显式注入用户配置的 DNS 服务器列表。
        val dnsServers = ProotDns.loadCustomDnsServers(context)
        if (dnsServers.isNotEmpty()) {
            argv.add("-Dsun.net.spi.nameservice.nameservers=${dnsServers.joinToString(",")}")
        }
        argv.addAll(expandArgfiles(runtimeArgs, workingDir))
        argv.addAll(expandArgfiles(programArgs, workingDir))

        val env = HashMap(System.getenv())
        // LD_PRELOAD 标签修复库：拦截 malloc/free 恢复指针标签再释放，解决 Android 15+ MTE 崩溃
        env["LD_PRELOAD"] = "$nativeDir/libtagfix.so"
        env["JAVA_HOME"] = runtimeDir.absolutePath
        env["EC_LIBJLI"] = resolved.libjli.absolutePath
        env["LD_LIBRARY_PATH"] = resolved.ldLibraryPath
        env["HOME"] = workingDir
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        // JLine/终端能力依赖 TERM；给一个广泛支持的 256 色终端类型。
        env["TERM"] = "xterm-256color"
        // FCL/Pojav 修改过的 JRE 需通过这些变量定位 app 的原生库目录
        env["FCL_NATIVEDIR"] = nativeDir
        env["POJAV_NATIVEDIR"] = nativeDir
        // 叠加清单中的 env（${RUNTIME_DIR} 替换；PATH/LD_LIBRARY_PATH 追加）
        ManifestEnv.apply(env, manifest, runtimeDir)
        return LaunchSpec(launchBin.absolutePath, argv, env, isProot = false)
    }

    // ──────────────────────────────────────────────────────
    // 参数与配置辅助
    // ──────────────────────────────────────────────────────

    /**
     * 从 JVM 参数中解析 -Xmx 最大堆（MB）；无 -Xmx 或不可解析返回 -1。
     * 支持 K/M/G/T 单位后缀与无后缀（字节）写法，大小写不敏感。
     */
    fun parseXmxMb(args: List<String>): Long {
        // 取最后一个 -Xmx（JVM 语义：后者覆盖前者）。
        val raw = args.lastOrNull { it.startsWith("-Xmx") }
            ?.removePrefix("-Xmx")?.trim() ?: return -1
        if (raw.isEmpty()) return -1
        val unit = raw.last().lowercaseChar()
        val hasUnit = unit in charArrayOf('k', 'm', 'g', 't')
        val number = (if (hasUnit) raw.dropLast(1) else raw).toLongOrNull() ?: return -1
        if (number <= 0) return -1
        return when (unit) {
            'k' -> number / 1024
            'm' -> number
            'g' -> number * 1024
            't' -> number * 1024 * 1024
            else -> number / (1024 * 1024) // 无后缀：字节
        }
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
     * 把用户配置的 DNS 服务器写入 /sdcard/resolv.conf。
     *
     * PMMP 的 musl libc patch（sdcard-resolv-conf.diff）把 resolv.conf 路径从
     * /etc/resolv.conf 改到 /sdcard/resolv.conf（Android /etc 不可写）。PHP 静态
     * 链接 musl，所有 getaddrinfo 调用都从该路径读取 DNS 服务器。Android 不维护
     * 这个文件，故须在启动 PHP 前主动写入用户配置的 DNS。
     *
     * DNS 来源：用户在「网络设置」中配置的自定义 DNS（默认 8.8.8.8,1.1.1.1），
     * 通过 [ProotDns.loadCustomDnsServers] 从 config/network.json 读取。
     */
    private fun writeResolvConf(context: Context, onNotice: (String) -> Unit) {
        val dnsServers = ProotDns.loadCustomDnsServers(context)
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
            onNotice("[EdgeCube] 写入 resolv.conf 失败：${e.message}，DNS 解析可能不可用")
        }
    }
}
