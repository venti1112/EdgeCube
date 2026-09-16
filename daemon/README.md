# EdgeCube-Daemon

EdgeCube 的后端守护进程。**目前只有框架**，不含任何业务逻辑。

一句话概括：一个 HTTP + WebSocket 服务，功能全部以「可插拔模块」的形式挂上去。

- 单个端口同时提供 HTTP 与 WebSocket；一条 WS 长连接上既做类 HTTP 的一问一答，
  也做服务端主动推送。
- 配置四层合并（默认值 → 配置文件 → 环境变量 → 命令行），带注释的模板可一键生成。
- 加功能 = 写一个模块 + 在清单里加一行；卸功能 = 删掉那一行。

---

## 快速开始

```bash
cd daemon
cargo build --release

# 生成一份带注释的配置到 $XDG_CONFIG_HOME/edgecube/daemon.toml
./target/release/edgecube-daemon --init-config

# 只校验配置与模块，不监听端口
./target/release/edgecube-daemon --check

# 启动
./target/release/edgecube-daemon
```

验证：

```bash
curl http://127.0.0.1:8787/healthz
curl http://127.0.0.1:8787/api/info          # 配了 token 时需要 ?token=...
curl http://127.0.0.1:8787/api/methods       # 当前注册了哪些 WS 方法
```

命令行参数：

| 参数 | 说明 |
| --- | --- |
| `-c, --config <PATH>` | 指定配置文件 |
| `--init-config` | 生成带注释的默认配置后退出（已存在则不覆盖） |
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

查找顺序：`-c` 指定 → `./edgecube.toml` → `$XDG_CONFIG_HOME/edgecube/daemon.toml`
→ 都没有就用默认值启动（会打一条警告）。

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

## 实例管理模块（`instance`）

第一个真正的业务模块：管**磁盘上的实例**（元数据、目录、体积），**不管进程** ——
启动/停止服务端进程属于进程管理模块，见下面「`instance.status` 的语义」。

### 存储布局（照搬 V1 的三分离）

```text
<data_dir>/
├── config/
│   ├── instances.json          # 索引：{ selected, instances: [{id,name,path?}] }
│   └── instances/<id>.json     # 单个实例的完整元数据
└── instances/<id>/             # 实例工作目录（服务端文件、世界存档……）
```

- **列表只读索引**（`{id,name}` 摘要），不必把每个实例的启动配置都读进来 ——
  实例多起来这是数量级差别。
- 元数据的 JSON key 与 V1 的 `Instance` 模型**逐字一致**，并且能读 V1 的历史 key
  （`javaVersion` / `selectedJar`）→ 两边的实例数据可以直接互相搬。
- **命名分两套，别混**：**落盘**用 V1 的 camelCase（`maxMemory`、`runtimeEnvId`），
  **线上**（WS / HTTP 响应）统一 snake_case（`max_memory`、`runtime_env_id`）——
  文件格式对齐 V1，协议格式对齐 daemon 自己，前端只需要记一套命名。
  实现上就是 `InstanceConfig::to_wire_value()`（线上）与 `serde_json::to_string`
  （落盘）两条路，测试里两边都钉住了。
- 写文件一律「先写**唯一命名**的临时文件再 rename」：中途崩溃不会留下半个 JSON；
  临时名带 pid + 序号，两个写入者并发也不会互相把对方的临时文件 rename 走。
- 「读索引 → 改 → 写索引」在模块内用互斥锁串行化，避免并发新建/删除互相覆盖。

### 方法

| 方法 | 参数 | 说明 |
| --- | --- | --- |
| `instance.list` | `with_status?` | 列表；`with_status=true` 时每个实例附带状态 |
| `instance.get` | `id` | 完整元数据 + 目录 + lint |
| `instance.create` | `name`，可选 `runtime` / `maxMemory` / `runtimeEnvId` / `serverFile` / `path` … | 新建（id 由服务端生成，16 位 hex） |
| `instance.delete` | `id`，`keep_files?` | 删除；`keep_files=true` 只摘出列表，目录留在磁盘上 |
| `instance.status` | `id?` | 给 id 看一个，不给看全部 |
| `instance.select` | `id?` | 设置「当前选中」（索引里的 `selected`） |
| `instance.scan` | — | 重新扫描磁盘：清理缺失 + 接管外部新建的目录 |

HTTP 侧同一套能力：`GET/POST /api/instances`、`GET/DELETE /api/instances/{id}`
（`?keep_files=true`）、`POST /api/instances/{id}/select`。

事件：`instance.created` / `instance.deleted` / `instance.updated` ——
另一个前端连着的时候，列表能靠它们自己更新。

### `instance.status` 的语义

它报的是**磁盘视角**：目录在不在、多大、多少文件、元数据自不自洽。

