package com.venti1112.edgecube.ssh

import android.content.Context
import org.apache.sshd.common.config.keys.KeyUtils
import org.apache.sshd.common.digest.BuiltinDigests
import org.apache.sshd.common.file.virtualfs.VirtualFileSystemFactory
import org.apache.sshd.common.io.nio2.Nio2ServiceFactoryFactory
import org.apache.sshd.common.util.OsUtils
import org.apache.sshd.common.util.io.PathUtils
import org.apache.sshd.core.CoreModuleProperties
import org.apache.sshd.server.SshServer
import org.apache.sshd.server.auth.password.PasswordAuthenticator
import org.apache.sshd.server.keyprovider.SimpleGeneratorHostKeyProvider
import org.apache.sshd.server.session.ServerSession
import org.apache.sshd.server.shell.InvertedShellWrapper
import org.apache.sshd.server.shell.ShellFactory
import org.apache.sshd.sftp.server.FileHandle
import org.apache.sshd.sftp.server.Handle
import org.apache.sshd.sftp.server.SftpEventListener
import org.apache.sshd.sftp.server.SftpSubsystemFactory
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.io.File
import java.nio.file.AccessDeniedException
import java.nio.file.CopyOption
import java.nio.file.OpenOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.security.Security

/**
 * SSH 服务器管理器：在 Android 原生侧运行一个 SSH 服务，同时提供
 *  - SFTP 子系统（安全文件传输，根目录锁定为指定 rootDir）；
 *  - SSH 终端（交互式 shell，桥接到自带 PTY，见 [EcPtyInvertedShell]）。
 *
 * 基于 Apache MINA SSHD（纯 Java），单例。SFTP 与 SSH 终端共用同一端口、同一主机密钥与
 * 同一套账号；两者各由开关独立启停（至少启用其一才会启动）。与 FTP（Apache FTPServer）
 * 是相互独立的服务，可同时运行。
 *
 * 安全性：强制用户名 + 密码认证（不允许匿名）。主机密钥持久化在应用私有目录，
 * 客户端二次连接不会出现 host key changed 警告。
 */
object SshServerManager {

    @Volatile
    private var server: SshServer? = null

    @Volatile
    private var securityInitialized = false

    /** SSH 服务是否正在运行。 */
    val isRunning: Boolean
        get() = server?.isOpen == true

    /**
     * 启动 SSH 服务。
     *
     * @param context 应用上下文（用于主机密钥路径与 PTY 环境）。
     * @param rootDir SFTP 根目录与 SSH 终端初始工作目录（客户端 SFTP 只能访问此目录内）。
     * @param port 监听端口（默认建议 2222；<1024 在非 root Android 无法绑定）。
     * @param username 登录用户名（不可为空）。
     * @param password 登录密码（不可为空）。
     * @param writable 是否允许 SFTP 写入（上传/删除/重命名）；仅作用于 SFTP，不限制 SSH 终端。
     * @param sftpEnabled 是否启用 SFTP 文件访问。
     * @param shellEnabled 是否启用 SSH 终端。
     * @param ipv6Enabled 是否启用 IPv6（双栈）监听；关闭时仅监听 IPv4。
     */
    @Synchronized
    fun start(
        context: Context,
        rootDir: String,
        port: Int,
        username: String,
        password: String,
        writable: Boolean,
        sftpEnabled: Boolean,
        shellEnabled: Boolean,
        ipv6Enabled: Boolean,
    ) {
        if (isRunning) throw IllegalStateException("SSH 服务已在运行")
        require(sftpEnabled || shellEnabled) { "SFTP 与 SSH 终端至少需启用其一" }
        require(username.isNotBlank() && password.isNotBlank()) { "SSH 服务要求设置用户名与密码" }

        initSecurity(context)

        val root = File(rootDir)
        if (!root.isDirectory) root.mkdirs()

        val sshd = SshServer.setUpDefaultServer()
        sshd.port = port
        // host="::" 绑定 IPv6 通配地址，在 Android（内核 bindv6only=0）上为双栈，可同时接受
        // IPv4 与 IPv6；"0.0.0.0" 则仅监听 IPv4。与 FTP 监听器一致。
        sshd.host = if (ipv6Enabled) "::" else "0.0.0.0"
        // 显式指定 NIO2 传输工厂，避免 R8/资源合并下 ServiceLoader 自动发现失效。
        sshd.ioServiceFactoryFactory = Nio2ServiceFactoryFactory()

        sshd.keyPairProvider = hostKeyProvider(context)

        // 强制密码认证：用户名与密码必须完全匹配（不允许匿名）。
        sshd.passwordAuthenticator = PasswordAuthenticator { user, pass, _ ->
            user == username && pass == password
        }

        if (sftpEnabled) {
            val sftpFactory = SftpSubsystemFactory.Builder().build()
            // 只读模式：拦截一切写操作（含写打开、删除、重命名、建目录、改属性）。
            if (!writable) sftpFactory.addSftpEventListener(ReadOnlySftpEventListener)
            sshd.subsystemFactories = listOf(sftpFactory)
            // 把每个会话 jail 到 rootDir 子树，禁止越权访问其它目录。
            sshd.fileSystemFactory = VirtualFileSystemFactory(root.toPath())
        }

        if (shellEnabled) {
            // SSH 终端：每个 shell 通道新建一个独立 PTY（多会话天然隔离）。
            val appContext = context.applicationContext
            val rootPath = root.absolutePath
            sshd.shellFactory = ShellFactory {
                InvertedShellWrapper(EcPtyInvertedShell(appContext, rootPath))
            }
        }
        // 不提供 exec/command 通道（仅交互式 shell 与 SFTP）。
        sshd.commandFactory = null

        // 禁用空闲超时与心跳超时，避免 shell 通道在用户未输入时被服务端关闭。
        // MINA SSHD 默认 IDLE_TIMEOUT = 10 分钟，对于长时间不操作的 SSH 终端可能过短。
        val noTimeout = java.time.Duration.ZERO
        CoreModuleProperties.IDLE_TIMEOUT.set(sshd, noTimeout)
        CoreModuleProperties.NIO2_READ_TIMEOUT.set(sshd, noTimeout)
        CoreModuleProperties.AUTH_TIMEOUT.set(sshd, noTimeout)

        sshd.start()
        server = sshd
    }

