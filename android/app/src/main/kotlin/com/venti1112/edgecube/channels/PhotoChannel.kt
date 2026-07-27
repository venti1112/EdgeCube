package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.photos.PhotoStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 照片通道：相册权限、图片枚举、缩略图/原图读取与复制到缓存
 * （实现见 [PhotoStore]）。
 */
internal object PhotoChannel {

    private const val CHANNEL = "com.venti1112.edgecube/photos"

    fun register(
        messenger: BinaryMessenger,
        context: Context,
        permissions: PermissionsController,
    ) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(permissions.hasPhotoPermission())
                "request" -> permissions.requestPhotoPermission(result)
                "list" -> {
                    if (!permissions.hasPhotoPermission()) {
                        result.success(emptyList<Map<String, Any?>>())
                    } else {
                        ChannelIo.runAsync(result, "PHOTO_LIST_FAILED") {
                            PhotoStore.queryPhotos(context)
                        }
                    }
                }
                "bytes" -> {
                    val uri = call.argument<String>("uri")
                    val maxSize = call.argument<Int>("maxSize") ?: 512
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        ChannelIo.runAsync(result, "PHOTO_BYTES_FAILED") {
                            PhotoStore.readThumbnailBytes(context, uri, maxSize)
                        }
                    }
                }
                "originalBytes" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        ChannelIo.runAsync(result, "PHOTO_ORIGINAL_FAILED") {
                            PhotoStore.readOriginalBytes(context, uri)
                        }
                    }
                }
                "copyToCache" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name")
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        ChannelIo.runAsync(result, "PHOTO_COPY_FAILED") {
                            PhotoStore.copyToCache(context, uri, name)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
