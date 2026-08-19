package start

import (
	"fmt"
	"net"
	"time"

	pty "edgecube/pty/console"

	winio "github.com/Microsoft/go-winio"
)

// \\.\pipe\mypipe
// runControl:监听 Windows 命名管道控制通道(双向),接受 daemon 连接,每连接独立 goroutine。
func runControl(pipe string, con pty.Console) error {
	n, err := winio.ListenPipe(pipe, &winio.PipeConfig{})
	if err != nil {
		return fmt.Errorf("open control pipe error: %w", err)
	}
	defer n.Close()

	if testFifoResize {
		go func() {
			time.Sleep(time.Second * 5)
			_ = testWinResize(pipe)
		}()
	}

	for {
		conn, err := n.Accept()
		if err != nil {
			return fmt.Errorf("accept control pipe error: %w", err)
		}
		go func() {
			defer conn.Close()
			s := &controlSession{u: newConnUtils(conn, conn)}
			setCurrentSession(s)
			defer clearCurrentSession(s)
			_ = handleConn(s.u, con)
		}()
	}
}

func dialControlImpl(path string) (net.Conn, error) {
	timeout := time.Second
	return winio.DialPipe(path, &timeout)
}

func testWinResize(pipe string) error {
	n, err := dialControl(pipe)
	if err != nil {
		return fmt.Errorf("open control pipe error: %w", err)
	}
	defer n.Close()
	u := newConnUtils(n, n)
	return testResize(u)
}