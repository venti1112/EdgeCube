//! 单条 WS 连接的生命周期。
//!
//! 一条连接 = 两个任务：
//!
//! * **writer** —— 独占 `sink`，从 `mpsc` 里取消息写出去。所有出站流量
//!   （应答、事件推送、心跳、告别帧）都经过它，保证帧不会交叉、顺序不乱。
//! * **reader** —— 处理入站帧：解析信封、分发调用、维护订阅、投喂心跳。
//!
//! 每次 `call` 再 `spawn` 一个子任务去跑处理器，所以慢方法不会阻塞心跳和其他调用；
//! 并发上限由 [`crate::config::ServerConfig::max_inflight_calls`] 的信号量兜底。

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::body::Bytes;
use axum::extract::ws::{CloseFrame, Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::sync::{Semaphore, broadcast};
use tokio::time::MissedTickBehavior;

use crate::conn::{ConnHandle, Outbound};
use crate::error::RpcError;
use crate::event::{TopicPattern, topics};
use crate::module::CallCtx;
use crate::server::ws::protocol::{self, ClientMessage, Hello, MsgId, ServerMessage};
use crate::state::AppState;
use crate::util::now_ms;
use crate::{PRODUCT, PROTOCOL_VERSION, VERSION};

/// WS 关闭码。
const CLOSE_NORMAL: u16 = 1000;
const CLOSE_GOING_AWAY: u16 = 1001;

/// 跑完一条连接，直到对端断开或服务关闭。
pub async fn run(socket: WebSocket, app: AppState, peer: SocketAddr) {
    let conn_id = app.conns.next_id();
    let peer_str = peer.to_string();
    let is_local = peer.ip().is_loopback();

    let (mut sink, mut stream) = socket.split();
    let (handle, mut out_rx) = app.conns.register(conn_id, peer_str.clone()).await;

    tracing::info!(conn_id, peer = %peer_str, local = is_local, "连接已建立");

    // ---- 唯一 writer ----
    let writer = tokio::spawn(async move {
        while let Some(out) = out_rx.recv().await {
            let frame = match out {
                Outbound::Msg(msg) => {
                    tracing::trace!(conn_id, kind = msg.type_name(), "出站消息");
                    Message::Text(msg.encode().into())
                }
                Outbound::Ping => Message::Ping(Bytes::new()),
                Outbound::Pong(payload) => Message::Pong(Bytes::from(payload)),
                Outbound::Close { code, reason } => {
                    let _ = sink
                        .send(Message::Close(Some(CloseFrame {
                            code,
                            reason: reason.into(),
                        })))
                        .await;
                    break;
                }
            };
            if sink.send(frame).await.is_err() {
                break;
            }
        }
        let _ = sink.close().await;
    });

    // ---- 握手：把能力清单一次性给客户端 ----
    handle.push(Arc::new(ServerMessage::Hello(Box::new(Hello {
        protocol: PROTOCOL_VERSION,
        product: PRODUCT.to_string(),
        version: VERSION.to_string(),
        pid: std::process::id(),
        conn_id,
        peer: peer_str.clone(),
        started_at_ms: app.started_at_ms,
        auth_required: app.config.server.auth_required(),
        config_path: app.config_path_string(),
        modules: app.registry.enabled_descriptors().to_vec(),
        methods: app.registry.method_infos(),
        topics: app.registry.topics().to_vec(),
        max_inflight_calls: app.config.server.max_inflight_calls,
        request_timeout_secs: app.config.server.request_timeout_secs,
        ts: now_ms(),
    }))));
    app.bus.publish_from(
        Some("core"),
        topics::CONN_OPENED,
        json!({ "conn_id": conn_id, "peer": peer_str, "connections": app.conns.count().await }),
    );

    // ---- reader 主循环 ----
    let mut subs: Vec<TopicPattern> = Vec::new();
    let mut bus_rx = app.bus.subscribe();
    let mut heartbeat = tokio::time::interval(Duration::from_secs(
        app.config.server.heartbeat_interval_secs.max(1),
    ));
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);
    // 第一次 tick 立刻到，跳过（否则刚连上就发心跳）。
    heartbeat.tick().await;

    let inflight = Arc::new(Semaphore::new(app.config.server.max_inflight_calls.max(1)));
    let idle_limit = Duration::from_secs(app.config.server.idle_timeout_secs);
    let mut last_seen = Instant::now();
    let mut exit_reason = "对端断开";

    loop {
        tokio::select! {
            // 服务在关：主动告知并礼貌退出
            _ = app.cancel.cancelled() => {
                exit_reason = "服务关闭";
                // 先发一条应用层告别消息，让客户端知道是「服务要停」而不是「网络断了」。
                handle.push(Arc::new(ServerMessage::Bye {
                    code: CLOSE_GOING_AWAY,
                    reason: "server shutting down".into(),
                }));
                handle.close(CLOSE_GOING_AWAY, "server shutting down");
                break;
            }

            // 心跳 + 空闲检查
            _ = heartbeat.tick() => {
                if app.config.server.idle_timeout_secs > 0 && last_seen.elapsed() >= idle_limit {
                    exit_reason = "空闲超时";
                    handle.close(CLOSE_NORMAL, "idle timeout");
                    break;
                }
                if !handle.send(Outbound::Ping) {
                    exit_reason = "写端已关闭";
                    break;
                }
            }

            // 事件推送（按订阅过滤）
            received = bus_rx.recv() => match received {
                Ok(event) => {
                    if subs.iter().any(|p| p.matches(&event.topic)) {
                        handle.push(Arc::new(ServerMessage::event(&event)));
                    }
                }
                Err(broadcast::error::RecvError::Lagged(skipped)) => {
                    // 客户端订阅者太少导致跟不上，属正常退化：丢事件而不是撑爆内存。
                    tracing::warn!(conn_id, skipped, "事件消费落后，已丢弃部分事件");
                }
                Err(broadcast::error::RecvError::Closed) => {
                    exit_reason = "事件总线已关闭";
                    break;
                }
            },

            // 入站帧
            incoming = stream.next() => match incoming {
                None => break,
                Some(Err(e)) => {
                    tracing::debug!(conn_id, error = %e, "读取帧失败");
                    exit_reason = "帧错误";
                    break;
                }
                Some(Ok(frame)) => {
                    last_seen = Instant::now();
                    match frame {
                        Message::Text(text) => {
                            handle_text(
                                &app,
                                &handle,
                                &inflight,
                                &mut subs,
                                conn_id,
                                &peer_str,
                                is_local,
                                text.as_str(),
                            );
                        }
                        Message::Ping(payload) => {
                            // 显式回 Pong：不同运行时的自动回包行为不一致，自己发更可靠。
                            handle.pong(payload.to_vec());
                        }
                        Message::Pong(_) => {}
                        Message::Close(_) => {
                            exit_reason = "对端主动关闭";
                            break;
                        }
                        Message::Binary(_) => {
                            handle.push(Arc::new(ServerMessage::Error {
                                id: None,
                                error: RpcError::bad_request("本协议只接受文本帧"),
                            }));
                        }
                    }
                }
            },
        }
    }

    // ---- 收尾 ----
    app.conns.unregister(conn_id).await;
    let _ = writer.await;
    app.bus.publish_from(
        Some("core"),
        topics::CONN_CLOSED,
        json!({ "conn_id": conn_id, "peer": peer_str, "reason": exit_reason, "connections": app.conns.count().await }),
    );
    tracing::info!(conn_id, peer = %peer_str, reason = exit_reason, "连接已断开");
}

