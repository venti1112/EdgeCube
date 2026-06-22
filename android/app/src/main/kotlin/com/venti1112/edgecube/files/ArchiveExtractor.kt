package com.venti1112.edgecube.files

import com.github.junrar.Archive
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.apache.commons.compress.compressors.lz4.FramedLZ4CompressorInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.compress.compressors.zstandard.ZstdCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.Locale

/**
 * 归档解压器：在 Android 原生侧统一处理所有压缩/归档格式。
 *
 * 支持格式：zip、tar、tar.gz/tgz、tar.xz/txz、tar.bz2/tbz2、tar.zst、tar.lz4、
 * 7z、rar，以及单文件压缩流 xz / gz / bz2 / zst / lz4。
 * 压缩格式：zip。
 *
 * 安全性：所有条目在写入前都经过路径穿越检查（[resolveSafe]），跳过任何
 * 会逃逸出目标目录的条目，防止 Zip Slip 等攻击。
 */
object ArchiveExtractor {

    /**
     * 把 [sourcePaths] 中的文件/目录压缩为 zip 文件 [archivePath]。
     *
     * @return 写入归档的文件数量；空目录不计入。
     */
    fun compressToZip(sourcePaths: List<String>, archivePath: String): Int {
        if (sourcePaths.isEmpty()) {
            throw IllegalArgumentException("没有可压缩的文件")
        }
        val archive = File(archivePath)
        archive.parentFile?.mkdirs()
        val archiveCanon = archive.canonicalFile
        var count = 0
        ZipArchiveOutputStream(archive).use { zip ->
            zip.setEncoding("UTF-8")
            zip.setUseLanguageEncodingFlag(true)
            for (path in sourcePaths) {
                val source = File(path)
                if (!source.exists()) continue
                count += addToZip(zip, source, source.name, archiveCanon)
            }
        }
        return count
    }

    /**
     * 解压 [archivePath] 到 [destDir]。
     *
     * @param archivePath 归档文件绝对路径。
     * @param destDir 目标目录（已存在）。
     * @return 解压出的文件数量。
     */
    fun extract(archivePath: String, destDir: String): Int {
        val file = File(archivePath)
        if (!file.isFile) {
            throw IllegalArgumentException("归档文件不存在：$archivePath")
        }
        val dest = File(destDir)
        if (!dest.isDirectory) dest.mkdirs()
        val name = file.name.lowercase(Locale.ROOT)
        return when {
            name.endsWith(".zip") -> extractZip(file, dest)
            name.endsWith(".tar") -> extractTar(FileInputStream(file), dest)
            name.endsWith(".tar.gz") || name.endsWith(".tgz") ->
                extractTar(GzipCompressorInputStream(BufferedInputStream(FileInputStream(file))), dest)
            name.endsWith(".tar.xz") || name.endsWith(".txz") ->
                extractTar(XZCompressorInputStream(BufferedInputStream(FileInputStream(file))), dest)
            name.endsWith(".tar.bz2") || name.endsWith(".tbz2") ->
                extractTar(BZip2CompressorInputStream(BufferedInputStream(FileInputStream(file))), dest)
            name.endsWith(".tar.zst") || name.endsWith(".tzst") ->
                extractTar(ZstdCompressorInputStream(BufferedInputStream(FileInputStream(file))), dest)
            name.endsWith(".tar.lz4") ->
                extractTar(FramedLZ4CompressorInputStream(BufferedInputStream(FileInputStream(file))), dest)
            name.endsWith(".7z") -> extract7z(file, dest)
            name.endsWith(".rar") -> extractRar(file, dest)
            // 单文件压缩流：解压为去掉压缩后缀的同名文件。
            name.endsWith(".xz") -> extractSingleStream(
                XZCompressorInputStream(BufferedInputStream(FileInputStream(file))),
                dest, stripExt(file.name, ".xz"),
            )
            name.endsWith(".gz") -> extractSingleStream(
                GzipCompressorInputStream(BufferedInputStream(FileInputStream(file))),
                dest, stripExt(file.name, ".gz"),
            )
            name.endsWith(".bz2") -> extractSingleStream(
                BZip2CompressorInputStream(BufferedInputStream(FileInputStream(file))),
                dest, stripExt(file.name, ".bz2"),
            )
            name.endsWith(".zst") -> extractSingleStream(
                ZstdCompressorInputStream(BufferedInputStream(FileInputStream(file))),
                dest, stripExt(file.name, ".zst"),
            )
            name.endsWith(".lz4") -> extractSingleStream(
                FramedLZ4CompressorInputStream(BufferedInputStream(FileInputStream(file))),
                dest, stripExt(file.name, ".lz4"),
            )
            else -> throw IllegalArgumentException("不支持的归档格式：${file.name}")
        }
    }

