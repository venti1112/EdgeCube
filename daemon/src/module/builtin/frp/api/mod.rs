//! 各平台 API 的统一门面 + 共用的 HTTP / 解析设施。
//!
//! # 为什么整段流程都在 daemon
//!
//! 「发起授权 → 轮询 → 拿令牌落盘」是跨分钟级的长流程：轮询要一直活着，
//! 令牌只能存一处。放 App 侧意味着用户一切后台就断、令牌要在每个客户端各存
//! 一份。这里由 daemon 统一做（`frp.login.*`），App 只把授权链接丢给浏览器、
//! 显示状态。
//!
//! # 各家 API 的实现口径
//!
//! 端点、包络判定、字段映射按各家 API 的实际返回来。刻意的取舍有两处：
//!
//! 1. **OpenFrp 的解密在 Rust 侧做**，用 `crypto_box` —— 同为 NaCl box
//!    （X25519 + XSalsa20-Poly1305），但密文的排布约定与 NaCl 原生相反：
//!    NaCl 是 `MAC ‖ 密文`，RustCrypto 的 `aead` 惯例是 `密文 ‖ MAC`。
//!    所以走 `decrypt_in_place_detached` 手动拆 nonce / MAC / 密文，
//!    不去猜顺序。
//! 2. **错误分类更细**。「令牌失效」单独一个码，前端才能只对这一类
//!    「清凭据 + 引导重登」，而不是对所有错误都清一遍。

pub mod chml;
pub mod mefrp;
pub mod msl;
pub mod openfrp;
pub mod sakura;

use std::sync::OnceLock;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::model::{Account, FrpNode, Provider, RemoteTunnel, SavedTunnel};
use super::store::FrpStore;
use crate::error::RpcError;

/// 所有出站请求的超时（各家统一 15 秒）。
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// 轮询间隔缺省值（秒）—— 服务端没给 `interval` 时用它。
pub const DEFAULT_POLL_SECS: u64 = 5;

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();

/// 全局复用的 HTTP 客户端（连接池 + 统一超时 / User-Agent）。
///
/// 各家平台都要求 `EdgeCube/<版本>` 这个 UA（OpenFrp 明确说没有会被防火墙
/// 拦）；UA 在客户端上设一次，省掉每条请求的重复。
pub fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .user_agent(format!("EdgeCube/{}", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("构建 FRP HTTP 客户端")
    })
}

// ---------------------------------------------------------------------------
// 错误
// ---------------------------------------------------------------------------

/// 平台 API 调用失败。`code` 直接作为 `RpcError.code` 发给前端。
#[derive(Debug, Clone)]
pub struct ApiError {
    pub code: &'static str,
    pub message: String,
}

impl ApiError {
    /// 平台自己的业务失败（包络里带出来的那句 msg）。
    pub fn business(message: impl Into<String>) -> Self {
        Self {
            code: "frp_api_error",
            message: message.into(),
        }
    }

    /// 令牌过期 / 无效：前端应清凭据并引导重登。
    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self {
            code: "frp_unauthorized",
            message: message.into(),
        }
    }

    pub fn not_logged_in(provider: Provider) -> Self {
        Self {
            code: "frp_not_logged_in",
            message: format!("尚未登录 {}", provider.display_name()),
        }
    }

    /// 响应不是预期形状（缺字段、JSON 解析失败、解密失败……）。
    pub fn protocol(message: impl Into<String>) -> Self {
        Self {
            code: "frp_protocol_error",
            message: message.into(),
        }
    }

    /// 网络层失败（含超时 / TLS / DNS）。
    pub fn network(message: impl Into<String>) -> Self {
        Self {
            code: "frp_network_error",
            message: message.into(),
        }
    }

    /// 生成 frpc 配置时的问题（配置为空、节点没地址……）。
    pub fn config(message: impl Into<String>) -> Self {
        Self {
            code: "frp_config_error",
            message: message.into(),
        }
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self {
            code: "internal",
            message: message.into(),
        }
    }
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl From<ApiError> for RpcError {
    fn from(err: ApiError) -> Self {
        RpcError::new(err.code, err.message)
    }
}