/// 处理一帧文本：解析 → 分发 → 入队应答。
#[allow(clippy::too_many_arguments)]
fn handle_text(
    app: &AppState,
    handle: &ConnHandle,
    inflight: &Arc<Semaphore>,
    subs: &mut Vec<TopicPattern>,
    conn_id: u64,
    peer: &str,
    is_local: bool,
    text: &str,
) {
    let msg = match protocol::decode(text) {
        Ok(m) => m,
        Err(e) => {
            handle.push(Arc::new(ServerMessage::Error { id: None, error: e }));
            return;
        }
    };

    let id = msg.id();
    match msg {
        ClientMessage::Call { method, params, .. } => {
            // 并发闸门：拿不到许可立刻回 busy，而不是排队把连接拖死。
            let permit = match inflight.clone().try_acquire_owned() {
                Ok(p) => p,
                Err(_) => {
                    handle.push(Arc::new(ServerMessage::err(
                        id,
                        RpcError::busy(format!(
                            "在途调用已达上限（{}）",
                            app.config.server.max_inflight_calls
                        )),
                    )));
                    return;
                }
            };

            let app = app.clone();
            let handle = handle.clone();
            let peer = peer.to_string();
            let module = method.split('.').next().unwrap_or_default().to_string();

            // 慢方法不该阻塞心跳与其它调用，因此每次调用单独 spawn。
            tokio::spawn(async move {
                let _permit = permit;
                let started = Instant::now();
                let ctx = CallCtx {
                    app: app.clone(),
                    module,
                    method: method.clone(),
                    params,
                    conn_id,
                    peer,
                    is_local,
                };

                let result = app.registry.dispatch(ctx).await;
                let elapsed_ms = started.elapsed().as_millis() as u64;

                let message = match result {
                    Ok(value) => {
                        tracing::debug!(conn_id, method = %method, elapsed_ms, "调用成功");
                        ServerMessage::ok_timed(id, value, elapsed_ms)
                    }
                    Err(error) => {
                        tracing::debug!(conn_id, method = %method, elapsed_ms, code = %error.code, "调用失败");
                        ServerMessage::err_timed(id, error, elapsed_ms)
                    }
                };
                handle.push(Arc::new(message));
            });
        }

        ClientMessage::Subscribe { topic, .. } => {
            let result = add_subscription(subs, &topic, app.config.server.max_subscriptions);
            push_ack(handle, id, result, "subscribed", &topic);
        }

        ClientMessage::Unsubscribe { topic, .. } => {
            let before = subs.len();
            subs.retain(|p| p.as_str() != topic);
            let result = if subs.len() == before {
                Err(RpcError::new("not_subscribed", format!("未订阅 `{topic}`")))
            } else {
                Ok(json!({ "unsubscribed": true }))
            };
            push_ack(handle, id, result, "unsubscribed", &topic);
        }

        ClientMessage::Ping { .. } => {
            handle.push(Arc::new(ServerMessage::Pong { id, ts: now_ms() }));
        }

        ClientMessage::Hello {
            client, protocol, ..
        } => {
            if let Some(v) = protocol
                && v != PROTOCOL_VERSION
            {
                tracing::warn!(
                    conn_id,
                    client = client.as_deref().unwrap_or("?"),
                    client_protocol = v,
                    server_protocol = PROTOCOL_VERSION,
                    "客户端协议版本与服务端不一致"
                );
            }
            tracing::debug!(conn_id, client = ?client, "客户端握手");
            handle.push(Arc::new(ServerMessage::ok(
                id,
                json!({ "protocol": PROTOCOL_VERSION, "accepted": true }),
            )));
        }
    }
}

