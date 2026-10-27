# EdgeCube-Daemon

EdgeCube 的后端守护进程。一句话概括：一个 HTTP + WebSocket 服务，功能全部以
「可插拔模块」的形式挂上去。

框架本身不含业务逻辑；已落地的业务模块见下面几节
（[`instance`](#实例管理模块instance) 管磁盘上的实例、
[`frp`](#映射隧道模块frp) 管映射隧道的登录与配置，以及**隧道的运行**（一条隧道一个进程）、
[`mcserver`](#服务端目录模块mcserver) 取各服务端源的版本与下载地址、
[`mods`](#模组与插件模块mods) 管模组与插件（搜索 / 安装 / 更新检查 / 启停）、
[`download`](#下载队列模块download) 管全局下载队列、
[`runtime`](#运行环境模块runtime) 管运行环境（Zulu JDK / frp）的下载与删除、
[`monitor`](#系统监控模块monitor) 读设备内存与 CPU、
[`task`](#任务系统模块task) 把多步操作编成工作流任务）。

- 单个端口同时提供 HTTP 与 WebSocket；一条 WS 长连接上既做类 HTTP 的一问一答，
  也做服务端主动推送。
- 配置四层合并（默认值 → 配置文件 → 环境变量 → 命令行），带注释的模板可一键生成。
- 加功能 = 写一个模块 + 在清单里加一行；卸功能 = 删掉那一行。

---

## 快速开始

```bash
cd daemon
cargo build --release

# 不需要先 --init-config：第一次启动时哪儿都没找到配置的话，
# 会自动释放一份带注释的默认配置到 $XDG_CONFIG_HOME/edgecube/daemon.toml 并加载它。

# 只校验配置与模块，不监听端口
./target/release/edgecube-daemon --check

# 启动
./target/release/edgecube-daemon

# （可选）把默认配置写到自定义路径，或者在没有启动服务的前提下生成一份：
./target/release/edgecube-daemon --init-config -c /path/to/daemon.toml
```

验证：

```bash
curl http://127.0.0.1:8787/healthz
curl http://127.0.0.1:8787/api/info          # 配了 token 时需要 ?token=...
curl http://127.0.0.1:8787/api/methods       # 当前注册了哪些 WS 方法
curl http://127.0.0.1:8787/api/monitor       # 设备内存与 CPU 使用率
```

命令行参数：

| 参数 | 说明 |
| --- | --- |
| `-c, --config <PATH>` | 指定配置文件（**不存在就报错**，不会替你生成） |
| `--init-config` | 把带注释的默认配置写到 `-c` 指定路径后退出（已存在则不覆盖）。首次运行反正会自动释放，它的价值在「写到自定义路径」 |
| `--print-config` | 打印**合并后**的最终配置后退出 |
| `--check` | 校验配置与模块注册情况后退出 |
| `--host` / `--port` / `--token` | 覆盖监听地址 / 端口 / 令牌 |
| `--log-level` / `--log-format` / `--no-color` | 覆盖日志设置 |

环境变量：`EDGECUBE_CONFIG`、`EDGECUBE_HOST`、`EDGECUBE_PORT`、`EDGECUBE_TOKEN`、
`EDGECUBE_LOG_LEVEL`、`EDGECUBE_LOG_FORMAT`、`EDGECUBE_NO_COLOR`。

日志只写 stdout：落盘/轮转/收集交给 systemd、journald 或容器运行时，
框架不自己实现一套。格式（pretty / json）在启动时定下来，不支持运行期切换。

---

## 配置文件

优先级：**内置默认值 < 配置文件 < 环境变量 < 命令行**。

查找顺序：`-c` 指定 → `./edgecube.toml` → `$XDG_CONFIG_HOME/edgecube/daemon.toml`。

**哪儿都没有时**：自动把带注释的默认配置**释放**到第三处再加载它，所以第一次
启动就是可用状态、改配置直接编辑那个文件即可，`--init-config` 不是必经步骤。
三条边界，都是刻意的：

- `-c` **显式指定**的路径不存在 → 直接报错退出。自动释放只发生在「哪儿都没找到」
  时 —— 帮用户在他给错的路径上生成一份配置，只会把「路径写错了」这件事盖住。
- 释放走「同目录临时文件 + rename」：中途被杀不会留下半截 TOML
  （半截文件下次启动解析失败，用户得自己删，比这次没写出来更麻烦）。
- 释放失败（只读文件系统、HOME/XDG 都没设）→ **不**阻止启动，退回内置默认值并
  打一条 warning 说清楚原因。配置目录定位不到（`default_config_path` 退化成相对路径）
  时也走这条路，而不是随手往进程 CWD 里写。

完整示例见 [`config.example.toml`](./config.example.toml)。几个要点：

- `server.token` 留空 = 不鉴权（只建议回环场景）。
- 模块私有配置一律写在 `[modules.config.<模块 id>]`，框架**不解析**，原样交给模块自己
  `deserialize`。字段名写错会在启动时报错，而不是被静默忽略。
- `modules.enabled` 支持 `"*"` 或 `["core", "ticker"]`；`modules.disabled` 在它基础上排除。
  标了 `always_on` 的模块（`core`）排除不掉——否则客户端连上来会完全瞎掉。

---

## WebSocket 协议

入口 `ws://host:port/ws`。令牌三种带法：`Authorization: Bearer <t>`、
`X-EdgeCube-Token: <t>`、`/ws?token=<t>`（浏览器 WebSocket 不能自定义头，只能用查询串）。

### 客户端 → 服务端

```json
{"type": "call",        "id": 1, "method": "core.ping", "params": {}}
{"type": "subscribe",   "id": 2, "topic": "ticker.*"}
{"type": "unsubscribe", "id": 3, "topic": "ticker.*"}
{"type": "ping",        "id": 4}
{"type": "hello",       "client": "app", "protocol": 1}
```

### 服务端 → 客户端

```json
{"type": "hello",  "protocol": 1, "methods": [...], "topics": [...]}
{"type": "result", "id": 1, "ok": true,  "result": {...}, "elapsed_ms": 0}
{"type": "result", "id": 1, "ok": false, "error": {"code": "method_not_found", "message": "..."}}
{"type": "event",  "topic": "ticker.tick", "seq": 12, "ts": 1789527819755, "data": {...}}
{"type": "pong",   "id": 4, "ts": 1789527819755}
{"type": "error",  "error": {...}}
{"type": "bye",    "code": 1001, "reason": "server shutting down"}
```

约定：

- `id` 由客户端给、服务端原样回填。**没有 `id` 的消息都是服务端主动推的。**
- 每次调用只回一个 `result`。不同调用并发执行，**回来顺序不保证**，按 `id` 配对。
- 单连接并发上限 `server.max_inflight_calls`，超出立刻回 `busy`（不排队）。
- 事件带全局自增 `seq`，跳号说明期间丢过事件（连接处理不过来时会主动丢，不会撑爆内存）。
- 订阅支持精确主题、`prefix.*` 和 `*`；`subscribe` 幂等，个数上限 `server.max_subscriptions`。
- 错误码是稳定字符串，前端按 `code` 分支即可，不要匹配 `message`：

  | code | HTTP 对应 | 含义 |
  | --- | --- | --- |
  | `bad_request` | 400 | 信封本身不合法 |
  | `invalid_params` | 400 | 方法存在，参数不对 |
  | `unauthorized` | 401 | 令牌缺失/错误 |
  | `forbidden` | 403 | 鉴权过了但无权（如 `Scope::Local` 方法被远程调用） |
  | `method_not_found` | 404 | 没有这个方法（会自动给出候选） |
  | `busy` | 429 | 并发/订阅数超限 |
  | `timeout` | 504 | 处理方法超时 |
  | `unavailable` | 503 | 服务正在关闭 |
  | `internal` | 500 | 服务端内部错误 |

### HTTP 接口

| 路径 | 鉴权 | 说明 |
| --- | --- | --- |
| `GET /` | 否 | 服务概览 |
| `GET /healthz` | 否 | 存活探针，返回 `ok` |
| `GET /api/info` | 是 | 服务与运行环境信息 |
| `GET /api/modules` | 是 | 已装载 / 被禁用的模块 |
| `GET /api/methods` | 是 | WS 方法清单 |
| `GET /api/topics` | 是 | 事件主题清单 |
| `GET /api/protocol` | 是 | 协议速查（JSON） |
| `GET /api/monitor` | 是 | 系统监控快照（= `monitor.snapshot`） |
| `GET /api/monitor/status` | 是 | 监控采样器状态（= `monitor.status`） |
| `POST /api/instances/{id}/start` | 是 | 启动实例 |
| `POST /api/instances/{id}/stop` | 是 | 优雅停止 |
| `POST /api/instances/{id}/restart` | 是 | 重启 |
| `POST /api/instances/{id}/kill` | 是 | 强制停止 |
| `GET /api/instances/{id}/files/download` | 是 | 下载文件；**目录**现场打成 zip 流出 |
| `POST /api/instances/{id}/files/upload` | 是 | 上传文件：请求体就是文件内容 |
| `GET /pty/{id}` | 是 | WebSocket 升级：该实例的**控制台流** |
| `GET /shell` | 是 | WebSocket 升级：**主机终端**（daemon 所在机器的 shell） |
| `GET {ws_path}` | 是 | WebSocket 升级 |

模块挂的路由同样要过鉴权。

### 多客户端隔离：谁的数据发给谁

一台 daemon 可以同时服务多个前端（App、网页、命令行……），投递语义分两类：

| 消息 | 发给谁 | 靠什么保证 |
| --- | --- | --- |
| `hello` / `result` / `pong` / `error` / `bye` | **只有发起的那条连接** | 每条连接一个独立出站队列（`mpsc`）+ 唯一 writer；应答只 `push` 到本会话的 `ConnHandle` |
| `event` | 所有**订阅了该主题**的连接 | 每条会话各自订阅事件总线，按自己的订阅模式过滤后投递 |

- **`id` 只是会话内的配对键**：两条连接同时用 `id = 7` 互不影响，
  服务端各自配对（`tests/framework.rs` 的 `same_id_on_two_connections_do_not_collide`）。
- **没有任何路径会把应答扇出**：`ConnRegistry::broadcast()` 是唯一的"发所有人"入口，
  框架内部只在关机时用它（`close_all` 发告别帧）。写模块时别拿它来回应答。
- 事件能看到什么完全由订阅决定：没订阅的连接一帧都收不到
  （`events_only_reach_subscribers`）。

#### 不保证的部分（当前是共享令牌模型）

- 鉴权只有一把全局 `server.token`，**没有 per-client 身份**。所以
  `core.info` 的 `connections`、`core.connections`、`core.conn_opened/conn_closed`
  对所有持令牌者可见 —— 这不是串数据，但属于信息暴露。
- **业务数据层面的隔离**（例如「A 只能看到自己那台服务器的控制台」）取决于模块怎么设计。
  框架保证的是「投递不串门」，不是「权限」。
- 真要做多用户，得先有身份：把身份放进 `CallCtx`，并在注册表分发处加
  per-method 授权钩子（`MethodSpec.scope` 已经预留了同类位置）。

---

## 核心模块（`core`）

框架自省，`always_on`。连通性 / 清单 / 配置这些方法都在这里，其中与「关于」页
相关的是 `core.host`：

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `core.host` | — | 守护进程所在机器的软硬件信息 |

返回形状（读不到的字段是 `null`，数字为 0 表示平台不支持）：

```json
{
  "hostname": "mc-host",
  "os_name": "Ubuntu",
  "os_version": "24.04",
  "kernel_version": "6.8.0-31-generic",
  "arch": "x86_64",
  "cpu_brand": "AMD Ryzen 7 5800X 8-Core Processor",
  "cpu_cores": 16,
  "cpu_physical_cores": 8,
  "memory_total_mb": 32012,
  "uptime_secs": 90061
}
```

- 与 `core.info` 的分工：`core.info` 是**服务视角**（版本、连接数、监听地址），
  `core.host` 是**机器视角**（这台机器是什么）。
- 采集是几个系统调用，不做缓存；这些字段在运行中基本不变，客户端打开关于页时
  调一次即可。
- 旧 daemon 没有这个方法时，App 只提示升级，不影响 `core.info` 与连接本身。

---

## 系统监控模块（`monitor`）

读**这台机器**的内存与 CPU 使用率，给客户端的「系统状态」卡片用。采集交给
[`sysinfo`](https://crates.io/crates/sysinfo)：Linux / Windows / macOS 一套代码，
不用自己读 `/proc` 或写平台 FFI。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `monitor.snapshot` | — | 取一份快照（读缓存，最旧不超过 `interval_ms`） |
| `monitor.status` | — | 采样器状态：是否在跑、间隔、采了多少次、有没有 CPU 读数 |

HTTP 侧同一套：`GET /api/monitor`、`GET /api/monitor/status`。

事件：`monitor.stats` —— 每 `interval_ms` 推一份与 `monitor.snapshot` **完全相同**的
快照，客户端订阅它就能把「系统状态」卡片做成活的。`publish = false` 时只采不推。

### 快照字段

```json
{
  "sampled_at_ms": 1789527819755,
  "interval_ms": 2000,
  "supported": true,
  "total_mem_mb": 32012,
  "used_mem_mb": 18635,
  "available_mem_mb": 13377,
  "used_mem_percent": 58.2,
  "cpu_usage": 13.4,
  "cpu_cores": 16,
  "server_mem_mb": null
}
```

- 字段语义一一对应，内存单位统一 MB。
- **`cpu_usage` 可能是 `null`**：sysinfo 的使用率是两次采样的差值，进程刚起来时
  还没有可信的窗口 —— 线上格式用 `null` 表示「还没有可信数值」，比哨兵值直白。
  采样器在 `Module::start` 就起，所以守护进程跑够一个 `interval_ms` 之后就不会再是 null。
- **`server_mem_mb` 恒为 `null`**：读它要服务端进程的 RSS。进程管理已经接进来了，
  但「哪个 pid 是这台实例的」在 `instance` 模块里 —— 两个模块之间没有互相调用的
  通道（框架就是这么设计的），所以这里仍然不编造数字。要用的话得让 `instance`
  把 pid 报给总线，或者给监控模块加一个可注入的 pid 来源。
- `supported` 是 sysinfo 的 `IS_SUPPORTED_SYSTEM`；为 false 时后面的数字没有意义。

### 采样器为什么常驻

`ticker` 模块有 `autostart` 开关，`monitor` **没有**，`Module::start` 里直接起：

- CPU 使用率必须连续两次采样才有意义（第一次的窗口是「进程启动至今」），
  按需采样会让每次冷启动后的第一份数据必然是 `null`；
- 一次采样的成本就是几个系统调用，用 `interval_ms` 调成本就够了。

`interval_ms` 会被 clamp 到 `[250, 60000]`：下限取 250 是因为 sysinfo 自己的
`MINIMUM_CPU_UPDATE_INTERVAL` 是 200ms，比它还密只会读到上一次的旧值。

---

## 实例管理模块（`instance`）

第一个真正的业务模块：管**实例的一切** —— 磁盘上的元数据 / 目录 / 体积，
以及它们的**进程**（启停、PTY 控制台、退出码）。

> 「只管磁盘不管进程」是它早期的边界，那时进程管理还没落地；现在两者都在这个
> 模块里，因为 `instance.status` 的 `phase` / 退出码本来就是实例的属性 ——
> 拆成两个模块只会让「这台实例到底在不在跑」有两个来源。
> 磁盘部分与进程部分在代码里是分开的（`store.rs` / `process.rs`），互不纠缠。

### 存储布局（索引 / 元数据 / 工作目录三分离）

```text
<data_dir>/
├── config/
│   ├── instances.json          # 索引：{ selected, instances: [{id,name,path?}] }
│   └── instances/<id>.json     # 单个实例的完整元数据
└── instances/<id>/             # 实例工作目录（服务端文件、世界存档……）
```

- **列表只读索引**（`{id,name}` 摘要），不必把每个实例的启动配置都读进来 ——
  实例多起来这是数量级差别。
- **元数据里只有一个启动相关的字段**：`startupCommand`。怎么把服务端拉起来
  （解释器、内存、jar、JVM 参数、容器命令……）全部由用户写在**这一条命令**里，
  daemon 不替用户推导 —— 少一层推导就少一处「起不来但日志里看不出为什么」。
  实例文件里的 `runtime` / `maxMemory` / `runtimeEnvId` /
  `serverFile` / `customJvmArgs` 会被忽略（字段已经不存在了）；
  唯一保留的迁移口是 `prootStartupCommand`，它语义上就是启动命令，
  通过 serde alias 继续读得进来、写出去一律是 `startupCommand`。
- **命名分两套，别混**：**落盘**用 camelCase（`startupCommand`、`autoRestartOnExit`），
  **线上**（WS / HTTP）统一 snake_case（`startup_command`、`auto_restart_on_exit`）——
  前端只需要记一套命名。`instance.create` 是直接把参数反序列化成元数据结构的，
  所以多词字段两种拼法都收（`startupCommand` 与 `startup_command` 等价），
  免得前端按线上命名发过去却被静默丢掉。
  实现上就是 `InstanceConfig::to_wire_value()`（线上）与 `serde_json::to_string`
  （落盘）两条路，测试里两边都钉住了。
- 写文件一律「先写**唯一命名**的临时文件再 rename」：中途崩溃不会留下半个 JSON；
  临时名带 pid + 序号，两个写入者并发也不会互相把对方的临时文件 rename 走。
- 「读索引 → 改 → 写索引」在模块内用互斥锁串行化，避免并发新建/删除互相覆盖。
- **`instance.update` 的补丁语义**：字段**缺席 = 不动**，显式传 `null`（或空白串）= 清空。
  可改字段就是 `UPDATABLE_FIELDS` 那份清单；**客户端把 `id` 一起平铺在 `params` 里是允许的**
  （它是寻址参数，会被忽略，不算「不认识的字段」）—— app 的 `InstanceApi.update` 正是这么发的。
  加字段记得同时加进 `UPDATABLE_FIELDS`，否则前端会收到「不认识的字段」而整份补丁被拒。
  另外 `line_ending` 值本身就是空白字符，**不能走会 `trim()` 的通用字符串读取**。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `instance.list` | `with_status?` | 列表；`with_status=true` 时每个实例附带状态 |
| `instance.get` | `id` | 完整元数据 + 目录 + lint |
| `instance.create` | `name`，可选 `startupCommand` / `path` / `compatMode` / `autoRestartOnExit` / `lineEnding` | 新建（id 由服务端生成，16 位 hex） |
| `instance.update` | `id` + 要改的字段 | 改元数据；缺席 = 不动、`null` = 清空（见上文「补丁语义」） |
| `instance.delete` | `id`，`keep_files?` | 删除；`keep_files=true` 只摘出列表，目录留在磁盘上 |
| `instance.status` | `id?` | 给 id 看一个，不给看全部 |
| `instance.select` | `id?` | 设置「当前选中」（索引里的 `selected`） |
| `instance.scan` | — | 重新扫描磁盘：清理缺失 + 接管外部新建的目录 |
| `instance.start` | `id` | 按 `startupCommand` 拉起进程（走 PTY） |
| `instance.stop` | `id` | 优雅停止：把 `stopCommand` 写进服务端控制台 |
| `instance.restart` | `id` | 重启：**等旧进程真的退下去**再起，不会撞端口 |
| `instance.kill` | `id` | 强制停止：杀进程组（可能丢数据） |
| `instance.config.get` | `id` | 读服务端配置：**认哪种文件由这里决定**（见下） |
| `instance.eula.get` | `id` | 读 EULA 状态（`eula.txt` 里有没有 `eula=true`） |
| `instance.eula.accept` | `id` | 同意 EULA（写入 `eula.txt`，没有就建） |
| `instance.config.save` | `id`、`kind`、`content` | 写回；写哪个文件由 `kind` 算，**不接受前端给路径** |
| `instance.config.icon.get` | `id` | 读服务端图标（`server-icon.png`，base64；没有不是错误） |
| `instance.config.icon.save` | `id`、`data` | 写服务端图标（base64 的 PNG，**必须 64×64**） |

HTTP 侧同一套能力：`GET/POST /api/instances`、`GET/DELETE /api/instances/{id}`
（`?keep_files=true`）、`POST /api/instances/{id}/select`，
以及 `POST /api/instances/{id}/start|stop|restart|kill`。

#### 服务端配置（`instance.config.*`）

V2 的「服务器配置」由 daemon 判断（依据是磁盘上的文件，而磁盘归 daemon 管），
前端因此只需要**一个通用页**：进来问一次 `instance.config.get`，按回的 `kind` 选字段表。

检测优先级：

```text
pnx.yml  >  server-settings.yml  >  server.properties
```

三者都没有时 `kind = null`（**不是错误**），前端给「先启动一次服务端生成配置文件」。

`server.properties` 是 Java 与 PocketMine **共用**的，靠内容区分（PMMP 必写的
`pocketmine.yml`，或 `pvp` / `enable-query` / `white-list` 这几个键写的是
`on`/`off`）→ `kind` 是 `java` 还是 `pmmp`。前端拿这两个不同的 kind 选两张不同的
字段表（布尔写法与 gamemode 的取值集合都不一样）。

**字段表不在 daemon 里**（每个字段叫什么、用什么控件、下拉有哪些选项）——
那是展示的事，留在前端 `app/lib/instance/config/sections.dart`。daemon 只回
`{kind, file, exists, content}`。保存时也只回 `{id, kind, content}`：文件名从一个
封闭枚举算出来（三个固定字符串之一），前端给不了路径，所以没有「按 id 写任意文件」
这种洞。写入是原子的（先写 `.tmp` 再 `rename`），且**只写已经存在的文件** ——
凭空造一份半成品配置只会让服务端起不来。

#### 服务端图标（`instance.config.icon.*`）

`server-icon.png` 是**另一个文件**，只有 Java 系服务端认它（pnx / allay 都是基岩系，
没有这东西），所以单独一对方法，前端也只在 `kind` 是 `java` / `pmmp` 时画那张卡。

走 WS 传 base64 而不是复用 HTTP 上传：图标只有几 KB，而**校验必须在 daemon 侧** ——
Minecraft 对尺寸不符的图标是**静默忽略**（服务器照跑、图标不换），那种「改了没反应」
最难查。所以写入前读 PNG 头两段（签名 + IHDR 的宽高）确认是 **64×64**，不合格直接拒
（`instance_icon_invalid`），且**不碰原来那份文件**。`data` 不是合法 base64 时是
`invalid_params`（调用方发错了），与「内容不对」分开报。

读 PNG 头是安全的（签名 + IHDR 的位置是 PNG 规范的硬约束），不必为此引图片库。

模块自己的错误码（前端按码分支）：`instance_not_found`、`instance_name_taken`、
`instance_dir_missing`、`instance_not_configured`（没配启动命令）、
`instance_already_running`、`instance_not_running`、`instance_start_failed`、
`instance_stop_command_missing`、`instance_stop_timeout`、`instance_kill_failed`、
`instance_config_unreadable`、`instance_config_missing`、`instance_config_save_failed`、
`instance_icon_unreadable`、`instance_icon_invalid`。

事件：`instance.created` / `instance.deleted` / `instance.updated`（另一个前端连着的时候，
列表能靠它们自己更新）、`instance.phase`（`{id, phase, exit_code, pid}`）、
`instance.players`（见下文「玩家管理」）。

### 文件管理（`instance.files.*`）

实例工作目录的远程文件管理器：路径一律是**相对实例目录**
的 `/` 分隔串（`""` = 根），列表目录在前、名称忽略大小写排序，不过滤隐藏文件。

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `instance.files.list` | `id`，`path?` | 列目录；目录不存在 → 空列表（**不报错**） |
| `instance.files.search` | `id`，`query`，`path?`，`recursive?` | 按名称子串搜索（忽略大小写） |
| `instance.files.mkdir` / `.create` | `id`，`path?`（父目录），`name` | 新建文件夹 / 空文件；重名报 `file_exists` |
| `instance.files.rename` | `id`，`path`，`name` | 同目录内改名 |
| `instance.files.delete` | `id`，`path` | 删除（目录递归）；**幂等**，第二次回 `deleted: false` |
| `instance.files.copy` | `id`，`path`，`dest` | 复制进 `dest` 目录；重名自动加 ` (1)` |
| `instance.files.move` | `id`，`path`，`dest` | 移动进 `dest` 目录；重名**硬报错** |
| `instance.files.read` | `id`，`path`，`raw?` | 读文本；非 UTF-8 报 `file_not_utf8`，`raw=true` 按 latin1 兜底 |
| `instance.files.write` | `id`，`path`，`content` | 覆盖写文本（只写已存在的普通文件） |
| `instance.files.compress` | `id`，`paths`，`dest`，`name?`，`format?` | 压成归档；`format` = `zip`（缺省）/ `tar.gz` / `tar.xz` / `tar.zst`。缺省名：单个源去扩展名、多个源 `压缩文件`，后缀按格式补 |
| `instance.files.extract` | `id`，`path`，`dest`，`name?` | 解压**任意支持的归档**到 `dest` 下的新子目录（缺省名 = 归档名去掉归档后缀）。格式按文件名认：zip、tar、tar.gz/tgz、tar.xz/txz、tar.bz2/tbz2、tar.zst/tzst、tar.lz4、7z、rar，以及单流 gz/xz/bz2/zst/lz4 |

错误码：`file_not_found` / `file_exists` / `file_io` / `file_not_utf8` /
`file_too_large` / `file_archive` / `file_invalid_destination`。

传输走上面那张表里的两条 HTTP 路由，不走 WS：几十上百 MB 的 jar 和世界存档
塞进 JSON 一问一答不现实。

- **下载**：`?path=<相对路径>`。文件原样发；目录**现场打成 zip**（落在系统临时目录，
  客户端读完就删），所以前端「导出文件夹」只要一次请求。文件名同时给
  `filename=` 和 RFC 5987 的 `filename*=`，中文名也能落对。
- **上传**：`?path=<目标目录>&name=<文件名>&overwrite?`。请求体就是文件内容，
  边收边写同目录下的临时文件，收完 `rename` 落定；中途失败或超上限
  （`upload_max_bytes`）都不会留下半个文件。`overwrite` 缺省为 `false`，
  此时重名会自动加 ` (1)`。
- 四条 `file_*` 上限都在 `[modules.config.instance]`：`text_max_bytes` /
  `upload_max_bytes` / `search_max_results` / `archive_max_entries`。

**安全约束**：`resolve()` 是唯一的路径入口 —— 拒绝绝对路径、拒绝任何 `..` 分量
（`a/../b` 也拒），拼出来的一定在实例目录内；符号链接**列出来但不跟随**
（删除 / 改名 / 移动作用于链接本身，断链也算「已存在」，免得重名检测漏判）；
归档里的条目逐段过 `archive::entry_target`（`..` 弹到根外就整包拒绝，
Windows 盘符也挡），zip 那条还额外走 `enclosed_name()`（zip-slip）。
tar 里的符号链接 / 硬链接 / 设备文件条目**跳过不落盘** —— 先造一条指向
`/etc` 的链接、再往里写文件，等于绕开路径校验。
压缩与解压都有条目数上限，挡压缩炸弹。

归档实现集中在 `instance/archive/`：`zip.rs` / `tar.rs` / `sevenz.rs` /
`rar.rs` / `single.rs`，`mod.rs` 只做格式探测与分发。压缩输出只有四种
（zip / tar.gz / tar.xz / tar.zst）；7z 与 rar **只能解压** ——
`sevenz-rust2` 不带写入器，`unrar` 本身只有解压能力。

### 玩家管理（`instance.players.*` / `instance.console.write`）

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `instance.players.online` | `id` | 在线玩家快照：`{id, players[], count}` |
| `instance.players.whitelist` | `id` | 白名单：`{id, entries[], names[]}` |
| `instance.players.ops` | `id` | OP 名单，同上 |
| `instance.players.bans` | `id` | 封禁名单，同上 |
| `instance.players.ip_bans` | `id` | IP 封禁名单，同上 |
| `instance.console.write` | `id`，`data` | 往控制台写一段输入（同 `/pty/{id}` 的击键通道） |

**在线玩家由 daemon 解析，前端不碰日志。** 服务端没有「现在谁在线」这种接口，
只能从输出里认人；进程归 daemon 管，只有它拿得到从头到尾、一条不漏的输出流，
所以解析就在 PTY 读线程里**边读边做**（`players.rs` 的 `OnlinePlayers`）——
前端读到的历史是有上限的一段，拿它解析必然在断线/错过一帧时漏事件。

- 名单一变就推 `instance.players` 事件：`{id, players[], count, ts}`。
  **事件里就是完整快照**（不是增量），前端收到直接整份替换即可。
- 解析规则：Bukkit 系
  `Steve[/10.0.0.5:1234] logged in` / `left the game`、中文
  `Steve 加入了游戏` / `Steve 退出了游戏` / `Steve[/ip] 登入游戏` / `登出游戏`，
  以及 `list` 响应的 `… players online: a, b` 与 `… 个玩家在线：a, b`（整份替换）。
  判定顺序是**加入 → 退出 → `list`**，一条输出只认一种。
  几处已知的怪癖原样保留：原版服务端的 `Steve joined the game` **认不出来**
  （只认上面那几支），`登入游戏` 那一支因为 `[` 没转义会抓到 IP 的尾数。
- 在线集合挂在**会话**上（不是单次运行）：进程退出时清空并推一次事件 ——
  进程都没了，名单里不该还留着人。
- 命令是**写死行尾的字节**：前端把「命令 + `lineEnding`」拼好发过来，
  daemon 原样写进 PTY。`instance.console.write` 就是给这种场景用的 ——
  不必为了发一条命令去连一整条 `/pty/{id}`（那会把整个控制台输出也拉回来）。

### `instance.status` 的语义

它报的是**磁盘视角**：目录在不在、多大、多少文件、元数据自不自洽。

```json
{
  "phase": "stopped",          // 生命周期阶段，见下
  "running": false,
  "process_managed": true,     // ← 进程管理已接入，phase 是真的
  "pid": 12345,                // 在运行时才有
  "exit_code": null,           // 上一次退出的退出码
  "started_at_ms": 1789527819755,
  "dir": "/srv/edgecube/instances/1a2b3c4d5e6f7788",
  "dir_exists": true,
  "size_bytes": 1536, "size_human": "1.5 KiB",
  "file_count": 2, "dir_count": 1, "size_truncated": false,
  "created_at_ms": 1789000000000, "updated_at_ms": 1789000000000,
  "warnings": ["元数据里的入口文件 `server.jar` 不在实例目录中"]
}
```

- `phase` 有五种取值（`stopped` / `preparing` / `starting` /
  `running` / `stopping`），外加一个 **`crashed`** —— 进程异常退出必须和
  「用户主动停止」区分开，否则前端只能把崩溃显示成正常停止。
  判定规则见 `process.rs`：拉起 → `starting`（`compatMode` 直接 `running`）；
  输出里出现 `Done (` → `running`；收到停止命令 → `stopping`；
  退出时「我们让它停的 / 退出码 0」→ `stopped`，否则 `crashed`。
- **`warnings` 是这里最实用的部分**：目录丢了、**没配启动命令**、换行符不合法……
  都会在这里说出来，前端直接挂到实例卡片上即可。

### EULA 同意机制（`instance.eula.*`）

启动 Minecraft 服务端前必须让用户同意 EULA —— 服务端自己会在启动时读实例目录下的
`eula.txt`，里面没有 `eula=true` 就直接退出。

`instance.eula.get` 回 `{exists, agreed, file}`，`instance.eula.accept` 把
**固定内容**写进 `eula.txt`（没有就建）。判定与写入都在 daemon：

- 文件在**服务端机器上**，前端拿不到；
- 判定口径宽松：用的是
  `eula\s*=\s*true`（忽略大小写）的正则，**没有锚定行首**，所以
  `# eula=true` 这种注释行也算「已同意」。这条宽松口径**刻意保留**：宁可多认几个，
  也别把已经同意过的用户再拦一次（`eula.rs` 的单测把这些形状都钉住了）。
- 内容是**固定的一段**（一行注释 + `eula=true` + 结尾换行），
  **前端给不了内容** —— 与 `instance.config.save` 的「文件名由封闭枚举算」同一条约束。

**没有走「文件编辑」那条路**（`instance.files.read/write`）的原因：`files.write`
只写**已存在**的文件，而新实例上服务端还没生成 `eula.txt`。

前端那一半：启动按钮先过这道关卡，
**不同意就当没点过启动**（不是弹一个错误）。**只有启动走这道关卡** ——
重启按钮是直接 `server.restart`，不走这道关卡。

### 几条安全约束（都是必须的）

- **id 是安全边界**：只允许 `[0-9A-Za-z_-]`、长度 ≤64。id 会被直接拼进文件路径，
  放行 `..` 或 `/` 就等于把 `instance.delete` 变成任意目录删除。
- **删除前重新校验目录**：实例允许把工作目录放在数据根之外（`path` 指向别处，
  例如接管一个已经存在的服务端目录），所以删除时会再查一遍 —— 必须是绝对路径、
  不含 `..`、层级 ≥3（挡住 `/`、`/etc`、`/tmp`）。元数据被人手工改坏也拦得住。
- **扫描失败绝不动索引**：数据根读不了（存储没挂载、权限不足）时整体跳过，
  而不是把索引当空的清掉。
- 目录体积统计有条目数与深度上限，触顶时 `size_truncated = true`，数值只是下界。

---

## 进程与控制台（`instance` 的进程部分）

进程管理在 `instance/process.rs` 里，方案取自 `pty-terminal-demo`：

1. **PTY 用 `portable-pty`**（不是 `std::process` + 管道）—— 服务端按「是不是终端」
   决定要不要开控制台，管道会让它退化成非交互模式；
2. **输出保留 8 KiB 环形历史** —— 控制台随时连上来都能看到之前的输出；
3. **「取历史快照」与「注册订阅者」在同一把锁里原子完成** —— 分两步做必然要么漏帧、
   要么重复。这是整个方案的关键，改的时候别拆成两步。

### 控制台协议（`GET /pty/{id}`，需令牌）

**服务端 → 客户端**

1. 文本帧 `{"type":"history_begin"}`
2. 二进制帧：历史快照（历史为空时不发）
3. 文本帧 `{"type":"history_end","state":{…RunInfo}}` —— 历史到此为止，
   `state` 是当前运行状态。**客户端读到它才开始算「实时」**。
4. 之后：二进制帧 = 原始输出；文本帧 `{"type":"exit","code":N,"phase":"…"}` =
   进程退出（连接**不关** —— 服务端可能被重新启动，控制台接着看）。

**客户端 → 服务端**

* 二进制帧 = 原样写进 PTY 的字节（击键、粘贴）；
* 文本帧 = `{"resize":{"cols":N,"rows":M}}`。

断开连接**只是退订**：PTY 与进程照旧跑，别的客户端还能连上来看（demo 的语义）。
实例不存在返回 404，没令牌升级被拒。

### 停止：`stopCommand`

| 值 | 行为 |
| --- | --- |
| 普通文本（如 `stop`） | 往服务端 stdin 写这一行，末尾补 `lineEnding` |
| caret 记号（`^C` / `^D` / `^[` / `^?`，大小写都认） | 只写那**一个**控制字节。`^C` 由终端驱动转成 SIGINT，没有控制台命令的服务端靠它优雅退出 |
| 空 | 回落到 `stop` |

判定「是不是 caret 记号」要求**整个值恰好是一个记号** —— 否则 `say ^C` 这种带
caret 的普通命令会被误当成控制字符，那种误判极难排查。

### 强制停止

`ChildKiller::kill()`（Unix 上是 SIGHUP、Windows 上是 TerminateProcess），
**另外在 Unix 上给整个进程组补一刀 SIGKILL**：PTY 的子进程被 `setsid()` 提成了
会话首进程（pgid == pid），所以 `sh -c "a && b"` 里再 fork 出来的子孙也能一起清掉。
不做这一步的话，只杀直接子进程会留下真正的服务端在后台空跑。

### 自动重启

`autoRestartOnExit` 为真、且进程**自己**正常退出（不是我们让它停的、退出码 0）时
自动重起，间隔 1s。有次数上限（10 次）—— 没有上限的话一条「跑完就退」的命令会变成
死循环，用户只能看着 CPU 烧起来；到顶会停下并在控制台留一句说明。

---

## 主机终端模块（`shell`）

给 daemon 所在机器开一个交互式 shell —— **不是**某个实例的控制台，而是系统本身的
`$SHELL`（回落到 bash → sh；Windows 上用 `COMSPEC`，默认 `cmd.exe`）。工作目录默认
`$HOME`，环境继承 daemon 进程，只额外把 `TERM` 设成 `xterm-256color`。

### 数据面

| 路径 | 说明 |
| --- | --- |
| `GET /shell` | WebSocket 升级，需令牌。协议与 `/pty/{id}` **完全一致**（`history_begin` → 二进制历史 → `history_end` + `state` → 实时二进制 → `exit`） |

协议一致是刻意的：前端只有一套终端解析（`PtyClient`），主机终端只是换了个地址。
`state` 的字段名也对齐实例的 `RunInfo`：

```json
{"phase": "running", "pid": 12345, "started_at_ms": 1700000000000, "exit_code": null}
{"phase": "stopped", "pid": null, "exit_code": 0}
```

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `shell.status` | — | 当前状态（上面那个形状） |
| `shell.restart` | — | 杀掉当前 shell 并立即重开；**同步完成后才返回**，拿到返回值时新进程已起好 |

### 几条写在明处的行为

- **单会话**：一台 daemon 只有一个 shell，多端连上来共享同一条 PTY 与历史。
  对齐 V1 的 `ShellPage`，也让「谁在敲」的语义简单 —— 没有会话 id 要管。
- **断线不杀**：连接只是退订，shell 继续跑（与实例控制台同一条规则）。
- **退出后自动重开**：shell 自己 `exit` 之后，下一次连接会重新拉起一个；
  历史保留，所以能看到上一轮的退出码。
- **第一个连接才拉起**：daemon 启动时不抢起 shell —— 没人看的时候挂一个空终端没意义。
- **`always_on`**：这个模块不受 `modules.enabled` / `disabled` 影响。入口在 App 上，
  把它卸载掉只会让那个入口连到 404。

### 安全边界

`/shell` 等于「拿到令牌 = 拿到 daemon 所在机器的 shell」。这**不增加**实际的权限面：
能调 `instance.update` 的人本来就能把 `startup_command` 改成任意命令，效果一样。
所以这里不额外做命令白名单 / 目录限制（那只会造成「看着安全、其实绕得过去」的错觉），
而是把边界放在令牌与监听地址上（默认只听回环，对外要显式配 token）。

实现上有一点值得注意：**tar 归档里那种「先造符号链接再往里写」的越权手法在这里不存在**
—— shell 是给管理员自己用的，不是给归档解压用的；反过来说，解压那条路径上的
链接条目必须跳过（见文件管理一节）。

---

## 映射隧道模块（`frp`）

内网穿透（FRP）：登录各映射平台、拿平台的隧道、把「已保存隧道」变成 frpc 能直接
读的配置。**frpc 本身作为「运行环境」从 GitHub Releases 下载**（见运行环境一节）。

**一条隧道配置 = 一个可独立运行的 FRP 实例**：`toml/<localId>.toml` 各自对应一个
frpc 进程，自己启停、互不影响。游戏实例与它是**平级的两种独立实例** —— 游戏实例
只是可以「连带启动」某一条（一个 `frp_tunnel_id` 引用），但**不**把它管起来：
用哪个 frpc、现在跑没跑，都在 FRP 这边，游戏实例那边不存第二份状态。

存储布局：

```
<data_dir>/
└── config/frp/
    ├── auth.json                 # 各平台令牌 + 账号缓存（0600）
    ├── settings.json             # FRP 侧自己的设置（跑隧道用哪个 frpc）
    ├── config/<localId>.json     # 一条已保存隧道的元数据（camelCase）
    └── toml/<localId>.toml       # 生成好的 frpc 配置 ← 一个 toml 就是一个 FRP 实例
```

### 登录为什么在 daemon

登录、轮询、令牌落盘必须常在 —— 放在前端进程里的话，页面一关授权就断，
令牌也只留在那一台设备上。所以这些全部由 daemon 承担：

- **后端发起授权**：`frp.login.start` 向平台申请授权，只把「授权页地址 + 设备码」
  交给前端；ssid / csrf / 设备码 / OpenFrp 的 curve25519 私钥都留在 daemon。
- **后端轮询**：轮询任务在 daemon 里跑（最多 60 次，间隔 5s；ChmlFrp 用服务端下发
  的 `interval`，收到 `slow_down` 再加 5s）。App 断开、切后台、退出都不影响它 ——
  用户回来用 `frp.login.status` 或订阅 `frp.login` 就能拿到最终结果。
- **后端落盘**：拿到令牌先验证账号，验过才写进
  `auth.json`。ChmlFrp 存 `{at, rt, exp}`，临近过期时 daemon 自动用
  refresh_token 换新并回写 —— 所以 ChmlFrp 不需要频繁重登。
- **网络抖动接着轮，业务错误立即停**：单次异常先吞掉继续等 —— 包括读不懂的
  响应体（OpenFrp 未授权时回 204 空体，解析在那上面会抛异常）。空体 / 坏 JSON /
  网关的 HTML 错误页都当
  「还没授权好」接着轮；但「授权码已被消费 / 密文解不开」这类错误再轮也不会好，
  直接以 `error` 收尾。

三种登录方式：MSL / OpenFrp / ChmlFrp 走浏览器授权
（`frp.login.start`），SakuraFrp / ME Frp 走令牌粘贴（`frp.login.token`），
自定义 FRP 不需要登录。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `frp.providers` | — | 平台清单（key / 展示名 / 是否需要登录 / 支持哪种登录） |
| `frp.account` | `provider`，`verify?` | 登录态；`verify=true` 时联网复核（复核不过就清令牌回登录表单） |
| `frp.login.start` | `provider` | 发起浏览器授权，返回 `{url, user_code, state}` |
| `frp.login.status` | `provider` | 当前授权进度（没会话时 `state = idle`） |
| `frp.login.cancel` | `provider` | 取消授权（轮询任务一并收掉） |
| `frp.login.token` | `provider`，`token` | 用粘贴的令牌登录（Sakura / ME Frp） |
| `frp.logout` | `provider` | 退出登录（清令牌 + 账号缓存） |
| `frp.remote.tunnels` | `provider` | 平台侧隧道列表 |
| `frp.remote.nodes` | `provider` | 平台侧节点列表（Sakura 会按用户等级过滤） |
| `frp.remote.create` | `provider`，`node_id`，`name`，`type?`，`local_ip?`，`local_port`，`remote_port` | 在平台上创建隧道（节点由 daemon 按 id 从平台列表里取） |
| `frp.remote.delete` | `provider`，`remote_tunnel_id` | 删除平台上的隧道 |
| `frp.tunnels.list` | — | 本地已保存隧道（带 `config_exists` 与 `data_dir`） |
| `frp.tunnels.save` | `provider` + 隧道字段（见下） | 保存 / 更新，返回 `{tunnel}` |
| `frp.tunnels.config` | `local_id`，`refresh?` | 生成并落盘 frpc 配置，返回 `{config, path, generated}` |
| `frp.tunnels.remove` | `local_id` | 删除本地隧道（元数据 + 配置一起删） |
| `frp.runtimes` | — | 已装好的 frpc 运行环境 + 当前生效的那个（`{runtimes, selected}`） |
| `frp.settings.save` | `frpc_runtime_id?` | 记下跑隧道用哪个 frpc；空 = 回到「用第一个装好的」 |
| `frp.run.list` | — | 所有 FRP 实例的运行态（`{runs}`，不含日志） |
| `frp.run.get` | `local_id` | 单条隧道的运行态（**含日志**，运行页用）；没记录时 `run = null` |
| `frp.run.start` | `local_id` | 启动一条隧道；**已经在跑就原样返回**（一条隧道同时只有一个进程） |
| `frp.run.stop` | `local_id` | 停一条隧道（幂等） |
| `frp.run.clear_log` | `local_id` | 清空某条隧道的运行日志 |

事件：`frp.login` —— `{provider, session_id, state, message, url, user_code, account}`，
`state` 为 `idle / waiting / success / error / cancelled`，`account` 只在 success 里有值
（且已剥掉 `frp_token`）。前端订阅它就能把「等待授权」做成活的，不必自己轮询。

另有 `frp.run`：某条隧道的运行态变了（起了 / 退出了 / 起不来），载荷 = 那条
`frp.run.list` 里的 summary（**不带日志** —— 日志只在 `frp.run.get` 里）。

### 配置是怎么生成的

策略（`builder.rs`）：

| 平台 | 配置来源 |
| --- | --- |
| MSL / ChmlFrp / ME Frp / SakuraFrp | 平台 API 直接返回成品（toml / ini / text），原样用 |
| OpenFrp | 官方客户端闭源，用「节点地址 + frpc 用户 token + 隧道端口」自己拼标准 TOML |
| 自定义 FRP | 用户粘贴的那份，或用简易表单由 **daemon 生成** |

成品配置若没指明日志去向，会补一行 `log.to = "console"`（顶层字段，插在第一个
`[[proxies]]` 之前）；ini 配置（ChmlFrp 那份）整段原样返回，插 TOML 的键会把它弄坏。

`frp.tunnels.config` 是「生成 / 保存配置文件」的落点：默认先读磁盘上已有的那份，
没有（或 `refresh=true`）才重新生成。自定义隧道在 `frp.tunnels.save` 时就会顺手写盘
（纯拼文本、不联网）；别的平台要联网拉，所以留在 `frp.tunnels.config` 里按需触发。

### FRP 实例的运行（一条隧道一个进程）

`frp.run.*` 这一组就是「把一条隧道跑起来」。进程在 **`frp` 模块**里管
（`run.rs`），键是隧道的 `local_id`，不是实例 id：

```text
frp.run.start(local_id)
  └── 选 frpc（设置里选的，没选过用第一个装好的）
        → 拿隧道配置（缺了现生成一份）
        → 起 frpc（-c <toml>，普通管道子进程，stdout/stderr 收进环形缓冲）
```

设计取舍：

- **一条隧道同时只有一个进程**：`run.start` 发现已经在跑就原样返回，不再起一个
  （所以几条游戏实例「连带启动」同一条隧道是安全的）。
- **进程表是每个 `AppState` 一份**（挂在 `app.services`），不是进程级 `static`：
  `instance` 的「连带启动」要走 `frp::start_tunnel` 这条进程内入口拿到它，而
  `instance` 模块比 `frp` 先启动 —— 所以「谁先用到谁建」（`get_or_init`）。
- **起不来也留一条 `failed` 记录**（`record_failure`）：隧道起不来是用户要处理的
  事（frpc 没装、隧道被删、配置生成失败），列表里没有它就等于静默失败 ——
  尤其「游戏实例连带启动失败」那条路径，游戏实例本身是起得来的，不在这儿留一条
  用户根本不知道公网入口没起来。
- **状态一变就推 `frp.run` 事件**：从守候线程里直接 `bus.publish`，前端不用轮询。
- **停止是两段**（SIGTERM → 宽限 → SIGKILL 整个进程组）；daemon 收摊时
  `stop_all` 收掉所有 frpc（它们不是 PTY 子进程，父进程退了不会自己走）。
- **日志是轮询不是事件流**：daemon 只在状态变化时推事件，日志行不推（那是对一个
  调试看板的过度设计）；运行页每 1s 重取一次 200 行的小快照。

### 游戏实例的「连带启动」

`instance.start` 成功后，若这个实例配了 `frp_tunnel_id`，就调 `frp::start_tunnel`
把那条隧道拉起来。**失败不影响实例启动**（原因已留在 `frp.run.list` 里），
**也只连带启动、不连带停止** —— 一条隧道可能被好几个游戏实例连着，跟着停会误伤。

模块自己的错误码（前端按码分支，不要匹配 message）：`frp_not_logged_in`、
`frp_unauthorized`、`frp_api_error`（平台拒绝）、`frp_network_error`、
`frp_protocol_error`、`frp_config_error`、`frp_tunnel_not_found`、`frp_node_not_found`、
`frp_run_failed`（隧道起不来，原因在 message 里）。

---

## 服务端目录模块（`mcserver`）

把「某个服务端类型、某个版本」的服务端文件找出来。**所有上游请求都在 daemon 这边
出网**，前端只发 RPC —— 每个客户端各打一遍上游、客户端所在网络还不一定通，
那两件事都不该让前端承担。

它**自己不下载、不建实例**：只回答「下什么、地址在哪、校验值是什么、启动命令写什么」。
下文件交给 [`download`](#下载队列模块download)，建实例交给
[`instance`](#实例管理模块instance)，前端把三件事串起来：

```text
mcserver.versions → mcserver.plan → instance.create → download.add
```

这样切的理由：**三个模块互不知道对方在干什么**，而且任何一步都能单独重试
（版本选错了就回上一页，下载失败就重下，实例建错了就删掉重来）。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `mcserver.types` | — | 分类 + 服务端类型表（含文件名、建议启动命令、可用的校验算法） |
| `mcserver.versions` | `type` | 某类型的版本列表（新版本在前） |
| `mcserver.loaders` | `type`、`mc_version` | 该 MC 版本可用的加载器版本（目前只有 Fabric） |
| `mcserver.plan` | `type`、`version?`、`loader_version?` | 下载地址 + 校验 + 文件名 + 建议启动命令 |

`mcserver.types` 存在是为了让前端**零硬编码**：类型清单、文件名、分类
都在后端的 `model.rs` 里，前端只渲染 —— 加一个源不必改前端。

`mcserver.plan` 的返回：

```json
{
  "type": "paper",
  "type_name": "Paper",
  "version": "1.21.8",
  "loader_version": null,
  "url": "https://fill-data.papermc.io/v2/objects/…/paper-1.21.8-60.jar",
  "file_name": "server.jar",
  "startup_command": "java -jar server.jar nogui",
  "checksum": { "algorithm": "sha256", "value": "8de7…" }
}
```

`checksum.algorithm` 的取值**直接就是 `download.add` 的参数名**（`sha1` / `sha256` /
`md5`），前端不用做映射；`null` 表示上游没给校验值。

### 这一轮覆盖的源

| 类型 | 分类 | 版本列表 | 下载与校验 |
| --- | --- | --- | --- |
| `vanilla` | 原版 | Mojang `version_manifest.json`（只留 release） | 版本详情里的 `downloads.server`，**只有 sha1** |
| `paper` | 插件 | `fill.papermc.io/v3`（分组，摊平后滤 rc/pre） | `builds/latest` 的 `server:default`，sha256 |
| `folia` | 插件 | 同 paper（PaperMC 的另一个官方 project） | 同 paper，sha256 |
| `purpur` | 插件 | `api.purpurmc.org/v2`（上游升序，自己降序） | 构建详情，**md5** |
| `leaf` | 插件 | `api.leafmc.one/v2`（上游顺序是乱的，自己排） | 构建数组挑最大 → `primary`，sha256 |
| `leaves` | 插件 | `api.leavesmc.org/v2` | `builds/latest` → `application`，sha256 |
| `fabric` | 模组 | `meta.fabricmc.net`（只要 stable） | `loader/{mc}/{loader}/{installer}/server/jar` 直链，**无校验** |
| `velocity` | 代理 | 同 paper | 同 paper，sha256 |
| `bungeecord` | 代理 | **没有版本概念**（`needs_version = false`） | CI 构建号拼出的产物地址，无校验 |

**Forge / NeoForge 没做**：它们要多一步「先下载安装器再跑一遍」，本轮跳过。

### 几条实测出来的取舍

- **版本号一律自己排序**（降序）。上游给的顺序不可信：purpur / leaves 是升序，
  leaf 干脆是乱的（`1.21.11, 1.21.4, 1.21.5 …`），照单反转会原样保留这种乱序。
  排序按 `.` 分段做**数值**比较，
  所以 `1.21` 比 `1.9` 新、`26.3` 比 `1.21.8` 新。
- **原版只有 sha1**（实测 `downloads.server` 就 `sha1` / `size` / `url` 三个字段），
  gosh-dl 的校验又只支持 md5/sha256 —— 所以这一路由 daemon 下载完自己算，
  见下载队列那节的「sha1」一段。
- **purpur 多问一次构建详情**只为拿到 `md5`。`/download` 那个「永远指向
  最新」的短链拿不到校验值；多用一次请求换取完整性校验，值。
- **用构建号拼地址，不用浮动短链**（purpur / bungeecord）。浮动短链在下载途中
  上游出了新构建就会拿到另一个文件。
- **`velocity` / `bungeecord` 的启动命令不带 `nogui`**：代理没有 GUI，多传一个
  未知参数可能被当成非法参数退出 —— `nogui` 只给 Java 系服务端带上。
- **版本号是拼进上游 URL 的**，所以有一道白名单（只允许字母数字与 `._-+`）+
  一道「必须在版本列表里出现过」。前者防路径注入，后者才是主校验。

### 缓存与错误码

版本列表按 `cache_ttl_secs` 缓存（默认 5 分钟，`0` = 不缓存）。它是只读、变得很慢
的数据，而前端在列表页来回点、用户反复重试都会重复打上游。

错误码：`mcserver_type_not_found`、`mcserver_not_found`（版本/构建拿不到）、
`mcserver_version_required`、`mcserver_loader_required`、`mcserver_no_loaders`、
`mcserver_upstream_error`（网络/非 2xx，**可以重试**）、
`mcserver_parse_error`（上游改接口了，得升级 daemon）、`mcserver_unavailable`。

### 上游改接口了怎么办

每个源的**解析**都是单独的纯函数（`api/*.rs` 里的 `parse_*`），并且有测试拿
**真实抓下来的响应体**钉住。上游改形状时先炸的是那些测试，而不是线上用户。

---

## 模组与插件模块（`mods`）

管理一个实例里的模组与插件：**搜索、安装、更新检查、启停、删除**。

跟 [`mcserver`](#服务端目录模块mcserver) 同一条理由：**所有上游请求都在 daemon 这边出网**。
Modrinth 不限地区但国内经常连不上，而且它有 300 次/分钟的限流（实测响应头
`x-ratelimit-limit: 300`）—— 让每个客户端各打一遍，既慢又各自撞限流。

它**自己不下载**：只回答「下什么、放到哪、校验值是什么」。落盘交给
[`download`](#下载队列模块download) 队列，编排交给 [`task`](#任务系统模块task)：

```text
task.submit("mods-install") → mods.plan（解析地址 + 目标目录）→ mods.download（落盘 + 清理旧版本）
```

前端只发一次 `task.submit`，进度看任务对象。

### 三个决策

1. **落到哪个目录按项目类型定**：`mod` → `<实例>/mods/`、`plugin` → `<实例>/plugins/`。
   **不让用户选** —— 选错了（插件丢进 `mods/`）服务端只会静默不加载，是最难查的一类问题。
2. **「启用 / 禁用」是改名**（`X.jar` ↔ `X.jar.disabled`），不搬家。服务端只认
   `*.jar`，改后缀就能让它不加载；而用户自己用文件管理器也看得懂、也能手工改回来。
3. **更新检查按「上游最新」比，不筛游戏版本**（除非调用方显式传 `game_version`）：
   实例元数据里没记它跑的是哪个 MC 版本，硬猜不如让用户按需筛。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `mods.sources` | — | 源 / 项目类型 / 加载器 / 排序表（前端零硬编码） |
| `mods.tags` | `project_type?` | 可选游戏版本（**含快照/beta，带类型**）+ **该类型**可筛的加载器 |
| `mods.search` | `project_type`、`query?`、`loader?`、`game_version?`、`sort?`、`offset?`、`limit?` | 搜索 / 浏览 |
| `mods.project` | `project_id`、`source?` | 项目详情 |
| `mods.versions` | `project_id`、`loader?`、`game_version?` | 项目的版本列表 |
| `mods.installed` | `instance_id` | 已装清单（含从 jar 里读到的元数据） |
| `mods.check_updates` | `instance_id`、`project_type?`、`loader?`、`game_version?` | 按 sha1 批量反查最新版 |
| `mods.match_projects` | `instance_id`、`project_type?` | 按 sha1 对回上游项目（**列表左侧的图标**靠它） |
| `mods.set_enabled` | `instance_id`、`project_type`、`file_name`、`enabled` | 启用 / 禁用（改名，幂等） |
| `mods.remove` | `instance_id`、`project_type`、`file_name` | 删除一个已装文件 |
| `mods.plan` | `instance_id`、`project_id`、`project_type`、`version_id?`、`loader?`、`game_version?` | 解析下载地址与目标路径 |

事件主题一个：`mods.changed`（装 / 删 / 启用 / 禁用都推，前端订阅它回刷列表 ——
否则「另一个客户端装了个模组」在本机要等手动刷新才看得见）。

### 筛选器的可选值也是「表」

**加载器是两张表**（`PROJECT_TYPES[].loaders`）：模组是
`fabric / forge / quilt / neoforge`，插件是
`paper / spigot / bukkit / bungeecord / velocity / waterfall / folia / purpur`。
**插件那一栏绝不能出现 Fabric / Forge** —— 前端如果拿 `mods.sources` 里那张
「全平台合并的总表」去渲染筛选器，就会出这个问题。单测
`loader_tables_never_mix` 把两张表钉住了。

**游戏版本要给全量**（含 snapshot / beta / alpha，顺序就是上游的「新的在前」）。
版本菜单「正式版在前、其余在后」、非正式版的副标题写它的 `version_type`
—— 这个分组由**前端**做。daemon 侧**不要**把快照滤掉：滤了用户就选不了快照版本了。

### 「已装」的名字与版本是从 jar 里读的

`sodium-fabric-0.7.3+mc1.21.8.jar` 这种名字里塞了三个信息，而 `Mod.jar` 什么都不说明。
所以 `mods.installed` 还会带一个 `pmmp` 标志（这个实例是不是 `.phar` 服务端，
判据是启动命令与服务端文件名里有没有 `.phar` / `pocketmine`）—— 界面据此决定
插件那一栏认 `.jar` 还是 `.phar`、标签写「插件下载」还是「Poggit 插件」。
**判断在 daemon**：V2 的实例元数据里没有「运行时是什么」这个字段。

`mods.installed` 会**开一遍 jar** 读元数据，按下面的优先级取第一个能认出来的
（`loader` 决定前端显示成「Fabric / Plugin / BungeeCord…」，`bukkit` 显示成「Plugin」）：

| 元数据文件 | loader | 读什么 |
| --- | --- | --- |
| `fabric.mod.json` | `fabric` | `id` / `name` / `version` / `description` / `contact.homepage` / `authors[]` / `environment` |
| `quilt.mod.json` | `quilt` | `quilt_loader.id`、`metadata.name` / `.description` / `.environment` |
| `META-INF/neoforge.mods.toml` | `neoforge` | `[[mods]]` 的 `modId` / `displayName` / `version` / `description`，加顶层 `authors` / `displayURL` / `clientSideOnly` |
| `META-INF/mods.toml` | `forge` | 同上（loader 由内容里的 `neoforge` 字样判） |
| `mcmod.info` | `forge` | 数组或 `{modList:[…]}` 的第一项：`modid` / `name` / `version` / `description` / `authorList` / `url` |
| `velocity-plugin.json` | `velocity` | 顶层数组第一项：`id` / `name` / `version` / `description` / `authors[]` / `url` |
| `paper-plugin.yml` | `bukkit` | 顶层 `name`（或 `main`）/ `version` / `description` / `author` / `website` |
| `plugin.yml` | `bukkit` | 同上 |
| `bungee.yml` | `bungeecord` | 同上 |

`.phar`（PocketMine）走另一条路：跳过 PHP stub 到 `__HALT_COMPILER` 之后按
tar 解析，读里面的 `plugin.yml`，loader 标 `pocketmine`。

几个要点：

- **一次遍历**，不是「候选挨个 `by_name`」——顺带把大小写差异抹平（有的 jar 里写
  `Plugin.yml`）。高优先级的那个解析不出来时会**退回低优先级的**，而不是因为
  「它存在过」就报告读不出来。
- **`plugin.yml` / `paper-plugin.yml` / `bungee.yml` 不引 YAML 依赖**：只要顶层的
  `name` / `version` 两个标量，行扫描就够（只看没有缩进的行、剥引号与行尾注释）。
  引一个 YAML 库会顺带接受一大票我们并不支持的语法（锚点、多行标量），反而更容易
  给出**错误**的结论。
- **`${file.jarVersion}` 这类占位符当作「没给版本」**：那个值要运行时才由加载器填，
  显示成 `${file.jarVersion}` 比显示成空更让人困惑。
- **读不出元数据的 jar 照样列出来**，只是 `meta` 是 `null`（很多老插件就是没有）。
- **`environment` 的归一化规则**（每条都是踩过的坑）：
  Fabric 的 `environment` 缺失/`*`/非字符串 → `both`；Quilt 的服务端写作
  `dedicated_server`（**不是** Fabric 的 `server`）；Forge 的顶层 `clientSideOnly`
  **缺失 → `unknown`**（判不准就别动它，免得把服务端模组当客户端模组删掉），
  而且 `[[dependencies.x]]` 里的 `side` 说的是**依赖项**的要求，不能拿来判自己。
  这个字段是「清理客户端模组」唯一的依据。
- **YAML 行扫描按缩进只认顶层键**：不看缩进的话，
  `plugin.yml` 里嵌套的 `name:`（比如 `commands.foo.name`）会**覆盖**顶层那个，
  界面上显示成错误的名字。
- **有缓存**：按「文件大小 + mtime」记住解析结果（含「这个 jar 没有元数据」这个结论）。
  进页面 / 切标签 / 下拉刷新都会重扫，不缓存就是每次都把每个 jar 重开一遍。

### 更新检查

`mods.check_updates` 走 Modrinth 的**批量接口** `POST /version_files/update`：
把已装文件的 sha1 分片（默认 100 个一批）提交，拿回「这些文件在当前筛选条件下的
最新版本」。

- **只查启用中的文件**：被禁用的那些服务端根本不加载，它们有没有更新无所谓。
- **算 sha1 是这条路上最贵的一步**（要整读一遍文件），所以只在用户主动点
  「检查更新」时做；`mods.installed` 完全不碰它。超过 `update_max_files` 的文件
  不查，并在响应里标 `truncated`。
- **「有没有更新」的判据是「回来的那个版本里不含我们手上的 sha1」**：当前文件就是
  最新版时，上游照样会把它回给我们（实测），所以不能只看「上游回没回」。
- 上游**不认得**某个哈希时是**直接不给键**（不是给 `null`），那种条目在结果里标
  `known: false` —— 说明这个文件不是从 Modrinth 装的。

### 安装完会清掉被替换的旧版本

模组文件名里带版本号，装了新版就会和旧版**同时存在** —— 两个同名模组会让服务端
起不来。所以 `mods.plan` 会算出 `replaces`，`mods.download` **在下载成功之后**
把它们删掉（失败时旧模组必须还在，否则用户既没新版本也没旧版本）。

匹配是**启发式**，两条线索任意命中就算：jar 里的 `meta.id` 等于项目 slug，
或者文件名就是要下的那个。**认不出来时什么都不删** —— 宁可留下一个重复文件让用户
自己处理，也不要凭猜删掉一个无关的模组。

### 错误码

`mods_type_not_found`、`mods_source_not_found`、`mods_not_found`（这个 jar / 项目没有）、
`mods_version_not_found`、`mods_loader_unsupported`（给插件筛 fabric 这种组合）、
`mods_no_file`（上游没给可下载文件）、`mods_target_exists`（重名，不覆盖）、
`mods_io_error`、`mods_not_a_file`、`mods_instance_not_found`、
`mods_upstream_error`（可重试）、`mods_parse_error`（上游改接口了，得升级 daemon）、
`mods_unavailable`。

### 本轮故意没做的

- **依赖解析**：上游给了 `dependencies`（含 `required`），但 `mods.plan` 只是**原样带给
  前端显示**，不自动递归安装。自动装依赖会连带装一堆用户没要的东西。
- **整合包**（Modrinth 的 `modpack`）：那是另一条流程（解析包 → 装服务端 + 模组），
  与「往 mods/ 放一个 jar」不是一回事。
- **CurseForge**：要 API Key，属于「加源」而不是「改结构」，随时能加。
- **`.phar`（PocketMine）**：Modrinth 上没有对应物，认了也只会列出一堆读不出元数据的
  文件。

---

## 下载队列模块（`download`）

全局一份的 HTTP 下载队列，底层是 [`gosh-dl`](https://crates.io/crates/gosh-dl)。
队列是**全局**的（引擎只有一个：并发上限、限速、事件流都是进程级），
但每个任务都归属**某个实例** —— 落盘路径以实例根目录为根。

### 为什么单独一个模块

队列不是某个实例的属性，也不该散进 `instance` 模块。它只向 instance 借一样东西：
**实例 id → 实例工作目录**。这件事由 `instance::resolve_instance_root(data_dir, id)`
这个纯函数提供 —— 目录布局的知识（元数据里自定义的 `path`、否则
`<root>/instances/<id>`）只留在 `instance/store.rs` 一处，下载这边不重写一遍。

`[modules.config.download]` 里**没有 `dir`**：数据根直接读
`[modules.config.instance] dir`（连回退链一起复用）。两处各配一个根目录，
迟早会配出「下载不知道实例在哪」的错位。读的是**配置节本身**而不是 instance 模块的
运行时状态，所以 instance 被 `modules.disabled` 关掉时，下载照样算得对目录。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `download.add` | `url`、`instance_id`、`path?`、`filename?`、`md5?` / `sha256?` / `sha1?` | 提交任务，返回任务对象 |
| `download.status` | `id` | 按任务 ID 查状态 |
| `download.list` | — | 全部任务（最新提交在前）+ 汇总速率 |

参数细节：

- `path` 是**相对实例根目录**的目录，`""`（缺省）就是实例根。`..` 与绝对路径一律拒绝
  —— 走的是 instance 那一份 `files::resolve`，不是另写一份。
- `filename` 是文件名；不给就从 URL 末段取（`%XX` **不解码**，想要好看的名字就自己传）。
  它必须是**单段**：带 `/` 或 `\` 会被拒 —— 目录归 `path` 管，混着写等于给逃逸开第二个入口。
- `md5` / `sha256` / `sha1` 只接受**一个**，且提交时就校验十六进制长度（32 / 64 / 40）。
  给多个直接报错，不静默取一个。
- 目标文件已存在 → 直接拒绝（`download_target_exists`）。`gosh-dl` 默认是**静默覆盖**，
  而这里写的是实例目录 —— 里面躺着服务端 jar 与世界存档。

任务对象（三个方法返回同一形状，**事件里带的也是它**）：

```json
{
  "id": "3f2b1c4d-…",
  "instance_id": "a1b2c3d4e5f60718",
  "path": "mods",
  "filename": "foo.jar",
  "target": "mods/foo.jar",
  "state": "downloading",
  "url": "https://example.com/foo.jar",
  "total_size": 1234, "completed_size": 512, "download_speed": 256,
  "eta_seconds": 3, "connections": 4, "progress_percent": 41.5,
  "checksum": { "algorithm": "sha256", "value": "…" },
  "created_at_ms": 1758800000000,
  "finished_at_ms": null,
  "error": { "kind": "…", "message": "…", "retryable": true }
}
```

- `state` 取值：`queued` / `connecting` / `downloading` / `seeding` / `paused` /
  `verifying` / `completed` / `error`。
  `verifying` 是我们自己加的一个状态（见下面的「sha1」），`seeding` 与 `paused`
  当前拿不到（没开 BT、也没做暂停）。
- `path` / `target` 是**相对实例根目录**的路径，前端展示用后者。
- `error` 只在 `state = "error"` 时非空。**提交阶段**能判定的问题走错误码；
  真正的下载失败（连不上、404、校验不过）是**异步**的，体现为任务状态 ——
  不假装成一次调用的失败。
- 任务 ID 是**完整 UUID**（gosh-dl 的 `DownloadId`）。别用它的 `to_gid()` 那种 16 位 hex：
  那只取 UUID 前 8 字节，是有损投影，拿它反查会查到另一个 ID（`from_gid` 会把高位填零）。

### sha1：gosh-dl 不支持的那一种

`gosh-dl` 的校验只有 md5 / sha256，而**原版服务端的上游只给 sha1**
（Mojang 版本详情的 `downloads.server` 就 `sha1` / `size` / `url` 三个字段，实测）。
所以这一路由 daemon 自己算：

1. 下完后引擎报 `completed`，扫描循环发现「还欠一次 sha1」→ 把任务标成 `verifying`
   并起一个后台任务；
2. 后台任务流式读文件算 sha1（几十 MB 到几 GB，不能整个读进内存）；
3. 对上 → `completed`；对不上 → **删掉文件**并把任务渲染成 `error`
   （`error.kind = "checksum_mismatch"`）。

第 3 步删文件是刻意的：留一个内容不对的 `server.jar` 比没有更糟 ——
用户会以为下好了，然后对着一个起不来的服务端查半天。

### 事件：`download.progress` 与 `download.state`

对齐 monitor 那套「**首拉快照 + 订阅推送**」的用法：

- `download.progress` —— 排队中 / 进行中（含 `verifying`）的任务进度，**间隔推送**；
- `download.state` —— 状态**变了**的任务（含终态与校验失败），只在迁移时推一次。

两条主题携带的都是**完整的任务对象**（和 `download.status` 返回的同形），
前端一套模型就能同时吃快照与事件。进页先 `download.list`（或 `download.status`）
取一次快照，然后订阅 —— 中间的缝隙最多一个推送间隔。

推送间隔由 `progress_interval_ms` 决定（默认 500 ms，clamp `[200, 5000]`）。

**为什么是「定时扫引擎」而不是转发 gosh-dl 的事件**：它每读一块推一条，
一个 60 MB 的 jar 能推上千条，前端和事件总线都会被冲垮。定时扫天然是节流过的；
而且即使慢消费者丢过事件（broadcast 的 `Lagged`），下一拍也会自动收敛回真值 ——
不需要补历史。

**`total_size` 早期可能是空的，前端要能画「不确定进度」**：引擎的进度回调
只在**读到数据**时触发，而且同一连接里**最快 250ms 一次**。所以刚提交、数据还没
开始流动的那几帧只有 `completed_size = 0`，`total_size` 是 `null`；
等第一块数据到了才有总大小。前端据此决定画确定进度条还是不确定进度条
（`total_size` 为空时用转圈那种）。

### 落盘与生命周期

- 目标目录会被自动建出来（`gosh-dl` 自己也会建；提前建是为了让「路径不可写」
  在**提交时**就报出来，而不是变成一个异步失败的任务）。
- 队列**不持久化**：`database_path` 留空、`storage` feature 也没开，daemon 重启即清空。
  `stop()` 会调引擎的 `shutdown()`，取消进行中的任务（每个最多等 5 秒）。
- 目标文件已存在、或同一路径已有任务在跑，都按 `download_target_exists` 拒绝。
  后者**只算还没结束的任务** —— 失败过的任务会一直留在记账里（列表还要显示它），
  要是拿它挡路，用户「重试同一个文件」就会被自己的历史顶回去。
  两次检查都是尽力而为（检查与落盘之间有时差）。

### 错误码（前端按码分支，不要匹配 message）

`download_instance_not_found`、`download_task_not_found`、`download_url_invalid`、
`download_path_invalid`、`download_filename_invalid`、`download_filename_missing`、
`download_checksum_invalid`、`download_target_exists`、`download_save_failed`、
`download_engine_unavailable`、`download_failed`。

### 本轮故意没做的（按依赖顺序）

1. **暂停 / 取消 / 重试**（`download.pause` / `cancel` / `resume`）：引擎支持
   （`pause` / `resume` / `cancel`），只是这一轮只要那三个接口 + 事件。
   在取消接上之前，提交错了只能等它下完。
2. **按实例过滤列表**与**分页**：`download.list` 现在一次回全部。
3. **持久化**（重启续传）：要打开 gosh-dl 的 `storage` feature + `database_path`，
   并且**我们那张「任务 → 实例 + 相对路径」的记账表也必须一起落盘** ——
   否则任务回来了却不知道属于哪个实例，而恢复出来的 `save_dir` 是绝对路径，
   实例被删或改过 `dir` 就会往错的地方写。
4. **BitTorrent / 磁力**：gosh-dl 支持，但依赖里已经**关掉**了
   （`default-features = false, features = ["http"]`）。真要加，把 `Cargo.toml`
   那行改回默认 features，注意会带进 `mainline` / `socket2` / `bitvec`，
   并且 DHT / PEX / LPD 会默认主动出网。
5. **URL 黑名单**：现在只保证是 http/https（gosh-dl 兜底），不挡私网 / 回环地址。
   鉴权令牌是当前唯一的防线；要挡解析到内网的 URL 得另外加。

---

## 运行环境模块（`runtime`）

下载与管理运行环境，目前两家厂商：**Zulu 的 JDK**（[Azul Metadata API]）与
**fatedier 的 frp**（[GitHub Releases]）。一个环境的完整生命周期由 daemon 包办，
而且**是一条工作流**：

```text
task.submit("runtime-install", {provider: "frp", version: "0.71.0"})
  └── download（解析上游 → 落元数据 → 交给下载队列并等它下完）
        └── extract（解压 → 找可执行文件 → 落终态）
```

`extract` 找的可执行文件**由厂商决定**（厂商表里的 `launcher`）：JDK 找 `bin/java`，
frp 找包里的 `frpc`（同一个包里还有 `frps`，自建服务端将来要用）。两家的包布局
不一样，所以「找文件」的参数收在厂商表里，而不是写死在解压代码里。

**前端提交一次 `task.submit` 就可以关掉 App**，装完的结果在元数据里，
中间过程靠 `task.state` / `task.progress` 与 `runtime.state` 推 —— 200 MB 下完
却因为 App 关了就没人解压，是用户没法自救的状态，所以这里刻意不像服务端下载
那样由前端串步骤。

拆成两步（而不是以前那种「一次调用里 spawn 一个后台任务把两件事做完」）是为了
**两件事各自可见**：前端能看到正在下载还是正在解压、下载进度是多少、失败在哪一步。

* **失败清理**：解压失败会把半截的解压目录与暂存压缩包一起删掉（`download`
  步骤的**回滚**干的）；元数据保留为 `failed`，`runtime.list` 里看得见原因。
* **并发挡板**：同一个 id 只能有一个安装在跑。占位（`RunningGuard`）放在任务级
  暂存里，所以它的生命周期天然等于这个任务 —— 成功 / 失败 / 取消都会自动摘掉，
  不需要收尾钩子。
* **取消不触发回滚**（szal 的语义）：用户主动取消时半截产物会留下，要自己删。

**`runtime.install` 已经删掉了** —— 装环境只有上面这一条路。

[Azul Metadata API]: https://api.azul.com/metadata/v1/docs/swagger
[GitHub Releases]: https://docs.github.com/en/rest/releases/releases

### frp 的版本清单（GitHub API）

frp 的版本与下载地址走 **fatedier/frp 仓库的 Releases API**（`api/github.rs`）：

- **默认只拉 latest**（`/releases/fatedier/frp/releases/latest`，一次请求就够）——
  绝大多数情况用最新版就够。
- **点了「历史版本」才拉老版本**（`/releases?per_page=N`），前端把 `all=true`
  传进来。默认值必须是「最省」的那个：GitHub 未认证配额只有 **60 次/小时**，
  每点一次历史版本就烧一次配额。
- 下载地址取 asset 的 `browser_download_url`，校验值直接拿 GitHub asset 的
  **`digest`**（sha256），不用再下 `frp_sha256_checksums.txt` 去翻。
- 版本清单有 TTL 缓存（`cache_ttl_secs`，默认 300s），`latest` 与 `history` 分开
  缓存（两个入口的响应形状不同）。

### 落盘布局

与实例**同一套数据根**（`[modules.config.instance] dir`，运行环境没有自己的 `dir`）：

```text
<data_dir>/config/runtimes/<id>.json   元数据（含「正在装」「装失败」）
<data_dir>/runtimes/<id>/              解压出来的 JDK
<data_dir>/runtimes/.staging/<id>/     下载中的压缩包（装完就删）
```

**没有索引文件**（实例那边有 `instances.json`）：环境数量是个位数，扫一遍
`config/runtimes/` 就够。少一份要与元数据对齐的状态，就少一类「索引说有、
文件却不在」的问题。

### id 与状态

id 是 `zulu-jdk-21-linux-x64`、`frp-frpc-0.71.0-linux-x64` 这种**可读且稳定**的
标识（厂商-包类型-版本-平台）：一个组合只有一个环境，**再装就是覆盖重装**。
随机 id 会让列表里出现两个「Zulu JDK 21」而用户分不清。
版本是**字符串**（JDK 是 `21`，frp 是 `0.71.0`），统一按上游的说法
收下来，前端不做「这个厂商的版本号长什么样」的猜测。

状态机：`downloading → extracting → installed`，任何一步失败落成
`failed`（带 `stage: download|extract` 与原因）。两个要点：

* **daemon 重启**：下载队列不持久化，重启后「正在装」不可能自己装完。
  `start()` 会把它们收拾成确定的失败态；若暂存里那个压缩包的大小与上游给的
  一致，说明死在解压那一步，`stage` 记成 `extract` —— 重试时**跳过那 200 MB**。
* **删除就是取消**：在途的后台任务每次落地前都会问一遍「我这条记账还在不在」，
  所以 `runtime.delete` 先删元数据就等于叫停它（真的在解压中的那一轮，结束后会
  把自己刚解出来的东西再清一次）。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `runtime.catalog` | — | 厂商 / 包类型表 + 本机平台（前端零硬编码，`supported=false` 时入口置灰） |
| `runtime.versions` | `provider?`、`package_type?`、`all?` | 可装的版本列表（新的在前；默认只给最新一个，`all=true` 才拉全部） |
| `runtime.list` | — | 全部环境（含正在装与失败的）+ 环境目录 |
| `runtime.delete` | `id` | 删掉环境（元数据 + 目录 + 暂存） |

`runtime.versions` 每一项是 `{version, label, subtitle}`：`version` 是装的时候
原样传回去的字符串，`label` 是列表主行（Zulu 是 `Java 21`、frp 是 `0.71.0`），
`subtitle` 是副行（Zulu 是完整版本号、frp 是发布日期）。**前端不拼这些字符串** ——
厂商不同、版本号的读法就不同，那是厂商表里的知识（`version_prefix`）。

安装走任务系统：`task.submit("runtime-install", {provider?, package_type?, version})`。
参数不合法的（比如缺 `version`）在 `task.submit` 当场被拒
（`task_invalid_params`），**不会拿到任务 id**；上游找不到版本这类失败落在任务里
（`task.get` 的 `steps[].error`，带稳定码前缀 `runtime_version_not_found` 等），
同时环境元数据变 `failed`。

事件：`runtime.state`，**载荷与 `runtime.list` 里的单项同形**。删除不推事件
（删掉之后没有「这个环境」可以描述了），前端自己刷新列表。

错误码：`runtime_unsupported_host`（这台机器没有对应的构建）、
`runtime_provider_not_found`、`runtime_package_type_not_found`、
`runtime_version_required`、`runtime_version_not_found`、`runtime_not_found`、
`runtime_busy`（同一环境并发装）、`runtime_upstream_error`、`runtime_parse_error`
（上游改接口了）、`runtime_save_failed`。

### 几条实测出来的取舍

* **上游的查询参数是防错的关键**：Linux 要用 `os=linux-glibc`（写 `linux` 会同时
  回一份 musl 构建，列表里没有字段可辨）；`crac_supported=false` /
  `crs_supported=false` / `javafx_bundled=false` 滤掉 CRaC 与 JavaFX 变体；
  `availability_types=CA` 只要免费社区构建（`SA` 是订阅版，没有凭证下不下来）。
* **校验值必须问详情**：列表接口（`ZuluPkgList`）里没有 hash，详情（`ZuluPkgDetail`）
  才有 `sha256_hash` / `md5_hash` / `size`。拿到详情后还会核对 `archive_type` 与
  `lib_c_type` —— 查询参数写错时上游不报错，只会给一份别的平台的包。**没有
  sha256 的包拒绝下载**。
* **解压后找 `bin/java`，不猜顶层目录名**：Linux/Windows 的顶层是
  `zulu21.52.203-…`，macOS 却是 `zulu-21.jdk/Contents/Home`，深一层。
  找不到 `bin/java` 就不算装好，整份解压结果清掉。
* **权限位交给 tar**：Linux/macOS 用上游的 `.tar.gz`（`tar` 默认按
  `mode & 0o777` 落权限位，`bin/java` 的可执行位不用额外开关）；Windows 用 `zip`，
  解压时从条目的 unix mode 补回来。为此加了 `tar` + `flate2` 两个成熟 crate
  —— 平台相关的权限 / 符号链接处理，不该手写。
* **与实例启动的关系**：这一轮**不接**。实例仍然只有一条 `startupCommand`
  （用户定的硬约束）；环境先做成独立的「下载 + 管理」，之后要不要让实例引用
  某个环境（启动时把 `bin` 加进 PATH 或拼绝对路径）再说。
* JRE 暂不开放（Zulu 也提供，接口同一条查询、只差 `java_package_type` 一个参数）；
  基岩端那种「别家 JDK」（Temurin / Corretto）未做，加厂商 = 加一个适配器文件。

---

---

## 任务系统模块（`task`）

把多步操作编排成一个**任务**：底层是 [szal] 的工作流引擎（步骤 / 流程 / 重试 /
回滚 / 取消）。模块本身**不含业务知识** —— 它只管执行与可观测性，工作流由
各业务模块在自己的 `start()` 里注册步骤与模板。

[szal]: https://crates.io/crates/szal

### 已注册的两条内置工作流

| 工作流 | 步骤 | 参数 |
| --- | --- | --- |
| `instance-provision` | `mcserver.plan`（准备服务端）→ `instance.create`（创建实例）→ `instance.download`（下载服务端） | `name`、`type`、`version?`、`loader_version?` |
| `runtime-install` | `runtime.download`（下载运行环境）→ `runtime.extract`（解压运行环境） | `provider?`、`package_type?`、`version` |

**步骤是按模块注册的，flow 按 `step_type` 组合** —— 所以 `instance-provision`
跨了三个模块（`instance` 定义模板，`mcserver` 提供第一步，`download` 的队列被
第三步复用）。加一条工作流 = 加一个步骤 + 一个模板，不必动 task 模块。

「实例创建→下载」的**回滚**是三步里最有价值的地方：`create` 步骤标了
`rollbackable`，后面失败时引擎会把它撤销（`instance.delete`，连目录一起）——
「下载没成就不留空壳实例」，而且**只删这一次流程建的那个**
（id 从 `create` 步骤的产出里拿）。

### 为什么用 szal

- 现成的步骤超时 / 重试退避 / 失败回滚 / 取消，自己写一遍既不短也不可靠。
- 默认构建零数据库与基础设施依赖（`sqlite` / `fleet` / `majra` 都是 feature，
  不开），只多了 szal 同作者的 `bote`（MCP/JSON-RPC，我们用不上但甩不掉，
  GPL-3.0-only，与 AGPL 组合无碍）与 `zmij`（dtolnay 的浮点格式化标准件）。
- szal 的 `CancellationToken` 直接是 `tokio_util::sync::CancellationToken`
  的 re-export，与 daemon 的关闭令牌同源。

### 设计取舍（都是源码里确认过的）

- **每个任务一个 `Engine` 实例**。szal 的进度事件（`StepProgress`）与生命
  周期事件（`WorkflowEvent`）都**只带步骤级标识**，没有「哪次执行」的
  概念——多个任务共享一个 Engine 时事件分不清归属。按任务建 Engine、把
  任务 id 闭包捕获进两个 sink，事件天然带着归属；Engine 本身只是配置加
  几个 `Arc`，开销可忽略。
- **步骤间数据走共享产出表**，不走引擎。szal 的 handler 只收到步骤自己的
  `StepDef`（定义原样，引擎不注入上下文），「前面步骤产生了什么」（比如
  create 步骤写进去的 `instance_id`）从 `StepEnv.outputs` 取——任务执行器
  在步骤成功后自动写，回滚处理也读同一份。
- **取消只在步骤之间生效**。正在执行的步骤会跑完；等待类步骤（下载等）
  要自己 `select!` 取消令牌。**取消不触发回滚**——skipped 不算失败，用户
  主动放弃，已完成的部分留给他自己决定（与「失败必须收拾干净」是两种语义）。
- **不用 flow 级超时**。szal 的 `FlowDef.timeout_ms` 在超时后会把剩余步骤
  全标 `skipped` 但 `success` 仍为 `true`（已确认是 1.2.0 的行为）——超时
  归零成「成功」是个坑。所以只用步骤级超时（`StepDef::with_timeout`，
  注意 `new()` 默认 30 秒，长步骤要显式放大或用 `task::flows::TIMEOUT_UNLIMITED`）。
- **不持久化**：任务表内存态，重启即清空（与下载队列、运行环境的暂存语义
  一致）。元数据不落盘，`start()` 无需「重启收拾」。

### 注册入口（给别的模块用）

注册表挂在 `AppState` 的跨模块句柄槽上（[`crate::services`]）——模块之间没有
对象查找，共享句柄都走这里。业务模块在 `start()` 里：

```rust
use edgecube_daemon::module::builtin::task::flows::{
    self, FlowRegistry, FlowStepInfo, FlowTemplate, StepSpec, StepEnv, TIMEOUT_UNLIMITED,
};

// 取注册表（还没有就建一个；谁先起来谁建，task 起来时用的是同一份）
let registry = flows::registry(&env.app);

// 注册一个步骤类型（step_type 用「模块id.动作」）。
// 用 `*_or_warn` 是为了**不因为撞名把模块启动搞挂**（生产撞名会记一条 warn）
registry.register_step_or_warn("instance.create", StepSpec {
    title: "创建实例".into(),
    run: Arc::new(|step, progress, env| Box::pin(async move {
        // ... 读 step.config、env.app，干活，返回 JSON output
    })),
    // 标了可回滚的步骤必须有 rollback
    rollback: Some(Arc::new(|_step, env| Box::pin(async move {
        // 从 env.output("create") 拿 instance_id，删掉它
        Ok(())
    }))),
});

// 注册一个工作流模板
registry.register_flow_or_warn("instance-provision", FlowTemplate {
    title: "创建实例并下载服务端".into(),
    steps: vec![ /* FlowStepInfo { name, title, step_type } */ ],
    build: Arc::new(|params| {
        // 校验 params → 构造 FlowDef（StepDef::new(...).with_step_type(...).with_config(...)）
        Ok(flow)
    }),
});
```

`task.submit` 提交时会预检每个 `step_type` 都已注册、标了可回滚的步骤确有
回滚实现——坏任务不进队。

**步骤实现里能拿到 `StepEnv`**：`app`（全局状态）、`outputs`（前面步骤的产出，
`env.output("name").await`）、`cancel`（协作取消令牌）、`scratch`
（任务级暂存，放 JSON 装不下的东西 —— 比如 `runtime` 的并发占位 guard；
任务一结束自动析构）。

### 跨模块共享句柄（`services`）

模块之间**没有对象查找**：`ModuleRegistry::all_modules()` 回吐的是
`Arc<dyn Module>`，trait 上没有 `as_any`，拿不到具体类型。可确实有「A 要用
B 的能力」的场景 —— 工作流步骤要复用下载队列、要问服务端目录拿下载计划。

这类句柄统一放进 **`AppState.services`**（`src/services.rs`，一个按类型存的槽）：

```rust
// 放（模块自己的 start() 里）
env.app.services.insert(Arc::new(my_handle));

// 取（任何拿到 AppState 的地方）
let handle = env.app.services.get::<MyHandle>();
```

**为什么不是模块内的 `static OnceLock`**（这是踩过的坑）：那种写法在生产形态
（一个进程一个 daemon）下没问题，但**集成测试一个进程会起多个 `AppState`**
（每个 harness 一套模块），于是第二个 `AppState` 会拿到第一个的句柄 —— 而那个
句柄绑在第一个的数据目录 / 引擎上。症状极隐蔽：**用例单独跑通过、跟在别的用例
后面就错**（"工作流没注册"、"下载落到别的目录"）。

挂在 `AppState` 上天然就是「一份实例一份句柄」。当前放进去的两样：下载队列
（`download::queue_of(&app)`）与工作流注册表（`task::flows::registry(&app)`）。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `task.flows` | — | 已注册的工作流清单（名字 / 标题 / 步骤概览） |
| `task.submit` | `flow`、`params?` | 提交任务，返回任务对象（`queued` 或 `running`） |
| `task.list` | — | 全部任务（最新提交在前） |
| `task.get` | `id` | 按任务 id 查 |
| `task.cancel` | `id` | 取消（幂等；已终态的原样返回） |

HTTP 侧同一套：`GET /api/tasks`、`POST /api/tasks`（`{flow, params}`）、
`GET /api/tasks/{id}`、`POST /api/tasks/{id}/cancel`、`GET /api/task-flows`。

### 任务对象

```json
{
  "id": "3f2b1c4d-…",
  "flow": "instance-provision",
  "title": "创建实例并下载服务端",
  "params": { …调用方给的原始参数… },
  "state": "running",
  "current_step": "download",
  "steps": [
    { "id": "…", "name": "create", "title": "创建实例", "step_type": "instance.create",
      "status": "completed", "progress": null, "output": {…}, "error": null,
      "attempts": 1, "duration_ms": 42 }
  ],
  "error": null,
  "rolled_back": false,
  "created_at_ms": …, "started_at_ms": …, "finished_at_ms": null,
  "total_duration_ms": null
}
```

- `state`：`queued` / `running` / `completed` / `failed` / `cancelled`。
- `steps[].status`：`pending` / `running` / `completed` / `failed` /
  `skipped` / `rolled_back`（回滚是叠加在 `completed` 上的，单独标出）。
- `steps[].progress`：步骤实现通过 `ProgressReporter.report` 上报的最近一帧
  （如下载百分比）；**上报频率由步骤实现自己控制**，模块不二次节流。
- `error`：失败时 `{step, message}`，第一个失败的步骤。
- 与下载队列同一套约定：**快照 + 事件带完整对象**——`task.get` / `task.list`
  / `task.state` / `task.progress` 四处载荷同形，前端一套模型通吃。

### 事件

- `task.state` —— 任务或步骤状态变了（含失败后的回滚过程），载荷为完整
  任务对象。
- `task.progress` —— 步骤进行中的进度，载荷为完整任务对象（步骤的
  `progress` 字段是最新一帧）。

### 错误码

`task_flow_not_found`、`task_not_found`、`task_invalid_params`
（参数不被工作流接受 / 步骤 `step_type` 未注册 / 标了回滚但没注册回滚实现）、
`task_engine_error`（引擎级异常，预检后理论少见）。

### 许可证说明

szal 是 **AGPL-3.0-only**。daemon 作为与其链接的组合作品整体按 AGPL 条款
提供——`daemon/Cargo.toml` 与 `daemon/LICENSE` 已相应改为 AGPL-3.0-or-later。
仓库根与 app 不链接 szal，仍为 GPL-3.0-or-later；这精确反映了「只有 daemon
受传染」的事实。

---

## 加一个功能模块

### 1. 写模块

在 `src/module/builtin/` 下新建文件，照着 `ticker.rs` 抄。最小形态：

```rust
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::json;

use crate::error::Result;
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};

/// [modules.config.demo]
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct DemoConfig {
    greeting: String,
}

pub struct DemoModule;

#[async_trait]
impl Module for DemoModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("demo", "示例", env!("CARGO_PKG_VERSION"))
            .description("演示用模块")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        // 声明会推哪些事件（供客户端发现）
        reg.topic("demo.hello", "打招呼事件");

        // WS 方法：类 HTTP 的一问一答
        reg.method("demo.greet", "打个招呼", |ctx| async move {
            let name: String = ctx.param_or("name", "world".to_string())?;
            Ok(json!({ "greeting": format!("hello, {name}") }))
        });

        // 限定只允许本机调用的方法
        reg.method_with_scope("demo.danger", "危险操作", crate::module::Scope::Local,
            |_ctx| async move { ok(json!({ "done": true })) });

        Ok(())
    }

    /// 服务已就绪，起后台任务。此处的失败会让启动失败并回滚已启动的模块。
    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let cfg: DemoConfig = env.config()?;
        tracing::info!(greeting = %cfg.greeting, "demo 模块已加载");
        // 需要共享状态就自己持有 Arc<...>，需要推送就 env.app.bus.publish_from(...)
        // 要与别的模块共享**句柄**（队列、注册表之类）就放进 env.app.services
        // —— 那是**每个 AppState 一份**的槽，别用模块内的 static OnceLock
        // （一个进程多个 AppState 时会串到别的实例上，见 `src/services.rs`）
        Ok(())
    }

    /// 优雅关闭，按启动的逆序调用。
    async fn stop(&self) -> Result<()> {
        Ok(())
    }
}
```

### 2. 注册（**唯一的插拔点**）

`src/module/registry.rs`：

```rust
pub fn builtin_modules() -> Vec<Arc<dyn Module>> {
    vec![
        Arc::new(builtin::core::CoreModule::new()),
        Arc::new(builtin::ticker::TickerModule::new()),
        Arc::new(builtin::demo::DemoModule::new()),   // ← 加这一行
    ]
}
```

### 3. 挂 HTTP 路由（可选）

```rust
fn register(&self, reg: &mut Registration) -> Result<()> {
    reg.router("api/demo", axum::Router::new().route("/api/demo", axum::routing::get(handler)));
    Ok(())
}
```

处理器里用 `State<AppState>` 取全局状态，返回 `crate::server::http::api_result(...)`
就能拿到和 WS 侧一致的错误码与 HTTP 状态码映射。

### 模块能挂的四样东西

| 扩展点 | 注册方法 | 生命周期 |
| --- | --- | --- |
| WS 方法 | `reg.method(...)` | 服务存活期间 |
| HTTP 路由 | `reg.router(...)` | 服务存活期间 |
| 事件主题 | `reg.topic(...)` | 服务存活期间 |
| 后台任务 / 资源 | `Module::start` / `Module::stop` | 服务启动后 → 关闭前 |

### 三个「拔」

1. **编译期拔**：从 `builtin_modules()` 里删掉那一行，模块彻底不存在。
2. **配置期拔**：`modules.disabled = ["demo"]`，模块被构建但方法/路由/主题一概不注册。
3. **运行期禁用**（未实现）：框架已预留 `ModuleRegistry::all_modules()` 与
   `Module::stop`，将来可在此基础上做热插拔。

> 运行期动态库（dylib）加载**没有**实现。真要做的话，模块注册表已经用
> `Arc<dyn Module>` 抽象好了，只需要再补一个 loader + 稳定的 ABI 约定，
> 不需要改动上面的任何扩展点。

---

## 目录结构

```
src/
├── main.rs                  入口：编排启动流程（解析参数 → 日志 → 配置 → 注册表 → 信号 → 服务）
├── lib.rs                   库门面 + 版本/协议号常量
├── cli.rs                   命令行解析（零依赖手写）
├── logging.rs               tracing 初始化，支持配置读完后热调级别
├── config/mod.rs            配置四层合并 + 校验 + 带注释模板
├── error.rs                 Error（进程内）与 RpcError（给客户端）两层错误
├── event.rs                 事件总线（broadcast）+ 主题匹配
├── conn.rs                  连接表：点对点推送、广播、连接快照
├── state.rs                 AppState：配置快照、总线、注册表、连接表、取消令牌、跨模块句柄槽
├── services.rs              跨模块共享句柄的槽（每个 AppState 一份）
├── module/
│   ├── mod.rs               Module trait、Registration、CallCtx
│   ├── registry.rs          ModuleRegistry + builtin_modules()（插拔点）
│   └── builtin/
│       ├── core.rs          框架自省模块（always_on；core.host 提供主机信息）
│       ├── ticker.rs        示例模块模板
│       ├── monitor.rs       系统监控（内存 / CPU，常驻采样）
│       ├── instance/        实例管理（真正的业务模块）
│       │   ├── mod.rs       模块 + WS 方法 + HTTP 路由 + 控制台流
│       │   ├── model.rs     实例元数据 / 状态 / 生命周期阶段
│       │   ├── store.rs     存储层：索引、原子写、目录统计、路径校验
│       │   ├── provision.rs `instance-provision` 工作流：准备 → 创建 → 下载
│       │   ├── config.rs   服务端配置：认哪种文件（pnx / allay / java / pmmp）+ 读写

│       │   └── process.rs   PTY 会话 + 启停 + 阶段状态机（照 pty-terminal-demo）
│       ├── download.rs     下载队列（全局 HTTP 下载，落盘以实例根为根）
│       ├── mcserver/       服务端目录（各服务端源的版本与下载地址）
│       │   ├── mod.rs       模块 + 四个方法 + 版本列表缓存
│       │   ├── model.rs     分类 / 类型表（文件名、启动命令、可用的校验算法）
│       │   └── api/         各家上游客户端（一个源一个文件）
│       │       ├── mod.rs     HTTP 封装 + 版本号比较 + 版本号白名单
│       │       ├── mojang.rs   · papermc.rs  · purpur.rs
│       │       ├── leafmc.rs   · fabric.rs   · bungeecord.rs
│       ├── mods/           模组与插件（Modrinth 的搜索 / 版本 / 安装 + 已装管理）
│       │   ├── mod.rs       模块 + 十个方法 + `mods-install` 工作流（含 install 子模块）
│       │   ├── model.rs     源 / 项目类型 / 加载器 / 排序表 + 中立模型 + 已装条目
│       │   ├── installed.rs 扫 mods/ 与 plugins/、读 jar 元数据、启停改名、删除
│       │   └── api/
│       │       ├── mod.rs     HTTP 封装转出
│       │       └── modrinth.rs Modrinth v2（搜索 / 项目 / 版本 / 哈希反查）
│       ├── runtime/       运行环境（Zulu JDK / frp 的下载 / 解压 / 列表 / 删除）
│       │   ├── mod.rs       模块 + 四个方法 + 重启收拾（安装走 install.rs 的工作流）
│       │   ├── install.rs   `runtime-install` 工作流：下载 → 解压两个步骤
│       │   ├── model.rs     厂商 / 包类型表 + 目标平台 + 环境 id 与状态机
│       │   ├── store.rs     config/runtimes/<id>.json 的读写 + 目录布局
│       │   ├── extract.rs   解压（tar.gz / zip）+ 按厂商找可执行文件（java / frpc）
│       │   └── api/
│       │       ├── azul.rs    Azul Metadata API（JDK 列表 / 详情的解析）
│       │       └── github.rs  GitHub Releases（frp 的 latest / 历史版本）
│       ├── task/             任务系统（szal 工作流引擎：执行与可观测性底座）
│       │   ├── mod.rs       模块 + 五个方法 + HTTP 镜像 + 事件主题
│       │   ├── model.rs     任务对象（snake_case）+ 步骤状态机 + 配置
│       │   ├── flows.rs     注册入口（FlowRegistry 挂在 AppState.services 上）
│       │   └── runner.rs    执行器：每任务一个 Engine + 双 sink + 共享产出表
│       └── frp/             映射隧道（平台登录 + 配置生成 + 隧道运行）
│           ├── mod.rs       模块 + WS 方法（登录会话在 start 里建）
│           ├── run.rs       隧道运行：一条 toml 一个进程（`frp.run.*`）+ 事件
│           ├── model.rs     平台 / 账号 / 节点 / 隧道 / 登录状态
│           ├── store.rs     auth.json + 隧道元数据 + TOML 的读写（0600、原子写）
│           ├── login.rs     登录会话表：发起 → 后台轮询 → 落盘 → 推事件
│           ├── builder.rs   隧道元数据 → frpc 配置文本
│           └── api/         各家平台客户端（与 daemon 其余部分完全隔离）
│               ├── mod.rs   门面 + 宽松解析工具 + 统一错误
│               ├── msl.rs      · openfrp.rs  · sakura.rs
│               ├── chml.rs     · mefrp.rs
└── server/
    ├── mod.rs               bind / serve / run + 优雅关闭
    ├── http.rs              路由组装、鉴权中间件、CORS、api_result
    └── ws/
        ├── mod.rs           WS 升级处理 + 协议速查
        ├── protocol.rs      信封定义与编解码
        └── session.rs       连接生命周期、分发、订阅、心跳
```

---

## 测试

```bash
cargo test                 # 单元 + 集成
cargo clippy --all-targets # 无告警
```

> 下载队列里有两条「真下一遍」的用例（起一台只服务一个文件的本地 HTTP 服务，
> 把文件下进实例目录再核对字节）。它们需要**直连回环**：机器上若配了
> `HTTP_PROXY` 又没把 `127.0.0.1` 放进 `NO_PROXY`，用例会**跳过并打印原因**
> —— gosh-dl 的 reqwest 客户端会读环境代理，daemon 这边改不了它。
> 想真跑就给命令带上 `NO_PROXY=127.0.0.1,localhost,::1`。

- `src/**` 内的单元测试：配置合并、主题匹配、连接表、注册表分发、模块生命周期、
  实例模块的存储层（原子写、并发写、路径校验、索引降级、目录统计）与业务操作
  （增删查改、重名、keep_files、扫描 prune/adopt），
  **文件系统层**（路径越界、排序、搜索范围、复制的 ` (n)` 规则、
  zip 往返与 zip-slip 拒绝、上传上限），监控模块的采样语义
  （间隔 clamp、第一次采样没有 CPU 读数、快照读缓存、只采不推、生命周期），
  以及**进程管理**（真起进程：输出进历史、退出码与崩溃的区分、
  停止命令与 `^C`、强杀、`Done (` 就绪判定、兼容模式、事件推送、
  环形历史裁剪、错误码），以及**映射隧道的模型与存储**（`token` 文件 0600、
  元数据 camelCase、简易表单 → TOML、配置构建的
  ini / TOML 两条分支、隧道增删存的校验与路径注入防护），
  以及**下载队列**（URL 取名与「不解码」的取舍、文件名的单段与字节上限、
  校验值的长度与字符集、三种校验值同时给多个必须报错、配置 clamp、
  模块只注册三个方法、路径逃逸 / 实例不存在 / 目标已存在 / 同一路径已有任务
  这几种拒绝，sha1 的三段状态机（`verifying` → `completed` / `error` 覆盖），
  以及**真起一个本地 HTTP 服务把文件下进实例目录**、核对字节与状态，
  还真的验一遍 sha1：匹配就留文件、不匹配就删文件并报 `checksum_mismatch`），
  以及**服务端目录**（拿各上游**真实响应体**钉住每个源的解析：原版清单只用 release、
  paper 分组摊平与滤预发布、folia 复用 paper 解析（产物键与校验都在）、
  purpur 升序要自己降序且 md5 能读到、
  leaf 的乱序列表与「取最大构建号」、leaf 与 leaves 的字段名不同、
  fabric 只要 stable 与加载器嵌套结构、bungeecord 用构建号而非浮动短链；
  外加版本号数值比较、版本号白名单挡住路径字符、缓存的 TTL 与「0 = 不缓存」、
  类型表自洽（分类引用存在、每个类型只属一个分类、校验算法取值合法）），
  以及**模组与插件**（拿 Modrinth **真实响应体**钉住每个解析：搜索命中的关注数是
  `follows` 而项目详情是 `followers`（取错就恒为 0）、加载器要从 `categories`
  混装字段里挑、`facets` 是「内层 OR 外层 AND」、sha1 统一小写、
  版本反查对不认识的哈希是**不给键**而不是给 null；
  元数据解析覆盖 fabric / quilt / forge / neoforge / velocity / plugin.yml 六种，
  含 `plugin.yml` 只看顶层不误读缩进的子项、引号与行尾注释、`${file.jarVersion}`
  占位符当作没给、坏字节不 panic；以及配置模板节能反序列化、多写字段必须报错、
  「游戏版本清单只留正式版并按日期排序而不是信上游顺序」、加载器与项目类型的组合
  校验、工作流参数校验与「声明清单与构造出的步骤一一对应」、sha1 对已知向量），
  以及**运行环境**（Azul 列表与详情的解析拿**真实响应体**钉住：glibc 收窄、
  按 Java 版本号收敛同一大版本的多条候选、详情核对平台与必须有 sha256；
  解压用本地造的 tar.gz / zip 验「权限位留下来」「macOS 三层布局找得到 java」
  「没有 bin/java 就判失败」；安装整条用本地 HTTP 源测到底 ——
  装好 / 校验不过 / **重试跳过下载直接解压**；重启收拾与 id 白名单；
  端到端再走一遍 WS：目录、空列表、非法 id、上游不可达时按跳过处理），
  以及**配置文件查找与自动释放**（首次运行释放并加载、
  已有配置绝不动、cwd 优先、显式路径不存在必报错、释放失败退回内置默认值、
  相对路径不写）。
- `tests/cli.rs` 针对真实二进制：临时目录里跑 `--print-config` / `--check`，
  验证「没有配置文件时自动释放并加载」走的是 `main()` 那条真实路径，
  释放出来的模板能被模块解析；`-c` 指了不存在的路径照样报错。
- `tests/framework.rs` 端到端：每例都真起一个服务（绑 `127.0.0.1:0`），
  真开 TCP 打 HTTP、真开 WebSocket 走完整协议，覆盖鉴权、路由挂载、
  并发调用配对、订阅推送、协议级错误、优雅关闭、模块禁用、
  **多连接隔离**（应答只回发起方、同 id 不串台、事件只给订阅者），
  **实例模块的 WS/HTTP 全流程**（含路径穿越被拒、扫描报告），
  **文件管理的 WS 与 HTTP 全流程**（建/读写/搜索/改名/复制/移动/压缩/解压/删除、
  越界与重名冲突的错误码、上传落地与重名策略、下载字节一致性与目录打 zip、
  下载后的临时文件清理），
  **监控模块的 WS/HTTP 全流程**（快照字段、`monitor.stats` 推送、
  跑够两个采样间隔后 `cpu_usage` 出现读数），以及
  **进程与控制台的全流程**（起真进程、阶段流转、`^C` 停止、
  `/pty/{id}` 的历史快照 / 输入回显 / `exit` 控制帧 / 鉴权与 404），以及
  **下载队列与服务端目录的全流程**：真起一台本地 HTTP 服务把文件下进实例目录并核对
  字节、`download.progress` 与 `download.state` 事件真的从服务端推出来（含
  「进行中且带得动画百分比的总大小」那一帧）、类型表 / 版本列表 / 下载计划、
  版本白名单与缺参数各自的错误码、Fabric 的「先选 MC 版本再选加载器」两步。
  以及**模组与插件的全流程**：类型表与「装到哪个目录」的唯一出处、往实例目录里写
  **真 zip** 之后能读出 jar 内的名字与版本、`.txt` 不会被当成模组、
  `.disabled` 的拆名与幂等启停、重名与缺文件各自的错误码、文件名带分隔符被拒、
  工作流清单与提交时缺参数、**另一条连接改动后订阅方能收到 `mods.changed`**。
  其中需要上游网络的那几段，**上游不通时会跳过并打印原因**，而不是报成功能坏了。
  每例的实例数据目录都是独立的临时目录，不会碰你的真实数据目录。

---

## 设计取舍

- **为什么不用 clap**：参数只有十来个，手写解析能少一个重量级依赖，
  也让「命令行覆盖配置」这条路径一眼看得懂。
- **进程为什么用 `portable-pty` 而不是 `std::process`**：服务端大多按「是不是
  终端」决定要不要开控制台 —— 管道会让 Minecraft 的 JLine 退化成非交互模式、
  PocketMine 也不出交互提示。另外 PTY 才能让「停止命令」真的像在控制台里敲
  一行，`^C` 也才能变成 SIGINT。方案与内存布局照 `pty-terminal-demo`。
- **为什么控制台另开一个 `/pty/{id}` 端点**：终端输出是几十 KB/s 的二进制流，
  混进 JSON-RPC 那条连接既要 base64（+33% 流量）又会和调用应答抢队头。
  分成一条专门的流以后，主连接的协议不用为二进制开例外。
- **监控为什么引入 `sysinfo`**：内存与 CPU 的跨平台读取（Linux `/proc`、
  Windows `GlobalMemoryStatusEx`/`GetSystemTimes`、macOS `host_statistics`）
  自己写要维护三套平台代码 + 一堆不安全的 FFI，而 `sysinfo` 正是为这件事存在的。
  这是**唯一**一个非框架依赖，且只开了 `system` 一个 feature
  （不需要 disk / network / component / user）。
- **为什么模块注册是同步的**：所有扩展点在**开始监听之前**收集完毕，
  任何冲突（路径重复、方法重名、模块 id 重复）都在启动期失败，
  不会出现「跑起来了但一半功能没注册」。
- **为什么出站只有一条 mpsc**：WS 的 sink 由唯一 writer 任务独占，
  应答、推送、心跳、告别帧不会交叉写坏帧。
- **为什么超时层只包 `/api/*`**：长连接和长轮询会被全局超时误杀，
  模块要限耗时请自己 `tokio::time::timeout`。
