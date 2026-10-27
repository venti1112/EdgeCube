//! STUN 全局设置：服务器列表、保活、并发上限、日志开关。
//!
//! V1 是「一个 `config/stun.json` 管全部」（开关 / 本地端口 / PROXY 也在一起）。
//! V2 把**每实例**的部分（开关 / PROXY / 转发目标端口）搬进了实例元数据
//! （见 `InstanceConfig` 的 `stun_*` 字段），这里只剩全局调参 —— 存
//! `<data_dir>/config/stun/settings.json`（照 FRP 侧设置的落盘方式）。
//!
//! 读取侧一律「坏文件当没配过」（最坏是回落到内置服务器列表），
//! 数值统一 clamp（同 V1 `StunConfig.fromJson`：加载即夹取）。

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::error::Result;

/// 内置 STUN 服务器（V1 同款 8 台；都经实网验证支持 TCP 3478）。
/// 顺序即尝试顺序。
pub const DEFAULT_SERVERS: [&str; 8] = [
    "fwa.lifesizecloud.com",
    "stun.freeswitch.org",
    "turn.cloudflare.com",
    "global.turn.twilio.com",
    "stun.nextcloud.com",
    "stun.telnyx.com",
    "stun.sonetel.com",
    "stun.voip.blackberry.com",
];

/// STUN 默认端口（V1 `StunClient.defaultPort`）。
pub const DEFAULT_STUN_PORT: u16 = 3478;

/// 保活间隔缺省值（秒，V1 同款）。
pub const DEFAULT_KEEP_ALIVE_SECONDS: u32 = 20;
/// 并发连接上限缺省值（V1 同款）。
pub const DEFAULT_MAX_CONNECTIONS: u32 = 128;
/// TCP 保活用的 HTTP 目标缺省值。
///
/// nyat-core 的 TCP 保活就是周期向它发 `HEAD / HTTP/1.1`；哪台都行，
/// 这里跟 MSL / V1 生态里常见的做法一致用百度（国内可达性好）。
pub const DEFAULT_KEEPALIVE_HTTP: &str = "www.baidu.com:80";

pub const KEEP_ALIVE_MIN: u32 = 5;
pub const KEEP_ALIVE_MAX: u32 = 300;
pub const MAX_CONNECTIONS_MIN: u32 = 1;
pub const MAX_CONNECTIONS_MAX: u32 = 1024;

/// STUN 全局设置。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct StunSettings {
    /// 自定义 STUN 服务器列表（`host` 或 `host:port`）；空 = 用内置列表。
    pub servers: Vec<String>,
    /// 保活 / 探测间隔（秒）。
    pub keep_alive_seconds: u32,
    /// 并发转发连接数上限，超出的入站连接直接拒绝。
    pub max_connections: u32,
    /// TCP 保活用的 HTTP 目标（`host:port`）。高级项，不上界面。
    pub keepalive_http: String,
    /// 是否把每条入站连接的建立 / 断开写进隧道日志。
    pub show_connection_log: bool,
}

impl Default for StunSettings {
    fn default() -> Self {
        Self {
            servers: Vec::new(),
            keep_alive_seconds: DEFAULT_KEEP_ALIVE_SECONDS,
            max_connections: DEFAULT_MAX_CONNECTIONS,
            keepalive_http: DEFAULT_KEEPALIVE_HTTP.to_string(),
            show_connection_log: true,
        }
    }
}

impl StunSettings {
    /// 夹取到合法范围并去掉空白项（读取与写入共用，语义同 V1 的加载 clamp）。
    pub fn normalized(mut self) -> Self {
        self.keep_alive_seconds = self
            .keep_alive_seconds
            .clamp(KEEP_ALIVE_MIN, KEEP_ALIVE_MAX);
        self.max_connections = self
            .max_connections
            .clamp(MAX_CONNECTIONS_MIN, MAX_CONNECTIONS_MAX);
        self.keepalive_http = self.keepalive_http.trim().to_string();
        if self.keepalive_http.is_empty() {
            self.keepalive_http = DEFAULT_KEEPALIVE_HTTP.to_string();
        }
        self.servers = self
            .servers
            .iter()
            .map(|server| server.trim())
            .filter(|server| !server.is_empty())
            .map(str::to_string)
            .collect();
        self
    }

    /// 生效的服务器列表：没配自定义就用内置的。
    pub fn effective_servers(&self) -> Vec<String> {
        if self.servers.is_empty() {
            DEFAULT_SERVERS.iter().map(|s| s.to_string()).collect()
        } else {
            self.servers.clone()
        }
    }

    /// 线上形态（snake_case）：`servers` 给**生效列表**，界面不用再判空回退。
    pub fn to_wire(&self) -> Value {
        json!({
            "servers": self.effective_servers(),
            "keep_alive_seconds": self.keep_alive_seconds,
            "max_connections": self.max_connections,
            "keepalive_http": self.keepalive_http,
            "show_connection_log": self.show_connection_log,
        })
    }
}

