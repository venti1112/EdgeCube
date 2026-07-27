package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.server.ForgeInstaller
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Forge 安装通道：下载 installer 后在本地运行
 * `java -jar installer.jar --installServer`（实现见 [ForgeInstaller]），
 * 安装日志经事件通道逐行推送。
 */
internal object ForgeChannel {

    private const val CHANNEL = "com.venti1112.edgecube/forge"
    private const val EVENT_CHANNEL = "com.venti1112.edgecube/forge_events"

    fun register(messenger: BinaryMessenger, context: Context) {
        var eventSink: EventChannel.EventSink? = null
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        // 安装日志行回调：事件下发须在主线程。
        val onLine: (String) -> Unit = { line ->
            ChannelIo.mainHandler.post { eventSink?.success(line) }
        }

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "runInstaller" -> {
                    val installerJar = call.argument<String>("installerJar")
                    val workingDir = call.argument<String>("workingDir")
                    val jreId = call.argument<String>("jreId") ?: "jre21"
                    // 非空时改用 proot 容器（Java rootfs）内的 java 运行安装器，
                    // 供未安装原生 JRE 的场景使用。
                    val prootRootfsId = call.argument<String>("prootRootfsId")
                    if (installerJar == null || workingDir == null) {
                        result.error("BAD_ARGS", "缺少 installerJar/workingDir", null)
                    } else {
                        ChannelIo.runAsync(result, "INSTALL_FAILED") {
                            if (!prootRootfsId.isNullOrBlank()) {
                                ForgeInstaller.runInstallerProot(
                                    context, installerJar, workingDir, prootRootfsId, onLine,
                                )
                            } else {
                                ForgeInstaller.runInstaller(
                                    context, installerJar, workingDir, jreId, onLine,
                                )
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
