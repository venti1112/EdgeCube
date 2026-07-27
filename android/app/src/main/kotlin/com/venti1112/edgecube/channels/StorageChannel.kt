package com.venti1112.edgecube.channels

import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 存储通道：外部存储权限、根路径、分区容量与应用自身占用。
 */
internal object StorageChannel {

    private const val CHANNEL = "com.venti1112.edgecube/storage"

    fun register(
        messenger: BinaryMessenger,
        context: Context,
        permissions: PermissionsController,
    ) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(permissions.hasStorageAccess())
                "request" -> permissions.requestStorageAccess(result)
                "externalStorageRoot" ->
                    result.success(Environment.getExternalStorageDirectory()?.absolutePath)
                "getStorageStats" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        try {
                            val stat = StatFs(path)
                            val total = stat.totalBytes
                            val available = stat.availableBytes
                            result.success(
                                mapOf(
                                    "totalBytes" to total,
                                    "availableBytes" to available,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("STAT_FAILED", e.message, null)
                        }
                    }
                }
                "getAppSize" -> {
                    try {
                        val pm = context.packageManager
                        val info = pm.getPackageInfo(context.packageName, 0)
                        val apkSize = File(info.applicationInfo!!.sourceDir).length()
                        var nativeLibSize = 0L
                        val nativeLibDir = File(info.applicationInfo!!.nativeLibraryDir)
                        if (nativeLibDir.exists()) {
                            nativeLibDir.walkTopDown().filter { it.isFile }
                                .forEach { nativeLibSize += it.length() }
                        }
                        result.success(
                            mapOf(
                                "apkSize" to apkSize,
                                "nativeLibSize" to nativeLibSize,
                                "totalSize" to (apkSize + nativeLibSize),
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("APP_SIZE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
