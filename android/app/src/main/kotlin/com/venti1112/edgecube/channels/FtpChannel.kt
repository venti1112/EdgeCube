package com.venti1112.edgecube.channels

import com.venti1112.edgecube.ftp.FtpServerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * FTP 文件管理通道：对外开放指定根目录的 FTP 访问（实现见 [FtpServerManager]）。
 */
internal object FtpChannel {

    private const val CHANNEL = "com.venti1112.edgecube/ftp"

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val rootDir = call.argument<String>("rootDir")
                    val port = call.argument<Int>("port")
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val writable = call.argument<Boolean>("writable") ?: true
                    val ipv6Enabled = call.argument<Boolean>("ipv6Enabled") ?: false
                    if (rootDir == null || port == null) {
                        result.error("BAD_ARGS", "缺少 rootDir/port", null)
                    } else {
                        try {
                            FtpServerManager.start(
                                rootDir, port, username, password, writable, ipv6Enabled,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FTP_START_FAILED", e.message, null)
                        }
                    }
                }
                "stop" -> {
                    FtpServerManager.stop()
                    result.success(null)
                }
                "isRunning" -> {
                    result.success(FtpServerManager.isRunning)
                }
                else -> result.notImplemented()
            }
        }
    }
}
