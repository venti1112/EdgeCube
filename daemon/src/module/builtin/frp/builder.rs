//! 把「已保存隧道」变成能直接丢给 frpc 的配置文本。
//!
//! 策略（方案 A）：
//!
//! | 平台 | 配置来源 |
//! | --- | --- |
//! | MSL / ChmlFrp / ME Frp / SakuraFrp | 平台 API 直接返回成品配置（toml / ini / text），原样用 |
//! | OpenFrp | 官方客户端闭源，用「节点地址 + frpc 用户 token + 隧道端口」自己拼标准 TOML |
//! | custom | 用户保存 / 表单生成的那份，原样用 |
//!
//! 非 ini 的配置统一补 `log.to = "console"`：上游 frpc 的日志要进 stdout，
//! daemon 才能读到它。

use super::api::{self, ApiError};
use super::model::{FrpNode, Provider, SavedTunnel, toml_quote};
use super::store::FrpStore;

/// 生成配置文本（不落盘，落盘见 [`super::store::FrpStore::write_toml`]）。
pub async fn build(store: &FrpStore, tunnel: &SavedTunnel) -> Result<String, ApiError> {
    match tunnel.provider {
        Provider::Custom => {
            if tunnel.custom_toml.trim().is_empty() {
                return Err(ApiError::config("自定义配置为空"));
            }
            Ok(ensure_console_log(&tunnel.custom_toml))
        }
        Provider::OpenFrp => build_openfrp(store, tunnel).await,
        _ => Ok(ensure_console_log(
            &api::remote_config(store, tunnel).await?,
        )),
    }
}

/// OpenFrp：`getUserInfo.data.token` 是 frpc 用户 token；节点地址从节点列表
/// 按 nodeId 取 hostname。官方已确认兼容原版 frpc + token 认证。
async fn build_openfrp(store: &FrpStore, tunnel: &SavedTunnel) -> Result<String, ApiError> {
    let account = api::user_info(store, Provider::OpenFrp).await?;
    let user_token = match account.frp_token.as_deref().filter(|t| !t.is_empty()) {
        Some(token) => token.to_string(),
        None => return Err(ApiError::config("获取 OpenFrp 用户 token 失败")),
    };
    let nodes = api::node_list(store, Provider::OpenFrp).await?;
    let node = find_node(&nodes, &tunnel.node_id)?;
    Ok(standard_toml(
        &node.hostname,
        node.server_port,
        &account.username,
        &user_token,
        tunnel,
    ))
}

fn find_node<'a>(nodes: &'a [FrpNode], node_id: &str) -> Result<&'a FrpNode, ApiError> {
    for node in nodes {
        if node.id == node_id {
            if node.hostname.is_empty() {
                return Err(ApiError::config(format!(
                    "节点 {} 未提供连接地址",
                    node.name
                )));
            }
            return Ok(node);
        }
    }
    Err(ApiError::config(format!(
        "节点不存在或已下线（id={node_id}）"
    )))
}

/// 标准 frp v0.52+ TOML。
fn standard_toml(
    server_addr: &str,
    server_port: u16,
    user: &str,
    auth_token: &str,
    tunnel: &SavedTunnel,
) -> String {
    let mut out = String::new();
    out.push_str(&format!("serverAddr = {}\n", toml_quote(server_addr)));
    out.push_str(&format!("serverPort = {server_port}\n"));
    if !user.is_empty() {
        out.push_str(&format!("user = {}\n", toml_quote(user)));
    }
    out.push_str(&format!("auth.token = {}\n", toml_quote(auth_token)));
    out.push_str("log.to = \"console\"\n");
    out.push_str("log.level = \"info\"\n");
    out.push('\n');
    out.push_str("[[proxies]]\n");
    out.push_str(&format!("name = {}\n", toml_quote(&tunnel.name)));
    out.push_str(&format!("type = {}\n", toml_quote(&tunnel.kind)));
    out.push_str(&format!("localIP = {}\n", toml_quote(&tunnel.local_ip)));
    out.push_str(&format!("localPort = {}\n", tunnel.local_port));
    if let Some(remote_port) = tunnel.remote_port {
        out.push_str(&format!("remotePort = {remote_port}\n"));
    }
    out
}

