//! MSL Frp（user.mslmc.net）API 客户端。
//!
//! 响应包络 `{code, data, msg}`，`code == 200` 为成功（HTTP 恒为 200）；
//! 鉴权 `Authorization: Bearer <token>`。
//!
//! 登录走浏览器授权（OAuth 应用授权）：官方已下线密码登录
//! （`POST /user/login` 现在只会回「缺少参数!」）。

use serde_json::{Value, json};

use super::super::model::{Account, FrpNode, RemoteTunnel};
use super::super::store::FrpStore;
use super::{
    ApiError, CreateTunnelReq, LoginFlow, LoginStart, PollOutcome, array_field, bool_field, client,
    envelope_message, node_id_int, parse_json, parse_poll_json, str_field, u32_field,
};

const BASE: &str = "https://user.mslmc.net/api";

/// OAuth 应用标识（写死的 appid）。
const APP_ID: &str = "3JAza1AwWgOQeBj2C2j7OODOPOv";

/// 本地生成 32 位十六进制 csrf（授权与轮询需前后一致）。
fn random_csrf() -> String {
    // rand 0.10：`random_range` 在 `RngExt` 上（见 openfrp.rs 的说明）。
    use rand::RngExt as _;
    let mut rng = rand::rng();
    (0..32)
        .map(|_| char::from_digit(rng.random_range(0..16), 16).unwrap_or('0'))
        .collect()
}

async fn get(path_with_query: &str, token: &str) -> Result<Value, ApiError> {
    let resp = client()
        .get(format!("{BASE}{path_with_query}"))
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .send()
        .await?;
    envelope(resp).await
}

async fn post(path: &str, body: &Value, token: Option<&str>) -> Result<Value, ApiError> {
    let mut req = client()
        .post(format!("{BASE}{path}"))
        .header("Content-Type", "application/json")
        .json(body);
    if let Some(token) = token.filter(|t| !t.is_empty()) {
        req = req.header("Authorization", format!("Bearer {token}"));
    }
    envelope(req.send().await?).await
}

/// 解析包络：`code != 200` 抛业务错误。
async fn envelope(resp: reqwest::Response) -> Result<Value, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    check_envelope(value, status)
}

/// 轮询用的包络解析：读不懂的响应体当「还没授权好」返回 `None`
/// （单次异常先吞掉继续等）；`code != 200` 仍是业务错误。
async fn envelope_poll(resp: reqwest::Response) -> Result<Option<Value>, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let Some(value) = parse_poll_json(status, &body) else {
        return Ok(None);
    };
    check_envelope(value, status).map(Some)
}

/// 包络的 code 判定。
fn check_envelope(value: Value, status: u16) -> Result<Value, ApiError> {
    let code = value.get("code").and_then(Value::as_i64).unwrap_or(-1);
    if code != 200 {
        return Err(ApiError::business(envelope_message(&value, status)));
    }
    Ok(value)
}

