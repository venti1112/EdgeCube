//! OpenFrp（api.openfrp.net）API 客户端。
//!
//! 登录走远程安全登录（Remote Login）：curve25519 密钥对 + 浏览器授权 +
//! NaCl box 解出 Authorization（access.openfrp.net/argoAccess）。原先那种
//! 「粘贴 Authorization」的登录方式已被官方移除。
//!
//! 业务接口鉴权是 `Authorization: <token>`（**没有** Bearer 前缀）；响应包络
//! `{flag, data, msg}`。`getUserInfo` 回来的 `data.token` 是 frpc 用户 token
//! （拼配置用），和登录用的 Authorization 不是一回事。
//!
//! 密文排布：`authorization_data` 是标准 base64 的 `nonce(24) ‖ MAC(16) ‖ 密文`
//! —— NaCl `crypto_box_easy` 的排布，MAC 在前。RustCrypto 的 `aead` 惯例相反
//! （MAC 在后），所以这里用 `decrypt_in_place_detached` 把 MAC 单独递进去，
//! 不去猜顺序（有单测钉住）。

use base64::Engine as _;
use base64::engine::general_purpose::{STANDARD, URL_SAFE};
use crypto_box::aead::AeadInPlace as _;
use crypto_box::{Nonce, PublicKey, SalsaBox, SecretKey, Tag};
// rand 0.10 起 `fill` / `random_range` 这类便捷方法从 `Rng` 挪到了 `RngExt`，
// 只引 `Rng` 会「方法找不到」。这里要的就是填充字节，所以引 `RngExt`。
use rand::RngExt as _;
use serde_json::{Value, json};

use super::super::model::{Account, FrpNode, RemoteTunnel};
use super::{
    ApiError, CreateTunnelReq, LoginFlow, LoginStart, PollOutcome, array_field, bool_field, client,
    envelope_message, parse_bool, parse_json, parse_poll_json, str_field, u32_field,
};

const BASE: &str = "https://api.openfrp.net";
const ACCESS_BASE: &str = "https://access.openfrp.net";

/// NaCl box 的 nonce / MAC 长度。
const NONCE_LEN: usize = 24;
const MAC_LEN: usize = 16;

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

async fn post(path: &str, token: &str) -> Result<Value, ApiError> {
    post_body(path, token, &json!({})).await
}

async fn post_body(path: &str, token: &str, body: &Value) -> Result<Value, ApiError> {
    let resp = client()
        .post(format!("{BASE}{path}"))
        .header("Content-Type", "application/json")
        .header("Authorization", token)
        .json(body)
        .send()
        .await?;
    envelope(resp).await
}

/// 业务包络：`flag != true` 就是失败。
async fn envelope(resp: reqwest::Response) -> Result<Value, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    if value.get("flag").and_then(Value::as_bool) != Some(true) {
        return Err(ApiError::business(envelope_message(&value, status)));
    }
    Ok(value)
}

/// argoAccess 包络：`{code, msg, data}`，`code == 200` 为成功。
/// code 复用 HTTP 状态码（204 未授权 / 400 参数错 / 404 授权不存在）。
async fn access_envelope(resp: reqwest::Response) -> Result<Value, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    let code = value.get("code").and_then(Value::as_i64).unwrap_or(-1);
    if code != 200 {
        return Err(ApiError::business(envelope_message(&value, status)));
    }
    Ok(value)
}

// ---------------------------------------------------------------------------
// base64
// ---------------------------------------------------------------------------

/// 宽松 base64 解码：兼容标准与 URL-safe、自动补齐 padding。
fn b64_decode(raw: &str) -> Result<Vec<u8>, ApiError> {
    let normalized: String = raw
        .trim()
        .chars()
        .map(|c| match c {
            '-' => '+',
            '_' => '/',
            other => other,
        })
        .collect();
    let padded = match normalized.len() % 4 {
        0 => normalized,
        rem => format!("{normalized}{}", "=".repeat(4 - rem)),
    };
    STANDARD
        .decode(padded.as_bytes())
        .map_err(|e| ApiError::protocol(format!("base64 解码失败：{e}")))
}

fn b64_url_encode(bytes: &[u8]) -> String {
    URL_SAFE.encode(bytes)
}

// ---------------------------------------------------------------------------
// 远程安全登录
// ---------------------------------------------------------------------------

