package com.venti1112.edgecube.ftp

import org.apache.ftpserver.FtpServer
import org.apache.ftpserver.FtpServerFactory
import org.apache.ftpserver.listener.ListenerFactory
import org.apache.ftpserver.usermanager.PropertiesUserManagerFactory
import org.apache.ftpserver.usermanager.impl.BaseUser
import org.apache.ftpserver.usermanager.impl.WritePermission
import java.io.File

/**
 * FTP 服务器管理器：在 Android 原生侧运行一个 FTP 服务，对外暴露指定根目录。
 *
 * 使用 Apache FTPServer（纯 Java 实现），单例。同一时刻只允许一个 FTP 服务运行。
 * 根目录、端口、用户名、密码在 [start] 时传入；停止后可重新启动。
 */
object FtpServerManager {

    @Volatile
    private var server: FtpServer? = null

    /** FTP 服务是否正在运行。 */
    val isRunning: Boolean
        get() = server?.isStopped == false && server?.isSuspended == false

    /**
     * 启动 FTP 服务。
     *
     * @param rootDir FTP 根目录（客户端只能访问此目录内的文件）。
     * @param port 监听端口。
     * @param username 登录用户名（空则启用匿名访问）。
     * @param password 登录密码（匿名访问时忽略）。
     * @param writable 是否允许写入（上传/删除/重命名）。
     * @param ipv6Enabled 是否启用 IPv6（双栈）监听；关闭时仅监听 IPv4。
     */
    @Synchronized
    fun start(rootDir: String, port: Int, username: String, password: String, writable: Boolean, ipv6Enabled: Boolean) {
        if (isRunning) throw IllegalStateException("FTP 服务已在运行")

        val root = File(rootDir)
        if (!root.isDirectory) root.mkdirs()

        val serverFactory = FtpServerFactory()

        // 配置监听器（端口与绑定地址）。
        // serverAddress="::" 绑定 IPv6 通配地址，在 Android（内核 bindv6only=0）上为双栈，
        // 可同时接受 IPv4 与 IPv6 连接；"0.0.0.0" 则仅监听 IPv4。IPv6 客户端通过 EPSV
        // 协商被动数据连接（FTPServer 默认支持），无需额外配置。
        val listenerFactory = ListenerFactory()
        listenerFactory.port = port
        listenerFactory.serverAddress = if (ipv6Enabled) "::" else "0.0.0.0"
        serverFactory.addListener("default", listenerFactory.createListener())

        // 配置用户：匿名或具名，home 目录限定为 rootDir。
        val userManagerFactory = PropertiesUserManagerFactory()
        val userManager = userManagerFactory.createUserManager()
        val user = BaseUser().apply {
            this.name = if (username.isBlank()) "anonymous" else username
            this.password = if (username.isBlank()) "" else password
            this.homeDirectory = root.absolutePath
            if (writable) {
                this.authorities = listOf(WritePermission())
            }
        }
        userManager.save(user)
        // 匿名访问时同时注册 anonymous 用户。
        if (username.isBlank()) {
            // BaseUser name 已是 anonymous，无需重复。
        }
        serverFactory.userManager = userManager

        val srv = serverFactory.createServer()
        srv.start()
        server = srv
    }

    /** 停止 FTP 服务。 */
    @Synchronized
    fun stop() {
        server?.let {
            if (!it.isStopped) {
                it.stop()
            }
        }
        server = null
    }
}
