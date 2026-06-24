package com.venti1112.edgecube.server

import android.content.Context
import android.os.Build
import android.system.Os
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipFile
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files

/**
 * `.ecpkg` 清单模型与解析。
 *
 * 对应 `docs/ecpkg-spec.md` 中定义的 `edgecube-package.json` 格式。
 */
data class EcManifest(
    val formatVersion: Int,
    val type: String,
    val id: String,
    val name: String,
    val version: String,
    val description: String?,
    val author: String?,
    val homepage: String?,
    val repository: String?,
    val updateUrl: String?,
    val universalDir: String?,
    val arch: Map<String, ArchEntry>,
    val launcher: Launcher,
    val env: Map<String, String>,
    val minAppVersion: Int?,
) {
    data class ArchEntry(val dir: String)
    data class Launcher(val type: String, val lib: String)
}

object EcPackage {

    private val ID_PATTERN = Regex("""^[A-Za-z0-9._-]+$""")

    /** 解析并校验 `edgecube-package.json` 内容。 */
    fun parse(json: String): EcManifest {
        val root = JSONObject(json)

        val formatVersion = root.getInt("formatVersion")
        if (formatVersion != 1) {
            throw IllegalArgumentException("不支持的格式版本：$formatVersion")
        }

        val type = root.getString("type")
        if (type !in setOf("jre", "php", "frpc")) {
            throw IllegalArgumentException("不支持的运行时类型：$type")
        }

        val id = root.getString("id")
        if (!validateId(id)) {
            throw IllegalArgumentException("运行时 id 包含非法字符：$id")
        }

        val name = root.getString("name")
        val version = root.getString("version")

        val archObj = root.getJSONObject("arch")
        val arch = mutableMapOf<String, EcManifest.ArchEntry>()
        val archKeys = archObj.keys()
        while (archKeys.hasNext()) {
            val key = archKeys.next()
            val dir = archObj.getJSONObject(key).getString("dir")
            arch[key] = EcManifest.ArchEntry(dir)
        }
        if (arch.isEmpty()) {
            throw IllegalArgumentException("arch 不能为空")
        }

        val launcherObj = root.getJSONObject("launcher")
        val launcher = EcManifest.Launcher(
            type = launcherObj.getString("type"),
            lib = launcherObj.getString("lib"),
        )
        if (launcher.type !in setOf("jli", "embed", "frpc")) {
            throw IllegalArgumentException("不支持的启动器类型：${launcher.type}")
        }

        val env = mutableMapOf<String, String>()
        if (root.has("env")) {
            val envObj = root.getJSONObject("env")
            val envKeys = envObj.keys()
            while (envKeys.hasNext()) {
                val key = envKeys.next()
                env[key] = envObj.getString(key)
            }
        }

        return EcManifest(
            formatVersion = formatVersion,
            type = type,
            id = id,
            name = name,
            version = version,
            description = root.optString("description").takeIf { it.isNotEmpty() },
            author = root.optString("author").takeIf { it.isNotEmpty() },
            homepage = root.optString("homepage").takeIf { it.isNotEmpty() },
            repository = root.optString("repository").takeIf { it.isNotEmpty() },
            updateUrl = root.optString("updateUrl").takeIf { it.isNotEmpty() },
            universalDir = root.optString("universalDir").takeIf { it.isNotEmpty() },
            arch = arch,
            launcher = launcher,
            env = env,
            minAppVersion = root.optInt("minAppVersion").takeIf { it > 0 },
        )
    }

    /** 校验 id 是否合法（§4.3 安全约束）。 */
    fun validateId(id: String): Boolean = ID_PATTERN.matches(id) && !id.startsWith(".")

    /** 根据设备支持的 ABI 选取匹配的架构目录（含 ABI 回退）。 */
    fun pickArchDir(context: Context, manifest: EcManifest): String? {
        for (abi in Build.SUPPORTED_ABIS) {
            val key = when (abi) {
                "arm64-v8a" -> "arm64"
                "armeabi-v7a" -> "arm"
                "x86_64" -> "x86_64"
                else -> continue
            }
            val entry = manifest.arch[key] ?: continue
            return entry.dir
        }
        return null
    }
}