impl From<reqwest::Error> for ApiError {
    fn from(err: reqwest::Error) -> Self {
        Self::network(format!("网络请求失败：{err}"))
    }
}

// ---------------------------------------------------------------------------
// 解析小工具
// ---------------------------------------------------------------------------

/// 宽松解析各家 API 的布尔字段。
///
/// 同一个字段各家给的类型都不一样（bool / int / "true"），照 `as bool` 直接转
/// 会在 MSL 的 `status`（其实是 0/1）上炸掉。
pub fn parse_bool(value: Option<&Value>, or_else: bool) -> bool {
    match value {
        None | Some(Value::Null) => or_else,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().map(|v| v != 0.0).unwrap_or(or_else),
        Some(Value::String(s)) => {
            let v = s.trim().to_ascii_lowercase();
            if v.is_empty() {
                or_else
            } else {
                matches!(v.as_str(), "true" | "1" | "yes" | "on")
            }
        }
        _ => or_else,
    }
}

/// 取字符串字段；数字转十进制文本。
pub fn str_field(value: &Value, key: &str) -> String {
    match value.get(key) {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(other) => other.to_string(),
    }
}

/// 取无符号整数字段，兼容数字与数字字符串。
pub fn u32_field(value: &Value, key: &str) -> Option<u32> {
    match value.get(key) {
        Some(Value::Number(n)) => n.as_u64().and_then(|v| u32::try_from(v).ok()),
        Some(Value::String(s)) => s.trim().parse().ok(),
        _ => None,
    }
}

/// 取布尔字段（缺省值见 [`parse_bool`]）。
pub fn bool_field(value: &Value, key: &str, or_else: bool) -> bool {
    parse_bool(value.get(key), or_else)
}

/// 取对象字段；不是对象就给个空对象。
pub fn object_field(value: &Value, key: &str) -> Map<String, Value> {
    value
        .get(key)
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default()
}

