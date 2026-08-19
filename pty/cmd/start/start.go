package start

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"runtime"
	"syscall"
	"time"

	pty "edgecube/pty/console"
	"edgecube/pty/utils"
	"github.com/zijiren233/go-colorable"
	"golang.org/x/term"
)

var (
	dir, cmd, coder, ptySize string
	cmds                     []string
	control                  string
	testFifoResize           bool
)

// 帧类型(与 MCSManager 保持兼容:ERROR/PING/RESIZE 不变,新增 EXIT/INFO)
const (
	ERROR  uint8 = iota + 2 // 0x02 错误上报(PTY → daemon)
	PING                     // 0x03 保留
	RESIZE                   // 0x04 调整窗口(daemon → PTY)
	EXIT                     // 0x05 进程退出上报(PTY → daemon)
	INFO                     // 0x06 事件上报(PTY → daemon)
)

type PtyInfo struct {
	Pid int `json:"pid"`
}

type errorMsg struct {
	Msg string `json:"msg"`
}

type exitMsg struct {
	Code   int    `json:"code"`
	Signal string `json:"signal,omitempty"`
}

type infoMsg struct {
	Event string `json:"event"`
}

// waitStatus:st.Sys() 的可选接口(Unix 的 syscall.WaitStatus 实现;Windows 无,断言失败忽略)
type waitStatus interface {
	Signaled() bool
	Signal() syscall.Signal
}

func init() {
	if runtime.GOOS == "windows" {
		flag.StringVar(&cmd, "cmd", "[\"cmd\"]", "command")
	} else {
		flag.StringVar(&cmd, "cmd", "[\"sh\"]", "command")
	}

	flag.StringVar(&coder, "coder", "auto", "Coder")
	flag.StringVar(&dir, "dir", ".", "command work path")
	flag.StringVar(&ptySize, "size", "80,50", "Initialize pty size, stdin will be forwarded directly")
	flag.StringVar(&control, "fifo", "", "control channel endpoint (unix socket / windows named pipe)")
	flag.BoolVar(&testFifoResize, "test-fifo-resize", false, "test fifo resize")
}

func Main() {
	flag.Parse()
	con, err := newPTY()
	if err != nil {
		fail(err)
		return
	}
	if err = con.Start(dir, cmds); err != nil {
		fail(err)
		return
	}

	// 握手:首行 JSON 上报真实游戏进程 PID,走 stderr 避免混入终端输出
	info, _ := json.Marshal(&PtyInfo{Pid: con.Pid()})
	fmt.Fprintln(os.Stderr, string(info))

	defer con.Close()

	if control != "" {
		go func() {
			err := runControl(control, con)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] Control error: %v\n", err)
			}
		}()
	}

	// 进程退出上报(EXIT 帧 / stderr 兜底)
	exitDone := make(chan struct{})
	go func() {
		defer close(exitDone)
		if st, err := con.Wait(); err == nil {
			m := &exitMsg{Code: st.ExitCode()}
			if ws, ok := st.Sys().(waitStatus); ok {
				if ws.Signaled() {
					m.Signal = ws.Signal().String()
				}
			}
			reportControl(EXIT, m, "process exited code=%d signal=%s", m.Code, m.Signal)
		}
	}()

	// 数据通道:stdin 半关闭检测(daemon 关闭输入流时进程继续运行,上报事件)
	go func() {
		_, _ = io.Copy(con.StdIn(), os.Stdin)
		reportControl(INFO, &infoMsg{Event: "stdin_closed"}, "stdin closed")
	}()

	if err = handleStdOut(con); err != nil {
		fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] Handle stdout error: %v\n", err)
	}
	<-exitDone
}

// fail:启动失败。结构化 JSON 打到 stderr(daemon 读取判定),并尝试经控制通道发 ERROR 帧。
func fail(err error) {
	fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] New pty error: %v\n", err)
	reportControl(ERROR, &errorMsg{Msg: err.Error()}, "start failed")
}

func handleStdOut(c pty.Console) error {
	if colorable.IsReaderTerminal(os.Stdin) {
		oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
		if err != nil {
			return fmt.Errorf("make raw error: %w", err)
		}
		defer func() { _ = term.Restore(int(os.Stdin.Fd()), oldState) }()
	}
	if runtime.GOOS == "windows" && c.StdErr() != nil {
		go func() { _, _ = io.Copy(colorable.NewColorableStderr(), c.StdErr()) }()
	}
	_, ok := c.StdOut().(io.WriterTo)
	if !ok {
		return fmt.Errorf("StdOut is not io.WriterTo")
	}
	_, _ = io.Copy(colorable.NewColorableStdout(), c.StdOut())
	return nil
}

// reportControl:向控制通道上报一帧。优先走已建立的活动连接,否则兜底新建连接(1 秒超时)。
// 失败仅打 stderr 日志(daemon 同时读 stderr 兜底)。
func reportControl(msgType uint8, data any, logFmt string, args ...any) {
	fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] "+logFmt+"\n", args...)
	if control == "" {
		return
	}
	if sendOnSession(msgType, data) {
		return
	}
	conn, err := dialControl(control)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] report control (type=%d) failed: %v\n", msgType, err)
		return
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(time.Second))
	u := newConnUtils(conn, conn)
	if err := u.SendMessage(msgType, data); err != nil {
		fmt.Fprintf(os.Stderr, "[EDGECUBE-PTY] report control (type=%d) failed: %v\n", msgType, err)
	}
}

func newPTY() (pty.Console, error) {
	if err := json.Unmarshal([]byte(cmd), &cmds); err != nil {
		return nil, fmt.Errorf("unmarshal command error: %w", err)
	}
	con := pty.New(utils.CoderToType(coder))
	if err := con.ResizeWithString(ptySize); err != nil {
		return nil, fmt.Errorf("pty resize error: %w", err)
	}
	return con, nil
}

type resizeMsg struct {
	Width  uint `json:"width"`
	Height uint `json:"height"`
}