//! STUN 打洞隧道模块：给实例开一条公网直连通道。
//!
//! # 它是干活的，不是记账的
//!
//! 每个实例在「实例设置」里有自己的 STUN 三件套（开关 / PROXY protocol /
//! 可选目标端口覆盖，见 `InstanceConfig` 的 `stun_*` 字段）。
//! `enabled && running` 的实例各跑一条隧道：
//!
//! ```text
//! nyat-core 打洞（向 STUN 服务器建 TCP 映射并保活）
//!        │ 公网端点 E、本地端口 P
//!        ▼
//! 本机监听 0.0.0.0:P（与探测套接字共用 P，SO_REUSEPORT）
//!        │ 每条入站连接 → 127.0.0.1:<目标端口>（服务端实际端口或覆盖值）
//!        ▼
//! 玩家 ──▶ E ──(NAT)──▶ P ──▶ 服务端
//! ```
//!
//! 与 UPnP 模块同构：**不认识 `instance` 模块**，只监听它推的
//! `instance.phase` / `instance.created` / `instance.updated` /
//! `instance.deleted` 事件来对齐状态（自动重启这类路径也天然覆盖）。
//!
//! # 与 V1 的差异
//!
//! V1 是全局单条隧道（一个 `StunTunnelService` 管全部配置）；V2 拆成
//! 「每实例一条」（开关 / PROXY / 目标端口覆盖进实例元数据），全局只剩
//! 服务器列表、保活间隔、并发上限、日志开关（存 `config/stun/settings.json`）。
//! 状态机、日志文案、转发语义（流量口径、PROXY v2、并发上限）与 V1 逐条对齐。
//!
//! # 方法 / 事件
//!
//! | 方法 | 说明 |
//! | --- | --- |
//! | `stun.status` | 状态总览（全局设置 + 每实例隧道行 + 统计），**不联网** |
//! | `stun.settings.set` | 更新全局设置（只传要改的字段），立即重建隧道 |
//! | `stun.logs` | 隧道日志（环形缓冲，最多 500 行） |
//! | `stun.logs.clear` | 清空隧道日志 |
//!
//! 事件主题 `stun.evt`：与 `stun.status` 同一份快照，任何变化都推。

pub mod mapper;
pub mod proxy;
pub mod settings;
#[cfg(test)]
mod tests;
pub mod tunnel;

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

use async_trait::async_trait;
use serde_json::{Value, json};
use tokio::sync::broadcast;