/// 成品配置若没指明日志去向，补一行 `log.to = "console"`（顶层字段）。
///
/// ini 配置（ChmlFrp 那份）由上游 frpc 的 ini 兼容层解析，插 TOML 的键会把它
/// 弄坏，所以整段原样返回。
fn ensure_console_log(config: &str) -> String {
    if config.trim_start().starts_with('[') {
        return config.to_string();
    }
    if config.contains("log.to") {
        return config.to_string();
    }
    // 顶层字段必须插在第一个 [[proxies]] 之前，否则会落到上一个表里。
    match config.find("[[") {
        None => format!("{config}\nlog.to = \"console\"\n"),
        Some(index) => format!(
            "{}log.to = \"console\"\n{}",
            &config[..index],
            &config[index..]
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tunnel() -> SavedTunnel {
        SavedTunnel {
            name: "我的隧道".into(),
            kind: "tcp".into(),
            local_ip: "127.0.0.1".into(),
            local_port: 25565,
            remote_port: Some(30000),
            ..Default::default()
        }
    }

    #[test]
    fn standard_toml_layout() {
        let text = standard_toml("node.example.com", 7000, "steve", "tok\"en", &tunnel());
        assert_eq!(
            text,
            "serverAddr = \"node.example.com\"\n\
             serverPort = 7000\n\
             user = \"steve\"\n\
             auth.token = \"tok\\\"en\"\n\
             log.to = \"console\"\n\
             log.level = \"info\"\n\
             \n\
             [[proxies]]\n\
             name = \"我的隧道\"\n\
             type = \"tcp\"\n\
             localIP = \"127.0.0.1\"\n\
             localPort = 25565\n\
             remotePort = 30000\n"
        );
    }

    #[test]
    fn standard_toml_omits_optional_fields() {
        let mut without_user = tunnel();
        without_user.remote_port = None;
        let text = standard_toml("node.example.com", 7000, "", "token", &without_user);
        assert!(!text.contains("user = "));
        assert!(!text.contains("remotePort"));
    }

    #[test]
    fn console_log_is_inserted_before_first_table() {
        let config = "serverAddr = \"x\"\n\n[[proxies]]\nname = \"a\"\n";
        let patched = ensure_console_log(config);
        assert_eq!(
            patched,
            "serverAddr = \"x\"\n\nlog.to = \"console\"\n[[proxies]]\nname = \"a\"\n"
        );

        // 已经写过就不重复插
        let already = "log.to = \"file\"\n[[proxies]]\n";
        assert_eq!(ensure_console_log(already), already);

        // 没有任何表：追加到末尾
        assert_eq!(
            ensure_console_log("serverAddr = \"x\"\n"),
            "serverAddr = \"x\"\n\nlog.to = \"console\"\n"
        );
    }

    #[test]
    fn ini_config_is_left_alone() {
        let ini = "[common]\nserver_addr = x\n";
        assert_eq!(ensure_console_log(ini), ini);
        let ini_padded = "\n  [common]\nserver_addr = x\n";
        assert_eq!(ensure_console_log(ini_padded), ini_padded);
    }

    #[test]
    fn find_node_rejects_missing_or_addressless_nodes() {
        let nodes = vec![
            FrpNode {
                id: "1".into(),
                name: "cn-1".into(),
                hostname: String::new(),
                ..Default::default()
            },
            FrpNode {
                id: "2".into(),
                name: "cn-2".into(),
                hostname: "cn-2.example.com".into(),
                ..Default::default()
            },
        ];
        assert!(find_node(&nodes, "1").is_err(), "没地址的节点不能用");
        assert_eq!(find_node(&nodes, "2").unwrap().name, "cn-2");
        assert!(find_node(&nodes, "3").is_err());
    }
}
