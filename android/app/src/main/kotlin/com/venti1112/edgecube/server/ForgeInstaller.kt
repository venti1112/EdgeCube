package com.venti1112.edgecube.server

import android.content.Context
import com.venti1112.edgecube.proot.ProotCommandBuilder
import com.venti1112.edgecube.proot.RootfsManifest
import com.venti1112.edgecube.proot.RootfsStore
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

/**
 * Forge/NeoForge 安装器：下载好的 installer.jar 在本地运行
 * `java -jar installer.jar --installServer`，把安装日志逐行回调给调用方。
 *
 * 必须在后台线程调用（安装器会下载库文件，耗时数十秒到数分钟）。
 */
object ForgeInstaller {

    private val ansiPattern = Regex("\\x1B\\[[0-?]*[ -/]*[@-~]")

    /**
     * 用原生 JRE 运行 Forge Installer。
     * 复用 liblaunch.so + JRE 机制，绕开 Android SELinux 对 data 目录的 execve 限制。
     * 安装器会自行下载 Forge 库文件到 workingDir。
     *
     * @param onLine 安装日志行回调（已去 ANSI），线程为本方法的调用线程。
     * @return 进程退出码，0 表示成功。
     */
    fun runInstaller(
        context: Context,
        installerJar: String,
        workingDir: String,
        jreId: String,
        onLine: (String) -> Unit,
    ): Int {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val tagfixLib = "$nativeDir/libtagfix.so"

        // 确保 JRE 已安装。
        val manifest = RuntimeInstaller.installedRuntime(context, jreId)
            ?: throw IllegalStateException("JRE 运行时 $jreId 未安装，请先在「管理 → 运行环境」导入")

        val jreDir = RuntimeInstaller.runtimeDir(context, jreId)
        val resolved = JreLayout.resolve(jreDir, nativeDir)
        val launchBin = File(nativeDir, "liblaunch.so")
        if (!launchBin.exists()) {
            throw IllegalStateException("未找到 liblaunch.so，请确认其已随 APK 打包到 lib 目录")
        }

        val cmd = listOf(
            launchBin.absolutePath,
            "-XX:ErrorFile=/proc/self/fd/2",
            // Android 上 /tmp 不可写，指定可写的 tmpdir
            "-Djava.io.tmpdir=${context.cacheDir.absolutePath}",
            "-jar", installerJar,
            "--installServer",
        )

        val pb = ProcessBuilder(cmd)
        pb.directory(File(workingDir))
        pb.redirectErrorStream(true)
        val env = pb.environment()
        env["LD_PRELOAD"] = tagfixLib
        env["JAVA_HOME"] = jreDir.absolutePath
        env["EC_LIBJLI"] = resolved.libjli.absolutePath
        env["LD_LIBRARY_PATH"] = resolved.ldLibraryPath
        env["HOME"] = workingDir
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        env["FCL_NATIVEDIR"] = nativeDir
        env["POJAV_NATIVEDIR"] = nativeDir
        env["PATH"] = "${jreDir.absolutePath}/bin:${System.getenv("PATH") ?: ""}"
        // 叠加清单 env
        ManifestEnv.apply(env, manifest, jreDir)

        onLine("[EdgeCube] 开始安装 Forge 服务端…")
        return runAndStream(pb, onLine)
    }

    /**
     * 在 proot 容器（Java rootfs）内运行 Forge/NeoForge 安装器。
     *
     * 用于未安装原生 JRE、但已导入带 Java 环境 rootfs 的场景。复用
     * [ProotCommandBuilder.buildGenericCommand] 构造 proot 命令（已配好
     * bind/DNS/bootstrap），在容器内执行 `<envMainBin> -jar <installer> --installServer`。
     * 工作目录 [workingDir] 被 bind 到容器内 /mnt/server（即 proot 内 cwd），
     * 安装产物落回宿主目录，与原生安装路径的产物定位逻辑一致。
     */
    fun runInstallerProot(
        context: Context,
        installerJar: String,
        workingDir: String,
        rootfsId: String,
        onLine: (String) -> Unit,
    ): Int {
        val rootfs = RootfsStore.installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot 容器 $rootfsId 不存在")
        val manifest = rootfs.manifest
        val javaBin = manifest?.envMainBin
        if (manifest == null || manifest.isGeneric ||
            manifest.envType != RootfsManifest.ENV_JAVA || javaBin.isNullOrBlank()
        ) {
            throw IllegalStateException("所选 proot 容器不是 Java 环境，无法用于安装模组加载器")
        }

        // proot 内 cwd = /mnt/server = 宿主 workingDir，安装器 jar 用 basename 即可。
        // 文件名由本应用命名（forge-installer.jar / neoforge-installer.jar），无注入风险，
        // 仍以单引号包裹防御 sh -c 解析。
        val installerName = File(installerJar).name
        val command = "'$javaBin' -jar '$installerName' --installServer"
        val pc = ProotCommandBuilder.buildGenericCommand(
            context, rootfsId, workingDir, command,
        )

        val pb = ProcessBuilder(pc.argv)
        pb.directory(File(pc.cwd))
        pb.redirectErrorStream(true)
        val env = pb.environment()
        env.clear()
        env.putAll(pc.env)

        val envLabel = manifest.envName.ifEmpty { rootfsId }
        onLine("[EdgeCube] 在 proot 容器内开始安装（$envLabel）…")
        return runAndStream(pb, onLine)
    }

    /** 启动进程，逐行读取输出（去 ANSI 后回调），返回退出码。 */
    private fun runAndStream(pb: ProcessBuilder, onLine: (String) -> Unit): Int {
        val p = pb.start()
        var exitCode = -1
        try {
            BufferedReader(InputStreamReader(p.inputStream, StandardCharsets.UTF_8)).use { reader ->
                var line = reader.readLine()
                while (line != null) {
                    onLine(ansiPattern.replace(line, ""))
                    line = reader.readLine()
                }
            }
            exitCode = p.waitFor()
        } catch (e: Exception) {
            onLine("[EdgeCube] 安装器异常：${e.message}")
        }
        onLine("[EdgeCube] 安装器退出，退出码：$exitCode")
        return exitCode
    }
}
