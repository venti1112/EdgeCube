//! UPnP 路由器端口映射模块。
//!
//! # 它是干活的，不是记账的
//!
//! 每个实例在「实例设置」里有自己的 UPnP 三件套（开关 / 协议 / 外部端口，
//! 见 `InstanceConfig` 的 `upnp_*` 字段）。模块负责把它们变成路由器上真实的
//! 端口映射：实例起 → 加映射；实例停 → 撤映射；配置改了 → 重新对齐。
//!
//! # 怎么知道实例动了？—— 听事件，而不是被挂钩子
//!
//! `instance` 模块**不认识** upnp：它只是照常把 `instance.created` /
//! `instance.updated` / `instance.deleted` / `instance.phase` 推到事件总线上
//! （前端也是这些事件的消费者）。本模块在启动时挂一个监听器跟着对齐状态。
//!
//! 好处是**自动重启这类绕过 `instance.start()` 的路径也天然覆盖**：
//! 进程退出（`stopped`/`crashed`）与自动拉起（`starting`）都会推阶段事件，
//! 监听器一视同仁地撤映射、再映射 —— 不用在进程管理的边角里各埋一个钩子。
//!
//! # 每个实例一个状态机
//!
//! 一条记录（`Mapping`）由三样东西决定：
//!
//! * `enabled` —— 实例配置里 UPnP 开着吗；
//! * `running` —— 实例在跑吗（阶段事件维护；daemon 刚启动时一律不在跑）；
//! * `applied` —— 路由器上现在有没有我们加的那条映射（实际五元组）。
//!
//! `enabled && running` 时才该有映射；不满足但有 `applied` 就撤掉。内部端口
//! 不进配置（它是服务端自己的 `server-port` 等，见 [`port`]），每次同步时
//! 从实例目录现读；但如果映射已经在位，就**认在位的那条**——服务端还听着
//! 老端口，改文件是给下次启动准备的，现在重映射反而会把在线的人踢下来。
//!
//! # 方法 / 事件
//!
//! | 方法 | 说明 |
//! | --- | --- |
//! | `upnp.status` | 状态总览（网关 + 每实例行），**只读缓存不联网** |
//! | `upnp.probe` | 重新发现网关 + 重试失败的映射，返回最新总览 |
//!
//! 事件主题 `upnp.evt`：上面两个方法返回的同一份快照，任何变化都推。
//!
//! # 与 V1 的差异
//!
//! V1 是单实例的（一个 `UpnpService` 一套全局状态）。V2 把「网关」和
//! 「每一组映射」拆开：网关一份（发现一次给所有实例用），映射按实例各记各的。
//! 协议、外部端口、永久租约、CGNAT 判断、端口读取优先级都与 V1 对齐。

pub mod port;
pub mod transport;

use std::collections::{BTreeMap, BTreeSet};
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use async_trait::async_trait;
use serde_json::{Value, json};
use tokio::sync::broadcast;

use self::transport::{AddPortFailure, GatewayOps, IgdTransport, Protocol, UpnpTransport};
use super::instance::store::InstanceStore;
use crate::error::Result;
use crate::event::EventBus;
use crate::module::{CallCtx, Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::state::AppState;
use crate::util::now_ms;

/// 事件主题：状态总览变了（新实例行、映射成功/失败、网关状态变化……）。
pub const TOPIC_EVT: &str = "upnp.evt";

/// 发现失败后的重试冷却：映射请求可能成串来（一批实例同时起），
/// 别让每次都去广播一轮 SSDP。用户点「重新探测」（`upnp.probe`）不受它限制。
const DISCOVER_RETRY_COOLDOWN_MS: u64 = 5_000;

/// 网关在某一刻的状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
enum GatewayPhase {
    /// 还没探测过。
    #[default]
    Unknown,
    /// 正在发现（SSDP 广播中）。
    Searching,
    /// 可用。
    Ready,
    /// 上次发现失败（原因在 `error`）。
    Error,
}

impl GatewayPhase {
    fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Searching => "searching",
            Self::Ready => "ready",
            Self::Error => "error",
        }
    }
}

/// 一条实例映射记录的状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MapPhase {
    /// 不在位、也不该在位（实例没跑 / 开关关着）。
    Idle,
    /// 正在往路由器上加。
    Mapping,
    /// 已映射。
    Mapped,
    /// 上次映射失败（原因在 `error`）。
    Failed,
}

impl MapPhase {
    fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Mapping => "mapping",
            Self::Mapped => "mapped",
            Self::Failed => "failed",
        }
    }
}

/// 路由器上实际生效的那条映射。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Applied {
    protocol: Protocol,
    external_port: u16,
    internal_port: u16,
}

/// 网关的共享状态。
#[derive(Default)]
struct GatewayInfo {
    phase: GatewayPhase,
    /// 发现成功后缓存的句柄（加/撤映射不再重新发现）。
    ops: Option<Arc<dyn GatewayOps>>,
    /// 网关自己的地址（展示用）。
    address: Option<SocketAddr>,
    /// 本机在网关那一侧的内网地址。
    local_ip: Option<IpAddr>,
    /// 网关看到的公网地址（拿不到就是 `None`）。
    external_ip: Option<IpAddr>,
    error: Option<String>,
    /// 最近一次探测（不管成败）的时间。
    probed_at_ms: Option<u64>,
}

impl GatewayInfo {
    /// 公网地址落在私网 / 运营商级 NAT 段 = 大概率是 CGNAT（V1 同款判断）。
    fn cgnat(&self) -> bool {
        self.external_ip.is_some_and(is_private_ip)
    }

    fn to_wire(&self) -> Value {
        json!({
            "state": self.phase.as_str(),
            "external_ip": self.external_ip.map(|ip| ip.to_string()),
            "cgnat": self.cgnat(),
            "address": self.address.map(|addr| addr.to_string()),
            "error": self.error,
            "probed_at_ms": self.probed_at_ms,
        })
    }
}

/// 一个实例的映射记录。
#[derive(Debug, Clone, PartialEq)]
struct Mapping {
    instance_id: String,
    instance_name: String,
    /// 配置里开着 UPnP 吗（关闭后记录保留，显示为 `enabled=false, idle`）。
    enabled: bool,
    /// 配置里选的协议。
    protocol: Protocol,
    /// 配置里的外部端口；`None` = 与内部端口相同。
    external_port: Option<u16>,
    /// 最近一次读到（或用的）内部端口，展示用。
    internal_port: Option<u16>,
    /// 实例在跑吗。
    running: bool,
    phase: MapPhase,
    applied: Option<Applied>,
    error: Option<String>,
}

