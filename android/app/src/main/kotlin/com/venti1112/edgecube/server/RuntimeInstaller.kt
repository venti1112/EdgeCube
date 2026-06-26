package com.venti1112.edgecube.server

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.system.Os
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipFile
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files

/**
 * 运行时管理器：基于已安装的 `.ecpkg` 环境包，实现发现、导入、删除。
 *
 * 不再内置 assets 运行时；所有运行时通过用户导入 `.ecpkg` 安装到
 * `filesDir/runtimes/<id>/`。
 */
object RuntimeInstaller {

    fun runtimesDir(context: Context): File = File(context.filesDir, "runtimes")

    fun runtimeDir(context: Context, id: String): File =
        File(runtimesDir(context), id)

    /** 扫描所有已安装且有效的运行时。 */
    fun installedRuntimes(context: Context): List<EcManifest> {
        val dir = runtimesDir(context)
        if (!dir.isDirectory) return emptyList()
        val result = mutableListOf<EcManifest>()
        for (child in dir.listFiles() ?: emptyArray()) {
            if (!child.isDirectory || child.name.startsWith(".")) continue
            val manifest = readInstalledManifest(child) ?: continue
            result.add(manifest)
        }
        return result
    }

    /** 读取指定 id 的已安装运行时清单；未安装或无效返回 null。 */
    fun installedRuntime(context: Context, id: String): EcManifest? {
        val dir = runtimeDir(context, id)
        if (!dir.isDirectory) return null
        return readInstalledManifest(dir)
    }

    /** 指定运行时是否已安装且有效。 */
    fun isInstalled(context: Context, id: String): Boolean {
        return installedRuntime(context, id) != null
    }

    /** 当前已安装的 JRE 运行时 id 列表。 */
    fun availableJreIds(context: Context): List<String> {
        return installedRuntimes(context)
            .filter { it.type == "jre" }
            .map { it.id }
    }

    /** 当前已安装的 PHP 运行时 id 列表。 */
    fun availablePhpIds(context: Context): List<String> {
        return installedRuntimes(context)
            .filter { it.type == "php" }
            .map { it.id }
    }

    /** 取首个已安装的 frpc 运行时（用于隧道）。 */
    fun installedFrpc(context: Context): EcManifest? {
        return installedRuntimes(context).firstOrNull { it.type == "frpc" }
    }

    /** 是否存在已安装的 frpc 运行时。 */
    fun isFrpcAvailable(context: Context): Boolean = installedFrpc(context) != null