/// 发起远程安全登录：生成 curve25519 密钥对，提交公钥换授权页地址。
pub async fn create_browser_login() -> Result<(LoginStart, LoginFlow), ApiError> {
    let mut seed = [0u8; 32];
    rand::rng().fill(&mut seed);
    let secret = SecretKey::from(seed);
    let public_key = b64_url_encode(secret.public_key().as_bytes());

    let resp = client()
        .post(format!("{ACCESS_BASE}/argoAccess/requestLogin"))
        .header("Content-Type", "application/json")
        .json(&json!({ "public_key": public_key }))
        .send()
        .await?;
    let value = access_envelope(resp).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let url = str_field(&data, "authorization_url");
    let request_uuid = str_field(&data, "request_uuid");
    if url.is_empty() || request_uuid.is_empty() {
        return Err(ApiError::business("授权会话创建失败"));
    }
    let flow = LoginFlow::OpenFrp {
        request_uuid,
        // 私钥（已 clamp 的 32 字节），轮询时用它解密 authorization_data。
        secret: secret.to_bytes(),
    };
    Ok((
        LoginStart {
            url,
            user_code: String::new(),
        },
        flow,
    ))
}

/// 轮询远程安全登录结果。
///
/// `pollLogin` 的文档写的是 GET + JSON body（request_uuid）。GET 带 body 是
/// 非标准用法，会有 CDN / 反代丢掉 body，服务端收不到 request_uuid 就一直非
/// 200（表现为「已授权但一直等待」）。所以 query 与 body 各带一份，双重保险。
pub async fn poll_browser_login(
    request_uuid: &str,
    secret: &[u8; 32],
) -> Result<PollOutcome, ApiError> {
    let payload = serde_json::to_string(&json!({ "request_uuid": request_uuid }))
        .map_err(|e| ApiError::internal(format!("序列化失败：{e}")))?;
    let resp = client()
        .get(format!("{ACCESS_BASE}/argoAccess/pollLogin"))
        .query(&[("request_uuid", request_uuid)])
        .header("Content-Type", "application/json")
        .body(payload)
        .send()
        .await?;

    let status = resp.status().as_u16();
    let server_pk = resp
        .headers()
        .get("x-request-public-key")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_string();
    let body = resp.text().await?;
    classify_poll_response(status, &server_pk, &body, secret)
}

/// 处理一次 pollLogin 响应。
///
/// 抽成纯函数是为了能直接拿 204 空体这类真实响应做回归测试。
fn classify_poll_response(
    status: u16,
    server_pk: &str,
    body: &str,
    secret: &[u8; 32],
) -> Result<PollOutcome, ApiError> {
    // 204 空体（未授权）等读不懂的响应：还没授权好，接着轮。
    let Some(value) = parse_poll_json(status, body) else {
        return Ok(PollOutcome::Pending);
    };

    // code 兼容数字与字符串形式（部分实现回 "200"）。
    let code = match value.get("code") {
        Some(Value::Number(n)) => n.as_i64().unwrap_or(-1),
        Some(Value::String(s)) => s.trim().parse().unwrap_or(-1),
        _ => -1,
    };
    // 非 200（204 未授权 / 400 / 429 限流……）一律当「还没授权好」，继续轮询。
    if code != 200 {
        return Ok(PollOutcome::Pending);
    }

    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let auth_data = str_field(&data, "authorization_data");
    if auth_data.is_empty() {
        // code == 200 却没有密文：状态异常，报错而不是无限轮询
        // （request_uuid 已被消费，接着轮也不会好了）。
        return Err(ApiError::protocol("授权响应缺少 authorization_data"));
    }
    if server_pk.is_empty() {
        return Err(ApiError::protocol("授权响应缺少 x-request-public-key 头"));
    }
    let token = decrypt_authorization(secret, server_pk, &auth_data)?;
    Ok(PollOutcome::Done(token))
}

