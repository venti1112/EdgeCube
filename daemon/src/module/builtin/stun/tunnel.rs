//! 每实例一条的 STUN 隧道：探测 → 监听 → 转发 → 保活 → 重建。
//!
//! 状态机与日志文案逐条对照 V1 的 `lib/stun/stun_tunnel_service.dart`
//! （那是纯 Dart 的单例全局隧道；这里拆成「每实例一条」）：
//!
//! ```text
//! Idle ──start──▶ Probing ──拿到映射──▶ (bind) ──▶ Running
//!                    ▲   │失败≥N              │保活断/公网变
//!                    │   ▼                    ▼
//!                    │ Failed            重建（3 秒后回到 Probing）
//!                    └─ 每轮全挂 → 15 秒后重试（V1 同款）
//! ```
//!
//! 与 V1 的实现差异（都是 nyat-core 带来的）：
//!
//! * V1 用 Dart 的临时端口做探测、再用 `SO_REUSEADDR` 技巧让监听套接字绑上
//!   同一个端口；nyat-core 让我们**自己选**本地端口 —— 用 `0.0.0.0:0` 让内核
//!   挑，实际端口从映射回调里读回来（`Mapping::local`）。
//! * V1 的保活是在探测连接上重发 Binding Request；nyat-core 是「HTTP HEAD 保活
//!   连接 + 断开后内部重连」，公网地址变化由它回调，本模块只管重建。

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::Duration;

use serde_json::{Value, json};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::LogBuffer;
use super::TunnelManager;
use super::mapper::{MapperSpec, Mapping, StunMapper};
use super::proxy;

/// 隧道相位。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    /// 未启用 / 已停止（含「实例在跑但隧道失败终态后实例没重启」之外的一切静止态）。
    Idle,
    /// 正在探测公网映射，或失败后的等待重试间隙。
    Probing,
    /// 隧道已就绪，正在转发。
    Running,
    /// 多轮尝试后仍拿不到隧道（通常是 NAT 类型不支持），等实例重启或配置变更。
    Failed,
}

impl Phase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Probing => "probing",
            Self::Running => "running",
            Self::Failed => "failed",
        }
    }
}

/// 运行态快照（任务写，查询侧读）。
#[derive(Debug, Clone, PartialEq)]
struct RunState {
    phase: Phase,
    /// 公网直连端点；未就绪为 `None`。
    public: Option<SocketAddr>,
    /// 本机监听端口（NAT 映射的内侧端点）；未就绪为 0。
    local_port: u16,
    /// 当前 / 最近尝试的 STUN 服务器。
    server: Option<String>,
    /// 最近一次失败原因。
    error: Option<String>,
}

impl Default for RunState {
    fn default() -> Self {
        Self {
            phase: Phase::Idle,
            public: None,
            local_port: 0,
            server: None,
            error: None,
        }
    }
}

/// 计数器（原子；读快照不加锁，写侧最热的是每个数据块的 fetch_add）。
#[derive(Default)]
pub struct Stats {
    active: AtomicU64,
    total_up: AtomicU64,
    total_down: AtomicU64,
    up_speed: AtomicU64,
    down_speed: AtomicU64,
    last_up: AtomicU64,
    last_down: AtomicU64,
}

impl Stats {
    /// 一次运行开始时清零（V1 `start()` 同款：总量也归零）。
    fn reset(&self) {
        for counter in [
            &self.active,
            &self.total_up,
            &self.total_down,
            &self.up_speed,
            &self.down_speed,
            &self.last_up,
            &self.last_down,
        ] {
            counter.store(0, Ordering::Relaxed);
        }
    }

    /// 停止时把速率归零（总量保留，同 V1）。
    fn stop_speeds(&self) {
        self.up_speed.store(0, Ordering::Relaxed);
        self.down_speed.store(0, Ordering::Relaxed);
    }