    /**
     * 导入 `.ecpkg` 文件并安装到 `runtimes/<id>/`。
     *
     * @param force 为 true 时不询问直接覆盖已存在的同 id 运行时。
     */
    fun importPackage(
        context: Context,
        ecpkgPath: String,
        onProgress: ((Int, Int) -> Unit)? = null,
        force: Boolean = false,
    ): EcManifest {
        val file = File(ecpkgPath)
        if (!file.isFile) throw IllegalArgumentException("文件不存在：$ecpkgPath")

        val zip = ZipFile.builder().setFile(file).get()
        zip.use { zf ->
            // 1. 读取并解析清单
            val manifestEntry = zf.getEntry("edgecube-package.json")
                ?: throw IllegalArgumentException("ZIP 中缺少 edgecube-package.json")
            val manifestJson = zf.getInputStream(manifestEntry).use { it.readBytes().toString(Charsets.UTF_8) }
            val manifest = EcPackage.parse(manifestJson)

            // 2. 校验 id
            if (!EcPackage.validateId(manifest.id)) {
                throw IllegalArgumentException("运行时 id 包含非法字符：${manifest.id}")
            }

            // 3. 校验设备架构
            val archDir = EcPackage.pickArchDir(context, manifest)
                ?: throw IllegalArgumentException("当前设备架构不支持此包")

            // 4. 校验 minAppVersion
            val minVer = manifest.minAppVersion
            val appVer = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_ACTIVITIES).longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getPackageInfo(context.packageName, 0).versionCode.toLong()
                }
            } catch (_: Exception) { 0L }
            if (appVer < minVer) {
                throw IllegalArgumentException("应用版本过低，需要构建号 ≥ $minVer")
            }

            // 5. 校验 universalDir / archDir 在 ZIP 中存在
            manifest.universalDir?.let { ud ->
                if (!hasDirectoryEntry(zf, ud)) {
                    throw IllegalArgumentException("ZIP 中缺少 universalDir：$ud")
                }
            }
            if (!hasDirectoryEntry(zf, archDir)) {
                throw IllegalArgumentException("ZIP 中缺少 archDir：$archDir")
            }

            // 6. 安全替换：解压到临时目录
            val target = runtimeDir(context, manifest.id)
            val tmpDir = File(runtimesDir(context), ".${manifest.id}.tmp")
            if (target.exists() && !force) {
                throw IllegalStateException("RUNTIME_EXISTS")
            }
            tmpDir.deleteRecursively()
            tmpDir.mkdirs()

            try {
                val entries = zf.entries.toList()
                val total = entries.size
                var processed = 0

                // 先提取 universalDir
                manifest.universalDir?.let { ud ->
                    val prefix = "$ud/"
                    for (entry in entries) {
                        if (!entry.name.startsWith(prefix)) continue
                        extractEntry(zf, entry, tmpDir, prefix)
                        processed++
                    }
                }

                // 再提取 archDir（覆盖同名文件）
                val prefix = "$archDir/"
                for (entry in entries) {
                    if (!entry.name.startsWith(prefix)) continue
                    extractEntry(zf, entry, tmpDir, prefix)
                    processed++
                }

                // 设置可执行位
                setExecutableBits(tmpDir)

                // SONAME 兜底链接
                createSonameLinks(tmpDir)

                // 复制清单
                File(tmpDir, "edgecube-package.json").writeText(manifestJson)

                // 最后写 version（作为完成标记）
                File(tmpDir, "version").writeText(manifest.version)

                onProgress?.invoke(processed, total)

                // 原子替换
                target.deleteRecursively()
                if (!tmpDir.renameTo(target)) {
                    throw IllegalStateException("无法重命名临时目录到目标目录")
                }
            } catch (e: Throwable) {
                tmpDir.deleteRecursively()
                throw e
            }

            return manifest
        }
    }

    /** 删除指定运行时。 */
    fun deleteRuntime(context: Context, id: String) {
        runtimeDir(context, id).deleteRecursively()
    }

    // 内部辅助

    private fun readInstalledManifest(dir: File): EcManifest? {
        val manifestFile = File(dir, "edgecube-package.json")
        val versionFile = File(dir, "version")
        if (!manifestFile.isFile || !versionFile.isFile) return null
        return try {
            val manifest = EcPackage.parse(manifestFile.readText())
            val installedVersion = versionFile.readText().trim()
            if (installedVersion == manifest.version) manifest else null
        } catch (_: Exception) {
            null
        }
    }

    /** 检查 ZIP 中是否存在指定目录（以 / 结尾的条目，或包含该前缀的条目）。 */
    private fun hasDirectoryEntry(zf: ZipFile, dirName: String): Boolean {
        val prefix = "$dirName/"
        for (entry in zf.entries) {
            if (entry.name.startsWith(prefix)) return true
        }
        return false
    }

    /** 提取单个 ZIP 条目到目标目录，剥离前缀。 */
    private fun extractEntry(zf: ZipFile, entry: ZipArchiveEntry, dest: File, prefix: String) {
        val relName = entry.name.removePrefix(prefix)
        if (relName.isEmpty()) return
        // 拒绝路径遍历：相对路径不得以 / 开头，且任何路径分量不得为 ..
        if (relName.startsWith("/") || relName.split('/').any { it == ".." }) {
            throw SecurityException("非法路径：${entry.name}")
        }

        if (entry.isUnixSymlink) {
            val target = File(dest, relName)
            target.parentFile?.mkdirs()
            target.delete()
            val linkTarget = zf.getInputStream(entry).use { it.readBytes().toString(Charsets.UTF_8) }
            // 校验：符号链接目标不逃逸出运行时根目录
            val resolved = File(dest, relName).parentFile?.let { parent ->
                File(parent, linkTarget).canonicalPath
            } ?: linkTarget
            if (!resolved.startsWith(dest.canonicalPath)) {
                throw SecurityException("符号链接目标逃逸：${entry.name} -> $linkTarget")
            }
            try {
                Os.symlink(linkTarget, target.absolutePath)
            } catch (_: Throwable) {}
            return
        }

        if (entry.isDirectory) {
            File(dest, relName).mkdirs()
            return
        }

        val outFile = File(dest, relName)
        outFile.parentFile?.mkdirs()
        zf.getInputStream(entry).use { input ->
            FileOutputStream(outFile).use { output -> input.copyTo(output) }
        }
    }

    // 对 *.so 和 bin/* 设置可执行位。
    private fun setExecutableBits(root: File) {
        root.walkTopDown().forEach { f ->
            if (f.isFile) {
                val name = f.name
                val parent = f.parentFile?.name ?: ""
                if (name.endsWith(".so") || parent == "bin" || name.endsWith(".exe")) {
                    f.setExecutable(true, false)
                }
            }
        }
    }

    // 为 lib/ 下带版本号的 .so 创建 SONAME 符号链接兜底。
    private fun createSonameLinks(root: File) {
        val libDir = File(root, "lib")
        if (!libDir.isDirectory) return
        for (f in libDir.listFiles() ?: emptyArray()) {
            val name = f.name
            val soIdx = name.indexOf(".so.")
            if (soIdx < 0 || !f.isFile || Files.isSymbolicLink(f.toPath())) continue
            val base = name.substring(0, soIdx + 3) // "libfoo.so"
            val versionPart = name.substring(soIdx + 4) // "16.1.1"
            val parts = versionPart.split(".")
            var linkName = base
            for (i in 0 until parts.size - 1) {
                linkName = "$linkName.${parts[i]}"
                val linkFile = File(libDir, linkName)
                if (!linkFile.exists()) {
                    try { Os.symlink(name, linkFile.absolutePath) } catch (_: Throwable) {}
                }
            }
            val baseFile = File(libDir, base)
            if (!baseFile.exists() && parts.size > 1) {
                try { Os.symlink(name, baseFile.absolutePath) } catch (_: Throwable) {}
            }
        }
    }
}
