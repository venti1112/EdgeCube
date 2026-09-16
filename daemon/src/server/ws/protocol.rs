//! WS 应用层协议（信封定义）。
//!
//! 设计目标：在一条长连接上同时支持「类 HTTP 一问一答」和「服务端主动推送」。
//! 两者共用一个 JSON 信封，靠 `type` 区分。
//!
//! # 客户端 → 服务端
//!
//! ```json
//! {"type": "call", "id": 1, "method": "core.ping", "params": {}}
//! {"type": "subscribe", "id": 2, "topic": "ticker.*"}
//! {"type": "unsubscribe", "id": 3, "topic": "ticker.*"}
//! {"type": "ping", "id": 4}
//! ```
//!
//! # 服务端 → 客户端
//!
//! ```json
//! {"type": "hello", "protocol": 1, "methods": [...], "topics": [...]}
//! {"type": "result", "id": 1, "ok": true, "result": {...}, "elapsed_ms": 0}
//! {"type": "result", "id": 1, "ok": false, "error": {"code": "method_not_found", "message": "..."}}
//! {"type": "event", "topic": "ticker.tick", "seq": 12, "ts": 1730000000000, "data": {...}}
//! {"type": "pong", "id": 4, "ts": 1730000000000}
//! {"type": "error", "error": {...}}     // 协议级错误，没有对应的 id
//! ```
//!
//! 要点：
//!
//! * `id` 由客户端给，服务端原样回填。**没有 id 的消息一律是服务端主动推的**。
//! * 并发调用不保序，靠 `id` 配对；一次调用只可能收到一个 `result`。
//! * 事件带全局自增 `seq`，客户端发现跳号就知道自己掉过事件。

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::RpcError;
use crate::module::{MethodInfo, ModuleDescriptor, TopicSpec};

/// 请求/响应的关联 id。允许字符串或数字，原样回填。
pub type MsgId = Option<Value>;

/// 客户端发来的消息。
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    /// 类 HTTP 调用。
    Call {
        #[serde(default)]
        id: MsgId,
        method: String,
        #[serde(default)]
        params: Value,
    },
    /// 订阅事件主题，支持 `*` / `prefix.*`。
    Subscribe {
        #[serde(default)]
        id: MsgId,
        topic: String,
    },
    /// 取消订阅。
    Unsubscribe {
        #[serde(default)]
        id: MsgId,
        topic: String,
    },
    /// 应用层心跳（与 WS Ping 帧并行，给不方便发控制帧的客户端用）。
    Ping {
        #[serde(default)]
        id: MsgId,
    },
    /// 可选握手，声明客户端身份与协议版本。
    Hello {
        #[serde(default)]
        id: MsgId,
        #[serde(default)]
        client: Option<String>,
        #[serde(default)]
        protocol: Option<u32>,
    },
}

impl ClientMessage {
    pub fn id(&self) -> MsgId {
        match self {
            Self::Call { id, .. }
            | Self::Subscribe { id, .. }
            | Self::Unsubscribe { id, .. }
            | Self::Ping { id }
            | Self::Hello { id, .. } => id.clone(),
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::Call { .. } => "call",
            Self::Subscribe { .. } => "subscribe",
            Self::Unsubscribe { .. } => "unsubscribe",
            Self::Ping { .. } => "ping",
            Self::Hello { .. } => "hello",
        }
    }
}

/// 连接建立后服务端发的第一条消息：自报家门 + 能力清单。
#[derive(Debug, Clone, Serialize)]
pub struct Hello {
    pub protocol: u32,
    pub product: String,
    pub version: String,
    pub pid: u32,
    pub conn_id: u64,
    pub peer: String,
    pub started_at_ms: u64,
    pub auth_required: bool,
    pub config_path: Option<String>,
    /// 已装载模块。
    pub modules: Vec<ModuleDescriptor>,
    /// 可调用的方法清单。
    pub methods: Vec<MethodInfo>,
    /// 可订阅的事件主题。
    pub topics: Vec<TopicSpec>,
    pub max_inflight_calls: usize,
    pub request_timeout_secs: u64,
    pub ts: u64,
}