/// 解密服务端下发的 Authorization。
///
/// `auth_data` = base64(`nonce(24) ‖ MAC(16) ‖ SalsaBox 密文`)。
fn decrypt_authorization(
    secret: &[u8; 32],
    server_public_key_b64: &str,
    auth_data: &str,
) -> Result<String, ApiError> {
    let combined = b64_decode(auth_data)?;
    if combined.len() <= NONCE_LEN + MAC_LEN {
        return Err(ApiError::protocol("授权密文长度不足"));
    }
    let server_key: [u8; 32] = b64_decode(server_public_key_b64)?
        .try_into()
        .map_err(|_| ApiError::protocol("服务端公钥长度不是 32 字节"))?;

    let my_secret = SecretKey::from(*secret);
    let salsa = SalsaBox::new(&PublicKey::from(server_key), &my_secret);

    let mut buffer = combined[NONCE_LEN + MAC_LEN..].to_vec();
    let tag = Tag::from_slice(&combined[NONCE_LEN..NONCE_LEN + MAC_LEN]);
    salsa
        .decrypt_in_place_detached(
            Nonce::from_slice(&combined[..NONCE_LEN]),
            &[],
            &mut buffer,
            tag,
        )
        .map_err(|_| ApiError::protocol("授权数据解密失败"))?;

    String::from_utf8(buffer).map_err(|e| ApiError::protocol(format!("授权数据不是 UTF-8：{e}")))
}

// ---------------------------------------------------------------------------
// 业务接口
// ---------------------------------------------------------------------------

