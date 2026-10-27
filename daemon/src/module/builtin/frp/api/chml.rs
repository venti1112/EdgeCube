//! ChmlFrp（cf-v2.uapis.cn）API 客户端。
//!
//! 鉴权走 QZhua 账号（account-api.qzhua.net）的 OAuth 设备码授权：设备端申请
//! device_code → 用户浏览器授权 → 设备端轮询换 access_token。拿到 access_token
//! 直接作 `Authorization: Bearer` 调 cf-v2.uapis.cn，不必再换 ChmlFrp 自有令牌
//! （后端会校验 QZhua 的 access_token）。
//!
//! access_token 有时效（expires_in），临近过期用 refresh_token 自动续。落盘的
//! 是 JSON 串 `{at, rt, exp}`（`exp` 是到期毫秒时间戳）—— 它比
//! 别的平台多一层编码，是为了让 daemon 自己就能把续期做完整：只存 access_token
//! 的话，过期那天用户就得重新点一遍浏览器授权。

use serde_json::{Value, json};

use super::super::model::{Account, FrpNode, Provider, RemoteTunnel};
use super::super::store::FrpStore;
use super::{
    ApiError, CreateTunnelReq, LoginFlow, LoginStart, PollOutcome, array_field, client,
    envelope_message, parse_json, parse_poll_json, store_op, str_field, u32_field,
};
use crate::util::now_ms;

const BASE: &str = "https://cf-v2.uapis.cn";

/// QZhua 统一认证的发行者。
const OAUTH_ISSUER: &str = "https://account-api.qzhua.net";

/// OAuth 客户端标识。
const CLIENT_ID: &str = "019f997e3360710b931fcd6d81aad92a";

/// scope：profile / email 是标准 OIDC，offline_access 才给 refresh_token，
/// `chmlfrp_api` 是 ChmlFrp 自定义 scope（不能省，省了后端不认）。
const SCOPE: &str = "profile email offline_access chmlfrp_api";

/// 设备码授权的默认有效期与轮询间隔（服务端不给时的兜底）。
const DEFAULT_DEVICE_INTERVAL_SECS: u64 = 5;
const DEFAULT_DEVICE_EXPIRES_SECS: u64 = 300;

/// access_token 到期前 60 秒视为「即将过期」，提前刷新。
const REFRESH_SKEW_MS: u64 = 60_000;

// ---------------------------------------------------------------------------
// 令牌编码（`{at, rt, exp}`）
// ---------------------------------------------------------------------------

/// 编码令牌 JSON。`exp` 为到期毫秒时间戳；服务端没给 expires_in 就不写。
fn encode_token(
    access_token: &str,
    refresh_token: Option<&str>,
    expires_in: Option<u64>,
) -> String {
    let mut value = json!({ "at": access_token });
    if let Some(refresh) = refresh_token.filter(|t| !t.is_empty()) {
        value["rt"] = json!(refresh);
    }
    if let Some(seconds) = expires_in {
        value["exp"] = json!(now_ms() + seconds * 1000);
    }
    value.to_string()
}

/// 解析令牌 JSON；不是 JSON 就当成裸 access_token（兼容早期的 usertoken）。
fn decode_token(encoded: &str) -> Value {
    match serde_json::from_str::<Value>(encoded) {
        Ok(value @ Value::Object(_)) => value,
        _ => json!({ "at": encoded }),
    }
}

// ---------------------------------------------------------------------------
// QZhua OAuth 设备码流程
// ---------------------------------------------------------------------------

