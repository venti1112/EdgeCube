package com.venti1112.edgecube.shell

import android.content.Context
import android.os.Environment
import java.io.File

/**
 * 一个可执行 shell 的解析结果。
 *
 * [cmd] 为可执行文件绝对路径；[argvPrefix] 为附加在用户命令之前的固定参数
 * （交互模式形如 `-i`、`sh -i`；一次性模式形如 `-c`、`sh -c`）；[label] 为展示名。
 */
data class ShellSpec(
    val cmd: String,
    val argvPrefix: List<String>,
    val label: String,
)

/**
 * shell 二进制解析与环境构造。
 *
 * 策略：优先使用用户日后自行编译并放入 `jniLibs/<abi>/` 的 `libbash.so` / `libbusybox.so`
 * （安装时解压到可执行的 nativeLibraryDir），都不存在时回退到系统自带的 `/system/bin/sh`
 * （toybox，开箱即用 ls/cd/cat 等）。
 *
 * 现代 Android 的 W^X 约束：只能从 nativeLibraryDir 执行二进制，filesDir 不可执行，故
 * 自带 shell 必须以 `lib*.so` 形式打包。
 */
object ShellResolver {
    private const val BASH = "libbash.so"
    private const val BUSYBOX = "libbusybox.so"
    private const val SYSTEM_SH = "/system/bin/sh"

    /** 交互式 shell（用于 PTY 终端，自带行编辑/历史/补全）。 */
    fun resolveInteractive(nativeDir: String): ShellSpec {
        File(nativeDir, BASH).let { if (it.exists()) return ShellSpec(it.absolutePath, listOf("-i"), "Bash") }
        File(nativeDir, BUSYBOX).let { if (it.exists()) return ShellSpec(it.absolutePath, listOf("sh", "-i"), "BusyBox ash") }
        return ShellSpec(SYSTEM_SH, listOf("-i"), "system sh")
    }

    /** 一次性执行（`<shell> -c <command>`，用于 MCP 命令执行）。 */
    fun resolveOnce(nativeDir: String): ShellSpec {
        File(nativeDir, BASH).let { if (it.exists()) return ShellSpec(it.absolutePath, listOf("-c"), "Bash") }
        File(nativeDir, BUSYBOX).let { if (it.exists()) return ShellSpec(it.absolutePath, listOf("sh", "-c"), "BusyBox ash") }
        return ShellSpec(SYSTEM_SH, listOf("-c"), "system sh")
    }

    /** 当前可用的 shell 列表（按优先级），用于界面展示。 */
    fun availableLabels(nativeDir: String): List<String> {
        val list = mutableListOf<String>()
        if (File(nativeDir, BASH).exists()) list.add("Bash")
        if (File(nativeDir, BUSYBOX).exists()) list.add("BusyBox ash")
        list.add("system sh")
        return list
    }

    /** 默认工作目录：优先外部存储根（应用持有 MANAGE_EXTERNAL_STORAGE），否则应用私有目录。 */
    fun defaultCwd(context: Context): String {
        val ext = Environment.getExternalStorageDirectory()
        if (ext != null && ext.isDirectory) return ext.absolutePath
        return context.filesDir.absolutePath
    }

    /**
     * 构造 shell 子进程的基础环境（继承本进程环境 + 覆盖项）。
     *
     * PATH 把 nativeDir 与系统 bin 目录纳入，使自带二进制与 toybox applet 都可被找到；
     * 不强行设置依赖 bash 转义的 PS1（mksh 不识别），仅给一个跨 shell 一致的 `$ `。
     */
    fun baseEnv(context: Context, nativeDir: String, home: String): HashMap<String, String> {
        val env = HashMap(System.getenv())
        val inheritedPath = System.getenv("PATH")
        env["PATH"] = buildString {
            append(nativeDir)
            append(":/system/bin:/system/xbin")
            if (!inheritedPath.isNullOrEmpty()) {
                append(':')
                append(inheritedPath)
            }
        }
        env["HOME"] = home
        env["TERM"] = "xterm-256color"
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        env["LD_LIBRARY_PATH"] = nativeDir
        env["PS1"] = "\$ "
        return env
    }
}
