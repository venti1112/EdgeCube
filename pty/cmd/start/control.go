//go:build !windows
// +build !windows

package start

import (
	"fmt"
	"net"
	"os"
	"time"

	pty "edgecube/pty/console"
)

// runControl:监听 Unix domain socket 控制通道(替代单向 FIFO,支持 PTY → daemon 双向上报),
// 接受 daemon 连接,每连接独立 goroutine 处理 RESIZE 帧;连接断开后继续等待重连。
func runControl(sock string, con pty.Console) error {
	if err := os.Remove(sock); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove control socket error: %w", err)
	}
	ln, err := net.Listen("unix", sock)
	if err != nil {
		return fmt.Errorf("listen control socket error: %w", err)
	}
	defer ln.Close()

	if testFifoResize {
		go func() {
			time.Sleep(time.Second * 5)
			_ = testUnixResize(sock)
		}()
	}

	for {
		conn, err := ln.Accept()
		if err != nil {
			return fmt.Errorf("accept control socket error: %w", err)
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
	conn, err := net.DialTimeout("unix", path, time.Second)
	if err != nil {
		return nil, err
	}
	return conn, nil
}

func testUnixResize(sock string) error {
	conn, err := dialControl(sock)
	if err != nil {
		return fmt.Errorf("open control socket error: %w", err)
	}
	defer conn.Close()
	u := newConnUtils(conn, conn)
	return testResize(u)
}