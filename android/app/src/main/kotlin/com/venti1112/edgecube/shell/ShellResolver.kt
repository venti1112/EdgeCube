package com.venti1112.edgecube.shell

import android.content.Context
import android.os.Environment

/**
 * 一个可执行 shell 的解析结果。
 *
 * [cmd] 为可执行文件绝对路径；[argvPrefix] 为附加在用户命令之前的固定参数
 * （交互模式形如 `-i`；一次性模式形如 `-c`）；[label] 为展示名。
 */
data class ShellSpec(
    val cmd: String,
    val argvPrefix: List<String>,
    val label: String,
)

/**
 * shell 解析与环境构造。
 *
 * 统一使用系统自带的 `/system/bin/sh`（Android 上为 mksh/toybox），
 * 附带系统 toybox 提供的常用命令（ls/cd/cat/grep/mount 等），无需额外打包 shell 二进制。
 */
object ShellResolver {
    private const val SYSTEM_SH = "/system/bin/sh"
    private const val SYSTEM_SH_LABEL = "system sh"

    /** 交互式 shell（用于 PTY 终端）。 */
    fun resolveInteractive(): ShellSpec =
        ShellSpec(SYSTEM_SH, listOf("-i"), SYSTEM_SH_LABEL)

    /** 一次性执行（`sh -c <command>`，用于 MCP 命令执行）。 */
    fun resolveOnce(): ShellSpec =
        ShellSpec(SYSTEM_SH, listOf("-c"), SYSTEM_SH_LABEL)

    /** 当前可用的 shell 列表，用于界面展示。 */
    fun availableLabels(): List<String> = listOf(SYSTEM_SH_LABEL)

    /** 默认工作目录：优先外部存储根（应用持有 MANAGE_EXTERNAL_STORAGE），否则应用私有目录。 */
    fun defaultCwd(context: Context): String {
        val ext = Environment.getExternalStorageDirectory()
        if (ext != null && ext.isDirectory) return ext.absolutePath
        return context.filesDir.absolutePath
    }

    /**
     * 构造 shell 子进程的基础环境（继承本进程环境 + 覆盖项）。
     *
     * PATH 包含系统 bin 目录，确保 toybox 提供的常用命令可被找到；
     * 不强行设置依赖特定 shell 转义的 PS1（mksh 不识别），仅给一个跨 shell 一致的 `$ `。
     */
    fun baseEnv(context: Context, home: String): HashMap<String, String> {
        val env = HashMap(System.getenv())
        val inheritedPath = System.getenv("PATH")
        env["PATH"] = buildString {
            append("/system/bin:/system/xbin")
            if (!inheritedPath.isNullOrEmpty()) {
                append(':')
                append(inheritedPath)
            }
        }
        env["HOME"] = home
        env["TERM"] = "xterm-256color"
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        env["PS1"] = "\$ "
        return env
    }
}
