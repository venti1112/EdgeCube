//! 端到端集成测试。
//!
//! 每个用例都**真起一个服务**（绑 `127.0.0.1:0`，用系统分配的端口），
//! 真开一条 TCP 连接去打 HTTP，真开一条 WebSocket 走完整协议。
//! 只有这样才能验证「框架真的能跑起来」——单元测试测不出路由拼装、
//! 升级握手、优雅关闭这些事。

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::Message;
use tokio_util::sync::CancellationToken;

use edgecube_daemon::config::Config;
use edgecube_daemon::module::registry::{ModuleRegistry, builtin_modules};
use edgecube_daemon::server;
use edgecube_daemon::state::AppState;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>;

const TOKEN: &str = "test-token-1234";

/// 一个跑在随机端口上的完整 daemon 实例。
struct Harness {
    addr: SocketAddr,
    cancel: CancellationToken,
    serve: JoinHandle<()>,
    /// 本次测试专属的实例数据目录（见 `start` 的说明）。
    instance_dir: PathBuf,
}

impl Harness {
    async fn start(configure: impl FnOnce(&mut Config)) -> Self {
        let mut config = Config::default();
        config.server.host = "127.0.0.1".into();
        // 0 = 让系统分配空闲端口，测试之间不会撞车。
        config.server.port = 0;
        config.server.token = Some(TOKEN.into());
        config.server.heartbeat_interval_secs = 1;
        config
            .modules
            .config
            .insert("ticker".into(), toml::from_str("interval_ms = 80").unwrap());
        // 实例模块默认落在平台默认数据目录（真实的 ~/.local/share/edgecube）。
        // 测试必须把它指到临时目录：既不污染用户目录，也不让并行的用例共用一个索引。
        // 名字里带进程内自增序号 —— 光靠时间戳，同一毫秒里起的两个 harness
        // 会撞到同一个路径，先结束的那个会把另一个的目录删掉。
        let instance_dir = {
            use std::sync::atomic::{AtomicU64, Ordering};
            static SEQ: AtomicU64 = AtomicU64::new(0);
            std::env::temp_dir().join(format!(
                "edgecube-it-data-{}-{}-{}",
                std::process::id(),
                edgecube_daemon::util::now_ms(),
                SEQ.fetch_add(1, Ordering::Relaxed)
            ))
        };
        std::fs::create_dir_all(&instance_dir).expect("应能建临时数据目录");
        config.modules.config.insert(
            "instance".into(),
            toml::from_str(&format!("dir = {:?}", instance_dir.display().to_string()))
                .expect("实例模块配置应能解析"),
        );
        configure(&mut config);

        let registry = Arc::new(ModuleRegistry::build(builtin_modules(), &config).unwrap());
        let cancel = CancellationToken::new();
        let app = AppState::new(config, None, registry, cancel.clone());

        // 测试专属的 flow（`e2e.*` 命名空间）放进**这次运行的**注册表 ——
        // 注册表挂在 `AppState` 的跨模块槽上，所以每个 harness 一份，
        // 互不干扰（生产模块的步骤也会注册进同一份）。
        populate_task_test_registry(&edgecube_daemon::module::builtin::task::flows::registry(
            &app,
        ));

        app.registry.start_all(&app).await.expect("模块应能启动");

        let bound = server::bind(&app).await.expect("应能绑定端口");
        let addr = bound.local_addr;
        let serving = app.clone();
        let serve = tokio::spawn(async move {
            if let Err(e) = bound.serve(&serving).await {
                eprintln!("serve 异常退出: {e}");
            }
        });

        Self {
            addr,
            cancel,
            serve,
            instance_dir,
        }
    }

    /// 本次测试的实例数据目录（三分离布局的根）。
    fn instance_dir(&self) -> &std::path::Path {
        &self.instance_dir
    }

    fn ws_url(&self) -> String {
        format!("ws://{}/ws?token={TOKEN}", self.addr)
    }

    /// 控制台（PTY 流）的 WS 地址。协议见 `instance::serve_pty`。
    fn pty_url(&self, id: &str) -> String {
        format!("ws://{}/pty/{id}?token={TOKEN}", self.addr)
    }

    /// 主机终端的 WS 地址。协议与 `/pty/{id}` 一致，见 `shell::serve_shell`。
    fn shell_url(&self) -> String {
        format!("ws://{}/shell?token={TOKEN}", self.addr)
    }

    /// 裸 HTTP GET，返回 (状态码, 完整响应文本)。
    async fn get(&self, path: &str, token: Option<&str>) -> (u16, String) {
        self.request("GET", path, token, None).await
    }

    /// 裸 HTTP 请求（手写报文，省掉一个 HTTP 客户端依赖）。
    async fn request(
        &self,
        method: &str,
        path: &str,
        token: Option<&str>,
        body: Option<Value>,
    ) -> (u16, String) {
        let mut stream = TcpStream::connect(self.addr).await.expect("连接失败");
        let auth = match token {
            Some(t) => format!("Authorization: Bearer {t}\r\n"),
            None => String::new(),
        };
        let (payload, content) = match body {
            Some(value) => {
                let text = value.to_string();
                let headers = format!(
                    "Content-Type: application/json\r\nContent-Length: {}\r\n",
                    text.len()
                );
                (text, headers)
            }
            None => (String::new(), String::new()),
        };
        let req = format!(
            "{method} {path} HTTP/1.1\r\nHost: {}\r\n{auth}{content}Connection: close\r\n\r\n{payload}",
            self.addr
        );
        stream.write_all(req.as_bytes()).await.expect("写请求失败");

        let mut buf = Vec::new();
        stream.read_to_end(&mut buf).await.expect("读响应失败");
        let text = String::from_utf8_lossy(&buf).into_owned();
        let status = text
            .lines()
            .next()
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|c| c.parse().ok())
            .unwrap_or(0);
        (status, text)
    }

    /// 请求体与响应体都是原始字节的裸 HTTP 请求 —— 文件上传/下载用。
    ///
    /// 响应头单独返回，方便断言 `Content-Disposition` 这类头。
    async fn transfer(
        &self,
        method: &str,
        path: &str,
        token: Option<&str>,
        content_type: Option<&str>,
        body: &[u8],
    ) -> (u16, String, Vec<u8>) {
        let mut stream = TcpStream::connect(self.addr).await.expect("连接失败");
        let auth = match token {
            Some(t) => format!("Authorization: Bearer {t}\r\n"),
            None => String::new(),
        };
        let content = match content_type {
            Some(kind) => format!("Content-Type: {kind}\r\nContent-Length: {}\r\n", body.len()),
            None => format!("Content-Length: {}\r\n", body.len()),
        };
        let head = format!(
            "{method} {path} HTTP/1.1\r\nHost: {}\r\n{auth}{content}Connection: close\r\n\r\n",
            self.addr
        );
        stream
            .write_all(head.as_bytes())
            .await
            .expect("写请求头失败");
        if !body.is_empty() {
            stream.write_all(body).await.expect("写请求体失败");
        }

        let mut buf = Vec::new();
        stream.read_to_end(&mut buf).await.expect("读响应失败");
        split_response(&buf)
    }

    async fn shutdown(self) {
        self.cancel.cancel();
        let _ = tokio::time::timeout(Duration::from_secs(5), self.serve).await;
        let _ = std::fs::remove_dir_all(&self.instance_dir);
    }
}

/// 取出 HTTP 响应里的 JSON 体（跳过报文头）。
fn json_body(text: &str) -> Value {
    let body = text.split("\r\n\r\n").nth(1).unwrap_or("");
    serde_json::from_str(body).unwrap_or_else(|e| panic!("响应不是 JSON: {e}\n{text}"))
}

/// 解析一整段 JSON 字节（HTTP 响应体已剥掉报文头时用）。
fn json_bytes(raw: &[u8]) -> Value {
    serde_json::from_slice(raw)
        .unwrap_or_else(|e| panic!("响应不是 JSON: {e}\n{}", String::from_utf8_lossy(raw)))
}

/// 把一条原始 HTTP 响应拆成 (状态码, 响应头, 响应体字节)。
///
/// 测试里的请求一律带 `Connection: close`，服务端也总是给出 `Content-Length`，
/// 所以不用实现 chunked 解码；真收到分块响应会在这里露馅，而不是悄悄比对错。
fn split_response(raw: &[u8]) -> (u16, String, Vec<u8>) {
    let head_end = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .unwrap_or_else(|| panic!("响应里没有报文头分隔符: {:?}", String::from_utf8_lossy(raw)));
    let head = String::from_utf8_lossy(&raw[..head_end]).into_owned();
    assert!(
        !head.to_lowercase().contains("transfer-encoding: chunked"),
        "响应不该分块: {head}"
    );
    let status = head
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|c| c.parse().ok())
        .unwrap_or(0);
    (status, head, raw[head_end + 4..].to_vec())
}

