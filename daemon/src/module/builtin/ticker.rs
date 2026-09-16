//! 定时器模块 —— **示例模块模板**。
//!
//! 一个文件里覆盖了模块能做的全部事情，加新模块照抄这个结构即可：
//!
//! | 能力 | 本模块里对应位置 |
//! | --- | --- |
//! | 读自己的配置节 | [`TickerConfig`] + `[modules.config.ticker]` |
//! | 注册 WS 方法 | `ticker.status/start/stop/publish` |
//! | 挂 HTTP 路由 | `GET /api/ticker`、`POST /api/ticker/start|stop` |
//! | 声明事件主题 | `ticker.tick` / `ticker.started` / `ticker.stopped` |
//! | 起后台任务 | [`TickerState::start_loop`] |
//! | 优雅停止 | `Module::stop` → [`TickerState::stop_loop`] |
//!
//! 业务逻辑本身很无聊（每 N 毫秒推一条事件），正因为无聊才适合当模板。

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use axum::Json;
use axum::extract::State;
use axum::routing::{get, post};
use axum::{Router, response::Response};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::error::{Result, RpcError, RpcResult};
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::server::http::api_result;
use crate::state::AppState;
use crate::util::now_ms;

/// 事件主题。
const TOPIC_TICK: &str = "ticker.tick";
const TOPIC_STARTED: &str = "ticker.started";
const TOPIC_STOPPED: &str = "ticker.stopped";

/// 间隔下限：再密就是压力测试而不是定时器了。
const MIN_INTERVAL_MS: u64 = 50;
/// 间隔上限：一天。
const MAX_INTERVAL_MS: u64 = 86_400_000;
const DEFAULT_INTERVAL_MS: u64 = 1000;

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// `[modules.config.ticker]`
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TickerConfig {
    /// 触发间隔（毫秒），会被 clamp 到 [50, 86400000]。
    pub interval_ms: u64,
    /// 服务启动后自动开跑。
    pub autostart: bool,
}

impl Default for TickerConfig {
    fn default() -> Self {
        Self {
            interval_ms: DEFAULT_INTERVAL_MS,
            autostart: false,
        }
    }
}

impl TickerConfig {
    fn clamped_interval(&self) -> u64 {
        self.interval_ms.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
    }
}

// ---------------------------------------------------------------------------
// 模块状态
// ---------------------------------------------------------------------------

/// 运行时状态。整个模块只有这一份，通过 `Arc` 在方法处理器、HTTP
/// 处理器和后台任务之间共享。
#[derive(Default)]
struct TickerState {
    interval_ms: AtomicU64,
    ticks: AtomicU64,
    running: AtomicBool,
    /// 当前循环任务的句柄与取消令牌；`None` = 没在跑。
    task: Mutex<Option<Running>>,
}

struct Running {
    cancel: CancellationToken,
    join: JoinHandle<()>,
}

impl TickerState {
    fn status_json(&self) -> Value {
        json!({
            "running": self.running.load(Ordering::Relaxed),
            "ticks": self.ticks.load(Ordering::Relaxed),
            "interval_ms": self.interval_ms.load(Ordering::Relaxed),
            "min_interval_ms": MIN_INTERVAL_MS,
            "max_interval_ms": MAX_INTERVAL_MS,
        })
    }

