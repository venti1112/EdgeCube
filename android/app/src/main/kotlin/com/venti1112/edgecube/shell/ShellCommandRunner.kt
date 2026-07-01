package com.venti1112.edgecube.shell

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

/**
 * 一次性 shell 命令执行（供 MCP 工具使用）。
 *
 * 与交互终端（[ShellProcessManager] 走 PTY）不同，这里用 [ProcessBuilder] 跑
 * `<shell> -c <command>`，合并 stdout/stderr 并干净地捕获输出与退出码，适合程序化调用。
 * 范式参照 [com.venti1112.edgecube.MainActivity] 的 Forge 安装器实现。
 */
object ShellCommandRunner {
    /** 输出捕获上限（字符）；超出截断并标注。 */
    private const val MAX_OUTPUT_CHARS = 64 * 1024

    /**
     * 在 [cwd]（空/无效则用默认目录）执行 [command]，返回
     * `{exitCode, output, cwd, shell}`。出错时 exitCode 为 -1，output 含错误信息。
     */
    fun runOnce(context: Context, command: String, cwd: String?): Map<String, Any?> {
        val workDir = cwd?.takeIf { File(it).isDirectory } ?: ShellResolver.defaultCwd(context)
        val spec = ShellResolver.resolveOnce()

        val cmd = ArrayList<String>()
        cmd.add(spec.cmd)
        cmd.addAll(spec.argvPrefix)
        cmd.add(command)

        val pb = ProcessBuilder(cmd)
        pb.directory(File(workDir))
        pb.redirectErrorStream(true)
        pb.environment().putAll(ShellResolver.baseEnv(context, workDir))

        val sb = StringBuilder()
        var truncated = false
        val exitCode: Int
        try {
            val p = pb.start()
            p.outputStream.close() // 不向子进程提供 stdin
            BufferedReader(InputStreamReader(p.inputStream, StandardCharsets.UTF_8)).use { reader ->
                val chunk = CharArray(4096)
                while (true) {
                    val n = reader.read(chunk)
                    if (n < 0) break
                    if (sb.length >= MAX_OUTPUT_CHARS) {
                        truncated = true
                        continue
                    }
                    val room = MAX_OUTPUT_CHARS - sb.length
                    if (n <= room) {
                        sb.append(chunk, 0, n)
                    } else {
                        sb.append(chunk, 0, room)
                        truncated = true
                    }
                }
            }
            exitCode = p.waitFor()
        } catch (e: Exception) {
            return mapOf(
                "exitCode" to -1,
                "output" to "执行失败：${e.message}",
                "cwd" to workDir,
                "shell" to spec.label,
            )
        }

        var output = sb.toString()
        if (truncated) output += "\n…(输出已截断，超过 $MAX_OUTPUT_CHARS 字符)"
        return mapOf(
            "exitCode" to exitCode,
            "output" to output,
            "cwd" to workDir,
            "shell" to spec.label,
        )
    }
}