/// 取数组字段；不是数组就是空。
pub fn array_field(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// 节点 ID 转整数：各家的创建接口都收数字，解析不了就按 0 传。
pub fn node_id_int(id: &str) -> i64 {
    id.trim().parse().unwrap_or(0)
}

/// 响应体 JSON 解析；失败算平台侧协议问题。
pub fn parse_json(status: u16, body: &str) -> Result<Value, ApiError> {
    serde_json::from_str(body)
        .map_err(|e| ApiError::protocol(format!("平台响应不是合法 JSON（HTTP {status}）：{e}")))
}

/// 轮询响应的 JSON 解析：读不懂就记条日志返回 `None`，交给调用方接着轮。
///
/// 未完成授权时平台可能回空体（OpenFrp 就是 204 空体），也可能被 CDN / 网关
/// 换成 HTML 错误页；这类响应一律按「还没授权好」处理 —— 单次读不懂的响应
/// 不该把整个登录会话判死刑。
pub fn parse_poll_json(status: u16, body: &str) -> Option<Value> {
    match serde_json::from_str(body) {
        Ok(value) => Some(value),
        Err(e) => {
            tracing::debug!(status, error = %e, "轮询响应不是合法 JSON，按未完成继续等待");
            None
        }
    }
}

/// 包络里的提示语；没有就退回 `HTTP <状态码>`。
pub fn envelope_message(json: &Value, status: u16) -> String {
    let msg = str_field(json, "msg");
    if !msg.is_empty() {
        return msg;
    }
    let message = str_field(json, "message");
    if !message.is_empty() {
        return message;
    }
    format!("HTTP {status}")
}

/// 存储层的同步读写（都是小文件）丢进阻塞线程池，别卡住 tokio 工作线程。
pub async fn store_op<T, F>(store: &FrpStore, op: F) -> Result<T, ApiError>
where
    F: FnOnce(&FrpStore) -> Result<T, ApiError> + Send + 'static,
    T: Send + 'static,
{
    let store = store.clone();
    match tokio::task::spawn_blocking(move || op(&store)).await {
        Ok(result) => result,
        Err(join) => Err(ApiError::internal(format!("FRP 存储任务失败：{join}"))),
    }
}

// ---------------------------------------------------------------------------
// 登录流程
// ---------------------------------------------------------------------------

/// 浏览器授权登录在 daemon 侧要留存的会话状态。
///
/// 各家的轮询参数不同，只有 daemon 需要它 —— 前端拿到的是
/// [`LoginStart`]（授权页地址 + 设备码），拿不到这些私密状态。
#[derive(Debug, Clone)]
pub enum LoginFlow {
    /// MSL Frp：OAuth 应用授权，轮询要带回 ssid + csrf。
    Msl { ssid: String, csrf: String },
    /// OpenFrp：远程安全登录，轮询带回 request_uuid，密文用私钥解。
    OpenFrp {
        request_uuid: String,
        secret: [u8; 32],
    },
    /// ChmlFrp：QZhua 设备码授权。
    Chml {
        device_code: String,
        interval_ms: u64,
        expires_at_ms: u64,
    },
}

impl LoginFlow {
    /// 本次轮询的间隔（MSL / OpenFrp 固定 5 秒，ChmlFrp 用服务端给的
    /// `interval`，`slow_down` 时再加 5 秒）。
    pub fn interval_ms(&self) -> u64 {
        match self {
            LoginFlow::Chml { interval_ms, .. } => *interval_ms,
            _ => DEFAULT_POLL_SECS * 1000,
        }
    }

    /// 轮询所需的平台 key（会话表以此分槽）。
    pub fn provider(&self) -> Provider {
        match self {
            LoginFlow::Msl { .. } => Provider::MslFrp,
            LoginFlow::OpenFrp { .. } => Provider::OpenFrp,
            LoginFlow::Chml { .. } => Provider::ChmlFrp,
        }
    }
}

/// 发起登录后给前端看的东西：授权页地址 + 设备码（没有就是空串）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginStart {
    pub url: String,
    #[serde(default)]
    pub user_code: String,
}

/// 一次轮询的结果。
#[derive(Debug, Clone)]
pub enum PollOutcome {
    /// 用户还没在浏览器里点完，继续等。
    Pending,
    /// 拿到登录令牌。
    Done(String),
}

// ---------------------------------------------------------------------------
// 门面
// ---------------------------------------------------------------------------

/// 发起浏览器授权登录（只有支持浏览器登录的平台会走到这里）。
pub async fn login_start(provider: Provider) -> Result<(LoginStart, LoginFlow), ApiError> {
    match provider {
        Provider::MslFrp => msl::create_app_login().await,
        Provider::OpenFrp => openfrp::create_browser_login().await,
        Provider::ChmlFrp => chml::create_device_login().await,
        other => Err(ApiError::business(format!(
            "{} 不支持浏览器登录",
            other.display_name()
        ))),
    }
}

/// 轮询一次授权结果。`flow` 可能在过程中被就地调整（ChmlFrp 的 `slow_down`）。
pub async fn login_poll(store: &FrpStore, flow: &mut LoginFlow) -> Result<PollOutcome, ApiError> {
    match flow {
        LoginFlow::Msl { ssid, csrf } => msl::poll_app_login(store, ssid, csrf).await,
        LoginFlow::OpenFrp {
            request_uuid,
            secret,
        } => openfrp::poll_browser_login(request_uuid, secret).await,
        LoginFlow::Chml {
            device_code,
            interval_ms,
            expires_at_ms,
        } => chml::poll_device_login(store, device_code, interval_ms, *expires_at_ms).await,
    }
}