async fn token_request_raw(form: &[(&str, &str)]) -> Result<(u16, String), ApiError> {
    let resp = client()
        .post(format!("{OAUTH_ISSUER}/oauth2/token"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(form)
        .send()
        .await?;
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    Ok((status, body))
}

async fn token_request(form: &[(&str, &str)]) -> Result<Value, ApiError> {
    let (status, body) = token_request_raw(form).await?;
    parse_json(status, &body)
}

/// 申请设备码：返回授权页地址、用户短码与轮询状态。
pub async fn create_device_login() -> Result<(LoginStart, LoginFlow), ApiError> {
    let resp = client()
        .post(format!("{OAUTH_ISSUER}/oauth2/device_authorization"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&[("client_id", CLIENT_ID), ("scope", SCOPE)])
        .send()
        .await?;
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    // device_authorization 失败时回 {error, error_description}，没有 code。
    if let Some(error) = value.get("error") {
        let description = str_field(&value, "error_description");
        let message = if description.is_empty() {
            error.as_str().unwrap_or("设备码申请失败").to_string()
        } else {
            description
        };
        return Err(ApiError::business(message));
    }

    let device_code = str_field(&value, "device_code");
    let user_code = str_field(&value, "user_code");
    // verification_uri_complete 自带短码，能用就用；否则退回 verification_uri。
    let url = {
        let complete = str_field(&value, "verification_uri_complete");
        if complete.is_empty() {
            str_field(&value, "verification_uri")
        } else {
            complete
        }
    };
    if device_code.is_empty() || url.is_empty() {
        return Err(ApiError::business(
            "设备码响应缺少 device_code 或 verification_uri",
        ));
    }

    let interval_secs = value
        .get("interval")
        .and_then(Value::as_u64)
        .unwrap_or(DEFAULT_DEVICE_INTERVAL_SECS);
    let expires_in = value
        .get("expires_in")
        .and_then(Value::as_u64)
        .unwrap_or(DEFAULT_DEVICE_EXPIRES_SECS);
    let flow = LoginFlow::Chml {
        device_code,
        interval_ms: interval_secs * 1000,
        expires_at_ms: now_ms() + expires_in * 1000,
    };
    Ok((LoginStart { url, user_code }, flow))
}

/// 轮询设备码授权结果。
///
/// - `authorization_pending` / `slow_down` → `Pending`（后者顺手把间隔加 5 秒，
///   尊重服务端的限流要求）；
/// - 拿到 access_token → `Done`（编码成 `{at, rt, exp}`）；
/// - `expired_token` / `access_denied` 等 → 致命错误，停止轮询。
pub async fn poll_device_login(
    _store: &FrpStore,
    device_code: &str,
    interval_ms: &mut u64,
    expires_at_ms: u64,
) -> Result<PollOutcome, ApiError> {
    if now_ms() >= expires_at_ms {
        return Err(ApiError::business("设备码已过期，请重新发起登录"));
    }

    let (status, body) = token_request_raw(&[
        ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
        ("client_id", CLIENT_ID),
        ("device_code", device_code),
    ])
    .await?;
    // 读不懂的响应体（网关错误页等）当「还没授权好」，接着轮。
    let Some(value) = parse_poll_json(status, &body) else {
        return Ok(PollOutcome::Pending);
    };

    if let Some(error) = value.get("error").and_then(Value::as_str) {
        match error {
            "authorization_pending" => return Ok(PollOutcome::Pending),
            "slow_down" => {
                *interval_ms += 5_000;
                return Ok(PollOutcome::Pending);
            }
            _ => {
                let description = str_field(&value, "error_description");
                let message = if description.is_empty() {
                    error.to_string()
                } else {
                    description
                };
                return Err(ApiError::business(message));
            }
        }
    }

    let access_token = str_field(&value, "access_token");
    if access_token.is_empty() {
        return Err(ApiError::business("token 响应缺少 access_token"));
    }
    let refresh_token = str_field(&value, "refresh_token");
    Ok(PollOutcome::Done(encode_token(
        &access_token,
        Some(&refresh_token),
        value.get("expires_in").and_then(Value::as_u64),
    )))
}

/// 用 refresh_token 换新的 access_token，并**回写磁盘**。
///
/// 回写是必须的：refresh_token 一般是「用一次换一把」，不回写下次启动就拿着
/// 已经作废的那把去刷新，用户只能重登。
pub async fn refresh_token(store: &FrpStore, encoded: &str) -> Result<String, ApiError> {
    let parsed = decode_token(encoded);
    let refresh = str_field(&parsed, "rt");
    if refresh.is_empty() {
        return Err(ApiError::business("无 refresh_token，请重新登录"));
    }

    let value = token_request(&[
        ("grant_type", "refresh_token"),
        ("client_id", CLIENT_ID),
        ("refresh_token", &refresh),
    ])
    .await?;
    if let Some(error) = value.get("error") {
        let description = str_field(&value, "error_description");
        let message = if !description.is_empty() {
            description
        } else {
            error.as_str().unwrap_or("刷新 token 失败").to_string()
        };
        return Err(ApiError::business(message));
    }

    let access_token = str_field(&value, "access_token");
    if access_token.is_empty() {
        return Err(ApiError::business("刷新响应缺少 access_token"));
    }
    // 服务端没给新 refresh_token 就沿用旧的。
    let next_refresh = {
        let fresh = str_field(&value, "refresh_token");
        if fresh.is_empty() { refresh } else { fresh }
    };
    let new_token = encode_token(
        &access_token,
        Some(&next_refresh),
        value.get("expires_in").and_then(Value::as_u64),
    );

    let to_store = new_token.clone();
    store_op(store, move |store| {
        store
            .update_token(Provider::ChmlFrp, &to_store)
            .map_err(|e| ApiError::internal(format!("保存刷新后的令牌失败：{e}")))
    })
    .await?;
    Ok(new_token)
}

/// 取当前有效的 access_token；临近过期就刷新。
pub async fn resolve_access_token(store: &FrpStore, encoded: &str) -> Result<String, ApiError> {
    let parsed = decode_token(encoded);
    let access_token = str_field(&parsed, "at");
    let expires_at = parsed.get("exp").and_then(Value::as_u64);
    // 没有到期时间、或离到期还早：直接用。
    if expires_at.is_none_or(|exp| now_ms() + REFRESH_SKEW_MS < exp) {
        return Ok(access_token);
    }
    let refreshed = refresh_token(store, encoded).await?;
    Ok(str_field(&decode_token(&refreshed), "at"))
}

// ---------------------------------------------------------------------------
// 业务接口（Bearer 鉴权）
// ---------------------------------------------------------------------------

/// 包络：`state == "success"` 或 `code == 200` 都算成功。
async fn envelope(resp: reqwest::Response) -> Result<Value, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    let state = str_field(&value, "state");
    let code = value.get("code").and_then(Value::as_i64);
    if state == "success" || code == Some(200) {
        return Ok(value);
    }
    if status == 401 || status == 403 || matches!(code, Some(401) | Some(403)) {
        return Err(ApiError::unauthorized(envelope_message(&value, status)));
    }
    Err(ApiError::business(envelope_message(&value, status)))
}

async fn get(
    store: &FrpStore,
    path_with_query: &str,
    encoded_token: &str,
) -> Result<Value, ApiError> {
    let access_token = resolve_access_token(store, encoded_token).await?;
    let resp = client()
        .get(format!("{BASE}{path_with_query}"))
        .header("Authorization", format!("Bearer {access_token}"))
        .header("Content-Type", "application/json")
        .send()
        .await?;
    envelope(resp).await
}

/// 验证令牌并获取账号信息（含 frpc usertoken）。
pub async fn user_info(store: &FrpStore, token: &str) -> Result<Account, ApiError> {
    let value = get(store, "/userinfo", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let frp_token = str_field(&data, "usertoken");
    Ok(Account {
        username: str_field(&data, "username"),
        group: str_field(&data, "usergroup"),
        used_tunnels: u32_field(&data, "tunnel"),
        // 上游把 tunnelCount 拼成了 tunnnelCount，两个都认。
        max_tunnels: u32_field(&data, "tunnnelCount").or_else(|| u32_field(&data, "tunnelCount")),
        frp_token: (!frp_token.is_empty()).then_some(frp_token),
    })
}

/// 我的隧道列表。`dorp` 是远程端口（数字）或域名（http/https）。
pub async fn tunnel_list(store: &FrpStore, token: &str) -> Result<Vec<RemoteTunnel>, ApiError> {
    let value = get(store, "/tunnel", token).await?;
    let rows = array_field(&value, "data");
    Ok(rows
        .iter()
        .map(|m| {
            let dorp = str_field(m, "dorp");
            let remote_port = dorp.trim().parse::<u32>().ok();
            let ip = str_field(m, "ip");
            RemoteTunnel {
                id: str_field(m, "id"),
                name: str_field(m, "name"),
                node_name: str_field(m, "node"),
                kind: fallback(str_field(m, "type"), "tcp"),
                local_ip: fallback(str_field(m, "localip"), "127.0.0.1"),
                local_port: u32_field(m, "nport").unwrap_or(25565),
                remote_port,
                // 是端口就拼 ip:端口；是域名（http/https）就原样用。
                remote_address: match remote_port {
                    Some(_) => format!("{ip}:{}", dorp.trim()),
                    None => dorp,
                },
                ..Default::default()
            }
        })
        .collect())
}

/// 节点列表（无需鉴权）。
pub async fn node_list() -> Result<Vec<FrpNode>, ApiError> {
    let resp = client().get(format!("{BASE}/node")).send().await?;
    let value = envelope(resp).await?;
    let rows = array_field(&value, "data");
    Ok(rows
        .iter()
        .map(|m| {
            let name = str_field(m, "name");
            let area = str_field(m, "area");
            let notes = str_field(m, "notes");
            FrpNode {
                id: name.clone(),
                name: name.clone(),
                description: format!("{area} {notes}").trim().to_string(),
                vip: str_field(m, "nodegroup") == "vip",
                ..Default::default()
            }
        })
        .collect())
}

/// 创建隧道。
pub async fn create_tunnel(
    store: &FrpStore,
    token: &str,
    req: &CreateTunnelReq,
) -> Result<(), ApiError> {
    let access_token = resolve_access_token(store, token).await?;
    let resp = client()
        .post(format!("{BASE}/create_tunnel"))
        .header("Authorization", format!("Bearer {access_token}"))
        .header("Content-Type", "application/json")
        .json(&json!({
            // ChmlFrp 的节点用的是名字，不是数字 ID。
            "tunnelname": req.name,
            "node": req.node.name,
            "porttype": req.kind,
            "localip": req.local_ip,
            "localport": req.local_port,
            "encryption": false,
            "compression": false,
            "extraparams": "",
            "remoteport": req.remote_port,
        }))
        .send()
        .await?;
    envelope(resp).await?;
    Ok(())
}

/// 删除隧道。
pub async fn delete_tunnel(store: &FrpStore, token: &str, tunnel_id: &str) -> Result<(), ApiError> {
    let value = get(
        store,
        &format!("/delete_tunnel?tunnelid={tunnel_id}"),
        token,
    )
    .await?;
    let _ = value;
    Ok(())
}

/// 拉取隧道的成品 frpc 配置（ini 文本 —— 上游 frpc 兼容 ini）。
pub async fn tunnel_config(
    store: &FrpStore,
    token: &str,
    node: &str,
    tunnel_name: &str,
) -> Result<String, ApiError> {
    let access_token = resolve_access_token(store, token).await?;
    let resp = client()
        .get(format!("{BASE}/tunnel_config"))
        .query(&[("node", node), ("tunnelName", tunnel_name)])
        .header("Authorization", format!("Bearer {access_token}"))
        .header("Content-Type", "application/json")
        .send()
        .await?;
    let value = envelope(resp).await?;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_encoding_is_stable() {
        let encoded = encode_token("at-1", Some("rt-1"), None);
        let parsed: Value = serde_json::from_str(&encoded).unwrap();
        assert_eq!(parsed["at"], json!("at-1"));
        assert_eq!(parsed["rt"], json!("rt-1"));
        assert!(parsed.get("exp").is_none(), "没给 expires_in 就不写 exp");

        let encoded = encode_token("at-2", Some(""), Some(3600));
        let parsed: Value = serde_json::from_str(&encoded).unwrap();
        assert_eq!(parsed["at"], json!("at-2"));
        assert!(parsed.get("rt").is_none(), "空 refresh_token 不写");
        let exp = parsed["exp"].as_u64().unwrap();
        assert!(exp > now_ms() + 3_500_000, "exp 是毫秒时间戳");
    }

    #[test]
    fn token_decoding_accepts_legacy_plain_token() {
        assert_eq!(
            decode_token("plain-usertoken")["at"],
            json!("plain-usertoken")
        );
    }

    #[tokio::test]
    async fn fresh_token_is_used_as_is() {
        let store = FrpStore::new(std::env::temp_dir().join("edgecube-frp-chml-test"));
        // 无 exp：直接返回 at，不去打网络
        let token = encode_token("at-fresh", Some("rt"), None);
        assert_eq!(
            resolve_access_token(&store, &token).await.unwrap(),
            "at-fresh"
        );

        // 还有一小时才过期：也不刷新
        let token = json!({ "at": "at-2", "rt": "rt", "exp": now_ms() + 3_600_000 }).to_string();
        assert_eq!(resolve_access_token(&store, &token).await.unwrap(), "at-2");
    }
}
