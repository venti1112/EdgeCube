package com.venti1112.edgecube.localservice

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter ↔ Android 本地服务通道。
 *
 * MethodChannel 负责「动作 + 当前状态」，EventChannel 负责状态变化与日志。
 * `preparing/starting` 这类耗时阶段不会阻塞 MethodChannel 调用，调用方
 * 立即拿到当时的状态，后续进展全部走事件流。
 */
internal object LocalServiceChannel {

    private const val CHANNEL = "com.venti1112.edgecube/local_service"
    private const val EVENT_CHANNEL = "com.venti1112.edgecube/local_service_events"

    fun register(messenger: BinaryMessenger, context: Context) {
        val manager = LocalServiceManager.getInstance(context)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(LocalServiceManager.isSupported(context))
                "status" -> result.success(manager.status())
                "start" -> {
                    manager.start()
                    result.success(manager.status())
                }
                "stop" -> {
                    manager.stop()
                    result.success(manager.status())
                }
                "logs" -> result.success(manager.logsSnapshot())
                "clearLogs" -> {
                    manager.clearLogs()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    manager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    manager.setEventSink(null)
                }
            },
        )
    }
}
