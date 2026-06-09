package com.venti1112.edgecube

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 在应用模块内直接实现「管理全部文件」权限的查询与申请。
 *
 * 用 MethodChannel 而非第三方插件，避免依赖会触发旧版 Kotlin Gradle Plugin
 * 的库——这些库在 Flutter 内置 Kotlin 下无法构建。
 */
class MainActivity : FlutterActivity() {
    private val channel = "com.venti1112.edgecube/storage"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGranted" -> result.success(isGranted())
                    "request" -> {
                        requestAccess()
                        result.success(null)
                    }
                    "externalStorageRoot" ->
                        result.success(Environment.getExternalStorageDirectory()?.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    private fun isGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            // 低版本由运行时权限处理，此处视为已具备访问能力。
            true
        }
    }

    private fun requestAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        // 优先跳转到本应用的「所有文件访问权限」页；失败则退回到列表页。
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }
}