    /// 采样一次速率（模块的 1 秒定时器调用）。
    fn tick(&self) {
        let up = self.total_up.load(Ordering::Relaxed);
        let down = self.total_down.load(Ordering::Relaxed);
        self.up_speed.store(
            up.saturating_sub(self.last_up.load(Ordering::Relaxed)),
            Ordering::Relaxed,
        );
        self.down_speed.store(
            down.saturating_sub(self.last_down.load(Ordering::Relaxed)),
            Ordering::Relaxed,
        );
        self.last_up.store(up, Ordering::Relaxed);
        self.last_down.store(down, Ordering::Relaxed);
    }

    fn snapshot(&self) -> (u64, u64, u64, u64, u64) {
        (
            self.active.load(Ordering::Relaxed),
            self.total_up.load(Ordering::Relaxed),
            self.total_down.load(Ordering::Relaxed),
            self.up_speed.load(Ordering::Relaxed),
            self.down_speed.load(Ordering::Relaxed),
        )
    }
}

/// 实例级配置（sync 时刷新；影响转发的字段变了就重启任务）。
#[derive(Debug, Clone, PartialEq)]
pub struct TunnelConfig {
    pub name: String,
    pub enabled: bool,
    pub proxy_protocol: bool,
    pub target_override: Option<u16>,
    /// 展示用的生效转发目标端口（覆盖值或服务端实际端口）。
    pub display_target: u16,
}

/// 一次运行的参数快照（任务只读；设置变更 = 重启任务拿新快照）。
#[derive(Debug, Clone)]
pub struct RunConfig {
    pub servers: Vec<String>,
    pub keepalive_http: String,
    pub interval: Duration,
    pub max_connections: u32,
    pub show_log: bool,
    pub proxy_protocol: bool,
    /// 转发目标端口（本机 `127.0.0.1:<它>`）。
    pub target: u16,
}

/// 时序参数（生产值对齐 V1；测试可调小）。
#[derive(Debug, Clone)]
pub struct Tuning {
    /// 单台 STUN 服务器建立映射的限时（nyat 单次尝试可能拖到分钟级，必须自己卡）。
    pub establish_timeout: Duration,
    /// 一轮内全部服务器都没探测成功后的重试间隔（V1：15 秒）。
    pub retry_delay: Duration,
    /// 绑定监听失败后的重试间隔（V1：5 秒）。
    pub bind_retry_delay: Duration,
    /// 重建前的等待（V1：3 秒）。
    pub rebuild_delay: Duration,
    /// 连续失败多少轮后放弃（V1：3）。
    pub max_failures: u32,
}

impl Default for Tuning {
    fn default() -> Self {
        Self {
            establish_timeout: Duration::from_secs(15),
            retry_delay: Duration::from_secs(15),
            bind_retry_delay: Duration::from_secs(5),
            rebuild_delay: Duration::from_secs(3),
            max_failures: 3,
        }
    }
}

/// 任务运行环境（管理器组装，任务只读）。
pub struct TaskEnv {
    /// 回推事件用（管理器没了就静默跳过 —— 关闭流程里很正常）。
    pub manager: Weak<TunnelManager>,
    pub log: Arc<LogBuffer>,
    pub mapper: Arc<dyn StunMapper>,
    pub run: RunConfig,
    pub tuning: Tuning,
}

impl TaskEnv {
    /// 推一份全局状态快照（事件载荷与 `stun.status` 同一份）。
    fn publish(&self) {
        if let Some(manager) = self.manager.upgrade() {
            manager.publish();
        }
    }
}

