//! 系统监控模块：设备内存与整机 CPU 使用率。
//!
//! 采集交给 [`sysinfo`]（跨平台，Linux / Windows / macOS 都不用自己读 `/proc`
//! 或写平台 FFI），模块自己只负责三件事：**采样节奏**、**缓存**、**把「读不到」说明白**。
//!
//! # 字段语义
//!
//! `total_mem_mb` / `used_mem_mb` / `available_mem_mb` / `cpu_usage` /
//! `server_mem_mb`。内存单位一律 MB，`cpu_usage` 是百分数。
//!
//! 三处刻意的取舍：
//!
//! 1. **拿不到可信值时是 `null`，不是 `-1`**：线上格式里 `null` 更直白，
//!    前端判空即可，不必再约定哨兵值。
//! 2. **`server_mem_mb` 恒为 `null`** —— 读它要服务端进程的 RSS，属于进程管理模块。
//!    这和 `instance.status.process_managed = false` 是同一件事，模块落地前不编造数字。
//! 3. **CPU 用真使用率**：用 sysinfo 的
//!    [`System::global_cpu_usage`]（两次采样之间的差值）。
//!
//! # 采样器为什么常驻
//!
//! `ticker` 模块有 `autostart` 开关，本模块**没有**：
//!
//! * CPU 使用率必须**连续两次采样**才有意义（第一次的窗口是「进程启动至今」），
//!   按需采样会让每次冷启动后的第一次调用必然是 `null`；常驻采样换来的是
//!   `monitor.snapshot` 随时都有一份有意义的读数。
//! * 一次采样的成本就是几个系统调用，用 [`MonitorConfig::interval_ms`] 调成本即可。
//!
//! `monitor.stats` 事件按 [`MonitorConfig::publish`] 决定推不推；没订阅的连接本来
//! 也收不到，所以默认开着。

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use axum::extract::State;
use axum::routing::get;
use axum::{Router, response::Response};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sysinfo::{CpuRefreshKind, MemoryRefreshKind, RefreshKind, System};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::error::Result;
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::server::http::api_result;
use crate::state::AppState;
use crate::util::now_ms;

/// 唯一的推送主题：一份完整快照，间隔由配置决定。
const TOPIC_STATS: &str = "monitor.stats";

/// 采样间隔下限（毫秒）。
///
/// 取 250 而不是更小，是因为 sysinfo 的 CPU 使用率靠两次采样的差值算，
/// 而它自己的 `MINIMUM_CPU_UPDATE_INTERVAL` 是 200ms —— 比它还密只会读到
/// 上一次的旧值，白烧 CPU。
const MIN_INTERVAL_MS: u64 = 250;
/// 采样间隔上限（毫秒）：一分钟。
const MAX_INTERVAL_MS: u64 = 60_000;
const DEFAULT_INTERVAL_MS: u64 = 2_000;

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// `[modules.config.monitor]`
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct MonitorConfig {
    /// 采样间隔（也是推送间隔），毫秒，会被 clamp 到 [250, 60000]。
    pub interval_ms: u64,
    /// 是否周期性推送 `monitor.stats`。
    ///
    /// 关掉只是不推事件，采样照旧 —— `monitor.snapshot` 读的是缓存，
    /// 关了推送就等于「只拉不推」。
    pub publish: bool,
}

impl Default for MonitorConfig {
    fn default() -> Self {
        Self {
            interval_ms: DEFAULT_INTERVAL_MS,
            publish: true,
        }
    }
}

impl MonitorConfig {
    fn clamped_interval(&self) -> u64 {
        self.interval_ms.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
    }
}

// ---------------------------------------------------------------------------
// 快照
// ---------------------------------------------------------------------------

/// 一次系统状态快照。
///
/// 字段名就是线上格式（daemon 侧统一 snake_case）。
#[derive(Debug, Clone, Serialize)]
pub struct Snapshot {
    /// 采样时刻（Unix 毫秒）。
    pub sampled_at_ms: u64,
    /// 当前采样间隔，方便前端算出「这份数据最旧能有多旧」。
    pub interval_ms: u64,
    /// 当前平台是否支持采集。不支持时后面的数字全是 0 / null。
    pub supported: bool,

    /// 设备总物理内存（MB）。
    pub total_mem_mb: u64,
    /// 设备已用内存（MB）。口径是 `total - available`。
    pub used_mem_mb: u64,
    /// 设备可用内存（MB）。
    pub available_mem_mb: u64,
    /// 已用内存占比（0–100）。
    pub used_mem_percent: f64,