/// 加入订阅，去重并限流。
fn add_subscription(
    subs: &mut Vec<TopicPattern>,
    topic: &str,
    max: usize,
) -> Result<Value, RpcError> {
    if topic.trim().is_empty() {
        return Err(RpcError::invalid_params("topic 不能为空"));
    }
    if subs.iter().any(|p| p.as_str() == topic) {
        // 重复订阅当幂等处理，别让前端重连逻辑踩坑。
        return Ok(json!({ "topic": topic, "already": true }));
    }
    if subs.len() >= max {
        return Err(RpcError::busy(format!("订阅数已达上限（{max}）")));
    }
    subs.push(TopicPattern::new(topic));
    Ok(json!({ "topic": topic }))
}

fn push_ack(
    handle: &ConnHandle,
    id: MsgId,
    result: Result<Value, RpcError>,
    _kind: &str,
    topic: &str,
) {
    let message = match result {
        Ok(value) => ServerMessage::ok(id, value),
        Err(error) => ServerMessage::err(id, error),
    };
    tracing::trace!(topic, "订阅状态变更");
    handle.push(Arc::new(message));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subscribe_dedupes_and_reports_duplicate() {
        let mut subs = Vec::new();
        let v = add_subscription(&mut subs, "ticker.*", 4).unwrap();
        assert_eq!(v["topic"], json!("ticker.*"));
        assert_eq!(subs.len(), 1);

        let v = add_subscription(&mut subs, "ticker.*", 4).unwrap();
        assert_eq!(v["already"], json!(true));
        assert_eq!(subs.len(), 1, "重复订阅不该再占一个坑");
    }

    #[test]
    fn subscribe_respects_cap() {
        let mut subs = Vec::new();
        assert!(add_subscription(&mut subs, "a", 1).is_ok());
        let err = add_subscription(&mut subs, "b", 1).unwrap_err();
        assert_eq!(err.code, "busy");
    }

    #[test]
    fn empty_topic_rejected() {
        let mut subs = Vec::new();
        assert_eq!(
            add_subscription(&mut subs, "  ", 4).unwrap_err().code,
            "invalid_params"
        );
    }
}
