//! 全局运行时状态。
//!
//! 一个 `AppState` 在 HTTP handler、WS 会话、模块后台任务之间传来传去；
//! 内部只有一份 `Arc`，克隆很便宜。

use std::net::SocketAddr;
use std::ops::Deref;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;

use serde_json::json;
use tokio_util::sync::CancellationToken;

use crate::config::Config;
use crate::conn::ConnRegistry;
use crate::event::EventBus;
use crate::module::registry::ModuleRegistry;
use crate::util::now_ms;

pub struct AppStateInner {
    /// 启动时解析好的配置，运行期只读。改配置 = 重启（或后续实现热重载）。
    pub config: Config,
    /// 实际使用的配置文件路径，没有则为 `None`（全默认值启动）。
    pub config_path: Option<PathBuf>,
    pub bus: EventBus,
    pub registry: Arc<ModuleRegistry>,
    pub conns: ConnRegistry,
    /// 全局取消令牌，Ctrl-C / SIGTERM 时触发。
    pub cancel: CancellationToken,
    pub started_at: Instant,
    pub started_at_ms: u64,
    /// 真正绑定到的地址。`server.port = 0`（让系统分配）时，配置里的
    /// `host:port` 并不是实际地址，对外汇报必须用这个。
    bound_addr: std::sync::RwLock<Option<SocketAddr>>,
}

#[derive(Clone)]
pub struct AppState(Arc<AppStateInner>);

impl Deref for AppState {
    type Target = AppStateInner;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl AppState {
    pub fn new(
        config: Config,
        config_path: Option<PathBuf>,
        registry: Arc<ModuleRegistry>,
        cancel: CancellationToken,
    ) -> Self {
        Self(Arc::new(AppStateInner {
            bus: EventBus::new(config.server.event_buffer),
            config,
            config_path,
            registry,
            conns: ConnRegistry::new(),
            cancel,
            started_at: Instant::now(),
            started_at_ms: now_ms(),
            bound_addr: std::sync::RwLock::new(None),
        }))
    }

    /// 绑定成功后由服务层调用，记下真实监听地址。
    pub fn set_bound_addr(&self, addr: SocketAddr) {
        if let Ok(mut slot) = self.0.bound_addr.write() {
            *slot = Some(addr);
        }
    }

    /// 对外汇报的监听地址：优先用真实绑定地址，未绑定时退回配置值。
    ///
    /// `server.port = 0` 时配置值没有意义（那是"让系统挑一个"），
    /// 所以必须报实际地址。
    pub fn bind_display(&self) -> String {
        if let Ok(slot) = self.0.bound_addr.read()
            && let Some(addr) = *slot
        {
            return addr.to_string();
        }
        format!("{}:{}", self.config.server.host, self.config.server.port)
    }

    pub fn uptime_ms(&self) -> u64 {
        self.started_at.elapsed().as_millis() as u64
    }

    pub fn uptime_secs(&self) -> u64 {
        self.started_at.elapsed().as_secs()
    }

    /// 是否已进入关闭流程。方法处理器可以用它拒绝新任务。
    pub fn is_shutting_down(&self) -> bool {
        self.cancel.is_cancelled()
    }

    pub fn config_path_string(&self) -> Option<String> {
        self.config_path.as_ref().map(|p| p.display().to_string())
    }

    /// 供 `core.config` 方法使用的配置快照，**令牌已遮蔽**。
    pub fn redacted_config(&self) -> serde_json::Value {
        let mut value = serde_json::to_value(&self.config).unwrap_or_else(|_| json!({}));
        if self.config.server.auth_required()
            && let Some(token) = value.get_mut("server").and_then(|s| s.get_mut("token"))
        {
            *token = json!("<redacted>");
        }
        value
    }
}

impl std::fmt::Debug for AppState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AppState")
            .field("uptime_ms", &self.uptime_ms())
            .field("config_path", &self.config_path)
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state(token: Option<&str>) -> AppState {
        let mut config = Config::default();
        config.server.token = token.map(str::to_string);
        let registry = Arc::new(ModuleRegistry::build(vec![], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    #[test]
    fn uptime_and_shutdown_flag() {
        let s = state(None);
        assert!(s.uptime_secs() <= 1);
        assert!(!s.is_shutting_down());
        s.cancel.cancel();
        assert!(s.is_shutting_down());
    }

    #[test]
    fn token_is_redacted_in_snapshot() {
        let s = state(Some("super-secret-value"));
        let v = s.redacted_config();
        assert_eq!(v["server"]["token"], json!("<redacted>"));
        assert!(!v.to_string().contains("super-secret-value"));

        let s2 = state(None);
        assert!(s2.redacted_config()["server"]["token"].is_null());
    }

    #[test]
    fn bind_display_prefers_real_address() {
        let s = state(None);
        // 还没绑定 → 退回配置值
        assert_eq!(s.bind_display(), "127.0.0.1:8787");
        // 绑定后（比如 port = 0 由系统分配）应当报实际地址
        s.set_bound_addr("127.0.0.1:54321".parse().expect("地址应合法"));
        assert_eq!(s.bind_display(), "127.0.0.1:54321");
    }
}
