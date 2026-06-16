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
import java.nio.file.Files
import java.util.zip.GZIPInputStream

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
    val ALL_VERSIONS = listOf("jre17", "jre21", "jre25")

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

    // ──────────────────────────────────────────────────────
    // PHP 运行时（PocketMine）：tgz 格式的 embed SAPI 共享库发行版
    //   assets/runtimes/<version>/bin_<arch>.tgz    （当前仅 arm64）
    //   内部布局（tgz 内有 php-runtime/bin/php7/ 前缀，解压时自动剥离）：
    //     lib/libphp.so + libphpwrapper.so + php.ini 等
    //   通过 dlopen libphpwrapper.so → php_run() 运行 PHP 脚本
    // 解压目标：filesDir/runtimes/<version>/
    // ──────────────────────────────────────────────────────
        
    /** PHP wrapper 库在解压后的相对路径（被 libphploader.so dlopen）。 */
    private const val PHP_WRAPPER_REL = "lib/libphpwrapper.so"
        
    /** 全部内置 PHP 运行时版本，与 assets 子目录名一致。 */
    val ALL_PHP_VERSIONS = listOf("php8.2")
        
    /** PHP wrapper 库的完整路径（供 libphploader.so 通过 EC_PHP_LIB 加载）。 */
    fun phpLib(context: Context, version: String): File =
        File(jreDir(context, version), PHP_WRAPPER_REL)
        
    /** PHP lib 目录路径（供 LD_LIBRARY_PATH 使用，libphp.so 在此目录）。 */
    fun phpLibDir(context: Context, version: String): File =
        File(jreDir(context, version), "lib")
        
    /** 当前架构下可用（assets 中确有对应 bin_<arch>.tgz）的 PHP 运行时版本列表。 */
    fun availablePhpRuntimes(context: Context): List<String> {
        val arch = deviceArch()
        return ALL_PHP_VERSIONS.filter { v ->
            assetExists(context, "$ASSET_ROOT/$v/bin_$arch.tgz")
        }
    }
        
    /** 该 PHP 版本是否已按最新版本号解压就位（version 文件存在且与 assets 一致）。 */
    fun isPhpInstalled(context: Context, version: String): Boolean {
        val assetVer = assetVersion(context, version) ?: return false
        val installedFile = File(jreDir(context, version), "version")
        if (!installedFile.exists()) return false
        val installed = installedFile.readText().trim()
        return installed.isNotEmpty() && installed == assetVer
    }
        
    /**
     * 解压安装指定 PHP 版本（先清空旧目录），按设备架构选取 bin_<arch>.tgz 并解压
     * 到私有目录。耗时操作，请在后台线程调用。
     */
    fun installPhp(context: Context, version: String) {
        val assetVer = assetVersion(context, version)
            ?: throw IllegalStateException("assets 中缺少 $version 的 version 文件")
        val arch = deviceArch()
        val asset = "$ASSET_ROOT/$version/bin_$arch.tgz"
        if (!assetExists(context, asset)) {
            throw IllegalStateException("$version 不支持当前架构 $arch")
        }
        
        val target = jreDir(context, version)
        target.deleteRecursively()
        target.mkdirs()
        
        // tgz 内部有 php-runtime/bin/php7/ 前缀，解压时剥离
        val stripPrefix = "php-runtime/bin/php7/"
        
        context.assets.open(asset).use { input ->
            TarArchiveInputStream(GZIPInputStream(BufferedInputStream(input))).use { tar ->
                val buf = ByteArray(8192)
                var entry = tar.nextTarEntry
                while (entry != null) {
                    val raw = entry.name.removePrefix("./")
                    val name = raw.removePrefix(stripPrefix)
                    if (name.isNotEmpty() && !entry.isDirectory) {
                        val outFile = File(target, name)
                        if (entry.isSymbolicLink) {
                            outFile.parentFile?.mkdirs()
                            outFile.delete()
                            try {
                                Os.symlink(entry.linkName, outFile.absolutePath)
                            } catch (_: Throwable) {}
                        } else {
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { os ->
                                var n = tar.read(buf)
                                while (n != -1) {
                                    os.write(buf, 0, n)
                                    n = tar.read(buf)
                                }
                            }
                            // lib/ 下的 .so 给执行位（dlopen 需要）
                            if (name.startsWith("lib/") && name.endsWith(".so")) {
                                outFile.setExecutable(true, false)
                            }
                        }
                    } else if (name.isNotEmpty() && entry.isDirectory) {
                        File(target, name).mkdirs()
                    }
                    entry = tar.nextTarEntry
                }
            }
        }
        
        // 扫描 lib/ 目录，为带版本号的 .so 创建 SONAME 符号链接
        // 例：libxml2.so.16.1.1 → libxml2.so.16, libxml2.so
        val libDir = File(target, "lib")
        if (libDir.isDirectory) {
            for (f in libDir.listFiles() ?: emptyArray()) {
                val name = f.name
                val soIdx = name.indexOf(".so.")
                if (soIdx >= 0 && f.isFile && !Files.isSymbolicLink(f.toPath())) {
                    val base = name.substring(0, soIdx + 3) // "libfoo.so"
                    val versionPart = name.substring(soIdx + 4) // "16.1.1"
                    val parts = versionPart.split(".")
                    var linkName = base
                    // 逐级创建：libfoo.so.16.1, libfoo.so.16（跳过最后一级=原文件名本身）
                    for (i in 0 until parts.size - 1) {
                        linkName = "$linkName.${parts[i]}"
                        val linkFile = File(libDir, linkName)
                        if (!linkFile.exists()) {
                            try {
                                Os.symlink(name, linkFile.absolutePath)
                            } catch (_: Throwable) {}
                        }
                    }
                    // 创建无版本号的 base 链接：libfoo.so -> libfoo.so.X
                    val baseFile = File(libDir, base)
                    if (!baseFile.exists() && parts.size > 1) {
                        try {
                            Os.symlink(name, baseFile.absolutePath)
                        } catch (_: Throwable) {}
                    }
                }
            }
        }
        
        // 最后写版本号，作为"解压完整"的标记（version 文件不存在 = 解压未完成）。
        File(target, "version").writeText(assetVer)
    }

    // ──────────────────────────────────────────────────────
    // frpc 运行时（frp 客户端，内网穿透）：Go 以 c-shared 编译的自包含 .so
    //   assets/runtimes/frpc/bin_<arch>.tgz   （arm64 / arm / x86_64）
    //   assets/runtimes/frpc/version          版本号（单行）
    //   tgz 内部布局：lib/libfrpc.so (+ version)
    //   通过 libfrpcloader.so dlopen lib/libfrpc.so 运行，与 PHP/Java 同构。
    // 解压目标：filesDir/runtimes/frpc/
    // ──────────────────────────────────────────────────────

    /** frpc 在 runtimes 下的固定目录名（单一版本，无需多版本共存）。 */
    const val FRPC_VERSION = "frpc"

    /** frpc 引擎库在解压后的相对路径（被 libfrpcloader.so dlopen）。 */
    private const val FRPC_LIB_REL = "lib/libfrpc.so"

    fun frpcDir(context: Context): File = jreDir(context, FRPC_VERSION)

    /** libfrpc.so 的完整路径（供 libfrpcloader.so 通过 EC_FRPC_LIB 加载）。 */
    fun frpcLib(context: Context): File = File(frpcDir(context), FRPC_LIB_REL)

    /** frpc lib 目录路径（供 LD_LIBRARY_PATH 使用）。 */
    fun frpcLibDir(context: Context): File = File(frpcDir(context), "lib")

    /** 当前架构下是否内置了 frpc（assets 中确有对应 bin_<arch>.tgz）。 */
    fun isFrpcAvailable(context: Context): Boolean {
        val arch = deviceArch()
        return assetExists(context, "$ASSET_ROOT/$FRPC_VERSION/bin_$arch.tgz")
    }

    /** frpc 是否已按最新版本号解压就位（version 一致且引擎库存在）。 */
    fun isFrpcInstalled(context: Context): Boolean {
        val assetVer = assetVersion(context, FRPC_VERSION) ?: return false
        val installedFile = File(frpcDir(context), "version")
        if (!installedFile.exists()) return false
        val installed = installedFile.readText().trim()
        return installed.isNotEmpty() && installed == assetVer && frpcLib(context).exists()
    }

    /**
     * 解压安装 frpc（先清空旧目录），按设备架构选取 bin_<arch>.tgz。
     * 耗时操作，请在后台线程调用。
     */
    fun installFrpc(context: Context) {
        val assetVer = assetVersion(context, FRPC_VERSION)
            ?: throw IllegalStateException("assets 中缺少 frpc 的 version 文件")
        val arch = deviceArch()
        val asset = "$ASSET_ROOT/$FRPC_VERSION/bin_$arch.tgz"
        if (!assetExists(context, asset)) {
            throw IllegalStateException("frpc 不支持当前架构 $arch")
        }

        val target = frpcDir(context)
        target.deleteRecursively()
        target.mkdirs()

        context.assets.open(asset).use { input ->
            TarArchiveInputStream(GZIPInputStream(BufferedInputStream(input))).use { tar ->
                val buf = ByteArray(8192)
                var entry = tar.nextTarEntry
                while (entry != null) {
                    val name = entry.name.removePrefix("./")
                    if (name.isNotEmpty() && !entry.isDirectory) {
                        val outFile = File(target, name)
                        outFile.parentFile?.mkdirs()
                        FileOutputStream(outFile).use { os ->
                            var n = tar.read(buf)
                            while (n != -1) {
                                os.write(buf, 0, n)
                                n = tar.read(buf)
                            }
                        }
                        // lib/ 下的 .so 给执行位（dlopen 需要）
                        if (name.startsWith("lib/") && name.endsWith(".so")) {
                            outFile.setExecutable(true, false)
                        }
                    } else if (name.isNotEmpty() && entry.isDirectory) {
                        File(target, name).mkdirs()
                    }
                    entry = tar.nextTarEntry
                }
            }
        }

        // 最后写版本号，作为"解压完整"的标记。
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
