package com.venti1112.edgecube.proot

import android.content.Context
import java.io.File
import org.json.JSONObject

/**
 * proot 容器与内置运行时的 DNS 配置。
 *
 * proot 不自动继承 Android 系统的 DNS 配置（Android 没有 /etc/resolv.conf），
 * 若不在 rootfs 内显式写入，容器内所有域名解析都会失败（apt update、
 * Mojang 服务器连接等）。
 */
object ProotDns {

    /**
     * 确保 rootfs 内 /etc/resolv.conf 存在且含可用 DNS。
     *
     * 策略：优先使用用户在「网络设置」中配置的自定义 DNS（默认 8.8.8.8,1.1.1.1），
     * 从 `<filesDir>/config/network.json` 的 `customDns` 字段读取。
     * 始终覆盖写入，确保 rootfs 自带的 DNS 配置被替换。
     */
    fun ensureResolvConf(context: Context, rootfsDir: File) {
        val resolvConf = File(rootfsDir, "etc/resolv.conf")
        val dnsServers = loadCustomDnsServers(context)
        val content = buildString {
            dnsServers.forEach { appendLine("nameserver $it") }
        }
        resolvConf.parentFile?.mkdirs()
        resolvConf.writeText(content)
    }

    /**
     * 更新所有已安装 rootfs 的 /etc/resolv.conf。
     * 用户在「网络设置」中更改 DNS 后立即调用，使所有已导入的 rootfs 即时生效。
     */
    fun updateAllRootfsDns(context: Context) {
        val rootfsList = RootfsStore.installedRootfs(context)
        for (rootfs in rootfsList) {
            ensureResolvConf(context, rootfs.dir)
        }
    }

    /**
     * 从 `<filesDir>/config/network.json` 读取用户配置的自定义 DNS 服务器列表。
     *
     * Dart 侧 [NetworkStore] 将 DNS 存为逗号分隔字符串（`customDns` 字段），
     * 默认值 "8.8.8.8,1.1.1.1"。此处直接读取该 JSON 文件，避免通过 MethodChannel
     * 传参的额外开销。
     */
    fun loadCustomDnsServers(context: Context): List<String> {
        val defaultDns = listOf("8.8.8.8", "1.1.1.1")
        return try {
            val configFile = File(context.filesDir, "config/network.json")
            if (!configFile.isFile) return defaultDns
            val raw = configFile.readText()
            if (raw.isBlank()) return defaultDns
            val json = JSONObject(raw)
            val dnsStr = json.optString("customDns").takeIf { it.isNotBlank() }
                ?: return defaultDns
            val servers = dnsStr.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (servers.isEmpty()) defaultDns else servers
        } catch (_: Throwable) {
            defaultDns
        }
    }
}