/// 服务端发回的消息。
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    /// 连接就绪。
    Hello(Box<Hello>),
    /// 一次 `call` / `subscribe` / ... 的应答。
    Result {
        id: MsgId,
        ok: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        result: Option<Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<RpcError>,
        /// 服务端处理耗时，方便前端做性能观察。
        #[serde(skip_serializing_if = "Option::is_none")]
        elapsed_ms: Option<u64>,
    },
    /// 主动推送。
    Event {
        topic: String,
        seq: u64,
        ts: u64,
        #[serde(skip_serializing_if = "Option::is_none")]
        source: Option<String>,
        data: Value,
    },
    Pong {
        id: MsgId,
        ts: u64,
    },
    /// 协议级错误：消息本身不合法，或与任何请求都对不上。
    Error {
        #[serde(skip_serializing_if = "Option::is_none")]
        id: MsgId,
        error: RpcError,
    },
    /// 服务端即将断开。
    Bye {
        code: u16,
        reason: String,
    },
}

impl ServerMessage {
    /// 成功应答。
    pub fn ok(id: MsgId, result: Value) -> Self {
        Self::Result {
            id,
            ok: true,
            result: Some(result),
            error: None,
            elapsed_ms: None,
        }
    }

    /// 带耗时的成功应答。
    pub fn ok_timed(id: MsgId, result: Value, elapsed_ms: u64) -> Self {
        Self::Result {
            id,
            ok: true,
            result: Some(result),
            error: None,
            elapsed_ms: Some(elapsed_ms),
        }
    }

    /// 失败应答。
    pub fn err(id: MsgId, error: RpcError) -> Self {
        Self::Result {
            id,
            ok: false,
            result: None,
            error: Some(error),
            elapsed_ms: None,
        }
    }

    /// 失败应答（带耗时）。
    pub fn err_timed(id: MsgId, error: RpcError, elapsed_ms: u64) -> Self {
        Self::Result {
            id,
            ok: false,
            result: None,
            error: Some(error),
            elapsed_ms: Some(elapsed_ms),
        }
    }

    /// 事件推送。
    pub fn event(event: &crate::event::Event) -> Self {
        Self::Event {
            topic: event.topic.clone(),
            seq: event.seq,
            ts: event.ts,
            source: event.source.clone(),
            data: event.data.clone(),
        }
    }

    /// 序列化为单帧 JSON 文本。
    pub fn encode(&self) -> String {
        // 信封由框架自己构造，理论上不会失败；真失败就退化成一句可读的错误。
        serde_json::to_string(self).unwrap_or_else(|e| {
            format!(
                r#"{{"type":"error","error":{{"code":"internal","message":"编码响应失败: {e}"}}}}"#
            )
        })
    }

    pub fn type_name(&self) -> &'static str {
        match self {
            Self::Hello(_) => "hello",
            Self::Result { .. } => "result",
            Self::Event { .. } => "event",
            Self::Pong { .. } => "pong",
            Self::Error { .. } => "error",
            Self::Bye { .. } => "bye",
        }
    }
}

