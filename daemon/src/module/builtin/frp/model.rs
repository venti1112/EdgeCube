//! FRP 映射隧道的领域模型（供应商无关的统一视图）。
//!
//! 有两处刻意的差异，都是线上格式的规范化：
//!
//! 1. **磁盘 / 线上分两套键名**。元数据文件是 camelCase，落在
//!    `config/frp/config/<localId>.json`，
//!    发给前端的则是 snake_case（与 daemon 其余模块一致）——
//!    两边各有一处显式转换，见 [`SavedTunnel::to_wire_json`]。
//! 2. **`frp_token` 不下发前端**。它是拼 frpc 配置用的私密字段
//!    （OpenFrp 的 user token / ChmlFrp 的 usertoken / ME Frp 的 frpToken），
//!    只留在 daemon 的内存与 `auth.json` 里。

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::error::RpcError;

/// 映射平台。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub enum Provider {
    MslFrp,
    OpenFrp,
    SakuraFrp,
    ChmlFrp,
    MeFrp,
    /// 自定义 FRP：不进平台，用户自己填 / 粘贴 frpc 配置。
    #[default]
    Custom,
}

/// 全部平台，顺序即「选择映射平台」页的展示顺序。
pub const ALL_PROVIDERS: [Provider; 6] = [
    Provider::MslFrp,
    Provider::OpenFrp,
    Provider::SakuraFrp,
    Provider::ChmlFrp,
    Provider::MeFrp,
    Provider::Custom,
];

impl Provider {
    /// 持久化用的稳定标识。
    pub fn key(self) -> &'static str {
        match self {
            Provider::MslFrp => "mslfrp",
            Provider::OpenFrp => "openfrp",
            Provider::SakuraFrp => "sakurafrp",
            Provider::ChmlFrp => "chmlfrp",
            Provider::MeFrp => "mefrp",
            Provider::Custom => "custom",
        }
    }

    /// 展示名（custom 是空串，前端用本地文案「自定义 FRP」）。
    pub fn display_name(self) -> &'static str {
        match self {
            Provider::MslFrp => "MSL Frp",
            Provider::OpenFrp => "OpenFrp",
            Provider::SakuraFrp => "Sakura Frp",
            Provider::ChmlFrp => "ChmlFrp",
            Provider::MeFrp => "ME Frp",
            Provider::Custom => "",
        }
    }

    /// 该平台是否需要账号登录（custom 不需要）。
    pub fn requires_login(self) -> bool {
        self != Provider::Custom
    }

    /// 是否走浏览器授权登录。
    ///
    /// MSL 已下线密码登录；OpenFrp 已下线 Authorization 粘贴登录（改走
    /// curve25519 远程安全登录）；ChmlFrp 走 QZhua 设备码授权。
    pub fn supports_browser_login(self) -> bool {
        matches!(
            self,
            Provider::MslFrp | Provider::OpenFrp | Provider::ChmlFrp
        )
    }

    /// 是否支持粘贴访问 Token 登录（仅 Sakura / ME 这两家）。
    pub fn supports_token_login(self) -> bool {
        matches!(self, Provider::SakuraFrp | Provider::MeFrp)
    }

    pub fn from_key(key: &str) -> Option<Self> {
        ALL_PROVIDERS.into_iter().find(|p| p.key() == key)
    }

    /// 需要令牌的平台里，取不到令牌时报这个错。
    pub fn not_logged_in(self) -> RpcError {
        RpcError::new(
            "frp_not_logged_in",
            format!("尚未登录 {}", self.display_name()),
        )
    }
}

impl Serialize for Provider {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.key())
    }
}

impl<'de> Deserialize<'de> for Provider {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(deserializer)?;
        Provider::from_key(&raw)
            .ok_or_else(|| serde::de::Error::custom(format!("未知的映射平台 `{raw}`")))
    }
}

// ---------------------------------------------------------------------------
// 账号
// ---------------------------------------------------------------------------

/// 供应商无关的账号信息（各家 API 的用户信息映射到统一字段）。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Account {
    /// 用户名 / 昵称。
    #[serde(default)]
    pub username: String,
    /// 用户组显示名（如「普通用户」「VIP」）。
    #[serde(default)]
    pub group: String,
    /// 已用 / 上限隧道数；API 未提供时为 `None`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub used_tunnels: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_tunnels: Option<u32>,
    /// frpc 侧鉴权 token（OpenFrp 的 user token、ChmlFrp 的 usertoken、
    /// ME Frp 的 frpToken）。与登录令牌不同，拼配置用，**不下发前端**。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frp_token: Option<String>,
}

