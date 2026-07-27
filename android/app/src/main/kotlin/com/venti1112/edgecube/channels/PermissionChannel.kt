package com.venti1112.edgecube.channels

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 启动权限通道：由 Dart 端在用户同意用户协议后调用，
 * 依次请求通知权限与本地网络权限（见 [PermissionsController]）。
 */
internal object PermissionChannel {

    private const val CHANNEL = "com.venti1112.edgecube/permission"

    fun register(messenger: BinaryMessenger, permissions: PermissionsController) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStartupPermissions" -> permissions.requestStartupPermissions(result)
                else -> result.notImplemented()
            }
        }
    }
}
