//! daemon 配置:载入 / 生成默认并落盘 / CLI 覆盖。
//!
//! 配置文件为数据目录下的 `config.json`,顶层结构对应 openapi `/config/{key}`
//! 的设置项(locale/theme/network/developer/terminal/download 等)。

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

use crate::error::Result;

/// 局域网监听配置(openapi servers.url 默认 127.0.0.1:8760;
/// ws.md:局域网绑定为 daemon 配置项,Android UI 默认走 127.0.0.1)。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct NetworkConfig {
    pub bind: String,
    pub port: u16,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self {
            bind: "127.0.0.1".into(),
            port: 8760,
        }
    }
}

/// daemon 顶层配置。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct DaemonConfig {
    pub network: NetworkConfig,
    pub locale: String,
    pub theme: serde_json::Value,
    pub developer: serde_json::Value,
    pub terminal: serde_json::Value,
    pub download: serde_json::Value,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        Self {
            network: NetworkConfig::default(),
            locale: "zh-CN".into(),
            theme: serde_json::json!({}),
            developer: serde_json::json!({}),
            terminal: serde_json::json!({}),
            download: serde_json::json!({}),
        }
    }
}

/// 命令行覆盖项,优先级最高。
#[derive(Debug, Default, Clone)]
pub struct Overrides {
    pub bind: Option<String>,
    pub port: Option<u16>,
}

impl DaemonConfig {
    /// 载入配置:
    /// - 文件存在:读取,缺失字段由 `serde(default)` 补齐;
    /// - 文件不存在:写入默认配置后返回(首启落盘);
    /// - 配置损坏:直接报错,不静默重置。
    pub fn load(path: &Path, overrides: &Overrides) -> Result<Self> {
        let mut cfg = if path.exists() {
            let raw = fs::read_to_string(path)?;
            tracing::debug!(path = %path.display(), "loading config");
            serde_json::from_str(&raw)?
        } else {
            let cfg = DaemonConfig::default();
            fs::write(path, serde_json::to_string_pretty(&cfg)?)?;
            tracing::info!(path = %path.display(), "config not found, default config written");
            cfg
        };

        if let Some(bind) = &overrides.bind {
            cfg.network.bind = bind.clone();
        }
        if let Some(port) = overrides.port {
            cfg.network.port = port;
        }
        Ok(cfg)
    }
}

/// daemon 数据目录:优先 `EDGECUBE_HOME`,否则按平台惯例取系统数据目录。
pub fn data_dir() -> Result<PathBuf> {
    if let Ok(home) = std::env::var("EDGECUBE_HOME") {
        return Ok(PathBuf::from(home));
    }

    #[cfg(target_os = "windows")]
    {
        let base = std::env::var("APPDATA")
            .map(PathBuf::from)
            .or_else(|_| std::env::var("USERPROFILE").map(|p| PathBuf::from(p).join("AppData/Roaming")))?;
        Ok(base.join("edgecube"))
    }

    #[cfg(not(target_os = "windows"))]
    {
        let base = std::env::var("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                std::env::var("HOME")
                    .map(|h| PathBuf::from(h).join(".local/share"))
                    .unwrap_or_else(|_| PathBuf::from("."))
            });
        Ok(base.join("edgecube"))
    }
}