/// 解析客户端消息。错误里带原始片段，便于排查。
pub fn decode(text: &str) -> Result<ClientMessage, RpcError> {
    serde_json::from_str::<ClientMessage>(text).map_err(|e| {
        let preview: String = text.chars().take(200).collect();
        RpcError::bad_request(format!("消息格式不合法: {e}；收到: {preview}"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn decodes_every_client_message_kind() {
        let call =
            decode(r#"{"type":"call","id":1,"method":"core.ping","params":{"a":1}}"#).unwrap();
        assert!(matches!(call, ClientMessage::Call { .. }));
        assert_eq!(call.kind(), "call");
        assert_eq!(call.id(), Some(json!(1)));

        // params / id 都可省略
        let call = decode(r#"{"type":"call","method":"core.ping"}"#).unwrap();
        match call {
            ClientMessage::Call { id, params, .. } => {
                assert_eq!(id, None);
                assert_eq!(params, Value::Null);
            }
            other => panic!("{other:?}"),
        }

        assert!(matches!(
            decode(r#"{"type":"subscribe","topic":"ticker.*"}"#).unwrap(),
            ClientMessage::Subscribe { .. }
        ));
        assert!(matches!(
            decode(r#"{"type":"unsubscribe","topic":"ticker.*"}"#).unwrap(),
            ClientMessage::Unsubscribe { .. }
        ));
        assert!(matches!(
            decode(r#"{"type":"ping"}"#).unwrap(),
            ClientMessage::Ping { .. }
        ));
        assert!(matches!(
            decode(r#"{"type":"hello","client":"app","protocol":1}"#).unwrap(),
            ClientMessage::Hello { .. }
        ));
    }

    #[test]
    fn bad_json_gives_readable_error() {
        let err = decode("这不是 JSON").unwrap_err();
        assert_eq!(err.code, "bad_request");
        assert!(err.message.contains("消息格式不合法"));

        let err = decode(r#"{"type":"nope"}"#).unwrap_err();
        assert_eq!(err.code, "bad_request");
    }

    #[test]
    fn string_ids_are_echoed_verbatim() {
        let m = decode(r#"{"type":"call","id":"req-7","method":"core.ping"}"#).unwrap();
        assert_eq!(m.id(), Some(json!("req-7")));
    }

    #[test]
    fn result_envelope_has_type_tag_and_omits_nulls() {
        let ok = ServerMessage::ok(Some(json!(1)), json!({"pong": true}));
        let v: Value = serde_json::from_str(&ok.encode()).unwrap();
        assert_eq!(v["type"], json!("result"));
        assert_eq!(v["ok"], json!(true));
        assert_eq!(v["id"], json!(1));
        assert_eq!(v["result"]["pong"], json!(true));
        assert!(v.get("error").is_none(), "成功应答不该带 error");

        let err = ServerMessage::err(Some(json!(2)), RpcError::method_not_found("没有"));
        let v: Value = serde_json::from_str(&err.encode()).unwrap();
        assert_eq!(v["ok"], json!(false));
        assert_eq!(v["error"]["code"], json!("method_not_found"));
        assert!(v.get("result").is_none(), "失败应答不该带 result");
    }

    #[test]
    fn hello_flattens_into_tagged_object() {
        let hello = Hello {
            protocol: crate::PROTOCOL_VERSION,
            product: crate::PRODUCT.into(),
            version: crate::VERSION.into(),
            pid: 1,
            conn_id: 9,
            peer: "127.0.0.1:1".into(),
            started_at_ms: 0,
            auth_required: false,
            config_path: None,
            modules: vec![],
            methods: vec![],
            topics: vec![],
            max_inflight_calls: 32,
            request_timeout_secs: 30,
            ts: 123,
        };
        let v: Value =
            serde_json::from_str(&ServerMessage::Hello(Box::new(hello)).encode()).unwrap();
        assert_eq!(v["type"], json!("hello"));
        assert_eq!(v["protocol"], json!(crate::PROTOCOL_VERSION));
        assert_eq!(v["conn_id"], json!(9));
    }

    #[test]
    fn event_envelope_carries_seq_and_source() {
        let e = crate::event::Event {
            topic: "ticker.tick".into(),
            seq: 3,
            ts: 1,
            source: Some("ticker".into()),
            data: json!({"n": 1}),
        };
        let v: Value = serde_json::from_str(&ServerMessage::event(&e).encode()).unwrap();
        assert_eq!(v["type"], json!("event"));
        assert_eq!(v["seq"], json!(3));
        assert_eq!(v["source"], json!("ticker"));
        assert_eq!(v["data"]["n"], json!(1));
    }
}
