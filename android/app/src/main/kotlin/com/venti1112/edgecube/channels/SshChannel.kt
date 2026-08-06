package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.ssh.SshServerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * SSH 服务通道：同一 SSH 服务器同时提供 SFTP 文件访问与 SSH 终端，
 * 与 FTP 独立（实现见 [SshServerManager]）。
 */
internal object SshChannel {

    private const val CHANNEL = "com.venti1112.edgecube/ssh"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val rootDir = call.argument<String>("rootDir")
                    val port = call.argument<Int>("port")
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val writable = call.argument<Boolean>("writable") ?: true
                    val sftpEnabled = call.argument<Boolean>("sftpEnabled") ?: true
                    val shellEnabled = call.argument<Boolean>("shellEnabled") ?: true
                    val ipv6Enabled = call.argument<Boolean>("ipv6Enabled") ?: false
                    if (rootDir == null || port == null) {
                        result.error("BAD_ARGS", "缺少 rootDir/port", null)
                    } else {
                        // 首次启动需生成 RSA 主机密钥（数百 ms），放后台线程；完成后回主线程返回。
                        ChannelIo.runAsync(
                            result,
                            "SSH_START_FAILED",
                            errorCodeOf = { e ->
                                // Android < 8.0 时 SSHD 无法运行，映射为语义化 code 供 UI 提示。
                                if (e.message == "SSH_NEEDS_API26") "SSH_NEEDS_API26" else "SSH_START_FAILED"
                            },
                        ) {
                            SshServerManager.start(
                                context, rootDir, port, username, password,
                                writable, sftpEnabled, shellEnabled, ipv6Enabled,
                            )
                            true
                        }
                    }
                }
                "stop" -> {
                    SshServerManager.stop()
                    result.success(null)
                }
                "isRunning" -> {
                    result.success(SshServerManager.isRunning)
                }
                "hostKeyFingerprint" -> {
                    // 首次可能需生成主机密钥（数百 ms），放后台线程；完成后回主线程返回。
                    ChannelIo.runAsync(result, "SSH_FP_FAILED") {
                        SshServerManager.hostKeyFingerprint(context)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
