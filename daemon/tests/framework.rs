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

    // 2) 新建
    let created = client
        .call_ok(
            2,
            "instance.create",
            json!({ "name": "生存服", "maxMemory": 2048, "runtimeEnvId": "jre21" }),
        )
        .await;
    let id = created["instance"]["id"].as_str().unwrap().to_string();
    assert!(id.len() == 16, "id 应是 16 位 hex: {id}");
    assert_eq!(created["instance"]["name"], json!("生存服"));
    assert_eq!(created["selected"], json!(id));
    assert!(
        data_dir.join("instances").join(&id).is_dir(),
        "工作目录应已建好"
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
    assert_eq!(got["instance"]["max_memory"], json!(2048));
    let status = client
        .call_ok(6, "instance.status", json!({ "id": id }))
        .await;
    assert_eq!(status["status"]["process_managed"], json!(false));
    assert_eq!(status["status"]["running"], json!(false));

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
