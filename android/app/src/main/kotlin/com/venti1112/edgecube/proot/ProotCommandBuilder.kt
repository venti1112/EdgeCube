package com.venti1112.edgecube.proot

import android.content.Context
import android.os.Environment
import java.io.File

/** proot 启动命令的完整描述。 */
data class ProotCommand(
    val cmd: String,
    val argv: List<String>,
    val env: Map<String, String>,
    val cwd: String,
)

/**
 * proot 启动命令构造器：在 Android 上以无 root 方式运行 Linux rootfs。
 *
 * boot_command 拼装的做法来自 tiny_container 的 `ContainerMainViewModel.kt`。
 * 服务端工作目录通过 bind 挂载到容器内 [GUEST_SERVER_DIR]，cwd 设为该路径，
 * 使容器内看到的 server.jar / world / plugins 等文件实际位于 Android 可写存储。
 */
object ProotCommandBuilder {

    /** 容器内服务端工作目录的挂载点。 */
    const val GUEST_SERVER_DIR = "/mnt/server"

    /** 容器内 Android 共享存储的挂载点。 */
    const val GUEST_SDCARD_DIR = "/mnt/sdcard"

    /**
     * 构造「在 rootfs 内运行服务端」的 proot 命令。
     *
     * 根据 rootfs 元数据 [RootfsManifest.envType] 决定启动方式：
     *  - java：执行 [RootfsManifest.envMainBin]（如 /usr/bin/java），附加 -XX:ErrorFile
     *    与 -Djava.io.tmpdir 等容器内可用的 JVM 标准参数，再追加 [runtimeArgs] 与 [programArgs]。
     *  - php / node / python / box64 / dotnet：执行 envMainBin，附加 envArgs（如有）+ programArgs。
     *    box64 的 envMainBin 为 /usr/local/bin/box64，programArgs 为 x86_64 服务端文件。
     *    dotnet 的 envMainBin 为 /usr/bin/dotnet，programArgs 为 .dll 文件。
     *  - generic（无清单或 envMainBin 为空）：调用方必须改用 [buildGenericCommand]
     *    并提供完整启动命令；本方法对 generic rootfs 抛出 [IllegalStateException]。
     *
     * 服务端工作目录（[workingDir]，Android 路径）会被 bind 到容器内
     * [GUEST_SERVER_DIR]，proot 的 cwd 设为该挂载点。运行时本体（Java/PHP/…）
     * 来自 rootfs，故运行的是 rootfs 内未打补丁的原版。
     *
     * @param runtimeArgs 运行时参数（如 -Xmx2G）；非 java 环境也会原样追加到主程序后。
     * @param programArgs 程序参数（如 -jar server.jar nogui；或脚本文件路径 + 参数）。
     */
    fun buildServerCommand(
        context: Context,
        rootfsId: String,
        workingDir: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
    ): ProotCommand {
        val rootfs = RootfsStore.installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装，请先在「管理 → 运行环境」导入 rootfs.tar.zst")
        val manifest = rootfs.manifest
        if (manifest == null || manifest.isGeneric) {
            throw IllegalStateException(
                "rootfs '$rootfsId' 是纯容器（无元数据或 envType=generic），" +
                    "请在实例配置中填写完整的启动命令，或导入带元数据的环境 rootfs。"
            )
        }
        val envMainBin = manifest.envMainBin
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        ProotBootstrap.ensureBootstrap(context)
        // 每次启动前确保 DNS 配置存在（apt 等操作可能清空 resolv.conf）
        ProotDns.ensureResolvConf(context, rootfs.dir)

        val argv = baseArgv(context, rootfs.dir, GUEST_SERVER_DIR, serverBind = work)

        // 容器内执行的命令：环境主程序（如 /usr/bin/java、/usr/bin/php、…）
        argv.add(envMainBin)

        when (manifest.envType) {
            RootfsManifest.ENV_JAVA -> {
                // JVM 崩溃时把 hs_err 写到 stderr（PTY 从设备），父进程能收到
                argv.add("-XX:ErrorFile=/proc/self/fd/2")
                // 容器内 /tmp 已 bind，可直接用
                argv.add("-Djava.io.tmpdir=/tmp")
            }
            else -> {
                // php/node/python/box64/dotnet 等：附加清单声明的固定前缀参数。
                // box64 的 envMainBin 是 /usr/local/bin/box64，programArgs 是 x86_64 文件。
                // dotnet 的 envMainBin 是 /usr/bin/dotnet，programArgs 是 .dll 文件。
            }
        }
        // 清单声明的固定前缀参数（如 php/node 等的启动前缀）。
        // Java 环境**跳过** envArgs：java 的 `-jar` 必须紧邻 jar 文件、位于所有 JVM
        // 参数（如 -Xmx）之后，而 envArgs 是在 runtimeArgs 之前追加的——放在这里会得到
        // `java -jar -Xmx2G server.jar`，JVM 会把 -Xmx2G 当作 jar 文件名而失败。
        // Java 的 `-jar` 改由调用方在 programArgs 中于正确位置（runtimeArgs 之后、jar 之前）
        // 提供（见 server_page 的 `['-jar', file, 'nogui']`），与原生启动路径一致。
        // 现代 Forge/NeoForge（1.17+）走 @argfile，argfile 内已含主类，也不需要 -jar。
        val hasArgfile = runtimeArgs.any { it.startsWith("@") }
        if (!hasArgfile && manifest.envType != RootfsManifest.ENV_JAVA) {
            argv.addAll(manifest.envArgs)
        }
        // 调用方传入的运行时参数（如 -Xmx2G、@libraries/.../unix_args.txt）
        argv.addAll(runtimeArgs)
        // 调用方传入的程序参数（如 server.jar nogui）
        argv.addAll(programArgs)

        val env = ProotBootstrap.baseHostEnv(context).toMutableMap()
        // buildGenericCommand 和 buildShellCommand 均已覆盖 PATH，
        // buildServerCommand 同样需要容器内 PATH，否则 JVM 内 JLine
        // 尝试执行 "sh" 时会在宿主 PATH 中查找，而宿主路径在容器内不可见。
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = "/root"
        return ProotCommand(argv.first(), argv, env, work.absolutePath)
    }

