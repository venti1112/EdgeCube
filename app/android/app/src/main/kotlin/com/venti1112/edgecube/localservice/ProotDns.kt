package com.venti1112.edgecube.localservice

import android.content.Context
import android.net.ConnectivityManager
import java.io.File

/**
 * 写入 rootfs 内的 `/etc/resolv.conf`。
 *
 * proot 不会继承 Android 的 DNS 配置（Android 根本没有 /etc/resolv.conf），
 * 不显式写入的话容器内所有域名解析都会失败：daemon 下载 JDK、查询 Mojang
 * 服务、检查更新都会报「无法解析主机」。
 */
object ProotDns {

    private val DEFAULT_DNS = listOf("8.8.8.8", "1.1.1.1")

    fun ensureResolvConf(context: Context, rootfsDir: File) {
        val file = File(rootfsDir, "etc/resolv.conf")
        file.parentFile?.mkdirs()
        file.writeText(buildString {
            for (server in systemDnsServers(context)) {
                appendLine("nameserver $server")
            }
        })
    }

    /** 读取系统当前 DNS；拿不到就退回公共 DNS。 */
    fun systemDnsServers(context: Context): List<String> {
        val fromSystem = try {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            val network = cm?.activeNetwork ?: return DEFAULT_DNS
            cm.getLinkProperties(network)?.dnsServers
                ?.mapNotNull { it.hostAddress }
                ?.filter { it.isNotBlank() }
                .orEmpty()
        } catch (_: Throwable) {
            emptyList()
        }
        return fromSystem.ifEmpty { DEFAULT_DNS }
    }
}
