package com.venti1112.edgecube.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * APK 安装器：通过系统 PackageInstaller 安装指定 APK 文件。
 *
 * 使用 FileProvider 安全地向系统安装器分享 APK 文件。
 */
object ApkInstaller {

    /**
     * 触发系统安装界面安装 [apkPath] 指向的 APK。
     *
     * 需在 AndroidManifest 中声明 `REQUEST_INSTALL_PACKAGES` 权限，
     * 并配置 `${applicationId}.fileprovider` FileProvider。
     */
    fun install(context: Context, apkPath: String) {
        val file = File(apkPath)
        if (!file.isFile) {
            throw IllegalArgumentException("APK 文件不存在：$apkPath")
        }

        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    /**
     * 验证下载的 APK 签名是否与当前已安装的应用一致。
     *
     * 同时检查包名是否匹配，防止安装恶意替换包。
     */
    fun verifyApkSignature(context: Context, apkPath: String): Boolean {
        val pm = context.packageManager
        val packageName = context.packageName

        val installedSigners = getInstalledSignatures(pm, packageName) ?: return false
        val archiveSigners = getArchiveSignatures(pm, apkPath) ?: return false

        // 包名必须匹配
        if (archiveSigners.first != packageName) return false

        val apkSignatures = archiveSigners.second

        if (installedSigners.size != apkSignatures.size) return false
        for (i in installedSigners.indices) {
            if (!installedSigners[i].toByteArray().contentEquals(apkSignatures[i].toByteArray())) {
                return false
            }
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun getInstalledSignatures(
        pm: PackageManager,
        packageName: String,
    ): Array<Signature>? {
        return try {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            info.signatures
        } catch (_: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun getArchiveSignatures(
        pm: PackageManager,
        apkPath: String,
    ): Pair<String, Array<Signature>>? {
        return try {
            val info = pm.getPackageArchiveInfo(apkPath, PackageManager.GET_SIGNATURES)
                ?: return null
            val sigs = info.signatures ?: return null
            Pair(info.packageName, sigs)
        } catch (_: Exception) {
            null
        }
    }
}
