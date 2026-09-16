//! 配置：四层合并 + 校验。
//!
//! 优先级由低到高：
//!
//! 1. 代码内置默认值（[`Config::default`]）
//! 2. 配置文件（TOML）
//! 3. 环境变量（`EDGECUBE_*`）
//! 4. 命令行参数
//!
//! 模块私有配置统一放在 `[modules.config.<模块 id>]` 下，框架**不解析**它，
//! 原样交给模块自己 `deserialize`。这样加模块不用改框架。

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::cli::Cli;
use crate::error::{Error, Result};

/// 默认监听端口。
pub const DEFAULT_PORT: u16 = 8787;

/// 默认 WS 路径。
pub const DEFAULT_WS_PATH: &str = "/ws";

/// 完整配置。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub server: ServerConfig,
    pub log: LogConfig,
    pub modules: ModulesConfig,
}

// ---------------------------------------------------------------------------
// server
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ServerConfig {
    /// 监听地址。默认只监听回环，要对外暴露得显式改。
    pub host: String,
    /// 监听端口，HTTP 与 WS 共用同一个端口。
    pub port: u16,
    /// WebSocket 升级路径。必须 `/` 开头且不以 `/` 结尾。
    pub ws_path: String,
    /// 访问令牌。`None` / 空串 = 不鉴权（仅建议回环地址下这么用）。
    pub token: Option<String>,
    /// CORS 白名单，`["*"]` 表示放开。Web 端跑在别的源时需要。
    pub cors_origins: Vec<String>,
    /// 最大同时在线连接数。
    pub max_connections: usize,
    /// 单连接最大并发在途调用数，超出直接回 `busy`。
    pub max_inflight_calls: usize,
    /// 单次调用超时（秒）。
    pub request_timeout_secs: u64,
    /// 心跳间隔（秒），服务端主动发 WS Ping 帧。
    pub heartbeat_interval_secs: u64,
    /// 空闲超时（秒），超过则断开。
    pub idle_timeout_secs: u64,
    /// 关闭时等待在途请求的上限（秒）。
    pub shutdown_grace_secs: u64,
    /// 事件广播环形缓冲容量，慢消费者超出后丢事件而不是拖垮服务。
    pub event_buffer: usize,
    /// 单连接允许的订阅主题个数上限。
    pub max_subscriptions: usize,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: "127.0.0.1".into(),
            port: DEFAULT_PORT,
            ws_path: DEFAULT_WS_PATH.into(),
            token: None,
            cors_origins: vec!["*".into()],
            max_connections: 128,
            max_inflight_calls: 32,
            request_timeout_secs: 30,
            heartbeat_interval_secs: 15,
            idle_timeout_secs: 60,
            shutdown_grace_secs: 5,
            event_buffer: 1024,
            max_subscriptions: 64,
        }
    }
}

impl ServerConfig {
    /// 令牌规范化：`None` 与空白串都视作「不鉴权」。
    pub fn effective_token(&self) -> Option<&str> {
        self.token
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
    }

    pub fn auth_required(&self) -> bool {
        self.effective_token().is_some()
    }
}

// ---------------------------------------------------------------------------
// log
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    /// 人看的多行彩色输出。
    #[default]
    Pretty,
    /// 一行一个 JSON 对象，给日志采集用。
    Json,
}

impl LogFormat {
    pub fn parse(s: &str) -> Result<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "pretty" | "text" | "plain" => Ok(Self::Pretty),
            "json" => Ok(Self::Json),
            other => Err(Error::config(format!(
                "未知的日志格式 `{other}`，可选: pretty | json"
            ))),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LogConfig {
    /// tracing 过滤串，如 `info`、`edgecube_daemon=debug,tower_http=warn`。
    pub level: String,
    pub format: LogFormat,
    /// 是否输出 ANSI 颜色（重定向到文件/管道时应关掉）。
    ///
    /// 日志只写 stdout：落盘交给 systemd/journald 或容器运行时，
    /// 免得框架自己再实现一套滚动与轮转。
    pub ansi: bool,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: "info".into(),
            format: LogFormat::Pretty,
            ansi: true,
        }
    }
}

// ---------------------------------------------------------------------------
// modules
// ---------------------------------------------------------------------------

/// `modules.enabled` 支持两种写法：`"*"` 或 `["core", "ticker"]`。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Enabled {
    Pattern(String),
    List(Vec<String>),
}

