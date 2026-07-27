package com.venti1112.edgecube.channels

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import io.flutter.plugin.common.MethodChannel

/**
 * 运行时权限的申请与回调分发。
 *
 * Android 的权限申请结果经 Activity.onRequestPermissionsResult 回调返回，
 * 与发起申请的 MethodChannel 调用不在同一栈上，故须在此暂存 pending result，
 * 待回调后兑现。所有申请共用一套 requestCode（REQ_*）。
 */
class PermissionsController(private val activity: Activity) {

    companion object {
        /** 启动权限链第一步：通知权限（Android 13+）。 */
        private const val REQ_NOTIFICATIONS = 1001
        /** 照片权限（READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE）。 */
        private const val REQ_PHOTO = 1002
        /** 旧版外部存储读写权限（Android 10-）。 */
        private const val REQ_STORAGE = 1003
        /** 启动权限链第二步：本地网络权限（Android 17+）。 */
        private const val REQ_LOCAL_NETWORK = 1004
    }

    private var pendingPhotoResult: MethodChannel.Result? = null
    private var pendingStorageResult: MethodChannel.Result? = null
    private var pendingStartupResult: MethodChannel.Result? = null

    /** [Activity.onRequestPermissionsResult] 的分发入口，由 MainActivity 转调。 */
    fun onRequestPermissionsResult(requestCode: Int) {
        when (requestCode) {
            REQ_NOTIFICATIONS -> {
                requestLocalNetworkPermission()
            }
            REQ_PHOTO -> {
                pendingPhotoResult?.success(hasPhotoPermission())
                pendingPhotoResult = null
            }
            REQ_STORAGE -> {
                pendingStorageResult?.success(hasStorageAccess())
                pendingStorageResult = null
            }
            REQ_LOCAL_NETWORK -> {
                pendingStartupResult?.success(null)
                pendingStartupResult = null
            }
        }
    }

    // —— 启动权限链（通知 → 本地网络）——

    /** 由 Dart 端在用户同意用户协议后调用，依次请求通知权限与本地网络权限。 */
    fun requestStartupPermissions(result: MethodChannel.Result) {
        if (pendingStartupResult != null) {
            result.success(null)
            return
        }
        pendingStartupResult = result
        requestPostNotifications()
    }

    /** 请求通知权限（Android 13+）；授权后自动接着请求本地网络权限。 */
    private fun requestPostNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                activity.requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATIONS,
                )
                return
            }
        }
        requestLocalNetworkPermission()
    }

    /** Android 17+ 需要 ACCESS_LOCAL_NETWORK 权限才能访问局域网（Minecraft 服务端、FTP、SSH、UPnP）。 */
    private fun requestLocalNetworkPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
            Build.VERSION.SDK_INT_FULL >= Build.VERSION_CODES_FULL.CINNAMON_BUN_1
        ) {
            if (activity.checkSelfPermission(android.Manifest.permission.ACCESS_LOCAL_NETWORK)
                != PackageManager.PERMISSION_GRANTED
            ) {
                activity.requestPermissions(
                    arrayOf(android.Manifest.permission.ACCESS_LOCAL_NETWORK),
                    REQ_LOCAL_NETWORK,
                )
                return
            }
        }
        pendingStartupResult?.success(null)
        pendingStartupResult = null
    }

    // —— 外部存储 ——

    /** 是否已获得外部存储访问权（R+ 为所有文件访问权，旧版为读写权限）。 */
    fun hasStorageAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            activity.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /**
     * 申请外部存储访问权。R+ 跳转「所有文件访问权」设置页（无回调，立即返回 null）；
     * M–Q 弹系统权限对话框（结果经回调兑现）。
     */
    fun requestStorageAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            result.success(null)
            try {
                val intent = android.content.Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    android.net.Uri.parse("package:${activity.packageName}"),
                )
                activity.startActivity(intent)
            } catch (e: Exception) {
                activity.startActivity(
                    android.content.Intent(
                        android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION,
                    ),
                )
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingStorageResult = result
            activity.requestPermissions(
                arrayOf(
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                ),
                REQ_STORAGE,
            )
        } else {
            result.success(true)
        }
    }

    // —— 照片 ——

    /** 是否已获得照片读取权限（13+ 为 READ_MEDIA_IMAGES，旧版为 READ_EXTERNAL_STORAGE）。 */
    fun hasPhotoPermission(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                activity.checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) ==
                    PackageManager.PERMISSION_GRANTED
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                activity.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                    PackageManager.PERMISSION_GRANTED
            else -> true
        }
    }

    /** 申请照片读取权限；结果（布尔）经回调兑现。 */
    fun requestPhotoPermission(result: MethodChannel.Result) {
        if (hasPhotoPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (pendingPhotoResult != null) {
            result.error("REQUEST_PENDING", "已有照片权限请求正在进行", null)
            return
        }
        pendingPhotoResult = result
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_IMAGES
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }
        activity.requestPermissions(arrayOf(permission), REQ_PHOTO)
    }
}
