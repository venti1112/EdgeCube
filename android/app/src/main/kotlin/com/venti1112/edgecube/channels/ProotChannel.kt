package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.proot.ProotDns
import com.venti1112.edgecube.proot.ProotRootfs
import com.venti1112.edgecube.proot.RootfsManifest
import com.venti1112.edgecube.proot.RootfsStore
import com.venti1112.edgecube.security.PackageSignatureVerifier
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * proot 容器通道：rootfs 导入、列表、删除。
 *
 * 与 runtime 通道分离：rootfs 包（裸 tar 或 ZIP/.ecpkg 包装）的
 * 校验/解压/布局逻辑由 proot 包独立实现。
 */
internal object ProotChannel {

    private const val CHANNEL = "com.venti1112.edgecube/proot"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "listRootfs" -> {
                    // 即便有缓存，遍历目录 + 读元数据文件仍可能在 rootfs
                    // 数量多时造成主线程卡顿，放后台线程执行。
                    ChannelIo.runAsync(result, "PROOT_LIST_FAILED") {
                        RootfsStore.installedRootfs(context).map { rootfsToMap(it) }
                    }
                }

                "importRootfs" -> {
                    val path = call.argument<String>("path")
                    val id = call.argument<String>("id")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        // 解压可能耗时数十秒到数分钟，放后台线程。
                        // ROOTFS_EXISTS 等业务错误用语义化 code，便于 UI 区分。
                        ChannelIo.runAsync(
                            result,
                            "PROOT_IMPORT_FAILED",
                            errorCodeOf = { e ->
                                e.message?.takeIf { it == "ROOTFS_EXISTS" } ?: "PROOT_IMPORT_FAILED"
                            },
                        ) {
                            rootfsToMap(RootfsStore.importRootfs(context, path, id))
                        }
                    }
                }

                "deleteRootfs" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("BAD_ARGS", "缺少 id", null)
                    } else {
                        // deleteRecursively 需遍历几万文件，放后台线程避免 UI 卡顿。
                        ChannelIo.runAsync(result, "PROOT_DELETE_FAILED") {
                            RootfsStore.deleteRootfs(context, id)
                            null
                        }
                    }
                }

                // 检查 proot 二进制是否已随 APK 打包（jniLibs 是否含 lib__bin__proot-classic__.so）。
                // UI 据此决定是否显示 proot 入口与提示用户安装原生库。
                "isProotAvailable" -> {
                    val nativeDir = context.applicationInfo.nativeLibraryDir
                    val prootSo = File(nativeDir, "lib__bin__proot-classic__.so")
                    result.success(prootSo.exists())
                }

                // 更新所有已安装 proot rootfs 的 /etc/resolv.conf。
                // 用户在「网络设置」中更改 DNS 后立即调用，无需重启实例。
                "updateProotDns" -> {
                    ChannelIo.runAsync(result, "DNS_UPDATE_FAILED") {
                        ProotDns.updateAllRootfsDns(context)
                        null
                    }
                }

                "verifyRootfsSignature" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        ChannelIo.runAsync(result, "SIGNATURE_VERIFY_FAILED") {
                            if (PackageSignatureVerifier.isZipFile(path)) {
                                PackageSignatureVerifier.verifyZip(context, path).toMap()
                            } else {
                                // 旧格式裸 tar 包（非 ZIP），无内嵌签名。
                                mapOf("hasSignature" to false, "valid" to false)
                            }
                        }
                    }
                }

                // 判断文件是否为 rootfs 包（ZIP/.ecpkg 内含 rootfs.tar.zst 等 tar 条目）。
                // .ecpkg 文件关联打开时用于区分 rootfs 包与运行时包。
                "isRootfsPackage" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        ChannelIo.runAsync(result, "PROOT_PACKAGE_PROBE_FAILED") {
                            RootfsStore.isRootfsPackage(path)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * 把 rootfs 信息与内嵌清单字段平铺为一个 Map 返回给 Dart 端。
     * manifest 为 null（无清单文件）时所有清单字段给安全默认值，
     * 调用方据此把 rootfs 视为 generic 纯容器。
     * 大小不在此返回——由 Dart 端在 isolate 中实时计算（rootfs 含数万文件，
     * 但放在 isolate 中不会卡 UI，且能避免缓存与实际不一致）。
     */
    private fun rootfsToMap(r: ProotRootfs): Map<String, Any?> {
        val m = r.manifest
        return mapOf(
            "id" to r.id,
            "dir" to r.dir.absolutePath,
            "envType" to (m?.envType ?: RootfsManifest.ENV_GENERIC),
            "envName" to (m?.envName ?: ""),
            "envVersionName" to (m?.envVersionName ?: ""),
            "envMainBin" to (m?.envMainBin ?: ""),
            "envArgs" to (m?.envArgs ?: emptyList<String>()),
            "serverFileHint" to (m?.serverFileHint ?: ""),
            "description" to (m?.description ?: ""),
            "buildDate" to (m?.buildDate ?: ""),
            "isGeneric" to r.isGeneric,
        )
    }
}
