package com.venti1112.edgecube.channels

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * `.ecpkg` 文件关联入口：处理 ACTION_VIEW / ACTION_SEND 打开的运行时包，
 * 解析出可读路径后经 `openEcpkg` 方法推送给 Dart 端。
 *
 * Activity 冷启动时 Flutter engine 尚未就绪，路径/错误先暂存，
 * [attach] 后补发。
 */
class EcpkgChannel(private val activity: Activity) {

    companion object {
        private const val CHANNEL = "com.venti1112.edgecube/ecpkg"
    }

    private var channel: MethodChannel? = null
    private var pendingPath: String? = null
    private var pendingError: String? = null

    /** engine 就绪后创建通道并补发暂存的路径/错误。 */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        flushPending()
    }

    /** 由 MainActivity 的 onCreate / onNewIntent 转调。 */
    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> return
        } ?: return

        // 检查文件名是否以 .ecpkg 结尾
        val fileName = fileNameFromUri(uri)
        if (fileName == null) {
            sendError("无法获取文件名")
            return
        }
        if (!fileName.lowercase().endsWith(".ecpkg")) {
            sendError("不是有效的 .ecpkg 文件")
            return
        }

        // 获取可访问的文件路径
        val path = resolveFilePath(uri)
        if (path == null) {
            sendError("无法读取文件，请检查文件访问权限")
            return
        }
        // Flutter engine 尚未就绪时暂存，attach 中发送
        pendingPath = path
        flushPending()
    }

    private fun sendError(message: String) {
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("ecpkgError", message)
        } else {
            pendingError = message
        }
    }

    private fun flushPending() {
        val ch = channel ?: return

        val error = pendingError
        if (error != null) {
            pendingError = null
            ch.invokeMethod("ecpkgError", error)
            return
        }

        val path = pendingPath ?: return
        pendingPath = null
        ch.invokeMethod("openEcpkg", path)
    }

    private fun fileNameFromUri(uri: Uri): String? {
        // 尝试从 URI 中获取文件名
        if (uri.scheme == "file") {
            return uri.lastPathSegment
        }
        // 对于 content:// URI，查询 DISPLAY_NAME
        if (uri.scheme == "content") {
            activity.contentResolver.query(
                uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        return cursor.getString(nameIndex)
                    }
                }
            }
        }
        return uri.lastPathSegment
    }

    private fun resolveFilePath(uri: Uri): String? {
        // 对于 file:// scheme，直接返回路径
        if (uri.scheme == "file") {
            val path = uri.path
            if (path != null && File(path).exists()) {
                return path
            }
        }
        // 对于 content:// scheme 或 file:// 无法直接访问时，复制到缓存
        return try {
            val fileName = fileNameFromUri(uri) ?: "imported.ecpkg"
            val tempFile = File(activity.cacheDir, fileName)
            activity.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