/// 验证 Authorization 并获取账号信息（含 frpc 用户 token）。
pub async fn user_info(token: &str) -> Result<Account, ApiError> {
    let value = post("/frp/api/getUserInfo", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let frp_token = str_field(&data, "token");
    Ok(Account {
        username: str_field(&data, "username"),
        group: str_field(&data, "friendlyGroup"),
        used_tunnels: u32_field(&data, "used"),
        max_tunnels: u32_field(&data, "proxies"),
        frp_token: (!frp_token.is_empty()).then_some(frp_token),
    })
}

/// 我的隧道（代理）列表。
pub async fn proxy_list(token: &str) -> Result<Vec<RemoteTunnel>, ApiError> {
    let value = post("/frp/api/getUserProxies", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let rows = array_field(&data, "list");
    Ok(rows
        .iter()
        .map(|m| RemoteTunnel {
            id: str_field(m, "id"),
            name: str_field(m, "proxyName"),
            node_id: str_field(m, "nid"),
            node_name: str_field(m, "friendlyNode"),
            kind: fallback(str_field(m, "proxyType"), "tcp"),
            local_ip: fallback(str_field(m, "localIp"), "127.0.0.1"),
            local_port: u32_field(m, "localPort").unwrap_or(25565),
            remote_port: u32_field(m, "remotePort"),
            remote_address: str_field(m, "connectAddress"),
            online: bool_field(m, "online", false),
        })
        .collect())
}

/// 节点列表。`allowPort` 形如 `"(min,max)"`。
pub async fn node_list(token: &str) -> Result<Vec<FrpNode>, ApiError> {
    let value = post("/frp/api/getNodeList", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let rows = array_field(&data, "list");
    Ok(rows
        .iter()
        .map(|m| {
            let (min_port, max_port) = parse_allow_port(&str_field(m, "allowPort"));
            let protocols = m.get("protocolSupport").cloned().unwrap_or(Value::Null);
            FrpNode {
                id: str_field(m, "id"),
                name: str_field(m, "name"),
                hostname: str_field(m, "hostname"),
                min_port,
                max_port,
                description: str_field(m, "description"),
                online: m.get("status").and_then(Value::as_i64).unwrap_or(200) == 200,
                // group 形如 "normal;vip"，不含 normal 就是付费节点。
                vip: !str_field(m, "group").split(';').any(|g| g == "normal"),
                udp_support: parse_bool(protocols.get("udp"), true),
                ..Default::default()
            }
        })
        .collect())
}

/// 从 `"(20000, 30000)"` 里取端口范围。
fn parse_allow_port(raw: &str) -> (Option<u32>, Option<u32>) {
    let trimmed = raw.trim();
    let inner = trimmed
        .strip_prefix('(')
        .and_then(|s| s.strip_suffix(')'))
        .unwrap_or("");
    let mut parts = inner.split(',');
    let min = parts.next().map(str::trim).and_then(|s| s.parse().ok());
    let max = parts.next().map(str::trim).and_then(|s| s.parse().ok());
    (min, max)
}

/// 创建隧道。
pub async fn new_proxy(token: &str, req: &CreateTunnelReq) -> Result<(), ApiError> {
    post_body(
        "/frp/api/newProxy",
        token,
        &json!({
            "node_id": super::node_id_int(&req.node.id),
            "name": req.name,
            "type": req.kind,
            "local_addr": req.local_ip,
            "local_port": req.local_port,
            "remote_port": req.remote_port,
            "domain_bind": "",
            "dataGzip": false,
            "dataEncrypt": false,
            "url_route": "",
            "host_rewrite": "",
            "request_from": "",
            "request_pass": "",
            "custom": "",
        }),
    )
    .await?;
    Ok(())
}

/// 删除隧道。
pub async fn remove_proxy(token: &str, proxy_id: &str) -> Result<(), ApiError> {
    let id = match proxy_id.trim().parse::<i64>() {
        Ok(number) => json!(number),
        Err(_) => json!(proxy_id),
    };
    post_body("/frp/api/removeProxy", token, &json!({ "proxy_id": id })).await?;
    Ok(())
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
    fn decrypts_nacl_box_layout() {
        // 扮服务端：用自己的私钥 + 客户端公钥做 SalsaBox 加密，然后按 NaCl
        // 的 `nonce ‖ MAC ‖ 密文` 拼成一串发出去。
        let client_secret = SecretKey::from([7u8; 32]);
        let server_secret = SecretKey::from([9u8; 32]);
        let server_box = SalsaBox::new(&client_secret.public_key(), &server_secret);

        let nonce = [3u8; NONCE_LEN];
        let mut buffer = b"authorization-token".to_vec();
        let tag = server_box
            .encrypt_in_place_detached(Nonce::from_slice(&nonce), &[], &mut buffer)
            .expect("加密");

        let mut combined = nonce.to_vec();
        combined.extend_from_slice(&tag);
        combined.extend_from_slice(&buffer);

        let plaintext = decrypt_authorization(
            &client_secret.to_bytes(),
            &b64_url_encode(server_secret.public_key().as_bytes()),
            &STANDARD.encode(&combined),
        )
        .expect("解密");
        assert_eq!(plaintext, "authorization-token");
    }

    #[test]
    fn pending_poll_never_kills_the_session() {
        let secret = [7u8; 32];
        // 未授权时服务端回 204 空体；网关抽风时可能是 HTML 错误页。
        let pending = classify_poll_response(204, "", "", &secret).expect("空体不该报错");
        assert!(matches!(pending, PollOutcome::Pending));
        let html = classify_poll_response(502, "", "<html>502 Bad Gateway</html>", &secret)
            .expect("HTML 错误页不该报错");
        assert!(matches!(html, PollOutcome::Pending));
        // 非 200 的 JSON 也是「还没授权好」。
        let not_found =
            classify_poll_response(200, "", r#"{"code":400,"msg":"授权请求不存在"}"#, &secret)
                .expect("业务 code 非 200 不该报错");
        assert!(matches!(not_found, PollOutcome::Pending));
    }

    #[test]
    fn consumed_session_still_reports_protocol_error() {
        let secret = [7u8; 32];
        // code == 200 却没有密文：UUID 已被消费，接着轮也不会好了。
        let err = classify_poll_response(200, "", r#"{"code":200}"#, &secret).unwrap_err();
        assert_eq!(err.code, "frp_protocol_error");
        // 有密文但缺服务端公钥同样致命。
        let err = classify_poll_response(
            200,
            "",
            r#"{"code":200,"data":{"authorization_data":"AAAA"}}"#,
            &secret,
        )
        .unwrap_err();
        assert_eq!(err.code, "frp_protocol_error");
    }

    #[test]
    fn allow_port_parses_comma_separated_list() {
        assert_eq!(
            parse_allow_port("(20000, 30000)"),
            (Some(20000), Some(30000))
        );
        assert_eq!(
            parse_allow_port("(20000,30000)"),
            (Some(20000), Some(30000))
        );
        assert_eq!(parse_allow_port(""), (None, None));
        assert_eq!(parse_allow_port("whatever"), (None, None));
    }

    #[test]
    fn base64_decoding_tolerates_url_safe_and_missing_padding() {
        // 同一段字节的三种常见写法都该解出来
        assert_eq!(b64_decode("aGk=").unwrap(), b"hi");
        assert_eq!(b64_decode("aGk").unwrap(), b"hi");
        assert_eq!(b64_decode("__8").unwrap(), b"\xff\xff");
    }
}