/// 最小 percent-编码：URL 里安全的那批字符原样保留，其余按 UTF-8 字节转义。
fn url_encode(text: &str) -> String {
    let mut out = String::new();
    for byte in text.as_bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(*byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

/// 上传一个文件（请求体就是文件内容），返回 (状态码, 响应头, 响应体)。
async fn upload_file(
    h: &Harness,
    id: &str,
    path: &str,
    name: &str,
    body: &[u8],
) -> (u16, String, Vec<u8>) {
    let url = format!(
        "/api/instances/{id}/files/upload?path={}&name={}",
        url_encode(path),
        url_encode(name)
    );
    h.transfer(
        "POST",
        &url,
        Some(TOKEN),
        Some("application/octet-stream"),
        body,
    )
    .await
}

/// WS 测试客户端。
struct Client {
    ws: Ws,
}

impl Client {
    /// 连上并吃掉 `hello`，返回 hello 内容。
    async fn connect(url: &str) -> (Self, Value) {
        let (ws, _) = tokio_tungstenite::connect_async(url)
            .await
            .expect("WS 握手应成功");
        let mut client = Self { ws };
        let hello = client.next_json().await.expect("连接后第一帧应当是 hello");
        assert_eq!(
            hello["type"],
            json!("hello"),
            "首帧应是 hello，实际 {hello}"
        );
        (client, hello)
    }

    async fn send(&mut self, value: Value) {
        self.ws
            .send(Message::text(value.to_string()))
            .await
            .expect("发送失败");
    }

    /// 读下一条 JSON；收到 Close 帧返回 `None`。控制帧会被跳过。
    async fn next_json(&mut self) -> Option<Value> {
        loop {
            let frame = tokio::time::timeout(Duration::from_secs(5), self.ws.next())
                .await
                .expect("等待消息超时")?;
            match frame {
                Ok(Message::Text(text)) => {
                    return Some(
                        serde_json::from_str(text.as_str()).expect("服务端必须发合法 JSON"),
                    );
                }
                Ok(Message::Close(_)) | Err(_) => return None,
                Ok(_) => continue,
            }
        }
    }

    /// 读下一条 `result`（跳过事件等异步推送）。
    async fn next_result(&mut self) -> Value {
        loop {
            let msg = self.next_json().await.expect("连接不该断");
            if msg["type"] == json!("result") {
                return msg;
            }
        }
    }

    /// 在给定时间内读一条 JSON；超时或连接关闭返回 `None`。
    ///
    /// 用来断言「这条连接**什么都没**收到」—— 收到的是控制帧不算数。
    async fn next_json_within(&mut self, wait: Duration) -> Option<Value> {
        let deadline = tokio::time::Instant::now() + wait;
        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if remaining.is_zero() {
                return None;
            }
            match tokio::time::timeout(remaining, self.ws.next()).await {
                Err(_) | Ok(None) | Ok(Some(Err(_))) => return None,
                Ok(Some(Ok(Message::Text(text)))) => {
                    return Some(
                        serde_json::from_str(text.as_str()).expect("服务端必须发合法 JSON"),
                    );
                }
                // Ping/Pong/Close 等控制帧跳过
                Ok(Some(Ok(_))) => continue,
            }
        }
    }

    /// 等指定 id 的 `result`（不重新发送请求）。
    async fn wait_result(&mut self, id: i64) -> Value {
        loop {
            let msg = self.next_json().await.expect("连接不该断");
            if msg["type"] == json!("result") && msg["id"] == json!(id) {
                return msg;
            }
        }
    }

    /// 一次调用，返回完整的 result 信封。
    async fn call(&mut self, id: i64, method: &str, params: Value) -> Value {
        self.send(json!({"type": "call", "id": id, "method": method, "params": params}))
            .await;
        loop {
            let msg = self.next_json().await.expect("连接不该断");
            if msg["type"] == json!("result") && msg["id"] == json!(id) {
                return msg;
            }
        }
    }

    /// 调用并断言成功，返回 result 字段。
    async fn call_ok(&mut self, id: i64, method: &str, params: Value) -> Value {
        let msg = self.call(id, method, params).await;
        assert_eq!(msg["ok"], json!(true), "调用 {method} 失败: {msg}");
        msg["result"].clone()
    }

    /// 订阅并等应答。
    async fn subscribe(&mut self, id: i64, topic: &str) -> Value {
        self.send(json!({"type": "subscribe", "id": id, "topic": topic}))
            .await;
        loop {
            let msg = self.next_json().await.expect("连接不该断");
            if msg["type"] == json!("result") && msg["id"] == json!(id) {
                return msg;
            }
        }
    }

    /// 等一条指定主题的事件。
    async fn wait_event(&mut self, topic: &str) -> Value {
        loop {
            let msg = self.next_json().await.expect("连接不该断");
            if msg["type"] == json!("event") && msg["topic"] == json!(topic) {
                return msg;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

#[tokio::test]
async fn healthz_is_reachable_without_token() {
    let h = Harness::start(|_| {}).await;
    let (status, body) = h.get("/healthz", None).await;
    assert_eq!(status, 200);
    assert!(body.ends_with("ok"), "响应体应是 ok，实际 {body:?}");
    h.shutdown().await;
}

#[tokio::test]
async fn introspection_requires_a_valid_token() {
    let h = Harness::start(|_| {}).await;

    let (status, _) = h.get("/api/info", None).await;
    assert_eq!(status, 401, "没带令牌必须 401");

    let (status, body) = h.get("/api/info", Some("wrong")).await;
    assert_eq!(status, 401, "令牌错误必须 401");
    assert!(body.contains("unauthorized"));

    let (status, body) = h.get("/api/info", Some(TOKEN)).await;
    assert_eq!(status, 200);
    assert!(body.contains("\"product\""), "应当返回服务信息: {body}");
    assert!(body.contains(r#""ws_path":"/ws""#));

    h.shutdown().await;
}

#[tokio::test]
async fn token_may_be_passed_in_query_string() {
    let h = Harness::start(|_| {}).await;
    // 浏览器 WebSocket 不能自定义头，查询串是必需的能力
    let (status, _) = h.get(&format!("/api/modules?token={TOKEN}"), None).await;
    assert_eq!(status, 200);
    h.shutdown().await;
}

#[tokio::test]
async fn module_http_routes_are_mounted_and_authenticated() {
    let h = Harness::start(|_| {}).await;

    let (status, body) = h.get(&format!("/api/ticker?token={TOKEN}"), None).await;
    assert_eq!(status, 200);
    assert!(body.contains(r#""running":false"#), "ticker 状态: {body}");

    let (status, _) = h.get("/api/ticker", None).await;
    assert_eq!(status, 401, "模块路由同样要过鉴权");

    h.shutdown().await;
}

#[tokio::test]
async fn no_token_configured_means_open_access() {
    let h = Harness::start(|c| c.server.token = None).await;
    let (status, _) = h.get("/api/info", None).await;
    assert_eq!(status, 200);
    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// WebSocket
// ---------------------------------------------------------------------------

#[tokio::test]
async fn hello_advertises_capabilities() {
    let h = Harness::start(|_| {}).await;
    let (_, hello) = Client::connect(&h.ws_url()).await;

    assert_eq!(hello["product"], json!("edgecube-daemon"));
    assert_eq!(hello["auth_required"], json!(true));
    assert_eq!(hello["protocol"], json!(1));
    assert!(
        hello["peer"].as_str().unwrap().starts_with("127.0.0.1:"),
        "peer 应当是回环地址: {}",
        hello["peer"]
    );

    let names = |field: &str, key: &str| -> Vec<String> {
        hello[field]
            .as_array()
            .unwrap_or_else(|| panic!("{field} 应当是数组"))
            .iter()
            .map(|item| item[key].as_str().unwrap().to_string())
            .collect()
    };

    let methods = names("methods", "name");
    assert!(
        methods.contains(&"core.ping".to_string()),
        "方法清单: {methods:?}"
    );
    assert!(methods.contains(&"ticker.start".to_string()));

    let topics = names("topics", "topic");
    assert!(topics.contains(&"ticker.tick".to_string()));

    let modules = names("modules", "id");
    assert!(modules.contains(&"core".to_string()));
    assert!(modules.contains(&"ticker".to_string()));

    h.shutdown().await;
}

#[tokio::test]
async fn ws_requires_token_to_upgrade() {
    let h = Harness::start(|_| {}).await;

    let url = format!("ws://{}/ws", h.addr);
    assert!(
        tokio_tungstenite::connect_async(url).await.is_err(),
        "没有令牌不该允许升级"
    );

    let url = format!("ws://{}/ws?token=nope", h.addr);
    assert!(
        tokio_tungstenite::connect_async(url).await.is_err(),
        "令牌错误不该允许升级"
    );

    h.shutdown().await;
}

#[tokio::test]
async fn call_roundtrip_and_error_shapes() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let pong = client.call_ok(1, "core.ping", json!({})).await;
    assert_eq!(pong["pong"], json!(true));
    assert!(pong["ts"].as_u64().unwrap() > 0);
    // 连接 id 是进程内全局自增的，其它用例可能同时开着连接，所以只校验存在性
    assert!(pong["conn_id"].as_u64().unwrap() >= 1);

    let echoed = client
        .call_ok(2, "core.echo", json!({"hello": "世界"}))
        .await;
    assert_eq!(echoed["params"]["hello"], json!("世界"));

    // 未知方法 → method_not_found，且不该让连接断掉
    let msg = client.call(3, "core.nope", json!({})).await;
    assert_eq!(msg["ok"], json!(false));
    assert_eq!(msg["error"]["code"], json!("method_not_found"));
    assert!(msg["error"]["message"].as_str().unwrap().contains("core."));

    // 参数类型不符 → invalid_params
    let msg = client
        .call(4, "ticker.start", json!({"interval_ms": "nope"}))
        .await;
    assert_eq!(msg["error"]["code"], json!("invalid_params"));

    // 出错之后连接依然可用
    let pong = client.call_ok(5, "core.ping", json!({})).await;
    assert_eq!(pong["pong"], json!(true));

    h.shutdown().await;
}

#[tokio::test]
async fn core_host_reports_machine_shape() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let host = client.call_ok(1, "core.host", json!({})).await;

    // 具体值随机器变，这里只钉字段与类型；字段缺失/漂移由这条兜底。
    for field in [
        "hostname",
        "os_name",
        "os_version",
        "kernel_version",
        "arch",
        "cpu_brand",
        "cpu_physical_cores",
    ] {
        assert!(host.get(field).is_some(), "缺字段: {field}");
    }
    assert!(!host["arch"].as_str().unwrap_or_default().is_empty());
    assert!(host["cpu_cores"].as_u64().unwrap() >= 1);
    assert!(host["memory_total_mb"].as_u64().unwrap() >= 1);
    assert!(host["uptime_secs"].as_u64().is_some());

    h.shutdown().await;
}

#[tokio::test]
async fn concurrent_calls_are_paired_by_id() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    // 一次性甩 20 个请求，服务端并发处理，回来顺序不保证
    for id in 0..20 {
        client
            .send(json!({"type": "call", "id": id, "method": "core.echo", "params": {"n": id}}))
            .await;
    }

    let mut seen = Vec::new();
    while seen.len() < 20 {
        let msg = client.next_result().await;
        let id = msg["id"].as_i64().unwrap();
        assert_eq!(msg["ok"], json!(true));
        assert_eq!(msg["result"]["params"]["n"], json!(id), "id 与结果必须配对");
        seen.push(id);
    }
    seen.sort();
    assert_eq!(seen, (0..20).collect::<Vec<_>>());

    h.shutdown().await;
}

#[tokio::test]
async fn subscribe_receives_pushed_events() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    client
        .call_ok(1, "ticker.start", json!({"interval_ms": 60}))
        .await;

    // 订阅通配符
    let ack = client.subscribe(2, "ticker.*").await;
    assert_eq!(ack["ok"], json!(true));
    assert_eq!(ack["result"]["topic"], json!("ticker.*"));

    // 现在应该能收到推送了
    let event = client.wait_event("ticker.tick").await;
    assert_eq!(event["source"], json!("ticker"));
    assert!(event["seq"].as_u64().unwrap() >= 1);
    assert!(event["data"]["n"].as_u64().unwrap() >= 1);

    // 重复订阅是幂等的
    let ack = client.subscribe(3, "ticker.*").await;
    assert_eq!(ack["result"]["already"], json!(true));

    // 取消订阅后不再收到
    client
        .send(json!({"type": "unsubscribe", "id": 4, "topic": "ticker.*"}))
        .await;
    loop {
        let m = client.next_json().await.expect("连接不该断");
        if m["type"] == json!("result") && m["id"] == json!(4) {
            assert_eq!(m["result"]["unsubscribed"], json!(true));
            break;
        }
    }

    let stopped = client.call_ok(5, "ticker.stop", json!({})).await;
    assert_eq!(stopped["stopped"], json!(true));
    let status = client.call_ok(6, "ticker.status", json!({})).await;
    assert_eq!(status["running"], json!(false));
    assert!(status["ticks"].as_u64().unwrap() >= 1);

    h.shutdown().await;
}

#[tokio::test]
async fn malformed_and_protocol_level_messages_are_handled() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    // 不是 JSON
    client
        .ws
        .send(Message::text("{ 这不是 json"))
        .await
        .unwrap();
    let msg = client.next_json().await.unwrap();
    assert_eq!(msg["type"], json!("error"));
    assert_eq!(msg["error"]["code"], json!("bad_request"));

    // 是 JSON 但 type 不认识
    client.send(json!({"type": "nonsense"})).await;
    let msg = client.next_json().await.unwrap();
    assert_eq!(msg["type"], json!("error"));

    // 应用层 ping/pong
    client.send(json!({"type": "ping", "id": 9})).await;
    let msg = client.next_json().await.unwrap();
    assert_eq!(msg["type"], json!("pong"));
    assert_eq!(msg["id"], json!(9));

    // 订阅个数上限（默认 64）
    for i in 0..70 {
        client
            .send(json!({"type": "subscribe", "id": 100 + i, "topic": format!("topic.{i}")}))
            .await;
    }
    let mut ok_count = 0;
    let mut busy_count = 0;
    for _ in 0..70 {
        let msg = client.next_result().await;
        if msg["ok"] == json!(true) {
            ok_count += 1;
        } else {
            assert_eq!(msg["error"]["code"], json!("busy"));
            busy_count += 1;
        }
    }
    assert_eq!(ok_count, 64, "上限内应当全部成功");
    assert_eq!(busy_count, 6, "超出的必须被拒绝");

    h.shutdown().await;
}

#[tokio::test]
async fn local_only_methods_work_over_loopback() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    // 测试是从 127.0.0.1 连过来的，所以 Scope::Local 的方法应当放行
    let config = client.call_ok(1, "core.config", json!({})).await;
    assert_eq!(
        config["server"]["token"],
        json!("<redacted>"),
        "令牌必须被遮蔽"
    );
    assert!(
        !config.to_string().contains(TOKEN),
        "响应里不能出现真实令牌: {config}"
    );

    h.shutdown().await;
}

#[tokio::test]
async fn graceful_shutdown_notifies_client() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;
    assert_eq!(
        client.call_ok(1, "core.ping", json!({})).await["pong"],
        json!(true)
    );

    h.cancel.cancel();

    // 应当先收到 bye，然后连接被关闭
    let bye = loop {
        match client.next_json().await {
            Some(m) if m["type"] == json!("bye") => break m,
            Some(_) => continue,
            None => panic!("还没收到 bye 连接就断了"),
        }
    };
    assert_eq!(bye["code"], json!(1001));
    assert!(client.next_json().await.is_none(), "bye 之后应当关闭连接");

    // 服务任务应当自行退出
    tokio::time::timeout(Duration::from_secs(5), h.serve)
        .await
        .expect("serve 应当优雅退出")
        .expect("serve 任务不该 panic");
}

#[tokio::test]
async fn disabled_module_is_fully_absent() {
    // ticker 被禁用后：方法没了、HTTP 路由没了，core 仍在
    let h = Harness::start(|c| {
        c.modules.disabled = vec!["ticker".into()];
    })
    .await;

    let (status, body) = h.get(&format!("/api/modules?token={TOKEN}"), None).await;
    assert_eq!(status, 200);
    assert!(body.contains("method_count"));

    let (mut client, hello) = Client::connect(&h.ws_url()).await;
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    assert!(
        !methods.iter().any(|m| m.starts_with("ticker.")),
        "被禁用的模块不该注册方法: {methods:?}"
    );
    assert!(methods.contains(&"core.ping".to_string()));

    let msg = client.call(1, "ticker.status", json!({})).await;
    assert_eq!(msg["error"]["code"], json!("method_not_found"));

    // 模块的 HTTP 路由也应当消失（未挂载 → 404）
    let (status, _) = h.get(&format!("/api/ticker?token={TOKEN}"), None).await;
    assert_eq!(status, 404);

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 多连接隔离：一台 daemon 服务多个前端时，谁的数据是谁的
// ---------------------------------------------------------------------------

/// A 的请求应答只会回到 A。
#[tokio::test]
async fn replies_are_private_to_the_requesting_connection() {
    let h = Harness::start(|_| {}).await;
    let (mut a, hello_a) = Client::connect(&h.ws_url()).await;
    let (mut b, hello_b) = Client::connect(&h.ws_url()).await;

    // 两条连接是两条独立会话：conn_id 不同
    assert_ne!(
        hello_a["conn_id"], hello_b["conn_id"],
        "同一 daemon 的两个前端应当拿到不同的连接 id"
    );

    // A 调用 → 只有 A 收到应答
    let echoed = a
        .call_ok(1, "core.echo", json!({"secret": "only-for-A"}))
        .await;
    assert_eq!(echoed["params"]["secret"], json!("only-for-A"));
    let leaked = b.next_json_within(Duration::from_millis(300)).await;
    assert!(leaked.is_none(), "B 不该收到 A 的应答，却收到: {leaked:?}");

    // 反过来一样（B 复用同一个 id = 1，也不受影响）
    let echoed = b
        .call_ok(1, "core.echo", json!({"secret": "only-for-B"}))
        .await;
    assert_eq!(echoed["params"]["secret"], json!("only-for-B"));
    let leaked = a.next_json_within(Duration::from_millis(300)).await;
    assert!(leaked.is_none(), "A 不该收到 B 的应答，却收到: {leaked:?}");

    h.shutdown().await;
}

/// 两条连接并发使用同一个 id 也不会串台：id 只是**会话内**的配对键。
#[tokio::test]
async fn same_id_on_two_connections_do_not_collide() {
    let h = Harness::start(|_| {}).await;
    let (mut a, _) = Client::connect(&h.ws_url()).await;
    let (mut b, _) = Client::connect(&h.ws_url()).await;

    a.send(json!({"type": "call", "id": 7, "method": "core.echo", "params": {"who": "A"}}))
        .await;
    b.send(json!({"type": "call", "id": 7, "method": "core.echo", "params": {"who": "B"}}))
        .await;

    let for_a = a.wait_result(7).await;
    let for_b = b.wait_result(7).await;

    assert_eq!(for_a["id"], json!(7));
    assert_eq!(for_b["id"], json!(7));
    assert_eq!(for_a["result"]["params"]["who"], json!("A"));
    assert_eq!(for_b["result"]["params"]["who"], json!("B"));

    // 各自的 conn_id 也不一样（core.ping 会回带上它）
    let ping_a = a.call_ok(8, "core.ping", json!({})).await;
    let ping_b = b.call_ok(8, "core.ping", json!({})).await;
    assert_ne!(ping_a["conn_id"], ping_b["conn_id"]);

    h.shutdown().await;
}

/// 事件是发布/订阅：没订阅的连接收不到，订阅了的才收得到。
///
/// 这和「应答只回发起方」是两件不同的事 —— 事件本来就是给多个订阅者看的，
/// 但不是**所有**连接都能看到。
#[tokio::test]
async fn events_only_reach_subscribers() {
    let h = Harness::start(|_| {}).await;
    let (mut a, _) = Client::connect(&h.ws_url()).await;
    let (mut b, _) = Client::connect(&h.ws_url()).await;

    // 只有 A 订阅
    let ack = a.subscribe(1, "ticker.*").await;
    assert_eq!(ack["ok"], json!(true));
    a.call_ok(2, "ticker.start", json!({"interval_ms": 60}))
        .await;

    // A 收得到推送
    let event = a.wait_event("ticker.tick").await;
    assert_eq!(event["source"], json!("ticker"));
    assert!(event["data"]["n"].as_u64().unwrap() >= 1);

    // B 什么都没收到
    let leaked = b.next_json_within(Duration::from_millis(300)).await;
    assert!(
        leaked.is_none(),
        "没订阅的连接不该收到事件，却收到: {leaked:?}"
    );

    // B 自己订上之后才开始收
    b.subscribe(3, "ticker.*").await;
    let for_b = b.wait_event("ticker.tick").await;
    assert_eq!(for_b["topic"], json!("ticker.tick"));

    a.call_ok(4, "ticker.stop", json!({})).await;
    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 实例管理模块（真 WS + 真 HTTP）
// ---------------------------------------------------------------------------

#[tokio::test]
async fn instance_module_crud_over_ws() {
    let h = Harness::start(|_| {}).await;
    let data_dir = h.instance_dir().to_path_buf();
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // hello 里应当能看到这个模块的方法与主题
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    assert!(
        methods.contains(&"instance.create".to_string()),
        "{methods:?}"
    );
    assert!(methods.contains(&"instance.delete".to_string()));
    assert!(methods.contains(&"instance.status".to_string()));
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(topics.contains(&"instance.created".to_string()));

    // 1) 空列表
    let list = client.call_ok(1, "instance.list", json!({})).await;
    assert_eq!(list["count"], json!(0));
    assert_eq!(list["data_dir"], json!(data_dir.display().to_string()));

    // 2) 新建。参数用**线上**的 snake_case —— create 直接反序列化元数据模型，
    //    多词字段两种拼法都收（见 model.rs「两个拼法都收」）。
    let created = client
        .call_ok(
            2,
            "instance.create",
            json!({
                "name": "生存服",
                "startup_command": "java -Xmx2G -jar server.jar nogui",
                "compat_mode": true
            }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    assert!(id.len() == 16, "id 应是 16 位 hex: {id}");
    assert_eq!(created["instance"]["name"], json!("生存服"));
    assert_eq!(
        created["instance"]["startup_command"],
        json!("java -Xmx2G -jar server.jar nogui"),
        "snake_case 的 create 参数不能像以前那样被静默丢掉"
    );
    assert_eq!(created["instance"]["compat_mode"], json!(true));
    assert_eq!(created["selected"], json!(id));
    assert!(
        data_dir.join("instances").join(&id).is_dir(),
        "工作目录应已建好"
    );
    // 元数据里没有「服务端类型」这套字段；启动配置的字段则是**线上标准形状**：
    // 没配就是显式 null（前端不用猜字段在不在）
    assert!(created["instance"].get("runtime").is_none());
    for key in [
        "runtime_env_id",
        "server_file",
        "max_memory",
        "custom_jvm_args",
    ] {
        assert!(
            created["instance"][key].is_null(),
            "{key} 没配就该是 null: {}",
            created["instance"]
        );
    }
    // 只写了启动命令 → 手动模式，生效命令就是它
    assert_eq!(created["instance"]["manual_command"], json!(true));
    assert_eq!(
        created["instance"]["launch_command"],
        json!("java -Xmx2G -jar server.jar nogui")
    );

    // 3) 列表里有了，且标记为选中
    let list = client.call_ok(3, "instance.list", json!({})).await;
    assert_eq!(list["count"], json!(1));
    assert_eq!(list["instances"][0]["id"], json!(id));
    assert_eq!(list["instances"][0]["selected"], json!(true));

    // 4) 带状态
    let listed = client
        .call_ok(4, "instance.list", json!({ "with_status": true }))
        .await;
    assert_eq!(listed["instances"][0]["status"]["phase"], json!("stopped"));
    assert_eq!(listed["instances"][0]["status"]["dir_exists"], json!(true));

    // 5) 详情 + 状态
    let got = client.call_ok(5, "instance.get", json!({ "id": id })).await;
    assert_eq!(
        got["instance"]["startup_command"],
        json!("java -Xmx2G -jar server.jar nogui")
    );
    // 配了启动命令 → 没有任何告警
    assert!(
        got["lint"].as_array().unwrap().is_empty(),
        "{}",
        got["lint"]
    );
    let status = client
        .call_ok(6, "instance.status", json!({ "id": id }))
        .await;
    assert_eq!(
        status["status"]["process_managed"],
        json!(true),
        "进程管理已经接进来了"
    );
    assert_eq!(status["status"]["running"], json!(false));
    assert!(
        status["status"]["warnings"].as_array().unwrap().is_empty(),
        "{}",
        status["status"]["warnings"]
    );

    // 6) 出错的分支
    let dup = client
        .call(7, "instance.create", json!({ "name": "生存服" }))
        .await;
    assert_eq!(dup["error"]["code"], json!("instance_name_taken"));

    let bogus = client
        .call(8, "instance.delete", json!({ "id": "ffffffffffffffff" }))
        .await;
    assert_eq!(bogus["error"]["code"], json!("instance_not_found"));

    let evil = client
        .call(9, "instance.delete", json!({ "id": "../../etc" }))
        .await;
    assert_eq!(evil["error"]["code"], json!("invalid_params"));

    let missing_param = client.call(10, "instance.get", json!({})).await;
    assert_eq!(missing_param["error"]["code"], json!("invalid_params"));

    // 7) 删除
    let deleted = client
        .call_ok(11, "instance.delete", json!({ "id": id }))
        .await;
    assert_eq!(deleted["deleted"], json!(true));
    assert_eq!(deleted["files_deleted"], json!(true));
    assert!(!data_dir.join("instances").join(&id).exists());
    assert_eq!(
        client.call_ok(12, "instance.list", json!({})).await["count"],
        json!(0)
    );

    h.shutdown().await;
}

#[tokio::test]
async fn instance_module_http_routes() {
    let h = Harness::start(|_| {}).await;
    let data_dir = h.instance_dir().to_path_buf();
    let token = Some(TOKEN);

    // 未鉴权 → 401
    let (status, _) = h.get("/api/instances", None).await;
    assert_eq!(status, 401);

    // 建一个
    let (status, body) = h
        .request(
            "POST",
            "/api/instances",
            token,
            Some(json!({ "name": "HTTP 建的" })),
        )
        .await;
    assert_eq!(status, 200, "{body}");
    let created = json_body(&body);
    assert_eq!(created["ok"], json!(true));
    let id = created["result"]["instance"]["id"]
        .as_str()
        .unwrap()
        .to_string();

    // 列表
    let (status, body) = h.get("/api/instances", token).await;
    assert_eq!(status, 200);
    let listed = json_body(&body);
    assert_eq!(listed["result"]["count"], json!(1));

    // 单个（这里回的是状态，方便前端一次拿到"活没活"）
    let (status, body) = h.get(&format!("/api/instances/{id}"), token).await;
    assert_eq!(status, 200);
    let one = json_body(&body);
    assert_eq!(one["result"]["status"]["id"], json!(id));
    assert_eq!(one["result"]["status"]["phase"], json!("stopped"));

    // 选中
    let (status, _) = h
        .request("POST", &format!("/api/instances/{id}/select"), token, None)
        .await;
    assert_eq!(status, 200);

    // 不识别的实例 → 404（instance_not_found 映射过来的）
    let (status, _) = h.get("/api/instances/ffffffffffffffff", token).await;
    assert_eq!(status, 404);

    // 删除（保留文件）
    let (status, body) = h
        .request(
            "DELETE",
            &format!("/api/instances/{id}?keep_files=true"),
            token,
            None,
        )
        .await;
    assert_eq!(status, 200, "{body}");
    let deleted = json_body(&body);
    assert_eq!(deleted["result"]["files_deleted"], json!(false));
    assert!(data_dir.join("instances").join(&id).is_dir(), "文件应保留");

    h.shutdown().await;
}

#[tokio::test]
async fn instance_scan_reports_disk_changes() {
    let h = Harness::start(|_| {}).await;
    let data_dir = h.instance_dir().to_path_buf();
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let created = client
        .call_ok(1, "instance.create", json!({ "name": "会被删掉的" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();

    // 手工制造"磁盘与索引不一致"：删掉目录 + 加一个未登记的目录
    std::fs::remove_dir_all(data_dir.join("instances").join(&id)).unwrap();
    std::fs::create_dir_all(data_dir.join("instances").join("aaaabbbbccccdddd")).unwrap();

    let report = client.call_ok(2, "instance.scan", json!({})).await;
    assert_eq!(report["pruned"], json!([id.clone()]));
    assert_eq!(report["adopted"], json!(["aaaabbbbccccdddd"]));
    assert_eq!(report["total"], json!(1));
    assert_eq!(
        client.call_ok(3, "instance.list", json!({})).await["instances"][0]["name"],
        json!("aaaabbbbccccdddd"),
        "接管时名称默认取目录名"
    );

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 实例文件管理
// ---------------------------------------------------------------------------

/// 一条连接把文件管理的各种操作走一遍：建/读写/搜索/改名/复制/移动/压缩/解压/删除，
/// 外加越界路径与重名冲突的稳定错误码。
#[tokio::test]
async fn instance_files_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // hello 里要能看见这批方法：客户端据此决定要不要显示文件页
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for wanted in [
        "instance.files.list",
        "instance.files.write",
        "instance.files.compress",
        "instance.files.extract",
    ] {
        assert!(
            methods.contains(&wanted.to_string()),
            "缺少 {wanted}: {methods:?}"
        );
    }

    let created = client
        .call_ok(1, "instance.create", json!({ "name": "文件" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    let work_dir = h.instance_dir().join("instances").join(&id);

    // 1) 刚建好的实例目录是空的
    let listed = client
        .call_ok(2, "instance.files.list", json!({ "id": id }))
        .await;
    assert_eq!(listed["path"], json!(""));
    assert_eq!(listed["entries"], json!([]));

    // 2) 建目录 / 建空文件；重名都要报 file_exists
    let dir = client
        .call_ok(
            3,
            "instance.files.mkdir",
            json!({ "id": id, "name": "mods" }),
        )
        .await;
    assert_eq!(dir["entry"]["path"], json!("mods"));
    assert_eq!(dir["entry"]["is_dir"], json!(true));

    let file = client
        .call_ok(
            4,
            "instance.files.create",
            json!({ "id": id, "name": "server.properties" }),
        )
        .await;
    assert_eq!(file["entry"]["size"], json!(0));

    let dup = client
        .call(
            5,
            "instance.files.mkdir",
            json!({ "id": id, "name": "mods" }),
        )
        .await;
    assert_eq!(dup["error"]["code"], json!("file_exists"));

    // 3) 写文本 → 读回（中文原样往返）
    let text = "#Minecraft server properties\nmotd=你好，边缘方块\n";
    let written = client
        .call_ok(
            6,
            "instance.files.write",
            json!({ "id": id, "path": "server.properties", "content": text }),
        )
        .await;
    assert_eq!(written["size"], json!(text.len()));

    let read = client
        .call_ok(
            7,
            "instance.files.read",
            json!({ "id": id, "path": "server.properties" }),
        )
        .await;
    assert_eq!(read["content"], json!(text));
    assert_eq!(read["encoding"], json!("utf-8"));
    assert_eq!(read["size"], json!(text.len()));

    // 非 UTF-8：严格读报 file_not_utf8，raw=true 时按 latin1 一定打得开
    std::fs::write(work_dir.join("legacy.dat"), [0xff, 0x00, 0x41]).unwrap();
    let strict = client
        .call(
            8,
            "instance.files.read",
            json!({ "id": id, "path": "legacy.dat" }),
        )
        .await;
    assert_eq!(strict["error"]["code"], json!("file_not_utf8"));
    let raw = client
        .call_ok(
            9,
            "instance.files.read",
            json!({ "id": id, "path": "legacy.dat", "raw": true }),
        )
        .await;
    assert_eq!(raw["encoding"], json!("latin1"));
    assert_eq!(raw["content"].as_str().unwrap().chars().count(), 3);

    // 4) 搜索：默认只看当前层，递归时要显式打开
    client
        .call_ok(
            10,
            "instance.files.create",
            json!({ "id": id, "path": "mods", "name": "jei.jar" }),
        )
        .await;
    let shallow = client
        .call_ok(
            11,
            "instance.files.search",
            json!({ "id": id, "query": "JEI" }),
        )
        .await;
    assert_eq!(
        shallow["entries"],
        json!([]),
        "根目录直接子项里没有 jei.jar"
    );
    let deep = client
        .call_ok(
            12,
            "instance.files.search",
            json!({ "id": id, "path": "mods", "query": "jei" }),
        )
        .await;
    assert_eq!(deep["entries"][0]["path"], json!("mods/jei.jar"));

    // 5) 重命名（同目录内）
    let renamed = client
        .call_ok(
            13,
            "instance.files.rename",
            json!({ "id": id, "path": "server.properties", "name": "server.properties.bak" }),
        )
        .await;
    assert_eq!(renamed["entry"]["path"], json!("server.properties.bak"));

    // 6) 复制重名自动加 ` (n)`；移动重名则硬报错（两套语义）
    client
        .call_ok(
            14,
            "instance.files.mkdir",
            json!({ "id": id, "name": "backup" }),
        )
        .await;
    let copied = client
        .call_ok(
            15,
            "instance.files.copy",
            json!({ "id": id, "path": "server.properties.bak", "dest": "backup" }),
        )
        .await;
    assert_eq!(
        copied["entry"]["path"],
        json!("backup/server.properties.bak")
    );

    // 重名复制自动改名：` (n)` 插在扩展名**前**
    let copied_again = client
        .call_ok(
            16,
            "instance.files.copy",
            json!({ "id": id, "path": "server.properties.bak", "dest": "backup" }),
        )
        .await;
    assert_eq!(
        copied_again["entry"]["name"],
        json!("server.properties (1).bak")
    );

    let clash = client
        .call(
            17,
            "instance.files.move",
            json!({ "id": id, "path": "server.properties.bak", "dest": "backup" }),
        )
        .await;
    assert_eq!(clash["error"]["code"], json!("file_exists"));

    let moved = client
        .call_ok(
            18,
            "instance.files.move",
            json!({ "id": id, "path": "backup/server.properties (1).bak", "dest": "mods" }),
        )
        .await;
    assert_eq!(
        moved["entry"]["path"],
        json!("mods/server.properties (1).bak")
    );

    // 不能把目录搬进它自己里面
    client
        .call_ok(
            19,
            "instance.files.mkdir",
            json!({ "id": id, "path": "mods", "name": "sub" }),
        )
        .await;
    let into_self = client
        .call(
            20,
            "instance.files.move",
            json!({ "id": id, "path": "mods", "dest": "mods/sub" }),
        )
        .await;
    assert_eq!(
        into_self["error"]["code"],
        json!("file_invalid_destination")
    );

    // 7) 压缩：单个文件去掉扩展名（server.properties.bak → server.properties.zip）
    let zipped = client
        .call_ok(
            21,
            "instance.files.compress",
            json!({ "id": id, "paths": ["server.properties.bak"], "dest": "" }),
        )
        .await;
    assert_eq!(zipped["entry"]["name"], json!("server.properties.zip"));
    assert!(zipped["entry"]["size"].as_u64().unwrap() > 0);

    // 解压到同名新文件夹（缺省子目录名 = 归档名去扩展名）
    let extracted = client
        .call_ok(
            22,
            "instance.files.extract",
            json!({ "id": id, "path": "server.properties.zip", "dest": "" }),
        )
        .await;
    assert_eq!(extracted["entry"]["name"], json!("server.properties"));
    let inside = client
        .call_ok(
            23,
            "instance.files.list",
            json!({ "id": id, "path": "server.properties" }),
        )
        .await;
    assert_eq!(
        inside["entries"][0]["path"],
        json!("server.properties/server.properties.bak")
    );

    // 目录压缩：顶层就是目录本身；重名再压一次会自动加 ` (1)`
    let dir_zip = client
        .call_ok(
            24,
            "instance.files.compress",
            json!({ "id": id, "paths": ["mods"], "dest": "" }),
        )
        .await;
    assert_eq!(dir_zip["entry"]["name"], json!("mods.zip"));
    let dir_zip_again = client
        .call_ok(
            25,
            "instance.files.compress",
            json!({ "id": id, "paths": ["mods"], "dest": "" }),
        )
        .await;
    assert_eq!(dir_zip_again["entry"]["name"], json!("mods (1).zip"));

    // 8) 路径越界与根目录保护
    let escape = client
        .call(
            26,
            "instance.files.list",
            json!({ "id": id, "path": "../" }),
        )
        .await;
    assert_eq!(escape["error"]["code"], json!("invalid_params"));

    let rm_root = client
        .call(27, "instance.files.delete", json!({ "id": id, "path": "" }))
        .await;
    assert_eq!(rm_root["error"]["code"], json!("invalid_params"));

    let missing = client
        .call(
            28,
            "instance.files.read",
            json!({ "id": id, "path": "nope.txt" }),
        )
        .await;
    assert_eq!(missing["error"]["code"], json!("file_not_found"));

    // 9) 删除是幂等的：第二次回 deleted=false
    let deleted = client
        .call_ok(
            29,
            "instance.files.delete",
            json!({ "id": id, "path": "mods.zip" }),
        )
        .await;
    assert_eq!(deleted["deleted"], json!(true));
    let again = client
        .call_ok(
            30,
            "instance.files.delete",
            json!({ "id": id, "path": "mods.zip" }),
        )
        .await;
    assert_eq!(again["deleted"], json!(false));

    h.shutdown().await;
}

/// 上传 / 下载走 HTTP：请求体就是文件内容，下载目录时现场打成 zip。
#[tokio::test]
async fn instance_files_transfer_over_http() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let created = client
        .call_ok(1, "instance.create", json!({ "name": "传输" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    client
        .call_ok(
            2,
            "instance.files.mkdir",
            json!({ "id": id, "name": "mods" }),
        )
        .await;

    // 没令牌一律 401（上传下载走同一套鉴权）
    let (status, _, _) = h
        .transfer(
            "POST",
            &format!("/api/instances/{id}/files/upload?path=&name=x.jar"),
            None,
            Some("application/octet-stream"),
            b"nope",
        )
        .await;
    assert_eq!(status, 401);
    let (status, _, _) = h
        .transfer(
            "GET",
            &format!("/api/instances/{id}/files/download?path=x.jar"),
            None,
            None,
            b"",
        )
        .await;
    assert_eq!(status, 401);

    // 1) 上传：请求体就是文件内容
    let payload: Vec<u8> = (0..70_000u32).map(|i| (i % 251) as u8).collect();
    let (status, _, body) = upload_file(&h, &id, "", "server.jar", &payload).await;
    assert_eq!(status, 200, "{}", String::from_utf8_lossy(&body));
    let uploaded = json_bytes(&body);
    assert_eq!(uploaded["result"]["entry"]["path"], json!("server.jar"));
    assert_eq!(uploaded["result"]["entry"]["size"], json!(payload.len()));

    // 重名不覆盖 → 自动加 ` (1)`（插在扩展名前）
    let (status, _, body) = upload_file(&h, &id, "", "server.jar", b"second").await;
    assert_eq!(status, 200);
    let second = json_bytes(&body);
    assert_eq!(second["result"]["entry"]["name"], json!("server (1).jar"));

    // 显式覆盖 → 名字不变，内容换掉
    let (status, _, body) = h
        .transfer(
            "POST",
            &format!("/api/instances/{id}/files/upload?path=&name=server.jar&overwrite=true"),
            Some(TOKEN),
            Some("application/octet-stream"),
            b"overwritten",
        )
        .await;
    assert_eq!(status, 200, "{}", String::from_utf8_lossy(&body));
    let overwritten = json_bytes(&body);
    assert_eq!(
        overwritten["result"]["entry"]["size"],
        json!("overwritten".len())
    );

    // 上传到不存在的目录 → 400（不是 500，也不是写了个奇怪的路径出来）
    let (status, _, body) = upload_file(&h, &id, "nope", "x.jar", b"x").await;
    assert_eq!(status, 400, "{}", String::from_utf8_lossy(&body));
    assert_eq!(json_bytes(&body)["error"]["code"], json!("invalid_params"));

    // 2) 下载文件：字节要与上传的一模一样
    let (status, head, body) = h
        .transfer(
            "GET",
            &format!("/api/instances/{id}/files/download?path=server.jar"),
            Some(TOKEN),
            None,
            b"",
        )
        .await;
    assert_eq!(status, 200);
    assert_eq!(body, b"overwritten", "下载的应当是覆盖后的内容");
    assert!(head.contains("application/octet-stream"), "{head}");
    assert!(head.contains(r#"filename="server.jar""#), "{head}");

    // 中文文件名：下载头里要有 RFC 5987 的 filename*
    let (status, _, _) = upload_file(&h, &id, "mods", "中文模组.jar", b"mod").await;
    assert_eq!(status, 200);
    let (status, head, body) = h
        .transfer(
            "GET",
            &format!(
                "/api/instances/{id}/files/download?path={}",
                url_encode("mods/中文模组.jar")
            ),
            Some(TOKEN),
            None,
            b"",
        )
        .await;
    assert_eq!(status, 200);
    assert_eq!(body, b"mod");
    assert!(
        head.contains("filename*=UTF-8''%E4%B8%AD%E6%96%87%E6%A8%A1%E7%BB%84.jar"),
        "中文文件名要走 filename*: {head}"
    );

    // 3) 下载目录：现场打 zip，落到临时文件里流出来
    let (status, head, body) = h
        .transfer(
            "GET",
            &format!("/api/instances/{id}/files/download?path=mods"),
            Some(TOKEN),
            None,
            b"",
        )
        .await;
    assert_eq!(status, 200);
    assert!(head.contains("application/zip"), "{head}");
    assert!(head.contains(r#"filename="mods.zip""#), "{head}");
    assert!(body.starts_with(b"PK\x03\x04"), "应当是个 zip 包");
    // zip 是现打在系统临时目录里的，读完后要由清理钩子删掉
    // （删除发生在服务端读取循环收尾之后，跟响应到达客户端有个几毫秒的时差）
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    loop {
        let leftovers: Vec<String> = std::fs::read_dir(std::env::temp_dir())
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|name| name.starts_with("edgecube-dl-"))
            .collect();
        if leftovers.is_empty() {
            break;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "下载用的临时 zip 应当被删掉，还剩 {leftovers:?}"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    // 4) 不存在的路径 → 404
    let (status, _, body) = h
        .transfer(
            "GET",
            &format!("/api/instances/{id}/files/download?path=nope.txt"),
            Some(TOKEN),
            None,
            b"",
        )
        .await;
    assert_eq!(status, 404);
    assert_eq!(json_bytes(&body)["error"]["code"], json!("file_not_found"));

    // 5) 实例不存在 → 404
    let (status, _, _) = h
        .transfer(
            "GET",
            "/api/instances/ffffffffffffffff/files/download?path=x",
            Some(TOKEN),
            None,
            b"",
        )
        .await;
    assert_eq!(status, 404);

    h.shutdown().await;
}

/// 把 monitor 的采样间隔压到下限，省得用例等两秒。
fn fast_monitor(config: &mut Config) {
    config.modules.config.insert(
        "monitor".into(),
        toml::from_str("interval_ms = 250\npublish = true").expect("监控配置应能解析"),
    );
}

/// `monitor.snapshot` / `monitor.status` 走真连接，字段语义要跟文档一致。
#[tokio::test]
async fn monitor_snapshot_and_status_over_ws() {
    let h = Harness::start(fast_monitor).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let snap = client.call_ok(1, "monitor.snapshot", json!({})).await;
    assert_eq!(snap["interval_ms"], json!(250));
    assert!(snap["sampled_at_ms"].as_u64().unwrap() > 0, "要有采样时刻");
    assert!(snap["cpu_cores"].as_u64().unwrap() >= 1, "逻辑核数不该是 0");
    // 进程管理还没接入：这个字段必须是 null，而不是编一个 0 出来
    assert_eq!(snap["server_mem_mb"], json!(null));

    if snap["supported"] == json!(true) {
        let total = snap["total_mem_mb"].as_u64().unwrap();
        let used = snap["used_mem_mb"].as_u64().unwrap();
        let available = snap["available_mem_mb"].as_u64().unwrap();
        assert!(total > 0, "读不到总内存说明平台适配有问题");
        assert!(used + available <= total + 1, "内存口径自相矛盾");
        let percent = snap["used_mem_percent"].as_f64().unwrap();
        assert!((0.0..=100.0).contains(&percent), "占比越界: {percent}");
    }

    let status = client.call_ok(2, "monitor.status", json!({})).await;
    assert_eq!(status["running"], json!(true), "采样器应当常驻");
    assert_eq!(status["interval_ms"], json!(250));
    assert_eq!(status["min_interval_ms"], json!(250));
    assert_eq!(status["publish"], json!(true));
    assert!(status["samples"].as_u64().unwrap() >= 1, "至少采过一次");

    // 采样器真的在跑，而且跑够两个间隔之后 CPU 就有读数了。
    // （第一份快照的 `cpu_usage` 必然是 null：sysinfo 靠两次采样的差值算，
    //   进程刚起来时还没有可信窗口 —— 这是文档里写明的语义。）
    tokio::time::sleep(Duration::from_millis(700)).await;
    let fresh = client.call_ok(3, "monitor.snapshot", json!({})).await;
    assert!(
        fresh["sampled_at_ms"].as_u64().unwrap() > snap["sampled_at_ms"].as_u64().unwrap(),
        "采样器应当一直在刷新快照"
    );
    if snap["supported"] == json!(true) {
        let usage = fresh["cpu_usage"]
            .as_f64()
            .unwrap_or_else(|| panic!("跑够两个间隔后应当有 CPU 读数: {fresh}"));
        assert!((0.0..=100.0).contains(&usage), "使用率越界: {usage}");
    }

    h.shutdown().await;
}

/// 订阅 `monitor.stats` 能持续收到推送，内容与 `monitor.snapshot` 同构。
#[tokio::test]
async fn monitor_stats_are_pushed_over_ws() {
    let h = Harness::start(fast_monitor).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let sub = client.subscribe(1, "monitor.stats").await;
    assert_eq!(sub["ok"], json!(true), "订阅应成功: {sub}");

    let event = client.wait_event("monitor.stats").await;
    assert_eq!(event["data"]["interval_ms"], json!(250));
    assert!(event["data"].get("total_mem_mb").is_some());
    assert!(event["seq"].as_u64().unwrap() >= 1, "事件要有全局序号");

    h.shutdown().await;
}

/// HTTP 侧同一套能力，并且一样要过鉴权。
#[tokio::test]
async fn monitor_http_routes() {
    let h = Harness::start(fast_monitor).await;

    let (status, body) = h.get("/api/monitor", Some(TOKEN)).await;
    assert_eq!(status, 200);
    let body = json_body(&body);
    assert_eq!(body["ok"], json!(true), "API 信封: {body}");
    let snap = &body["result"];
    assert!(snap.get("total_mem_mb").is_some(), "快照字段缺失: {snap}");
    assert_eq!(snap["server_mem_mb"], json!(null));

    let (status, body) = h.get("/api/monitor/status", Some(TOKEN)).await;
    assert_eq!(status, 200);
    let body = json_body(&body);
    assert_eq!(body["result"]["running"], json!(true), "状态: {body}");

    let (status, _) = h.get("/api/monitor", None).await;
    assert_eq!(status, 401, "模块挂的路由同样要过鉴权");

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 进程生命周期与控制台
// ---------------------------------------------------------------------------

/// 建一个「跑着不动、可用 ^C 停」的实例，返回它的 id。
///
/// 用 `sleep` 而不是真服务端：测试只关心协议与阶段流转，不需要真的 Minecraft。
async fn spawn_sleeper(client: &mut Client, id_of_call: i64, name: &str) -> String {
    let created = client
        .call_ok(
            id_of_call,
            "instance.create",
            json!({
                "name": name,
                "startup_command": "printf 'hello-from-server\\n'; sleep 300",
                "stop_command": "^C",
            }),
        )
        .await;
    created["instance"]["id"].as_str().unwrap().to_string()
}

/// WS 侧改实例：`params` 里本来就带着寻址用的 `id`，它**不是**补丁字段。
///
/// 客户端（app 的 `InstanceApi.update`）恰恰就是这么发的，而 daemon 一度把整个
/// `params` 直接当补丁去校验 → 「不认识的字段 `id`」，实例设置完全存不下去。
/// 同一批还有 `stop_command` 不在白名单、`line_ending` 被 trim 成空串两处，
/// 所以这个用例断言的是**整个客户端形状**，而不是单个字段。
#[tokio::test]
async fn instance_update_over_ws_accepts_the_client_shaped_patch() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let created = client
        .call_ok(1, "instance.create", json!({ "name": "服" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();

    let updated = client
        .call_ok(
            2,
            "instance.update",
            json!({
                "id": id, // ← 寻址参数，混在补丁里
                "name": "新名字",
                "startup_command": "java -jar server.jar nogui",
                "stop_command": "^C",
                "compat_mode": false,
                "auto_restart_on_exit": false,
                "line_ending": "\r\n",
            }),
        )
        .await;
    assert_eq!(updated["changed"], json!(true));
    assert_eq!(updated["instance"]["id"], json!(id), "id 不该被改掉");
    assert_eq!(updated["instance"]["name"], json!("新名字"));
    assert_eq!(updated["instance"]["stop_command"], json!("^C"));
    assert_eq!(updated["instance"]["line_ending"], json!("\r\n"));

    // 重新读一遍：确认是落盘了，不是只在返回值里对
    let got = client.call_ok(3, "instance.get", json!({ "id": id })).await;
    assert_eq!(got["instance"]["stop_command"], json!("^C"));
    assert_eq!(got["instance"]["line_ending"], json!("\r\n"));
    assert!(
        got["lint"].as_array().unwrap().is_empty(),
        "配齐了就不该有告警: {}",
        got["lint"]
    );

    // 只带 id 的补丁 = 没有改动，也不该报错
    let untouched = client
        .call_ok(4, "instance.update", json!({ "id": id }))
        .await;
    assert_eq!(untouched["changed"], json!(false));

    h.shutdown().await;
}

/// 启动 → 状态里看得见 pid → 停止 → 阶段回到已停止。
#[tokio::test]
async fn instance_lifecycle_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;
    let id = spawn_sleeper(&mut client, 1, "生命周期").await;

    // 启动
    let started = client
        .call_ok(2, "instance.start", json!({ "id": id }))
        .await;
    assert_eq!(started["run"]["phase"], json!("starting"));
    let pid = started["run"]["pid"].as_u64().expect("应报出 pid");
    assert!(pid > 0);

    // 状态：真的在跑
    let status = client
        .call_ok(3, "instance.status", json!({ "id": id }))
        .await;
    assert_eq!(status["status"]["phase"], json!("starting"));
    assert_eq!(status["status"]["process_managed"], json!(true));
    assert_eq!(status["status"]["pid"], json!(pid));

    // 起来之后再启动一次 → 稳定错误码
    let again = client.call(4, "instance.start", json!({ "id": id })).await;
    assert_eq!(again["error"]["code"], json!("instance_already_running"));

    // 停止（停止命令是 ^C → SIGINT）
    let stopped = client
        .call_ok(5, "instance.stop", json!({ "id": id }))
        .await;
    assert_eq!(stopped["stopping"], json!(true));

    // 等它真的收尾
    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    loop {
        let status = client
            .call_ok(6, "instance.status", json!({ "id": id }))
            .await;
        if status["status"]["phase"] == json!("stopped") {
            assert!(status["status"]["pid"].is_null(), "停了就不该再报 pid");
            assert!(
                !status["status"]["exit_code"].is_null(),
                "应当记下退出码: {status}"
            );
            break;
        }
        assert!(std::time::Instant::now() < deadline, "等停止超时: {status}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    // 没在跑的时候停 → 稳定错误码
    let idle = client.call(7, "instance.stop", json!({ "id": id })).await;
    assert_eq!(idle["error"]["code"], json!("instance_not_running"));

    h.shutdown().await;
}

/// 表单模式（运行环境 + 服务端 jar + 最大内存 + JVM 参数）真的能起来。
///
/// 摆一个假的 JDK：那个 `java` 是个脚本，把收到的参数写进文件 —— 于是这条用例
/// 验的是**整条链路**（元数据 → 拼命令 → shell → PTY），而不只是「拼出来的
/// 字符串长得对」。
#[tokio::test]
async fn instance_form_mode_composes_and_runs_the_command() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;
    let data_dir = h.instance_dir().to_path_buf();

    // 1) 假 JDK：`bin/java` 记下参数、打印就绪标记、赖着不走
    let env_id = "zulu-jdk-21-linux-x64";
    let args_file = data_dir.join("java-args.txt");
    let java = data_dir
        .join("runtimes")
        .join(env_id)
        .join("zulu21")
        .join("bin")
        .join("java");
    std::fs::create_dir_all(java.parent().unwrap()).unwrap();
    std::fs::write(
        &java,
        format!(
            "#!/bin/sh\nprintf '%s' \"$*\" > {}\nprintf 'Done (1.000s)! For help, type \"help\"\\n'\nsleep 300\n",
            args_file.display()
        ),
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&java, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    std::fs::create_dir_all(data_dir.join("config").join("runtimes")).unwrap();
    std::fs::write(
        data_dir
            .join("config")
            .join("runtimes")
            .join(format!("{env_id}.json")),
        serde_json::to_string_pretty(&json!({
            "id": env_id,
            "vendor": "zulu",
            "package_type": "jdk",
            "version": "21",
            "version_name": "21.0.12.1",
            "vendor_version": "21.52.203",
            "os": "linux",
            "arch": "x64",
            "archive_type": "tar.gz",
            "package_uuid": "uuid",
            "file_name": "zulu.tar.gz",
            "url": "https://cdn.azul.com/zulu/bin/zulu.tar.gz",
            "sha256": null,
            "md5": null,
            "size": null,
            "support_term": null,
            "build_date": null,
            "state": "installed",
            "stage": null,
            "error": null,
            "task_id": null,
            "home": "zulu21",
            "binary": "zulu21/bin/java",
            "created_at_ms": 1,
            "installed_at_ms": 1,
            "updated_at_ms": 1
        }))
        .unwrap(),
    )
    .unwrap();

    // 2) 表单模式的实例。jar 还没放进去 → 暂时给不出命令，状态里提醒
    let created = client
        .call_ok(
            1,
            "instance.create",
            json!({
                "name": "表单服",
                "manual_command": false,
                "runtime_env_id": env_id,
                "server_file": "server.jar",
                "max_memory": 1024,
                "custom_jvm_args": "-Dfoo=bar",
                "stop_command": "^C"
            }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    assert_eq!(created["instance"]["manual_command"], json!(false));
    assert!(
        created["instance"]["launch_command"].is_null(),
        "jar 还没放进去，这时不该给出命令: {created}"
    );
    let status = client
        .call_ok(2, "instance.status", json!({ "id": id }))
        .await;
    assert!(
        status["status"]["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|w| w.as_str().unwrap().contains("没有 `server.jar`")),
        "缺 jar 要在状态里说: {}",
        status["status"]["warnings"]
    );

    // 放上 jar → daemon 现拼出一条生效命令
    std::fs::write(
        data_dir.join("instances").join(&id).join("server.jar"),
        b"jar",
    )
    .unwrap();
    let got = client.call_ok(3, "instance.get", json!({ "id": id })).await;
    let launch = got["instance"]["launch_command"]
        .as_str()
        .expect("应给出生效命令")
        .to_string();
    assert_eq!(
        launch,
        format!(
            "{} -Xmx1024M -Dfoo=bar -jar server.jar nogui",
            java.display()
        )
    );

    // 3) 启动：假 java 收到的参数就是那条命令的参数（说明真跑起来了、引号也没乱）
    let started = client
        .call_ok(4, "instance.start", json!({ "id": id }))
        .await;
    assert_eq!(started["instance"]["launch_command"], json!(launch));
    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    while !args_file.exists() {
        assert!(std::time::Instant::now() < deadline, "等假 java 起来超时");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_eq!(
        std::fs::read_to_string(&args_file).unwrap(),
        "-Xmx1024M -Dfoo=bar -jar server.jar nogui"
    );

    // 它打印了 `Done (` → 阶段自己走到 running（输出确实来自那个脚本）
    loop {
        let status = client
            .call_ok(5, "instance.status", json!({ "id": id }))
            .await;
        if status["status"]["phase"] == json!("running") {
            break;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "等 running 超时: {status}"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    // 4) 环境被删掉（用户在运行环境页里卸了）→ 重启时给出稳定错误码
    client
        .call_ok(6, "instance.stop", json!({ "id": id }))
        .await;
    std::fs::remove_file(
        data_dir
            .join("config")
            .join("runtimes")
            .join(format!("{env_id}.json")),
    )
    .unwrap();
    let refused = client.call(7, "instance.start", json!({ "id": id })).await;
    assert_eq!(
        refused["error"]["code"],
        json!("instance_runtime_missing"),
        "{refused}"
    );

    h.shutdown().await;
}

/// 主机终端：`/shell` 起来的是一条真 shell —— 输入能回显、状态能查、能重启。
#[tokio::test]
async fn host_shell_stream_round_trip() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;

    let (mut pty, _) = tokio_tungstenite::connect_async(h.shell_url())
        .await
        .expect("主机终端应能连上");

    // 1) 历史帧 + 当前状态：第一条连接就会把 shell 拉起来
    let state = read_pty_history(&mut pty).await;
    assert_eq!(state["phase"], json!("running"), "状态: {state}");
    assert!(state["pid"].is_u64(), "跑起来就该有 pid: {state}");

    // 2) 输入能到 PTY（tty 会回显，所以一定能读回自己敲的字）
    pty.send(Message::Binary(b"echo shell-round-trip\n".to_vec().into()))
        .await
        .expect("发送输入失败");
    let mut echoed = String::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !echoed.contains("shell-round-trip") {
        let frame = tokio::time::timeout_at(deadline, pty.next())
            .await
            .expect("等回显超时")
            .expect("连接不该断")
            .expect("帧应合法");
        if let Message::Binary(data) = frame {
            echoed.push_str(&String::from_utf8_lossy(&data));
        }
    }

    // 3) `shell.status` 与控制台流看到的是同一个会话
    let status = client.call_ok(2, "shell.status", json!({})).await;
    assert_eq!(status["phase"], json!("running"), "状态: {status}");
    let first_pid = status["pid"].clone();

    // 4) 重启换一个进程，状态仍是 running
    client.call_ok(3, "shell.restart", json!({})).await;
    let after = client.call_ok(4, "shell.status", json!({})).await;
    assert_eq!(after["phase"], json!("running"), "重启后状态: {after}");
    assert_ne!(after["pid"], first_pid, "重启应当换一个进程: {after}");

    h.shutdown().await;
}

/// 读一段 PTY 历史，返回 `history_end` 里的 state。
///
/// 与控制台测试里的内联循环同构，抽出来给主机终端复用。
async fn read_pty_history(pty: &mut Ws) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    loop {
        let frame = tokio::time::timeout_at(deadline, pty.next())
            .await
            .expect("读历史超时")
            .expect("连接不该断")
            .expect("帧应合法");
        match frame {
            Message::Text(text) => {
                let value: Value = serde_json::from_str(text.as_str()).expect("控制帧应是 JSON");
                match value["type"].as_str() {
                    Some("history_begin") => {}
                    Some("history_end") => return value["state"].clone(),
                    other => panic!("历史阶段不该出现 {other:?}"),
                }
            }
            Message::Binary(_) => {}
            _ => {}
        }
    }
}

/// 控制台流：历史快照 → 实时输出 → 输入回显，全程走 `/pty/{id}`。
#[tokio::test]
async fn console_pty_stream_round_trip() {
    let h = Harness::start(|_| {}).await;
    let (mut client, _) = Client::connect(&h.ws_url()).await;
    let id = spawn_sleeper(&mut client, 1, "控制台").await;

    // 先起来，再连控制台 —— 连上来就该看到「之前已经打印过的东西」
    client
        .call_ok(2, "instance.start", json!({ "id": id }))
        .await;
    tokio::time::sleep(Duration::from_millis(300)).await;

    let (mut pty, _) = tokio_tungstenite::connect_async(h.pty_url(&id))
        .await
        .expect("PTY 应能连上");

    // 1) 读历史：begin → [二进制] → end，end 里带当前状态
    let mut history = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    let state = loop {
        let frame = tokio::time::timeout_at(deadline, pty.next())
            .await
            .expect("读历史超时")
            .expect("连接不该断")
            .expect("帧应合法");
        match frame {
            Message::Text(text) => {
                let value: Value = serde_json::from_str(text.as_str()).expect("控制帧应是 JSON");
                match value["type"].as_str() {
                    Some("history_begin") => {}
                    Some("history_end") => break value["state"].clone(),
                    other => panic!("历史阶段不该出现 {other:?}"),
                }
            }
            Message::Binary(data) => history.extend_from_slice(&data),
            _ => {}
        }
    };
    let history = String::from_utf8_lossy(&history).to_string();
    assert!(
        history.contains("hello-from-server"),
        "历史里应有服务端输出: {history:?}"
    );
    assert!(
        history.contains("[EdgeCube] 启动"),
        "历史里应有启动提示: {history:?}"
    );
    assert_eq!(state["phase"], json!("starting"), "状态: {state}");

    // 2) 键盘输入要能到 PTY（tty 默认回显，所以能读回来）
    pty.send(Message::Binary(b"ping-round-trip\n".to_vec().into()))
        .await
        .expect("发送输入失败");
    let mut echoed = String::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !echoed.contains("ping-round-trip") {
        let frame = tokio::time::timeout_at(deadline, pty.next())
            .await
            .expect("等回显超时")
            .expect("连接不该断")
            .expect("帧应合法");
        if let Message::Binary(data) = frame {
            echoed.push_str(&String::from_utf8_lossy(&data));
        }
    }

    // 3) resize 控制帧不该把连接弄断
    pty.send(Message::Text(
        json!({ "resize": { "cols": 120, "rows": 40 } })
            .to_string()
            .into(),
    ))
    .await
    .expect("发送 resize 失败");
    let after_resize = client
        .call_ok(3, "instance.status", json!({ "id": id }))
        .await;
    assert!(
        after_resize["status"]["pid"].as_u64().is_some(),
        "resize 之后进程照旧在跑: {after_resize}"
    );

    // 4) 收尾：杀掉，控制台应当收到 exit 控制帧
    client
        .call_ok(4, "instance.kill", json!({ "id": id }))
        .await;
    let mut saw_exit = false;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !saw_exit {
        match tokio::time::timeout_at(deadline, pty.next()).await {
            Ok(Some(Ok(Message::Text(text)))) => {
                if let Ok(value) = serde_json::from_str::<Value>(text.as_str())
                    && value["type"] == json!("exit")
                {
                    assert_eq!(value["phase"], json!("stopped"), "强杀算主动停: {value}");
                    saw_exit = true;
                }
            }
            Ok(Some(Ok(_))) => {}
            _ => break,
        }
    }
    assert!(saw_exit, "进程退出后控制台应收到 exit 控制帧");

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 玩家管理
// ---------------------------------------------------------------------------

/// 在线玩家由 daemon 从控制台输出里解析（前端不解析日志），名单文件由 daemon
/// 直接读盘，发命令走 `instance.console.write` —— 一条连接把整条路走一遍。
#[tokio::test]
async fn instance_players_over_ws() {
    /// 等到名单变成 `want` 的那条 `instance.players` 事件。
    async fn wait_players(client: &mut Client, want: Value) -> Value {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
        loop {
            let event = tokio::time::timeout_at(deadline, client.wait_event("instance.players"))
                .await
                .unwrap_or_else(|_| panic!("等 {want} 超时"));
            if event["data"]["players"] == want {
                assert_eq!(
                    event["data"]["count"],
                    json!(want.as_array().unwrap().len())
                );
                return event;
            }
        }
    }

    let h = Harness::start(|_| {}).await;
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for wanted in [
        "instance.players.online",
        "instance.players.whitelist",
        "instance.players.bans",
        "instance.console.write",
    ] {
        assert!(
            methods.contains(&wanted.to_string()),
            "缺少 {wanted}: {methods:?}"
        );
    }

    // 假服务端：先报两个玩家上线，然后收一行命令回一条 `list` 响应
    let created = client
        .call_ok(
            1,
            "instance.create",
            json!({
                "name": "玩家",
                "startup_command": "printf 'Steve[/127.0.0.1:5000] logged in with entity id 1\\nAlex 加入了游戏\\n'; \
                                    while IFS= read -r line; do \
                                      printf 'CMD %s\\n' \"$line\"; \
                                      printf 'There are 1 of a max of 20 players online: Alex\\n'; \
                                    done",
                "stop_command": "^C",
                "compat_mode": true,
            }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    let dir = h.instance_dir().join("instances").join(&id);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("whitelist.json"),
        r#"[{"name":"Steve","uuid":"u1"}]"#,
    )
    .unwrap();
    std::fs::write(dir.join("white-list.txt"), "TxtOnly\n").unwrap();

    // 1) 名单文件：JSON 优先；打标签用的名字是小写
    let whitelist = client
        .call_ok(2, "instance.players.whitelist", json!({ "id": id }))
        .await;
    assert_eq!(
        whitelist["entries"],
        json!([{ "name": "Steve", "uuid": "u1" }])
    );
    assert_eq!(whitelist["names"], json!(["steve"]));

    // 2) 没在跑：空名单，发命令报 instance_not_running
    let before = client
        .call_ok(3, "instance.players.online", json!({ "id": id }))
        .await;
    assert_eq!(before["players"], json!([]));
    let refused = client
        .call(
            4,
            "instance.console.write",
            json!({ "id": id, "data": "list\n" }),
        )
        .await;
    assert_eq!(refused["error"]["code"], json!("instance_not_running"));

    // 3) 起进程：输出里的两条加入都要被认出来（事件推给订阅者）
    client.subscribe(5, "instance.players").await;
    client
        .send(json!({
            "type": "call", "id": 6, "method": "instance.start",
            "params": { "id": id },
        }))
        .await;
    wait_players(&mut client, json!(["Steve", "Alex"])).await;

    let online = client
        .call_ok(7, "instance.players.online", json!({ "id": id }))
        .await;
    assert_eq!(
        online["players"],
        json!(["Steve", "Alex"]),
        "快照与事件一致"
    );
    let status = client
        .call_ok(8, "instance.status", json!({ "id": id }))
        .await;
    assert_eq!(status["status"]["phase"], json!("running"), "{status}");

    // 4) 发命令：`list` 的响应把名单整份替换掉
    client
        .send(json!({
            "type": "call", "id": 9, "method": "instance.console.write",
            "params": { "id": id, "data": "list\n" },
        }))
        .await;
    wait_players(&mut client, json!(["Alex"])).await;

    // 5) 进程退出：名单清空并推空事件
    client
        .send(json!({
            "type": "call", "id": 10, "method": "instance.kill",
            "params": { "id": id },
        }))
        .await;
    wait_players(&mut client, json!([])).await;

    let after = client
        .call_ok(11, "instance.players.online", json!({ "id": id }))
        .await;
    assert_eq!(after["players"], json!([]));

    h.shutdown().await;
}

/// 控制台路由同样要过鉴权，且不存在的实例不该给个空终端。
#[tokio::test]
async fn console_pty_requires_token_and_a_real_instance() {
    let h = Harness::start(|_| {}).await;

    let (mut client, _) = Client::connect(&h.ws_url()).await;
    let id = spawn_sleeper(&mut client, 1, "鉴权").await;

    // 没令牌 → 升级被拒
    let url = format!("ws://{}/pty/{id}", h.addr);
    assert!(
        tokio_tungstenite::connect_async(url).await.is_err(),
        "没令牌不该连得上控制台"
    );

    // 不存在的实例 → 404
    let url = format!("ws://{}/pty/ffffffffffffffff?token={TOKEN}", h.addr);
    let err = tokio_tungstenite::connect_async(url)
        .await
        .expect_err("不存在的实例应被拒");
    let text = format!("{err:?}");
    assert!(text.contains("404"), "应当是 404: {text}");

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 下载队列：真起服务、把真文件下进真实例目录
// ---------------------------------------------------------------------------

/// 一台只服务一个固定文件的极简 HTTP 服务，返回它的 URL。
///
/// 手搓而不是引测试框架：这里要验的是「走完整 WS 协议提交 → 引擎去下载 →
/// 文件落到实例目录」这条链路，一个固定响应体就够。
///
/// `chunk_delay` 是**分块之间**的等待：响应体分三次发，中间各等一会儿。
///
/// 为什么要分块：引擎的进度回调有两个门 —— 一是只在**读到数据**时触发，
/// 二是同一连接内**最快 250ms 一次**（`stream_to_file` 里的 `update_interval`）。
/// 把整个响应体一口气发完的话，整个下载期间可能一个回调都不触发，我们这边
/// 能看到的只有引擎里的初始零值（`total_size` 为空）。
/// 按 300ms 分块发，就能保证「进行中且带总大小」的进度帧一定出现。
async fn serve_one_file(body: &'static [u8], chunk_delay: Duration) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("应当能监听回环端口");
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        while let Ok((mut socket, _)) = listener.accept().await {
            tokio::spawn(async move {
                let mut scratch = [0u8; 2048];
                let _ = socket.read(&mut scratch).await;
                let head = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n\
                     Content-Length: {}\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n",
                    body.len()
                );
                let _ = socket.write_all(head.as_bytes()).await;

                let chunk_size = (body.len() / 3).max(1);
                for (index, part) in body.chunks(chunk_size).enumerate() {
                    if index > 0 && !chunk_delay.is_zero() {
                        tokio::time::sleep(chunk_delay).await;
                    }
                    let _ = socket.write_all(part).await;
                    let _ = socket.flush().await;
                }
            });
        }
    });

    format!("http://{addr}/pack.bin")
}

/// 等一条「属于某任务、且已经知道总大小」的进度事件。
///
/// 要挑「带总大小」的帧：下载刚起步时引擎还不知道内容长度（那一帧
/// `total_size` 是空的、`connections` 是 0），而前端画百分比要的正是有总大小的帧。
async fn wait_sized_progress(client: &mut Client, task_id: &str) -> Value {
    for _ in 0..300 {
        let msg = client.next_json().await.expect("连接不该断");
        if msg["type"] != json!("event") || msg["topic"] != json!("download.progress") {
            continue;
        }
        if msg["data"]["id"] == json!(task_id) && msg["data"]["total_size"].as_u64().is_some() {
            return msg;
        }
    }
    panic!("等任务 {task_id} 带总大小的进度事件超时");
}

/// 等一条「属于某任务、且状态正好是 `expected`」的状态事件。
async fn wait_task_state(client: &mut Client, task_id: &str, expected: &str) -> Value {
    for _ in 0..300 {
        let msg = client.next_json().await.expect("连接不该断");
        if msg["type"] != json!("event") || msg["topic"] != json!("download.state") {
            continue;
        }
        if msg["data"]["id"] == json!(task_id) && msg["data"]["state"] == json!(expected) {
            return msg;
        }
    }
    panic!("等任务 {task_id} 变成 {expected} 的状态事件超时");
}

/// 本机是否把回环也塞进了代理。
///
/// gosh-dl 的 reqwest 客户端会读环境里的 `HTTP_PROXY`，daemon 这边改不了。
/// 真配了代理又没排除回环时，下面这条用例没法跑 —— 跳过并说明原因，
/// 好过让环境问题冒充成功能坏了。
fn loopback_is_proxied() -> bool {
    let proxy = std::env::var("HTTP_PROXY")
        .or_else(|_| std::env::var("http_proxy"))
        .unwrap_or_default();
    if proxy.trim().is_empty() {
        return false;
    }
    let no_proxy = std::env::var("NO_PROXY")
        .or_else(|_| std::env::var("no_proxy"))
        .unwrap_or_default();
    !no_proxy
        .split(',')
        .any(|item| matches!(item.trim(), "127.0.0.1" | "localhost" | "::1" | "*"))
}

#[tokio::test]
async fn download_queue_over_ws() {
    if loopback_is_proxied() {
        eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
        return;
    }

    // 18 字节，会被 `serve_one_file` 分三次发（每次 6 字节）
    const BODY: &[u8] = b"edgecube-integration";
    // 推送间隔压到 50ms，好让「进行中」那几帧真的落在这个测试的窗口里
    let h = Harness::start(|c| {
        c.modules.config.insert(
            "download".into(),
            toml::from_str("progress_interval_ms = 50").expect("下载队列配置应能解析"),
        );
    })
    .await;
    let data_dir = h.instance_dir().to_path_buf();
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // 三个方法都挂上来了，两条事件主题也声明了
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in ["download.add", "download.status", "download.list"] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(
        topics.contains(&"download.progress".to_string()),
        "{topics:?}"
    );
    assert!(topics.contains(&"download.state".to_string()), "{topics:?}");

    // 建一个真实例，拿它的 id
    let created = client
        .call_ok(1, "instance.create", json!({ "name": "下载服" }))
        .await;
    let instance_id = created["instance"]["id"].as_str().unwrap().to_string();

    // 服务端每答一次先等 400ms：把下载拖慢到跨过好几次推送间隔
    // 每块之间等 300ms：跨过引擎 250ms 的进度上报间隔，保证抓得到带总大小的进度帧
    let url = serve_one_file(BODY, Duration::from_millis(300)).await;

    // 先订阅再提交 —— 这样事件一定是订阅之后产生的（订阅之前的不补发）
    let sub = client.subscribe(2, "download.progress").await;
    assert_eq!(sub["ok"], json!(true), "{sub}");
    let sub = client.subscribe(3, "download.state").await;
    assert_eq!(sub["ok"], json!(true), "{sub}");

    // 1) 正常提交
    let added = client
        .call_ok(
            4,
            "download.add",
            json!({
                "url": url,
                "instance_id": instance_id,
                "path": "downloads",
                "filename": "pack.bin",
            }),
        )
        .await;
    let task_id = added["task"]["id"].as_str().unwrap().to_string();
    assert_eq!(added["task"]["target"], json!("downloads/pack.bin"));
    assert_eq!(added["task"]["instance_id"], json!(instance_id));
    assert_eq!(added["task"]["checksum"], json!(null));
    assert!(
        task_id.len() == 36,
        "任务 ID 应当是完整 UUID（不是 16 位 GID）: {task_id}"
    );

    // 2) 进度事件：下载还在进行时就会推，且带得动画百分比所需的总大小
    let progress = wait_sized_progress(&mut client, &task_id).await;
    assert_eq!(progress["data"]["id"], json!(task_id));
    let state = progress["data"]["state"].as_str().unwrap_or_default();
    assert!(
        ["queued", "connecting", "downloading"].contains(&state),
        "这一帧应当还在进行中（不是终态）: {progress}"
    );
    assert_eq!(progress["data"]["total_size"], json!(BODY.len() as u64));
    assert_eq!(progress["data"]["target"], json!("downloads/pack.bin"));
    assert_eq!(progress["data"]["instance_id"], json!(instance_id));

    // 3) 状态事件：终态会推一条（下载极快时中间态可能被跳过，所以只钉终态）
    let finished = wait_task_state(&mut client, &task_id, "completed").await;
    assert!(finished["seq"].as_u64().unwrap() >= 1, "事件要有全局序号");
    assert_eq!(finished["data"]["finished_at_ms"].is_null(), json!(false));

    // 4) 快照与事件说的是同一件事：再查一次状态
    let status = client
        .call_ok(5, "download.status", json!({ "id": task_id }))
        .await;
    assert_eq!(status["task"]["state"], json!("completed"), "{status}");
    assert_eq!(status["task"]["total_size"], json!(BODY.len() as u64));

    // 真的落到了实例目录里，字节一致
    let written = data_dir
        .join("instances")
        .join(&instance_id)
        .join("downloads")
        .join("pack.bin");
    assert_eq!(
        std::fs::read(&written).expect("文件应当落在实例目录里"),
        BODY
    );

    // 3) 列表
    let listed = client.call_ok(6, "download.list", json!({})).await;
    assert_eq!(listed["count"], json!(1));
    assert_eq!(listed["tasks"][0]["id"], json!(task_id));

    // 4) 各类拒绝：各有各的错误码，前端按码分支
    let cases: [(Value, &str); 5] = [
        (
            json!({ "url": url, "instance_id": instance_id, "path": "../outside" }),
            "download_path_invalid",
        ),
        (
            json!({ "url": url, "instance_id": instance_id, "path": "/etc" }),
            "download_path_invalid",
        ),
        (
            json!({ "url": url, "instance_id": "nope000000000000" }),
            "download_instance_not_found",
        ),
        (
            json!({
                "url": url, "instance_id": instance_id,
                "path": "downloads", "filename": "pack.bin",
            }),
            "download_target_exists",
        ),
        (
            json!({ "url": "ftp://example.com/x.bin", "instance_id": instance_id }),
            "download_url_invalid",
        ),
    ];
    for (index, (params, code)) in cases.into_iter().enumerate() {
        let msg = client.call(10 + index as i64, "download.add", params).await;
        assert_eq!(msg["ok"], json!(false), "应当失败: {msg}");
        assert_eq!(msg["error"]["code"], json!(code), "{msg}");
    }

    // 校验值：长度不对、两个都给，都要在提交时就被拒
    let bad_checksums: [Value; 2] = [
        json!({ "url": url, "instance_id": instance_id, "filename": "a.bin", "md5": "abc" }),
        json!({
            "url": url, "instance_id": instance_id, "filename": "a.bin",
            "md5": "a".repeat(32), "sha256": "b".repeat(64),
        }),
    ];
    for (index, params) in bad_checksums.into_iter().enumerate() {
        let msg = client.call(20 + index as i64, "download.add", params).await;
        assert_eq!(
            msg["error"]["code"],
            json!("download_checksum_invalid"),
            "{msg}"
        );
    }

    // 查不存在的任务
    let msg = client
        .call(
            30,
            "download.status",
            json!({ "id": "00000000-0000-0000-0000-000000000000" }),
        )
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("download_task_not_found"),
        "{msg}"
    );

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 服务端目录：类型表 + 版本列表 + 下载计划
// ---------------------------------------------------------------------------

/// 上游不通（离线 / 网络被挡）时，需要联网的那几段就跳过 —— 那不是功能坏了。
fn upstream_is_down(msg: &Value) -> bool {
    msg["error"]["code"] == json!("mcserver_upstream_error")
}

#[tokio::test]
async fn runtime_module_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // 四个方法 + 一个事件主题都挂上来了。
    // 注意**没有** `runtime.install`：装环境现在只有 `task.submit("runtime-install")`
    // 一条路（见 `task_flows_cover_both_builtin_workflows`）。
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in [
        "runtime.catalog",
        "runtime.versions",
        "runtime.list",
        "runtime.delete",
    ] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }

    // ── 厂商表（纯常量，不联网）──
    let catalog = client.call_ok(1, "runtime.catalog", json!({})).await;
    assert_eq!(catalog["default_provider"], json!("zulu"));
    assert_eq!(catalog["default_package_type"], json!("jdk"));
    assert_eq!(catalog["providers"][0]["id"], json!("zulu"));
    assert!(
        catalog["host"].is_object() || catalog["host"].is_null(),
        "本机平台要么给、要么说明不支持：{catalog}"
    );

    // ── 空列表 ──
    let list = client.call_ok(2, "runtime.list", json!({})).await;
    assert_eq!(list["environments"], json!([]));
    assert_eq!(list["count"], json!(0));
    assert!(
        list["dir"]
            .as_str()
            .is_some_and(|dir| dir.ends_with("runtimes")),
        "dir 应当指到 <数据根>/runtimes 这一层：{list}"
    );

    // ── 删一个不存在的 id：参数合法但东西不在 ──
    let msg = client
        .call(
            3,
            "runtime.delete",
            json!({ "id": "zulu-jdk-21-linux-x64" }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("runtime_not_found"), "{msg}");

    // 非法 id（会变成路径）在参数校验就被拒
    let msg = client
        .call(4, "runtime.delete", json!({ "id": "../escape" }))
        .await;
    assert_eq!(msg["error"]["code"], json!("invalid_params"), "{msg}");

    // ── 缺版本号：装环境走任务，所以这里是 `task.submit` 在 `build` 阶段就拒 ──
    let msg = client
        .call(5, "task.submit", json!({ "flow": "runtime-install" }))
        .await;
    assert_eq!(msg["ok"], json!(false), "{msg}");
    assert_eq!(msg["error"]["code"], json!("task_invalid_params"), "{msg}");
    assert!(
        msg["error"]["message"]
            .as_str()
            .is_some_and(|m| m.contains("version")),
        "要告诉调用方缺的是哪个参数：{msg}"
    );

    // ── 真实上游：大版本列表应当是降序的（可选，离线环境跳过）──
    let versions = client.call(7, "runtime.versions", json!({})).await;
    if versions["ok"] != json!(true) {
        assert!(
            upstream_is_down(&versions)
                || versions["error"]["code"] == json!("runtime_upstream_error"),
            "上游失败应当是 upstream_error：{versions}"
        );
        eprintln!("跳过需要上游的那段（拿不到 Azul 版本清单）: {versions}");
        h.shutdown().await;
        return;
    }
    let majors: Vec<u32> = versions["result"]["versions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| {
            item["version"]
                .as_str()
                .unwrap()
                .parse::<u32>()
                .expect("Zulu 的版本就是大版本号")
        })
        .collect();
    assert!(!majors.is_empty(), "版本列表不该是空的");
    let mut sorted = majors.clone();
    sorted.sort_unstable_by(|a, b| b.cmp(a));
    assert_eq!(majors, sorted, "大版本应当降序（新的在前）: {majors:?}");
    // 默认只给最新那个（`all = false`）—— 前端据此决定要不要显示「历史版本」
    assert_eq!(versions["result"]["all"], json!(false));
    // 每一项都带展示用的 label / subtitle（前端零硬编码）
    assert!(
        versions["result"]["versions"][0]["label"]
            .as_str()
            .is_some_and(|label| label.starts_with("Java ")),
        "Zulu 的版本主行应当是 `Java 21` 这种：{versions}"
    );
    // 本机平台要能装（CI 与开发机都是 linux x64 / aarch64）
    assert!(
        versions["result"]["os"].is_string() && versions["result"]["arch"].is_string(),
        "应当带本机平台：{versions}"
    );

    h.shutdown().await;
}

/// frp 这条链路的两半：**环境**里多了 frp 这个厂商（版本走 GitHub），
/// **FRP 侧**能列出可用的 frpc 运行环境并记住选了哪个。
///
/// 「游戏实例连带启动哪条隧道」只剩一个引用（`frp_tunnel_id`）——
/// `frp_runtime_id` / `frp_enabled` 是旧模型的字段，**现在必须被拒**。
#[tokio::test]
async fn frp_is_offered_and_runtimes_are_listable() {
    let h = Harness::start(|_| {}).await;
    let (mut c, hello) = Client::connect(&h.ws_url()).await;

    // 运行态的主题挂上来了（前端靠它实时更新隧道卡片）
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(topics.contains(&"frp.run".to_string()), "{topics:?}");
    // 旧模型那个「实例的 frpc 状态」主题已经退场
    assert!(!topics.contains(&"instance.frp".to_string()), "{topics:?}");

    // ── 运行环境：frp 厂商在册，前端零硬编码靠它渲染 ──
    let catalog = c.call_ok(1, "runtime.catalog", json!({})).await;
    let providers: Vec<&str> = catalog["providers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap())
        .collect();
    assert_eq!(providers, vec!["zulu", "frp"], "{catalog}");
    let frp = catalog["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!("frp"))
        .expect("frp 应当在厂商表里");
    assert_eq!(frp["package_types"], json!(["frpc"]));
    // frp 的版本号本身就是完整的说法，没有 `Java ` 那种前缀
    assert_eq!(frp["version_prefix"], json!(""));
    assert_eq!(frp["homepage"], json!("https://github.com/fatedier/frp"));

    // ── 一个 frpc 都没装：空清单 + 没选中（界面给「先去装一个」）──
    let runtimes = c.call_ok(2, "frp.runtimes", json!({})).await;
    assert_eq!(runtimes["runtimes"], json!([]), "{runtimes}");
    assert_eq!(runtimes["selected"], json!(null), "{runtimes}");

    // ── 设置：选哪个 frpc 跑隧道，写了要读得回来 ──
    c.call_ok(
        3,
        "frp.settings.save",
        json!({ "frpc_runtime_id": "frp-frpc-0.71.0-linux-x64" }),
    )
    .await;
    let runtimes = c.call_ok(4, "frp.runtimes", json!({})).await;
    // 选的那个没装 → 回显的是「生效的那个」（这里一个都没有，所以是 null）
    assert_eq!(runtimes["selected"], json!(null), "{runtimes}");

    // ── 实例：只剩一个「连带启动哪条隧道」的引用 ──
    let created = c
        .call_ok(
            5,
            "instance.create",
            json!({ "name": "隧道测试服", "startup_command": "java -jar server.jar nogui" }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();

    let updated = c
        .call_ok(
            6,
            "instance.update",
            json!({ "id": id, "frp_tunnel_id": "abc123" }),
        )
        .await;
    // **线上是 snake_case**（落盘是 camelCase）—— 别搞反
    assert_eq!(updated["instance"]["frp_tunnel_id"], json!("abc123"));

    // 旧模型的另外两个字段已经不认了（加/减字段都要过 UPDATABLE_FIELDS）
    for stale in ["frp_runtime_id", "frp_enabled"] {
        let msg = c
            .call(7, "instance.update", json!({ "id": id, stale: "x" }))
            .await;
        assert_eq!(
            msg["error"]["code"],
            json!("invalid_params"),
            "{stale}: {msg}"
        );
    }

    // 清空也是同一套语义（`null` = 清掉）
    let cleared = c
        .call_ok(
            8,
            "instance.update",
            json!({ "id": id, "frp_tunnel_id": null }),
        )
        .await;
    assert_eq!(cleared["instance"]["frp_tunnel_id"], json!(null));

    // 白名单是硬的：不认识的字段照旧被拒
    let msg = c
        .call(9, "instance.update", json!({ "id": id, "frp_nope": true }))
        .await;
    assert_eq!(msg["error"]["code"], json!("invalid_params"), "{msg}");

    h.shutdown().await;
}

/// 运行态**不在** `instance.status` 里了：一条隧道可能被好几个游戏实例连着，
/// 状态只能有一个来源（`frp.run.*`）。
#[tokio::test]
async fn instance_status_carries_no_frp_block() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let created = c
        .call_ok(1, "instance.create", json!({ "name": "干净的服" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();

    let status = c.call_ok(2, "instance.status", json!({ "id": id })).await;
    assert!(
        status["status"].get("frp").is_none(),
        "instance.status 不该再有 frp 子对象：{status}"
    );

    // FRP 侧的运行态是另一条路，空的时候是空清单
    let runs = c.call_ok(3, "frp.run.list", json!({})).await;
    assert_eq!(runs["runs"], json!([]), "{runs}");

    h.shutdown().await;
}

#[tokio::test]
async fn mcserver_catalog_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // 四个方法都挂上来了
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in [
        "mcserver.types",
        "mcserver.versions",
        "mcserver.loaders",
        "mcserver.plan",
    ] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }

    // ── 不需要网络的部分 ──

    // 1) 类型表：分类与类型，字段齐全（前端零硬编码要靠它）
    let types = client.call_ok(1, "mcserver.types", json!({})).await;
    let categories = types["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 4, "{types}");
    let list = types["types"].as_array().unwrap();
    assert_eq!(list.len(), 9, "{types}");
    let find = |id: &str| {
        list.iter()
            .find(|entry| entry["id"] == json!(id))
            .unwrap_or_else(|| panic!("类型表里应当有 {id}: {types}"))
    };
    let paper = find("paper");
    assert_eq!(paper["file_name"], json!("server.jar"));
    assert_eq!(
        paper["startup_command"],
        json!("java -jar server.jar nogui")
    );
    assert_eq!(paper["checksum"], json!("sha256"));
    assert_eq!(paper["needs_loader"], json!(false));
    // 代理不带 nogui（代理没有 GUI，带了可能被当成非法参数退出）
    assert_eq!(
        find("velocity")["startup_command"],
        json!("java -jar velocity.jar")
    );
    // 只有 Fabric 需要选加载器，只有 BungeeCord 没有版本可选
    assert_eq!(find("fabric")["needs_loader"], json!(true));
    assert_eq!(find("bungeecord")["needs_version"], json!(false));
    // Folia 是 PaperMC 的另一个官方 project，跟 paper 一起排在插件分类最前
    let folia = find("folia");
    assert_eq!(folia["category"], json!("plugin"));
    assert_eq!(folia["file_name"], json!("server.jar"));
    assert_eq!(
        folia["startup_command"],
        json!("java -jar server.jar nogui")
    );
    assert_eq!(folia["checksum"], json!("sha256"));
    let plugin = categories
        .iter()
        .find(|category| category["id"] == json!("plugin"))
        .expect("应当有插件分类");
    assert_eq!(
        plugin["types"],
        json!(["paper", "folia", "purpur", "leaf", "leaves"]),
        "插件分类的展示顺序"
    );

    // 2) 参数类错误码（一样不需要网络）
    let msg = client
        .call(2, "mcserver.versions", json!({ "type": "不存在的类型" }))
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("mcserver_type_not_found"),
        "{msg}"
    );

    let msg = client
        .call(3, "mcserver.plan", json!({ "type": "paper" }))
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("mcserver_version_required"),
        "{msg}"
    );

    let msg = client
        .call(
            4,
            "mcserver.loaders",
            json!({ "type": "paper", "mc_version": "1.21.8" }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("mcserver_no_loaders"), "{msg}");

    // ── 需要上游的部分 ──

    // 3) Paper 版本列表
    let versions = client
        .call(5, "mcserver.versions", json!({ "type": "paper" }))
        .await;
    if versions["ok"] != json!(true) {
        assert!(
            upstream_is_down(&versions),
            "上游失败应当是 upstream_error: {versions}"
        );
        eprintln!("跳过需要上游的那几段（拿不到 paper 版本列表）: {versions}");
        h.shutdown().await;
        return;
    }
    let versions = versions["result"].clone();
    let list = versions["versions"]
        .as_array()
        .expect("versions 应当是数组");
    assert!(!list.is_empty(), "paper 版本列表不该是空的");
    assert_eq!(versions["needs_version"], json!(true));
    let newest = list[0].as_str().expect("版本应当是字符串").to_string();
    // 预发布版不该出现
    assert!(
        !newest.to_ascii_lowercase().contains("rc"),
        "列表里不该有 rc 版: {newest}"
    );

    // 4) 计划：下载地址 + 校验 + 文件名 + 启动命令
    let plan = client
        .call_ok(
            6,
            "mcserver.plan",
            json!({ "type": "paper", "version": newest }),
        )
        .await;
    assert_eq!(plan["type"], json!("paper"));
    assert_eq!(plan["version"], json!(newest));
    assert_eq!(plan["file_name"], json!("server.jar"));
    assert_eq!(plan["startup_command"], json!("java -jar server.jar nogui"));
    assert!(
        plan["url"].as_str().unwrap().starts_with("https://"),
        "{plan}"
    );
    // 校验算法直接就是 `download.add` 的参数名
    assert_eq!(plan["checksum"]["algorithm"], json!("sha256"));
    assert_eq!(plan["checksum"]["value"].as_str().unwrap().len(), 64);

    // 5) 版本白名单：瞎传的版本会被拒，而且不该被拼进上游 URL
    let msg = client
        .call(
            7,
            "mcserver.plan",
            json!({ "type": "paper", "version": "../etc/passwd" }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("mcserver_not_found"), "{msg}");
    let msg = client
        .call(
            8,
            "mcserver.plan",
            json!({ "type": "paper", "version": "0.0.1-not-real" }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("mcserver_not_found"), "{msg}");

    // 6) 缓存：同样的版本列表再要一次，结果必须一致（这次走的是缓存）
    let again = client
        .call_ok(9, "mcserver.versions", json!({ "type": "paper" }))
        .await;
    assert_eq!(again["versions"], versions["versions"]);

    // 6.5) Folia：PaperMC v3 的另一个 project，整条链路与 paper 共用 ——
    //      真打一次上游，确认 project 名、产物键与校验都还对得上
    let folia = client
        .call(20, "mcserver.versions", json!({ "type": "folia" }))
        .await;
    if folia["ok"] != json!(true) {
        assert!(
            upstream_is_down(&folia),
            "上游失败应当是 upstream_error: {folia}"
        );
        eprintln!("跳过 Folia 那一段（拿不到 folia 版本列表）: {folia}");
    } else {
        let folia_versions = folia["result"]["versions"]
            .as_array()
            .expect("versions 应当是数组");
        assert!(!folia_versions.is_empty(), "folia 版本列表不该是空的");
        let folia_version = folia_versions[0]
            .as_str()
            .expect("版本应当是字符串")
            .to_string();

        let plan = client
            .call_ok(
                21,
                "mcserver.plan",
                json!({ "type": "folia", "version": folia_version }),
            )
            .await;
        assert_eq!(plan["type"], json!("folia"));
        assert_eq!(plan["type_name"], json!("Folia"));
        assert_eq!(plan["file_name"], json!("server.jar"));
        assert_eq!(plan["startup_command"], json!("java -jar server.jar nogui"));
        assert_eq!(plan["checksum"]["algorithm"], json!("sha256"));
        assert_eq!(plan["checksum"]["value"].as_str().unwrap().len(), 64);
        assert!(
            plan["url"].as_str().unwrap().starts_with("https://"),
            "{plan}"
        );
    }

    // 7) Fabric：本轮唯一需要「加载器版本」的源
    let fabric = client
        .call(10, "mcserver.versions", json!({ "type": "fabric" }))
        .await;
    if fabric["ok"] != json!(true) {
        assert!(upstream_is_down(&fabric), "{fabric}");
        eprintln!("跳过 Fabric 那一段: {fabric}");
        h.shutdown().await;
        return;
    }
    let mc_version = fabric["result"]["versions"]
        .as_array()
        .and_then(|versions| versions.first())
        .and_then(|version| version.as_str())
        .expect("Fabric 应当有版本")
        .to_string();

    // 缺 loader_version → 明确报错，而不是拿个空串去拼 URL
    let msg = client
        .call(
            11,
            "mcserver.plan",
            json!({ "type": "fabric", "version": mc_version }),
        )
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("mcserver_loader_required"),
        "{msg}"
    );

    let loaders = client
        .call(
            12,
            "mcserver.loaders",
            json!({ "type": "fabric", "mc_version": mc_version }),
        )
        .await;
    if loaders["ok"] != json!(true) {
        assert!(upstream_is_down(&loaders), "{loaders}");
        eprintln!("跳过 Fabric 加载器那一段: {loaders}");
        h.shutdown().await;
        return;
    }
    let loader = loaders["result"]["loaders"]
        .as_array()
        .and_then(|loaders| loaders.first())
        .and_then(|loader| loader.as_str())
        .expect("Fabric 应当有加载器版本")
        .to_string();

    let plan = client
        .call_ok(
            13,
            "mcserver.plan",
            json!({ "type": "fabric", "version": mc_version, "loader_version": loader }),
        )
        .await;
    assert_eq!(plan["loader_version"], json!(loader));
    assert!(
        plan["url"].as_str().unwrap().ends_with("/server/jar"),
        "{plan}"
    );
    // Fabric 那个合并 jar 接口不给校验值
    assert_eq!(plan["checksum"], json!(null), "{plan}");

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 模组与插件（mods）
// ---------------------------------------------------------------------------

/// 上游不通时跳过需要联网的那几段（与 [`upstream_is_down`] 同理）。
fn mods_upstream_is_down(msg: &Value) -> bool {
    msg["error"]["code"] == json!("mods_upstream_error")
}

/// 往磁盘上写一个「像模组」的 jar：真的是 zip，里面放一个元数据条目。
///
/// 用真 zip 而不是空文件，是因为列表里的名字 / 版本就来自「开这个 zip 读
/// `fabric.mod.json`」—— 拿假文件测等于什么都没测。
fn write_fake_jar(path: &std::path::Path, entry: &str, body: &str) {
    use std::io::Write;

    std::fs::create_dir_all(path.parent().expect("jar 应当有父目录")).expect("应能建目录");
    let file = std::fs::File::create(path).expect("应能建 jar");
    let mut zip = zip::ZipWriter::new(file);
    zip.start_file(entry, zip::write::SimpleFileOptions::default())
        .expect("应能写入条目");
    zip.write_all(body.as_bytes()).expect("应能写内容");
    zip.finish().expect("应能收尾");
}

#[tokio::test]
async fn mods_module_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut client, hello) = Client::connect(&h.ws_url()).await;

    // 十个方法 + 一个事件主题都挂上来了
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in [
        "mods.sources",
        "mods.tags",
        "mods.search",
        "mods.project",
        "mods.versions",
        "mods.installed",
        "mods.check_updates",
        "mods.match_projects",
        "mods.set_enabled",
        "mods.remove",
        "mods.plan",
    ] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(topics.contains(&"mods.changed".to_string()), "{topics:?}");

    // ── 不需要网络的部分 ──

    // 1) 表：前端零硬编码要靠它
    let sources = client.call_ok(1, "mods.sources", json!({})).await;
    assert_eq!(sources["file_exts"], json!(["jar", "phar"]));
    assert_eq!(sources["disabled_suffix"], json!(".disabled"));
    assert_eq!(sources["sources"][0]["id"], json!("modrinth"));
    let project_types = sources["project_types"].as_array().unwrap();
    assert_eq!(project_types.len(), 2, "{sources}");
    // 「装到哪个目录按项目类型自动定」——这两个 dir 就是那条规则的唯一出处
    assert_eq!(project_types[0]["id"], json!("mod"));
    assert_eq!(project_types[0]["dir"], json!("mods"));
    assert_eq!(project_types[1]["id"], json!("plugin"));
    assert_eq!(project_types[1]["dir"], json!("plugins"));

    // 2) 建一个实例，往它的目录里放点东西
    let created = client
        .call_ok(2, "instance.create", json!({ "name": "模组测试服" }))
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    let root = h.instance_dir().join("instances").join(&id);

    // 3) 还什么都没放：两个目录都不存在（前端据此决定要不要显示标签）
    let installed = client
        .call_ok(3, "mods.installed", json!({ "instance_id": id }))
        .await;
    let dirs = installed["dirs"].as_array().unwrap();
    assert_eq!(dirs.len(), 2);
    assert_eq!(dirs[0]["dir"], json!("mods"));
    assert_eq!(dirs[0]["exists"], json!(false));
    // 这个实例的启动命令是 java，所以不是 PocketMine
    assert_eq!(installed["pmmp"], json!(false));
    assert_eq!(dirs[0]["count"], json!(0));
    assert_eq!(dirs[1]["dir"], json!("plugins"));
    assert_eq!(dirs[1]["exists"], json!(false));

    // 4) 放两个 jar（一个有元数据、一个没有）+ 一个被禁用的插件 + 一个不该被认出来的 txt
    write_fake_jar(
        &root.join("mods").join("sodium.jar"),
        "fabric.mod.json",
        r#"{ "id": "sodium", "name": "Sodium", "version": "0.7.3" }"#,
    );
    write_fake_jar(
        &root.join("mods").join("broken.jar"),
        "META-INF/MANIFEST.MF",
        "Manifest-Version: 1.0\n",
    );
    write_fake_jar(
        &root.join("plugins").join("luckperms.jar.disabled"),
        "plugin.yml",
        "name: LuckPerms\nversion: 5.4.102\nmain: me.lucko.LPBukkitPlugin\n",
    );
    std::fs::write(root.join("mods").join("readme.txt"), b"not a mod").unwrap();

    let installed = client
        .call_ok(4, "mods.installed", json!({ "instance_id": id }))
        .await;
    let dirs = installed["dirs"].as_array().unwrap();
    let mods = &dirs[0];
    assert_eq!(mods["exists"], json!(true));
    assert_eq!(mods["count"], json!(2), "txt 不该被当成模组：{installed}");
    let files = mods["files"].as_array().unwrap();
    // 名字忽略大小写排序
    assert_eq!(files[0]["file_name"], json!("broken.jar"));
    assert_eq!(files[1]["file_name"], json!("sodium.jar"));
    // 元数据是从 jar 里读出来的，不是从文件名猜的
    assert_eq!(files[1]["meta"]["id"], json!("sodium"));
    assert_eq!(files[1]["meta"]["name"], json!("Sodium"));
    assert_eq!(files[1]["meta"]["version"], json!("0.7.3"));
    assert_eq!(files[1]["meta"]["from"], json!("fabric.mod.json"));
    assert_eq!(files[1]["meta"]["loader"], json!("fabric"));
    // Fabric 没写 environment = 两端皆可（不是 unknown）
    assert_eq!(files[1]["meta"]["environment"], json!("both"));
    assert_eq!(files[1]["enabled"], json!(true));
    // 读不出元数据的 jar 照样列出来，只是 meta 是 null
    assert_eq!(files[0]["meta"], json!(null));

    let plugins = &dirs[1];
    assert_eq!(plugins["exists"], json!(true));
    let plugin_file = &plugins["files"][0];
    assert_eq!(plugin_file["file_name"], json!("luckperms.jar.disabled"));
    // 显示名去掉了 .disabled，文件名保留 —— 前端拿 file_name 当主键
    assert_eq!(plugin_file["base_name"], json!("luckperms.jar"));
    assert_eq!(plugin_file["enabled"], json!(false));
    assert_eq!(plugin_file["meta"]["from"], json!("plugin.yml"));
    // 插件系统一是 bukkit 那一档（前端显示成「Plugin」）
    assert_eq!(plugin_file["meta"]["loader"], json!("bukkit"));

    // 5) 启用 / 禁用（改名）
    let enabled = client
        .call_ok(
            5,
            "mods.set_enabled",
            json!({
                "instance_id": id, "project_type": "plugin",
                "file_name": "luckperms.jar.disabled", "enabled": true,
            }),
        )
        .await;
    assert_eq!(enabled["file_name"], json!("luckperms.jar"));
    assert!(root.join("plugins").join("luckperms.jar").is_file());
    assert!(!root.join("plugins").join("luckperms.jar.disabled").exists());

    // 幂等：已经是那个状态再设一次不该报错（前端重试 / 双击都可能发生）
    let again = client
        .call_ok(
            6,
            "mods.set_enabled",
            json!({
                "instance_id": id, "project_type": "plugin",
                "file_name": "luckperms.jar", "enabled": true,
            }),
        )
        .await;
    assert_eq!(again["file_name"], json!("luckperms.jar"));

    let disabled = client
        .call_ok(
            7,
            "mods.set_enabled",
            json!({
                "instance_id": id, "project_type": "plugin",
                "file_name": "luckperms.jar", "enabled": false,
            }),
        )
        .await;
    assert_eq!(disabled["file_name"], json!("luckperms.jar.disabled"));

    // 6) 删除
    client
        .call_ok(
            8,
            "mods.remove",
            json!({
                "instance_id": id, "project_type": "plugin",
                "file_name": "luckperms.jar.disabled",
            }),
        )
        .await;
    assert!(!root.join("plugins").join("luckperms.jar.disabled").exists());

    // 7) 参数类错误码（都不需要网络）
    let msg = client
        .call(
            9,
            "mods.installed",
            json!({ "instance_id": "no-such-instance" }),
        )
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("mods_instance_not_found"),
        "{msg}"
    );

    let msg = client
        .call(
            10,
            "mods.set_enabled",
            json!({
                "instance_id": id, "project_type": "mod",
                "file_name": "missing.jar", "enabled": false,
            }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("mods_not_found"), "{msg}");

    // 文件名带路径分隔符直接拒掉（安全边界只有一份实现）
    let msg = client
        .call(
            11,
            "mods.remove",
            json!({
                "instance_id": id, "project_type": "mod", "file_name": "../sodium.jar",
            }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("invalid_params"), "{msg}");

    let msg = client
        .call(
            12,
            "mods.plan",
            json!({ "instance_id": id, "project_id": "sodium", "project_type": "shader" }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("mods_type_not_found"), "{msg}");

    // 给插件筛 fabric：上游只会回空列表，这里提前把组合拦掉
    let msg = client
        .call(
            13,
            "mods.plan",
            json!({
                "instance_id": id, "project_id": "sodium",
                "project_type": "plugin", "loader": "fabric",
            }),
        )
        .await;
    assert_eq!(
        msg["error"]["code"],
        json!("mods_loader_unsupported"),
        "{msg}"
    );

    // 8) 工作流挂上来了：两步，且不创建任何东西（所以没有回滚点）
    let flows = client.call_ok(14, "task.flows", json!({})).await;
    let flows = flows["flows"].as_array().expect("flows 应当是数组");
    let install = flows
        .iter()
        .find(|flow| flow["name"] == json!("mods-install"))
        .unwrap_or_else(|| panic!("清单里应当有 mods-install：{flows:?}"));
    let steps = install["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 2, "{install}");
    assert_eq!(steps[0]["step_type"], json!("mods.plan"));
    assert_eq!(steps[1]["step_type"], json!("mods.download"));

    // 9) 提交时缺参数：坏参数不该拿到任务 id
    let msg = client
        .call(
            15,
            "task.submit",
            json!({ "flow": "mods-install", "params": {} }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("task_invalid_params"), "{msg}");

    // 10) 另一条连接改动了已装清单，订阅方能收到 `mods.changed`
    //     （必须用第二条连接：同一条连接上 `call` 会先把事件读掉）
    let (mut watcher, _) = Client::connect(&h.ws_url()).await;
    watcher.subscribe(1, "mods.changed").await;
    client
        .call_ok(
            16,
            "mods.set_enabled",
            json!({
                "instance_id": id, "project_type": "mod",
                "file_name": "sodium.jar", "enabled": false,
            }),
        )
        .await;
    let event = watcher.wait_event("mods.changed").await;
    assert_eq!(event["source"], json!("mods"));
    assert_eq!(event["data"]["instance_id"], json!(id));
    assert_eq!(event["data"]["project_type"], json!("mod"));
    assert_eq!(event["data"]["file_name"], json!("sodium.jar.disabled"));
    assert_eq!(event["data"]["action"], json!("disabled"));

    // ── 需要上游的部分 ──

    // 11) 搜索。上游不通就跳过这一段（离线 / 网络被挡不是功能坏了）
    let search = client
        .call(
            17,
            "mods.search",
            json!({ "project_type": "mod", "query": "sodium", "limit": 3 }),
        )
        .await;
    if search["ok"] != json!(true) {
        assert!(mods_upstream_is_down(&search), "{search}");
        eprintln!("跳过需要 Modrinth 的那几段: {search}");
        h.shutdown().await;
        return;
    }
    let search = search["result"].clone();
    assert_eq!(search["project_type"], json!("mod"));
    assert_eq!(search["source"], json!("modrinth"));
    let hits = search["hits"].as_array().expect("hits 应当是数组");
    assert!(!hits.is_empty(), "sodium 应当能搜到东西：{search}");
    // 搜索命中的关注数字段是 `follows`（详情接口才是 `followers`）——
    // 上游这两个词不一样，取错就恒为 0
    assert!(hits[0]["follows"].is_u64(), "{search}");
    assert_eq!(hits[0]["source"], json!("modrinth"));
    assert!(
        hits[0]["page_url"]
            .as_str()
            .unwrap()
            .starts_with("https://modrinth.com/"),
        "{search}"
    );

    // 12) 版本列表 + 下载计划（后端解析地址，前端只发 RPC）
    let project_id = hits[0]["project_id"].as_str().unwrap().to_string();
    let versions = client
        .call_ok(18, "mods.versions", json!({ "project_id": project_id }))
        .await;
    let versions = versions["versions"]
        .as_array()
        .expect("versions 应当是数组");
    assert!(!versions.is_empty(), "应当有版本");
    // 版本对象里带着文件与 sha1 —— 计划与校验都从这里来
    assert!(
        versions[0]["files"][0]["sha1"].is_string(),
        "Modrinth 一定给 sha1：{}",
        versions[0]
    );

    let plan = client
        .call_ok(
            19,
            "mods.plan",
            json!({ "instance_id": id, "project_id": project_id, "project_type": "mod" }),
        )
        .await;
    assert_eq!(plan["dir"], json!("mods"), "模组落到 mods/：{plan}");
    assert_eq!(plan["checksum"]["algorithm"], json!("sha1"), "{plan}");
    assert!(
        plan["relative_path"].as_str().unwrap().starts_with("mods/"),
        "{plan}"
    );
    // 计划里要能看出「会不会替换掉已有的旧版本」
    assert!(plan["replaces"].is_array(), "{plan}");

    // 13) 更新检查：刚放进去的 sodium.jar 是**手写的假 jar**，上游必然不认得，
    //     所以这里只钉「不认得就如实说不认得」，不打上游结论的准确性
    let updates = client
        .call_ok(20, "mods.check_updates", json!({ "instance_id": id }))
        .await;
    let updates_list = updates["updates"].as_array().expect("updates 应当是数组");
    for entry in updates_list {
        if entry["known"] == json!(false) {
            assert_eq!(entry["has_update"], json!(false), "不认得就不该报有更新");
            assert_eq!(entry["latest"], json!(null));
        }
    }

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// 任务系统（task）
// ---------------------------------------------------------------------------

/// 往这次运行的注册表里装测试用的步骤与 flow。
///
/// 生产路径上「谁把步骤装进注册表」是各业务模块的 `start()`；这里装的是
/// **测试专属**的（`e2e.*` 命名空间），与生产步骤共用同一份注册表 ——
/// 注册表挂在 `AppState` 上，所以每个 harness 各有一份，不会互相串。
fn populate_task_test_registry(reg: &edgecube_daemon::module::builtin::task::flows::FlowRegistry) {
    use edgecube_daemon::module::builtin::task::flows::{
        FlowStepInfo, FlowTemplate, StepEnv, StepSpec, TIMEOUT_UNLIMITED,
    };
    use szal::engine::ProgressReporter;
    use szal::flow::{FlowDef, FlowMode};
    use szal::step::StepDef;

    // task.echo：立刻成功，output 回显参数里的 tag。
    reg.register_step(
        "e2e.echo",
        StepSpec {
            title: "回显".into(),
            run: Arc::new(|step, _p: ProgressReporter, _env: StepEnv| {
                Box::pin(async move {
                    let tag = step
                        .config
                        .as_ref()
                        .and_then(|c| c.get("tag"))
                        .cloned()
                        .unwrap_or(Value::Null);
                    Ok(json!({ "tag": tag }))
                })
            }),
            rollback: None,
        },
    )
    .expect("注册 e2e.echo");

    // task.mkdir：真建目录并报进度；带回滚（删目录）。
    fn mkdir_dir(step: &StepDef) -> Option<std::path::PathBuf> {
        step.config
            .as_ref()
            .and_then(|c| c.get("dir"))
            .and_then(|v| v.as_str())
            .map(std::path::PathBuf::from)
    }
    reg.register_step(
        "e2e.mkdir",
        StepSpec {
            title: "建目录".into(),
            run: Arc::new(|step, progress: ProgressReporter, _env: StepEnv| {
                Box::pin(async move {
                    let dir = step
                        .config
                        .as_ref()
                        .and_then(|c| c.get("dir"))
                        .and_then(|v| v.as_str())
                        .ok_or("缺 dir 配置")?
                        .to_string();
                    progress.report(json!({ "percent": 50, "message": "开始建" }));
                    tokio::fs::create_dir_all(&dir)
                        .await
                        .map_err(|e| format!("建目录失败: {e}"))?;
                    progress.report(json!({ "percent": 100 }));
                    Ok(json!({ "dir": dir }))
                })
            }),
            rollback: Some(Arc::new(|step, _env: StepEnv| {
                Box::pin(async move {
                    if let Some(dir) = mkdir_dir(&step) {
                        let _ = tokio::fs::remove_dir_all(&dir).await;
                    }
                    Ok(())
                })
            })),
        },
    )
    .expect("注册 e2e.mkdir");

    // task.fail：必定失败（带 config.at 时可先睡一会，用来测取消）。
    reg.register_step(
        "e2e.fail",
        StepSpec {
            title: "失败".into(),
            run: Arc::new(|step, _p: ProgressReporter, _env: StepEnv| {
                Box::pin(async move {
                    let sleep_ms = step
                        .config
                        .as_ref()
                        .and_then(|c| c.get("sleep_ms"))
                        .and_then(|v| v.as_u64());
                    if let Some(ms) = sleep_ms {
                        tokio::time::sleep(Duration::from_millis(ms)).await;
                    }
                    Err("故意失败".to_string())
                })
            }),
            rollback: None,
        },
    )
    .expect("注册 e2e.fail");

    // task.hang：一直等，直到取消令牌被触发（协作取消）。
    reg.register_step(
        "e2e.hang",
        StepSpec {
            title: "等待取消".into(),
            run: Arc::new(|_step, _p: ProgressReporter, env: StepEnv| {
                Box::pin(async move {
                    env.cancel.cancelled().await;
                    Err("已取消".to_string())
                })
            }),
            rollback: None,
        },
    )
    .expect("注册 e2e.hang");

    // flow：e2e.ok —— 两个回显步骤（顺序 + 共享产出）。
    {
        let mut info = vec![
            FlowStepInfo {
                name: "a".into(),
                title: "甲".into(),
                step_type: "e2e.echo".into(),
            },
            FlowStepInfo {
                name: "b".into(),
                title: "乙".into(),
                step_type: "e2e.echo".into(),
            },
        ];
        // 只留展示用的 steps，不参与 build
        info.shrink_to_fit();
        reg.register_flow(
            "e2e.ok",
            FlowTemplate {
                title: "顺序成功".into(),
                steps: info,
                build: Arc::new(|_params: &Value| {
                    let mut flow = FlowDef::new("e2e.ok", FlowMode::Sequential);
                    flow.add_step(
                        StepDef::new("a")
                            .with_step_type("e2e.echo")
                            .with_config(json!({ "tag": "first" }))
                            .with_timeout(TIMEOUT_UNLIMITED),
                    );
                    flow.add_step(
                        StepDef::new("b")
                            .with_step_type("e2e.echo")
                            .with_config(json!({ "tag": "second" }))
                            .with_timeout(TIMEOUT_UNLIMITED),
                    );
                    Ok(flow)
                }),
            },
        )
        .expect("注册 e2e.ok");
    }

    // flow：e2e.rollback —— 建目录（可回滚）→ 必然失败。
    reg.register_flow(
        "e2e.rollback",
        FlowTemplate {
            title: "回滚".into(),
            steps: vec![
                FlowStepInfo {
                    name: "create".into(),
                    title: "建目录".into(),
                    step_type: "e2e.mkdir".into(),
                },
                FlowStepInfo {
                    name: "boom".into(),
                    title: "失败".into(),
                    step_type: "e2e.fail".into(),
                },
            ],
            build: Arc::new(|params: &Value| {
                let dir = params
                    .get("dir")
                    .and_then(|v| v.as_str())
                    .ok_or("缺 dir 参数")?
                    .to_string();
                let mut flow = FlowDef::new("e2e.rollback", FlowMode::Sequential);
                flow.rollback_on_failure = true;
                flow.add_step(
                    StepDef::new("create")
                        .with_step_type("e2e.mkdir")
                        .with_config(json!({ "dir": dir }))
                        .with_rollback()
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                flow.add_step(
                    StepDef::new("boom")
                        .with_step_type("e2e.fail")
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                Ok(flow)
            }),
        },
    )
    .expect("注册 e2e.rollback");

    // flow：e2e.hang —— 一个协作式长步骤，用来测取消。
    reg.register_flow(
        "e2e.hang",
        FlowTemplate {
            title: "等待取消".into(),
            steps: vec![FlowStepInfo {
                name: "wait".into(),
                title: "等待".into(),
                step_type: "e2e.hang".into(),
            }],
            build: Arc::new(|_params: &Value| {
                let mut flow = FlowDef::new("e2e.hang", FlowMode::Sequential);
                flow.add_step(
                    StepDef::new("wait")
                        .with_step_type("e2e.hang")
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                Ok(flow)
            }),
        },
    )
    .expect("注册 e2e.hang");

    // flow：e2e.slow —— 一个会睡很久的失败步骤，用来测取消（非协作路径）。
    reg.register_flow(
        "e2e.slow",
        FlowTemplate {
            title: "慢失败".into(),
            steps: vec![FlowStepInfo {
                name: "slow".into(),
                title: "慢".into(),
                step_type: "e2e.fail".into(),
            }],
            build: Arc::new(|_params: &Value| {
                let mut flow = FlowDef::new("e2e.slow", FlowMode::Sequential);
                flow.add_step(
                    StepDef::new("slow")
                        .with_step_type("e2e.fail")
                        .with_config(json!({ "sleep_ms": 60_000 }))
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                Ok(flow)
            }),
        },
    )
    .expect("注册 e2e.slow");
}

/// 等任务到终态（轮询 `task.get`），返回终态视图。
async fn wait_task_terminal(client: &mut Client, id: &str) -> Value {
    for n in 0..300 {
        let view = client
            .call_ok(10_000 + n, "task.get", json!({ "id": id }))
            .await;
        if matches!(
            view["state"].as_str(),
            Some("completed") | Some("failed") | Some("cancelled")
        ) {
            return view;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("任务 {id} 未在 6s 内到达终态");
}

#[tokio::test]
async fn task_flows_lists_test_registry() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let out = c.call_ok(1, "task.flows", json!({})).await;
    let names: Vec<&str> = out["flows"]
        .as_array()
        .expect("flows 应是数组")
        .iter()
        .filter_map(|f| f["name"].as_str())
        .collect();
    assert!(
        names.contains(&"e2e.ok"),
        "清单里应有 e2e.ok，实际 {names:?}"
    );
    assert!(
        names.contains(&"e2e.rollback"),
        "清单里应有 e2e.rollback，实际 {names:?}"
    );

    h.shutdown().await;
}

#[tokio::test]
async fn task_submit_runs_sequential_flow_and_pushes_events() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;
    c.subscribe(2, "task.state").await;
    c.subscribe(3, "task.progress").await;

    let submitted = c
        .call_ok(4, "task.submit", json!({ "flow": "e2e.ok" }))
        .await;
    let id = submitted["id"].as_str().expect("应有任务 id").to_string();
    assert_eq!(submitted["flow"], json!("e2e.ok"));
    assert_eq!(submitted["steps"].as_array().unwrap().len(), 2);

    // 事件里带完整任务对象，且确实推出来了（progress 至少一帧）。
    let ev = c.wait_event("task.state").await;
    assert_eq!(ev["topic"], json!("task.state"));
    assert!(ev["data"]["id"].is_string(), "{ev}");

    let done = wait_task_terminal(&mut c, &id).await;
    assert_eq!(done["state"], json!("completed"), "{done}");
    assert_eq!(done["steps"][0]["status"], json!("completed"));
    assert_eq!(done["steps"][1]["status"], json!("completed"));
    // 步骤 output 落在任务对象上
    assert_eq!(done["steps"][0]["output"]["tag"], json!("first"));
    assert_eq!(done["steps"][1]["output"]["tag"], json!("second"));
    assert!(done["total_duration_ms"].as_u64().is_some());
    assert_eq!(done["rolled_back"], json!(false));

    h.shutdown().await;
}

#[tokio::test]
async fn task_rollback_deletes_created_dir() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let dir = h.instance_dir().join("task-rollback-probe");
    let sub = dir.join("nested");
    let submitted = c
        .call_ok(
            1,
            "task.submit",
            json!({ "flow": "e2e.rollback", "params": { "dir": sub.display().to_string() } }),
        )
        .await;
    let id = submitted["id"].as_str().unwrap().to_string();

    let done = wait_task_terminal(&mut c, &id).await;
    assert_eq!(done["state"], json!("failed"), "{done}");
    assert_eq!(done["rolled_back"], json!(true), "{done}");
    assert_eq!(done["steps"][0]["status"], json!("rolled_back"), "{done}");
    assert_eq!(done["steps"][1]["status"], json!("failed"), "{done}");
    assert!(
        done["steps"][1]["error"]
            .as_str()
            .unwrap_or_default()
            .contains("故意失败"),
        "{done}"
    );
    // create 步骤确实产出过（output 留下证据），但目录已被回滚删掉
    assert_eq!(
        done["steps"][0]["output"]["dir"],
        json!(sub.display().to_string())
    );
    assert!(!sub.exists(), "回滚应删掉 create 建的目录");

    h.shutdown().await;
}

#[tokio::test]
async fn task_cancel_stops_cooperative_step() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let submitted = c
        .call_ok(1, "task.submit", json!({ "flow": "e2e.hang" }))
        .await;
    let id = submitted["id"].as_str().unwrap().to_string();

    let cancelled = c.call_ok(2, "task.cancel", json!({ "id": id })).await;
    // 取消是幂等的：返回当时的任务视图
    assert_eq!(cancelled["id"], json!(id));

    let done = wait_task_terminal(&mut c, &id).await;
    assert_eq!(done["state"], json!("cancelled"), "{done}");
    assert_eq!(done["steps"][0]["status"], json!("skipped"), "{done}");
    // 取消不触发回滚
    assert_eq!(done["rolled_back"], json!(false), "{done}");

    h.shutdown().await;
}

#[tokio::test]
async fn task_get_unknown_id_is_error() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let msg = c.call(1, "task.get", json!({ "id": "no-such-task" })).await;
    assert_eq!(msg["ok"], json!(false), "{msg}");
    assert_eq!(msg["error"]["code"], json!("task_not_found"), "{msg}");

    h.shutdown().await;
}

#[tokio::test]
async fn task_submit_unknown_flow_is_error() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let msg = c
        .call(1, "task.submit", json!({ "flow": "e2e.not-exists" }))
        .await;
    assert_eq!(msg["ok"], json!(false), "{msg}");
    assert_eq!(msg["error"]["code"], json!("task_flow_not_found"), "{msg}");

    h.shutdown().await;
}

/// HTTP 镜像与 WS 同源：`GET /api/tasks` 与 `GET /api/task-flows`。
#[tokio::test]
async fn task_http_mirror_works() {
    let h = Harness::start(|_| {}).await;

    let (status, text) = h.get("/api/tasks", Some(TOKEN)).await;
    assert_eq!(status, 200, "{text}");
    let body = json_body(&text);
    assert!(body["result"]["tasks"].is_array(), "{body}");

    let (status, text) = h.get("/api/task-flows", Some(TOKEN)).await;
    assert_eq!(status, 200, "{text}");
    let body = json_body(&text);
    assert!(body["result"]["flows"].is_array(), "{body}");

    // 没令牌必须 401
    let (status, _) = h.get("/api/tasks", None).await;
    assert_eq!(status, 401);

    h.shutdown().await;
}

/// 两条**生产内置**工作流都注册上来了，而且形态对得上：
/// 「实例创建 → 下载」三步、「运行环境下载 → 解压」两步。
#[tokio::test]
async fn builtin_workflows_are_registered() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    let out = c.call_ok(1, "task.flows", json!({})).await;
    let flows = out["flows"].as_array().expect("flows 应是数组");
    let find = |name: &str| {
        flows
            .iter()
            .find(|f| f["name"] == json!(name))
            .unwrap_or_else(|| panic!("清单里没有 `{name}`：{flows:?}"))
    };

    // 实例：准备服务端 → 创建实例 → 下载服务端
    let provision = find("instance-provision");
    let steps: Vec<&str> = provision["steps"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["step_type"].as_str().unwrap())
        .collect();
    assert_eq!(
        steps,
        vec!["mcserver.plan", "instance.create", "instance.download"],
        "{provision}"
    );

    // 运行环境：下载 → 解压
    let install = find("runtime-install");
    let steps: Vec<&str> = install["steps"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["step_type"].as_str().unwrap())
        .collect();
    assert_eq!(
        steps,
        vec!["runtime.download", "runtime.extract"],
        "{install}"
    );

    // 模组 / 插件：解析下载地址 → 下载并安装
    let mods = find("mods-install");
    let steps: Vec<&str> = mods["steps"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["step_type"].as_str().unwrap())
        .collect();
    assert_eq!(steps, vec!["mods.plan", "mods.download"], "{mods}");

    h.shutdown().await;
}

/// 提交内置工作流：参数不合法的**在 `task.submit` 当场被拒**（不进队、不拿 id），
/// 参数合法但要打上游的则落到 `failed`（离线环境下同样是 `failed`）。
#[tokio::test]
async fn builtin_workflow_submit_validates_params() {
    let h = Harness::start(|_| {}).await;
    let (mut c, _) = Client::connect(&h.ws_url()).await;

    // ── 实例：缺 name / type，都在 build 阶段被拒 ──
    for (id, params) in [
        (1, json!({})),
        (2, json!({ "name": "我的服" })),
        (3, json!({ "type": "paper" })),
    ] {
        let msg = c
            .call(
                id,
                "task.submit",
                json!({ "flow": "instance-provision", "params": params }),
            )
            .await;
        assert_eq!(msg["ok"], json!(false), "{msg}");
        assert_eq!(msg["error"]["code"], json!("task_invalid_params"), "{msg}");
    }

    // ── 运行环境：缺 java_version ──
    let msg = c
        .call(
            4,
            "task.submit",
            json!({ "flow": "runtime-install", "params": {} }),
        )
        .await;
    assert_eq!(msg["error"]["code"], json!("task_invalid_params"), "{msg}");

    // ── 参数合法但类型不认识：进队后第一步就挂（不打上游，纯表查询）──
    let submitted = c
        .call_ok(
            5,
            "task.submit",
            json!({ "flow": "instance-provision", "params": { "name": "我的服", "type": "nope" } }),
        )
        .await;
    let id = submitted["id"]
        .as_str()
        .expect("应当拿到任务 id")
        .to_string();
    let done = wait_task_terminal(&mut c, &id).await;
    assert_eq!(done["state"], json!("failed"), "{done}");
    // 失败落在第一步（准备服务端），错误里带上我们拒的那个类型名 ——
    // 步骤错误是字符串，所以带**稳定错误码前缀**（前端按前缀分支）
    assert_eq!(done["steps"][0]["status"], json!("failed"), "{done}");
    assert!(
        done["steps"][0]["error"]
            .as_str()
            .is_some_and(|e| e.starts_with("mcserver_type_not_found") && e.contains("nope")),
        "错误要带稳定码并说清是哪个类型：{done}"
    );
    // 后面的步骤被引擎标成 skipped（不是 pending）—— 前一步挂了就不该再往下走
    assert_eq!(done["steps"][1]["status"], json!("skipped"), "{done}");
    assert_eq!(done["steps"][2]["status"], json!("skipped"), "{done}");

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// UPnP
// ---------------------------------------------------------------------------

/// 等 UPnP 总览满足条件（映射行的增删改是事件驱动的异步对账，要等它落定）。
async fn wait_upnp_status(c: &mut Client, what: &str, check: impl Fn(&Value) -> bool) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    let mut call_id = 900;
    loop {
        let status = c.call_ok(call_id, "upnp.status", json!({})).await;
        call_id += 1;
        if check(&status) {
            return status;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "等 {what} 超时: {status}"
        );
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

/// UPnP 全链路（不依赖真实网关）：方法与主题的契约、映射行跟着实例事件
/// 增 / 改 / 删、缓存查询不联网；`upnp.probe` 在无网关的环境里也要把失败
/// 写进网关状态而不是让调用报错。
#[tokio::test]
async fn upnp_status_probe_and_events_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut c, hello) = Client::connect(&h.ws_url()).await;

    // ── 方法与主题都挂上来了 ──
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in ["upnp.status", "upnp.probe"] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(topics.contains(&"upnp.evt".to_string()), "{topics:?}");

    // 事件连接先订好：之后创建的实例，它的 upnp.evt 必定能收到
    // （订阅应答先于 create 发出，服务端注册先于事件发布）。
    let (mut evts, _) = Client::connect(&h.ws_url()).await;
    let ack = evts.subscribe(1, "upnp.evt").await;
    assert_eq!(ack["ok"], json!(true), "{ack}");

    // ── 初始总览：没有开着 UPnP 的实例 → 没探过网关、零行 ──
    let status = c.call_ok(1, "upnp.status", json!({})).await;
    assert_eq!(status["gateway"]["state"], json!("unknown"), "{status}");
    assert!(status["gateway"]["external_ip"].is_null(), "{status}");
    assert_eq!(status["gateway"]["cgnat"], json!(false), "{status}");
    assert!(status["gateway"]["address"].is_null(), "{status}");
    assert!(status["gateway"]["error"].is_null(), "{status}");
    assert!(status["gateway"]["probed_at_ms"].is_null(), "{status}");
    assert_eq!(status["mappings"], json!([]), "{status}");
    assert_eq!(status["count"], json!(0), "{status}");

    // ── 创建一个开着 UPnP 的实例（UDP / 外部端口 19133）──
    let created = c
        .call_ok(
            2,
            "instance.create",
            json!({
                "name": "生存服",
                "upnp_enabled": true,
                "upnp_protocol": "udp",
                "upnp_external_port": 19133,
            }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    assert_eq!(created["instance"]["upnp_enabled"], json!(true));
    assert_eq!(created["instance"]["upnp_protocol"], json!("udp"));
    assert_eq!(created["instance"]["upnp_external_port"], json!(19133));

    // 行跟着 `instance.created` 出来；事件体是一份完整总览
    let evt = evts.wait_event("upnp.evt").await;
    let published_row = evt["data"]["mappings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["instance_id"] == json!(id))
        .unwrap_or_else(|| panic!("upnp.evt 里应当带上刚开的行: {evt}"));
    assert_eq!(published_row["enabled"], json!(true));
    assert_eq!(published_row["running"], json!(false));
    assert_eq!(
        published_row["state"],
        json!("idle"),
        "实例没在跑，行就该是 idle: {evt}"
    );
    assert_eq!(published_row["protocol"], json!("udp"));
    assert_eq!(published_row["external_port"], json!(19133));

    // 缓存查询与事件一致；实例没在跑 → 没有公网地址
    let status = wait_upnp_status(&mut c, "行出现", |s| s["count"] == json!(1)).await;
    let row = &status["mappings"][0];
    assert_eq!(row["instance_id"], json!(id));
    assert_eq!(
        row["internal_port"],
        json!(25565),
        "没有 server.properties → 默认 25565: {status}"
    );
    assert!(row["public_address"].is_null(), "{status}");

    // ── 改外部端口 → 行跟着 `instance.updated` 走 ──
    c.call_ok(
        3,
        "instance.update",
        json!({ "id": id, "upnp_external_port": 25570 }),
    )
    .await;
    let status = wait_upnp_status(&mut c, "外部端口变更", |s| {
        s["mappings"]
            .get(0)
            .is_some_and(|r| r["external_port"] == json!(25570))
    })
    .await;
    assert_eq!(status["mappings"][0]["protocol"], json!("udp"));
    assert_eq!(status["mappings"][0]["enabled"], json!(true));

    // ── 关开关：行保留，显示为未启用 ──
    c.call_ok(
        4,
        "instance.update",
        json!({ "id": id, "upnp_enabled": false }),
    )
    .await;
    wait_upnp_status(&mut c, "开关关闭", |s| {
        s["mappings"]
            .get(0)
            .is_some_and(|r| r["enabled"] == json!(false))
    })
    .await;

    // ── 再打开：跟着回来 ──
    c.call_ok(
        5,
        "instance.update",
        json!({ "id": id, "upnp_enabled": true }),
    )
    .await;
    wait_upnp_status(&mut c, "开关重开", |s| {
        s["mappings"]
            .get(0)
            .is_some_and(|r| r["enabled"] == json!(true))
    })
    .await;

    // ── probe：本机有没有网关都行，但必须落定成 ready / error；
    //    失败要把原因写进 gateway.error —— 而不是调用报错 ──
    let probed = c.call_ok(6, "upnp.probe", json!({})).await;
    let state = probed["gateway"]["state"].as_str().unwrap_or("");
    assert!(["ready", "error"].contains(&state), "{probed}");
    assert!(
        probed["gateway"]["probed_at_ms"].is_number(),
        "探过就该有探测时间: {probed}"
    );
    if state == "error" {
        assert!(
            probed["gateway"]["error"]
                .as_str()
                .is_some_and(|e| !e.is_empty()),
            "失败必须说明原因: {probed}"
        );
    } else {
        assert!(
            probed["gateway"]["address"].is_string(),
            "成功就该报出网关地址: {probed}"
        );
    }
    // 实例没在跑：probe 不会给它加映射，也就没有公网地址
    assert_eq!(probed["mappings"][0]["state"], json!("idle"), "{probed}");
    assert!(
        probed["mappings"][0]["public_address"].is_null(),
        "{probed}"
    );

    // ── 删除实例：行跟着 `instance.deleted` 消失 ──
    let deleted = c.call_ok(7, "instance.delete", json!({ "id": id })).await;
    assert_eq!(deleted["deleted"], json!(true));
    wait_upnp_status(&mut c, "行消失", |s| s["count"] == json!(0)).await;

    h.shutdown().await;
}

// ---------------------------------------------------------------------------
// STUN
// ---------------------------------------------------------------------------

/// 等 STUN 总览满足条件（隧道行的增删改是事件驱动的异步对账，要等它落定）。
async fn wait_stun_status(c: &mut Client, what: &str, check: impl Fn(&Value) -> bool) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    let mut call_id = 900;
    loop {
        let status = c.call_ok(call_id, "stun.status", json!({})).await;
        call_id += 1;
        if check(&status) {
            return status;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "等 {what} 超时: {status}"
        );
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

/// 等一条满足条件的 `stun.evt`（跳过队列里更早的那些）。
async fn wait_stun_event(evts: &mut Client, what: &str, check: impl Fn(&Value) -> bool) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        assert!(!remaining.is_zero(), "等 {what} 事件超时");
        let msg = evts
            .next_json_within(remaining)
            .await
            .unwrap_or_else(|| panic!("等 {what} 事件超时（连接结束）"));
        if msg["type"] == json!("event") && msg["topic"] == json!("stun.evt") && check(&msg) {
            return msg;
        }
    }
}

/// STUN 全链路（不真的打洞）：方法与主题契约、隧道行跟着实例事件增删改、
/// 设置保存 / clamp / 立即生效、日志查询与清空。
///
/// 实例在这里不会真的启动（没有可执行文件），所以不会发起任何打洞 ——
/// 探测 / 转发 / 重建这些真动作在模块的单测里用假打洞器覆盖。
#[tokio::test]
async fn stun_status_settings_and_logs_over_ws() {
    let h = Harness::start(|_| {}).await;
    let (mut c, hello) = Client::connect(&h.ws_url()).await;

    // ── 方法与主题都挂上来了 ──
    let methods: Vec<String> = hello["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["name"].as_str().unwrap().to_string())
        .collect();
    for expected in [
        "stun.status",
        "stun.settings.set",
        "stun.logs",
        "stun.logs.clear",
    ] {
        assert!(methods.contains(&expected.to_string()), "{methods:?}");
    }
    let topics: Vec<String> = hello["topics"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["topic"].as_str().unwrap().to_string())
        .collect();
    assert!(topics.contains(&"stun.evt".to_string()), "{topics:?}");

    // 事件连接先订好
    let (mut evts, _) = Client::connect(&h.ws_url()).await;
    let ack = evts.subscribe(1, "stun.evt").await;
    assert_eq!(ack["ok"], json!(true), "{ack}");

    // ── 初始总览：默认设置（内置 8 台服务器）、零行 ──
    let status = c.call_ok(1, "stun.status", json!({})).await;
    let defaults = &status["settings"];
    assert_eq!(defaults["servers"].as_array().unwrap().len(), 8, "{status}");
    assert_eq!(defaults["keep_alive_seconds"], json!(20), "{status}");
    assert_eq!(defaults["max_connections"], json!(128), "{status}");
    assert_eq!(defaults["show_connection_log"], json!(true), "{status}");
    assert_eq!(status["tunnels"], json!([]), "{status}");
    assert_eq!(status["count"], json!(0), "{status}");

    // ── 创建一个开着 STUN 的实例 ──
    let created = c
        .call_ok(
            2,
            "instance.create",
            json!({
                "name": "生存服",
                "stun_enabled": true,
                "stun_proxy_protocol": true,
                "stun_target_port": 25570,
            }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    assert_eq!(created["instance"]["stun_enabled"], json!(true));
    assert_eq!(created["instance"]["stun_proxy_protocol"], json!(true));
    assert_eq!(created["instance"]["stun_target_port"], json!(25570));

    // 行跟着 `instance.created` 出来；事件体是一份完整总览
    let id_for_check = id.clone();
    let evt = wait_stun_event(&mut evts, "行出现", move |evt| {
        evt["data"]["tunnels"]
            .as_array()
            .is_some_and(|rows| rows.iter().any(|r| r["instance_id"] == json!(id_for_check)))
    })
    .await;
    let published_row = evt["data"]["tunnels"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["instance_id"] == json!(id))
        .unwrap();
    assert_eq!(published_row["enabled"], json!(true));
    assert_eq!(published_row["running"], json!(false), "实例没在跑: {evt}");
    assert_eq!(published_row["state"], json!("idle"), "{evt}");
    assert_eq!(published_row["target_port"], json!(25570));
    assert_eq!(published_row["max_connections"], json!(128));

    // 缓存查询与事件一致；实例没在跑 → 未就绪、没有公网地址、零流量
    let status = wait_stun_status(&mut c, "行出现", |s| s["count"] == json!(1)).await;
    let row = &status["tunnels"][0];
    assert_eq!(row["instance_id"], json!(id));
    assert_eq!(row["local_port"], json!(0));
    assert!(row["public_address"].is_null(), "{status}");
    assert_eq!(row["active_connections"], json!(0));
    assert_eq!(row["total_up"], json!(0));
    assert_eq!(row["total_down"], json!(0));

    // ── 改目标端口覆盖 → 行跟着 `instance.updated` 走 ──
    c.call_ok(
        3,
        "instance.update",
        json!({ "id": id, "stun_target_port": 25580 }),
    )
    .await;
    wait_stun_status(&mut c, "目标端口变更", |s| {
        s["tunnels"]
            .get(0)
            .is_some_and(|r| r["target_port"] == json!(25580))
    })
    .await;

    // 清掉覆盖（null）→ 回到读盘端口（没有配置文件 → 25565）
    c.call_ok(
        4,
        "instance.update",
        json!({ "id": id, "stun_target_port": null }),
    )
    .await;
    wait_stun_status(&mut c, "覆盖清除", |s| {
        s["tunnels"]
            .get(0)
            .is_some_and(|r| r["target_port"] == json!(25565))
    })
    .await;

    // ── 关开关：行保留，显示为未启用；再打开跟着回来 ──
    c.call_ok(
        5,
        "instance.update",
        json!({ "id": id, "stun_enabled": false }),
    )
    .await;
    wait_stun_status(&mut c, "开关关闭", |s| {
        s["tunnels"]
            .get(0)
            .is_some_and(|r| r["enabled"] == json!(false))
    })
    .await;
    c.call_ok(
        6,
        "instance.update",
        json!({ "id": id, "stun_enabled": true }),
    )
    .await;
    wait_stun_status(&mut c, "开关重开", |s| {
        s["tunnels"]
            .get(0)
            .is_some_and(|r| r["enabled"] == json!(true))
    })
    .await;

    // ── 保存设置：越界值被 clamp、即时生效、事件也推 ──
    let saved = c
        .call_ok(
            7,
            "stun.settings.set",
            json!({
                "servers": ["stun.example.com:3479"],
                "keep_alive_seconds": 9999,
                "max_connections": 0,
                "show_connection_log": false,
            }),
        )
        .await;
    assert_eq!(
        saved["settings"]["servers"],
        json!(["stun.example.com:3479"]),
        "{saved}"
    );
    assert_eq!(
        saved["settings"]["keep_alive_seconds"],
        json!(300),
        "{saved}"
    );
    assert_eq!(saved["settings"]["max_connections"], json!(1), "{saved}");
    assert_eq!(
        saved["settings"]["show_connection_log"],
        json!(false),
        "{saved}"
    );
    // 行上的并发上限跟着新设置走
    assert_eq!(saved["tunnels"][0]["max_connections"], json!(1), "{saved}");
    wait_stun_event(&mut evts, "设置变更", |evt| {
        evt["data"]["settings"]["max_connections"] == json!(1)
    })
    .await;

    // ── 日志：实例没跑过 → 空；清空幂等 ──
    let logs = c.call_ok(8, "stun.logs", json!({})).await;
    assert_eq!(logs["count"], json!(0), "{logs}");
    assert_eq!(logs["lines"], json!([]), "{logs}");
    let cleared = c.call_ok(9, "stun.logs.clear", json!({})).await;
    assert_eq!(cleared["cleared"], json!(0), "{cleared}");

    // ── 非法参数：类型不符 → invalid_params ──
    let bad = c
        .call(
            10,
            "stun.settings.set",
            json!({ "keep_alive_seconds": "abc" }),
        )
        .await;
    assert_eq!(bad["ok"], json!(false), "{bad}");
    assert_eq!(bad["error"]["code"], json!("invalid_params"), "{bad}");

    // ── 删除实例：行跟着 `instance.deleted` 消失 ──
    let deleted = c.call_ok(11, "instance.delete", json!({ "id": id })).await;
    assert_eq!(deleted["deleted"], json!(true));
    wait_stun_status(&mut c, "行消失", |s| s["count"] == json!(0)).await;

    h.shutdown().await;
}