impl Default for Enabled {
    fn default() -> Self {
        Self::Pattern("*".into())
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ModulesConfig {
    /// 启用哪些模块。
    pub enabled: Enabled,
    /// 在 `enabled` 基础上再排除（`always_on` 的模块排除不掉）。
    pub disabled: Vec<String>,
    /// 各模块私有配置，键为模块 id。
    pub config: BTreeMap<String, toml::Value>,
}

impl ModulesConfig {
    /// 取某个模块自己的配置节。
    pub fn section(&self, module_id: &str) -> Option<&toml::Value> {
        self.config.get(module_id)
    }

    /// 该模块是否被配置启用（`disabled` 优先）。
    pub fn is_enabled(&self, module_id: &str) -> bool {
        if self.disabled.iter().any(|d| d == module_id) {
            return false;
        }
        match &self.enabled {
            Enabled::Pattern(p) => p == "*" || p == module_id,
            Enabled::List(list) => list.iter().any(|e| e == module_id),
        }
    }
}

// ---------------------------------------------------------------------------
// 加载 / 合并 / 校验
// ---------------------------------------------------------------------------

/// 配置文件查找结果。
#[derive(Debug, Clone)]
pub struct Loaded {
    pub config: Config,
    /// 实际使用的配置文件；不存在时为 `None`（全用默认值）。
    pub path: Option<PathBuf>,
    /// 配置文件不存在（非显式指定）时的提示语，交给日志层打印。
    pub notice: Option<String>,
}

/// 文件名，相对当前工作目录查找。
const CWD_CONFIG_FILE: &str = "edgecube.toml";

/// 平台配置目录下的文件名。
pub fn default_config_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("edgecube").join("daemon.toml")
}

impl Config {
    /// 按四层优先级解析出最终配置。
    pub fn load(cli: &Cli) -> Result<Loaded> {
        let explicit = cli
            .config
            .clone()
            .or_else(|| std::env::var_os("EDGECUBE_CONFIG").map(PathBuf::from));

        let (path, notice) = match explicit {
            Some(p) => {
                if !p.exists() {
                    return Err(Error::ConfigNotFound(p.display().to_string()));
                }
                (Some(p), None)
            }
            None => {
                let cwd = PathBuf::from(CWD_CONFIG_FILE);
                if cwd.exists() {
                    (Some(cwd), None)
                } else {
                    let xdg = default_config_path();
                    if xdg.exists() {
                        (Some(xdg), None)
                    } else {
                        (
                            None,
                            Some(format!(
                                "未找到配置文件，使用内置默认值（可用 --init-config 生成一份到 {}）",
                                xdg.display()
                            )),
                        )
                    }
                }
            }
        };

        // 1) 默认值
        let mut config = Config::default();

        // 2) 配置文件：serde 默认值先补齐缺字段，再整体覆盖。
        if let Some(p) = &path {
            let text = std::fs::read_to_string(p)?;
            let from_file: Config = toml::from_str(&text)
                .map_err(|e| Error::config(format!("解析 {} 失败: {e}", p.display())))?;
            config = from_file;
        }

        // 3) 环境变量
        config.apply_env()?;

        // 4) 命令行
        config.apply_cli(cli)?;

        config.validate()?;

        Ok(Loaded {
            config,
            path,
            notice,
        })
    }

    fn apply_env(&mut self) -> Result<()> {
        if let Ok(v) = std::env::var("EDGECUBE_HOST") {
            self.server.host = v;
        }
        if let Ok(v) = std::env::var("EDGECUBE_PORT") {
            self.server.port = v
                .trim()
                .parse()
                .map_err(|_| Error::config(format!("EDGECUBE_PORT 不是合法端口: `{v}`")))?;
        }
        if let Ok(v) = std::env::var("EDGECUBE_TOKEN") {
            self.server.token = Some(v);
        }
        if let Ok(v) = std::env::var("EDGECUBE_LOG_LEVEL") {
            self.log.level = v;
        }
        if let Ok(v) = std::env::var("EDGECUBE_LOG_FORMAT") {
            self.log.format = LogFormat::parse(&v)?;
        }
        if let Ok(v) = std::env::var("EDGECUBE_NO_COLOR") {
            self.log.ansi = v.trim() != "1" && !v.trim().eq_ignore_ascii_case("true");
        }
        Ok(())
    }

