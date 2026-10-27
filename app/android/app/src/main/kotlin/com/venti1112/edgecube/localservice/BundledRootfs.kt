package com.venti1112.edgecube.localservice

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream

/**
 * APK 内置 rootfs 的安装与完整性检查。
 *
 * 默认不解压：第一次点「启动本地服务」时才从 assets 取出 `rootfs-arm64-v8a.tar.zst`
 * 解压到 `filesDir/local-service/rootfs/<version>`。之后每次启动只做标记 +
 * 关键文件检查；标记缺失、版本不符或目录损坏都会重新解压。
 *
 * 版本目录与 `local-service/data` 分离：重新解压不会碰用户的服务端数据。
 */
object BundledRootfs {

    private const val ASSET_DIR = "rootfs"
    private const val INFO_ASSET = "$ASSET_DIR/rootfs-info.json"

    /** 解压完整性的关键文件；全部存在才认为 rootfs 可用。 */
    private val SENTINELS = listOf(
        "usr/bin/env",
        "usr/bin/dash",
        "etc/os-release",
        "usr/lib/aarch64-linux-gnu/libc.so.6",
        "etc/ssl/certs/ca-certificates.crt",
    )

    data class Info(
        val version: String,
        val sha256: String,
        val asset: String,
    )

    /** 读取构建期生成的 rootfs 元信息（版本 + 压缩包名 + sha256）。 */
    fun readInfo(context: Context): Info {
        val raw = try {
            context.assets.open(INFO_ASSET).use { it.readBytes().toString(Charsets.UTF_8) }
        } catch (_: FileNotFoundException) {
            throw IllegalStateException(
                "APK 中没有本地环境包（assets/$INFO_ASSET）。" +
                    "请检查构建时是否拉取了 rootfs 资产。",
            )
        }
        val json = JSONObject(raw)
        val version = json.optString("version")
        val asset = json.optString("asset")
        if (version.isBlank() || asset.isBlank()) {
            throw IllegalStateException("本地环境元信息不完整：$raw")
        }
        return Info(
            version = version,
            sha256 = json.optString("sha256"),
            asset = asset,
        )
    }

    fun installedDir(context: Context, info: Info): File =
        File(LocalServicePaths.rootfsBaseDir(context), info.version)

    /** 不触发解压的快速检查，供 UI 显示「环境已就绪」。 */
    fun isPrepared(context: Context): Boolean = try {
        val info = readInfo(context)
        hasMarker(context, info) && isHealthy(installedDir(context, info))
    } catch (_: Throwable) {
        false
    }

    /**
     * 确保 rootfs 可用；需要时解压。耗时操作，必须在后台线程调用。
     *
     * @param onMessage 面向 UI 的阶段提示（「正在解压本地环境…」）
     * @param onLog     proot/tar 的输出行，进日志框
     */
    fun ensureInstalled(
        context: Context,
        onMessage: (String) -> Unit,
        onLog: (String) -> Unit,
    ): File {
        val info = readInfo(context)
        val target = installedDir(context, info)
        if (hasMarker(context, info) && isHealthy(target)) {
            onMessage("本地环境已就绪")
            return target
        }

        ProotBootstrap.ensureBootstrap(context)

        // 旧目录要么不完整、要么版本已变，直接清掉重建
        if (target.exists() && !target.deleteRecursively()) {
            throw IllegalStateException("无法清理损坏的本地环境：${target.absolutePath}")
        }
        val tmp = File(LocalServicePaths.rootfsBaseDir(context), ".${info.version}.tmp")
        tmp.deleteRecursively()
        tmp.mkdirs()
        LocalServicePaths.installMarker(context).delete()

        val cached = File(context.cacheDir, "rootfs-${info.version}.tar.zst")
        try {
            onMessage("正在准备本地环境…")
            copyAsset(context, info.asset, cached)

            onMessage("正在解压本地环境（首次启动需要几分钟）…")
            extract(context, cached, tmp, onLog)

            onMessage("正在校验本地环境…")
            val missing = SENTINELS.filterNot { File(tmp, it).isFile }
            if (missing.isNotEmpty()) {
                throw IllegalStateException(
                    "本地环境解压不完整，缺少：${missing.joinToString()}",
                )
            }
            ProotDns.ensureResolvConf(context, tmp)

            if (!tmp.renameTo(target)) {
                target.deleteRecursively()
                if (!tmp.renameTo(target)) {
                    throw IllegalStateException("无法安装本地环境到 ${target.absolutePath}")
                }
            }
            writeMarker(context, info)
            cleanupOldVersions(context, target)
            onMessage("本地环境已就绪")
            return target
        } catch (e: Throwable) {
            tmp.deleteRecursively()
            throw e
        } finally {
            cached.delete()
        }
    }

    private fun copyAsset(context: Context, assetName: String, dest: File) {
        try {
            context.assets.open("$ASSET_DIR/$assetName").use { input ->
                FileOutputStream(dest).use { output ->
                    input.copyTo(output, 1024 * 1024)
                }
            }
        } catch (e: FileNotFoundException) {
            throw IllegalStateException(
                "APK 中没有本地环境包（assets/$ASSET_DIR/$assetName）。" +
                    "请检查构建时是否拉取了 rootfs 资产。",
                e,
            )
        }
    }

    private fun extract(context: Context, tarball: File, dest: File, onLog: (String) -> Unit) {
        val bootstrapBin = File(ProotBootstrap.bootstrapDir(context), "bin")
        val argv = listOf(
            File(bootstrapBin, "proot").absolutePath,
            // Android 文件系统上把硬链接转成符号链接
            "--link2symlink",
            File(bootstrapBin, "tar").absolutePath,
            "-xf",
            tarball.absolutePath,
            "-C",
            dest.absolutePath,
            "--delay-directory-restore",
            "--preserve-permissions",
        )
        val builder = ProcessBuilder(argv).redirectErrorStream(true)
        builder.environment().clear()
        builder.environment().putAll(ProotBootstrap.baseHostEnv(context))
        val process = builder.start()

        val tail = ArrayDeque<String>()
        process.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
            while (true) {
                val line = reader.readLine() ?: break
                onLog(line)
                tail.addLast(line)
                while (tail.size > 40) tail.removeFirst()
            }
        }
        val code = process.waitFor()
        if (code != 0) {
            val detail = tail.joinToString(" | ").ifBlank { "无输出" }
            throw IllegalStateException("解压本地环境失败（退出码 $code）：$detail")
        }
    }

    private fun isHealthy(dir: File): Boolean =
        dir.isDirectory && SENTINELS.all { File(dir, it).isFile }

    private fun hasMarker(context: Context, info: Info): Boolean {
        val raw = try {
            LocalServicePaths.installMarker(context).readText()
        } catch (_: Throwable) {
            return false
        }
        return try {
            val json = JSONObject(raw)
            json.optString("version") == info.version &&
                (info.sha256.isBlank() || json.optString("sha256") == info.sha256)
        } catch (_: Throwable) {
            false
        }
    }

    private fun writeMarker(context: Context, info: Info) {
        val json = JSONObject()
            .put("version", info.version)
            .put("sha256", info.sha256)
            .put("installedAtMs", System.currentTimeMillis())
        LocalServicePaths.installMarker(context).writeText(json.toString())
    }

    private fun cleanupOldVersions(context: Context, keep: File) {
        val base = LocalServicePaths.rootfsBaseDir(context)
        for (child in base.listFiles().orEmpty()) {
            if (child == keep) continue
            if (child.name.startsWith(".")) {
                child.deleteRecursively()
            } else if (child.isDirectory) {
                child.deleteRecursively()
            }
        }
    }
}
