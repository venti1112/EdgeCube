package com.venti1112.edgecube.proot

import android.content.Context
import com.venti1112.edgecube.security.PackageSignatureVerifier
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

/**
 * rootfs 的发现、导入与删除。
 *
 * rootfs 存放在 `filesDir/proot_rootfs/<id>/`，用户导入 rootfs 包解压得到。
 * 支持两种包格式：裸 tar 压缩包（rootfs.tar.zst / .tar.xz / .tar.gz / .tgz），
 * 以及 ZIP 包装包（`.zip` 或 `.ecpkg`，内含 `rootfs.tar.zst`）。ZIP 包与运行
 * 时 .ecpkg 复用同一签名体系（META-INF/edgecube.sig），通过 magic 识别而非后缀。
 * 导入与修补的做法来自 tiny_container 的 `ContainerManageViewModel.kt`。
 */
object RootfsStore {

    /** rootfs tar 压缩包条目的常见后缀（用于识别 ZIP/.ecpkg 包中的内层 tar）。 */
    private val TAR_SUFFIXES = listOf(
        ".tar.zst", ".tar.xz", ".tar.gz", ".tgz", ".tar",
    )

    /** ZIP 层的包清单文件名；rootfs 包中 `type` 字段为 `"proot"`。 */
    const val PACKAGE_MANIFEST_FILE = "edgecube-package.json"

    /** rootfs 包清单中的 type 值，用于区分 rootfs 包与运行时包。 */
    const val PACKAGE_TYPE_PROOT = "proot"

    /** rootfs 根目录：其下每个子目录是一个独立的 Linux 容器根。 */
    fun rootfsBaseDir(context: Context): File = File(context.filesDir, "proot_rootfs")

    /** 指定 id 的 rootfs 目录。 */
    fun rootfsDir(context: Context, id: String): File = File(rootfsBaseDir(context), id)

    /** 是否已安装任意 rootfs。 */
    fun hasRootfs(context: Context): Boolean {
        val base = rootfsBaseDir(context)
        if (!base.isDirectory) return false
        return base.listFiles()?.any { it.isDirectory && !it.name.startsWith(".") } == true
    }

    /** 列出所有已安装的 rootfs。 */
    fun installedRootfs(context: Context): List<ProotRootfs> {
        val base = rootfsBaseDir(context)
        if (!base.isDirectory) return emptyList()
        val result = mutableListOf<ProotRootfs>()
        for (child in base.listFiles() ?: emptyArray()) {
            if (!child.isDirectory || child.name.startsWith(".")) continue
            // 必须看起来像个 rootfs（含 /bin/sh 或 /usr/bin/sh）
            val sh = File(child, "bin/sh")
            if (!sh.exists() && !File(child, "usr/bin/sh").exists()) continue
            // 元数据直接读 rootfs 内的 edgecube-rootfs.json。
            val manifest = RootfsManifest.read(child)
            result.add(ProotRootfs(child.name, child, manifest))
        }
        return result.sortedBy { it.id }
    }

    /** 取指定 id 的 rootfs；不存在或无效返回 null。 */
    fun installedRootfs(context: Context, id: String): ProotRootfs? {
        val dir = rootfsDir(context, id)
        if (!dir.isDirectory) return null
        val sh = File(dir, "bin/sh")
        if (!sh.exists() && !File(dir, "usr/bin/sh").exists()) return null
        val manifest = RootfsManifest.read(dir)
        return ProotRootfs(id, dir, manifest)
    }

