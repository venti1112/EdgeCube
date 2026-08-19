# EdgeCube WS 协议(proto/ws.md)

> 与 `openapi.yaml` 同版本约束(0.1.0),是 REST 之外的 WS 部分唯一契约。
> 设计参考:MCSManager `daemon/src/routers/stream_router.ts`(终端数据面)
> 与 `service/protocol.ts`(IPacket RPC 风格 + uuid 关联请求/响应)。
> 实现阶段标记 `phase` 对应 docs/PLAN.md §10。

## 1. 概述

两个独立 WS 端点,均挂载于 daemon 同一 HTTP 服务器:

| 端点 | 用途 | phase |
|---|---|---|
| `/api/v1/ws/events` | 全局事件订阅:实例状态/日志/玩家/监控/下载/崩溃/通知,带缓冲回放 | 0 |
| `/api/v1/ws/terminal` | 实例终端会话:全双工 I/O + resize + 命令框 | 0 |

设计要点(继承 MCSManager):

- **RPC 风格请求/响应**:客户端请求带 `id`(uuid),服务端响应回带同一 `id`;
  事件(服务端主动推送)为另一帧类型,互不混淆。
- **多客户端 fan-out**:同一实例可被多个客户端同时订阅/开终端,互不影响。
- **会话与实例隔离**:所有事件带 `instanceId`;终端会话按 `sessionId` 区分。
- **未认证即断**:连接建立后 6 秒内未完成鉴权,服务端主动断开(对齐 MCSManager)。

## 2. 连接与鉴权

```
ws://{host}:{port}/api/v1/ws/events?token={token}      # 或
wss://.../api/v1/ws/events                              # 带 Authorization: Bearer <token> 头
```

- 两种携带方式等价;Web 客户端无法自定义头时用 query。
- 鉴权失败:服务端发 `{"type":"error","code":"not_authenticated",...}` 后关闭连接。
- 心跳:客户端每 30s 发 `ping`,服务端回 `pong`;服务端 90s 无消息主动断开。
- 局域网绑定为 daemon 配置项;Android UI 默认走 127.0.0.1。

## 3. 通用帧格式

### 3.1 文本帧(JSON)

**客户端 → 服务端(请求)**:

