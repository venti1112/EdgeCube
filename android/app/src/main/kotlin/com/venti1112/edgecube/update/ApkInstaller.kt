package com.venti1112.edgecube.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
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
}
