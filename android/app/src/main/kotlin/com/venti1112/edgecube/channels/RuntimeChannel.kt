package com.venti1112.edgecube.channels

import android.content.Context
import android.os.Build
import android.os.Environment
import com.venti1112.edgecube.security.PackageSignatureVerifier
import com.venti1112.edgecube.server.EcManifest
import com.venti1112.edgecube.server.RuntimeInstaller
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.server.TunnelProcessManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 运行环境通道：已安装 `.ecpkg` 运行时的发现、导入与删除
 * （实现见 [RuntimeInstaller]）。
 */
internal object RuntimeChannel {

    private const val CHANNEL = "com.venti1112.edgecube/runtime"

    fun register(messenger: BinaryMessenger, context: Context) {
        val serverManager = ServerProcessManager.getInstance(context)
        val tunnelManager = TunnelProcessManager.getInstance(context)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedRuntimes" -> {
                    val list = RuntimeInstaller.installedRuntimes(context).map { manifestToMap(it) }
                    result.success(list)
                }

                "importPackage" -> {
                    val path = call.argument<String>("path")
                    val force = call.argument<Boolean>("force") ?: false
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        // 解压耗时，放后台线程。
                        ChannelIo.runAsync(result, "IMPORT_FAILED") {
                            val manifest = RuntimeInstaller.importPackage(context, path, force = force)
                            manifestToMap(manifest)
                        }
                    }
                }

                "deleteRuntime" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("BAD_ARGS", "缺少 id", null)
                    } else {
                        RuntimeInstaller.deleteRuntime(context, id)
                        result.success(null)
                    }
                }

                "isRuntimeRunning" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("BAD_ARGS", "缺少 id", null)
                    } else {
                        val serverRunning = serverManager.activeRuntimeId == id
                        val tunnelRunning = tunnelManager.isRunning &&
                            RuntimeInstaller.installedFrpc(context)?.id == id
                        result.success(serverRunning || tunnelRunning)
                    }
                }

                // 返回当前设备架构标识符（aarch64 / arm / x86_64），无匹配时返回空串。
                "deviceArch" -> {
                    var arch = ""
                    for (abi in Build.SUPPORTED_ABIS) {
                        arch = when (abi) {
                            "arm64-v8a" -> "aarch64"
                            "armeabi-v7a" -> "arm"
                            "x86_64" -> "x86_64"
                            else -> continue
                        }
                        break
                    }
                    result.success(arch)
                }

                "getDownloadDir" -> {
                    val base = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        context.getExternalFilesDir(null)
                    else
                        Environment.getExternalStorageDirectory()
                    val dir = File(base, "Download/EdgeCube")
                    if (!dir.exists()) dir.mkdirs()
                    result.success(dir.absolutePath)
                }

                "verifyEcpkgSignature" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        ChannelIo.runAsync(result, "SIGNATURE_VERIFY_FAILED") {
                            PackageSignatureVerifier.verifyZip(context, path).toMap()
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /** 把 `.ecpkg` 清单平铺为一个 Map 返回给 Dart 端（可空字段给空串）。 */
    private fun manifestToMap(m: EcManifest): Map<String, Any?> = mapOf(
        "id" to m.id,
        "type" to m.type,
        "name" to m.name,
        "version" to m.version,
        "versionName" to (m.versionName ?: ""),
        "description" to (m.description ?: ""),
        "author" to (m.author ?: ""),
        "homepage" to (m.homepage ?: ""),
        "repository" to (m.repository ?: ""),
        "updateUrl" to (m.updateUrl ?: ""),
        "minAppVersion" to m.minAppVersion,
    )
}