impl Mapping {
    fn new(
        id: &str,
        name: &str,
        protocol: Protocol,
        external_port: Option<u16>,
        running: bool,
    ) -> Self {
        Self {
            instance_id: id.to_string(),
            instance_name: name.to_string(),
            enabled: true,
            protocol,
            external_port,
            internal_port: None,
            running,
            phase: MapPhase::Idle,
            applied: None,
            error: None,
        }
    }

    /// 映射的「有效外部端口」：配置里没写就跟着内部端口走。
    fn effective_external(&self, internal: u16) -> u16 {
        self.external_port.unwrap_or(internal)
    }

    fn to_wire(&self, gateway: &GatewayInfo) -> Value {
        let internal = self.internal_port;
        let external = internal.map(|port| self.effective_external(port));
        // 公网地址 = 网关公网 IP + 在位的那个外部端口（只在实际映射上时才给）
        let public_address = match (self.phase, self.applied, gateway.external_ip) {
            (MapPhase::Mapped, Some(applied), Some(ip)) => {
                Some(SocketAddr::new(ip, applied.external_port).to_string())
            }
            _ => None,
        };
        json!({
            "instance_id": self.instance_id,
            "instance_name": self.instance_name,
            "enabled": self.enabled,
            "running": self.running,
            "state": self.phase.as_str(),
            "protocol": self.protocol.as_str(),
            "internal_port": internal,
            "external_port": external,
            "public_address": public_address,
            "error": self.error,
        })
    }
}

/// 管理器的内部状态（锁的粒度：一个快照级的小锁，绝不在持锁时做 IO）。
struct Inner {
    gateway: GatewayInfo,
    /// **所有**正在运行的实例（不止开着 UPnP 的）——「运行中把开关打开」
    /// 那一刻要靠它知道该不该立刻映射：那个实例此前的阶段事件没留下记录。
    running: BTreeSet<String>,
    mappings: BTreeMap<String, Mapping>,
}

/// 缓存好、可以用的网关。
struct ReadyGateway {
    ops: Arc<dyn GatewayOps>,
    local_ip: IpAddr,
}

/// UPnP 管理器：网关缓存 + 每实例映射状态机。
///
/// 所有会对路由器产生动作的流程（发现、加、撤）都在 `ops` 这把异步锁下
/// 串行执行 —— 路由器是共享资源，并发发指令只会互相打架。
pub struct UpnpManager {
    bus: EventBus,
    /// 实例数据根（与 instance 模块同一个，见 `data_dir_of`）。
    data_dir: PathBuf,
    transport: Arc<dyn UpnpTransport>,
    inner: Mutex<Inner>,
    ops: tokio::sync::Mutex<()>,
}

impl UpnpManager {
    pub fn new(bus: EventBus, data_dir: PathBuf, transport: Arc<dyn UpnpTransport>) -> Self {
        Self {
            bus,
            data_dir,
            transport,
            inner: Mutex::new(Inner {
                gateway: GatewayInfo::default(),
                running: BTreeSet::new(),
                mappings: BTreeMap::new(),
            }),
            ops: tokio::sync::Mutex::new(()),
        }
    }