    /**
     * 导入 rootfs 包：裸 tar 压缩包（.tar.zst / .tar.xz / .tar.gz / .tgz）
     * 或 ZIP 包装（`.zip` / `.ecpkg`，内含 `rootfs.tar.zst`）。
     * 用 proot --link2symlink 包住 busybox/GNU tar 解压到临时目录，
     * 成功后原子重命名到目标目录。
     *
     * @param id 用户指定的 rootfs 标识（用作目录名）；为空时从文件名推导。
     * @param onProgress 可选进度回调 (已处理字节数, 总字节数)；总字节数未知时为 -1。
     */
    fun importRootfs(
        context: Context,
        tarballPath: String,
        id: String? = null,
        onProgress: ((Long, Long) -> Unit)? = null,
    ): ProotRootfs {
        val tarball = File(tarballPath)
        if (!tarball.isFile) throw IllegalArgumentException("文件不存在：$tarballPath")

        val rootfsId = (id?.takeIf { it.isNotBlank() } ?: tarball.nameWithoutExtension)
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("无法推导 rootfs id")

        // 新格式 ZIP 包：提取内层 tar.zst 到临时文件；旧格式裸 tar 包直接使用原路径。
        val isZip = PackageSignatureVerifier.isZipFile(tarballPath)
        val innerTarball = if (isZip) extractInnerTarball(context, tarball) else tarball

        try {
            ProotBootstrap.ensureBootstrap(context)

            val target = rootfsDir(context, rootfsId)
            if (target.exists()) throw IllegalStateException("ROOTFS_EXISTS")

            val tmpDir = File(rootfsBaseDir(context), ".$rootfsId.tmp")
            tmpDir.deleteRecursively()
            tmpDir.mkdirs()

            val bootstrapBin = File(ProotBootstrap.bootstrapDir(context), "bin")
            val prootBin = File(bootstrapBin, "proot")
            val tarBin = File(bootstrapBin, "tar")

            // proot 包住 tar：--link2symlink 把硬链接转为符号链接（Android fs 不支持硬链接），
            // --delay-directory-restore + --preserve-permissions 保证权限位正确。
            val cmd = listOf(
                prootBin.absolutePath,
                "--link2symlink",
                tarBin.absolutePath,
                "-xf", innerTarball.absolutePath,
                "-C", tmpDir.absolutePath,
                "--delay-directory-restore",
                "--preserve-permissions",
            )

            val env = ProotBootstrap.baseHostEnv(context)
            val pb = ProcessBuilder(cmd)
            pb.redirectErrorStream(true)
            pb.environment().clear()
            pb.environment().putAll(env)
            val proc = pb.start()

            // tar 输出多为进度/警告；逐行读取避免缓冲区满死锁。可解出的字节数由文件大小近似。
            val totalBytes = innerTarball.length()
            var lastReported = 0L
            try {
                BufferedReader(InputStreamReader(proc.inputStream, Charsets.UTF_8)).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        // tar -v 模式未启用，这里基本只有警告；偶发触发进度回调。
                        if (onProgress != null && System.nanoTime() - lastReported > 500_000_000L) {
                            onProgress(-1L, totalBytes)
                            lastReported = System.nanoTime()
                        }
                        // 丢弃行内容，避免占用内存；真实错误由 exitCode 捕获。
                        @Suppress("UNUSED_VARIABLE") val ignored = line
                    }
                }
            } finally {
                // 进度收尾
                onProgress?.invoke(totalBytes, totalBytes)
            }

            val code = proc.waitFor()
            if (code != 0) {
                tmpDir.deleteRecursively()
                throw IllegalStateException("解压失败（退出码 $code），请确认文件是有效的 rootfs.tar.zst")
            }

            // 修补 passwd/shadow/group/gshadow：移除 aid_* 条目并加入当前 app 身份
            // （来自 proot-distro 的做法，保证容器内 id 命令与文件归属正常）。
            fixPasswdForAndroid(tmpDir)
            // 写入 DNS 解析配置：proot 不自动继承 Android DNS，必须显式提供，
            // 否则容器内 apt/Minecraft 等所有域名解析都会失败。
            ProotDns.ensureResolvConf(context, tmpDir)

            // 原子替换
            if (!tmpDir.renameTo(target)) {
                tmpDir.deleteRecursively()
                throw IllegalStateException("无法重命名临时目录到目标目录")
            }