    /** 去掉文件名末尾的 [ext]（大小写不敏感），用于单文件压缩流的输出名。 */
    private fun stripExt(name: String, ext: String): String {
        val lower = name.lowercase(Locale.ROOT)
        return if (lower.endsWith(ext)) name.substring(0, name.length - ext.length) else name
    }

    private fun addToZip(
        zip: ZipArchiveOutputStream,
        source: File,
        entryName: String,
        archiveFile: File,
    ): Int {
        if (source.canonicalFile == archiveFile) return 0
        val normalizedName = entryName.replace('\\', '/')
        if (source.isDirectory) {
            val dirName = normalizedName.trimEnd('/') + "/"
            zip.putArchiveEntry(ZipArchiveEntry(dirName))
            zip.closeArchiveEntry()
            var count = 0
            source.listFiles()?.sortedBy { it.name.lowercase(Locale.ROOT) }?.forEach { child ->
                count += addToZip(zip, child, dirName + child.name, archiveFile)
            }
            return count
        }

        zip.putArchiveEntry(ZipArchiveEntry(normalizedName))
        FileInputStream(source).use { input -> input.copyTo(zip) }
        zip.closeArchiveEntry()
        return 1
    }

    /** zip：用 ZipFile 随机访问解压，能正确处理条目顺序与目录创建。 */
    private fun extractZip(file: File, dest: File): Int {
        var count = 0
        ZipFile.builder().setFile(file).get().use { zf ->
            val entries = zf.entries
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory) {
                    val target = resolveSafe(dest, entry.name)
                    if (target != null) target.mkdirs()
                    continue
                }
                val target = resolveSafe(dest, entry.name) ?: continue
                target.parentFile?.mkdirs()
                zf.getInputStream(entry).use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output) }
                }
                count++
            }
        }
        return count
    }

    /** tar（含经压缩流包装的 tar.*）：用 TarArchiveInputStream 顺序读取。 */
    private fun extractTar(input: InputStream, dest: File): Int {
        var count = 0
        TarArchiveInputStream(input).use { tis ->
            var entry = tis.nextEntry
            while (entry != null) {
                if (entry.isDirectory) {
                    val target = resolveSafe(dest, entry.name)
                    if (target != null) target.mkdirs()
                } else {
                    val target = resolveSafe(dest, entry.name) ?: run {
                        entry = tis.nextEntry
                        continue
                    }
                    target.parentFile?.mkdirs()
                    FileOutputStream(target).use { output -> tis.copyTo(output) }
                    count++
                }
                entry = tis.nextEntry
            }
        }
        return count
    }

    /** 7z：用 SevenZFile 随机访问解压。 */
    private fun extract7z(file: File, dest: File): Int {
        var count = 0
        SevenZFile.builder().setFile(file).get().use { sz ->
            var entry = sz.nextEntry
            while (entry != null) {
                if (entry.isDirectory) {
                    val target = resolveSafe(dest, entry.name)
                    if (target != null) target.mkdirs()
                } else {
                    val target = resolveSafe(dest, entry.name) ?: run {
                        entry = sz.nextEntry
                        continue
                    }
                    target.parentFile?.mkdirs()
                    val buf = ByteArray(8192)
                    FileOutputStream(target).use { output ->
                        while (true) {
                            val n = sz.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                        }
                    }
                    count++
                }
                entry = sz.nextEntry
            }
        }
        return count
    }

    /** rar：用 junrar 解压。 */
    private fun extractRar(file: File, dest: File): Int {
        var count = 0
        Archive(file).use { rar ->
            var header = rar.nextFileHeader()
            while (header != null) {
                if (header.isDirectory) {
                    val target = resolveSafe(dest, header.fileName)
                    if (target != null) target.mkdirs()
                } else {
                    val target = resolveSafe(dest, header.fileName) ?: run {
                        header = rar.nextFileHeader()
                        continue
                    }
                    target.parentFile?.mkdirs()
                    FileOutputStream(target).use { output -> rar.extractFile(header, output) }
                    count++
                }
                header = rar.nextFileHeader()
            }
        }
        return count
    }

    /** 单文件压缩流：解压为 [outName] 单个文件。 */
    private fun extractSingleStream(input: InputStream, dest: File, outName: String): Int {
        val target = File(dest, outName)
        target.parentFile?.mkdirs()
        input.use { i ->
            FileOutputStream(target).use { o -> i.copyTo(o) }
        }
        return 1
    }

    /**
     * 解析归档条目路径并校验是否在 [base] 目录内，防路径穿越。
     * 返回 null 表示该条目被拒绝（调用方应跳过）。
     */
    private fun resolveSafe(base: File, entryName: String): File? {
        // 归档内可能用 / 或 \ 作为分隔符，统一替换。
        val normalized = entryName.replace('\\', '/')
        val target = File(base, normalized).canonicalFile
        val baseCanon = base.canonicalFile
        // 目标必须等于 base 或位于 base 内。
        if (target == baseCanon || target.path.startsWith(baseCanon.path + File.separator)) {
            return target
        }
        return null
    }
}
