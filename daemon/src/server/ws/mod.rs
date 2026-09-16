//! WebSocket 接入层。

pub mod protocol;
pub mod session;

use std::net::SocketAddr;

use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{ConnectInfo, State};
use axum::response::Response;
use serde_json::json;

use crate::error::RpcError;
use crate::server::http::api_result;
use crate::state::AppState;

/// 单帧消息大小上限。客户端发来的都是小信封，超过这个数基本是打错了。
const MAX_MESSAGE_SIZE: usize = 1024 * 1024;

/// `GET {ws_path}` 的处理器：鉴权已由外层中间件完成。
pub async fn upgrade(
    ws: WebSocketUpgrade,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    State(app): State<AppState>,
) -> Response {
    let current = app.conns.count().await;
    let max = app.config.server.max_connections;
    if current >= max {
        tracing::warn!(current, max, peer = %peer, "连接数已达上限，拒绝接入");
        return api_result(Err(RpcError::busy(format!("连接数已达上限（{max}）"))));
    }

    tracing::debug!(peer = %peer, "接受 WS 升级");
    ws.max_message_size(MAX_MESSAGE_SIZE)
        .on_upgrade(move |socket| session::run(socket, app, peer))
}

/// 给文档用的 JSON 说明，方便手搓客户端的人。
pub fn protocol_doc() -> serde_json::Value {
    json!({
        "client_to_server": [
            {"type": "call", "id": 1, "method": "core.ping", "params": {}},
            {"type": "subscribe", "id": 2, "topic": "ticker.*"},
            {"type": "unsubscribe", "id": 3, "topic": "ticker.*"},
            {"type": "ping", "id": 4},
        ],
        "server_to_client": [
            {"type": "hello", "protocol": crate::PROTOCOL_VERSION},
            {"type": "result", "id": 1, "ok": true, "result": {}},
            {"type": "result", "id": 1, "ok": false, "error": {"code": "method_not_found", "message": ""}},
            {"type": "event", "topic": "ticker.tick", "seq": 1, "ts": 0, "data": {}},
            {"type": "pong", "id": 4, "ts": 0},
        ],
        "notes": [
            "id 由客户端提供并原样回填；没有 id 的消息都是服务端主动推送",
            "并发调用不保证顺序，按 id 配对",
            "事件 seq 全局自增，跳号说明丢过事件",
        ],
    })
}