            return installedRootfs(context, rootfsId)
                ?: throw IllegalStateException("导入后未检测到有效 rootfs")
        } finally {
            // 清理从 ZIP 提取的临时 tar 文件（旧格式裸 tar 不需要清理）。
            if (innerTarball !== tarball) {
                innerTarball.delete()
            }
        }
    }

    /** 删除指定 rootfs。 */
    fun deleteRootfs(context: Context, id: String) {
        rootfsDir(context, id).deleteRecursively()
    }

    /**
     * 修补 rootfs 的 passwd/shadow/group/gshadow：移除 aid_* 条目并加入当前
     * app 身份（来自 proot-distro 的做法）。
     *
     * Android 上每个 app 有独立的 uid（如 u0_a123），在容器内表现为非 0 的数字。
     * 默认 rootfs 的 passwd 没有 aid_* 条目，导致 `id` 命令报错、文件归属异常。
     */
    private fun fixPasswdForAndroid(rootfsDir: File) {
        val uid = android.os.Process.myUid()
        val gid = uid // app 的 gid 通常等于 uid
        val username = "aid_${uid}"

        val files = listOf("etc/passwd", "etc/shadow", "etc/group", "etc/gshadow")
        for (path in files) {
            val f = File(rootfsDir, path)
            if (!f.exists()) continue
            try {
                val lines = f.readLines()
                    .filterNot { it.startsWith("aid_") }
                    .toMutableList()
                when (path) {
                    "etc/passwd" -> lines.add("$username:x:$uid:$gid:Android:/:/sbin/nologin")
                    "etc/shadow" -> lines.add("$username:*:18446:0:99999:7:::")
                    "etc/group" -> lines.add("$username:x:$gid:")
                    "etc/gshadow" -> lines.add("$username:*::")
                }
                f.writeText(lines.joinToString("\n") + "\n")
            } catch (_: Throwable) {
                // 修补失败不阻断导入——容器仍可运行，仅 id 命令异常
            }
        }
    }

    /**
     * 判断指定文件是否为 rootfs 包。
     *
     * 用于统一导入入口区分 rootfs 包与运行时包：
     * - 裸 tar 压缩包（非 ZIP，扩展名为 .tar.zst / .tar.xz / .tar.gz / .tgz / .tar）返回 true；
     * - ZIP 内含 `edgecube-package.json` 且 `type` 为 `"proot"` 时返回 true；
     * - ZIP 内含 `edgecube-package.json` 但 `type` 为其他值（jre/php/frpc）时返回 false；
     * - 旧格式 rootfs ZIP（无 `edgecube-package.json` 但内含 tar 条目）回退返回 true。
     *
     * 识别规则与 [extractInnerTarball] 保持一致。
     */
    fun isRootfsPackage(path: String): Boolean {
        val file = File(path)
        if (!file.isFile) return false
        // 裸 tar 压缩包（非 ZIP）：直接按扩展名识别为 rootfs。
        if (!PackageSignatureVerifier.isZipFile(path)) {
            return TAR_SUFFIXES.any { path.lowercase().endsWith(it) }
        }
        return try {
            ZipFile(file).use { zf ->
                // 优先读取 edgecube-package.json 的 type 字段路由。
                val manifestEntry = zf.getEntry(PACKAGE_MANIFEST_FILE)
                if (manifestEntry != null) {
                    val json = zf.getInputStream(manifestEntry).use {
                        it.readBytes().toString(Charsets.UTF_8)
                    }
                    return@use JSONObject(json).optString("type") == PACKAGE_TYPE_PROOT
                }
                // 旧格式 rootfs ZIP（无清单）：回退到 tar 条目探测。
                var hasTarEntry = false
                val entries = zf.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.isDirectory || entry.name.startsWith("META-INF/")) continue
                    if (entry.name == "rootfs.tar.zst" ||
                        TAR_SUFFIXES.any { entry.name.endsWith(it) }
                    ) {
                        hasTarEntry = true
                        break
                    }
                }
                hasTarEntry
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 从 ZIP 包装的 rootfs 包中提取内层 tar 压缩包到临时文件。
     *
     * 新格式 `rootfs.zip` / `.ecpkg` 内含 `rootfs.tar.zst`（或唯一非 `META-INF/`
     * 条目）；本方法将其提取到 cacheDir 下的临时文件，供后续 proot tar 解压使用。
     */
    private fun extractInnerTarball(context: Context, zipFile: File): File {
        val tempFile = File(
            context.cacheDir,
            ".rootfs-import-${System.currentTimeMillis()}.tar.zst",
        )
        ZipFile(zipFile).use { zf ->
            val entries = zf.entries()
            var targetEntry: ZipEntry? = null
            var fallbackEntry: ZipEntry? = null
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory) continue
                if (entry.name.startsWith("META-INF/")) continue
                // 跳过包清单与版本标记等非 tar 条目（rootfs ZIP 的 edgecube-package.json
                // 中 type=proot，仅用于路由识别，不应进入 tar 解压流）。
                if (entry.name == PACKAGE_MANIFEST_FILE || entry.name == "version") continue
                if (entry.name == "rootfs.tar.zst" ||
                    TAR_SUFFIXES.any { entry.name.endsWith(it) }
                ) {
                    targetEntry = entry
                    break
                }
                if (fallbackEntry == null) {
                    fallbackEntry = entry
                }
            }
            val entry = targetEntry ?: fallbackEntry
                ?: throw IllegalArgumentException("ZIP 中未找到 rootfs tar 压缩包条目")

            zf.getInputStream(entry).use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
        }
        return tempFile
    }
}
