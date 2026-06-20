package com.venti1112.edgecube.ssh

import android.content.Context
import android.system.Os
import android.system.OsConstants
import com.venti1112.edgecube.server.EcPty
import com.venti1112.edgecube.shell.ShellResolver
import org.apache.sshd.server.Environment
import org.apache.sshd.server.Signal
import org.apache.sshd.server.SignalListener
import org.apache.sshd.server.channel.ChannelSession
import org.apache.sshd.server.session.ServerSession
import org.apache.sshd.server.shell.InvertedShell
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import kotlin.concurrent.thread

/**
 * 把 MINA SSHD 的 SSH 终端（shell 通道）桥接到应用自带的 PTY 工厂 [EcPty]。
 *
 * 复用与 Flutter 内置终端完全相同的底层原语：[EcPty] 每次 `createSubprocess` 在 /dev/ptmx
 * 上 fork 出一个**独立**的伪终端（独立 master fd + pid），[ShellResolver] 负责解析 shell
 * 二进制与构造环境。因此每个 SSH 客户端的每个 shell 通道都拥有自己的 PTY，多会话天然隔离
 * （不复用单例 `ShellProcessManager`，那是为单个 UI 终端设计的）。
 *
 * 实现 [InvertedShell] 的「反转流」语义（站在子进程视角命名）：
 *  - [getInputStream] 返回 PTY master 的写端：SSH server 把客户端按键写进来 → 子进程 stdin；
 *  - [getOutputStream] 返回 PTY master 的读端：SSH server 从这里读 → 子进程 stdout；
 *  - [getErrorStream] 返回 null：PTY 已把 stderr 合并进 master。
 *
 * 回显不在此处理（不调 setPtyEcho）：由 PTY 的 tty 行规负责，这正是真实终端体验的来源。
 *
 * @param context 应用上下文（解析 nativeLibraryDir 与环境）。
 * @param rootDir 终端初始工作目录（当前实例目录，与 SFTP 根目录一致）。
 */
class EcPtyInvertedShell(
    private val context: Context,
    private val rootDir: String,
) : InvertedShell {

    private companion object {
        const val DEFAULT_ROWS = 24
        const val DEFAULT_COLS = 80
        const val CELL_W = 8
        const val CELL_H = 16
    }

    private var fd = -1
    private var pid = -1
    private var toPty: FileOutputStream? = null
    private var fromPty: FileInputStream? = null

    @Volatile private var alive = false
    @Volatile private var exitCode = -1

    private var environment: Environment? = null
    private var winchListener: SignalListener? = null
    private var serverSession: ServerSession? = null
    private var channelSession: ChannelSession? = null

    override fun start(channel: ChannelSession, env: Environment) {
        environment = env
        channelSession = channel
        val nativeDir = context.applicationInfo.nativeLibraryDir
        // 初始工作目录用当前实例目录；无效则回退到默认目录（外部存储根或私有目录）。
        val cwd = rootDir.takeIf { File(it).isDirectory } ?: ShellResolver.defaultCwd(context)
        val spec = ShellResolver.resolveInteractive(nativeDir)
        val envMap = ShellResolver.baseEnv(context, nativeDir, cwd)
        // 优先采用客户端请求的 TERM，以获得正确的终端能力（颜色/全屏程序）。
        env.env[Environment.ENV_TERM]?.takeIf { it.isNotBlank() }?.let { envMap["TERM"] = it }
        val envp = envMap.map { "${it.key}=${it.value}" }.toTypedArray()

        val rows = env.env[Environment.ENV_LINES]?.toIntOrNull()?.takeIf { it > 0 } ?: DEFAULT_ROWS
        val cols = env.env[Environment.ENV_COLUMNS]?.toIntOrNull()?.takeIf { it > 0 } ?: DEFAULT_COLS

        val argv = ArrayList<String>()
        argv.add(spec.cmd)
        argv.addAll(spec.argvPrefix)

        val pidHolder = IntArray(1)
        val openedFd = EcPty.createSubprocess(
            spec.cmd, cwd, argv.toTypedArray(), envp, pidHolder, rows, cols, CELL_W, CELL_H,
        )
        if (openedFd < 0) throw IOException("创建 PTY 子进程失败")

        fd = openedFd
        pid = pidHolder[0]
        toPty = FileOutputStream(EcPty.fdFromInt(openedFd))
        fromPty = FileInputStream(EcPty.fdFromInt(openedFd))
        alive = true

        // 客户端窗口尺寸变化（SSH WINDOW_CHANGE → Signal.WINCH）时同步 PTY 窗口，
        // 子进程随之收到 SIGWINCH 重排。回调里从 Environment 重新读取列/行。
        val listener = SignalListener { _, _ ->
            val e = environment ?: return@SignalListener
            val r = e.env[Environment.ENV_LINES]?.toIntOrNull()?.takeIf { it > 0 }
                ?: return@SignalListener
            val c = e.env[Environment.ENV_COLUMNS]?.toIntOrNull()?.takeIf { it > 0 }
                ?: return@SignalListener
            try {
                EcPty.setPtyWindowSize(fd, r, c, CELL_W, CELL_H)
            } catch (_: Exception) {
            }
        }
        winchListener = listener
        env.addSignalListener(listener, Signal.WINCH)

        // 后台等待子进程退出并记录退出码（waitFor：>=0 为退出码，<0 为「信号取负」）。
        thread(name = "ssh-pty-wait") {
            val raw = try {
                EcPty.waitFor(pid)
            } catch (_: Exception) {
                -1
            }
            exitCode = if (raw < 0) 128 - raw else raw
            alive = false
        }
    }

    override fun getInputStream(): OutputStream =
        toPty ?: throw IllegalStateException("shell 尚未启动")

    override fun getOutputStream(): InputStream =
        fromPty ?: throw IllegalStateException("shell 尚未启动")

    override fun getErrorStream(): InputStream? = null

    override fun isAlive(): Boolean = alive

    override fun exitValue(): Int = exitCode

    // 来自 ServerSessionAware / 通道感知接口：保存并回传当前 SSH 会话与通道。
    override fun setSession(session: ServerSession) {
        serverSession = session
    }

    override fun getServerSession(): ServerSession? = serverSession

    override fun getServerChannelSession(): ChannelSession? = channelSession

    override fun destroy(channel: ChannelSession) {
        winchListener?.let { l -> environment?.removeSignalListener(l) }
        winchListener = null
        if (pid > 0) {
            try {
                Os.kill(pid, OsConstants.SIGTERM)
            } catch (_: Exception) {
            }
        }
        try {
            toPty?.close()
        } catch (_: Exception) {
        }
        try {
            fromPty?.close()
        } catch (_: Exception) {
        }
        if (fd >= 0) {
            try {
                EcPty.close(fd)
            } catch (_: Exception) {
            }
        }
        toPty = null
        fromPty = null
        alive = false
    }
}
