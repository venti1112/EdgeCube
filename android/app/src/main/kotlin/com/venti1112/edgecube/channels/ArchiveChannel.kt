package com.venti1112.edgecube.channels

import com.venti1112.edgecube.files.ArchiveExtractor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 归档通道：zip / tar / tar.gz|xz|zst / 7z / rar 等格式统一在原生侧处理
 * （实现见 [ArchiveExtractor]），解压进度经事件通道推送。
 */
internal object ArchiveChannel {

    private const val CHANNEL = "com.venti1112.edgecube/archive"
    private const val EVENT_CHANNEL = "com.venti1112.edgecube/archive_events"

    fun register(messenger: BinaryMessenger) {
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

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "compress" -> {
                    val sourcePaths = call.argument<List<String>>("sourcePaths")
                    val archivePath = call.argument<String>("archivePath")
                    if (sourcePaths == null || archivePath == null) {
                        result.error("BAD_ARGS", "缺少 sourcePaths/archivePath", null)
                    } else {
                        ChannelIo.runAsync(result, "COMPRESS_FAILED") {
                            ArchiveExtractor.compressToZip(sourcePaths, archivePath)
                        }
                    }
                }
                "extract" -> {
                    val archivePath = call.argument<String>("archivePath")
                    val destDir = call.argument<String>("destDir")
                    if (archivePath == null || destDir == null) {
                        result.error("BAD_ARGS", "缺少 archivePath/destDir", null)
                    } else {
                        ChannelIo.runAsync(result, "EXTRACT_FAILED") {
                            ArchiveExtractor.extract(archivePath, destDir) { current, total ->
                                ChannelIo.mainHandler.post {
                                    eventSink?.success(mapOf("current" to current, "total" to total))
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
