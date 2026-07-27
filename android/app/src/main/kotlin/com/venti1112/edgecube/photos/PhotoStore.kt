package com.venti1112.edgecube.photos

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

/**
 * 相册访问：MediaStore 图片枚举、缩略图/原图读取与复制到应用缓存。
 * 权限校验由调用方（照片通道）负责。
 */
object PhotoStore {

    /** 枚举设备上的全部图片（按修改时间倒序），返回可直接回传 Dart 的 Map 列表。 */
    fun queryPhotos(context: Context): List<Map<String, Any?>> {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
        )
        val photos = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_MODIFIED} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                photos.add(
                    mapOf(
                        "id" to id,
                        "uri" to uri,
                        "name" to cursor.getString(nameColumn),
                        "size" to cursor.getLong(sizeColumn),
                        "modified" to cursor.getLong(modifiedColumn),
                        "width" to cursor.getInt(widthColumn),
                        "height" to cursor.getInt(heightColumn),
                    ),
                )
            }
        }
        return photos
    }

    /** 读取图片原始字节（不缩放不转码）。 */
    fun readOriginalBytes(context: Context, uriString: String): ByteArray {
        val uri = Uri.parse(uriString)
        return ByteArrayOutputStream().use { output ->
            context.contentResolver.openInputStream(uri)?.use { input ->
                input.copyTo(output)
            } ?: throw IllegalArgumentException("无法打开图片")
            output.toByteArray()
        }
    }

    /** 读取图片缩略图（最长边不超过 [maxSize]），JPEG 编码。 */
    fun readThumbnailBytes(context: Context, uriString: String, maxSize: Int): ByteArray {
        val uri = Uri.parse(uriString)
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(uri, Size(maxSize, maxSize), null)
        } else {
            decodeScaledBitmap(context, uri, maxSize)
        }
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)
            output.toByteArray()
        }
    }

    private fun decodeScaledBitmap(context: Context, uri: Uri, maxSize: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, bounds)
        }
        val largest = maxOf(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
        var sampleSize = 1
        while (largest / sampleSize > maxSize) sampleSize *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        context.contentResolver.openInputStream(uri)?.use { input ->
            return BitmapFactory.decodeStream(input, null, options)
                ?: throw IllegalArgumentException("无法解码图片")
        }
        throw IllegalArgumentException("无法打开图片")
    }

    /** 把图片复制到应用缓存目录，返回缓存文件的绝对路径。 */
    fun copyToCache(context: Context, uriString: String, name: String?): String {
        val uri = Uri.parse(uriString)
        val safeName = (name ?: "photo").replace(Regex("[^A-Za-z0-9._-]"), "_")
        val suffix = File(safeName).extension.let { if (it.isNotEmpty()) ".$it" else ".jpg" }
        val target = File.createTempFile("selected_photo_", suffix, context.cacheDir)
        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        } ?: throw IllegalArgumentException("无法打开图片")
        return target.absolutePath
    }
}