    /// 整机 CPU 使用率（0–100）；`null` = 还没有可信值（进程刚起来）或平台不支持。
    pub cpu_usage: Option<f64>,
    /// 逻辑核数。
    pub cpu_cores: usize,

    /// 服务端进程的内存占用（MB）。
    ///
    /// **恒为 `null`**：要读进程 RSS，属于进程管理模块，那个模块还没接进来。
    pub server_mem_mb: Option<u64>,
}

impl Snapshot {
    fn to_json(&self) -> Value {
        serde_json::to_value(self).unwrap_or(Value::Null)
    }
}

/// 字节 → MB。
fn bytes_to_mb(bytes: u64) -> u64 {
    bytes / 1024 / 1024
}

// ---------------------------------------------------------------------------
// 模块状态
// ---------------------------------------------------------------------------

/// 采样器的可变状态。
///
/// `System` 放在锁里：一来 CPU 使用率靠内部保存的上一次计数算差值，
/// 二来 tokio 的 `Mutex` 要求 `T: Send` 就够了，不用去赌 `System` 是不是 `Sync`。
struct Inner {
    sys: System,
    /// 最近一次快照；`None` = 还没采过。
    latest: Option<Snapshot>,
    /// 是否已经有过一次「基准」采样 —— 第一次 refresh 出来的 CPU 值不可信。
    cpu_ready: bool,
}

struct MonitorState {
    inner: Mutex<Inner>,
    interval_ms: AtomicU64,
    publish: AtomicBool,
    /// 一共采了多少次。
    samples: AtomicU64,
    /// 采样器启动时刻（Unix 毫秒）；0 = 没在跑。
    started_at_ms: AtomicU64,
    /// 当前循环任务的句柄与取消令牌；`None` = 没在跑。
    task: Mutex<Option<Running>>,
}

struct Running {
    cancel: CancellationToken,
    join: JoinHandle<()>,
}