    fn lock_inner(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    // ── 查询 ───────────────────────────────────────────────────────────────

    /// 状态总览（同 `upnp.status` 的返回体；顺带带个时间戳给事件用）。
    pub fn status_json(&self) -> Value {
        let inner = self.lock_inner();
        let gateway = inner.gateway.to_wire();
        let mappings: Vec<Value> = inner
            .mappings
            .values()
            .map(|m| m.to_wire(&inner.gateway))
            .collect();
        json!({
            "gateway": gateway,
            "mappings": mappings,
            "count": mappings.len(),
            "ts": now_ms(),
        })
    }

    fn has_enabled(&self) -> bool {
        self.lock_inner().mappings.values().any(|m| m.enabled)
    }

    fn gateway_ops(&self) -> Option<Arc<dyn GatewayOps>> {
        self.lock_inner().gateway.ops.clone()
    }

    fn gateway_error(&self) -> Option<String> {
        self.lock_inner().gateway.error.clone()
    }

    fn record(&self, id: &str) -> Option<Mapping> {
        self.lock_inner().mappings.get(id).cloned()
    }

    /// 改一条记录；返回是否真的变了（用来决定要不要推事件）。
    fn update(&self, id: &str, f: impl FnOnce(&mut Mapping)) -> bool {
        let mut inner = self.lock_inner();
        let Some(m) = inner.mappings.get_mut(id) else {
            return false;
        };
        let before = m.clone();
        f(m);
        *m != before
    }

    /// 推一份快照给所有订阅者。
    fn publish(&self) {
        self.bus
            .publish_from(Some("upnp"), TOPIC_EVT, self.status_json());
    }

    // ── 实例对账 ───────────────────────────────────────────────────────────

    /// 重新对齐某个实例（加锁版，给外部入口用）。
    pub async fn sync(&self, id: &str) {
        let _guard = self.ops.lock().await;
        self.sync_locked(id).await;
    }

    /// 重新对齐某个实例：读盘上配置 + 内存里的运行状态，决定加 / 撤 / 不动。
    ///
    /// 调用方必须已持有 `ops`。
    async fn sync_locked(&self, id: &str) {
        let Some(info) = self.load(id) else {
            // 实例没了（被删 / scan 清理掉）：撤映射 + 丢记录
            self.forget_locked(id).await;
            return;
        };

        let mut changed = {
            let mut inner = self.lock_inner();
            let running = inner.running.contains(id);
            match inner.mappings.get_mut(id) {
                Some(m) => {
                    let before = m.clone();
                    m.instance_name = info.name.clone();
                    m.enabled = info.enabled;
                    m.protocol = info.protocol;
                    m.external_port = info.external_port;
                    m.running = running;
                    *m != before
                }
                None if info.enabled => {
                    let record =
                        Mapping::new(id, &info.name, info.protocol, info.external_port, running);
                    inner.mappings.insert(id.to_string(), record);
                    true
                }
                // 没开过开关、也没记录：不跟进（记录只为「开过」的实例存在）
                None => return,
            }
        };

        let disk_port = port::read_port(&info.dir);
        let record = self.record(id).expect("刚确认过存在");

        // 映射在位时内部端口认在位的那个（服务端还听着它）；否则按磁盘来
        // （那是「下次启动会听的端口」）。
        let internal = record
            .applied
            .map(|applied| applied.internal_port)
            .unwrap_or(disk_port);

        // 一、不该在位：有就撤，没有就把状态收拾干净
        if !(record.enabled && record.running) {
            if let Some(applied) = record.applied {
                self.remove_mapping_locked(id, applied, "实例未在运行（或开关已关）")
                    .await;
            } else {
                changed |= self.update(id, |m| {
                    m.internal_port = Some(disk_port);
                    // 实例都不跑了，「上次为什么没映射上」的失败标记也该翻篇
                    if m.phase == MapPhase::Failed {
                        m.phase = MapPhase::Idle;
                        m.error = None;
                    }
                });
                if changed {
                    self.publish();
                }
            }
            return;
        }

        // 二、该在位
        let target = Applied {
            protocol: record.protocol,
            external_port: record.effective_external(internal),
            internal_port: internal,
        };
        if record.applied == Some(target) {
            // 已经在位：只刷新展示（名字、端口），不动路由器
            changed |= self.update(id, |m| {
                m.internal_port = Some(target.internal_port);
                m.phase = MapPhase::Mapped;
            });
            if changed {
                self.publish();
            }
            return;
        }

        let Some(gateway) = self.ensure_gateway_locked().await else {
            let error = self
                .gateway_error()
                .unwrap_or_else(|| "UPnP 网关不可用".to_string());
            self.update(id, |m| {
                m.internal_port = Some(disk_port);
                m.phase = MapPhase::Failed;
                m.applied = None;
                m.error = Some(error);
            });
            self.publish();
            return;
        };

        // 目标变了（换协议 / 换外部端口）：先把旧的撤了再上新的。
        // 撤不掉也继续 —— 端口被占时 add 自己还有一轮「先撤再试」。
        if let Some(old) = record.applied {
            let ops = gateway.ops.clone();
            let removed = self.remove_port_on(&ops, old).await;
            if let Err(e) = removed {
                tracing::warn!(instance = id, error = %e, "替换映射前撤销旧映射失败，继续尝试新映射");
            }
            self.update(id, |m| m.applied = None);
        }

        self.update(id, |m| {
            m.internal_port = Some(target.internal_port);
            m.phase = MapPhase::Mapping;
            m.error = None;
        });
        self.publish();

        let local_addr = SocketAddr::new(gateway.local_ip, target.internal_port);
        let outcome = self.add_with_retry(&gateway.ops, target, local_addr).await;
        match &outcome {
            Ok(()) => {
                self.update(id, |m| {
                    m.phase = MapPhase::Mapped;
                    m.applied = Some(target);
                    m.error = None;
                });
                tracing::info!(
                    instance = id,
                    protocol = target.protocol.as_str(),
                    external = target.external_port,
                    internal = target.internal_port,
                    "UPnP 映射已建立"
                );
            }
            Err(message) => {
                self.update(id, |m| {
                    m.phase = MapPhase::Failed;
                    m.applied = None;
                    m.error = Some(message.clone());
                });
                tracing::warn!(instance = id, %message, "UPnP 映射失败");
            }
        }
        self.publish();
    }

    /// 从数据根读一个实例的 UPnP 相关配置与目录；实例不存在返回 `None`。
    fn load(&self, id: &str) -> Option<InstanceInfo> {
        let store = InstanceStore::new(&self.data_dir);
        let config = store.read_config(id).ok().flatten()?;
        let dir = store.instance_dir(&config);
        Some(InstanceInfo {
            name: config.name.clone(),
            enabled: config.upnp_enabled,
            protocol: Protocol::from_config(config.upnp_protocol()),
            external_port: config.upnp_external_port,
            dir,
        })
    }

    /// 丢记录 + 撤映射（实例删除、或磁盘上已经不存在时）。
    async fn forget_locked(&self, id: &str) {
        let record = self.lock_inner().mappings.remove(id);
        // running 集合同步清掉：这个 id 不会再来了（真回来会重新插）
        // （不在 `record` 分支里做：没有记录也可能在集合里）
        let _ = self.lock_inner().running.remove(id);
        let Some(record) = record else { return };
        if let Some(applied) = record.applied
            && let Some(ops) = self.gateway_ops()
            && let Err(e) = self.remove_port_on(&ops, applied).await
        {
            tracing::warn!(instance = id, error = %e, "删除实例时撤销 UPnP 映射失败");
        }
        self.publish();
    }

    /// 撤掉在位的映射并把记录标回 idle。
    async fn remove_mapping_locked(&self, id: &str, applied: Applied, reason: &str) {
        if let Some(ops) = self.gateway_ops()
            && let Err(e) = self.remove_port_on(&ops, applied).await
        {
            // 撤销失败只是路由器上可能留了个孤儿映射；行不能因此标成 failed
            tracing::warn!(instance = id, error = %e, "撤销 UPnP 映射失败");
        }
        self.update(id, |m| {
            m.applied = None;
            m.phase = MapPhase::Idle;
            m.error = None;
        });
        tracing::info!(instance = id, reason, "UPnP 映射已撤销");
        self.publish();
    }

    /// 全盘对账：以磁盘索引为准（启动播种、`upnp.probe`、事件积压后恢复）。
    ///
    /// 调用方必须已持有 `ops`。
    async fn reconcile_locked(&self) {
        let store = InstanceStore::new(&self.data_dir);
        let index = store.read_index();
        let mut seen = BTreeSet::new();
        for summary in &index.instances {
            seen.insert(summary.id.clone());
            self.sync_locked(&summary.id).await;
        }
        // 记录里有、索引里没有的（比如 scan 清理掉的）→ 撤映射丢记录
        let extra: Vec<String> = {
            let inner = self.lock_inner();
            inner
                .mappings
                .keys()
                .filter(|id| !seen.contains(*id))
                .cloned()
                .collect()
        };
        for id in extra {
            self.forget_locked(&id).await;
        }
    }

    // ── 网关 ───────────────────────────────────────────────────────────────

    /// 拿到可用网关：缓存有直接用，没有就发现（带失败冷却）。
    ///
    /// 调用方必须已持有 `ops`。
    async fn ensure_gateway_locked(&self) -> Option<ReadyGateway> {
        if let Some(ready) = self.ready_gateway() {
            return Some(ready);
        }
        self.discover_locked(false).await
    }

    fn ready_gateway(&self) -> Option<ReadyGateway> {
        let inner = self.lock_inner();
        if inner.gateway.phase != GatewayPhase::Ready {
            return None;
        }
        let ops = inner.gateway.ops.clone()?;
        let local_ip = inner.gateway.local_ip?;
        Some(ReadyGateway { ops, local_ip })
    }

    /// 重新发现网关 + 刷新公网 IP。
    ///
    /// `force = true`（`upnp.probe`）无视失败冷却。返回 `None` = 当前没有
    /// 可用网关，原因已写进网关状态（`gateway.error`）。
    async fn discover_locked(&self, force: bool) -> Option<ReadyGateway> {
        let now = now_ms();
        {
            let mut inner = self.lock_inner();
            let cooled = inner.gateway.phase == GatewayPhase::Error
                && inner
                    .gateway
                    .probed_at_ms
                    .is_some_and(|last| now.saturating_sub(last) < DISCOVER_RETRY_COOLDOWN_MS);
            if !force && cooled {
                return None;
            }
            inner.gateway.phase = GatewayPhase::Searching;
            inner.gateway.error = None;
        }
        self.publish();

        let transport = self.transport.clone();
        let discovered = tokio::task::spawn_blocking(move || transport.discover()).await;
        let found = match discovered {
            Ok(Ok(found)) => found,
            Ok(Err(message)) => return self.gateway_failed(message, now),
            Err(join) => {
                return self.gateway_failed(format!("发现网关的后台任务失败: {join}"), now);
            }
        };

        // 公网 IP 拿不到不算发现失败：映射不依赖它，只是展示与 CGNAT 判断缺一项
        let ops = found.ops;
        let probe_ops = ops.clone();
        let external_ip = tokio::task::spawn_blocking(move || probe_ops.external_ip())
            .await
            .ok()
            .and_then(|result| result.ok());

        {
            let mut inner = self.lock_inner();
            inner.gateway.phase = GatewayPhase::Ready;
            inner.gateway.ops = Some(ops.clone());
            inner.gateway.address = Some(found.address);
            inner.gateway.local_ip = Some(found.local_ip);
            inner.gateway.external_ip = external_ip;
            inner.gateway.error = None;
            inner.gateway.probed_at_ms = Some(now);
        }
        tracing::info!(
            address = %found.address,
            local_ip = %found.local_ip,
            external_ip = external_ip.map(|ip| ip.to_string()).unwrap_or_else(|| "未知".into()),
            "发现 UPnP 网关"
        );
        self.publish();
        Some(ReadyGateway {
            ops,
            local_ip: found.local_ip,
        })
    }

    fn gateway_failed(&self, message: String, now: u64) -> Option<ReadyGateway> {
        {
            let mut inner = self.lock_inner();
            inner.gateway.phase = GatewayPhase::Error;
            // 句柄留着：撤映射还能拿旧网关再试一次（比如换完端口才失败的场景）
            inner.gateway.error = Some(message.clone());
            inner.gateway.probed_at_ms = Some(now);
        }
        tracing::warn!(error = %message, "UPnP 网关发现失败");
        self.publish();
        None
    }

    // ── 路由器操作 ─────────────────────────────────────────────────────────

    /// 加一条映射；外部端口被占时先撤掉占位的再试一次（计划内的补救）。
    async fn add_with_retry(
        &self,
        ops: &Arc<dyn GatewayOps>,
        target: Applied,
        local_addr: SocketAddr,
    ) -> std::result::Result<(), String> {
        let ops = ops.clone();
        match self
            .add_port_on(&ops, target, local_addr, transport::MAPPING_DESCRIPTION)
            .await
        {
            Ok(()) => Ok(()),
            Err(AddPortFailure::PortInUse) => {
                tracing::warn!(
                    external = target.external_port,
                    "外部端口已被占用，撤销占位映射后重试"
                );
                let remover = ops.clone();
                if let Err(e) = self.remove_port_on(&remover, target).await {
                    tracing::warn!(error = %e, "撤销占位映射失败，仍然重试一次");
                }
                match self
                    .add_port_on(&ops, target, local_addr, transport::MAPPING_DESCRIPTION)
                    .await
                {
                    Ok(()) => Ok(()),
                    Err(AddPortFailure::Other(message)) => Err(message),
                    Err(AddPortFailure::PortInUse) => Err(format!(
                        "外部端口 {} 被别的映射占用，撤销后仍无法映射",
                        target.external_port
                    )),
                }
            }
            Err(AddPortFailure::Other(message)) => Err(message),
        }
    }

    async fn add_port_on(
        &self,
        ops: &Arc<dyn GatewayOps>,
        target: Applied,
        local_addr: SocketAddr,
        description: &str,
    ) -> std::result::Result<(), AddPortFailure> {
        let ops = ops.clone();
        let description = description.to_string();
        let outcome = tokio::task::spawn_blocking(move || {
            ops.add_port(
                target.protocol,
                target.external_port,
                local_addr,
                &description,
            )
        })
        .await;
        match outcome {
            Ok(result) => result,
            Err(join) => Err(AddPortFailure::Other(format!(
                "加映射的后台任务失败: {join}"
            ))),
        }
    }

    async fn remove_port_on(
        &self,
        ops: &Arc<dyn GatewayOps>,
        target: Applied,
    ) -> std::result::Result<(), String> {
        let ops = ops.clone();
        let outcome = tokio::task::spawn_blocking(move || {
            ops.remove_port(target.protocol, target.external_port)
        })
        .await;
        match outcome {
            Ok(result) => result,
            Err(join) => Err(format!("撤映射的后台任务失败: {join}")),
        }
    }

    // ── 对外流程 ───────────────────────────────────────────────────────────

    /// `upnp.probe`：立即发现 + 对账 + 重试失败映射，返回最新总览。
    pub async fn probe(&self) -> Value {
        let _guard = self.ops.lock().await;
        self.discover_locked(true).await;
        self.reconcile_locked().await;
        self.status_json()
    }

    /// 关闭时尽力撤销**所有**在位映射（daemon 退出后没人会替它们撤了）。
    pub async fn unmap_all(&self) {
        let _guard = self.ops.lock().await;
        let some_ops = self.gateway_ops();
        let entries: Vec<(String, Applied)> = {
            let inner = self.lock_inner();
            inner
                .mappings
                .values()
                .filter_map(|m| m.applied.map(|applied| (m.instance_id.clone(), applied)))
                .collect()
        };
        for (id, applied) in entries {
            let Some(ops) = some_ops.clone() else { break };
            match self.remove_port_on(&ops, applied).await {
                Ok(()) => {
                    self.update(&id, |m| {
                        m.applied = None;
                        m.phase = MapPhase::Idle;
                    });
                }
                Err(e) => tracing::warn!(instance = %id, error = %e, "关闭时撤销 UPnP 映射失败"),
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
                    tracing::warn!(skipped, "UPnP 事件监听落后，重新对账");
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
                self.lock_inner().running.remove(id);
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
    protocol: Protocol,
    external_port: Option<u16>,
    dir: PathBuf,
}

/// 公网地址落在私网 / 运营商级 NAT 段吗（V1 的 `_isPrivateIp` 逐条对齐；
/// IPv6 不判定，与 V1 一致 —— 它只按点分十进制看）。
fn is_private_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            let (a, b) = (octets[0], octets[1]);
            a == 10
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192 && b == 168)
                || (a == 100 && (64..=127).contains(&b))
        }
        IpAddr::V6(_) => false,
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 模块本体
// ══════════════════════════════════════════════════════════════════════════

/// UPnP 的数据根：自己不落盘，读的实例目录与 `instance` 模块同一个根。
fn data_dir_of(app: &AppState) -> PathBuf {
    super::instance::resolve_data_dir(app.config.modules.section("instance"))
}

struct UpnpState {
    manager: OnceLock<Arc<UpnpManager>>,
    listener: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl UpnpState {
    fn new() -> Self {
        Self {
            manager: OnceLock::new(),
            listener: Mutex::new(None),
        }
    }

    /// 取管理器；还没经 `start()` 初始化就现建一个（方法直接可达时兜底）。
    fn manager_of(&self, app: &AppState) -> Arc<UpnpManager> {
        if let Some(manager) = self.manager.get() {
            return manager.clone();
        }
        let manager = Arc::new(UpnpManager::new(
            app.bus.clone(),
            data_dir_of(app),
            Arc::new(IgdTransport),
        ));
        let _ = self.manager.set(manager);
        self.manager.get().cloned().expect("刚刚设置过")
    }
}

pub struct UpnpModule {
    state: Arc<UpnpState>,
}

impl UpnpModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(UpnpState::new()),
        }
    }
}

