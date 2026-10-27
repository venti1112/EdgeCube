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

/// 配置文件的查找位置。
///
/// 抽成结构体是为了能测：测试给一组临时目录，就不会往真实的
/// `~/.config/edgecube/` 里写东西，也不受仓库里有没有 `./edgecube.toml` 影响。
#[derive(Debug, Clone)]
pub struct Locations {
    /// 先看当前工作目录下的这个文件（常规取值是 `./edgecube.toml`）。
    pub cwd: PathBuf,
    /// 用户配置目录下的文件；哪儿都没找到时，默认配置就释放到这里。
    pub default: PathBuf,
}

impl Default for Locations {
    fn default() -> Self {
        Self {
            cwd: PathBuf::from(CWD_CONFIG_FILE),
            default: default_config_path(),
        }
    }
}

/// 配置文件查找结果。
#[derive(Debug, Clone)]
pub struct Loaded {
    pub config: Config,
    /// 实际使用的配置文件；不存在时为 `None`（全用默认值）。
    pub path: Option<PathBuf>,
    /// **本次由我们释放**的配置文件（原来是空的，现在写了一份默认的）。
    ///
    /// 与 [`Self::path`] 是两件事：`path` 是「读了哪个文件」（`None` = 全用内置默认值），
    /// `released` 是「顺手创建了哪个文件」。首次运行两个都指向同一份。
    pub released: Option<PathBuf>,
    /// 需要提醒用户的提示语（读不到、写不出……），交给日志层按 warning 打印。
    pub notice: Option<String>,
}

/// 文件名，相对当前工作目录查找。
const CWD_CONFIG_FILE: &str = "edgecube.toml";

/// 平台配置目录下的文件名。
///
/// 注意：`XDG_CONFIG_HOME` 与 `HOME` 都没有时会返回**相对路径**
/// （`./edgecube/daemon.toml`）—— 调用方要区分「能写」与「往哪写都行」，
/// 见 [`Config::load_with`] 里的判断。
pub fn default_config_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("edgecube").join("daemon.toml")
}