/// 校验一个用户粘贴的访问令牌，返回该令牌对应的账号。
pub async fn verify_token(
    store: &FrpStore,
    provider: Provider,
    token: &str,
) -> Result<Account, ApiError> {
    match provider {
        Provider::MslFrp => msl::user_info(token).await,
        Provider::OpenFrp => openfrp::user_info(token).await,
        Provider::SakuraFrp => sakura::user_info(token).await,
        Provider::ChmlFrp => chml::user_info(store, token).await,
        Provider::MeFrp => mefrp::user_info(token).await,
        Provider::Custom => Err(ApiError::business("自定义 FRP 没有账号体系")),
    }
}

/// 拉一次账号信息（用已保存的令牌）。
pub async fn user_info(store: &FrpStore, provider: Provider) -> Result<Account, ApiError> {
    let token = access_token(store, provider).await?;
    verify_token(store, provider, &token).await
}

/// 节点列表。
pub async fn node_list(store: &FrpStore, provider: Provider) -> Result<Vec<FrpNode>, ApiError> {
    let token = access_token(store, provider).await?;
    match provider {
        Provider::MslFrp => msl::node_list(&token).await,
        Provider::OpenFrp => openfrp::node_list(&token).await,
        // SakuraFrp 要先按用户等级过滤：等级不够的节点展示了也连不上。
        Provider::SakuraFrp => {
            let level = sakura::user_level(&token).await?;
            sakura::node_list(&token, level).await
        }
        // ChmlFrp 的节点列表无需鉴权。
        Provider::ChmlFrp => chml::node_list().await,
        Provider::MeFrp => mefrp::node_list(&token).await,
        Provider::Custom => Err(ApiError::business("自定义 FRP 没有节点列表")),
    }
}

/// 平台侧的隧道列表。
pub async fn tunnel_list(
    store: &FrpStore,
    provider: Provider,
) -> Result<Vec<RemoteTunnel>, ApiError> {
    let token = access_token(store, provider).await?;
    match provider {
        Provider::MslFrp => msl::tunnel_list(&token).await,
        Provider::OpenFrp => openfrp::proxy_list(&token).await,
        Provider::SakuraFrp => sakura::tunnel_list(&token).await,
        Provider::ChmlFrp => chml::tunnel_list(store, &token).await,
        Provider::MeFrp => mefrp::proxy_list(&token).await,
        Provider::Custom => Err(ApiError::business("自定义 FRP 没有远端隧道")),
    }
}

/// 创建隧道时要提交的字段（各家映射到自己的命名）。
pub struct CreateTunnelReq {
    pub node: FrpNode,
    pub name: String,
    pub kind: String,
    pub local_ip: String,
    pub local_port: u32,
    pub remote_port: u32,
}

/// 在平台上创建隧道。
pub async fn create_tunnel(
    store: &FrpStore,
    provider: Provider,
    req: &CreateTunnelReq,
) -> Result<(), ApiError> {
    let token = access_token(store, provider).await?;
    match provider {
        Provider::MslFrp => msl::add_tunnel(&token, req).await,
        Provider::OpenFrp => openfrp::new_proxy(&token, req).await,
        Provider::SakuraFrp => sakura::create_tunnel(&token, req).await,
        Provider::ChmlFrp => chml::create_tunnel(store, &token, req).await,
        Provider::MeFrp => mefrp::create_proxy(&token, req).await,
        Provider::Custom => Err(ApiError::business("自定义 FRP 不能创建远端隧道")),
    }
}

/// 删除平台上的隧道。
pub async fn delete_tunnel(
    store: &FrpStore,
    provider: Provider,
    tunnel_id: &str,
) -> Result<(), ApiError> {
    let token = access_token(store, provider).await?;
    match provider {
        Provider::MslFrp => msl::delete_tunnel(&token, tunnel_id).await,
        Provider::OpenFrp => openfrp::remove_proxy(&token, tunnel_id).await,
        Provider::SakuraFrp => sakura::delete_tunnel(&token, tunnel_id).await,
        Provider::ChmlFrp => chml::delete_tunnel(store, &token, tunnel_id).await,
        Provider::MeFrp => mefrp::delete_proxy(&token, tunnel_id).await,
        Provider::Custom => Err(ApiError::business("自定义 FRP 不能删除远端隧道")),
    }
}

