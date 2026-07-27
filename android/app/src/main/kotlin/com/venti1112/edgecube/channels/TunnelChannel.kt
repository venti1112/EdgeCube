package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.server.RuntimeInstaller
import com.venti1112.edgecube.server.TunnelProcessManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 隧道（frpc）通道：与服务端通道完全独立，可同时运行
 * （实现见 [TunnelProcessManager]）。
 */
internal object TunnelChannel {

    private const val CHANNEL = "com.venti1112.edgecube/tunnel"
    private const val EVENT_CHANNEL = "com.venti1112.edgecube/tunnel_events"

    fun register(messenger: BinaryMessenger, context: Context) {
        val tunnelManager = TunnelProcessManager.getInstance(context)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isFrpcAvailable" ->
                    result.success(RuntimeInstaller.isFrpcAvailable(context))

                "isFrpcReady" ->
                    result.success(RuntimeInstaller.installedFrpc(context) != null)

                "isRunning" -> result.success(tunnelManager.isRunning)

                "start" -> {
                    val configPath = call.argument<String>("configPath")
                    val name = call.argument<String>("name") ?: "frpc"
                    val runtimeId = call.argument<String>("runtimeId")
                    if (configPath == null) {
                        result.error("BAD_ARGS", "缺少 configPath", null)
                    } else {
                        // 含首次解压，放后台线程；完成后回主线程返回结果。
                        ChannelIo.runAsync(result, "START_FAILED") {
                            tunnelManager.start(configPath, name, runtimeId)
                            true
                        }
                    }
                }

                "stop" -> {
                    tunnelManager.stop()
                    result.success(null)
                }

                "forceStop" -> {
                    tunnelManager.forceStop()
                    result.success(null)
                }

                "reload" -> {
                    val port = call.argument<Int>("port") ?: 0
                    val user = call.argument<String>("user")
                    val password = call.argument<String>("password")
                    if (port <= 0) {
                        result.error("BAD_ARGS", "缺少有效的 port", null)
                    } else {
                        ChannelIo.runAsync(result, "RELOAD_FAILED") {
                            tunnelManager.reload(port, user, password)
                        }
                    }
                }

                "clearLog" -> {
                    tunnelManager.clearLog()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    tunnelManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    tunnelManager.setEventSink(null)
                }
            },
        )
    }
}