use self::mapper::{NyatMapper, StunMapper};
use self::settings::{StunSettings, StunStore};
use self::tunnel::{Phase, RunConfig, TaskEnv, Tuning, Tunnel, TunnelConfig};
use super::instance::store::InstanceStore;
use crate::error::{Result, RpcError};
use crate::event::EventBus;
use crate::module::{CallCtx, Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::state::AppState;
use crate::util::now_ms;

/// 事件主题：状态总览变了（设置 / 每实例隧道行 / 统计）。
pub const TOPIC_EVT: &str = "stun.evt";

/// 隧道日志缓冲的行数上限（V1 同款：500 行环形缓冲）。
const LOG_CAPACITY: usize = 500;

// ══════════════════════════════════════════════════════════════════════════
// 日志缓冲
// ══════════════════════════════════════════════════════════════════════════

/// 一行隧道日志（行上带实例归属，界面上不分实例混排）。
#[derive(Debug, Clone)]
struct LogLine {
    time_ms: u64,
    instance_id: Option<String>,
    instance_name: Option<String>,
    text: String,
}

/// 全局环形日志缓冲（所有隧道的日志按时间混在一起）。
pub struct LogBuffer {
    lines: Mutex<VecDeque<LogLine>>,
}

impl LogBuffer {
    fn new() -> Self {
        Self {
            lines: Mutex::new(VecDeque::with_capacity(LOG_CAPACITY)),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, VecDeque<LogLine>> {
        self.lines.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 追加一行；满了挤掉最老的。
    fn add(&self, instance: Option<(&str, &str)>, text: impl Into<String>) {
        let mut lines = self.lock();
        if lines.len() >= LOG_CAPACITY {
            lines.pop_front();
        }
        lines.push_back(LogLine {
            time_ms: now_ms(),
            instance_id: instance.map(|(id, _)| id.to_string()),
            instance_name: instance.map(|(_, name)| name.to_string()),
            text: text.into(),
        });
    }

    /// 快照（旧 → 新，与追加顺序一致）。
    fn snapshot(&self) -> Value {
        let lines = self.lock();
        let rows: Vec<Value> = lines
            .iter()
            .map(|line| {
                json!({
                    "time_ms": line.time_ms,
                    "instance_id": line.instance_id,
                    "instance_name": line.instance_name,
                    "text": line.text,
                })
            })
            .collect();
        json!({ "lines": rows, "count": rows.len() })
    }

    /// 清空；返回清掉的行数。
    fn clear(&self) -> usize {
        let mut lines = self.lock();
        let count = lines.len();
        lines.clear();
        count
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 管理器
// ══════════════════════════════════════════════════════════════════════════

/// 管理器的内部状态（一个快照级的小锁，绝不在持锁时做 IO）。
struct Inner {
    /// 每实例一条隧道（记录只为「开过 STUN 的实例」而存在）。
    tunnels: BTreeMap<String, Arc<Tunnel>>,
    /// **所有**正在运行的实例（不止开着 STUN 的）——「跑着的时候把开关打开」
    /// 那一刻要靠它知道该不该立刻建隧道。
    running: BTreeSet<String>,
}

/// STUN 管理器：全局设置 + 每实例隧道状态机。
///
/// 所有会牵动任务生命周期或落盘的流程（对账、设置保存、关停）都在 `ops`
/// 这把异步锁下串行执行；查询侧只碰小锁与原子量。
pub struct TunnelManager {
    bus: EventBus,
    /// 实例数据根（与 `instance` 模块同一个，见 `data_dir_of`）。
    data_dir: PathBuf,
    store: StunStore,
    mapper: Arc<dyn StunMapper>,
    /// 时序参数（生产用默认值；测试注入小值）。
    tuning: Tuning,
    settings: Mutex<StunSettings>,
    log: Arc<LogBuffer>,
    inner: Mutex<Inner>,
    ops: tokio::sync::Mutex<()>,
    /// 自己的弱引用（任务回推事件用；`remember` 里设置一次）。
    weak_self: OnceLock<Weak<TunnelManager>>,
}

impl TunnelManager {
    pub fn new(bus: EventBus, data_dir: PathBuf, mapper: Arc<dyn StunMapper>) -> Self {
        Self::with_tuning(bus, data_dir, mapper, Tuning::default())
    }

    pub fn with_tuning(
        bus: EventBus,
        data_dir: PathBuf,
        mapper: Arc<dyn StunMapper>,
        tuning: Tuning,
    ) -> Self {
        let store = StunStore::new(data_dir.join("config").join("stun"));
        let settings = store.read_settings();
        Self {
            bus,
            data_dir,
            store,
            mapper,
            tuning,
            settings: Mutex::new(settings),
            log: Arc::new(LogBuffer::new()),
            inner: Mutex::new(Inner {
                tunnels: BTreeMap::new(),
                running: BTreeSet::new(),
            }),
            ops: tokio::sync::Mutex::new(()),
            weak_self: OnceLock::new(),
        }
    }

    /// 记下自己的弱引用（任务回推事件用）。启动时调用一次。
    pub fn remember(self: &Arc<Self>) {
        let _ = self.weak_self.set(Arc::downgrade(self));
    }

    fn weak(&self) -> Weak<TunnelManager> {
        self.weak_self.get().cloned().unwrap_or_else(Weak::new)
    }

    fn lock_inner(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_settings(&self) -> std::sync::MutexGuard<'_, StunSettings> {
        self.settings.lock().unwrap_or_else(|e| e.into_inner())
    }

    // ── 查询 ───────────────────────────────────────────────────────────────

    /// 全局设置快照。
    pub fn settings(&self) -> StunSettings {
        self.lock_settings().clone()
    }

    /// 状态总览（同 `stun.status` 的返回体；顺带带个时间戳给事件用）。
    pub fn status_json(&self) -> Value {
        let settings = self.settings();
        let inner = self.lock_inner();
        let tunnels: Vec<Value> = inner
            .tunnels
            .values()
            .map(|tunnel| tunnel.to_wire(settings.max_connections))
            .collect();
        json!({
            "settings": settings.to_wire(),
            "tunnels": tunnels,
            "count": tunnels.len(),
            "ts": now_ms(),
        })
    }

    /// 日志快照（同 `stun.logs` 的返回体）。
    pub fn logs_json(&self) -> Value {
        self.log.snapshot()
    }

    /// 清空日志；返回清掉的行数。
    pub fn clear_logs(&self) -> Value {
        json!({ "cleared": self.log.clear() })
    }

    /// 推一份快照给所有订阅者。
    fn publish(&self) {
        self.bus
            .publish_from(Some("stun"), TOPIC_EVT, self.status_json());
    }

    /// 每秒采样一次每条隧道的速率（不推事件：界面自己轮询 `stun.status`）。
    pub async fn speed_ticker(self: Arc<Self>) {
        let mut ticker = tokio::time::interval(Duration::from_secs(1));
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            ticker.tick().await;
            let tunnels: Vec<Arc<Tunnel>> = self.lock_inner().tunnels.values().cloned().collect();
            for tunnel in tunnels {
                tunnel.tick_speeds();
            }
        }
    }

    // ── 实例对账 ───────────────────────────────────────────────────────────

    /// 重新对齐某个实例（加锁版，给事件处理用）。
    pub async fn sync(&self, id: &str) {
        let _guard = self.ops.lock().await;
        self.sync_locked(id, false).await;
    }

    /// 重新对齐某个实例：读盘上配置 + 内存里的运行状态，决定起 / 停 / 不动。
    ///
    /// `force_restart` 用于全局设置变更：在跑的隧道停掉重建，拿新参数快照。
    /// 失败终态（多轮探测全挂）**不会**自动重试，除非 `force_restart`。
    ///
    /// 调用方必须已持有 `ops`。
    async fn sync_locked(&self, id: &str, force_restart: bool) {
        let Some(info) = self.load(id) else {
            // 实例没了（被删 / scan 清理掉）：停隧道 + 丢记录
            self.forget_locked(id).await;
            return;
        };

        let running = self.lock_inner().running.contains(id);
        let should_run = info.enabled && running;
        let next_cfg = info.to_config();

        // 行：更新或按需创建（只给「开过」的实例建行）。
        let (tunnel, mut dirty, affects_run) = {
            let mut inner = self.lock_inner();
            match inner.tunnels.get(id) {
                Some(tunnel) => {
                    let previous = tunnel.config();
                    // 转发行为的参数变了才值得重启；只有展示字段（名字）变就不动
                    let affects_run = previous.proxy_protocol != next_cfg.proxy_protocol
                        || previous.display_target != next_cfg.display_target;
                    let running_changed = tunnel.is_running() != running;
                    tunnel.set_running(running);
                    let changed = tunnel.update_config(next_cfg) || running_changed;
                    (tunnel.clone(), changed, affects_run)
                }
                None if info.enabled => {
                    let tunnel = Arc::new(Tunnel::new(id, next_cfg, running));
                    inner.tunnels.insert(id.to_string(), tunnel.clone());
                    (tunnel, true, false)
                }
                // 没开过开关、也没记录：不跟进（记录只为「开过」的实例存在）
                None => return,
            }
        };

        // 一、不该跑：停掉并收拾干净
        if !should_run {
            if tunnel.stop() {
                self.log.add(Some((id, &info.name)), "隧道已停止");
                tracing::info!(instance = id, "STUN 隧道已停止");
                dirty = true;
            }
            if dirty {
                self.publish();
            }
            return;
        }

        // 二、该跑
        let mut has_task = tunnel.has_task();
        if has_task && (force_restart || affects_run) {
            // 参数变了：停掉重建，任务会在启动时拿新快照
            tunnel.stop();
            has_task = false;
        }
        // 失败终态原地躺平，等实例重启 / 配置变更 / 全局设置变更来救
        let failed = tunnel.phase() == Phase::Failed;
        if !has_task && (force_restart || !failed) {
            tunnel.start(self.task_env(&tunnel));
            dirty = true;
        }

        if dirty {
            self.publish();
        }
    }

    /// 从数据根读一个实例的 STUN 相关配置；实例不存在返回 `None`。
    fn load(&self, id: &str) -> Option<InstanceInfo> {
        let store = InstanceStore::new(&self.data_dir);
        let config = store.read_config(id).ok().flatten()?;
        let dir = store.instance_dir(&config);
        let display_target = config
            .stun_target_port
            .unwrap_or_else(|| super::upnp::port::read_port(&dir));
        Some(InstanceInfo {
            name: config.name,
            enabled: config.stun_enabled,
            proxy_protocol: config.stun_proxy_protocol,
            target_override: config.stun_target_port,
            display_target,
        })
    }

    /// 组装一次运行参数快照（任务只读；设置变更 = 重建任务拿新快照）。
    fn task_env(&self, tunnel: &Arc<Tunnel>) -> TaskEnv {
        let settings = self.settings();
        let cfg = tunnel.config();
        TaskEnv {
            manager: self.weak(),
            log: self.log.clone(),
            mapper: self.mapper.clone(),
            run: RunConfig {
                servers: settings.effective_servers(),
                keepalive_http: settings.keepalive_http,
                interval: Duration::from_secs(u64::from(settings.keep_alive_seconds)),
                max_connections: settings.max_connections,
                show_log: settings.show_connection_log,
                proxy_protocol: cfg.proxy_protocol,
                target: cfg.display_target,
            },
            tuning: self.tuning.clone(),
        }
    }

    /// 停隧道 + 丢记录（实例删除、或磁盘上已经不存在时）。
    async fn forget_locked(&self, id: &str) {
        let removed = {
            let mut inner = self.lock_inner();
            let removed = inner.tunnels.remove(id);
            // running 集合同步清掉：这个 id 不会再来了（真回来会重新插）
            inner.running.remove(id);
            removed
        };
        let Some(tunnel) = removed else { return };
        let name = tunnel.config().name;
        if tunnel.stop() {
            self.log.add(Some((id, &name)), "隧道已停止");
        }
        tracing::info!(instance = id, "STUN 隧道记录已移除");
        self.publish();
    }

    /// 全盘对账：以磁盘索引为准（启动播种、事件积压后恢复）。
    ///
    /// 调用方必须已持有 `ops`。
    async fn reconcile_locked(&self) {
        let store = InstanceStore::new(&self.data_dir);
        let index = store.read_index();
        let mut seen = BTreeSet::new();
        for summary in &index.instances {
            seen.insert(summary.id.clone());
            self.sync_locked(&summary.id, false).await;
        }
        // 记录里有、索引里没有的（比如 scan 清理掉的）→ 停隧道丢记录
        let extra: Vec<String> = {
            let inner = self.lock_inner();
            inner
                .tunnels
                .keys()
                .filter(|id| !seen.contains(*id))
                .cloned()
                .collect()
        };
        for id in extra {
            self.forget_locked(&id).await;
        }
    }

    // ── 对外流程 ───────────────────────────────────────────────────────────

    /// 保存全局设置并对齐所有隧道（设置变更 = 在跑的隧道全部重建）。
    pub async fn set_settings(&self, next: StunSettings) -> Result<Value> {
        let next = next.normalized();
        self.store.write_settings(&next)?;
        *self.lock_settings() = next;
        {
            let _guard = self.ops.lock().await;
            let ids: Vec<String> = self.lock_inner().tunnels.keys().cloned().collect();
            for id in ids {
                self.sync_locked(&id, true).await;
            }
        }
        self.publish();
        Ok(self.status_json())
    }

    /// 关闭时停掉**所有**隧道（daemon 退出后探测连接与监听套接字都会散）。
    pub async fn stop_all(&self) {
        let _guard = self.ops.lock().await;
        let tunnels: Vec<Arc<Tunnel>> = self.lock_inner().tunnels.values().cloned().collect();
        for tunnel in tunnels {
            if tunnel.stop() {
                tracing::info!(instance = %tunnel.id, "关闭时停止 STUN 隧道");
            }
        }
    }

    /// 事件监听：跟随实例的启停 / 变更 / 删除。
    pub async fn listen(self: Arc<Self>, mut rx: broadcast::Receiver<Arc<crate::event::Event>>) {
        loop {
            match rx.recv().await {
                Ok(event) => self.handle_event(&event.topic, &event.data).await,
                Err(broadcast::error::RecvError::Lagged(skipped)) => {
                    // 漏了事件（极端情况）：全盘对账一次把状态掰回来
                    tracing::warn!(skipped, "STUN 事件监听落后，重新对账");
                    let _guard = self.ops.lock().await;
                    self.reconcile_locked().await;
                }
                Err(broadcast::error::RecvError::Closed) => return,
            }
        }
    }

    /// 处理一条总线事件（主题与 `instance` 模块的声明对齐）。
    pub async fn handle_event(&self, topic: &str, data: &Value) {
        match topic {
            super::instance::process::TOPIC_PHASE => {
                let Some(id) = data["id"].as_str() else {
                    return;
                };
                let phase = data["phase"].as_str().unwrap_or_default();
                let running = matches!(phase, "starting" | "running");
                let stopped = matches!(phase, "stopped" | "crashed");
                if !running && !stopped {
                    // preparing / stopping 是过渡态，等落定再说
                    return;
                }
                {
                    let mut inner = self.lock_inner();
                    if running {
                        inner.running.insert(id.to_string());
                    } else {
                        inner.running.remove(id);
                    }
                }
                self.sync(id).await;
            }
            super::instance::TOPIC_CREATED | super::instance::TOPIC_UPDATED => {
                match data["id"].as_str() {
                    Some(id) => self.sync(id).await,
                    // scan 之类的整表刷新没有 id：全盘对账
                    None => {
                        let _guard = self.ops.lock().await;
                        self.reconcile_locked().await;
                    }
                }
            }
            super::instance::TOPIC_DELETED => {
                let Some(id) = data["id"].as_str() else {
                    return;
                };
                let _guard = self.ops.lock().await;
                self.forget_locked(id).await;
            }
            _ => {}
        }
    }
}

/// 磁盘上读到的实例信息（`sync` 的输入）。
struct InstanceInfo {
    name: String,
    enabled: bool,
    proxy_protocol: bool,
    target_override: Option<u16>,
    display_target: u16,
}

impl InstanceInfo {
    fn to_config(&self) -> TunnelConfig {
        TunnelConfig {
            name: self.name.clone(),
            enabled: self.enabled,
            proxy_protocol: self.proxy_protocol,
            target_override: self.target_override,
            display_target: self.display_target,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 模块本体
// ══════════════════════════════════════════════════════════════════════════

/// STUN 的数据根：读的实例目录与 `instance` 模块同一个根，
/// 自己的设置存 `<data_dir>/config/stun/settings.json`。
fn data_dir_of(app: &AppState) -> PathBuf {
    super::instance::resolve_data_dir(app.config.modules.section("instance"))
}

struct StunState {
    manager: OnceLock<Arc<TunnelManager>>,
    listener: Mutex<Option<tokio::task::JoinHandle<()>>>,
    ticker: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl StunState {
    fn new() -> Self {
        Self {
            manager: OnceLock::new(),
            listener: Mutex::new(None),
            ticker: Mutex::new(None),
        }
    }

    /// 取管理器；还没经 `start()` 初始化就现建一个（方法直接可达时兜底）。
    fn manager_of(&self, app: &AppState) -> Arc<TunnelManager> {
        if let Some(manager) = self.manager.get() {
            return manager.clone();
        }
        let manager = Arc::new(TunnelManager::new(
            app.bus.clone(),
            data_dir_of(app),
            Arc::new(NyatMapper),
        ));
        manager.remember();
        let _ = self.manager.set(manager);
        self.manager.get().cloned().expect("刚刚设置过")
    }
}

pub struct StunModule {
    state: Arc<StunState>,
}

impl StunModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(StunState::new()),
        }
    }
}

impl Default for StunModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for StunModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("stun", "STUN 隧道", env!("CARGO_PKG_VERSION")).description(
            "STUN 打洞隧道：按实例配置（开关 / PROXY protocol / 目标端口覆盖）在实例启动时\
             建立公网直连隧道（nyat-core 打洞 + 本地监听转发 + 保活重建），停止时拆除；\
             全局调参与每实例隧道行经 stun.status / stun.evt 暴露给客户端。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(
            TOPIC_EVT,
            "STUN 状态总览变了（全局设置 / 隧道行增删 / 相位与统计变化）",
        );

        {
            let state = self.state.clone();
            reg.method(
                "stun.status",
                "STUN 状态总览（全局设置 + 每实例隧道行，不联网）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { ok(state.manager_of(&ctx.app).status_json()) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "stun.settings.set",
                "更新 STUN 全局设置（只传要改的字段），并立即按新参数重建隧道",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move {
                        let manager = state.manager_of(&ctx.app);
                        let mut next = manager.settings();
                        if let Some(servers) = ctx.optional::<Vec<String>>("servers")? {
                            next.servers = servers;
                        }
                        if let Some(value) = ctx.optional::<u32>("keep_alive_seconds")? {
                            next.keep_alive_seconds = value;
                        }
                        if let Some(value) = ctx.optional::<u32>("max_connections")? {
                            next.max_connections = value;
                        }
                        if let Some(value) = ctx.optional::<String>("keepalive_http")? {
                            next.keepalive_http = value;
                        }
                        if let Some(value) = ctx.optional::<bool>("show_connection_log")? {
                            next.show_connection_log = value;
                        }
                        manager
                            .set_settings(next)
                            .await
                            .map_err(|e| RpcError::internal(format!("写 STUN 设置失败：{e}")))
                    }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "stun.logs",
                "隧道日志（环形缓冲，最多 500 行）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { ok(state.manager_of(&ctx.app).logs_json()) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "stun.logs.clear",
                "清空隧道日志",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { ok(state.manager_of(&ctx.app).clear_logs()) }
                },
            );
        }
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let app = env.app.clone();
        let manager = Arc::new(TunnelManager::new(
            app.bus.clone(),
            data_dir_of(&app),
            Arc::new(NyatMapper),
        ));
        manager.remember();
        let _ = self.state.manager.set(manager.clone());

        // 先挂监听器（在服务监听之前）：之后所有实例事件都能收到
        let listener = tokio::spawn(manager.clone().listen(app.bus.subscribe()));
        *self
            .state
            .listener
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(listener);
        let ticker = tokio::spawn(manager.clone().speed_ticker());
        *self.state.ticker.lock().unwrap_or_else(|e| e.into_inner()) = Some(ticker);

        // 播种：磁盘上开着 STUN 的实例先摆进行里（daemon 刚起来，都没在跑）。
        // 顺便对账一遍，把「记录里有、磁盘上没了」的旧账清掉。
        {
            let _guard = manager.ops.lock().await;
            manager.reconcile_locked().await;
        }
        tracing::info!(
            data_dir = %manager.data_dir.display(),
            tracked = manager.lock_inner().tunnels.len(),
            "stun 模块已加载"
        );
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        // 先停监听：关闭流程里实例退出的事件不需要再被处理
        let listener = self
            .state
            .listener
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(handle) = listener {
            handle.abort();
        }
        let ticker = self
            .state
            .ticker
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(handle) = ticker {
            handle.abort();
        }
        if let Some(manager) = self.state.manager.get() {
            manager.stop_all().await;
        }
        Ok(())
    }
}