impl MonitorState {
    fn new(interval_ms: u64, publish: bool) -> Self {
        Self {
            inner: Mutex::new(Inner {
                sys: System::new_with_specifics(
                    RefreshKind::nothing()
                        .with_memory(MemoryRefreshKind::nothing().with_ram())
                        .with_cpu(CpuRefreshKind::nothing().with_cpu_usage()),
                ),
                latest: None,
                cpu_ready: false,
            }),
            interval_ms: AtomicU64::new(interval_ms.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)),
            publish: AtomicBool::new(publish),
            samples: AtomicU64::new(0),
            started_at_ms: AtomicU64::new(0),
            task: Mutex::new(None),
        }
    }

    /// 采一次并更新缓存。调用方必须已持有 `inner` 的锁。
    ///
    /// 成本是几个系统调用（Linux 上读 `/proc/meminfo` 与 `/proc/stat`），
    /// 所以直接在当前线程做，不往 `spawn_blocking` 里扔。
    fn sample_locked(inner: &mut Inner, interval_ms: u64) -> Snapshot {
        inner.sys.refresh_memory();
        inner.sys.refresh_cpu_usage();

        // 第一次刷新的窗口是「进程启动至今」（甚至 0），拿它当使用率是胡扯。
        // 第一次如实报 null，第二次开始才是真读数。
        let cpu_usage = if inner.cpu_ready {
            Some(f64::from(inner.sys.global_cpu_usage()).clamp(0.0, 100.0))
        } else {
            None
        };
        inner.cpu_ready = true;

        let total = inner.sys.total_memory();
        let used = inner.sys.used_memory();
        let available = inner.sys.available_memory();
        let used_mem_percent = if total > 0 {
            (used as f64 / total as f64) * 100.0
        } else {
            0.0
        };

        let snapshot = Snapshot {
            sampled_at_ms: now_ms(),
            interval_ms,
            supported: sysinfo::IS_SUPPORTED_SYSTEM,
            total_mem_mb: bytes_to_mb(total),
            used_mem_mb: bytes_to_mb(used),
            available_mem_mb: bytes_to_mb(available),
            used_mem_percent,
            cpu_usage,
            cpu_cores: std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(0),
            // 进程管理模块接进来之前不编造数字，见模块文档。
            server_mem_mb: None,
        };
        inner.latest = Some(snapshot.clone());
        snapshot
    }

    /// 取一份快照。没采过就现场采一次（正常不会走到：采样器在 `start` 里就起了）。
    async fn snapshot(&self) -> Snapshot {
        let interval_ms = self.interval_ms.load(Ordering::Relaxed);
        let mut inner = self.inner.lock().await;
        if let Some(latest) = &inner.latest {
            return latest.clone();
        }
        self.samples.fetch_add(1, Ordering::Relaxed);
        Self::sample_locked(&mut inner, interval_ms)
    }

    async fn status_json(&self, running: bool) -> Value {
        let inner = self.inner.lock().await;
        let latest = inner
            .latest
            .as_ref()
            .map(|s| (s.sampled_at_ms, s.cpu_usage.is_some()));
        drop(inner);

        let started = self.started_at_ms.load(Ordering::Relaxed);
        json!({
            "running": running,
            "supported": sysinfo::IS_SUPPORTED_SYSTEM,
            "interval_ms": self.interval_ms.load(Ordering::Relaxed),
            "min_interval_ms": MIN_INTERVAL_MS,
            "max_interval_ms": MAX_INTERVAL_MS,
            "publish": self.publish.load(Ordering::Relaxed),
            "samples": self.samples.load(Ordering::Relaxed),
            "started_at_ms": started,
            "uptime_ms": if started == 0 { 0 } else { now_ms().saturating_sub(started) },
            "last_sampled_at_ms": latest.map(|(ts, _)| ts),
            "cpu_ready": latest.map(|(_, ready)| ready).unwrap_or(false),
        })
    }

    /// 起采样循环。已在跑就先停掉再起 —— 这样重复调用（以及将来的热改配置）都安全。
    async fn start_loop(self: &Arc<Self>, app: AppState, config: &MonitorConfig) -> Result<()> {
        let interval_ms = config.clamped_interval();
        self.publish.store(config.publish, Ordering::Relaxed);

        // 先停旧的，避免出现两个采样器同时写 `latest`
        self.stop_loop(None).await;

        let cancel = CancellationToken::new();
        let join = tokio::spawn(run_loop(
            self.clone(),
            app.clone(),
            interval_ms,
            cancel.clone(),
        ));

        let mut guard = self.task.lock().await;
        *guard = Some(Running { cancel, join });
        drop(guard);

        self.interval_ms.store(interval_ms, Ordering::Relaxed);
        self.started_at_ms.store(now_ms(), Ordering::Relaxed);

        tracing::info!(
            interval_ms,
            publish = config.publish,
            supported = sysinfo::IS_SUPPORTED_SYSTEM,
            "系统监控采样器已启动"
        );
        Ok(())
    }

    /// 停循环。返回是否真的停掉了（本来没跑则 false）。
    async fn stop_loop(&self, app: Option<&AppState>) -> bool {
        let taken = {
            let mut guard = self.task.lock().await;
            guard.take()
        };

        let Some(Running { cancel, join }) = taken else {
            return false;
        };

        cancel.cancel();
        // 等任务真正退出，保证 stop 返回后不会再有 monitor.stats。
        if let Err(e) = join.await
            && e.is_panic()
        {
            tracing::error!(error = %e, "系统监控采样任务 panic");
        }

        self.started_at_ms.store(0, Ordering::Relaxed);
        if let Some(app) = app {
            tracing::debug!(
                subscribers = app.bus.subscriber_count(),
                "系统监控采样器已停止"
            );
        }
        true
    }
}

/// 采样循环。取消令牌触发即退出。
async fn run_loop(
    state: Arc<MonitorState>,
    app: AppState,
    interval_ms: u64,
    cancel: CancellationToken,
) {
    let mut ticker = tokio::time::interval(Duration::from_millis(interval_ms));
    // 上一轮慢了就顺延，不追着补发一串。
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = ticker.tick() => {
                let snapshot = {
                    let mut inner = state.inner.lock().await;
                    state.samples.fetch_add(1, Ordering::Relaxed);
                    MonitorState::sample_locked(&mut inner, interval_ms)
                };
                if state.publish.load(Ordering::Relaxed) {
                    app.bus.publish_from(Some("monitor"), TOPIC_STATS, snapshot.to_json());
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct MonitorModule {
    state: Arc<MonitorState>,
}

impl MonitorModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(MonitorState::new(DEFAULT_INTERVAL_MS, true)),
        }
    }
}

