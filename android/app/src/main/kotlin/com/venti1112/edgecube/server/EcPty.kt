package com.venti1112.edgecube.server

import java.io.FileDescriptor

/**
 * 伪终端（PTY）子进程原语，native 实现见 cpp/ecpty.c（libecpty.so）。
 *
 * 用 fork + /dev/ptmx 创建一个带控制终端的子进程：返回的 int 是主设备 fd，
 * 子进程把从设备当作 stdin/stdout/stderr。父进程读写主设备 fd 即与子进程的
 * 终端通信。ANSI/VT 解析由 Flutter 侧 xterm.dart 负责，这里只管开 PTY 与收发字节。
 */
object EcPty {
    init {
        System.loadLibrary("ecpty")
    }

    /**
     * 创建 PTY 子进程。
     *
     * @param cmd        可执行文件绝对路径（如 liblaunch.so）。
     * @param cwd        子进程工作目录。
     * @param args       argv（含 argv[0]）。
     * @param envVars    形如 "KEY=VALUE" 的环境变量数组；子进程会先 clearenv 再逐个 putenv。
     * @param processId  长度为 1 的输出数组，写入子进程 pid。
     * @param rows/columns/cellWidth/cellHeight  初始窗口尺寸（字符行列 + 单元像素）。
     * @return 主设备（/dev/ptmx）fd；调用方负责最终 [close]。
     */
    external fun createSubprocess(
        cmd: String,
        cwd: String,
        args: Array<String>,
        envVars: Array<String>,
        processId: IntArray,
        rows: Int,
        columns: Int,
        cellWidth: Int,
        cellHeight: Int,
    ): Int

    /** 调整指定 PTY 的窗口尺寸，连接的程序会收到 SIGWINCH 并据此重排。 */
    external fun setPtyWindowSize(fd: Int, rows: Int, cols: Int, cellWidth: Int, cellHeight: Int)

    /** 开关 PTY 的回显（ECHO 标志）。命令行编辑模式关闭回显，原始终端模式开启。 */
    external fun setPtyEcho(fd: Int, echo: Boolean)

    /** 阻塞等待进程结束；返回 >=0 为退出码，<0 为「导致退出的信号取负」。 */
    external fun waitFor(pid: Int): Int

    /** 关闭一个 fd（close(2)）。 */
    external fun close(fileDescriptor: Int)

    /**
     * 把 int fd 包成 [FileDescriptor]，以便用 FileInputStream/FileOutputStream 读写。
     *
     * Android/JDK 没有公开的 `FileDescriptor(int)` 构造，反射写入私有 `descriptor` 字段
     * 是 Termux 等终端实现长期使用的稳定做法。
     */
    fun fdFromInt(fd: Int): FileDescriptor {
        val result = FileDescriptor()
        val field = FileDescriptor::class.java.getDeclaredField("descriptor")
        field.isAccessible = true
        field.setInt(result, fd)
        return result
    }
}