    /// 起循环。已在跑则报错，避免出现两个定时器。
    async fn start_loop(self: &Arc<Self>, app: AppState, interval_ms: u64) -> RpcResult<Value> {
        let interval_ms = interval_ms.clamp(MIN_INTERVAL_MS, MAX_INTERVAL_MS);

        let mut guard = self.task.lock().await;
        if guard.is_some() {
            return Err(RpcError::new("already_running", "定时器已经在运行了"));
        }

        let cancel = CancellationToken::new();
        let join = tokio::spawn(run_loop(
            self.clone(),
            app.clone(),
            interval_ms,
            cancel.clone(),
        ));

        *guard = Some(Running { cancel, join });
        self.interval_ms.store(interval_ms, Ordering::Relaxed);
        self.running.store(true, Ordering::Relaxed);
        drop(guard);

        app.bus.publish_from(
            Some("ticker"),
            TOPIC_STARTED,
            json!({ "interval_ms": interval_ms, "ts": now_ms() }),
        );
        tracing::info!(interval_ms, "定时器已启动");

        Ok(self.status_json())
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
        // 等任务真正退出，保证 stop 返回后不会再有 tick 事件。
        if let Err(e) = join.await
            && e.is_panic()
        {
            tracing::error!(error = %e, "定时器任务 panic");
        }

        self.running.store(false, Ordering::Relaxed);
        if let Some(app) = app {
            app.bus.publish_from(
                Some("ticker"),
                TOPIC_STOPPED,
                json!({ "ticks": self.ticks.load(Ordering::Relaxed), "ts": now_ms() }),
            );
        }
        tracing::info!("定时器已停止");
        true
    }
}

/// 后台循环。取消令牌触发即退出，不吞事件。
async fn run_loop(
    state: Arc<TickerState>,
    app: AppState,
    interval_ms: u64,
    cancel: CancellationToken,
) {
    let mut ticker = tokio::time::interval(Duration::from_millis(interval_ms));
    // 上一轮处理慢了就顺延，不要追着补发一串。
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = ticker.tick() => {
                let n = state.ticks.fetch_add(1, Ordering::Relaxed) + 1;
                app.bus.publish_from(
                    Some("ticker"),
                    TOPIC_TICK,
                    json!({ "n": n, "interval_ms": interval_ms, "ts": now_ms() }),
                );
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct TickerModule {
    state: Arc<TickerState>,
}

impl TickerModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(TickerState::default()),
        }
    }
}

impl Default for TickerModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for TickerModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("ticker", "定时器", env!("CARGO_PKG_VERSION"))
            .description("示例模块：按固定间隔推送事件，演示配置/HTTP/WS/后台任务的完整写法。")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(TOPIC_TICK, "定时器每次触发");
        reg.topic(TOPIC_STARTED, "定时器启动");
        reg.topic(TOPIC_STOPPED, "定时器停止");

        // ---- WS 方法 ----
        {
            let state = self.state.clone();
            reg.method("ticker.status", "查看定时器状态", move |_ctx| {
                let state = state.clone();
                async move { ok(state.status_json()) }
            });
        }
        {
            let state = self.state.clone();
            reg.method(
                "ticker.start",
                "启动定时器（可选参数 interval_ms）",
                move |ctx| {
                    let state = state.clone();
                    async move {
                        let default = state.interval_ms.load(Ordering::Relaxed);
                        let interval_ms = ctx.param_or("interval_ms", default)?;
                        state.start_loop(ctx.app.clone(), interval_ms).await
                    }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method("ticker.stop", "停止定时器", move |ctx| {
                let state = state.clone();
                async move {
                    let stopped = state.stop_loop(Some(&ctx.app)).await;
                    ok(json!({ "stopped": stopped, "status": state.status_json() }))
                }
            });
        }
        {
            let state = self.state.clone();
            reg.method("ticker.publish", "立刻手动推一次 tick", move |ctx| {
                let state = state.clone();
                async move {
                    let n = state.ticks.fetch_add(1, Ordering::Relaxed) + 1;
                    let seq = ctx.publish(
                        TOPIC_TICK,
                        json!({ "n": n, "manual": true, "ts": now_ms() }),
                    );
                    ok(json!({ "seq": seq, "n": n }))
                }
            });
        }

        // ---- HTTP 路由 ----
        reg.router("api/ticker", self.http_router());
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: TickerConfig = env.config()?;
        tracing::info!(
            interval_ms = config.clamped_interval(),
            autostart = config.autostart,
            "ticker 模块已加载"
        );
        if config.autostart {
            // 后台任务失败不该拖垮启动，这里只记日志。
            if let Err(e) = self
                .state
                .start_loop(env.app.clone(), config.clamped_interval())
                .await
            {
                tracing::warn!(error = %e, "ticker 自动启动失败");
            }
        }
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        self.state.stop_loop(None).await;
        Ok(())
    }
}

