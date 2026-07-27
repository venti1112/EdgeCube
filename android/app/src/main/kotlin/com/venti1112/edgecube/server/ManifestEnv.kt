package com.venti1112.edgecube.server

import java.io.File

/**
 * `.ecpkg` 清单 env 的叠加规则（服务端 / 隧道 / Forge 安装器共用）。
 */
object ManifestEnv {

    /**
     * 叠加清单中的 env 到基础环境。
     * - ${RUNTIME_DIR} 替换为运行时根目录绝对路径
     * - PATH / LD_LIBRARY_PATH 采用追加而非覆盖
     * - EC_* / LD_PRELOAD / TMPDIR 不允许被包覆盖
     */
    fun apply(
        env: MutableMap<String, String>,
        manifest: EcManifest,
        runtimeDir: File,
    ) {
        for ((key, rawValue) in manifest.env) {
            // App 内部加载器变量不可被包覆盖
            if (key.startsWith("EC_") || key == "LD_PRELOAD" || key == "TMPDIR") continue
            val value = rawValue.replace("\${RUNTIME_DIR}", runtimeDir.absolutePath)
            when (key) {
                "PATH" -> {
                    val existing = env["PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                "LD_LIBRARY_PATH" -> {
                    val existing = env["LD_LIBRARY_PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                else -> env[key] = value
            }
        }
    }
}