impl Account {
    /// 给前端看的账号视图（剥掉 `frp_token`）。
    pub fn public_json(&self) -> Value {
        json!({
            "username": self.username,
            "group": self.group,
            "used_tunnels": self.used_tunnels,
            "max_tunnels": self.max_tunnels,
        })
    }
}

// ---------------------------------------------------------------------------
// 平台侧：节点与隧道
// ---------------------------------------------------------------------------

/// 平台节点。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrpNode {
    /// 节点 ID（数字或字符串，统一存字符串）。
    pub id: String,
    pub name: String,
    /// frps 连接地址（域名 / IP）；部分 API 不下发。
    pub hostname: String,
    /// frps 服务端口。
    pub server_port: u16,
    /// 允许的远程端口范围；`None` = 未知。
    pub min_port: Option<u32>,
    pub max_port: Option<u32>,
    pub description: String,
    pub online: bool,
    /// 是否付费 / 会员专属节点。
    pub vip: bool,
    /// 是否支持 UDP（基岩版需要）。
    pub udp_support: bool,
}

impl Default for FrpNode {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            hostname: String::new(),
            server_port: 7000,
            min_port: None,
            max_port: None,
            description: String::new(),
            online: true,
            vip: false,
            udp_support: true,
        }
    }
}

/// 平台上已存在的隧道。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RemoteTunnel {
    pub id: String,
    pub name: String,
    pub node_id: String,
    pub node_name: String,
    /// tcp / udp / http / https。`kind` 是给 `type` 关键字让路。
    #[serde(rename = "type")]
    pub kind: String,
    pub local_ip: String,
    pub local_port: u32,
    /// 远程端口；http(s) 隧道可能没有。
    pub remote_port: Option<u32>,
    /// 完整公网连接地址（OpenFrp 的 connectAddress、Sakura 的 remote）。
    pub remote_address: String,
    pub online: bool,
}

impl RemoteTunnel {
    /// 展示用公网地址。
    pub fn display_address(&self) -> String {
        if !self.remote_address.is_empty() {
            return self.remote_address.clone();
        }
        match self.remote_port {
            Some(port) => format!("{}:{port}", self.node_name),
            None => self.node_name.clone(),
        }
    }
}

// ---------------------------------------------------------------------------
// 本地注册表
// ---------------------------------------------------------------------------

/// 已保存到本地注册表的隧道。
///
/// 序列化用 camelCase：磁盘上的文件落在
/// `config/frp/config/<localId>.json`。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SavedTunnel {
    /// 本地唯一 ID（随机 16 位十六进制，与实例 ID 同策略）。
    pub local_id: String,
    pub provider: Provider,
    /// 显示名。
    pub name: String,
    /// 平台上的隧道 ID（custom 为空）。
    pub remote_tunnel_id: String,
    pub node_id: String,
    pub node_name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub local_ip: String,
    pub local_port: u32,
    pub remote_port: Option<u32>,
    /// 公网连接地址（保存时已知则记录）。
    pub remote_address: String,
    /// 自定义隧道的完整 TOML（仅 provider == custom）。
    pub custom_toml: String,
}

impl SavedTunnel {
    /// 展示用公网地址。
    pub fn display_address(&self) -> String {
        if !self.remote_address.is_empty() {
            return self.remote_address.clone();
        }
        if let (Some(port), true) = (self.remote_port, !self.node_name.is_empty()) {
            return format!("{}:{port}", self.node_name);
        }
        self.node_name.clone()
    }

    /// 线上格式（snake_case）。`config_exists` 由调用方填。
    pub fn to_wire_json(&self, config_exists: bool) -> Value {
        json!({
            "local_id": self.local_id,
            "provider": self.provider,
            "name": self.name,
            "remote_tunnel_id": self.remote_tunnel_id,
            "node_id": self.node_id,
            "node_name": self.node_name,
            "type": self.kind,
            "local_ip": self.local_ip,
            "local_port": self.local_port,
            "remote_port": self.remote_port,
            "remote_address": self.remote_address,
            "config_exists": config_exists,
        })
    }
}