impl TickerModule {
    /// 与 WS 方法共用同一份状态的 HTTP 接口。
    fn http_router(&self) -> Router<AppState> {
        let status = {
            let state = self.state.clone();
            move |_app: State<AppState>| {
                let state = state.clone();
                async move { Json(state.status_json()) }
            }
        };

        let start = {
            let state = self.state.clone();
            move |app: State<AppState>, body: Option<Json<StartBody>>| {
                let state = state.clone();
                async move {
                    let interval = body
                        .and_then(|Json(b)| b.interval_ms)
                        .unwrap_or_else(|| state.interval_ms.load(Ordering::Relaxed));
                    let response: Response =
                        api_result(state.start_loop(app.0.clone(), interval).await);
                    response
                }
            }
        };

        let stop = {
            let state = self.state.clone();
            move |app: State<AppState>| {
                let state = state.clone();
                async move {
                    let stopped = state.stop_loop(Some(&app.0)).await;
                    Json(json!({ "stopped": stopped, "status": state.status_json() }))
                }
            }
        };

        Router::new()
            .route("/api/ticker", get(status))
            .route("/api/ticker/start", post(start))
            .route("/api/ticker/stop", post(stop))
    }
}

#[derive(Debug, Deserialize)]
struct StartBody {
    interval_ms: Option<u64>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::CallCtx;
    use crate::module::registry::ModuleRegistry;

    /// 造一个带指定 ticker 配置节的 AppState。
    fn app_with(section: Option<&str>) -> AppState {
        let mut config = Config::default();
        if let Some(text) = section {
            config
                .modules
                .config
                .insert("ticker".into(), toml::from_str(text).unwrap());
        }
        let registry =
            Arc::new(ModuleRegistry::build(vec![Arc::new(TickerModule::new())], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    fn ctx(app: &AppState, method: &str) -> CallCtx {
        CallCtx {
            app: app.clone(),
            module: "ticker".into(),
            method: method.into(),
            params: json!({}),
            conn_id: 1,
            peer: "127.0.0.1:1".into(),
            is_local: true,
        }
    }

    #[test]
    fn config_defaults_and_clamping() {
        let c = TickerConfig::default();
        assert_eq!(c.clamped_interval(), 1000);
        assert!(!c.autostart);
        assert_eq!(
            TickerConfig {
                interval_ms: 1,
                autostart: false
            }
            .clamped_interval(),
            MIN_INTERVAL_MS
        );
        assert_eq!(
            TickerConfig {
                interval_ms: u64::MAX,
                autostart: false
            }
            .clamped_interval(),
            MAX_INTERVAL_MS
        );
    }

    /// `ModuleEnv::config` 要能把 `[modules.config.ticker]` 反序列化出来，
    /// 缺节时回落到 `Default`。
    #[test]
    fn module_env_reads_own_section() {
        let app = app_with(Some("interval_ms = 250\nautostart = true"));
        let env = ModuleEnv {
            app,
            config: Some(toml::from_str("interval_ms = 250\nautostart = true").unwrap()),
        };
        let c: TickerConfig = env.config().unwrap();
        assert_eq!(c.clamped_interval(), 250);
        assert!(c.autostart);

        let app = app_with(None);
        let env = ModuleEnv { app, config: None };
        let c: TickerConfig = env.config().unwrap();
        assert_eq!(c.clamped_interval(), DEFAULT_INTERVAL_MS);
    }

    /// 配置写错字段名必须报错，而不是静默走默认值。
    #[test]
    fn misspelled_config_field_is_rejected() {
        let app = app_with(Some("intervall_ms = 250"));
        let env = ModuleEnv {
            app,
            config: Some(toml::from_str("intervall_ms = 250").unwrap()),
        };
        assert!(env.config::<TickerConfig>().is_err());
    }

    #[tokio::test]
    async fn start_then_stop_is_idempotent_safe() {
        let state = Arc::new(TickerState::default());
        let app = app_with(None);

        assert!(state.start_loop(app.clone(), 60).await.is_ok());
        // 第二次必须被拒绝
        let err = state.start_loop(app.clone(), 60).await.unwrap_err();
        assert_eq!(err.code, "already_running");

        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(state.ticks.load(Ordering::Relaxed) >= 2, "应该至少跑了几次");
        assert!(state.stop_loop(Some(&app)).await);
        // 已经停了，再停返回 false
        assert!(!state.stop_loop(Some(&app)).await);
        assert!(!state.status_json()["running"].as_bool().unwrap());
    }

    #[tokio::test]
    async fn loop_stops_promptly_on_cancel() {
        let state = Arc::new(TickerState::default());
        let app = app_with(None);

        state.start_loop(app.clone(), 50).await.unwrap();
        tokio::time::sleep(Duration::from_millis(120)).await;
        let before = state.ticks.load(Ordering::Relaxed);

        state.stop_loop(Some(&app)).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(
            state.ticks.load(Ordering::Relaxed),
            before,
            "stop 返回后不该再有新的 tick"
        );
    }

    #[tokio::test]
    async fn ticks_are_pushed_to_subscribers() {
        let state = Arc::new(TickerState::default());
        let app = app_with(None);
        let mut rx = app.bus.subscribe();

        state.start_loop(app.clone(), 50).await.unwrap();

        // 启动时也会推 ticker.started，这里只等 ticker.tick。
        let event = tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                let e = rx.recv().await.expect("事件总线不该关闭");
                if e.topic == TOPIC_TICK {
                    break e;
                }
            }
        })
        .await
        .expect("应该收到 tick 事件");

        assert_eq!(event.source.as_deref(), Some("ticker"));
        assert!(event.data["n"].as_u64().unwrap() >= 1);

        state.stop_loop(Some(&app)).await;
    }

