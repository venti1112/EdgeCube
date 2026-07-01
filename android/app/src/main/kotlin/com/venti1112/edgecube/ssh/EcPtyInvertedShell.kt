package com.venti1112.edgecube.ssh

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.Log
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
import java.util.concurrent.ArrayBlockingQueue
import kotlin.concurrent.thread

/**
 * 把 MINA SSHD 的 SSH 终端（shell 通道）桥接到应用自带的 PTY 工厂 [EcPty]。
 *
 * 复用与 Flutter 内置终端完全相同的底层原语：[EcPty] 每次 `createSubprocess` 在 /dev/ptmx
 * 上 fork 出一个**独立**的伪终端（独立 master fd + pid），[ShellResolver] 负责解析系统
 * shell 与构造环境。因此每个 SSH 客户端的每个 shell 通道都拥有自己的 PTY，多会话天然隔离
 * （不复用单例 `ShellProcessManager`，那是为单个 UI 终端设计的）。
 *
 * 实现 [InvertedShell] 的「反转流」语义（站在子进程视角命名）：
 *  - [getInputStream] 返回 PTY master 的写端：SSH server 把客户端按键写进来 → 子进程 stdin；
 *  - [getOutputStream] 返回 PTY master 的读端：SSH server 从这里读 → 子进程 stdout；
 *  - [getErrorStream] 返回 null：PTY 已把 stderr 合并进 master。
 *
 * 回显不在此处理（不调 setPtyEcho）：由 PTY 的 tty 行规负责，这正是真实终端体验的来源。
 *
 * @param context 应用上下文（用于 PTY 环境构造）。
 * @param rootDir 终端初始工作目录（当前实例目录，与 SFTP 根目录一致）。
 */