```json
{
  "phase": "stopped",          // 生命周期阶段，见下
  "running": false,
  "process_managed": false,    // ← 进程管理还没接进来，phase 不会动
  "dir": "/srv/edgecube/instances/1a2b3c4d5e6f7788",
  "dir_exists": true,
  "size_bytes": 1536, "size_human": "1.5 KiB",
  "file_count": 2, "dir_count": 1, "size_truncated": false,
  "created_at_ms": 1789000000000, "updated_at_ms": 1789000000000,
  "warnings": ["元数据里的入口文件 `server.jar` 不在实例目录中"]
}
```

- `phase` 的取值与 V1 的 `ServerStatus` 对齐（`stopped` / `preparing` / `starting` /
  `running` / `stopping`），只多一个 **`crashed`** —— 进程异常退出必须和
  「用户主动停止」区分开，否则前端只能把崩溃显示成正常停止。
  进程模块接进来之前它恒为 `stopped`，并且 `process_managed = false` 明说这件事。
- **`warnings` 是这里最实用的部分**：目录丢了、入口文件不在、运行环境/换行符
  不合法……都会在这里说出来，前端直接挂到实例卡片上即可。

### 几条安全约束（都是必须的）

- **id 是安全边界**：只允许 `[0-9A-Za-z_-]`、长度 ≤64。id 会被直接拼进文件路径，
  放行 `..` 或 `/` 就等于把 `instance.delete` 变成任意目录删除。
- **删除前重新校验目录**：实例允许把工作目录放在数据根之外（proot rootfs 场景），
  所以删除时会再查一遍 —— 必须是绝对路径、不含 `..`、层级 ≥3
  （挡住 `/`、`/etc`、`/tmp`）。元数据被人手工改坏也拦得住。
- **扫描失败绝不动索引**：数据根读不了（存储没挂载、权限不足）时整体跳过，
  而不是把索引当空的清掉。
- 目录体积统计有条目数与深度上限，触顶时 `size_truncated = true`，数值只是下界。

### 与 V1 的差异

| | V1 | daemon |
| --- | --- | --- |
| 数据根 | `<storage>/EdgeCube` | `$EDGECUBE_DATA_DIR` → XDG 数据目录，可配置 |
| 删除 | 直接递归删 | 同上；另外提供 `keep_files=true` 只摘出列表 |
| 路径校验 | 无（本地 App） | id 白名单 + 目录层级校验（网络服务必须） |
| 新增字段 | — | `createdAtMs` / `updatedAtMs`（V1 读到会忽略） |

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
├── state.rs                 AppState：配置快照、总线、注册表、连接表、取消令牌
├── module/
│   ├── mod.rs               Module trait、Registration、CallCtx
│   ├── registry.rs          ModuleRegistry + builtin_modules()（插拔点）
│   └── builtin/
│       ├── core.rs          框架自省模块（always_on）
│       ├── ticker.rs        示例模块模板
│       └── instance/        实例管理（真正的业务模块）
│           ├── mod.rs       模块 + WS 方法 + HTTP 路由
│           ├── model.rs     实例元数据 / 摘要 / 状态 / 生命周期阶段
│           └── store.rs     存储层：索引、原子写、目录统计、路径校验
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

- `src/**` 内的单元测试：配置合并、主题匹配、连接表、注册表分发、模块生命周期、
  以及实例模块的存储层（原子写、并发写、路径校验、索引降级、目录统计）
  与业务操作（增删查改、重名、keep_files、扫描 prune/adopt）。
- `tests/framework.rs` 端到端：每例都真起一个服务（绑 `127.0.0.1:0`），
  真开 TCP 打 HTTP、真开 WebSocket 走完整协议，覆盖鉴权、路由挂载、
  并发调用配对、订阅推送、协议级错误、优雅关闭、模块禁用、
  **多连接隔离**（应答只回发起方、同 id 不串台、事件只给订阅者），
  以及**实例模块的 WS/HTTP 全流程**（含路径穿越被拒、扫描报告）。
  每例的实例数据目录都是独立的临时目录，不会碰你的真实数据目录。

---

## 设计取舍

- **为什么不用 clap**：参数只有十来个，手写解析能少一个重量级依赖，
  也让「命令行覆盖配置」这条路径一眼看得懂。
- **为什么模块注册是同步的**：所有扩展点在**开始监听之前**收集完毕，
  任何冲突（路径重复、方法重名、模块 id 重复）都在启动期失败，
  不会出现「跑起来了但一半功能没注册」。
- **为什么出站只有一条 mpsc**：WS 的 sink 由唯一 writer 任务独占，
  应答、推送、心跳、告别帧不会交叉写坏帧。
- **为什么超时层只包 `/api/*`**：长连接和长轮询会被全局超时误杀，
  模块要限耗时请自己 `tokio::time::timeout`。