    #[tokio::test]
    async fn registered_methods_are_dispatchable() {
        let module = Arc::new(TickerModule::new());
        let registry = Arc::new(ModuleRegistry::build(vec![module], &Config::default()).unwrap());
        let app = AppState::new(
            Config::default(),
            None,
            registry.clone(),
            CancellationToken::new(),
        );

        let out = registry.dispatch(ctx(&app, "ticker.status")).await.unwrap();
        assert_eq!(out["running"], json!(false));

        let out = registry
            .dispatch(ctx(&app, "ticker.publish"))
            .await
            .unwrap();
        assert_eq!(out["n"], json!(1));

        let out = registry.dispatch(ctx(&app, "ticker.stop")).await.unwrap();
        assert_eq!(out["stopped"], json!(false));

        // 参数类型不符要报 invalid_params
        let mut bad = ctx(&app, "ticker.start");
        bad.params = json!({ "interval_ms": "soon" });
        let err = registry.dispatch(bad).await.unwrap_err();
        assert_eq!(err.code, "invalid_params");
    }

    #[tokio::test]
    async fn module_lifecycle_honours_autostart() {
        let module = Arc::new(TickerModule::new());
        let mut config = Config::default();
        config.modules.config.insert(
            "ticker".into(),
            toml::from_str("interval_ms = 60\nautostart = true").unwrap(),
        );
        let registry = Arc::new(ModuleRegistry::build(vec![module.clone()], &config).unwrap());
        let app = AppState::new(config, None, registry.clone(), CancellationToken::new());

        registry.start_all(&app).await.unwrap();
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert!(
            module.state.running.load(Ordering::Relaxed),
            "autostart 应已起跑"
        );

        registry.stop_all().await;
        assert!(
            !module.state.running.load(Ordering::Relaxed),
            "stop_all 应停掉定时器"
        );
    }

    #[test]
    fn descriptor_is_stable() {
        let d = TickerModule::new().descriptor();
        assert_eq!(d.id, "ticker");
        assert!(!d.always_on);
    }
}
