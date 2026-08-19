package start

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"sync"

	pty "edgecube/pty/console"
	"github.com/zijiren233/stream"
)

type connUtils struct {
	r *stream.Reader
	w *stream.Writer
}

func newConnUtils(r io.Reader, w io.Writer) *connUtils {
	return &connUtils{
		r: stream.NewReader(r, stream.BigEndian),
		w: stream.NewWriter(w, stream.BigEndian),
	}
}

func (cu *connUtils) ReadMessage() (uint8, []byte, error) {
	var (
		length  uint16
		msgType uint8
	)
	data, err := cu.r.U8(&msgType).U16(&length).ReadBytes(int(length))
	return msgType, data, err
}

func (cu *connUtils) SendMessage(msgType uint8, data any) error {
	b, err := json.Marshal(data)
	if err != nil {
		return err
	}
	return cu.w.U8(msgType).U16(uint16(len(b))).Bytes(b).Error()
}

// controlSession:一条已建立的控制通道连接(双向)。
// daemon → PTY:RESIZE 帧(handleConn 读循环);PTY → daemon:ERROR/EXIT/INFO 帧(上报)。
type controlSession struct {
	u  *connUtils
	mu sync.Mutex
}

var currentSession struct {
	sync.Mutex
	sess *controlSession
}

func setCurrentSession(s *controlSession) {
	currentSession.Lock()
	currentSession.sess = s
	currentSession.Unlock()
}

func clearCurrentSession(s *controlSession) {
	currentSession.Lock()
	if currentSession.sess == s {
		currentSession.sess = nil
	}
	currentSession.Unlock()
}

// sendOnSession:向当前活动连接发一帧,成功返回 true。
func sendOnSession(msgType uint8, data any) bool {
	currentSession.Lock()
	s := currentSession.sess
	currentSession.Unlock()
	if s == nil {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.u.SendMessage(msgType, data) == nil
}

// handleConn:daemon → PTY 方向的控制帧分发(RESIZE),连接断开即返回。
func handleConn(u *connUtils, con pty.Console) error {
	for {
		t, msg, err := u.ReadMessage()
		if err != nil {
			return fmt.Errorf("read message error: %w", err)
		}
		switch t {
		case RESIZE:
			resize := resizeMsg{}
			err := json.Unmarshal(msg, &resize)
			if err != nil {
				_ = u.SendMessage(
					ERROR,
					&errorMsg{
						Msg: fmt.Sprintf("unmarshal resize message error: %s", err),
					},
				)
				continue
			}
			err = con.SetSize(resize.Width, resize.Height)
			if err != nil {
				_ = u.SendMessage(
					ERROR,
					&errorMsg{
						Msg: fmt.Sprintf("resize error: %s", err),
					},
				)
				continue
			}
		}
	}
}

func testResize(u *connUtils) error {
	err := u.SendMessage(
		RESIZE,
		&resizeMsg{
			Width:  20,
			Height: 20,
		},
	)
	if err != nil {
		return fmt.Errorf("send resize message error: %w", err)
	}
	return nil
}

// dialControl:连接控制通道(Unix socket / Windows named pipe),兜底上报用。
func dialControl(path string) (net.Conn, error) {
	return dialControlImpl(path)
}