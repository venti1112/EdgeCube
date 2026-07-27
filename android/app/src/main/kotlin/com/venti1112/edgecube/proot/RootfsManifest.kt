package com.venti1112.edgecube.proot

import java.io.File
import org.json.JSONObject

/**
 * rootfs 内嵌入的元数据清单（[MANIFEST_FILE]，formatVersion=2）。
 *
 * 每个 rootfs 在根目录可携带 `edgecube-rootfs.json` 清单，声明环境类型
 * （java/php/node/python/generic…）与主程序路径。EdgeCube 导入时直接读取该清单，
 * 不再扫描文件系统判断 Java 路径。缺失清单的 rootfs 视为 `generic` 纯容器，
 * 启动时必须由用户在实例配置中提供完整启动命令
 * （[ProotCommandBuilder.buildGenericCommand]）。
 *
 * - [formatVersion]：清单格式版本，目前固定为 2。
 * - [envType]：环境类型（java/php/node/python/box64/dotnet/generic/…），决定默认启动方式。
 * - [envName]：展示名（如 "OpenJDK 21"），用于 UI。
 * - [envVersionName]：运行时版本字符串（如 "21.0.5+11"）。
 * - [envMainBin]：环境主程序的容器内绝对路径（如 "/usr/bin/java"）；
 *   generic 时为空串，表示不预定义主程序。
 * - [envArgs]：主程序固定前缀参数（如 java 的 ["-jar"]）；generic 时为空数组。
 * - [serverFileHint]：服务端文件扩展名提示（如 ".jar"、".phar"、".js"），
 *   用于 UI 在实例目录中筛选可作为服务端的文件。
 * - [description]：人类可读的描述。
 * - [buildDate]：构建日期字符串（YYYYMMDD）。
 */
data class RootfsManifest(
    val formatVersion: Int,
    val envType: String,
    val envName: String,
    val envVersionName: String,
    val envMainBin: String,
    val envArgs: List<String>,
    val serverFileHint: String,
    val description: String,
    val buildDate: String,
) {
    /** 是否为纯容器（无预定义主程序）。 */
    val isGeneric: Boolean get() = envType == ENV_GENERIC || envMainBin.isBlank()

    companion object {
        /** rootfs 内的元数据清单文件名（位于 rootfs 根目录）。 */
        const val MANIFEST_FILE = "edgecube-rootfs.json"

        /** 已识别的环境类型常量。未携带清单的 rootfs 视为 [ENV_GENERIC]。 */
        const val ENV_JAVA = "java"
        const val ENV_PHP = "php"
        const val ENV_NODE = "node"
        const val ENV_PYTHON = "python"
        /** box64：ARM64 上运行 x86_64 二进制的模拟器，envMainBin 为 /usr/local/bin/box64。 */
        const val ENV_BOX64 = "box64"
        /** .NET (ASP.NET Core)：运行时通过 Microsoft 源安装 aspnetcore-runtime，envMainBin 为 /usr/bin/dotnet。 */
        const val ENV_DOTNET = "dotnet"
        /** 纯容器：rootfs 无清单或 envType=generic；用户须提供完整启动命令。 */
        const val ENV_GENERIC = "generic"

        /**
         * 读取 rootfs 根目录下的 [MANIFEST_FILE]。
         *
         * 文件不存在或解析失败时返回 null（调用方据此把 rootfs 视为 generic 纯容器）。
         * 不再扫描文件系统判断 Java 路径——一切以清单为准。
         */
        fun read(rootfsDir: File): RootfsManifest? {
            val file = File(rootfsDir, MANIFEST_FILE)
            if (!file.isFile) return null
            return try {
                val raw = file.readText()
                if (raw.isBlank()) return null
                parse(JSONObject(raw))
            } catch (_: Throwable) {
                null
            }
        }

        /** 解析清单 JSON 为 [RootfsManifest]；字段缺失时给安全默认值。 */
        private fun parse(root: JSONObject): RootfsManifest {
            val formatVersion = root.optInt("formatVersion", 1)
            val envType = root.optString("envType").takeIf { it.isNotEmpty() } ?: ENV_GENERIC
            val envMainBin = root.optString("envMainBin")
            // envArgs：JSON 数组，逐项取字符串；缺失或类型不符时空数组
            val envArgs = mutableListOf<String>()
            root.optJSONArray("envArgs")?.let { arr ->
                for (i in 0 until arr.length()) {
                    arr.optString(i).takeIf { it.isNotEmpty() }?.let { envArgs.add(it) }
                }
            }
            return RootfsManifest(
                formatVersion = formatVersion,
                envType = envType,
                envName = root.optString("envName").takeIf { it.isNotEmpty() }
                    ?: envType.replaceFirstChar { it.uppercase() },
                envVersionName = root.optString("envVersionName"),
                envMainBin = envMainBin,
                envArgs = envArgs,
                serverFileHint = root.optString("serverFileHint"),
                description = root.optString("description"),
                buildDate = root.optString("buildDate"),
            )
        }
    }
}

/** 已安装 rootfs 的描述。 */
data class ProotRootfs(
    val id: String,
    val dir: File,
    /**
     * rootfs 内嵌的元数据清单；rootfs 未携带清单时为 null（视为 generic 纯容器）。
     *
     * 调用方据此判断：
     *  - 非空且 [RootfsManifest.envMainBin] 非空：按元数据 envType 启动主程序。
     *  - null 或 envMainBin 为空：纯容器，须由用户提供完整启动命令。
     */
    val manifest: RootfsManifest?,
) {
    /** 兼容旧调用方：返回主程序路径（容器视角），无则 null。 */
    val envMainBin: String? get() = manifest?.envMainBin?.takeIf { it.isNotBlank() }

    /** 环境类型；无清单时为 [RootfsManifest.ENV_GENERIC]。 */
    val envType: String get() = manifest?.envType ?: RootfsManifest.ENV_GENERIC

    /** 是否为纯容器（无主程序）。 */
    val isGeneric: Boolean get() = manifest?.isGeneric ?: true
}