/// 拉取某条已保存隧道对应的成品 frpc 配置。
///
/// 只处理「配置在平台侧」的四家；custom 与 OpenFrp 的配置不由远端下发，
/// 由 [`super::builder`] 在调用本函数之前就分流出去了（走到这里说明调用方写错）。
pub async fn remote_config(store: &FrpStore, tunnel: &SavedTunnel) -> Result<String, ApiError> {
    let provider = tunnel.provider;
    let token = access_token(store, provider).await?;
    match provider {
        Provider::MslFrp => msl::tunnel_config(&token, &tunnel.remote_tunnel_id).await,
        Provider::ChmlFrp => {
            let node = if tunnel.node_name.is_empty() {
                tunnel.node_id.clone()
            } else {
                tunnel.node_name.clone()
            };
            chml::tunnel_config(store, &token, &node, &tunnel.name).await
        }
        Provider::SakuraFrp => {
            if tunnel.remote_tunnel_id.is_empty() {
                return Err(ApiError::config("该隧道未关联远端隧道 ID，无法拉取配置"));
            }
            sakura::tunnel_config(&token, &tunnel.remote_tunnel_id).await
        }
        Provider::MeFrp => mefrp::tunnel_config(&token, &tunnel.remote_tunnel_id).await,
        // OpenFrp 的成品配置由本地拼装（官方客户端闭源，见 builder）。
        Provider::OpenFrp => Err(ApiError::internal("OpenFrp 的配置由本地拼装")),
        // custom 用本地那份，不该来远端拉。
        Provider::Custom => Err(ApiError::internal("自定义隧道没有远端配置")),
    }
}

/// 取某平台当前可用的登录令牌。
///
/// ChmlFrp 存的是 `{at, rt, exp}`，临近过期会在这里刷新并回写，
/// 所以它比别家多一步。
pub async fn access_token(store: &FrpStore, provider: Provider) -> Result<String, ApiError> {
    let raw = store_op(store, move |store| Ok(store.token(provider)))
        .await?
        .ok_or_else(|| ApiError::not_logged_in(provider))?;
    if provider == Provider::ChmlFrp {
        return chml::resolve_access_token(store, &raw).await;
    }
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_bool_accepts_every_shape() {
        assert!(parse_bool(Some(&json!(true)), false));
        assert!(parse_bool(Some(&json!(1)), false));
        assert!(!parse_bool(Some(&json!(0)), true));
        assert!(parse_bool(Some(&json!("true")), false));
        assert!(parse_bool(Some(&json!(" YES ")), false));
        // 空串算「没说」→ 用默认值，而不是 false
        assert!(parse_bool(Some(&json!("")), true));
        assert!(!parse_bool(Some(&json!("")), false));
        assert!(parse_bool(None, true));
        assert!(!parse_bool(Some(&json!([])), false));
    }

    #[test]
    fn field_helpers_tolerate_odd_types() {
        let value = json!({ "id": 42, "name": "cn-1", "port": "25566", "nil": null });
        assert_eq!(str_field(&value, "id"), "42");
        assert_eq!(str_field(&value, "name"), "cn-1");
        assert_eq!(str_field(&value, "nil"), "");
        assert_eq!(str_field(&value, "missing"), "");
        assert_eq!(u32_field(&value, "port"), Some(25566));
        assert_eq!(u32_field(&value, "name"), None);
    }

    #[test]
    fn login_flow_polls_on_schedule() {
        let msl = LoginFlow::Msl {
            ssid: "s".into(),
            csrf: "c".into(),
        };
        assert_eq!(msl.interval_ms(), 5000);
        assert_eq!(msl.provider(), Provider::MslFrp);
        let chml = LoginFlow::Chml {
            device_code: "d".into(),
            interval_ms: 10_000,
            expires_at_ms: 0,
        };
        assert_eq!(chml.interval_ms(), 10_000);
    }
}