```json
{ "type": "request", "id": "a1b2c3d4-...", "event": "subscribe", "data": { ... } }
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | string | 固定 `request` |
| `id` | uuid | 请求标识,响应原样回带 |
| `event` | string | 事件名(见 §4/§5) |
| `data` | object | 事件参数 |

**服务端 → 客户端(响应)**:

```json
{ "type": "response", "id": "a1b2c3d4-...", "status": "ok", "data": { ... } }
{ "type": "response", "id": "a1b2c3d4-...", "status": "error", "data": { "code": "instance_busy", "message": "..." } }
```

**服务端 → 客户端(事件推送)**:

```json
{ "type": "event", "event": "instance/state", "instanceId": "uuid", "data": { ... }, "ts": 1720000000000 }
```

| 字段 | 说明 |
|---|---|
| `event` | 事件名 |
| `instanceId` | 关联实例(全局事件可缺省) |
| `ts` | 毫秒时间戳 |
| `data` | 事件负载(见 §4 事件表) |

**服务端 → 客户端(错误/心跳)**:

```json
{ "type": "error", "code": "not_authenticated", "message": "..." }
{ "type": "pong" }
```

### 3.2 二进制帧(仅 /ws/terminal)

终端原始 PTY 字节:单个二进制帧 = 一段原始字节(UTF-8 或按实例 `outputEncoding` 转码后的字节)。客户端写按键可发二进制帧(原始字节),或文本帧 `write`(UTF-8 字符串)。

## 4. /api/v1/ws/events

### 4.1 客户端请求

| event | data | 说明 | phase |
|---|---|---|---|
| `auth` | `{ token }` | 显式鉴权(未用 header/query 时) | 0 |
| `subscribe` | `{ instanceId?, types? }` | 订阅事件;`instanceId` 缺省订阅全部实例;`types` 为事件名数组过滤;**成功响应 `data` 携带快照与日志回放(§4.2)** | 0 |
| `unsubscribe` | `{ instanceId?, types? }` | 取消订阅(参数语义同 subscribe,全缺省 = 取消全部) | 0 |
| `ping` | — | 心跳 | 0 |

### 4.2 subscribe 成功响应(回放)

对齐 MCSManager"新连接先回放历史再进实时流",订阅成功后响应:

```json
{
  "type": "response", "id": "...", "status": "ok",
  "data": {
    "snapshot": [ { "instanceId": "...", "summary": { ...InstanceSummary } } ],
    "replay": [ { "seq": 0, "instanceId": "...", "ts": ..., "text": "..." } ],
    "nextSeq": 123
  }
}
```

- `snapshot`:订阅范围内全部实例当前状态(UI 据此初始渲染)
- `replay`:每实例最近日志环形缓冲(上限 5000 行,按订阅实例合并、按 seq 升序)
- `nextSeq`:下一实时行的全局序号
- 回放期间 UI 侧应屏蔽终端合成转义回复(MCSManager `historyReplayGate` 思路)

### 4.3 服务端推送事件表

| event | 方向 | data | 说明 | phase |
|---|---|---|---|---|
| `instance/state` | 推送 | `{ status, exitCode?, pid? }` | 实例状态变化(五态) | 0 |
| `instance/opened` | 推送 | `{ instanceId, instanceName, pid }` | 实例进入运行 | 0 |
| `instance/stopped` | 推送 | `{ instanceId, instanceName, exitCode }` | 实例退出 | 0 |
| `instance/failure` | 推送 | `{ instanceId, instanceName, exitCode }` | 启动失败(兜底 kill 后) | 0 |
| `instance/stdout` | 推送 | `{ seq, text }` | 日志行(去 ANSI,命令回显 `> cmd` 同通道) | 0 |
| `instance/process-config` | 推送 | `{ file, config }` | 配置文件被外部修改(可选监控) | 1 |
| `player/join` | 推送 | `{ name }` | 玩家加入(附加层解析) | 1 |
| `player/leave` | 推送 | `{ name }` | 玩家离开 | 1 |
| `player/list` | 推送 | `{ players: [name] }` | list 轮询结果刷新 | 1 |
| `crash/report` | 推送 | `{ kind, exitCode, errorReason?, errorDetail?, errorSuggest?, logLines, logFilePath? }` | 崩溃报告(服务端/隧道) | 1 |
| `monitor/stats` | 推送 | `{ ...MonitorSnapshot }` | 系统监控周期推送(订阅 `monitor/stats` 类型,间隔 daemon 配置) | 1 |
| `download/progress` | 推送 | `{ jobId, name, type, receivedBytes, totalBytes, speedBytesPerSec, status, error? }` | 下载/导出/备份异步任务进度 | 1 |
| `backup/progress` | 推送 | `{ jobId, targetId?, status, phase, receivedBytes?, totalBytes?, error? }` | 备份执行进度 | 2 |
| `notification` | 推送 | `{ level, message }` | 通用提示(本地化 key,UI 侧翻译) | 0 |
| `ftp/status`、`ssh/status` | 推送 | 对应状态对象 | 服务开关变化 | 2 |

订阅过滤:客户端 `types` 只填 `monitor/stats` 时,仅该事件推送;未过滤时全部推送(默认)。

## 5. /api/v1/ws/terminal

### 5.1 会话模型

- 每个连接同一时刻只打开**一个**实例终端会话(`open` 新实例时自动替换并关闭旧会话)
- 一个实例可被多个连接同时打开(watcher 集合,对齐 MCSManager `instance.watchers`)
- **尺寸裁决**:服务端维护每连接 watcher 尺寸,resize 时取全部 watcher 的**最小**行列(多端查看不打架)
- 未 `open` 的实例无 PTY 进程;`open` 时才启动 PTY 并拉起游戏进程
- 连接断开:watcher 注销;若该实例无其他 watcher,PTY 进程**继续运行**(守护进程模型,服务端不受 UI 生命周期影响)

### 5.2 客户端请求

| event | data | 说明 | phase |
|---|---|---|---|
| `auth` | `{ token }` | 显式鉴权 | 0 |
| `open` | `{ instanceId, cols?, rows?, replay? }` | 打开终端会话;`replay: true`(默认)响应含历史回放;首次 open 即启动实例 | 0 |
| `detail` | `{}` | 拉取会话详情(状态/pid/watcher 数) | 0 |
| `write` | `{ input: string }` | UTF-8 文本按键(文本帧);原始字节用二进制帧 | 0 |
| `input` | `{ command: string }` | 结构化命令(命令框);与 `write` 语义分离,可被 RCON 等替换 | 0 |
| `resize` | `{ cols, rows }` | 本 watcher 终端尺寸变化(上限 900) | 0 |
| `close` | `{}` | 关闭本会话(不停止实例) | 0 |

### 5.3 服务端帧/事件

| 类型 | event | data/负载 | 说明 |
|---|---|---|---|
| 二进制帧 | — | 原始 PTY 字节 | 游戏进程输出(已按 `outputEncoding` 转码) |
| 文本事件 | `opened` | `{ instanceId, pid, status, sessionId }` | open 成功 |
| 文本事件 | `replay` | `{ lines: [{seq,text}], nextSeq }` | 历史回放(open 时 `replay:true`) |
| 文本事件 | `data` | `{ text }` | 合并后的输出文本块(50ms 批量,CircularBuffer 限流) |
| 文本事件 | `state` | `{ status, exitCode? }` | 实例状态变化(透传) |
| 文本事件 | `watchers` | `{ count }` | watcher 数变化(多端共享提示) |
| 文本事件 | `error` | `{ code, message }` | 会话错误(如实例 busy 无法 open) |

### 5.4 时序示例

```
客户端                      服务端(/ws/terminal)
  │  open {instanceId, cols:164, rows:40, replay:true}  │
  ├─────────────────────────────────────────────────────►│ 启动实例(PTY 进程)
  │  response ok {opened: {pid, status: starting}}      │
  │◄─────────────────────────────────────────────────────┤
  │  event replay {lines:[...]}                         │ 历史日志回放
  │◄─────────────────────────────────────────────────────┤
  │  event state {status: running}                      │
  │◄─────────────────────────────────────────────────────┤
  │  [二进制帧: PTY 原始字节]  (实时输出)               │
  │◄─────────────────────────────────────────────────────┤
  │  write {input:"say hi"}  (终端按键)                 │
  ├─────────────────────────────────────────────────────►│
  │  input {command:"list"}   (命令框)                  │
  ├─────────────────────────────────────────────────────►│ execPreset(command)
  │  event data {text:"There are 2 players online..."}  │
  │◄─────────────────────────────────────────────────────┤
  │  resize {cols:80, rows:24}  (多 watcher 取最小)     │
  ├─────────────────────────────────────────────────────►│ [0x04][len][JSON] → FIFO