    /** 停止 SSH 服务。 */
    @Synchronized
    fun stop() {
        server?.let {
            try {
                it.stop(true)
            } catch (_: Exception) {
            }
        }
        server = null
    }

    /**
     * 返回 SSH 主机密钥的 SHA-256 指纹（OpenSSH 形式 `SHA256:...`），供页面展示以便首次连接核对。
     * 若主机密钥尚不存在会先生成并落盘（与服务启动时使用的是同一密钥）。失败时返回 null。
     */
    fun hostKeyFingerprint(context: Context): String? {
        initSecurity(context)
        return try {
            val keyPair = hostKeyProvider(context).loadKeys(null).firstOrNull() ?: return null
            KeyUtils.getFingerPrint(BuiltinDigests.sha256, keyPair.public)
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 主机密钥提供器：持久化到应用私有目录（不放在 rootDir 内，避免随 SFTP 暴露给客户端）。
     * 首次访问生成 RSA-2048 并落盘，后续复用；客户端二次连接不会报 host key changed。
     */
    private fun hostKeyProvider(context: Context): SimpleGeneratorHostKeyProvider {
        val keyFile = File(context.filesDir, "ssh/hostkey.ser")
        keyFile.parentFile?.mkdirs()
        return SimpleGeneratorHostKeyProvider(keyFile.toPath()).apply {
            algorithm = "RSA"
            keySize = 2048
        }
    }

    /**
     * 一次性安全初始化（进程级，只执行一次）：
     *  - 移除 Android 内置的裁剪版 BouncyCastle，注册功能完整的打包版本（补 EdDSA 等算法）；
     *  - 告知 SSHD 运行在 Android，并补齐缺失的 user.home 解析（Android 上系统属性为空）。
     */
    private fun initSecurity(context: Context) {
        if (securityInitialized) return
        // 移除 Android 内置的裁剪版 BC，注册功能完整的打包版本（补 EdDSA / X25519 等算法）。
        // SSHD 的 BouncyCastleSecurityProviderRegistrar 会自动发现已注册的 BC 并使用。
        Security.removeProvider("BC")
        Security.insertProviderAt(BouncyCastleProvider(), 1)
        OsUtils.setAndroid(true)
        val home = context.filesDir.toPath()
        PathUtils.setUserHomeFolderResolver { home }
        securityInitialized = true
    }
}

/**
 * SFTP 只读监听器：在写入/删除/重命名/建目录/改属性及「以写方式打开」时抛
 * [AccessDeniedException]，从而在 [SshServerManager] 的 writable=false 模式下实现只读。
 */
private object ReadOnlySftpEventListener : SftpEventListener {

    private val WRITE_OPTIONS: Set<OpenOption> = setOf(
        StandardOpenOption.WRITE,
        StandardOpenOption.APPEND,
        StandardOpenOption.CREATE,
        StandardOpenOption.CREATE_NEW,
        StandardOpenOption.TRUNCATE_EXISTING,
        StandardOpenOption.DELETE_ON_CLOSE,
    )

    private fun deny(): Nothing =
        throw AccessDeniedException("SFTP 处于只读模式，写操作已被拒绝")

    override fun opening(session: ServerSession, remoteHandle: String, localHandle: Handle) {
        // 拦截以写方式（含 O_TRUNC/O_CREAT）打开文件，避免 truncate-on-open 绕过只读。
        val fileHandle = localHandle as? FileHandle ?: return
        if (fileHandle.openOptions.any { it in WRITE_OPTIONS }) deny()
    }

    override fun writing(
        session: ServerSession,
        remoteHandle: String,
        localHandle: FileHandle,
        offset: Long,
        data: ByteArray,
        dataOffset: Int,
        dataLen: Int,
    ) {
        deny()
    }

    override fun blocking(
        session: ServerSession,
        remoteHandle: String,
        localHandle: FileHandle,
        offset: Long,
        length: Long,
        mask: Int,
    ) {
        deny()
    }

    override fun removing(session: ServerSession, path: Path, isDirectory: Boolean) {
        deny()
    }

    override fun moving(
        session: ServerSession,
        srcPath: Path,
        dstPath: Path,
        opts: Collection<CopyOption>,
    ) {
        deny()
    }

    override fun creating(session: ServerSession, path: Path, attrs: Map<String, *>) {
        deny()
    }

    override fun linking(session: ServerSession, source: Path, target: Path, symLink: Boolean) {
        deny()
    }

    override fun modifyingAttributes(session: ServerSession, path: Path, attrs: Map<String, *>) {
        deny()
    }
}