    fn apply_cli(&mut self, cli: &Cli) -> Result<()> {
        if let Some(v) = &cli.host {
            self.server.host = v.clone();
        }
        if let Some(v) = cli.port {
            self.server.port = v;
        }
        if let Some(v) = &cli.token {
            self.server.token = Some(v.clone());
        }
        if let Some(v) = &cli.log_level {
            self.log.level = v.clone();
        }
        if let Some(v) = &cli.log_format {
            self.log.format = LogFormat::parse(v)?;
        }
        if cli.no_color {
            self.log.ansi = false;
        }
        Ok(())
    }

    /// 自身合法性校验（不涉及模块清单）。
    pub fn validate(&self) -> Result<()> {
        let s = &self.server;

        if s.host.trim().is_empty() {
            return Err(Error::config("server.host 不能为空"));
        }
        if !s.ws_path.starts_with('/') {
            return Err(Error::config(format!(
                "server.ws_path 必须以 `/` 开头，当前为 `{}`",
                s.ws_path
            )));
        }
        if s.ws_path.len() > 1 && s.ws_path.ends_with('/') {
            return Err(Error::config(format!(
                "server.ws_path 不能以 `/` 结尾，当前为 `{}`",
                s.ws_path
            )));
        }
        if s.ws_path == "/" {
            return Err(Error::config("server.ws_path 不能是 `/`"));
        }
        if s.max_connections == 0 {
            return Err(Error::config("server.max_connections 必须大于 0"));
        }
        if s.max_inflight_calls == 0 {
            return Err(Error::config("server.max_inflight_calls 必须大于 0"));
        }
        if s.max_subscriptions == 0 {
            return Err(Error::config("server.max_subscriptions 必须大于 0"));
        }
        if s.request_timeout_secs == 0 {
            return Err(Error::config("server.request_timeout_secs 必须大于 0"));
        }
        if s.heartbeat_interval_secs == 0 {
            return Err(Error::config("server.heartbeat_interval_secs 必须大于 0"));
        }
        if s.idle_timeout_secs != 0 && s.idle_timeout_secs < s.heartbeat_interval_secs {
            return Err(Error::config(
                "server.idle_timeout_secs 不能小于 heartbeat_interval_secs",
            ));
        }
        if s.event_buffer == 0 {
            return Err(Error::config("server.event_buffer 必须大于 0"));
        }
        if self.log.level.trim().is_empty() {
            return Err(Error::config("log.level 不能为空"));
        }
        if let Enabled::Pattern(p) = &self.modules.enabled
            && p != "*"
        {
            return Err(Error::config(format!(
                "modules.enabled 只支持 `\"*\"` 或数组，当前为字符串 `\"{p}\"`"
            )));
        }
        Ok(())
    }

    /// 结合模块清单校验模块相关配置。
    ///
    /// 单独一个函数是因为校验依赖 [`crate::module::registry`] 里注册了哪些模块，
    /// 而 [`Config::load`] 发生在注册表构建之前。
    pub fn validate_modules(&self, known: &[String]) -> Result<()> {
        let check = |id: &str, field: &str| -> Result<()> {
            if known.iter().any(|k| k == id) {
                Ok(())
            } else {
                Err(Error::config(format!(
                    "{field} 引用了未注册的模块 `{id}`；已注册: {}",
                    known.join(", ")
                )))
            }
        };

        if let Enabled::List(list) = &self.modules.enabled {
            for id in list {
                check(id, "modules.enabled")?;
            }
        }
        for id in &self.modules.disabled {
            check(id, "modules.disabled")?;
        }
        // 给未注册模块写了配置节，多半是拼错了模块名，直接报错更容易发现。
        for id in self.modules.config.keys() {
            check(id, "modules.config")?;
        }
        Ok(())
    }

    /// 用给定路径重新加载配置（供 `--check` 之外的热重载预留）。
    pub fn from_file(path: &Path) -> Result<Config> {
        let text = std::fs::read_to_string(path)?;
        toml::from_str(&text)
            .map_err(|e| Error::config(format!("解析 {} 失败: {e}", path.display())))
    }

