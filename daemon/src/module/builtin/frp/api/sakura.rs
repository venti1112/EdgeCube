//! SakuraFrp（api.natfrp.com/v4）API 客户端。
//!
//! 认证按 v4 定义分两套：GET 用 `token` 查询参数，POST 用 `Authorization: Bearer`。
//! 隧道列表直接返回数组（没有包络）；创建成功是 HTTP 201；204 之类的响应没有正文。

use serde_json::{Value, json};

use super::super::model::{Account, FrpNode, RemoteTunnel};
use super::{
    ApiError, CreateTunnelReq, bool_field, client, node_id_int, parse_json, str_field, u32_field,
};

const BASE: &str = "https://api.natfrp.com/v4";

/// 本应用自带的上游原版 frpc 版本（`/tunnel/config` 要声明目标版本）。
const FRPC_VERSION: &str = "0.69.1";

/// 节点 `flag` 的位标记：`1 << 5` 允许 UDP，`1 << 9` 节点离线。
const FLAG_UDP: i64 = 1 << 5;
const FLAG_OFFLINE: i64 = 1 << 9;

/// 非 2xx 按状态码分类：401 / 403 是令牌问题，其余按业务失败。
fn status_error(status: u16, value: Option<&Value>) -> ApiError {
    let message = value
        .map(|v| super::envelope_message(v, status))
        .unwrap_or_else(|| format!("HTTP {status}"));
    if status == 401 || status == 403 {
        ApiError::unauthorized(message)
    } else {
        ApiError::business(message)
    }
}

/// 解析响应：非 2xx 抛错，无正文返回 `Value::Null`。
fn decode(status: u16, body: &str) -> Result<Value, ApiError> {
    if !(200..300).contains(&status) {
        // 错误响应通常是 JSON（带 msg），但也可能是 HTML 网关页。
        let value = serde_json::from_str::<Value>(body).ok();
        return Err(status_error(status, value.as_ref()));
    }
    if body.is_empty() {
        return Ok(Value::Null);
    }
    parse_json(status, body)
}

async fn get(path_with_query: &str) -> Result<Value, ApiError> {
    let resp = client()
        .get(format!("{BASE}{path_with_query}"))
        .send()
        .await?;
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    decode(status, &body)
}

async fn post_raw(path: &str, token: &str, body: &Value) -> Result<reqwest::Response, ApiError> {
    let resp = client()
        .post(format!("{BASE}{path}"))
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .json(body)
        .send()
        .await?;
    let status = resp.status().as_u16();
    if !(200..300).contains(&status) {
        let body = resp.text().await?;
        let value = serde_json::from_str::<Value>(&body).ok();
        return Err(status_error(status, value.as_ref()));
    }
    Ok(resp)
}

async fn post(path: &str, token: &str, body: &Value) -> Result<Value, ApiError> {
    let resp = post_raw(path, token, body).await?;
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    decode(status, &body)
}

/// 验证令牌并获取账号信息。
pub async fn user_info(token: &str) -> Result<Account, ApiError> {
    let value = get(&format!("/user/info?token={token}")).await?;
    let group = value.get("group").cloned().unwrap_or(Value::Null);
    Ok(Account {
        username: str_field(&value, "name"),
        group: str_field(&group, "name"),
        used_tunnels: None,
        max_tunnels: u32_field(&value, "tunnels"),
        frp_token: None,
    })
}

/// 用户等级（过滤 VIP 节点用）。
pub async fn user_level(token: &str) -> Result<i64, ApiError> {
    let value = get(&format!("/user/info?token={token}")).await?;
    let group = value.get("group").cloned().unwrap_or(Value::Null);
    Ok(group.get("level").and_then(Value::as_i64).unwrap_or(0))
}

/// 我的隧道列表（API 直接返回数组）。
pub async fn tunnel_list(token: &str) -> Result<Vec<RemoteTunnel>, ApiError> {
    let value = get(&format!("/tunnels?token={token}")).await?;
    let rows = value.as_array().cloned().unwrap_or_default();
    Ok(rows
        .iter()
        .map(|m| {
            let remote = str_field(m, "remote");
            let remote_port = remote.trim().parse::<u32>().ok();
            RemoteTunnel {
                id: str_field(m, "id"),
                name: str_field(m, "name"),
                node_id: str_field(m, "node"),
                kind: fallback(str_field(m, "type"), "tcp"),
                local_ip: fallback(str_field(m, "local_ip"), "127.0.0.1"),
                local_port: u32_field(m, "local_port").unwrap_or(25565),
                remote_port,
                // `remote` 是端口就是端口，是绑定域名才当成连接地址。
                remote_address: if remote.contains(':') {
                    remote
                } else {
                    String::new()
                },
                online: bool_field(m, "online", false),
                ..Default::default()
            }
        })
        .collect())
}

/// 节点列表（API 返回以节点 id 为 key 的对象）。
///
/// 等级不够的 VIP 节点直接被过滤掉：展示了也连不上。
pub async fn node_list(token: &str, user_level: i64) -> Result<Vec<FrpNode>, ApiError> {
    let value = get(&format!("/nodes?token={token}")).await?;
    let Some(rows) = value.as_object() else {
        return Ok(Vec::new());
    };
    let mut nodes = Vec::new();
    for (id, raw) in rows {
        if !raw.is_object() {
            continue;
        }
        let vip = raw.get("vip").and_then(Value::as_i64).unwrap_or(0);
        if vip > user_level {
            continue;
        }
        let flag = raw.get("flag").and_then(Value::as_i64).unwrap_or(0);
        nodes.push(FrpNode {
            id: id.clone(),
            name: str_field(raw, "name"),
            hostname: str_field(raw, "host"),
            description: str_field(raw, "description"),
            online: flag & FLAG_OFFLINE == 0,
            vip: vip > 0,
            udp_support: flag & FLAG_UDP != 0,
            ..Default::default()
        });
    }
    Ok(nodes)
}

/// 创建隧道（成功是 HTTP 201，`decode` 已按 2xx 放行）。
///
/// `remote` 按 v4 定义传字符串（端口或绑定域名）：http/https 必填，
/// tcp 之类留空由服务端分配。
pub async fn create_tunnel(token: &str, req: &CreateTunnelReq) -> Result<(), ApiError> {
    post(
        "/tunnels",
        token,
        &json!({
            "node": node_id_int(&req.node.id),
            "name": req.name,
            "type": req.kind,
            "note": "Create By EdgeCube",
            "local_ip": req.local_ip,
            "local_port": req.local_port,
            "remote": req.remote_port.to_string(),
        }),
    )
    .await?;
    Ok(())
}

/// 删除隧道（`ids` 是逗号分隔的隧道 ID 字符串）。
pub async fn delete_tunnel(token: &str, tunnel_id: &str) -> Result<(), ApiError> {
    post("/tunnel/delete", token, &json!({ "ids": tunnel_id })).await?;
    Ok(())
}

/// 拉取隧道的成品配置（`POST /tunnel/config`，响应是 text/plain 或
/// text/toml，不是 JSON）。
pub async fn tunnel_config(token: &str, query: &str) -> Result<String, ApiError> {
    let resp = post_raw(
        "/tunnel/config",
        token,
        &json!({ "query": query, "frpc": FRPC_VERSION }),
    )
    .await?;
    let config = resp.text().await?;
    if config.trim().is_empty() {
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