impl Default for MonitorModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for MonitorModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("monitor", "系统监控", env!("CARGO_PKG_VERSION"))
            .description("设备内存与整机 CPU 使用率：常驻采样 + 随时可取的快照，支持周期性推送。")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(
            TOPIC_STATS,
            "系统状态快照（间隔由 monitor.interval_ms 决定）",
        );

        // ---- WS 方法 ----
        {
            let state = self.state.clone();
            reg.method(
                "monitor.snapshot",
                "取一份系统状态快照",
                move |_ctx| {
                    let state = state.clone();
                    async move { ok(state.snapshot().await.to_json()) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method("monitor.status", "查看采样器状态", move |_ctx| {
                let state = state.clone();
                async move {
                    let running = state.task.lock().await.is_some();
                    ok(state.status_json(running).await)
                }
            });
        }

        // ---- HTTP 路由 ----
        reg.router("api/monitor", self.http_router());
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: MonitorConfig = env.config()?;
        self.state.start_loop(env.app.clone(), &config).await
    }

    async fn stop(&self) -> Result<()> {
        self.state.stop_loop(None).await;
        Ok(())
    }
}

impl MonitorModule {
    /// 与 WS 方法共用同一份状态的 HTTP 接口。
    fn http_router(&self) -> Router<AppState> {
        let snapshot = {
            let state = self.state.clone();
            move |_app: State<AppState>| {
                let state = state.clone();
                async move {
                    let response: Response = api_result(Ok(state.snapshot().await.to_json()));
                    response
                }
            }
        };

        let status = {
            let state = self.state.clone();
            move |_app: State<AppState>| {
                let state = state.clone();
                async move {
                    let running = state.task.lock().await.is_some();
                    // 和 `/api/monitor` 一样走 api_result：同一个模块的两个路由
                    // 响应形状要一致（`{ok, result}`），别一半带信封一半不带。
                    let response: Response = api_result(Ok(state.status_json(running).await));
                    response
                }
            }
        };

        Router::new()
            .route("/api/monitor", get(snapshot))
            .route("/api/monitor/status", get(status))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::CallCtx;
    use crate::module::registry::ModuleRegistry;

    /// 造一个带指定 monitor 配置节的 AppState。
    fn app_with(section: Option<&str>) -> AppState {
        let mut config = Config::default();
        if let Some(text) = section {
            config
                .modules
                .config
                .insert("monitor".into(), toml::from_str(text).unwrap());
        }
        let registry =
            Arc::new(ModuleRegistry::build(vec![Arc::new(MonitorModule::new())], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    fn ctx(app: &AppState, method: &str) -> CallCtx {
        CallCtx {
            app: app.clone(),
            module: "monitor".into(),
            method: method.into(),
            params: json!({}),
            conn_id: 1,
            peer: "127.0.0.1:1".into(),
            is_local: true,
        }
    }

    #[test]
    fn config_defaults_and_clamping() {
        let c = MonitorConfig::default();
        assert_eq!(c.clamped_interval(), DEFAULT_INTERVAL_MS);
        assert!(c.publish);

        assert_eq!(
            MonitorConfig {
                interval_ms: 1,
                publish: true
            }
            .clamped_interval(),
            MIN_INTERVAL_MS
        );
        assert_eq!(
            MonitorConfig {
                interval_ms: u64::MAX,
                publish: true
            }
            .clamped_interval(),
            MAX_INTERVAL_MS
        );
    }

    #[test]
    fn module_env_reads_own_section() {
        let env = ModuleEnv {
            app: app_with(None),
            config: Some(toml::from_str("interval_ms = 500\npublish = false").unwrap()),
        };
        let c: MonitorConfig = env.config().unwrap();
        assert_eq!(c.clamped_interval(), 500);
        assert!(!c.publish);

        let env = ModuleEnv {
            app: app_with(Some("interval_ms = 500")),
            config: None,
        };
        let c: MonitorConfig = env.config().unwrap();
        assert_eq!(c.clamped_interval(), DEFAULT_INTERVAL_MS);
    }

    /// 配置写错字段名必须报错，而不是静默走默认值。
    #[test]
    fn misspelled_config_field_is_rejected() {
        let env = ModuleEnv {
            app: app_with(None),
            config: Some(toml::from_str("intervall_ms = 500").unwrap()),
        };
        assert!(env.config::<MonitorConfig>().is_err());
    }

    /// 采样出来的数字要自洽：used + available ≈ total，占比落在 0–100。
    #[tokio::test]
    async fn snapshot_numbers_are_consistent() {
        let state = MonitorState::new(DEFAULT_INTERVAL_MS, false);
        let snap = state.snapshot().await;

        assert_eq!(snap.supported, sysinfo::IS_SUPPORTED_SYSTEM);
        assert!(snap.interval_ms >= MIN_INTERVAL_MS);
        assert!(snap.sampled_at_ms > 0);
        assert!(snap.cpu_cores >= 1, "逻辑核数不该是 0");
        assert!(snap.server_mem_mb.is_none(), "进程模块没接入，必须是 null");

        if sysinfo::IS_SUPPORTED_SYSTEM {
            assert!(snap.total_mem_mb > 0, "读不到总内存说明平台适配有问题");
            assert!(snap.used_mem_mb + snap.available_mem_mb <= snap.total_mem_mb + 1);
            assert!((0.0..=100.0).contains(&snap.used_mem_percent));
        }
    }

    /// 第一次采样没有可信的 CPU 值（sysinfo 靠两次差值算），第二次才有。
    ///
    /// 直接调 `sample_locked` 而不是 `snapshot()`：后者读的是缓存（这是它该有的语义），
    /// 连着调两次只会拿到同一份。
    #[tokio::test]
    async fn cpu_is_null_on_first_sample_then_available() {
        let mut inner = Inner {
            sys: System::new_with_specifics(
                RefreshKind::nothing()
                    .with_memory(MemoryRefreshKind::nothing().with_ram())
                    .with_cpu(CpuRefreshKind::nothing().with_cpu_usage()),
            ),
            latest: None,
            cpu_ready: false,
        };

        let first = MonitorState::sample_locked(&mut inner, DEFAULT_INTERVAL_MS);
        assert!(
            first.cpu_usage.is_none(),
            "第一次采样的窗口是「进程启动至今」，不该报数"
        );
        assert_eq!(first.interval_ms, DEFAULT_INTERVAL_MS);

        // 等到 sysinfo 的最小更新间隔之后再来一次
        tokio::time::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL).await;
        let second = MonitorState::sample_locked(&mut inner, DEFAULT_INTERVAL_MS);

        if sysinfo::IS_SUPPORTED_SYSTEM {
            let usage = second.cpu_usage.expect("第二次应当有可信读数");
            assert!((0.0..=100.0).contains(&usage), "使用率越界: {usage}");
        }
        // 缓存也要跟着更新
        assert_eq!(
            inner.latest.as_ref().map(|s| s.sampled_at_ms),
            Some(second.sampled_at_ms)
        );
    }

    /// `monitor.snapshot` 读的是缓存，不重新采样 —— 多个客户端轮询同一个方法时
    /// 不该把采集成本乘上去。
    #[tokio::test]
    async fn snapshot_serves_the_cache() {
        let state = MonitorState::new(DEFAULT_INTERVAL_MS, false);

        let first = state.snapshot().await;
        let second = state.snapshot().await;
        assert_eq!(
            first.sampled_at_ms, second.sampled_at_ms,
            "两次调用应当拿到同一份缓存"
        );
        assert_eq!(state.samples.load(Ordering::Relaxed), 1, "只该现场采一次");
    }

    #[tokio::test]
    async fn start_then_stop_is_idempotent_safe() {
        let module = MonitorModule::new();
        let app = app_with(None);

        module
            .state
            .start_loop(
                app.clone(),
                &MonitorConfig {
                    interval_ms: MIN_INTERVAL_MS,
                    publish: false,
                },
            )
            .await
            .unwrap();
        assert!(module.state.task.lock().await.is_some());

        // 重复启动：不该炸。`start_loop` 内部会先 `stop_loop(None)` 并 await 旧任务的
        // JoinHandle，所以返回时能确定只剩这一个采样器。
        module
            .state
            .start_loop(
                app.clone(),
                &MonitorConfig {
                    interval_ms: 400,
                    publish: false,
                },
            )
            .await
            .unwrap();
        assert_eq!(
            module.state.interval_ms.load(Ordering::Relaxed),
            400,
            "新配置应当生效，说明是新的循环在跑"
        );

        tokio::time::sleep(Duration::from_millis(900)).await;
        assert!(
            module.state.samples.load(Ordering::Relaxed) >= 2,
            "常驻采样器应该已经采了不止一次"
        );

        assert!(module.state.stop_loop(Some(&app)).await);
        assert!(!module.state.stop_loop(Some(&app)).await, "已经停了");
        assert!(module.state.task.lock().await.is_none());
    }

    #[tokio::test]
    async fn loop_stops_promptly_on_cancel() {
        let module = MonitorModule::new();
        let app = app_with(None);
        module
            .state
            .start_loop(
                app.clone(),
                &MonitorConfig {
                    interval_ms: MIN_INTERVAL_MS,
                    publish: false,
                },
            )
            .await
            .unwrap();

        tokio::time::sleep(Duration::from_millis(400)).await;
        let before = module.state.samples.load(Ordering::Relaxed);

        module.state.stop_loop(Some(&app)).await;
        tokio::time::sleep(Duration::from_millis(400)).await;
        assert_eq!(
            module.state.samples.load(Ordering::Relaxed),
            before,
            "stop 返回后不该再采样"
        );
    }

    #[tokio::test]
    async fn stats_are_pushed_to_subscribers() {
        let module = MonitorModule::new();
        let app = app_with(None);
        let mut rx = app.bus.subscribe();

        module
            .state
            .start_loop(
                app.clone(),
                &MonitorConfig {
                    interval_ms: MIN_INTERVAL_MS,
                    publish: true,
                },
            )
            .await
            .unwrap();

        let event = tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                let e = rx.recv().await.expect("事件总线不该关闭");
                if e.topic == TOPIC_STATS {
                    break e;
                }
            }
        })
        .await
        .expect("应该收到 monitor.stats");

        assert_eq!(event.source.as_deref(), Some("monitor"));
        assert!(event.data.get("total_mem_mb").is_some());
        assert!(event.data.get("cpu_usage").is_some());

        module.state.stop_loop(Some(&app)).await;
    }

    /// `publish = false` 时只采不推。
    #[tokio::test]
    async fn publish_can_be_disabled() {
        let module = MonitorModule::new();
        let app = app_with(None);
        let mut rx = app.bus.subscribe();

        module
            .state
            .start_loop(
                app.clone(),
                &MonitorConfig {
                    interval_ms: MIN_INTERVAL_MS,
                    publish: false,
                },
            )
            .await
            .unwrap();

        // 这段时间足够推两三次了
        tokio::time::sleep(Duration::from_millis(800)).await;
        module.state.stop_loop(Some(&app)).await;

        assert!(
            module.state.samples.load(Ordering::Relaxed) >= 2,
            "采样照旧进行"
        );
        while let Ok(e) = rx.try_recv() {
            assert_ne!(e.topic, TOPIC_STATS, "publish=false 不该推事件");
        }
    }

    /// 模块生命周期：`start` 起采样器，`stop_all` 收掉它。
    #[tokio::test]
    async fn module_lifecycle_starts_and_stops_sampler() {
        let module = Arc::new(MonitorModule::new());
        let mut config = Config::default();
        config.modules.config.insert(
            "monitor".into(),
            toml::from_str("interval_ms = 250\npublish = false").unwrap(),
        );
        let registry = Arc::new(ModuleRegistry::build(vec![module.clone()], &config).unwrap());
        let app = AppState::new(config, None, registry.clone(), CancellationToken::new());

        registry.start_all(&app).await.unwrap();
        assert!(module.state.task.lock().await.is_some(), "start 应起采样器");
        assert_eq!(module.state.interval_ms.load(Ordering::Relaxed), 250);

        registry.stop_all().await;
        assert!(
            module.state.task.lock().await.is_none(),
            "stop 应收掉采样器"
        );
    }

    #[tokio::test]
    async fn registered_methods_are_dispatchable() {
        let module = Arc::new(MonitorModule::new());
        let registry = Arc::new(ModuleRegistry::build(vec![module], &Config::default()).unwrap());
        let app = AppState::new(
            Config::default(),
            None,
            registry.clone(),
            CancellationToken::new(),
        );

        let snap = registry
            .dispatch(ctx(&app, "monitor.snapshot"))
            .await
            .unwrap();
        assert!(snap.get("total_mem_mb").is_some());
        assert_eq!(snap["server_mem_mb"], json!(null));
        assert_eq!(snap["interval_ms"], json!(DEFAULT_INTERVAL_MS));

        let status = registry
            .dispatch(ctx(&app, "monitor.status"))
            .await
            .unwrap();
        assert_eq!(status["running"], json!(false));
        assert_eq!(status["min_interval_ms"], json!(MIN_INTERVAL_MS));
        assert_eq!(status["publish"], json!(true));
    }

    #[test]
    fn descriptor_is_stable() {
        let d = MonitorModule::new().descriptor();
        assert_eq!(d.id, "monitor");
        assert!(!d.always_on);
    }
}