/// 拆 `host[:port]`：端口缺省 [`DEFAULT_STUN_PORT`]。
///
/// 只按**最后一个** `:` 拆；两头空白去掉。IPv6 字面量（`[::1]:3478`）不在
/// 支持范围（STUN 隧道面向 IPv4，上游连接也固定先解析 IPv4）。
pub fn parse_host_port(raw: &str, default_port: u16) -> Option<(String, u16)> {
    let text = raw.trim();
    if text.is_empty() {
        return None;
    }
    match text.rsplit_once(':') {
        Some((host, port)) => {
            let host = host.trim();
            if host.is_empty() {
                return None;
            }
            match port.trim().parse::<u16>() {
                Ok(port) if port > 0 => Some((host.to_string(), port)),
                // `host:xxx` 拆出来的不是端口：整串当主机名（让它去 DNS 报错）
                _ => Some((text.to_string(), default_port)),
            }
        }
        None => Some((text.to_string(), default_port)),
    }
}

/// STUN 的落盘根：`<data_dir>/config/stun`。
pub struct StunStore {
    root: PathBuf,
}

impl StunStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// `<root>/settings.json`。
    pub fn settings_path(&self) -> PathBuf {
        self.root.join("settings.json")
    }

    /// 读全局设置。读不到 / 坏了都当「还没配过」—— 最坏是回落到内置默认。
    pub fn read_settings(&self) -> StunSettings {
        let Ok(text) = std::fs::read_to_string(self.settings_path()) else {
            return StunSettings::default();
        };
        serde_json::from_str::<StunSettings>(&text)
            .unwrap_or_default()
            .normalized()
    }

    /// 写全局设置（原子写：先写同目录临时文件再 rename）。
    pub fn write_settings(&self, settings: &StunSettings) -> Result<()> {
        let body = serde_json::to_string_pretty(settings)?;
        write_atomic(&self.settings_path(), &body)
    }
}

/// 原子写文本：先写同目录的临时文件再 `rename`。
///
/// 临时文件名带 pid + 进程内序号（同 frp / instance 存储的理由：共用固定
/// 名字的临时文件会让并发写的第二个写者 rename 失败）。
fn write_atomic(path: &Path, body: &str) -> Result<()> {
    use std::io::Write as _;
    use std::sync::atomic::{AtomicU64, Ordering};

    static SEQ: AtomicU64 = AtomicU64::new(0);

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp = PathBuf::from(format!(
        "{}.{}.{}.tmp",
        path.display(),
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));

    let write_result = (|| -> std::io::Result<()> {
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&tmp)?;
        file.write_all(body.as_bytes())?;
        file.flush()
    })();
    if let Err(e) = write_result {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.into());
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root(tag: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!(
            "edgecube-stun-settings-{tag}-{}-{}",
            std::process::id(),
            crate::util::now_ms()
        ));
        std::fs::create_dir_all(&root).expect("应能建临时目录");
        root
    }

    #[test]
    fn defaults_round_trip_and_are_clamped() {
        let root = temp_root("defaults");
        let store = StunStore::new(&root);
        let settings = store.read_settings();
        assert_eq!(settings, StunSettings::default());
        assert_eq!(settings.effective_servers().len(), 8);

        store.write_settings(&settings).expect("应能写入");
        let back = store.read_settings();
        assert_eq!(back, settings);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn out_of_range_values_are_clamped_on_read() {
        let root = temp_root("clamp");
        let store = StunStore::new(&root);
        std::fs::write(
            store.settings_path(),
            r#"{"keep_alive_seconds": 9999, "max_connections": 0, "keepalive_http": "  ", "servers": [" a.com ", "", "b.com:3479"]}"#,
        )
        .unwrap();
        let settings = store.read_settings();
        assert_eq!(settings.keep_alive_seconds, KEEP_ALIVE_MAX);
        assert_eq!(settings.max_connections, MAX_CONNECTIONS_MIN);
        assert_eq!(settings.keepalive_http, DEFAULT_KEEPALIVE_HTTP);
        assert_eq!(
            settings.servers,
            vec!["a.com".to_string(), "b.com:3479".to_string()]
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn broken_file_falls_back_to_defaults() {
        let root = temp_root("broken");
        let store = StunStore::new(&root);
        std::fs::write(store.settings_path(), "not json").unwrap();
        assert_eq!(store.read_settings(), StunSettings::default());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn parse_host_port_variants() {
        assert_eq!(
            parse_host_port("stun.example.com", 3478),
            Some(("stun.example.com".to_string(), 3478))
        );
        assert_eq!(
            parse_host_port("stun.example.com:9999", 3478),
            Some(("stun.example.com".to_string(), 9999))
        );
        assert_eq!(
            parse_host_port("1.2.3.4:0", 3478),
            Some(("1.2.3.4:0".to_string(), 3478)),
            "端口 0 不是有效端口，整串当主机名"
        );
        assert_eq!(
            parse_host_port("host:notaport", 3478),
            Some(("host:notaport".to_string(), 3478))
        );
        assert_eq!(parse_host_port("   ", 3478), None);
    }

    #[test]
    fn empty_servers_means_builtin_list() {
        let settings = StunSettings {
            servers: vec![],
            ..StunSettings::default()
        };
        assert_eq!(
            settings.effective_servers(),
            DEFAULT_SERVERS.map(str::to_string).to_vec()
        );
    }
}
