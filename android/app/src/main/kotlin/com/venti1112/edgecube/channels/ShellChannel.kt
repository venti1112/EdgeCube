package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.shell.ShellCommandRunner
import com.venti1112.edgecube.shell.ShellProcessManager
import com.venti1112.edgecube.shell.ShellResolver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Shell 终端通道：交互式 PTY shell（writeInput/resize 等）与一次性命令执行
 * （runCommand），事件流回放见 [ShellProcessManager.setEventSink]。
 */
internal object ShellChannel {

    private const val CHANNEL = "com.venti1112.edgecube/shell"
    private const val EVENT_CHANNEL = "com.venti1112.edgecube/shell_events"

    fun register(messenger: BinaryMessenger, context: Context) {
        val shellManager = ShellProcessManager.getInstance(context)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "availableShells" -> {
                    // 返回结构化 shell 选项列表（含 id/label/type）。
                    // 旧调用方若直接当 List<String> 用，Map.toString() 仍可显示，但推荐用 availableShellOptions。
                    val options = ShellResolver.availableOptions(context).map { opt ->
                        mapOf(
                            "id" to opt.id,
                            "label" to opt.label,
                            "type" to opt.type,
                        )
                    }
                    result.success(options)
                }

                "isRunning" -> result.success(shellManager.isRunning)

                "start" -> {
                    try {
                        val cwd = call.argument<String>("cwd")
                        val shellId = call.argument<String>("shellId")
                        shellManager.start(cwd, shellId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHELL_START_FAILED", e.message, null)
                    }
                }

                "writeInput" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null) shellManager.writeInput(bytes)
                    result.success(null)
                }

                "sendCommand" -> {
                    shellManager.sendCommand(call.argument<String>("line") ?: "")
                    result.success(null)
                }

                "resize" -> {
                    val cols = call.argument<Int>("cols") ?: 0
                    val rows = call.argument<Int>("rows") ?: 0
                    val cellWidth = call.argument<Int>("cellWidth") ?: 0
                    val cellHeight = call.argument<Int>("cellHeight") ?: 0
                    shellManager.resize(rows, cols, cellWidth, cellHeight)
                    result.success(null)
                }

                "setEcho" -> {
                    shellManager.setEcho(call.argument<Boolean>("echo") ?: true)
                    result.success(null)
                }

                "stop" -> {
                    shellManager.stop()
                    result.success(null)
                }

                "forceStop" -> {
                    shellManager.forceStop()
                    result.success(null)
                }

                "clearLog" -> {
                    shellManager.clearLog()
                    result.success(null)
                }

                "runCommand" -> {
                    val command = call.argument<String>("command")
                    if (command == null) {
                        result.error("BAD_ARGS", "缺少 command", null)
                    } else {
                        val cwd = call.argument<String>("cwd")
                        // 命令可能阻塞，放后台线程；完成后回主线程返回结果。
                        ChannelIo.runAsync(result, "RUN_FAILED") {
                            ShellCommandRunner.runOnce(context, command, cwd)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shellManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    shellManager.setEventSink(null)
                }
            },
        )
    }
}
