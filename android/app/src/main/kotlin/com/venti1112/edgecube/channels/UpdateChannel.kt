package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.update.ApkInstaller
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * APK 更新通道：安装 APK 与签名验证（实现见 [ApkInstaller]）。
 */
internal object UpdateChannel {

    private const val CHANNEL = "com.venti1112.edgecube/update"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath == null) {
                        result.error("BAD_ARGS", "缺少 apkPath", null)
                    } else {
                        try {
                            ApkInstaller.install(context, apkPath)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
                "verifySignature" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath == null) {
                        result.error("BAD_ARGS", "缺少 apkPath", null)
                    } else {
                        try {
                            val match = ApkInstaller.verifyApkSignature(context, apkPath)
                            result.success(match)
                        } catch (e: Exception) {
                            result.error("SIGNATURE_VERIFY_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
