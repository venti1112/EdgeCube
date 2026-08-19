#!/usr/bin/env python3
"""EdgeCube PTY 集成测试(Go 二进制行为验证)

覆盖:
  1. 握手行 JSON 走 stderr,stdout 只有终端输出
  2. UDS 控制通道双向:RESIZE 帧生效、ERROR 帧、EXIT 帧(正常退出带 code)
  3. stdin 半关闭 → INFO stdin_closed 帧,进程继续运行
  4. SIGKILL → EXIT 帧带 signal
  5. 启动失败 → stderr 结构化错误
用法: python3 integration.py [pty二进制路径]
"""
import json
import os
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "pty")
FAILED = []


def frame(msg_type, payload: bytes) -> bytes:
    return bytes([msg_type]) + struct.pack(">H", len(payload)) + payload


def read_frame(conn, timeout=5.0):
    conn.settimeout(timeout)
    head = conn.recv(3)
    if not head:
        return None, None
    msg_type = head[0]
    length = struct.unpack(">H", head[1:3])[0]
    data = b""
    while len(data) < length:
        chunk = conn.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    return msg_type, data


def expect(cond, name):
    if cond:
        print(f"  ✓ {name}")
    else:
        FAILED.append(name)
        print(f"  ✗ {name}")


def drain(stream, cond, timeout=5.0, size=65536):
    """从流中读直到 cond(data) 为真或超时,返回累积数据"""
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = os.read(stream.fileno(), size)
        if not chunk:
            break
        buf += chunk
        if cond(buf):
            break
    return buf


def scenario_clean_exit():
    print("[场景 A] 干净退出:握手行 stderr、RESIZE、EXIT 帧 code")
    sock = tempfile.mktemp(prefix="pty-test-a-")
    p = subprocess.Popen([BIN, "-fifo", sock, "-cmd", '["sh"]'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    time.sleep(0.3)
    # 1. stderr 首行是握手 JSON(非阻塞读)
    stderr_first = p.stderr.readline().decode()
    handshake = json.loads(stderr_first)
    expect(handshake.get("pid", 0) > 0, "握手行 JSON {pid} 在 stderr")
    # 2. stdout 此刻应无数据(终端未输出)
    leftover = drain(p.stdout, lambda b: len(b) > 0, timeout=0.3)
    expect(b'"pid"' not in leftover, "stdout 无握手 JSON 残留")
    # 3. 连接控制通道(长连收帧)
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(sock)
    conn.settimeout(5)
    # 4. 发 RESIZE
    conn.sendall(frame(0x04, json.dumps({"width": 40, "height": 15}).encode()))
    # 5. 写命令并读输出
    p.stdin.write(b"echo HELLO_PTY\n")
    p.stdin.flush()
    out = drain(p.stdout, lambda b: b"HELLO_PTY" in b)
    expect(b"HELLO_PTY" in out, "stdout 透传终端输出")
    # 6. 干净退出 → EXIT 帧
    p.stdin.write(b"exit 7\n")
    p.stdin.flush()
    t, data = read_frame(conn)
    expect(t == 0x05 and json.loads(data).get("code") == 7,
           f"EXIT 帧 code=7 (got type={t} data={data})")
    p.wait(timeout=5)
    conn.close()
    os.unlink(sock)


def scenario_stdin_eof():
    print("[场景 B] stdin 半关闭:INFO stdin_closed 且进程存活")
    sock = tempfile.mktemp(prefix="pty-test-b-")
    p = subprocess.Popen([BIN, "-fifo", sock, "-cmd", '["sh"]'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    time.sleep(0.3)
    game_pid = json.loads(p.stderr.readline().decode())["pid"]
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(sock)
    p.stdin.close()  # 半关闭
    t, data = read_frame(conn, timeout=5)
    expect(t == 0x06 and json.loads(data).get("event") == "stdin_closed",
           f"INFO stdin_closed 帧 (got type={t} data={data})")
    expect(p.poll() is None, "stdin 关闭后进程继续运行")
    # kill 游戏进程(不是 PTY 程序)→ EXIT 帧带 signal
    os.kill(game_pid, signal.SIGKILL)
    t, data = read_frame(conn, timeout=5)
    sig = json.loads(data).get("signal")
    expect(t == 0x05 and sig in ("killed", "SIGKILL"),
           f"SIGKILL → EXIT 帧带 signal (got type={t} data={data})")
    p.wait(timeout=5)
    conn.close()
    os.unlink(sock)


def scenario_start_failure():
    print("[场景 C] 启动失败:stderr 结构化错误")
    sock = tempfile.mktemp(prefix="pty-test-c-")
    p = subprocess.Popen([BIN, "-fifo", sock, "-cmd", '["/nonexistent/bin/xyz"]'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    err = p.stderr.readline().decode()
    expect("[EDGECUBE-PTY]" in err, "错误前缀 [EDGECUBE-PTY]")
    expect("New pty error" in err or "Process start error" in err, "启动失败信息")
    p.wait(timeout=5)
    if os.path.exists(sock):
        os.unlink(sock)


def main():
    if not os.path.exists(BIN):
        print(f"缺少二进制: {BIN},请先 go build -o test/pty ./cmd/start")
        sys.exit(1)
    scenario_clean_exit()
    scenario_stdin_eof()
    scenario_start_failure()
    if FAILED:
        print(f"\n失败 {len(FAILED)} 项: {FAILED}")
        sys.exit(1)
    print("\n全部通过 ✓")


if __name__ == "__main__":
    main()