impl Default for UpnpModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for UpnpModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("upnp", "路由器端口映射", env!("CARGO_PKG_VERSION")).description(
            "UPnP 端口映射：按实例配置（开关 / 协议 / 外部端口）在实例启动时加映射、停止时撤映射，\
             网关状态与每实例映射进度经 upnp.status / upnp.evt 暴露给客户端。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(
            TOPIC_EVT,
            "UPnP 状态总览变了（网关状态 / 映射成功失败 / 实例行增删）",
        );

        {
            let state = self.state.clone();
            reg.method(
                "upnp.status",
                "UPnP 状态总览（网关 + 每实例映射行，缓存不联网）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { ok(state.manager_of(&ctx.app).status_json()) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "upnp.probe",
                "重新探测网关并重试失败的映射（立即发现，返回最新总览）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { ok(state.manager_of(&ctx.app).probe().await) }
                },
            );
        }
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let app = env.app.clone();
        let manager = Arc::new(UpnpManager::new(
            app.bus.clone(),
            data_dir_of(&app),
            Arc::new(IgdTransport),
        ));
        let _ = self.state.manager.set(manager.clone());

        // 先挂监听器（在服务监听之前）：之后所有实例事件都能收到
        let handle = tokio::spawn(manager.clone().listen(app.bus.subscribe()));
        *self
            .state
            .listener
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(handle);

        // 播种：磁盘上开着 UPnP 的实例先摆进行里（daemon 刚起来，都没在跑）。
        // 顺便对账一遍，把「记录里有、磁盘上没了」的旧账清掉。
        {
            let _guard = manager.ops.lock().await;
            manager.reconcile_locked().await;
        }
        tracing::info!(
            data_dir = %manager.data_dir.display(),
            tracked = manager.lock_inner().mappings.len(),
            "upnp 模块已加载"
        );

        // 有实例开着 UPnP 就顺手探一次：页面打开时网关状态 / 公网 IP 是热的。
        // （实例都没在跑，这一步不会加任何映射。）
        if manager.has_enabled() {
            tokio::spawn(async move {
                let _guard = manager.ops.lock().await;
                manager.discover_locked(true).await;
            });
        }
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        // 先停监听：关闭流程里实例退出的事件不需要再被处理
        let handle = self
            .state
            .listener
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(handle) = handle {
            handle.abort();
        }
        if let Some(manager) = self.state.manager.get() {
            // 尽力撤销全部映射：租约是永久的，daemon 走了就没人撤了
            manager.unmap_all().await;
        }
        Ok(())
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 测试：假网关 + 假传输，把状态机全流程打一遍（不起 WS）
// ══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::builtin::instance::model::{InstanceConfig, InstanceSummary};
    use std::collections::VecDeque;
    use std::net::Ipv4Addr;
    use std::path::Path;

    // ── 假世界：一台路由器 + 一个可配置的发现过程 ─────────────────────────

    /// `add_port` / `remove_port` 的逐次脚本；放完就默认成功。
    enum Script {
        Ok,
        InUse,
        Fail(String),
    }

    #[derive(Default)]
    struct NetState {
        add_script: VecDeque<Script>,
        remove_script: VecDeque<Script>,
        adds: Vec<(Protocol, u16, SocketAddr, String)>,
        removes: Vec<(Protocol, u16)>,
        /// 网关报告的公网 IP；`None` = 取不到。
        external: Option<IpAddr>,
    }

    #[derive(Clone, Default)]
    struct FakeNet(Arc<Mutex<NetState>>);

    impl FakeNet {
        fn new(external: &str) -> Self {
            let net = Self::default();
            net.0.lock().unwrap().external = Some(external.parse().expect("测试 IP"));
            net
        }

        fn lock(&self) -> std::sync::MutexGuard<'_, NetState> {
            self.0.lock().unwrap_or_else(|e| e.into_inner())
        }

        fn script_add(&self, script: Script) {
            self.lock().add_script.push_back(script);
        }

        fn adds(&self) -> Vec<(Protocol, u16, SocketAddr, String)> {
            self.lock().adds.clone()
        }

        fn removes(&self) -> Vec<(Protocol, u16)> {
            self.lock().removes.clone()
        }
    }

    impl GatewayOps for FakeNet {
        fn external_ip(&self) -> std::result::Result<IpAddr, String> {
            self.lock()
                .external
                .ok_or_else(|| "取公网 IP 失败".to_string())
        }

        fn add_port(
            &self,
            protocol: Protocol,
            external_port: u16,
            local_addr: SocketAddr,
            description: &str,
        ) -> std::result::Result<(), AddPortFailure> {
            let mut state = self.lock();
            state
                .adds
                .push((protocol, external_port, local_addr, description.to_string()));
            match state.add_script.pop_front().unwrap_or(Script::Ok) {
                Script::Ok => Ok(()),
                Script::InUse => Err(AddPortFailure::PortInUse),
                Script::Fail(message) => Err(AddPortFailure::Other(message)),
            }
        }

        fn remove_port(
            &self,
            protocol: Protocol,
            external_port: u16,
        ) -> std::result::Result<(), String> {
            let mut state = self.lock();
            state.removes.push((protocol, external_port));
            match state.remove_script.pop_front().unwrap_or(Script::Ok) {
                Script::Ok | Script::InUse => Ok(()),
                Script::Fail(message) => Err(message),
            }
        }
    }

    /// 发现成功、指向固定假网关的传输（错误注入走 [`World::discover_error`]）。
    struct World {
        net: FakeNet,
        discover_error: Arc<Mutex<Option<String>>>,
        local_ip: IpAddr,
    }

    impl World {
        fn new(external: &str) -> Self {
            Self {
                net: FakeNet::new(external),
                discover_error: Arc::new(Mutex::new(None)),
                local_ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 100)),
            }
        }

        fn transport(&self) -> Arc<dyn UpnpTransport> {
            let net = self.net.clone();
            let error = self.discover_error.clone();
            let local_ip = self.local_ip;
            struct T {
                net: FakeNet,
                error: Arc<Mutex<Option<String>>>,
                local_ip: IpAddr,
            }
            impl UpnpTransport for T {
                fn discover(&self) -> std::result::Result<transport::FoundGateway, String> {
                    if let Some(message) =
                        self.error.lock().unwrap_or_else(|e| e.into_inner()).clone()
                    {
                        return Err(message);
                    }
                    Ok(transport::FoundGateway {
                        ops: Arc::new(self.net.clone()),
                        address: "192.168.1.1:1900".parse().unwrap(),
                        local_ip: self.local_ip,
                    })
                }
            }
            Arc::new(T {
                net,
                error,
                local_ip,
            })
        }

        fn discover_error(&self, message: Option<&str>) {
            *self
                .discover_error
                .lock()
                .unwrap_or_else(|e| e.into_inner()) = message.map(str::to_string);
        }
    }

    // ── 临时实例目录 ─────────────────────────────────────────────────────

    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new(tag: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "edgecube-upnp-{tag}-{}-{}",
                std::process::id(),
                now_ms()
            ));
            std::fs::create_dir_all(&root).expect("应能建临时目录");
            Self(root)
        }

        fn path(&self) -> &Path {
            &self.0
        }

        /// 往磁盘上摆一个实例（元数据 + 索引），返回它的工作目录。
        fn add_instance(
            &self,
            id: &str,
            name: &str,
            enabled: bool,
            protocol: &str,
            external: Option<u16>,
        ) -> PathBuf {
            let store = InstanceStore::new(&self.0);
            store.ensure_dirs().expect("目录");
            let config = InstanceConfig {
                id: id.to_string(),
                name: name.to_string(),
                upnp_enabled: enabled,
                upnp_protocol: protocol.to_string(),
                upnp_external_port: external,
                ..Default::default()
            };
            store.write_config(&config).expect("写元数据");
            let mut index = store.read_index();
            if !index.contains(id) {
                index.instances.push(InstanceSummary::new(id, name));
                store.write_index(&index).expect("写索引");
            }
            let dir = store.default_dir(id);
            std::fs::create_dir_all(&dir).expect("实例目录");
            dir
        }

        /// 改某个实例的 UPnP 配置（模拟用户在设置里改了）。
        fn set_upnp(&self, id: &str, enabled: bool, protocol: &str, external: Option<u16>) {
            let store = InstanceStore::new(&self.0);
            let mut config = store.read_config(id).expect("读元数据").expect("实例存在");
            config.upnp_enabled = enabled;
            config.upnp_protocol = protocol.to_string();
            config.upnp_external_port = external;
            store.write_config(&config).expect("写元数据");
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn manager_for(root: &TempRoot, world: &World) -> UpnpManager {
        UpnpManager::new(
            EventBus::new(64),
            root.path().to_path_buf(),
            world.transport(),
        )
    }

    fn write_server_properties(dir: &Path, port: u16) {
        std::fs::write(
            dir.join("server.properties"),
            format!("server-port={port}\nmotd=hi\n"),
        )
        .expect("写 server.properties");
    }

    fn phase_event(id: &str, phase: &str) -> Value {
        json!({ "id": id, "phase": phase })
    }

    fn row<'a>(status: &'a Value, id: &str) -> &'a Value {
        status["mappings"]
            .as_array()
            .expect("mappings 该是数组")
            .iter()
            .find(|row| row["instance_id"] == json!(id))
            .unwrap_or_else(|| panic!("状态里该有 {id}: {status}"))
    }

    // ── 状态机 ───────────────────────────────────────────────────────────

    #[tokio::test]
    async fn starts_unknown_and_seeds_only_enabled_instances() {
        let root = TempRoot::new("seed");
        let world = World::new("203.0.113.7");
        root.add_instance("aaaa", "开着", true, "tcp", None);
        root.add_instance("bbbb", "关着", false, "tcp", None);
        let manager = manager_for(&root, &world);

        // 还没探测：网关是 unknown，也没记录
        let before = manager.status_json();
        assert_eq!(before["gateway"]["state"], json!("unknown"));
        assert_eq!(before["count"], json!(0));

        // 播种（start() 里做的那一步）
        let _guard = manager.ops.lock().await;
        manager.reconcile_locked().await;
        let seeded = manager.status_json();
        assert_eq!(seeded["count"], json!(1));
        assert_eq!(row(&seeded, "aaaa")["state"], json!("idle"));
        assert_eq!(row(&seeded, "aaaa")["enabled"], json!(true));
        assert!(world.net.adds().is_empty(), "实例没在跑，不该加映射");
    }

    #[tokio::test]
    async fn starting_maps_and_stopping_unmaps() {
        let root = TempRoot::new("flow");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;

        let adds = world.net.adds();
        assert_eq!(adds.len(), 1);
        assert_eq!(adds[0].0, Protocol::Tcp);
        assert_eq!(adds[0].1, 25565);
        assert_eq!(adds[0].2, "192.168.1.100:25565".parse().unwrap());
        assert_eq!(adds[0].3, transport::MAPPING_DESCRIPTION);

        let mapped = manager.status_json();
        assert_eq!(mapped["gateway"]["state"], json!("ready"));
        assert_eq!(mapped["gateway"]["external_ip"], json!("203.0.113.7"));
        assert_eq!(mapped["gateway"]["cgnat"], json!(false));
        let mapped_row = row(&mapped, "aaaa");
        assert_eq!(mapped_row["state"], json!("mapped"));
        assert_eq!(mapped_row["internal_port"], json!(25565));
        assert_eq!(mapped_row["external_port"], json!(25565));
        assert_eq!(mapped_row["public_address"], json!("203.0.113.7:25565"));

        // running 再过一遍：不动路由器（幂等）
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "running"),
            )
            .await;
        assert_eq!(world.net.adds().len(), 1);

        // stopping 是过渡态：映射先留着
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "stopping"),
            )
            .await;
        assert!(world.net.removes().is_empty());

        // 真正退出：撤映射
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "stopped"),
            )
            .await;
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        let idle = manager.status_json();
        assert_eq!(row(&idle, "aaaa")["state"], json!("idle"));
        assert_eq!(row(&idle, "aaaa")["public_address"], json!(null));
    }

    #[tokio::test]
    async fn enable_while_running_maps_immediately() {
        let root = TempRoot::new("enable-live");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", false, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        // 实例已经在跑（开关还关着：没有记录）
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "running"),
            )
            .await;
        assert_eq!(manager.status_json()["count"], json!(0));
        assert!(world.net.adds().is_empty());

        // 运行中把开关打开 → 立刻映射
        root.set_upnp("aaaa", true, "tcp", None);
        manager
            .handle_event(
                super::super::instance::TOPIC_UPDATED,
                &json!({ "id": "aaaa" }),
            )
            .await;
        assert_eq!(world.net.adds().len(), 1);
        let status = manager.status_json();
        assert_eq!(row(&status, "aaaa")["state"], json!("mapped"));
        assert_eq!(row(&status, "aaaa")["running"], json!(true));

        // 再关掉 → 撤映射，记录留下（enabled=false, idle）
        root.set_upnp("aaaa", false, "tcp", None);
        manager
            .handle_event(
                super::super::instance::TOPIC_UPDATED,
                &json!({ "id": "aaaa" }),
            )
            .await;
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        let off = manager.status_json();
        assert_eq!(row(&off, "aaaa")["enabled"], json!(false));
        assert_eq!(row(&off, "aaaa")["state"], json!("idle"));
    }

    #[tokio::test]
    async fn protocol_and_external_port_come_from_config() {
        let root = TempRoot::new("udp");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "基岩服", true, "udp", Some(19133));
        std::fs::write(dir.join("pnx.yml"), "settings:\n  port: 19132\n").unwrap();
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;

        let adds = world.net.adds();
        assert_eq!(adds.len(), 1);
        assert_eq!(adds[0].0, Protocol::Udp);
        assert_eq!(adds[0].1, 19133, "外部端口用配置里的");
        assert_eq!(
            adds[0].2,
            "192.168.1.100:19132".parse().unwrap(),
            "内部端口来自 pnx.yml"
        );
        let status = manager.status_json();
        assert_eq!(row(&status, "aaaa")["protocol"], json!("udp"));
        assert_eq!(row(&status, "aaaa")["internal_port"], json!(19132));
        assert_eq!(row(&status, "aaaa")["external_port"], json!(19133));
        assert_eq!(
            row(&status, "aaaa")["public_address"],
            json!("203.0.113.7:19133")
        );
    }

    #[tokio::test]
    async fn changing_external_port_remaps() {
        let root = TempRoot::new("remap");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;
        assert_eq!(world.net.adds().len(), 1);

        // 运行中改外部端口 → 撤旧的、加新的
        root.set_upnp("aaaa", true, "tcp", Some(25599));
        manager
            .handle_event(
                super::super::instance::TOPIC_UPDATED,
                &json!({ "id": "aaaa" }),
            )
            .await;
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        let adds = world.net.adds();
        assert_eq!(adds.len(), 2);
        assert_eq!(adds[1].1, 25599);
        assert_eq!(
            row(&manager.status_json(), "aaaa")["public_address"],
            json!("203.0.113.7:25599")
        );
    }

    #[tokio::test]
    async fn running_mapping_keeps_its_internal_port_when_file_changes() {
        // 运行中改 server-port 是给「下次启动」准备的：在位的映射不该跟着换
        // （服务端还听着老端口，现在重映射会把在线的人踢下来）。
        let root = TempRoot::new("keep-port");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;

        write_server_properties(&dir, 25599);
        manager
            .handle_event(
                super::super::instance::TOPIC_UPDATED,
                &json!({ "id": "aaaa" }),
            )
            .await;
        assert_eq!(world.net.adds().len(), 1, "不该重映射");
        assert!(world.net.removes().is_empty());
        assert_eq!(
            row(&manager.status_json(), "aaaa")["internal_port"],
            json!(25565)
        );

        // 停掉再起：这次按磁盘上的新端口映射
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "stopped"),
            )
            .await;
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;
        let adds = world.net.adds();
        assert_eq!(adds.len(), 2);
        assert_eq!(adds[1].2, "192.168.1.100:25599".parse().unwrap());
    }

    #[tokio::test]
    async fn port_in_use_is_retried_after_removing_the_squatter() {
        let root = TempRoot::new("in-use");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        world.net.script_add(Script::InUse);
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;

        // 第一次被占 → 撤掉占位的 → 重试成功
        assert_eq!(world.net.adds().len(), 2);
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        assert_eq!(
            row(&manager.status_json(), "aaaa")["state"],
            json!("mapped")
        );
    }

    #[tokio::test]
    async fn mapping_failure_is_recorded_on_the_row() {
        let root = TempRoot::new("fail");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        world.net.script_add(Script::Fail("网关拒了".into()));
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;
        let status = manager.status_json();
        assert_eq!(row(&status, "aaaa")["state"], json!("failed"));
        assert_eq!(row(&status, "aaaa")["error"], json!("网关拒了"));
        assert_eq!(
            status["gateway"]["state"],
            json!("ready"),
            "映射失败不代表网关坏了"
        );

        // 实例停下：失败标记翻篇（状态回 idle）
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "crashed"),
            )
            .await;
        let idle = manager.status_json();
        assert_eq!(row(&idle, "aaaa")["state"], json!("idle"));
        assert_eq!(row(&idle, "aaaa")["error"], json!(null));
    }

    #[tokio::test]
    async fn discover_failure_marks_gateway_and_rows_then_probe_retries() {
        let root = TempRoot::new("no-gw");
        let world = World::new("203.0.113.7");
        root.add_instance("aaaa", "生存服", true, "tcp", None);
        let manager = manager_for(&root, &world);

        // 发现失败：网关进 error，想映射的行带上原因
        world.discover_error(Some("路由器没开 UPnP"));
        let _guard = manager.ops.lock().await;
        manager.reconcile_locked().await;
        drop(_guard);
        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;
        let failed = manager.status_json();
        assert_eq!(failed["gateway"]["state"], json!("error"));
        assert_eq!(failed["gateway"]["error"], json!("路由器没开 UPnP"));
        assert_eq!(row(&failed, "aaaa")["state"], json!("failed"));
        assert_eq!(row(&failed, "aaaa")["error"], json!("路由器没开 UPnP"));

        // 「重新探测」：这次发现成功，失败的映射会被重试
        world.discover_error(None);
        let probed = manager.probe().await;
        assert_eq!(probed["gateway"]["state"], json!("ready"));
        assert_eq!(row(&probed, "aaaa")["state"], json!("mapped"));
        assert_eq!(world.net.adds().len(), 1);
    }

    #[tokio::test]
    async fn cgnat_external_ip_is_flagged() {
        let root = TempRoot::new("cgnat");
        let world = World::new("100.64.3.4");
        root.add_instance("aaaa", "生存服", true, "tcp", None);
        let manager = manager_for(&root, &world);

        let status = manager.probe().await;
        assert_eq!(status["gateway"]["cgnat"], json!(true));

        // 公网 IP 取不到不算失败：只是展示缺失
        let world2 = World::new("203.0.113.7");
        world2.net.lock().external = None;
        let manager2 = manager_for(&root, &world2);
        let status2 = manager2.probe().await;
        assert_eq!(status2["gateway"]["state"], json!("ready"));
        assert_eq!(status2["gateway"]["external_ip"], json!(null));
        assert_eq!(status2["gateway"]["cgnat"], json!(false));
    }

    #[tokio::test]
    async fn deleting_instance_unmaps_and_drops_the_row() {
        let root = TempRoot::new("delete");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;
        assert_eq!(manager.status_json()["count"], json!(1));

        manager
            .handle_event(
                super::super::instance::TOPIC_DELETED,
                &json!({ "id": "aaaa" }),
            )
            .await;
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        assert_eq!(manager.status_json()["count"], json!(0));
    }

    #[tokio::test]
    async fn reconcile_drops_rows_for_gone_instances() {
        // scan 把实例清了（事件没有 id）：对账时旧记录要跟着走
        let root = TempRoot::new("scan");
        let world = World::new("203.0.113.7");
        let dir = root.add_instance("aaaa", "生存服", true, "tcp", None);
        write_server_properties(&dir, 25565);
        let manager = manager_for(&root, &world);

        manager
            .handle_event(
                super::super::instance::process::TOPIC_PHASE,
                &phase_event("aaaa", "starting"),
            )
            .await;

        // 磁盘上把元数据与索引都拿掉（模拟 scan 清理）
        let store = InstanceStore::new(root.path());
        store.delete_config("aaaa").unwrap();
        let mut index = store.read_index();
        index.instances.retain(|s| s.id != "aaaa");
        store.write_index(&index).unwrap();

        manager
            .handle_event(super::super::instance::TOPIC_UPDATED, &json!({}))
            .await;
        assert_eq!(world.net.removes(), vec![(Protocol::Tcp, 25565)]);
        assert_eq!(manager.status_json()["count"], json!(0));
    }

    #[tokio::test]
    async fn unmap_all_undoes_every_mapping() {
        let root = TempRoot::new("unmap-all");
        let world = World::new("203.0.113.7");
        let dir_a = root.add_instance("aaaa", "甲", true, "tcp", None);
        let dir_b = root.add_instance("bbbb", "乙", true, "udp", None);
        write_server_properties(&dir_a, 25565);
        std::fs::write(dir_b.join("server.properties"), "server-port=19132\n").unwrap();
        let manager = manager_for(&root, &world);

        for id in ["aaaa", "bbbb"] {
            manager
                .handle_event(
                    super::super::instance::process::TOPIC_PHASE,
                    &phase_event(id, "starting"),
                )
                .await;
        }
        assert_eq!(world.net.adds().len(), 2);

        manager.unmap_all().await;
        let mut removes = world.net.removes();
        removes.sort_by_key(|(_, port)| *port);
        assert_eq!(
            removes,
            vec![(Protocol::Udp, 19132), (Protocol::Tcp, 25565)]
        );
        let status = manager.status_json();
        assert_eq!(row(&status, "aaaa")["state"], json!("idle"));
        assert_eq!(row(&status, "bbbb")["state"], json!("idle"));
    }

    #[test]
    fn cgnat_ranges_match_v1() {
        for private in [
            "10.0.0.1",
            "172.16.0.1",
            "172.31.255.255",
            "192.168.1.1",
            "100.64.0.1",
            "100.127.255.255",
        ] {
            let ip: IpAddr = private.parse().unwrap();
            assert!(is_private_ip(ip), "{private} 该判为私网");
        }
        for public in [
            "8.8.8.8",
            "172.15.0.1",
            "172.32.0.1",
            "100.63.0.1",
            "100.128.0.1",
        ] {
            let ip: IpAddr = public.parse().unwrap();
            assert!(!is_private_ip(ip), "{public} 不该判为私网");
        }
    }

    #[test]
    fn builtin_registry_exposes_upnp_methods_and_topic() {
        let registry = crate::module::registry::ModuleRegistry::build(
            crate::module::registry::builtin_modules(),
            &crate::config::Config::default(),
        )
        .unwrap();
        for method in ["upnp.status", "upnp.probe"] {
            assert!(registry.lookup(method).is_some(), "缺少方法 {method}");
        }
        assert!(
            registry.topics().iter().any(|t| t.topic == TOPIC_EVT),
            "该声明 upnp.evt 主题"
        );
    }
}
