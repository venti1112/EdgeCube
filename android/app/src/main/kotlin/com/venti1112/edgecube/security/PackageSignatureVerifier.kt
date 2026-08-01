package com.venti1112.edgecube.security

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature as PmSignature
import android.util.Base64
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Signature as CryptoSignature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.zip.ZipFile

/**
 * 运行环境包（ecpkg / rootfs ZIP）的数字签名验证器。
 *
 * 统一验证 ZIP 内嵌签名（`META-INF/edgecube.sig`），签名使用与当前 APK 相同的
 * EC 密钥对，确保包由同一发布者签发。签名算法为 ECDSA over SHA-256。
 *
 * 签名数据计算方式：
 * 1. 遍历 ZIP 中所有非 `META-INF/` 前缀、非目录的条目，按条目名排序。
 * 2. 对每个条目内容计算 SHA-256。
 * 3. 拼接为 `"条目名\nSHA-256十六进制\n"` 格式字符串（manifest）。
 * 4. 对 manifest 的 UTF-8 字节进行 ECDSA over SHA-256 签名。
 */
object PackageSignatureVerifier {

    private const val SIG_ENTRY = "META-INF/edgecube.sig"

    /** ZIP 文件魔数：`PK\x03\x04` */
    private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B, 0x03, 0x04)

    private val HEX_CHARS = "0123456789abcdef".toCharArray()

    /** 签名验证结果。 */
    data class VerifyResult(
        /** ZIP 中是否存在签名条目。 */
        val hasSignature: Boolean,
        /** 签名是否验证通过（公钥匹配且签名有效）。`hasSignature=false` 时恒为 `false`。 */
        val valid: Boolean,
    ) {
        /** 是否为可信包（有签名且验证通过）。 */
        val isTrusted: Boolean get() = hasSignature && valid

        /** 转为 MethodChannel 可传输的 Map。 */
        fun toMap(): Map<String, Any> = mapOf(
            "hasSignature" to hasSignature,
            "valid" to valid,
        )
    }

    /**
     * 从当前已安装 APK 的签名证书中提取公钥。
     *
     * 使用 [PackageManager.GET_SIGNATURES] 获取签名（与
     * [com.venti1112.edgecube.update.ApkInstaller] 一致，兼容 V2/V3 签名），
     * 通过 X.509 证书解析出公钥。
     */
    fun getApkPublicKey(context: Context): PublicKey? {
        val pm = context.packageManager
        val signatures = try {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES).signatures
        } catch (_: Exception) {
            null
        } ?: return null

        if (signatures.isEmpty()) return null
        return signatureToPublicKey(signatures[0])
    }

    /** 将 Android [PmSignature] 转换为 X.509 证书并提取公钥。 */
    private fun signatureToPublicKey(sig: PmSignature): PublicKey? {
        return try {
            val cf = CertificateFactory.getInstance("X.509")
            val cert = cf.generateCertificate(sig.toByteArray().inputStream()) as X509Certificate
            cert.publicKey
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 验证 ZIP 文件内嵌的 [SIG_ENTRY] 签名。
     *
     * ecpkg 和 rootfs ZIP 包共用此方法。返回 [VerifyResult]：
     * - 无签名条目 → `VerifyResult(false, false)`
     * - 有签名但验证失败 → `VerifyResult(true, false)`
     * - 验证通过 → `VerifyResult(true, true)`
     */
    fun verifyZip(context: Context, zipPath: String): VerifyResult {
        val publicKey = getApkPublicKey(context)
            ?: return VerifyResult(hasSignature = false, valid = false)

        val file = File(zipPath)
        if (!file.isFile) return VerifyResult(hasSignature = false, valid = false)

        return try {
            ZipFile(file).use { zf ->
                verifyZipInternal(zf, publicKey)
            }
        } catch (_: Exception) {
            VerifyResult(hasSignature = false, valid = false)
        }
    }

    private fun verifyZipInternal(zf: ZipFile, publicKey: PublicKey): VerifyResult {
        // 1. 读取签名条目
        val sigEntry = zf.getEntry(SIG_ENTRY)
            ?: return VerifyResult(hasSignature = false, valid = false)

        val sigBytes = try {
            Base64.decode(
                zf.getInputStream(sigEntry).use { it.readBytes() },
                Base64.DEFAULT,
            )
        } catch (_: Exception) {
            return VerifyResult(hasSignature = true, valid = false)
        }

        if (sigBytes.isEmpty()) return VerifyResult(hasSignature = true, valid = false)

        // 2. 计算 manifest（条目哈希拼接字符串的 UTF-8 字节）
        val manifestBytes = try {
            computeManifest(zf)
        } catch (_: Exception) {
            return VerifyResult(hasSignature = true, valid = false)
        }

        // 3. 验证 ECDSA-SHA256 签名（对 manifest 原始字节签名，SHA-256 由签名算法内部计算）
        val valid = try {
            val sig = CryptoSignature.getInstance("SHA256withECDSA")
            sig.initVerify(publicKey)
            sig.update(manifestBytes)
            sig.verify(sigBytes)
        } catch (_: Exception) {
            false
        }
        return VerifyResult(hasSignature = true, valid = valid)
    }

    /**
     * 计算 ZIP 中所有非 `META-INF/` 条目的聚合摘要。
     *
     * @see PackageSignatureVerifier 类注释中的摘要算法说明
     */
    private fun computeManifest(zf: ZipFile): ByteArray {
        // 收集所有非 META-INF/、非目录条目名称，排序
        val contentNames = mutableListOf<String>()
        val entries = zf.entries()
        while (entries.hasMoreElements()) {
            val entry = entries.nextElement()
            if (entry.isDirectory) continue
            if (entry.name.startsWith("META-INF/")) continue
            contentNames.add(entry.name)
        }
        contentNames.sort()

        // 拼接 "条目名\nSHA-256十六进制\n"
        val sb = StringBuilder()
        for (name in contentNames) {
            val entry = zf.getEntry(name) ?: continue
            val hash = zf.getInputStream(entry).use { stream ->
                val md = MessageDigest.getInstance("SHA-256")
                val buf = ByteArray(8192)
                while (true) {
                    val n = stream.read(buf)
                    if (n == -1) break
                    md.update(buf, 0, n)
                }
                md.digest()
            }
            sb.append(name).append('\n')
            sb.append(hashToHex(hash)).append('\n')
        }

        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    /** 字节数组转小写十六进制字符串。 */
    private fun hashToHex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(HEX_CHARS[(b.toInt() ushr 4) and 0x0F])
            sb.append(HEX_CHARS[b.toInt() and 0x0F])
        }
        return sb.toString()
    }

    /**
     * 判断文件是否为 ZIP 格式（读文件头 4 字节判断 `PK\x03\x04`）。
     *
     * 用于 rootfs 导入时区分新格式 ZIP 包与旧格式裸 tar 压缩包。
     */
    fun isZipFile(path: String): Boolean {
        return try {
            RandomAccessFile(File(path), "r").use { raf ->
                if (raf.length() < 4) return false
                val magic = ByteArray(4)
                raf.readFully(magic)
                magic.contentEquals(ZIP_MAGIC)
            }
        } catch (_: Exception) {
            false
        }
    }
}