/// 发起浏览器授权登录：提交 csrf + appid，返回授权页地址与轮询状态。
pub async fn create_app_login() -> Result<(LoginStart, LoginFlow), ApiError> {
    let csrf = random_csrf();
    let resp = client()
        .post(format!("{BASE}/oauth/createAppLogin"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&[("csrf", csrf.as_str()), ("appid", APP_ID)])
        .send()
        .await?;
    let value = envelope(resp).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let url = str_field(&data, "url");
    let ssid = str_field(&data, "ssid");
    if url.is_empty() || ssid.is_empty() {
        return Err(ApiError::business("授权会话创建失败"));
    }
    let flow = LoginFlow::Msl {
        ssid,
        csrf: csrf.clone(),
    };
    Ok((
        LoginStart {
            url,
            user_code: String::new(),
        },
        flow,
    ))
}

/// 轮询浏览器授权结果：未完成返回 `Pending`；完成返回（续期后的）登录令牌。
pub async fn poll_app_login(
    _store: &FrpStore,
    ssid: &str,
    csrf: &str,
) -> Result<PollOutcome, ApiError> {
    let resp = client()
        .get(format!("{BASE}/oauth/appLogin"))
        .query(&[("ssid", ssid), ("csrf", csrf)])
        .send()
        .await?;
    let Some(value) = envelope_poll(resp).await? else {
        return Ok(PollOutcome::Pending);
    };

    // data 可能是对象（取 token）也可能是裸字符串。
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let token = match &data {
        Value::Object(_) => str_field(&data, "token"),
        Value::String(s) => s.clone(),
        _ => String::new(),
    };
    if token.is_empty() {
        return Ok(PollOutcome::Pending);
    }
    // 授权完成，顺带续期以延长有效期（失败则回退原 token）。
    let token = renew_token(&token).await.unwrap_or(token);
    Ok(PollOutcome::Done(token))
}

/// 续期令牌（best-effort）；失败或无返回则 `None`。
pub async fn renew_token(token: &str) -> Option<String> {
    let value = post("/user/renewToken", &json!({}), Some(token))
        .await
        .ok()?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let renewed = match &data {
        Value::Object(_) => str_field(&data, "token"),
        Value::String(s) => s.clone(),
        _ => String::new(),
    };
    (!renewed.is_empty()).then_some(renewed)
}

/// 验证令牌并获取账号信息。
pub async fn user_info(token: &str) -> Result<Account, ApiError> {
    let value = get("/frp/userInfo", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    Ok(Account {
        username: str_field(&data, "name"),
        group: str_field(&data, "user_group_name"),
        used_tunnels: None,
        max_tunnels: u32_field(&data, "maxTunnelCount"),
        frp_token: None,
    })
}

/// 节点列表。
pub async fn node_list(token: &str) -> Result<Vec<FrpNode>, ApiError> {
    let value = get("/frp/nodeList", token).await?;
    let rows = array_field(&value, "data");
    Ok(rows
        .iter()
        .map(|m| FrpNode {
            id: str_field(m, "id"),
            name: str_field(m, "node"),
            hostname: str_field(m, "ip"),
            min_port: u32_field(m, "min_open_port"),
            max_port: u32_field(m, "max_open_port"),
            description: str_field(m, "remarks"),
            online: m.get("status").and_then(Value::as_i64).unwrap_or(1) != 0,
            vip: m
                .get("allow_user_group")
                .and_then(Value::as_i64)
                .unwrap_or(0)
                > 0,
            udp_support: m.get("udp_support").and_then(Value::as_i64).unwrap_or(1) != 0,
            ..Default::default()
        })
        .collect())
}

/// 我的隧道列表。
pub async fn tunnel_list(token: &str) -> Result<Vec<RemoteTunnel>, ApiError> {
    let value = get("/frp/getTunnelList", token).await?;
    let rows = array_field(&value, "data");
    Ok(rows
        .iter()
        .map(|m| RemoteTunnel {
            id: str_field(m, "id"),
            name: str_field(m, "name"),
            node_id: str_field(m, "node_id"),
            local_ip: fallback(str_field(m, "local_ip"), "127.0.0.1"),
            local_port: u32_field(m, "local_port").unwrap_or(25565),
            remote_port: u32_field(m, "remote_port"),
            online: bool_field(m, "status", false),
            ..Default::default()
        })
        .collect())
}

/// 创建隧道。
pub async fn add_tunnel(token: &str, req: &CreateTunnelReq) -> Result<(), ApiError> {
    // bind_domain 参数永远没被调用方填过（隧道页不收集域名），这里就不留了。
    let body = json!({
        "id": node_id_int(&req.node.id),
        "name": req.name,
        "type": req.kind,
        "remarks": "Create By EdgeCube",
        "local_ip": req.local_ip,
        "local_port": req.local_port,
        "remote_port": req.remote_port,
        "use_kcp": false,
    });
    post("/frp/addTunnel", &body, Some(token)).await?;
    Ok(())
}

/// 删除隧道。
pub async fn delete_tunnel(token: &str, tunnel_id: &str) -> Result<(), ApiError> {
    // 数字 ID 传数字，其他原样传。
    let id = match tunnel_id.parse::<i64>() {
        Ok(number) => json!(number),
        Err(_) => json!(tunnel_id),
    };
    post("/frp/deleteTunnel", &json!({ "id": id }), Some(token)).await?;
    Ok(())
}

/// 拉取隧道的成品 frpc 配置（TOML 文本）。
pub async fn tunnel_config(token: &str, tunnel_id: &str) -> Result<String, ApiError> {
    let value = get(
        &format!("/frp/getTunnelConfig?id={tunnel_id}&format=toml"),
        token,
    )
    .await?;
    let config = value
        .get("data")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    if config.is_empty() {
        return Err(ApiError::config("配置内容为空"));
    }
    Ok(config)
}

fn fallback(value: String, or_else: &str) -> String {
    if value.is_empty() {
        or_else.to_string()
    } else {
        value
    }
}