    /**
     * 构造「在纯容器 rootfs 内运行用户自定义命令」的 proot 命令。
     *
     * 用于无元数据或 envType=generic 的 rootfs：用户须在实例配置中提供完整启动命令
     * （含主程序路径与所有参数），由本方法在容器内 [GUEST_SERVER_DIR] 下执行。
     *
     * [command] 已含主程序路径（容器内绝对路径，如 /usr/bin/python3 /mnt/server/main.py），
     * 用 busybox sh -c 包裹以支持 shell 语法（管道、引号、变量展开等）。
     */
    fun buildGenericCommand(
        context: Context,
        rootfsId: String,
        workingDir: String,
        command: String,
    ): ProotCommand {
        val rootfs = RootfsStore.installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装")
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")
        if (command.isBlank()) throw IllegalStateException("纯容器环境必须提供启动命令")

        ProotBootstrap.ensureBootstrap(context)
        ProotDns.ensureResolvConf(context, rootfs.dir)

        val argv = baseArgv(context, rootfs.dir, GUEST_SERVER_DIR, serverBind = work)

        // 用 rootfs 内的 sh -c 包裹用户命令：支持 shell 语法（管道/重定向/引号）。
        // 优先 /bin/bash（更友好），否则回退 /bin/sh。
        argv.add(preferredShell(rootfs.dir))
        argv.add("-c")
        argv.add(command)

        val env = ProotBootstrap.baseHostEnv(context).toMutableMap()
        // 用户命令可能调用容器内系统工具（chmod / cp / ls 等），PATH 必须包含
        // 容器内标准目录；baseHostEnv 的 PATH 只含 bootstrap/bin 与 /system/bin，
        // 会导致 sh -c "chmod ..." 报「未找到命令」。
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = "/root"
        return ProotCommand(argv.first(), argv, env, work.absolutePath)
    }