class EcPtyInvertedShell(
    private val context: Context,
    private val rootDir: String,
) : InvertedShell {

    private companion object {
        const val TAG = "EcPtyInvertedShell"
        const val DEFAULT_ROWS = 24
        const val DEFAULT_COLS = 80
        const val CELL_W = 8
        const val CELL_H = 16
    }

    private var fd = -1
    private var pid = -1
    private var toPty: FileOutputStream? = null
    private var fromPty: InputStream? = null

    @Volatile private var alive = false
    @Volatile private var exitCode = -1

    private var environment: Environment? = null
    private var winchListener: SignalListener? = null
    private var serverSession: ServerSession? = null
    private var channelSession: ChannelSession? = null

    /**
     * PTY master 读端的 InputStream 适配器。
     *
     * MINA SSHD 的 `InvertedShellWrapper.pumpStreams()` 在**单线程**中按顺序轮询三个方向：
     * ```
     * for (;;) {
     *     pumpStream(in, shellIn, buf)      // 客户端 → shell（从 SSH 通道读，写 PTY master）
     *     pumpStream(shellOut, out, buf)     // shell → 客户端（从 PTY master 读，写 SSH 通道）
     *     pumpStream(shellErr, err, buf)     // stderr（PTY 下为 null，跳过）
     *     if (!alive && all drained) exit
     *     sleep(...)
     * }
     * ```
     *
     * `pumpStream` 先调 `available()` 判断是否有数据。如果直接让 `available()` 返回 1 而
     * `read()` 阻塞在 PTY master fd 上，泵线程就卡死在 shell→client 这一步，永远回不到
     * client→shell 那一步——用户按键无法传递到 shell。
     *
     * 解决方案：用一个后台 **reader 线程**做真正的阻塞式 PTY 读取，将读到的字节放入
     * [ArrayBlockingQueue]。`available()` 和 `read()` 只与队列交互（poll 带短超时），
     * **绝不直接阻塞在 fd 上**，从而保证泵线程能及时回到 client→shell 方向处理用户输入。
     *
     * reader 线程在 PTY slave 关闭后（shell 退出）收到 EIO → `read()` 返回 -1 → 线程退出，
     * 不会泄漏。
     */
    private inner class PtyInputStream(private val delegate: FileInputStream) : InputStream() {
        /** 缓冲队列：reader 线程 put，泵线程 poll。最大约 64KB。 */
        private val queue = ArrayBlockingQueue<ByteArray>(16)

        /** 哨兵：reader 线程结束时放入，通知 read() 返回 EOF。 */
        private val EOF_SENTINEL = ByteArray(0)

        @Volatile private var eof = false

        /**
         * 泵线程是否已经消费了 EOF 哨兵。
         *
         * 与 [eof]（reader 线程设置）不同：[eof] 表示 reader 线程已结束读取，但队列中
         * 可能还有未消费的数据；[pumpSawEof] 表示泵线程已经取走了 EOF 哨兵，此后
         * `available()` 才允许返回 0，让 MINA SSHD 泵退出循环。
         */
        @Volatile private var pumpSawEof = false

        /** 上一次 poll 出的数组未消费完的剩余部分（避免放回队列破坏顺序）。 */
        private var leftover: ByteArray? = null
        private var leftoverOff = 0

        init {
            thread(name = "ssh-pty-read-$pid", isDaemon = true) {
                val buf = ByteArray(4096)
                try {
                    while (!eof) {
                        val n = delegate.read(buf)
                        if (n <= 0) break
                        val data = buf.copyOf(n)
                        // 队列满时丢弃最旧的一块腾出空间（极端情况下会丢数据，但不会阻塞 reader）
                        while (!queue.offer(data, 100, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                            queue.poll()
                        }
                    }
                } catch (_: Exception) {
                    // EIO（shell 退出后 PTY slave 关闭）或 fd 被关闭
                }
                eof = true
                queue.offer(EOF_SENTINEL)
            }
        }

        override fun available(): Int {
            // 泵线程已消费 EOF 哨兵：可以安全返回 0，让 MINA SSHD 泵退出。
            if (pumpSawEof) return 0
            // 优先消费 leftover（上一次 poll 出的数组未消费完的部分）。
            leftover?.let { return it.size - leftoverOff }
            val first = queue.peek()
            if (first != null) {
                // 队列头是 EOF 哨兵：标记 pumpSawEof 并返回 0。
                if (first === EOF_SENTINEL) {
                    pumpSawEof = true
                    return 0
                }
                return first.size
            }
            // 队列为空但 reader 线程尚未结束（可能还在 read 系统调用中）。
            // 返回 1 迫使泵线程调用 read()，read() 内部 poll 带短超时等待新数据，
            // 这样既不会阻塞泵线程，也不会让它过早退出。
            if (!eof) return 1
            // eof 已设置但队列空（极端情况：reader 线程刚设置 eof 还未来得及 offer 哨兵）。
            return if (pumpSawEof) 0 else 1
        }

        override fun read(): Int {
            val buf = ByteArray(1)
            val n = read(buf, 0, 1)
            return if (n == -1) -1 else buf[0].toInt() and 0xFF
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            // 1. 先消费上一次未用完的 leftover
            leftover?.let { lo ->
                val avail = lo.size - leftoverOff
                val n = minOf(len, avail)
                System.arraycopy(lo, leftoverOff, b, off, n)
                leftoverOff += n
                if (leftoverOff >= lo.size) { leftover = null; leftoverOff = 0 }
                return n
            }
            if (pumpSawEof) return -1

            // 2. 从队列 poll（短超时），不阻塞泵线程
            val data = queue.poll(50, java.util.concurrent.TimeUnit.MILLISECONDS)
                ?: return if (pumpSawEof) -1 else 0
            if (data === EOF_SENTINEL) {
                pumpSawEof = true
                return -1
            }

            // 3. 拷贝请求长度的数据，剩余保存到 leftover（而非放回队列，保证顺序）
            val n = minOf(len, data.size)
            System.arraycopy(data, 0, b, off, n)
            if (n < data.size) {
                leftover = data
                leftoverOff = n
            }
            return n
        }

        override fun read(b: ByteArray): Int = read(b, 0, b.size)

        override fun close() {
            eof = true
            // delegate.close() 已被外部覆盖为 no-op（fd 由 destroy() 统一管理），
            // 此处调用仅保持语义完整；eof=true 用于终止 reader 线程。
            delegate.close()
        }
    }

    override fun start(channel: ChannelSession, env: Environment) {
        environment = env
        channelSession = channel

        // ── 1. 解析 shell 与 cwd ──
        val spec = ShellResolver.resolveInteractive()
        // 初始工作目录用当前实例目录；无效则回退到默认目录（外部存储根或私有目录）。
        var cwd = rootDir.takeIf { File(it).isDirectory } ?: ShellResolver.defaultCwd(context)

        Log.i(TAG, "Starting SSH shell: cmd=${spec.cmd}, argv=${spec.argvPrefix}, cwd=$cwd")

        // ── 2. 预检查：shell 二进制是否可执行 ──
        if (!File(spec.cmd).canExecute()) {
            val msg = "EdgeCube: shell binary not found or not executable: ${spec.cmd}\r\n"
            Log.e(TAG, msg.trim())
            throw IOException(msg.trim())
        }

        // ── 3. 预检查：cwd 是否有效，无效则回退 ──
        if (!File(cwd).isDirectory) {
            Log.w(TAG, "cwd not a directory: $cwd, falling back to default")
            cwd = ShellResolver.defaultCwd(context)
        }

        // ── 4. 构造环境变量 ──
        val envMap = ShellResolver.baseEnv(context, cwd)
        // 优先采用客户端请求的 TERM，以获得正确的终端能力（颜色/全屏程序）。
        env.env[Environment.ENV_TERM]?.takeIf { it.isNotBlank() }?.let { envMap["TERM"] = it }
        val envp = envMap.map { "${it.key}=${it.value}" }.toTypedArray()

        val rows = env.env[Environment.ENV_LINES]?.toIntOrNull()?.takeIf { it > 0 } ?: DEFAULT_ROWS
        val cols = env.env[Environment.ENV_COLUMNS]?.toIntOrNull()?.takeIf { it > 0 } ?: DEFAULT_COLS

        val argv = ArrayList<String>()
        argv.add(spec.cmd)
        argv.addAll(spec.argvPrefix)

        // ── 5. 创建 PTY 子进程 ──
        val pidHolder = IntArray(1)
        val openedFd: Int
        try {
            openedFd = EcPty.createSubprocess(
                spec.cmd, cwd, argv.toTypedArray(), envp, pidHolder, rows, cols, CELL_W, CELL_H,
            )
        } catch (e: Exception) {
            Log.e(TAG, "PTY createSubprocess threw: ${e.message}", e)
            throw IOException("创建 PTY 子进程失败: ${e.message}", e)
        }
        if (openedFd < 0) {
            Log.e(TAG, "PTY createSubprocess returned fd=$openedFd")
            throw IOException("创建 PTY 子进程失败 (fd=$openedFd)")
        }

        fd = openedFd
        pid = pidHolder[0]
        Log.i(TAG, "PTY created: fd=$fd, pid=$pid, shell=${spec.cmd}")

        // ── 6. 创建 I/O 流 ──
        // 关键：共享同一个 FileDescriptor 对象，避免两个流各自持有独立 fd 副本导致
        // 一方 close 时把底层 fd 也关掉（另一方跟着失效）。
        //
        // FileOutputStream.close() 被覆盖为 no-op：MINA SSHD 的 pumpStream() 在检测到
        // SSH 通道 EOF（in.available() == -1）时会调用 shellIn.close()；默认实现会调用
        // Libcore.os.close(fd) 把 PTY master fd 关掉 → slave 侧立即收到 EOF → shell 退出。
        // 覆盖后 fd 的生命周期完全由 destroy() 中的 EcPty.close(fd) 控制。
        val sharedFd = EcPty.fdFromInt(openedFd)
        toPty = object : FileOutputStream(sharedFd) {
            override fun close() { /* fd 由 destroy() 统一管理 */ }
        }
        fromPty = PtyInputStream(object : FileInputStream(sharedFd) {
            override fun close() { /* fd 由 destroy() 统一管理 */ }
        })
        alive = true

        // ── 7. 启动完成，日志记录 ──
        // 注意：不向 PTY master 写入诊断信息，因为 PTY 行规会将 master 写入的数据
        // 回显到 master 读端，导致 shell 将其当作输入命令执行。
        Log.i(TAG, "SSH shell ready: fd=$fd, pid=$pid")

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
        thread(name = "ssh-pty-wait-$pid") {
            val raw = try {
                EcPty.waitFor(pid)
            } catch (e: Exception) {
                Log.w(TAG, "waitFor($pid) threw: ${e.message}")
                // waitFor 失败时（如 ECHILD），尝试 kill(pid, 0) 判断进程是否仍存活
                try {
                    Os.kill(pid, 0)
                    // 进程仍存活，waitFor 被异常中断，重试一次
                    Log.i(TAG, "Process $pid still alive after waitFor failure, retrying")
                    try { EcPty.waitFor(pid) } catch (_: Exception) { -1 }
                } catch (_: Exception) {
                    // kill(pid, 0) 也失败（ESRCH），进程确实已退出
                    -1
                }
            }
            exitCode = when {
                raw >= 0 -> raw                // 正常退出码
                raw > -1000 -> 128 - raw       // 信号退出（-signum）
                else -> 1                       // waitpid 本身失败（-(1000+errno)）
            }
            alive = false
            // 诊断日志：区分正常退出/信号退出/异常，便于排查 SSH 终端断开原因。
            val reason = when {
                raw >= 0 -> "normal exit (code=$raw)"
                raw > -1000 -> "killed by signal ${-raw} (exit code=$exitCode)"
                else -> "waitpid error (raw=$raw, errno=${-raw - 1000})"
            }
            Log.w(TAG, "Shell process $pid EXITED: $reason")
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
        Log.w(TAG, "destroy() called: pid=$pid, fd=$fd, alive=$alive",
            Throwable("destroy() call stack"))
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
