package com.venti1112.edgecube.server

import android.content.Context
import android.os.Build
import android.system.Os
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * 将内置于 assets 的 JRE（FCL 产物，tar.xz）按设备架构解压到应用私有目录，并按版本号校验。
 *
 * assets 布局：
 *   assets/runtimes/<version>/universal.tar.xz      架构无关部分
 *   assets/runtimes/<version>/bin-<arch>.tar.xz      架构相关部分（arm/arm64/x86_64）
 *   assets/runtimes/<version>/version                版本号（单行整数）
 *
 * 解压目标：filesDir/runtimes/<version>/
 */
object RuntimeInstaller {

    private const val ASSET_ROOT = "runtimes"

    /** 全部内置版本，与 assets 子目录名一致。 */
    val ALL_VERSIONS = listOf("jre8", "jre17", "jre21", "jre25")

    fun runtimesDir(context: Context): File = File(context.filesDir, "runtimes")

    fun jreDir(context: Context, version: String): File =
        File(runtimesDir(context), version)

    /** 当前进程架构对应的 JRE 架构名（与 bin-<arch> 命名一致）。 */
    fun deviceArch(): String {
        for (abi in Build.SUPPORTED_ABIS) {
            when (abi) {
                "arm64-v8a" -> return "arm64"
                "armeabi-v7a" -> return "arm"
                "x86_64" -> return "x86_64"
            }
        }
        return "arm64"
    }

    private fun assetExists(context: Context, path: String): Boolean = try {
        context.assets.open(path).use { true }
    } catch (e: Exception) {
        false
    }

    /** 当前架构下可用（assets 中确有对应 bin 与 universal）的版本列表。 */
    fun availableVersions(context: Context): List<String> {
        val arch = deviceArch()
        return ALL_VERSIONS.filter { v ->
            assetExists(context, "$ASSET_ROOT/$v/universal.tar.xz") &&
                assetExists(context, "$ASSET_ROOT/$v/bin-$arch.tar.xz")
        }
    }

    /** 读取 assets 中某版本的版本号；不存在返回 null。 */
    private fun assetVersion(context: Context, version: String): String? = try {
        context.assets.open("$ASSET_ROOT/$version/version").use {
            it.readBytes().toString(Charsets.UTF_8).trim()
        }
    } catch (e: Exception) {
        null
    }

    /** 该版本是否已按最新版本号解压就位。 */
    fun isInstalled(context: Context, version: String): Boolean {
        val assetVer = assetVersion(context, version) ?: return false
        val installedFile = File(jreDir(context, version), "version")
        if (!installedFile.exists()) return false
        val installed = installedFile.readText().trim()
        return installed.isNotEmpty() && installed == assetVer
    }

    /**
     * 解压安装指定版本（先清空旧目录），按设备架构选取 bin。耗时操作，请在后台线程调用。
     * [onProgress] 回调已处理条目数（可空）。
     */
    fun install(context: Context, version: String, onProgress: ((Long) -> Unit)? = null) {
        val assetVer = assetVersion(context, version)
            ?: throw IllegalStateException("assets 中缺少 $version 的 version 文件")
        val arch = deviceArch()
        val archAsset = "$ASSET_ROOT/$version/bin-$arch.tar.xz"
        if (!assetExists(context, archAsset)) {
            throw IllegalStateException("$version 不支持当前架构 $arch")
        }

        val target = jreDir(context, version)
        target.deleteRecursively()
        target.mkdirs()

        var count = 0L
        val tick: () -> Unit = { count++; onProgress?.invoke(count) }

        context.assets.open("$ASSET_ROOT/$version/universal.tar.xz").use {
            extractTarXz(it, target, tick)
        }
        context.assets.open(archAsset).use {
            extractTarXz(it, target, tick)
        }

        // 最后写版本号，作为“解压完整”的标记。
        File(target, "version").writeText(assetVer)
    }

    private fun extractTarXz(input: InputStream, dest: File, onEntry: () -> Unit) {
        TarArchiveInputStream(XZCompressorInputStream(BufferedInputStream(input))).use { tar ->
            val buf = ByteArray(8192)
            var entry = tar.nextTarEntry
            while (entry != null) {
                val name = entry.name.removePrefix("./")
                if (name.isNotEmpty()) {
                    val outFile = File(dest, name)
                    when {
                        entry.isSymbolicLink -> {
                            outFile.parentFile?.mkdirs()
                            outFile.delete()
                            // OpenJDK 内的符号链接多为同目录相对（如 libfoo.so.6 -> libfoo.so）。
                            try {
                                Os.symlink(entry.linkName, outFile.absolutePath)
                            } catch (_: Throwable) {
                            }
                        }
                        entry.isDirectory -> {
                            outFile.mkdirs()
                            outFile.setExecutable(true, false)
                        }
                        else -> {
                            outFile.parentFile?.mkdirs()
                            // 已存在且大小一致则跳过（断点续装容错）。
                            if (!outFile.exists() || outFile.length() != entry.size) {
                                FileOutputStream(outFile).use { os ->
                                    var n = tar.read(buf)
                                    while (n != -1) {
                                        os.write(buf, 0, n)
                                        n = tar.read(buf)
                                    }
                                }
                            }
                            // bin/ 下为工具可执行文件，给执行位（我们走 liblaunch，但保险）。
                            if (name.startsWith("bin/")) outFile.setExecutable(true, false)
                        }
                    }
                }
                onEntry()
                entry = tar.nextTarEntry
            }
        }
    }
}