/// 保存隧道的入参（`frp.tunnels.save`，snake_case 线上格式）。
#[derive(Debug, Clone, Deserialize)]
pub struct TunnelInput {
    /// 已有条目的 ID；缺省 = 新建。
    #[serde(default)]
    pub local_id: Option<String>,
    pub provider: Provider,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub remote_tunnel_id: String,
    #[serde(default)]
    pub node_id: String,
    #[serde(default)]
    pub node_name: String,
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub local_ip: Option<String>,
    #[serde(default)]
    pub local_port: Option<u32>,
    #[serde(default)]
    pub remote_port: Option<u32>,
    #[serde(default)]
    pub remote_address: String,
    /// custom：整段粘贴的 frpc 配置。
    #[serde(default)]
    pub custom_toml: Option<String>,
    /// custom：「简易表单」模式的结构化字段。
    #[serde(default)]
    pub custom_form: Option<CustomForm>,
}

/// 自定义 FRP 的简易表单。
///
/// 端口是 `Option`：前端文本框可能空着，留到 `frp.tunnels.save` 统一校验后弹
/// 「请完整填写隧道名称与端口」；在这里就要求非空的话，空值会变成
/// `invalid_params` 的参数解析报错，对不上那句提示。
#[derive(Debug, Clone, Deserialize)]
pub struct CustomForm {
    pub server_addr: String,
    pub server_port: Option<u32>,
    #[serde(default)]
    pub user: String,
    #[serde(default)]
    pub auth_token: String,
    #[serde(default = "default_protocol")]
    pub kind: String,
    #[serde(default = "default_local_ip")]
    pub local_ip: String,
    pub local_port: Option<u32>,
    pub remote_port: Option<u32>,
    #[serde(default = "default_tls")]
    pub tls_enable: bool,
}

impl CustomForm {
    /// 简易表单 → frpc TOML。
    ///
    /// `name` 是表单外那条隧道名（两种模式共用同一个输入框）。
    pub fn to_toml(&self, name: &str) -> String {
        let mut out = String::new();
        out.push_str(&format!(
            "serverAddr = {}\n",
            toml_quote(self.server_addr.trim())
        ));
        out.push_str(&format!(
            "serverPort = {}\n",
            self.server_port.unwrap_or(7000)
        ));
        let user = self.user.trim();
        if !user.is_empty() {
            out.push_str(&format!("user = {}\n", toml_quote(user)));
        }
        let token = self.auth_token.trim();
        if !token.is_empty() {
            out.push_str(&format!("auth.token = {}\n", toml_quote(token)));
        }
        out.push_str(&format!("transport.tls.enable = {}\n", self.tls_enable));
        out.push_str("log.to = \"console\"\n");
        out.push_str("log.level = \"info\"\n\n");
        out.push_str("[[proxies]]\n");
        out.push_str(&format!("name = {}\n", toml_quote(name)));
        out.push_str(&format!("type = {}\n", toml_quote(&self.kind)));
        out.push_str(&format!("localIP = {}\n", toml_quote(&self.local_ip)));
        out.push_str(&format!(
            "localPort = {}\n",
            self.local_port.unwrap_or(25565)
        ));
        out.push_str(&format!("remotePort = {}\n", self.remote_port.unwrap_or(0)));
        out
    }
}

/// TOML 基本字符串转义（反斜杠与双引号）。
pub(crate) fn toml_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn default_protocol() -> String {
    "tcp".to_string()
}

fn default_local_ip() -> String {
    "127.0.0.1".to_string()
}

fn default_tls() -> bool {
    true
}

