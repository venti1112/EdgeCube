//! 日志初始化。
//!
//! subscriber 的类型取决于「格式 + 是否上色」，没法热切换，所以启动顺序是
//! **先读配置 → 再装 subscriber**，一次到位（配置读不出来时由 `main` 直接
//! 往 stderr 打一行，不会静默）。
//!
//! 日志只写 stdout：落盘、轮转、收集都交给 systemd/journald 或容器运行时，
//! 框架不再自己实现一套。

use tracing_subscriber::EnvFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use crate::config::{LogConfig, LogFormat};
use crate::error::{Error, Result};

/// 按配置安装全局 subscriber。
///
/// 同一个进程只能装一次；重复调用返回错误（调用方应当是 `main`，
/// 不该出现第二次）。
pub fn init(config: &LogConfig) -> Result<()> {
    let filter = build_filter(&config.level)?;

    let installed = match config.format {
        LogFormat::Pretty => tracing_subscriber::registry()
            .with(filter)
            .with(
                tracing_subscriber::fmt::layer()
                    .with_target(true)
                    .with_ansi(config.ansi),
            )
            .try_init(),
        LogFormat::Json => tracing_subscriber::registry()
            .with(filter)
            .with(
                tracing_subscriber::fmt::layer()
                    .json()
                    .with_ansi(config.ansi),
            )
            .try_init(),
    };

    installed.map_err(|e| Error::other(format!("初始化日志失败: {e}")))
}

/// 校验过滤串。级别写错要**在启动时**报出来，而不是等日志一条都不打。
fn build_filter(level: &str) -> Result<EnvFilter> {
    EnvFilter::try_new(level).map_err(|e| Error::config(format!("日志级别 `{level}` 不合法: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_level_is_rejected() {
        // EnvFilter 对 `target=level` 里的非法 level 会报错
        assert!(build_filter("edgecube_daemon=definitely_not_a_level").is_err());
        assert!(build_filter("info").is_ok());
        assert!(build_filter("edgecube_daemon=debug,tower_http=warn").is_ok());
    }

    #[test]
    fn init_installs_once() {
        // 同一进程里只能装一次：第一次 Ok，之后 Err，但都不该 panic。
        // 测试之间会抢这个全局单例，所以只断言"不 panic 且至多一次成功"。
        let config = LogConfig::default();
        let first = init(&config).is_ok();
        let second = init(&config).is_ok();
        assert!(!(first && second), "重复安装不该都成功");
    }

    #[test]
    fn invalid_config_fails_without_installing() {
        let config = LogConfig {
            level: "edgecube=oops".into(),
            ..LogConfig::default()
        };
        assert!(init(&config).is_err());
    }
}
