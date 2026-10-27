//! ME Frp（api.mefrp.com）API 客户端。
//!
//! 鉴权 `Authorization: Bearer <token>`；包络 `{code, message, data}`，
//! `code == 200` 为成功。

use serde_json::{Value, json};

use super::super::model::{Account, FrpNode, RemoteTunnel};
use super::{
    ApiError, CreateTunnelReq, array_field, bool_field, client, envelope_message, node_id_int,
    parse_json, str_field, u32_field,
};

const BASE: &str = "https://api.mefrp.com/api";

async fn get(path: &str, token: &str) -> Result<Value, ApiError> {
    let resp = client()
        .get(format!("{BASE}{path}"))
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .send()
        .await?;
    envelope(resp).await
}

async fn post(path: &str, body: &Value, token: &str) -> Result<Value, ApiError> {
    let resp = client()
        .post(format!("{BASE}{path}"))
        .header("Content-Type", "application/json")
        .header("Authorization", format!("Bearer {token}"))
        .json(body)
        .send()
        .await?;
    envelope(resp).await
}

/// 包络：`code != 200` 即失败（401 / 403 归到令牌失效）。
async fn envelope(resp: reqwest::Response) -> Result<Value, ApiError> {
    let status = resp.status().as_u16();
    let body = resp.text().await?;
    let value = parse_json(status, &body)?;
    let code = value
        .get("code")
        .and_then(Value::as_i64)
        .unwrap_or(i64::from(status));
    if code != 200 {
        let message = envelope_message(&value, status);
        return Err(
            if code == 401 || code == 403 || status == 401 || status == 403 {
                ApiError::unauthorized(message)
            } else {
                ApiError::business(message)
            },
        );
    }
    Ok(value)
}

/// 验证令牌并获取账号信息。
pub async fn user_info(token: &str) -> Result<Account, ApiError> {
    let value = get("/auth/user/info", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    Ok(Account {
        username: str_field(&data, "username"),
        group: str_field(&data, "friendlyGroup"),
        used_tunnels: u32_field(&data, "usedProxies"),
        max_tunnels: u32_field(&data, "maxProxies"),
        frp_token: None,
    })
}

/// 我的隧道列表（顺带带回节点表，用来拼公网地址）。
pub async fn proxy_list(token: &str) -> Result<Vec<RemoteTunnel>, ApiError> {
    let value = get("/auth/proxy/list", token).await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);

    // nodes 同时含 name（显示名）与 hostname（连接地址），按 nodeId 索引。
    let nodes = array_field(&data, "nodes");
    let lookup = |node_id: &str| -> (String, String) {
        for node in &nodes {
            if str_field(node, "nodeId") == node_id {
                return (str_field(node, "name"), str_field(node, "hostname"));
            }
        }
        (String::new(), String::new())
    };

    let rows = array_field(&data, "proxies");
    Ok(rows
        .iter()
        .map(|m| {
            let node_id = str_field(m, "nodeId");
            let (node_name, hostname) = lookup(&node_id);
            let kind = fallback(str_field(m, "proxyType"), "tcp");
            let remote_port = u32_field(m, "remotePort");
            let domain = str_field(m, "domain");
            // tcp / udp: hostname:remotePort；http / https: 自定义域名（可能为空）。
            let remote_address = if kind == "http" || kind == "https" {
                domain
            } else {
                match (hostname.is_empty(), remote_port) {
                    (false, Some(port)) => format!("{hostname}:{port}"),
                    _ => String::new(),
                }
            };
            RemoteTunnel {
                id: str_field(m, "proxyId"),
                name: str_field(m, "proxyName"),
                node_id,
                node_name,
                kind,
                local_ip: fallback(str_field(m, "localIp"), "127.0.0.1"),
                local_port: u32_field(m, "localPort").unwrap_or(25565),
                remote_port,
                remote_address,
                online: bool_field(m, "isOnline", false),
            }
        })
        .collect())
}

/// 节点列表。
pub async fn node_list(token: &str) -> Result<Vec<FrpNode>, ApiError> {
    let value = get("/auth/node/list", token).await?;
    let rows = array_field(&value, "data");
    Ok(rows
        .iter()
        .map(|m| FrpNode {
            id: str_field(m, "nodeId"),
            name: str_field(m, "name"),
            hostname: str_field(m, "hostname"),
            description: str_field(m, "description"),
            ..Default::default()
        })
        .collect())
}

/// 拉取隧道的成品 frpc 配置（TOML 文本，官方前端启动隧道就走这个接口）。
pub async fn tunnel_config(token: &str, proxy_id: &str) -> Result<String, ApiError> {
    let id = match proxy_id.trim().parse::<i64>() {
        Ok(number) => json!(number),
        Err(_) => json!(proxy_id),
    };
    let value = post(
        "/auth/proxy/config",
        &json!({ "proxyId": id, "format": "toml" }),
        token,
    )
    .await?;
    let data = value.get("data").cloned().unwrap_or(Value::Null);
    let config = str_field(&data, "config");
    if config.is_empty() {
        return Err(ApiError::config("配置内容为空"));
    }
    Ok(config)
}

/// 创建隧道。
pub async fn create_proxy(token: &str, req: &CreateTunnelReq) -> Result<(), ApiError> {
    post(
        "/auth/proxy/create",
        &json!({
            "accessKey": "",
            "headerXFromWhere": "",
            "hostHeaderRewrite": "",
            "proxyProtocolVersion": "",
            "nodeId": node_id_int(&req.node.id),
            "proxyName": req.name,
            "proxyType": req.kind,
            "localIp": req.local_ip,
            "localPort": req.local_port,
            "remotePort": req.remote_port,
            "domain": "",
            "useCompression": false,
            "useEncryption": false,
        }),
        token,
    )
    .await?;
    Ok(())
}

/// 删除隧道。
pub async fn delete_proxy(token: &str, proxy_id: &str) -> Result<(), ApiError> {
    let id = match proxy_id.trim().parse::<i64>() {
        Ok(number) => json!(number),
        Err(_) => json!(proxy_id),
    };
    post("/auth/proxy/delete", &json!({ "proxyId": id }), token).await?;
    Ok(())
}

fn fallback(value: String, or_else: &str) -> String {
    if value.is_empty() {
        or_else.to_string()
    } else {
        value
    }
}
