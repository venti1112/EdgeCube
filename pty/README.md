# EdgeCube PTY(三端共享终端程序)

EdgeCube v2 的终端底座:一个 CLI 可执行文件,由 daemon(Rust 桌面 / Kotlin Android)spawn,
经三种通道与 daemon 通信。来源:MCSManager PTY(go, MIT),按 v2 需求改造。

## 三通道

### 1. 启动参数(CLI flags)

```
pty -size 164,40 -coder utf-8 -dir /abs/path -fifo /tmp/edgecube-xxx.sock \
    -cmd '["java","-jar","server.jar","nogui"]'
```

| flag | 说明 |
|---|---|
| `-cmd` | 命令 JSON 数组(防注入),首元素经 `exec.LookPath` 解析 |
| `-fifo` | 控制通道端点(Unix domain socket / Windows named pipe);空则不启用 |
| `-size` | 初始窗口 `cols,rows`,默认 `80,50` |
| `-coder` | 编码:auto/utf-8/gbk/big5/shift-jis/euckr/gb18030/utf-16 |
| `-dir` | 工作目录 |
| `-test-fifo-resize` | 测试模式:5 秒后自动发一次 resize |

### 2. 数据通道(stdin/stdout)

- 游戏进程的 PTY 输出 → 本程序 **stdout**(daemon 读取;流式编码转换 `-coder`)
- daemon 写按键 → 本程序 **stdin** → PTY 主设备
- stdin EOF(daemon 半关闭)= 仅终止转发,游戏进程不受影响(上报 `INFO stdin_closed`)

### 3. 控制通道(双向,daemon ↔ PTY)

二进制帧(BigEndian):`[msgType:1B][length:2B][payload:JSON]`

| type | 常量 | 方向 | payload |
|---|---|---|---|
| 0x02 | ERROR | PTY → daemon | `{"msg": "..."}` 错误上报 |
| 0x03 | PING | — | 保留 |
| 0x04 | RESIZE | daemon → PTY | `{"width": uint, "height": uint}` |
| 0x05 | EXIT | PTY → daemon | `{"code": int, "signal": "SIGKILL"?}` 进程退出上报 |
| 0x06 | INFO | PTY → daemon | `{"event": "stdin_closed"}` 事件上报 |

- Unix:**Unix domain socket**(改造点:原单向 FIFO 无法支撑 PTY → daemon 上报,换双向 socket);
  daemon 断线后 PTY 持续运行,重连即可继续收帧
- Windows:**命名管道**(winio,双向)
- PTY → daemon 的上报优先走当前活动连接,无连接时兜底新连(1s 超时)

### 握手

进程启动成功后,首行 JSON `{"pid": <游戏进程真实PID>}` 打到 **stderr**(改造点:原混入 stdout 的
终端输出,daemon 读 stderr 首行即可,无歧义)。启动失败时 stderr 输出 `[EDGECUBE-PTY]` 前缀错误。
daemon 侧:spawn 后读 stderr 首行,超时(如 10s)判定启动失败。

## 与上游 MCSManager PTY 的差异

1. 握手行 stdout → stderr
2. Unix 控制通道 FIFO → Unix domain socket(单向 → 双向)
3. 新增帧:EXIT(进程退出 code/signal 上报)、INFO(stdin 半关闭事件)
4. 新增:进程退出上报、stdin 半关闭检测(进程不受影响)
5. 错误日志前缀 `[MCSMANAGER-PTY]` → `[EDGECUBE-PTY]`
6. module: `github.com/MCSManager/pty` → `edgecube/pty`
7. 保留:编码转换全家桶、winpty 内嵌、`TERM=xterm-256color`、`-test-fifo-resize`、多行 stopCommand
   (daemon 侧拆行写入 stdin,PTY 无感知)

## 构建与测试

```bash
./scripts/build.sh                        # 本机
./scripts/build.sh linux/amd64 linux/arm64 windows/amd64   # 交叉编译
python3 test/integration.py test/pty      # 集成测试(握手/EXIT/INFO/SIGKILL/启动失败)
```

- `linux/*` 为静态二进制(CGO_ENABLED=0),`linux/arm64` 直接用于 Android(Kotlin daemon spawn,
  不经 proot)
- 集成测试断言:握手行走 stderr、RESIZE 帧、EXIT 帧(退出码/信号)、INFO stdin_closed、
  启动失败结构化报错