/// 任务句柄的「Drop 即中止」包装。
///
/// nyat 的打洞任务不随 `JoinHandle` 的丢弃而消失（那是 detach）。隧道任务在
/// 任何路径（正常结束 / 被 abort / 提前 return）放下 `Session` 时都必须把
/// 打洞任务带上，否则它会在后台无限保活、占着那个端口。
struct AbortOnDrop(JoinHandle<Result<(), String>>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// 一次成功试出的打洞会话。
struct Session {
    rx: watch::Receiver<Option<Mapping>>,
    handle: AbortOnDrop,
    server: String,
    mapping: Mapping,
}

/// `serve` 的结束原因。
enum ServeEnd {
    /// 保活断开或公网地址变化：等一会儿重建。
    Rebuild,
    /// 绑定监听失败：按「一轮失败」计数（V1 同款）。
    BindFailed,
}

/// 一条隧道。
///
/// 静态部分（实例配置）与动态部分（相位 / 统计）分开锁：快照读取只碰
/// 小锁 + 原子量，绝不在持有锁时做 IO（同 upnp 的取舍）。
pub struct Tunnel {
    pub id: String,
    cfg: Mutex<TunnelConfig>,
    running: AtomicBool,
    state: Mutex<RunState>,
    stats: Stats,
    /// 当前 supervisor 任务；`None` = 没在跑（含失败终态与自然结束）。
    control: Mutex<Option<JoinHandle<()>>>,
    /// 当前会话（`serve` 阶段）的取消令牌；`stop()` 先取消它再 abort 任务，
    /// 否则在途转发连接会守着旧套接字不散。
    session: Mutex<Option<CancellationToken>>,
}

impl Tunnel {
    pub fn new(id: impl Into<String>, cfg: TunnelConfig, running: bool) -> Self {
        Self {
            id: id.into(),
            cfg: Mutex::new(cfg),
            running: AtomicBool::new(running),
            state: Mutex::new(RunState::default()),
            stats: Stats::default(),
            control: Mutex::new(None),
            session: Mutex::new(None),
        }
    }

    fn lock_cfg(&self) -> std::sync::MutexGuard<'_, TunnelConfig> {
        self.cfg.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_state(&self) -> std::sync::MutexGuard<'_, RunState> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_control(&self) -> std::sync::MutexGuard<'_, Option<JoinHandle<()>>> {
        self.control.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn config(&self) -> TunnelConfig {
        self.lock_cfg().clone()
    }

    pub fn phase(&self) -> Phase {
        self.lock_state().phase
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }

    pub fn set_running(&self, running: bool) {
        self.running.store(running, Ordering::Relaxed);
    }

    /// 有没有活着的任务。自然结束的任务会在收尾时把自己的句柄清掉。
    pub fn has_task(&self) -> bool {
        self.lock_control().is_some()
    }

    /// 刷新实例侧配置；返回是否变化。
    pub fn update_config(&self, cfg: TunnelConfig) -> bool {
        let mut current = self.lock_cfg();
        if *current == cfg {
            return false;
        }
        *current = cfg;
        true
    }

    /// 启动任务。调用方必须已持 `ops`（且自查过「该不该跑」）。
    ///
    /// 失败终态**不会**在这里被自动重试：见管理器 `sync_locked` 的门控。
    pub fn start(self: &Arc<Self>, env: TaskEnv) {
        let mut control = self.lock_control();
        if control.is_some() {
            return;
        }
        self.stats.reset();
        {
            let mut state = self.lock_state();
            *state = RunState {
                phase: Phase::Probing,
                ..RunState::default()
            };
        }
        self.log(&env, format!("隧道启动中，本地目标端口 {}", env.run.target));
        let this = self.clone();
        *control = Some(tokio::spawn(async move {
            this.clone().run(env).await;
            // 自然结束（失败终态 / 静默退出）：把自己的句柄清掉，
            // 之后配置变更（reapply）才能再把它拉起来。
            let _ = this.lock_control().take();
        }));
    }

    /// 停止任务（幂等）。返回是否有过动作（调用方据此决定要不要记日志）。
    pub fn stop(&self) -> bool {
        if let Some(cancel) = self
            .session
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
        {
            // 先取消在途连接，再掐任务（abort 会让任务栈原地消失，
            // 收尾代码不再执行 —— 所以取消必须在这里做）。
            cancel.cancel();
        }
        let had_task = self.lock_control().take();
        if had_task.is_none() && self.phase() == Phase::Idle {
            return false;
        }
        if let Some(handle) = had_task {
            handle.abort();
        }
        self.stats.stop_speeds();
        *self.lock_state() = RunState::default();
        true
    }

    /// 采样一次速率（模块的 1 秒定时器调用）。
    pub fn tick_speeds(&self) {
        self.stats.tick();
    }

    /// 线上行（snake_case）。
    pub fn to_wire(&self, max_connections: u32) -> Value {
        let cfg = self.config();
        let state = self.lock_state().clone();
        let (active, up, down, up_speed, down_speed) = self.stats.snapshot();
        json!({
            "instance_id": self.id,
            "instance_name": cfg.name,
            "enabled": cfg.enabled,
            "running": self.is_running(),
            "state": state.phase.as_str(),
            "public_address": state.public.map(|addr| addr.to_string()),
            "local_port": state.local_port,
            // 留空覆盖时给「服务端实际端口」的现读值（每次 sync 刷新）
            "target_port": cfg.display_target,
            "active_connections": active,
            "max_connections": max_connections,
            "total_up": up,
            "total_down": down,
            "up_speed": up_speed,
            "down_speed": down_speed,
            "error": state.error,
            "server": state.server,
        })
    }

    fn log(&self, env: &TaskEnv, text: impl Into<String>) {
        let name = self.config().name;
        env.log.add(Some((&self.id, &name)), text);
    }

    // ════════════════════════════════════════════════════════════════════
    // 主循环
    // ════════════════════════════════════════════════════════════════════

    /// 一轮 = 探测公网映射 → 绑定监听 → 保活并监控 → 需要时重建（V1 `_runLoop`）。
    async fn run(self: Arc<Self>, env: TaskEnv) {
        let mut failures: u32 = 0;
        loop {
            // ── 探测：依次试各台服务器 ──
            let mut session = None;
            for server in &env.run.servers {
                self.log(&env, format!("正在从 STUN 服务器探测：{server}"));
                self.lock_state().server = Some(server.clone());
                match self.try_server(&env, server).await {
                    Ok(found) => {
                        session = Some(found);
                        break;
                    }
                    Err(message) => {
                        self.lock_state().error = Some(message.clone());
                        self.log(&env, format!("STUN [{server}] 不可用：{message}"));
                    }
                }
            }

            let Some(session) = session else {
                failures += 1;
                if !self
                    .pause_after_failure(&env, failures, FailureKind::Probe)
                    .await
                {
                    return;
                }
                continue;
            };

            self.log(
                &env,
                format!(
                    "探测成功：本地端口 {} → 公网 {}",
                    session.mapping.local.port(),
                    session.mapping.public
                ),
            );

            // ── 监听 + 转发 ──
            match self.serve(&env, session).await {
                ServeEnd::Rebuild => {
                    failures = 0;
                    {
                        let mut state = self.lock_state();
                        state.phase = Phase::Probing;
                        state.public = None;
                        state.local_port = 0;
                        state.error = None;
                    }
                    env.publish();
                    self.log(&env, "正在重建隧道…");
                    tokio::time::sleep(env.tuning.rebuild_delay).await;
                }
                ServeEnd::BindFailed => {
                    failures += 1;
                    // 探测虽已拿到映射，但没能监听，该地址不可用，不要留在界面上（V1）
                    {
                        let mut state = self.lock_state();
                        state.phase = Phase::Probing;
                        state.public = None;
                        state.local_port = 0;
                    }
                    env.publish();
                    if !self
                        .pause_after_failure(&env, failures, FailureKind::Bind)
                        .await
                    {
                        return;
                    }
                }
            }
        }
    }

    /// 一轮失败后的收尾：到限就转失败终态（返回 `false`），否则等待后重试。
    async fn pause_after_failure(&self, env: &TaskEnv, failures: u32, kind: FailureKind) -> bool {
        if failures >= env.tuning.max_failures {
            let message = match kind {
                FailureKind::Probe => {
                    "全部 STUN 服务器均无法建立隧道，当前网络可能不支持（对称 NAT / CGNAT），请改用 FRP 隧道"
                }
                FailureKind::Bind => "无法在映射端口上建立监听，隧道启动失败",
            };
            {
                let mut state = self.lock_state();
                state.phase = Phase::Failed;
                state.public = None;
                state.local_port = 0;
                state.error = Some(message.to_string());
            }
            self.log(env, format!("隧道启动失败：{message}"));
            env.publish();
            return false;
        }
        let delay = match kind {
            FailureKind::Probe => env.tuning.retry_delay,
            FailureKind::Bind => env.tuning.bind_retry_delay,
        };
        if delay > Duration::ZERO {
            self.log(
                env,
                format!(
                    "本轮探测失败，{} 秒后重试（{failures}/{}）",
                    delay.as_secs(),
                    env.tuning.max_failures
                ),
            );
            {
                let mut state = self.lock_state();
                state.phase = Phase::Probing;
                state.public = None;
                state.local_port = 0;
            }
            env.publish();
            tokio::time::sleep(delay).await;
        }
        true
    }

    /// 试一台服务器：等它给出第一个映射（限时 [`Tuning::establish_timeout`]）。
    async fn try_server(&self, env: &TaskEnv, server: &str) -> Result<Session, String> {
        let spec = MapperSpec {
            server: server.to_string(),
            keepalive_http: env.run.keepalive_http.clone(),
            interval: env.run.interval,
        };
        let (mut rx, handle) = env.mapper.start(spec);
        let mut handle = AbortOnDrop(handle);
        let deadline = tokio::time::sleep(env.tuning.establish_timeout);
        tokio::pin!(deadline);

        loop {
            let current = *rx.borrow_and_update();
            if let Some(mapping) = current {
                return Ok(Session {
                    rx,
                    handle,
                    server: server.to_string(),
                    mapping,
                });
            }
            tokio::select! {
                biased;
                res = &mut handle.0 => {
                    return Err(match res {
                        Ok(Err(message)) => message,
                        Ok(Ok(())) => "打洞任务提前结束".to_string(),
                        Err(join) => format!("打洞任务失败: {join}"),
                    });
                }
                changed = rx.changed() => {
                    if changed.is_err() {
                        // 发送端已丢（任务结束），句柄随 Drop 中止，不必再等
                        return Err("打洞任务已结束".to_string());
                    }
                }
                _ = &mut deadline => {
                    return Err(format!(
                        "{} 秒内未能建立映射",
                        env.tuning.establish_timeout.as_secs()
                    ));
                }
            }
        }
    }

    /// 绑定监听 + 转发 + 保活监控（就绪后停在这里，直到该重建了）。
    async fn serve(self: &Arc<Self>, env: &TaskEnv, mut session: Session) -> ServeEnd {
        let port = session.mapping.local.port();
        let listener = match bind_listener(port) {
            Ok(listener) => listener,
            Err(e) => {
                let message = format!("绑定本地端口 {port} 失败：{e}");
                self.lock_state().error = Some(message.clone());
                self.log(env, message);
                return ServeEnd::BindFailed;
            }
        };

        // 就绪：登记取消令牌（stop() 靠它中断在途连接）
        let cancel = CancellationToken::new();
        *self.session.lock().unwrap_or_else(|e| e.into_inner()) = Some(cancel.clone());
        {
            let mut state = self.lock_state();
            state.phase = Phase::Running;
            state.public = Some(session.mapping.public);
            state.local_port = port;
            state.server = Some(session.server.clone());
            state.error = None;
        }
        self.log(
            env,
            format!(
                "隧道已就绪：tcp://127.0.0.1:{} → tcp://0.0.0.0:{port}",
                env.run.target
            ),
        );
        self.log(env, format!("公网直连地址：{}", session.mapping.public));
        env.publish();

        let end = loop {
            tokio::select! {
                biased;
                accepted = listener.accept() => match accepted {
                    Ok((inbound, _)) => self.spawn_inbound(env, &cancel, inbound),
                    Err(e) => self.log(env, format!("监听套接字出错：{e}")),
                },
                res = &mut session.handle.0 => {
                    let reason = match res {
                        Ok(Err(message)) => message,
                        Ok(Ok(())) => "连接已关闭".to_string(),
                        Err(join) => format!("任务异常: {join}"),
                    };
                    self.log(env, format!("保活连接已断开，NAT 映射可能失效（{reason}）"));
                    break ServeEnd::Rebuild;
                }
                changed = session.rx.changed() => match changed {
                    Err(_) => {
                        self.log(env, "保活连接已断开，NAT 映射可能失效");
                        break ServeEnd::Rebuild;
                    }
                    Ok(()) => {
                        if let Some(new) = *session.rx.borrow_and_update()
                            && new != session.mapping
                        {
                            // 打洞任务内部重连了：本地端口和公网端点都变了，
                            // 监听套接字（绑在旧端口上）已失效，整条重建（V1 同款）。
                            self.log(
                                env,
                                format!(
                                    "检测到公网地址变化：{} → {}",
                                    session.mapping.public, new.public
                                ),
                            );
                            session.mapping = new;
                            break ServeEnd::Rebuild;
                        }
                    }
                },
            }
        };

        // 收尾：中断在途连接（它们自己会收尾计数）、放开监听；
        // 打洞任务由 `session.handle` 的 Drop 中止。
        cancel.cancel();
        let _ = self
            .session
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        drop(listener);
        end
    }

    /// 检查并发上限后放行一条入站连接。
    ///
    /// accept 循环是串行的，所以「检查 → 计数」之间没有竞争者。
    fn spawn_inbound(
        self: &Arc<Self>,
        env: &TaskEnv,
        cancel: &CancellationToken,
        inbound: TcpStream,
    ) {
        let Ok(peer) = inbound.peer_addr() else {
            return; // 对端已溜：静默丢弃
        };
        if self.stats.active.load(Ordering::Relaxed) >= u64::from(env.run.max_connections) {
            if env.run.show_log {
                self.log(
                    env,
                    format!("拒绝 {peer}：已达并发上限 {}", env.run.max_connections),
                );
            }
            return; // inbound 随 Drop 关闭
        }
        self.stats.active.fetch_add(1, Ordering::Relaxed);
        let ctx = Arc::new(ConnCtx {
            tunnel: self.clone(),
            log: env.log.clone(),
            instance_id: self.id.clone(),
            instance_name: self.config().name,
            target: env.run.target,
            proxy_protocol: env.run.proxy_protocol,
            show_log: env.run.show_log,
            peer,
            cancel: cancel.clone(),
        });
        tokio::spawn(async move { handle_inbound(ctx, inbound).await });
    }
}

enum FailureKind {
    Probe,
    Bind,
}

// ══════════════════════════════════════════════════════════════════════════
// 入站转发
// ══════════════════════════════════════════════════════════════════════════

/// 一条入站连接的上下文。
struct ConnCtx {
    tunnel: Arc<Tunnel>,
    log: Arc<LogBuffer>,
    instance_id: String,
    instance_name: String,
    target: u16,
    proxy_protocol: bool,
    show_log: bool,
    peer: SocketAddr,
    cancel: CancellationToken,
}

impl ConnCtx {
    fn log(&self, text: impl Into<String>) {
        if self.show_log {
            self.log
                .add(Some((&self.instance_id, &self.instance_name)), text);
        }
    }
}

/// 连接计数与断开日志的守卫（任何退出路径都会还账）。
struct ConnGuard(Arc<ConnCtx>);

impl Drop for ConnGuard {
    fn drop(&mut self) {
        self.0.tunnel.stats.active.fetch_sub(1, Ordering::Relaxed);
        self.0.log(format!("断开连接 {}", self.0.peer));
    }
}

/// 处理一条入站连接：连本地服务端口，双向转发（V1 `_handleInbound`）。
async fn handle_inbound(ctx: Arc<ConnCtx>, inbound: TcpStream) {
    let guard = ConnGuard(ctx.clone());
    let _ = inbound.set_nodelay(true);
    let Ok(local) = inbound.local_addr() else {
        return;
    };
    guard.0.log(format!("入站连接 {}", guard.0.peer));

    let backend = tokio::time::timeout(
        Duration::from_secs(5),
        TcpStream::connect(("127.0.0.1", guard.0.target)),
    )
    .await;
    let mut backend = match backend {
        Ok(Ok(stream)) => stream,
        Ok(Err(e)) => {
            guard.0.log(format!("{} 转发失败：{e}", guard.0.peer));
            return;
        }
        Err(_) => {
            guard
                .0
                .log(format!("{} 转发失败：连接本地端口超时", guard.0.peer));
            return;
        }
    };
    let _ = backend.set_nodelay(true);

    if guard.0.proxy_protocol {
        // PROXY protocol v2：让服务端拿到玩家真实 IP（需服务端开启对应支持）。
        if let Err(e) = backend
            .write_all(&proxy::build_header(guard.0.peer, local))
            .await
        {
            guard.0.log(format!("{} 转发失败：{e}", guard.0.peer));
            return;
        }
    }

    let (mut inbound_read, mut inbound_write) = inbound.into_split();
    let (mut backend_read, mut backend_write) = backend.into_split();

    // 单向搬运并计流量。上行 = 服务端发给玩家；下行 = 玩家发给服务端（V1 口径）。
    let outcome: std::io::Result<()> = tokio::select! {
        biased;
        res = pump(
            &mut inbound_read,
            &mut backend_write,
            &guard.0.tunnel.stats.total_down,
            &guard.0.cancel,
        ) => res,
        res = pump(
            &mut backend_read,
            &mut inbound_write,
            &guard.0.tunnel.stats.total_up,
            &guard.0.cancel,
        ) => res,
    };
    if let Err(e) = outcome {
        guard.0.log(format!("{} 转发失败：{e}", guard.0.peer));
    }
}

/// 单向搬运数据并计流量；被取消时干净退出。
async fn pump<R, W>(
    reader: &mut R,
    writer: &mut W,
    counter: &AtomicU64,
    cancel: &CancellationToken,
) -> std::io::Result<()>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut buf = vec![0u8; 16 * 1024];
    loop {
        tokio::select! {
            biased;
            _ = cancel.cancelled() => return Ok(()),
            res = reader.read(&mut buf) => {
                let n = res?;
                if n == 0 {
                    return Ok(());
                }
                counter.fetch_add(n as u64, Ordering::Relaxed);
                writer.write_all(&buf[..n]).await?;
            }
        }
    }
}

/// 把监听套接字绑到打洞用的本地端口。
///
/// 能成功的前提：nyat 的探测套接字设了 `SO_REUSEADDR` + `SO_REUSEPORT`，
/// 这里也必须设上（Linux/macOS 上「非监听套接字 + 监听套接字」共存的经典
/// 技巧；Windows 语义不同，以 Linux/macOS 为准 —— V1 也只有 Linux/Android
/// 的结论）。
fn bind_listener(port: u16) -> std::io::Result<TcpListener> {
    use socket2::{Domain, Protocol, Socket, Type};

    let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true)?;
    socket.set_nonblocking(true)?;
    socket.bind(&SocketAddr::from((Ipv4Addr::UNSPECIFIED, port)).into())?;
    socket.listen(1024)?;
    TcpListener::from_std(socket.into())
}