impl TunnelInput {
    /// 线上入参 → 领域模型。`local_id` 由调用方决定（新建时生成）。
    ///
    /// 简易表单的字段优先于平铺字段（两条路径不会同时有值）。
    pub fn into_tunnel(self, local_id: String) -> SavedTunnel {
        let kind = self
            .custom_form
            .as_ref()
            .map(|form| form.kind.clone())
            .or(self.kind)
            .filter(|k| !k.trim().is_empty())
            .unwrap_or_else(|| "tcp".to_string());
        let local_ip = self
            .custom_form
            .as_ref()
            .map(|form| form.local_ip.clone())
            .or(self.local_ip)
            .filter(|ip| !ip.trim().is_empty())
            .unwrap_or_else(default_local_ip);
        let local_port = self
            .custom_form
            .as_ref()
            .and_then(|form| form.local_port)
            .or(self.local_port)
            .unwrap_or(25565);
        let remote_port = self
            .custom_form
            .as_ref()
            .and_then(|form| form.remote_port)
            .or(self.remote_port);
        let name = if self.name.trim().is_empty() {
            "Custom".to_string()
        } else {
            self.name.trim().to_string()
        };

        // 自定义隧道的配置：粘贴模式原样收下，简易表单由 daemon 生成
        // （前端只发用户填的字段）。
        let custom_toml = match (&self.custom_toml, &self.custom_form) {
            (Some(text), _) if !text.trim().is_empty() => text.clone(),
            (_, Some(form)) => form.to_toml(&name),
            _ => String::new(),
        };

        // 自定义隧道的公网地址由表单里的服务器地址拼出来。
        let remote_address = match (&self.custom_form, remote_port) {
            (Some(form), Some(port)) if !form.server_addr.trim().is_empty() => {
                format!("{}:{port}", form.server_addr.trim())
            }
            _ => self.remote_address,
        };

        SavedTunnel {
            local_id,
            provider: self.provider,
            name,
            remote_tunnel_id: self.remote_tunnel_id,
            node_id: self.node_id,
            node_name: self.node_name,
            kind,
            local_ip,
            local_port,
            remote_port,
            remote_address,
            custom_toml,
        }
    }
}

// ---------------------------------------------------------------------------
// 登录会话
// ---------------------------------------------------------------------------