    /// 序列化为带注释的模板，用于 `--init-config`。
    pub fn template() -> String {
        CONFIG_TEMPLATE.to_string()
    }
}

/// `--init-config` 生成的模板。手写而不是序列化，是为了保留注释。
const CONFIG_TEMPLATE: &str = r#"# EdgeCube Daemon 配置文件
# 优先级：内置默认值 < 本文件 < 环境变量(EDGECUBE_*) < 命令行参数

[server]
# 监听地址。默认只监听回环；对外提供服务时注意配合 token。
host = "127.0.0.1"
# HTTP 与 WebSocket 共用同一个端口。
port = 8787
# WebSocket 升级路径。
ws_path = "/ws"
# 访问令牌。留空 = 不鉴权（客户端可用 `Authorization: Bearer <token>` 或 `?token=`）。
# token = ""
# CORS 白名单，["*"] 表示放开；Web 端跨源访问时必须配置。
cors_origins = ["*"]
max_connections = 128
# 单连接最大并发在途调用数。
max_inflight_calls = 32
request_timeout_secs = 30
heartbeat_interval_secs = 15
idle_timeout_secs = 60
shutdown_grace_secs = 5
event_buffer = 1024
max_subscriptions = 64

[log]
# tracing 过滤串，例如 "info" 或 "edgecube_daemon=debug,tower_http=warn"
level = "info"
# pretty（给人看）| json（给日志采集）
format = "pretty"
# 是否输出 ANSI 颜色。日志被重定向到文件/管道时建议 false。
# 日志只写 stdout，落盘交给 systemd/journald 或容器运行时。
ansi = true

[modules]
# "*" 表示启用全部已注册模块；也可以写成列表 ["core", "ticker"]。
enabled = "*"
# 在 enabled 基础上排除某些模块。core 是 always_on，排除不掉。
disabled = []

# 各模块的私有配置节，框架不解析，原样交给模块自己。
[modules.config.ticker]
interval_ms = 1000
autostart = false
"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Config {
        toml::from_str(s).expect("配置应能解析")
    }

    #[test]
    fn defaults_are_sane() {
        let c = Config::default();
        assert_eq!(c.server.port, DEFAULT_PORT);
        assert_eq!(c.server.ws_path, DEFAULT_WS_PATH);
        assert!(!c.server.auth_required());
        c.validate().expect("默认配置必须自洽");
    }

    #[test]
    fn partial_file_keeps_defaults() {
        let c = parse("[server]\nport = 9000\n");
        assert_eq!(c.server.port, 9000);
        // 未出现的字段回落到默认值
        assert_eq!(c.server.host, "127.0.0.1");
        assert_eq!(c.log.level, "info");
    }

    #[test]
    fn module_section_is_passed_through() {
        let c = parse(
            r#"
            [modules]
            enabled = ["core", "ticker"]

            [modules.config.ticker]
            interval_ms = 250
            "#,
        );
        assert!(c.modules.is_enabled("core"));
        assert!(c.modules.is_enabled("ticker"));
        assert!(!c.modules.is_enabled("other"));
        let section = c.modules.section("ticker").expect("应有 ticker 配置节");
        assert_eq!(
            section.get("interval_ms").and_then(|v| v.as_integer()),
            Some(250)
        );
    }

    #[test]
    fn disabled_wins_over_enabled() {
        let c = parse("[modules]\nenabled = \"*\"\ndisabled = [\"ticker\"]\n");
        assert!(c.modules.is_enabled("core"));
        assert!(!c.modules.is_enabled("ticker"));
    }

    #[test]
    fn blank_token_means_no_auth() {
        let c = parse("[server]\ntoken = \"   \"\n");
        assert!(!c.server.auth_required());
        assert_eq!(c.server.effective_token(), None);
    }

    #[test]
    fn bad_ws_path_rejected() {
        for bad in ["ws", "/ws/", "/"] {
            let c = parse(&format!("[server]\nws_path = \"{bad}\"\n"));
            assert!(c.validate().is_err(), "`{bad}` 应该被拒绝");
        }
    }

    #[test]
    fn enabled_string_must_be_star() {
        let c = parse("[modules]\nenabled = \"core\"\n");
        assert!(c.validate().is_err());
    }

    #[test]
    fn unknown_field_is_rejected() {
        let err = toml::from_str::<Config>("[server]\nprot = 1234\n");
        assert!(err.is_err(), "拼错字段名应当报错而不是被静默忽略");
    }

    #[test]
    fn validate_modules_reports_unknown() {
        let c = parse("[modules]\nenabled = [\"core\", \"nope\"]\n");
        let known = vec!["core".to_string(), "ticker".to_string()];
        let err = c.validate_modules(&known).unwrap_err();
        assert!(err.to_string().contains("nope"));
    }

    #[test]
    fn template_is_valid_and_parses() {
        let c: Config = toml::from_str(&Config::template()).expect("模板必须可解析");
        c.validate().expect("模板必须自洽");
        assert_eq!(c.server.port, DEFAULT_PORT);
    }
}
