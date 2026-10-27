package com.venti1112.edgecube.localservice

import android.content.Context
import java.io.File
import java.util.TimeZone

/** 一次本地服务启动的完整命令描述。 */
data class LocalServiceCommand(
    val argv: List<String>,
    val env: Map<String, String>,
    val cwd: String,
)

/**
 * 构造「在 proot 里运行 daemon」的命令。
 *
 * 平台无关的本地服务抽象在 Flutter 侧；这里是 Android 的实现细节：
 * 只有这一层知道 proot 的存在，换成桌面端直接 `ProcessBuilder` 拉起时
 * 不需要动上层。
 */
object ProotCommandBuilder {

    fun buildDaemonCommand(
        context: Context,
        rootfsDir: File,
        token: String,
        parentPid: Int,
    ): LocalServiceCommand {
        LocalServicePaths.ensureDirs(context)
        val daemon = ProotBootstrap.stageDaemonBinary(context)
        val proot = ProotBootstrap.prootBin(context)
        if (!proot.exists()) throw IllegalStateException("proot 未就绪：${proot.absolutePath}")
        if (!daemon.exists()) throw IllegalStateException("daemon 未就绪：${daemon.absolutePath}")

        val localDir = LocalServicePaths.baseDir(context)
        val tmpDir = File(context.cacheDir, "proot_tmp").apply { mkdirs() }

        val prootArgs = mutableListOf(
            proot.absolutePath,
            "--rootfs=${rootfsDir.absolutePath}",
            "--cwd=${LocalServicePaths.GUEST_BASE}",
            "--link2symlink",
            "-0",
            "--bind=/dev",
            "--bind=/proc",
            "--bind=/sys",
            // SecureRandom 偶发读 /dev/random 阻塞，指向 urandom
            "--bind=/dev/urandom:/dev/random",
            // 宿主本地服务目录：daemon 二进制、数据、配置、就绪文件都在这里
            "--bind=${localDir.absolutePath}:${LocalServicePaths.GUEST_BASE}",
            // 容器内 /tmp 与 /run 用 app 缓存目录
            "--bind=${tmpDir.absolutePath}:/tmp",
            "--bind=${tmpDir.absolutePath}:/run",
            LocalServicePaths.GUEST_DAEMON,
            "--host",
            "127.0.0.1",
            // 让系统分配端口：避免与设备上别的程序撞 8787
            "--port",
            "0",
            "--token",
            token,
            "--log-level",
            "info",
            "--log-format",
            "pretty",
            "--no-color",
            "--ready-file",
            LocalServicePaths.GUEST_READY,
            // App 进程没了就跟着退出；proot 不是父进程，不能指望 PDEATHSIG
            "--exit-with-parent",
            parentPid.toString(),
        )

        val env = ProotBootstrap.baseHostEnv(context).apply {
            // 进入容器后这些是 guest 路径，覆盖 baseHostEnv 里面向宿主的取值
            put("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${LocalServicePaths.GUEST_BASE}/bin")
            put("HOME", LocalServicePaths.GUEST_HOME)
            put("TMPDIR", "/tmp")
            put("LANG", "C.UTF-8")
            put("LC_ALL", "C.UTF-8")
            // 容器内没有 /etc/localtime，日志时间戳靠 TZ
            put("TZ", TimeZone.getDefault().id)
            put("EDGECUBE_DATA_DIR", LocalServicePaths.GUEST_DATA)
            put("XDG_CONFIG_HOME", LocalServicePaths.GUEST_CONFIG)
            put("EDGECUBE_LOG_LEVEL", "info")
            put("EDGECUBE_LOG_FORMAT", "pretty")
            put("EDGECUBE_NO_COLOR", "1")
        }

        // 用 /system/bin/sh 记录 PID 后 exec：
        //  - $$ 在 exec 后保持不变，pid 文件里就是 proot 的宿主 PID；
        //  - "$0" "$@" 保证参数逐个传递，不用手工拼引号。
        val pidFile = LocalServicePaths.prootPidFile(context)
        pidFile.delete()
        val script = "echo ${'$'}${'$'} > '${pidFile.absolutePath}'; " +
            "exec \"${'$'}0\" \"${'$'}@\""
        val argv = mutableListOf("/system/bin/sh", "-c", script, prootArgs.first())
        argv.addAll(prootArgs.drop(1))

        return LocalServiceCommand(
            argv = argv,
            env = env,
            cwd = localDir.absolutePath,
        )
    }
}