/// 登录会话状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LoginState {
    /// 从没发起过（或已被清理）。
    Idle,
    /// 等用户在浏览器里完成授权（daemon 正在轮询）。
    Waiting,
    Success,
    Error,
    Cancelled,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_keys_are_stable() {
        assert_eq!(Provider::MslFrp.key(), "mslfrp");
        assert_eq!(Provider::OpenFrp.key(), "openfrp");
        assert_eq!(Provider::SakuraFrp.key(), "sakurafrp");
        assert_eq!(Provider::ChmlFrp.key(), "chmlfrp");
        assert_eq!(Provider::MeFrp.key(), "mefrp");
        assert_eq!(Provider::Custom.key(), "custom");
        assert_eq!(Provider::from_key("mefrp"), Some(Provider::MeFrp));
        assert_eq!(Provider::from_key("nope"), None);
    }

    #[test]
    fn provider_login_capabilities() {
        // MSL / OpenFrp / ChmlFrp 走浏览器授权，Sakura / ME 走令牌粘贴
        for p in [Provider::MslFrp, Provider::OpenFrp, Provider::ChmlFrp] {
            assert!(p.supports_browser_login(), "{} 该支持浏览器登录", p.key());
            assert!(!p.supports_token_login());
        }
        for p in [Provider::SakuraFrp, Provider::MeFrp] {
            assert!(p.supports_token_login(), "{} 该支持令牌登录", p.key());
            assert!(!p.supports_browser_login());
        }
        assert!(!Provider::Custom.requires_login());
    }

    #[test]
    fn account_public_view_hides_frp_token() {
        let account = Account {
            username: "steve".into(),
            group: "普通用户".into(),
            used_tunnels: Some(3),
            max_tunnels: Some(5),
            frp_token: Some("secret-frp-token".into()),
        };
        let wire = account.public_json().to_string();
        assert!(wire.contains("steve"));
        assert!(!wire.contains("secret-frp-token"), "frp_token 不该下发前端");
        assert_eq!(account.public_json()["used_tunnels"], json!(3));
    }

    #[test]
    fn saved_tunnel_file_uses_camel_case() {
        let tunnel = SavedTunnel {
            local_id: "0123456789abcdef".into(),
            provider: Provider::SakuraFrp,
            name: "我的隧道".into(),
            remote_tunnel_id: "114514".into(),
            node_id: "233".into(),
            node_name: "cn-1".into(),
            kind: "tcp".into(),
            local_ip: "127.0.0.1".into(),
            local_port: 25565,
            remote_port: Some(25566),
            remote_address: "cn-1.example.com:25566".into(),
            custom_toml: String::new(),
        };
        let file = serde_json::to_value(&tunnel).unwrap();
        // 落盘文件用 camelCase 键名
        assert_eq!(file["localId"], json!("0123456789abcdef"));
        assert_eq!(file["provider"], json!("sakurafrp"));
        assert_eq!(file["remoteTunnelId"], json!("114514"));
        assert_eq!(file["nodeName"], json!("cn-1"));
        assert_eq!(file["localPort"], json!(25565));
        assert_eq!(file["remotePort"], json!(25566));
        assert!(file.get("local_id").is_none());

        let back: SavedTunnel = serde_json::from_value(file).unwrap();
        assert_eq!(back.provider, Provider::SakuraFrp);
        assert_eq!(back.remote_tunnel_id, "114514");

        // 线上格式反过来是 snake_case
        let wire = tunnel.to_wire_json(true);
        assert_eq!(wire["local_id"], json!("0123456789abcdef"));
        assert_eq!(wire["type"], json!("tcp"));
        assert_eq!(wire["config_exists"], json!(true));
    }

    #[test]
    fn tunnel_input_applies_fallbacks() {
        let input: TunnelInput = serde_json::from_value(json!({
            "provider": "openfrp",
            "name": "  ",
            "node_id": "42",
            "local_port": 25565,
            "remote_port": 30000,
        }))
        .unwrap();
        let tunnel = input.into_tunnel("abcdef0123456789".into());
        assert_eq!(tunnel.name, "Custom", "空名字回退 Custom");
        assert_eq!(tunnel.kind, "tcp");
        assert_eq!(tunnel.local_ip, "127.0.0.1");
        assert_eq!(tunnel.local_port, 25565);
    }

    #[test]
    fn remote_tunnel_display_address_falls_back_to_node_name() {
        let mut tunnel = RemoteTunnel {
            node_name: "cn-1".into(),
            remote_port: Some(25566),
            ..Default::default()
        };
        assert_eq!(tunnel.display_address(), "cn-1:25566");
        tunnel.remote_address = "example.com:25566".into();
        assert_eq!(tunnel.display_address(), "example.com:25566");
    }

    #[test]
    fn easy_form_generates_toml() {
        let form = CustomForm {
            server_addr: "frp.example.com".into(),
            server_port: Some(7000),
            user: "steve".into(),
            auth_token: String::new(),
            kind: "udp".into(),
            local_ip: "127.0.0.1".into(),
            local_port: Some(25565),
            remote_port: Some(25566),
            tls_enable: false,
        };
        assert_eq!(
            form.to_toml("EdgeCube"),
            "serverAddr = \"frp.example.com\"\n\
             serverPort = 7000\n\
             user = \"steve\"\n\
             transport.tls.enable = false\n\
             log.to = \"console\"\n\
             log.level = \"info\"\n\
             \n\
             [[proxies]]\n\
             name = \"EdgeCube\"\n\
             type = \"udp\"\n\
             localIP = \"127.0.0.1\"\n\
             localPort = 25565\n\
             remotePort = 25566\n"
        );
    }

    #[test]
    fn custom_input_prefers_raw_toml_over_easy_form() {
        let easy: TunnelInput = serde_json::from_value(json!({
            "provider": "custom",
            "name": "我的自定义",
            "custom_form": {
                "server_addr": "frp.example.com",
                "server_port": 7000,
                "local_port": 25565,
                "remote_port": 25566,
            },
        }))
        .unwrap();
        let tunnel = easy.into_tunnel("abcdef0123456789".into());
        assert!(
            tunnel
                .custom_toml
                .contains("serverAddr = \"frp.example.com\""),
            "表单该被拼成 TOML：{}",
            tunnel.custom_toml
        );
        assert!(tunnel.custom_toml.contains("name = \"我的自定义\""));
        assert_eq!(tunnel.kind, "tcp");
        assert_eq!(tunnel.local_ip, "127.0.0.1");
        assert_eq!(tunnel.remote_address, "frp.example.com:25566");

        // 粘贴模式优先：两者都给时用原文。
        let raw: TunnelInput = serde_json::from_value(json!({
            "provider": "custom",
            "name": "x",
            "custom_toml": "serverAddr = \"raw\"\n",
            "custom_form": {
                "server_addr": "frp.example.com",
                "server_port": 7000,
                "local_port": 25565,
                "remote_port": 25566,
            },
        }))
        .unwrap();
        assert_eq!(
            raw.into_tunnel("abcdef0123456789".into()).custom_toml,
            "serverAddr = \"raw\"\n"
        );
    }
}