/// 把带注释的默认配置释放到 `path`（父目录不存在就建）。
///
/// **不检查是否已存在** —— 调用方负责确认（`Config::load_with` 只在「哪儿都没找到」
/// 时才走到这里，`--init-config` 则自己先查一遍并报错，因为覆盖用户的配置更不可接受）。
///
/// 先写同目录的临时文件再 `rename`：中途被杀不会留下半截 TOML。半截文件的后果是
/// 下次启动解析失败、用户得自己删掉，比「这次没写出来」麻烦得多。
pub fn write_default_config(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("toml.tmp");
    std::fs::write(&tmp, Config::template())?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

impl Config {
    /// 按四层优先级解析出最终配置。
    pub fn load(cli: &Cli) -> Result<Loaded> {
        Self::load_in(cli, &Locations::default())
    }

    /// [`Config::load`] 的本体：配置文件该去哪儿找由调用方给。
    ///
    /// # 查找顺序
    ///
    /// 1. 显式指定（`-c` 或 `EDGECUBE_CONFIG`）—— **不存在就报错**，绝不代写；
    /// 2. [`Locations::cwd`]；
    /// 3. [`Locations::default`]；
    /// 4. 都没有 → **就地把默认配置释放到 3 再加载它**（写不出来就退回内置默认值）。
    ///
    /// 第 4 步是刻意的：`--init-config` 因此不再是必经步骤，第一次跑就是可用状态。
    /// 但它是「兜底」而不是「初始化命令」，所以显式指定的路径写错时仍然报错 ——
    /// 帮用户在他给错的路径上生成一份配置，只会把「路径写错了」这件事盖住。
    pub fn load_in(cli: &Cli, locations: &Locations) -> Result<Loaded> {
        let explicit = cli
            .config
            .clone()
            .or_else(|| std::env::var_os("EDGECUBE_CONFIG").map(PathBuf::from));

        let mut released = None;
        let (path, notice) = match explicit {
            Some(p) => {
                if !p.exists() {
                    return Err(Error::ConfigNotFound(p.display().to_string()));
                }
                (Some(p), None)
            }
            None => {
                let default_path = &locations.default;
                if locations.cwd.exists() {
                    (Some(locations.cwd.clone()), None)
                } else if default_path.exists() {
                    (Some(default_path.to_path_buf()), None)
                } else if !default_path.is_absolute() {
                    // HOME / XDG_CONFIG_HOME 都没设 → 定位不到用户配置目录
                    // （`default_config_path` 会退化成相对路径）。这时往相对路径写等于
                    // 随手丢在进程的 CWD 里（systemd 下可能是 /），不如老实退回内置默认值。
                    (
                        None,
                        Some(
                            "未找到配置文件，且无法确定用户配置目录（HOME / XDG_CONFIG_HOME 均未设置），\
                             本次使用内置默认值"
                                .to_string(),
                        ),
                    )
                } else {
                    // 哪儿都没有 → 释放一份默认配置，再按正常路径把它读回来。
                    // 「再读回来」这一步不只是省代码：它保证「写下去的东西一定能加载」，
                    // 模板哪天写坏了会当场炸在这里，而不是等到下次启动。
                    match write_default_config(default_path) {
                        Ok(()) => {
                            released = Some(default_path.to_path_buf());
                            (Some(default_path.to_path_buf()), None)
                        }
                        Err(e) => (
                            None,
                            Some(format!(
                                "未找到配置文件，且无法在 {} 释放默认配置（{e}），本次使用内置默认值",
                                default_path.display()
                            )),
                        ),
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
            released,
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

[modules.config.monitor]
# 采样间隔（毫秒），也是 monitor.stats 的推送间隔。会被 clamp 到 [250, 60000]。
# 采样器常驻，没有开关：CPU 使用率靠两次采样的差值，按需采样会让第一次永远是 null。
interval_ms = 2000
# 是否周期性推送 monitor.stats；关掉就是「只拉（monitor.snapshot）不推」。
publish = true

[modules.config.download]
# 全局 HTTP 下载队列（底层 gosh-dl）。任务落在实例目录里，所以本模块**没有自己的
# dir**：数据根跟着 [modules.config.instance] 的 dir 走。队列只在内存里，
# daemon 重启即清空。
# 同时下载的任务数上限（clamp 到 [1, 64]）。
max_concurrent = 3
# 单个任务的最大连接数（clamp 到 [1, 64]）。
connections_per_download = 8
# 全局限速（字节/秒），0 = 不限。
max_download_speed = 0
# 建连 / 读空闲超时（秒），至少 1。
connect_timeout_secs = 30
read_timeout_secs = 60
# 单个分段的重试次数。
max_retries = 5
# User-Agent，留空 = EdgeCube-daemon/<版本>。
user_agent = ""
# download.progress 的推送间隔（毫秒），clamp 到 [200, 5000]。
progress_interval_ms = 500

[modules.config.mcserver]
# 服务端目录（原版 / Paper / Purpur / Leaf / Leaves / Fabric / Velocity / BungeeCord）：
# 版本列表与下载地址都在 daemon 这边取，前端只发 RPC。
# 本模块自己不下载、不建实例 —— 只回答「下什么」。
# 版本列表缓存时长（秒），0 = 不缓存。
cache_ttl_secs = 300
# 单次上游请求的超时（秒）。
request_timeout_secs = 20

[modules.config.mods]
# 模组与插件（Modrinth）：搜索、版本列表、下载计划都在 daemon 这边取，前端只发 RPC；
# 实例里已装文件的列表 / 更新检查 / 启停 / 删除也归这一节管。
# 本模块自己不下载 —— 落盘交给 download 队列，编排交给 mods-install 工作流。
# 搜索与版本列表的缓存时长（秒），0 = 不缓存。
cache_ttl_secs = 300
# 游戏版本清单的缓存时长（秒）。它变得很慢，所以给得比上面长。
tags_cache_ttl_secs = 3600
# 单次上游请求的超时（秒）。
request_timeout_secs = 20
# 搜索不传 limit 时给多少条，以及 limit 的上限（上游最多 100）。
search_default_limit = 20
search_max_limit = 50
# 每个目录（mods / plugins）最多列多少个文件。
scan_max_files = 2000
# 读 jar 元数据时单个 zip 条目的字节上限。
meta_max_entry_bytes = 262144
# .phar（PocketMine 插件）的整文件上限 —— 它要整读进内存才能定位 tar 段。
phar_max_bytes = 67108864
# 更新检查一次提交给上游多少个 sha1（分片），以及一次最多算多少个文件的哈希。
hash_batch = 100
update_max_files = 200

[modules.config.runtime]
# 运行环境（Zulu JDK、frp）：下载 + 解压 + 列表 + 删除。
# **没有 dir**：环境与实例共用同一个数据根（上面 instance 的 dir），
# 布局是 <root>/config/runtimes/ 与 <root>/runtimes/<id>/。
# 单次上游请求的超时（秒）。
request_timeout_secs = 20
# 版本清单的缓存时长（秒），0 = 不缓存。frp 的清单走 GitHub API，
# 未认证配额只有 60 次/小时，所以别调到 0。
cache_ttl_secs = 300

[modules.config.task]
# 任务系统（工作流引擎 szal）：把多步操作（创建→下载、下载→解压）编成任务。
# 模块只管执行与可观测性，工作流定义由各业务模块在 start() 里注册进来；
# 生产 daemon 启动时 task.flows 是空列表，等业务模块挂载。
# 同时执行的任务上限，超出排队（queued）。
max_concurrent_tasks = 4
# 已结束任务的保留条数（在跑的不受影响），超过就删最老的。
history_limit = 100
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

    #[test]
    fn task_config_section_round_trips() {
        // --check 不解析各模块 section（要等 start），所以这里手验一遍：
        // 模板里写的 [modules.config.task] 能被 TaskConfig::deserialize 吃下去，
        // 字段名写错（如写成 max_concurrency）会因 deny_unknown_fields 炸。
        let c: Config = toml::from_str(&Config::template()).expect("模板必须可解析");
        let section = c
            .modules
            .section("task")
            .expect("模板里应有 [modules.config.task]");
        let tc: crate::module::builtin::task::model::TaskConfig =
            crate::module::builtin::task::model::TaskConfig::deserialize(section.clone())
                .expect("task 配置节应能反序列化");
        assert_eq!(tc.max_concurrent_tasks, 4);
        assert_eq!(tc.history_limit, 100);
        assert_eq!(tc.clamped_max_concurrent(), 4);
    }

    // ── 配置文件查找与「首次运行自动释放」 ────────────────────────────────
    //
    // 这些用例一律用临时目录当查找位置：既不会往真实的 ~/.config/edgecube/ 里写东西，
    // 也不受「仓库里恰好有个 ./edgecube.toml」影响。

    /// 一个临时目录；析构时清盘。
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let dir = std::env::temp_dir().join(format!(
                "edgecube-config-test-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            std::fs::create_dir_all(&dir).expect("应能建临时目录");
            Self(dir)
        }

        fn join(&self, name: &str) -> PathBuf {
            self.0.join(name)
        }

        /// 一组「cwd 里没有、用户配置目录里也没有」的查找位置。
        fn empty_locations(&self) -> Locations {
            Locations {
                cwd: self.join("edgecube.toml"),
                default: self.join("config/edgecube/daemon.toml"),
            }
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn first_run_releases_the_default_config_and_loads_it() {
        let tmp = TempDir::new("release");
        let locations = tmp.empty_locations();

        let loaded = Config::load_in(&Cli::default(), &locations).expect("应当能加载");

        let path = locations.default.clone();
        assert!(
            path.is_file(),
            "首次运行应当释放默认配置: {}",
            path.display()
        );
        assert_eq!(
            loaded.path.as_deref(),
            Some(path.as_path()),
            "释放的那份就是要加载的那份"
        );
        assert_eq!(loaded.released.as_deref(), Some(path.as_path()));
        assert!(
            loaded.notice.is_none(),
            "释放成功不该再有提示语: {:?}",
            loaded.notice
        );

        // 释放的内容就是带注释的模板
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("# EdgeCube Daemon 配置文件"), "{text}");
        toml::from_str::<Config>(&text)
            .expect("释放的文件必须可解析")
            .validate()
            .expect("释放的文件必须自洽");
        // 临时文件不该留下
        assert!(!path.with_extension("toml.tmp").exists());

        // **确实读了文件**：内置默认值的模块配置节是空的，模板里 monitor / ticker 都有
        assert!(loaded.config.modules.section("monitor").is_some());
        assert!(loaded.config.modules.section("ticker").is_some());
    }

    #[test]
    fn an_existing_config_is_loaded_and_never_rewritten() {
        let tmp = TempDir::new("existing");
        let locations = tmp.empty_locations();
        std::fs::create_dir_all(locations.default.parent().unwrap()).unwrap();
        let mine = "[server]\nmax_connections = 77\n";
        std::fs::write(&locations.default, mine).unwrap();

        let loaded = Config::load_in(&Cli::default(), &locations).unwrap();
        assert_eq!(loaded.config.server.max_connections, 77);
        assert!(loaded.released.is_none(), "已有配置就不该再释放");
        assert!(loaded.notice.is_none());
        // 用户写的文件一个字节都不该被动
        assert_eq!(std::fs::read_to_string(&locations.default).unwrap(), mine);
    }

    #[test]
    fn cwd_file_wins_over_the_user_config_dir() {
        let tmp = TempDir::new("cwd");
        let locations = tmp.empty_locations();
        std::fs::write(&locations.cwd, "[server]\nmax_connections = 31\n").unwrap();

        let loaded = Config::load_in(&Cli::default(), &locations).unwrap();
        assert_eq!(loaded.path.as_deref(), Some(locations.cwd.as_path()));
        assert_eq!(loaded.config.server.max_connections, 31);
        assert!(
            !locations.default.exists(),
            "找到了配置就不该再往用户配置目录释放一份"
        );
    }

    #[test]
    fn an_explicitly_given_path_must_exist() {
        let tmp = TempDir::new("explicit");
        let missing = tmp.join("nope.toml");
        let cli = Cli {
            config: Some(missing.clone()),
            ..Cli::default()
        };

        let err = Config::load_in(&cli, &tmp.empty_locations()).unwrap_err();
        assert!(matches!(err, Error::ConfigNotFound(_)), "{err}");
        assert!(
            !missing.exists(),
            "显式路径写错时不该替他生成一份 —— 那会把「路径错了」盖住"
        );
    }

    #[test]
    fn a_failed_release_falls_back_to_builtin_defaults() {
        let tmp = TempDir::new("unwritable");
        // 让默认位置的父目录被一个**普通文件**占着 → create_dir_all 必然失败
        let blocker = tmp.join("blocked");
        std::fs::write(&blocker, b"not a directory").unwrap();
        let locations = Locations {
            cwd: tmp.join("edgecube.toml"),
            default: blocker.join("edgecube/daemon.toml"),
        };

        let loaded = Config::load_in(&Cli::default(), &locations).expect("写不出来也必须能启动");
        assert!(loaded.path.is_none(), "没读成文件");
        assert!(loaded.released.is_none());
        let notice = loaded.notice.expect("应当有提示语");
        assert!(notice.contains("无法在"), "{notice}");
        // 退回内置默认值：模板里的模块配置节一个都没有
        assert!(loaded.config.modules.section("monitor").is_none());
        loaded.config.validate().expect("退回的默认值必须自洽");
    }

    #[test]
    fn a_relative_default_path_is_left_alone() {
        let tmp = TempDir::new("relative");
        // HOME / XDG_CONFIG_HOME 都没设时 default_config_path() 就长这样
        let relative = PathBuf::from("edgecube/daemon.toml");
        let locations = Locations {
            cwd: tmp.join("edgecube.toml"),
            default: relative.clone(),
        };

        let loaded = Config::load_in(&Cli::default(), &locations).unwrap();
        assert!(loaded.path.is_none());
        assert!(loaded.released.is_none());
        let notice = loaded.notice.expect("应当有提示语");
        assert!(notice.contains("XDG_CONFIG_HOME"), "{notice}");
        assert!(!relative.exists(), "不该在相对路径上写出任何东西");
    }
}