```

## 6. 与 MCSManager 的对应关系(实现参考)

| MCSManager | EdgeCube v2 | 差异 |
|---|---|---|
| socket.io + `IPacket{uuid,status,event,data}` | 原生 WS + `{type,id,event,data}` | 去掉 socket.io 依赖,协议等价 |
| `stream/auth {password}`(passport) | `auth {token}` | passport 一次性凭证 → 长期 token |
| `stream/detail` | `terminal/detail` | 同 |
| `stream/write {input}` | `terminal/write`(文本)+ 二进制帧 | 保留原始字节语义 |
| `stream/input {command}` | `terminal/input` | 同(命令框与按键分离) |
| `stream/resize {w,h}` | `terminal/resize` | 同,多 watcher 取最小 |
| `instance/stdout` 广播 | `instance/stdout`(带 seq) | 增加 seq 供断线续拉 |
| `getInstanceOutputLog` 回放 | open 时 `replay` + `/log?since=` | 回放 gate 思路保留 |
| CircularBuffer 50ms 合并 | `terminal/data` 合并块 | 同 |

## 7. 错误码(WS 侧)

| code | 场景 |
|---|---|
| `not_authenticated` | 未鉴权/凭证无效 |
| `auth_timeout` | 6 秒未完成鉴权 |
| `instance_not_found` | instanceId 不存在 |
| `instance_busy` | 实例忙碌(如启动中重复 start) |
| `session_closed` | 会话已关闭(实例被删除等) |
| `unsupported_event` | 未知 event |
| `rate_limited` | 超出推送/请求频率上限 |

REST 侧错误码见 `openapi.yaml` `ErrorResponse`。