    /**
     * 构造「进入 rootfs 交互式 shell」的 proot 命令。
     *
     * 默认进入容器内用户 home（/root 或 /home/<user>），可通过 [cwd] 指定容器内
     * 绝对路径。优先使用 `/bin/bash`（minbase 已包含），不存在时回退 `/bin/sh`。
     *
     * @param cwd 容器内绝对路径（如 /root、/mnt/server）；为空时用 /root。
     */
    fun buildShellCommand(
        context: Context,
        rootfsId: String,
        cwd: String? = null,
    ): ProotCommand {
        val rootfs = RootfsStore.installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装")
        ProotBootstrap.ensureBootstrap(context)
        // 每次进入 shell 前确保 DNS 配置存在（apt 等操作可能清空 resolv.conf）
        ProotDns.ensureResolvConf(context, rootfs.dir)

        val guestCwd = cwd?.takeIf { it.isNotBlank() } ?: "/root"

        // 交互 shell 无须 bind 服务端目录；-0 伪造 root 身份使 apt install /
        // dpkg 等包管理操作可行（proot 不真正提权，仅让 getuid 等系统调用返回 0，
        // 文件实际仍以 app uid 写入）。
        val argv = baseArgv(context, rootfs.dir, guestCwd)

        // 优先 bash（更好用），不存在则回退 sh
        argv.add(preferredShell(rootfs.dir))
        argv.add("-i")

        // 交互 shell 内给出更友好的提示符与终端类型
        val env = ProotBootstrap.baseHostEnv(context).toMutableMap()
        env["TERM"] = "xterm-256color"
        env["LANG"] = "zh_CN.UTF-8"
        env["HOME"] = guestCwd
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return ProotCommand(argv.first(), argv, env, guestCwd)
    }

    // ──────────────────────────────────────────────────────
    // 内部辅助
    // ──────────────────────────────────────────────────────

    /**
     * 三种启动方式共用的 proot argv 前缀：rootfs、容器内 cwd、必备 bind。
     *
     * @param serverBind 非空时把该宿主目录 bind 到容器内 [GUEST_SERVER_DIR]。
     */
    private fun baseArgv(
        context: Context,
        rootfsDir: File,
        guestCwd: String,
        serverBind: File? = null,
    ): MutableList<String> {
        val argv = mutableListOf<String>()
        argv.add(ProotBootstrap.prootBin(context).absolutePath)
        argv.add("--rootfs=${rootfsDir.absolutePath}")
        argv.add("--cwd=$guestCwd")
        argv.add("--link2symlink")
        // -0：伪造 root 身份（proot-distro 标准做法）。服务端常尝试
        // chmod/eula.txt 写入等操作，伪造 root 可避免权限相关失败。
        argv.add("-0")
        // 必备文件系统 bind：dev/proc/sys 是任何 Linux 程序的硬依赖
        argv.add("--bind=/dev")
        argv.add("--bind=/proc")
        argv.add("--bind=/sys")
        // /dev/urandom -> /dev/random：SecureRandom 在容器内偶发读 /dev/random 阻塞
        argv.add("--bind=/dev/urandom:/dev/random")
        // 服务端工作目录：bind 到容器内固定挂载点，cwd 即此处
        if (serverBind != null) {
            argv.add("--bind=${serverBind.absolutePath}:$GUEST_SERVER_DIR")
        }
        // Android 共享存储：让容器内可读写 /mnt/sdcard（与 tiny_container 一致）
        val sdcard = Environment.getExternalStorageDirectory()
        if (sdcard != null && sdcard.isDirectory) {
            argv.add("--bind=${sdcard.absolutePath}:$GUEST_SDCARD_DIR")
        }
        // tmpfs 替代不可写的 /tmp：用 app cacheDir 作为容器 /tmp
        val tmpDir = File(context.cacheDir, "proot_tmp")
        tmpDir.mkdirs()
        argv.add("--bind=${tmpDir.absolutePath}:/tmp")
        argv.add("--bind=${tmpDir.absolutePath}:/run")
        return argv
    }

    /** 容器内交互/包裹命令用的 shell：优先 /bin/bash，不存在回退 /bin/sh。 */
    private fun preferredShell(rootfsDir: File): String =
        if (File(rootfsDir, "bin/bash").exists()) "/bin/bash" else "/bin/sh"
}
