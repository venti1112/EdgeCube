package com.venti1112.edgecube.localservice

import android.content.Context
import java.io.File

/**
 * 本地服务的宿主路径与 guest 路径约定。
 *
 * 宿主目录统一挂在 `filesDir/local-service`，其中 `data` 是 daemon 的持久数据，
 * rootfs 放在独立的版本化目录：重装/升级本地环境不会碰用户数据。
 *
 * guest 侧统一 bind 到 `/opt/edgecube`，因此 daemon 的配置、数据、就绪文件
 * 在容器内都是稳定的绝对路径。
 */
object LocalServicePaths {

    const val GUEST_BASE = "/opt/edgecube"
    const val GUEST_DAEMON = "$GUEST_BASE/bin/edgecube-daemon"
    const val GUEST_READY = "$GUEST_BASE/ready.json"
    const val GUEST_DATA = "$GUEST_BASE/data"
    const val GUEST_CONFIG = "$GUEST_BASE/config"
    const val GUEST_HOME = "$GUEST_BASE/home"

    fun baseDir(context: Context): File = File(context.filesDir, "local-service")

    fun dataDir(context: Context): File = File(baseDir(context), "data")

    fun configDir(context: Context): File = File(baseDir(context), "config")

    fun homeDir(context: Context): File = File(baseDir(context), "home")

    fun readyFile(context: Context): File = File(baseDir(context), "ready.json")

    fun prootPidFile(context: Context): File = File(baseDir(context), "proot.pid")

    fun logFile(context: Context): File = File(baseDir(context), "daemon.log")

    /** 已解压 rootfs 的父目录；其下每个子目录是一个版本。 */
    fun rootfsBaseDir(context: Context): File = File(baseDir(context), "rootfs")

    fun installMarker(context: Context): File = File(baseDir(context), "rootfs-install.json")

    /** 启动前把绑定点需要的目录都建好（proot 要求 bind 源存在）。 */
    fun ensureDirs(context: Context) {
        for (dir in listOf(baseDir(context), dataDir(context), configDir(context), homeDir(context))) {
            dir.mkdirs()
        }
        File(baseDir(context), "bin").mkdirs()
        rootfsBaseDir(context).mkdirs()
    }
}
