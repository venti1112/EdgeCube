//! 终端 WS 端点(契约 ws.md §5,/api/v1/ws/terminal)。
//!
//! 会话模型:每连接同时至多一个实例终端(`open` 自动替换旧会话);一个实例
//! 可被多连接同时打开(watcher 注册表,尺寸取全部 watcher 最小行列)。
//! PTY 输出经二进制帧下发(原始字节,pty 已按 outputEncoding 转码);
//! `open` 支持 `replay: true` 从实例落盘日志回放历史输出。未 open 不启动进程;
//! `open` 遇已停止实例即启动实例(守护进程模型,连接断开进程继续运行)。
//!
//! 帧格式:文本帧 JSON `{type,id,event,data}`(request/response/event);
//! 二进制帧 = 原始 PTY 字节(客户端 → stdin,stdout → 客户端)。

use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::json;
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::instance::InstanceStatus;
use crate::proc::ProcStateEvent;
use crate::server::AppState;

/// 未鉴权宽限(契约:6 秒内未完成鉴权断开)。
const AUTH_TIMEOUT: Duration = Duration::from_secs(6);
/// 输出/事件下发通道缓冲。
const OUT_CHANNEL: usize = 256;
/// open 回放默认行数上限(从落盘日志取末尾 N 行;对齐日志环容量)。
const REPLAY_MAX: usize = 2000;

/// 查询参数(token 免 header 方式)。
#[derive(Debug, Deserialize)]
pub struct TerminalQuery {
    pub token: Option<String>,
}

/// 校验 token(与 REST require_auth 同口径)。
async fn verify_token(state: &AppState, token: &str) -> bool {
    let auth = state.auth.lock().await;
    auth.verify_token(token)
}

/// GET /api/v1/ws/terminal:升级为 WS。
/// token 经 query 或 Authorization 头携带;携带但无效 → 直接 401 不升级;
/// 未携带 → 升级后 6s 内须发 `auth` 事件,超时断开。
pub async fn terminal_upgrade(
    State(state): State<AppState>,
    Query(query): Query<TerminalQuery>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    // query token 优先,其次 Authorization 头
    if let Some(token) = query.token.as_deref() {
        if !verify_token(&state, token).await {
            return (StatusCode::UNAUTHORIZED, "invalid token").into_response();
        }
        return ws.on_upgrade(move |socket| terminal_socket(state, socket, true));
    }
    if let Some(token) = super::server::bearer_token(&headers) {
        if !verify_token(&state, token).await {
            return (StatusCode::UNAUTHORIZED, "invalid token").into_response();
        }
        return ws.on_upgrade(move |socket| terminal_socket(state, socket, true));
    }
    // 未携带 token:升级后走 6s `auth` 事件宽限
    ws.on_upgrade(move |socket| terminal_socket(state, socket, false))
}

async fn terminal_socket(state: AppState, socket: WebSocket, pre_authenticated: bool) {
    let (mut ws_tx, mut ws_rx) = socket.split();
    let (out_tx, mut out_rx) = mpsc::channel::<Message>(OUT_CHANNEL);

    // 下发任务:多来源(响应/事件/PTY 二进制)统一经 out_tx 串行写出
    let writer = tokio::spawn(async move {
        while let Some(msg) = out_rx.recv().await {
            if ws_tx.send(msg).await.is_err() {
                break;
            }
        }
    });

    let conn_id = Uuid::new_v4();
    let mut authenticated = pre_authenticated;
    let auth_deadline = tokio::time::Instant::now() + AUTH_TIMEOUT;
    // 会话 = (instanceId, watcherId);广播接收端单独存放(select 分支各自可变借用)
    let mut session: Option<(Uuid, Uuid)> = None;
    let mut output_rx: Option<tokio::sync::broadcast::Receiver<Vec<u8>>> = None;
    let mut state_rx: Option<tokio::sync::broadcast::Receiver<ProcStateEvent>> = None;

    loop {
        let output_recv = async {
            match output_rx.as_mut() {
                Some(r) => r.recv().await,
                None => std::future::pending().await,
            }
        };
        let state_recv = async {
            match state_rx.as_mut() {
                Some(r) => r.recv().await,
                None => std::future::pending().await,
            }
        };

        tokio::select! {
            biased;

            // 鉴权宽限(已鉴权时分支停用)
            _ = tokio::time::sleep_until(auth_deadline), if !authenticated => {
                let _ = out_tx.send(error_frame("auth_timeout", "authentication timeout")).await;
                break;
            }

            // PTY 输出 → 二进制帧
            chunk = output_recv => match chunk {
                Ok(bytes) => {
                    if out_tx.send(Message::Binary(bytes.into())).await.is_err() { break; }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(_) => {
                    // 广播端已关闭(实例句柄被替换,如重启):断开,客户端重连
                    break;
                }
            },

            // 状态变化 → state 事件
            ev = state_recv => match ev {
                Ok(event) => {
                    let mut data = json!({"status": status_str(event.status)});
                    if let Some(code) = event.exit_code {
                        data["exitCode"] = json!(code);
                    }
                    let instance = session.as_ref().map(|(i, _)| *i);
                    let _ = out_tx.send(event_frame("state", instance, data)).await;
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(_) => break,
            },

            // 客户端帧
            frame = ws_rx.next() => match frame {
                None => break,
                Some(Err(_)) => break,
                Some(Ok(Message::Text(text))) => {
                    tracing::debug!(conn_id = %conn_id, len = text.len(), frame = %text, "terminal ws text frame");
                    if !handle_text(
                        &state, &out_tx, &conn_id, &mut authenticated,
                        &mut session, &mut output_rx, &mut state_rx, &text,
                    ).await {
                        break;
                    }
                }
                Some(Ok(Message::Binary(bytes))) => {
                    tracing::debug!(conn_id = %conn_id, len = bytes.len(), "terminal ws binary frame");
                    // 原始按键 → pty stdin
                    if let Some((instance_id, _)) = &session {
                        if let Some(handle) = state.procs.get(*instance_id) {
                            let _ = handle.write_bytes(&bytes).await;
                        }
                    }
                }
                Some(Ok(_)) => {} // ping/pong 控制帧由底层处理
            },
        }
    }

    tracing::debug!(conn_id = %conn_id, "terminal ws closed");
    // 清理:注销 watcher(实例进程不受连接生命周期影响)
    if let Some((instance_id, watcher_id)) = session.take() {
        if let Some(handle) = state.procs.get(instance_id) {
            let count = handle.remove_watcher(watcher_id).await;
            let _ = out_tx
                .send(event_frame("watchers", Some(instance_id), json!({"count": count})))
                .await;
        }
    }
    drop(out_tx);
    let _ = writer.await;
}

/// 处理一条文本帧;返回 false = 断开连接。
/// 会话 = (instanceId, watcherId);接收端在 open 时写回调用方。
#[allow(clippy::too_many_arguments)]
async fn handle_text(
    state: &AppState,
    out_tx: &mpsc::Sender<Message>,
    conn_id: &Uuid,
    authenticated: &mut bool,
    session: &mut Option<(Uuid, Uuid)>,
    output_rx: &mut Option<tokio::sync::broadcast::Receiver<Vec<u8>>>,
    state_rx: &mut Option<tokio::sync::broadcast::Receiver<ProcStateEvent>>,
    text: &str,
) -> bool {
    #[derive(Deserialize)]
    struct Req {
        #[serde(rename = "type", default)]
        _type: String,
        #[serde(default)]
        id: serde_json::Value,
        event: String,
        #[serde(default)]
        data: serde_json::Value,
    }
    let Ok(req) = serde_json::from_str::<Req>(text) else {
        let _ = out_tx
            .send(error_frame("unsupported_event", "malformed frame"))
            .await;
        return true;
    };
    let id = req.id.clone();

    // ── auth:未鉴权时仅放行 auth/ping ─────────────────────────
    if !*authenticated && req.event != "auth" && req.event != "ping" {
        let _ = out_tx
            .send(response_error(id, "not_authenticated", "authenticate first"))
            .await;
        return true;
    }

    match req.event.as_str() {
        "ping" => {
            let _ = out_tx
                .send(response_ok(id, json!({"pong": true})))
                .await;
        }
        "auth" => {
            #[derive(Deserialize)]
            struct AuthData {
                #[serde(default)]
                token: String,
            }
            let data: AuthData = serde_json::from_value(req.data).unwrap_or(AuthData {
                token: String::new(),
            });
            if verify_token(state, &data.token).await {
                *authenticated = true;
                let _ = out_tx.send(response_ok(id, json!({"authenticated": true}))).await;
            } else {
                let _ = out_tx
                    .send(response_error(id, "not_authenticated", "invalid token"))
                    .await;
            }
        }
        "open" => {
            open_session(state, out_tx, conn_id, session, output_rx, state_rx, &id, &req.data).await;
        }
        "write" => {
            #[derive(Deserialize)]
            struct WriteData {
                #[serde(default)]
                input: String,
            }
            let data: WriteData = serde_json::from_value(req.data).unwrap_or(WriteData {
                input: String::new(),
            });
            let result = match session {
                Some((instance_id, _)) => match state.procs.get(*instance_id) {
                    Some(handle) => handle.write_bytes(data.input.as_bytes()).await,
                    None => Err(crate::proc::ProcError::NotRunning),
                },
                None => Err(crate::proc::ProcError::NotRunning),
            };
            let _ = out_tx.send(match result {
                Ok(()) => response_ok(id, json!({})),
                Err(e) => response_error(id, e.code(), &proc_msg(&e)),
            }).await;
        }
        "input" => {
            #[derive(Deserialize)]
            struct InputData {
                #[serde(default)]
                command: String,
            }
            let data: InputData = serde_json::from_value(req.data).unwrap_or(InputData {
                command: String::new(),
            });
            let result = match session {
                Some((instance_id, _)) => match state.procs.get(*instance_id) {
                    Some(handle) => handle.write_line(&data.command).await,
                    None => Err(crate::proc::ProcError::NotRunning),
                },
                None => Err(crate::proc::ProcError::NotRunning),
            };
            let _ = out_tx.send(match result {
                Ok(()) => response_ok(id, json!({})),
                Err(e) => response_error(id, e.code(), &proc_msg(&e)),
            }).await;
        }
        "resize" => {
            #[derive(Deserialize)]
            struct ResizeData {
                #[serde(default)]
                cols: u32,
                #[serde(default)]
                rows: u32,
            }
            let data: ResizeData = serde_json::from_value(req.data).unwrap_or(ResizeData { cols: 0, rows: 0 });
            if let Some((instance_id, watcher_id)) = *session {
                if let Some(handle) = state.procs.get(instance_id) {
                    let count = handle.update_watcher(watcher_id, data.cols, data.rows).await;
                    let _ = out_tx
                        .send(event_frame("watchers", Some(instance_id), json!({"count": count})))
                        .await;
                }
            }
            let _ = out_tx.send(response_ok(id, json!({}))).await;
        }
        "close" => {
            if let Some((instance_id, watcher_id)) = session.take() {
                *output_rx = None;
                *state_rx = None;
                if let Some(handle) = state.procs.get(instance_id) {
                    let count = handle.remove_watcher(watcher_id).await;
                    let _ = out_tx
                        .send(event_frame("watchers", Some(instance_id), json!({"count": count})))
                        .await;
                }
            }
            let _ = out_tx.send(response_ok(id, json!({}))).await;
        }
        "detail" => {
            let data = match session {
                Some((instance_id, _)) => match state.procs.get(*instance_id) {
                    Some(handle) => {
                        let snap = handle.snapshot();
                        json!({
                            "instanceId": instance_id,
                            "status": status_str(snap.status),
                            "pid": snap.pid,
                            "watchers": handle.watcher_count(),
                        })
                    }
                    None => json!({"instanceId": instance_id, "status": "stopped", "watchers": 0}),
                },
                None => json!({"status": "stopped", "watchers": 0}),
            };
            let _ = out_tx.send(response_ok(id, data)).await;
        }
        other => {
            let _ = out_tx
                .send(response_error(id, "unsupported_event", &format!("unknown event: {other}")))
                .await;
        }
    }
    true
}

/// open:取句柄或启动实例 → 注册 watcher → 响应 opened → 回放。
/// 返回 false = 断开(不该发生;错误经帧回传)。
async fn open_session(
    state: &AppState,
    out_tx: &mpsc::Sender<Message>,
    conn_id: &Uuid,
    session: &mut Option<(Uuid, Uuid)>,
    output_rx: &mut Option<tokio::sync::broadcast::Receiver<Vec<u8>>>,
    state_rx: &mut Option<tokio::sync::broadcast::Receiver<ProcStateEvent>>,
    id: &serde_json::Value,
    data: &serde_json::Value,
) {
    #[derive(Deserialize)]
    struct OpenData {
        #[serde(default)]
        instanceId: String,
        #[serde(default)]
        cols: Option<u32>,
        #[serde(default)]
        rows: Option<u32>,
        #[serde(default = "default_true")]
        replay: bool,
    }
    fn default_true() -> bool {
        true
    }
    let Ok(data) = serde_json::from_value::<OpenData>(data.clone()) else {
        let _ = out_tx.send(response_error(id.clone(), "instance_not_found", "instanceId required")).await;
        return;
    };
    let Ok(instance_id) = Uuid::parse_str(&data.instanceId) else {
        let _ = out_tx
            .send(response_error(id.clone(), "instance_not_found", "invalid instanceId"))
            .await;
        return;
    };

    if state.instances.get_config(instance_id).await.is_none() {
        let _ = out_tx
            .send(response_error(id.clone(), "instance_not_found", "instance not found"))
            .await;
        return;
    };

    // 取句柄;实例未运行(无句柄或已结束)时不自动启动:回放历史日志、
    // 返回 stopped,启动由用户显式发起。
    let Some(handle) = state.procs.get(instance_id).filter(|h| !h.is_done()) else {
        if data.replay {
            let lines: Vec<serde_json::Value> = state
                .procs
                .replay_log(instance_id, REPLAY_MAX)
                .await
                .into_iter()
                .enumerate()
                .map(|(seq, text)| json!({"seq": seq, "text": text}))
                .collect();
            let _ = out_tx
                .send(event_frame("replay", Some(instance_id), json!({"lines": lines, "nextSeq": lines.len()})))
                .await;
        }
        let _ = out_tx
            .send(response_ok(
                id.clone(),
                json!({"opened": {
                    "instanceId": instance_id,
                    "pid": null,
                    "status": "stopped",
                    "sessionId": null,
                    "watchers": 0,
                }}),
            ))
            .await;
        return;
    };

    // 替换旧会话:注销旧 watcher(可能是另一实例)
    if let Some((old_instance, old_watcher)) = session.take() {
        if let Some(old_handle) = state.procs.get(old_instance) {
            old_handle.remove_watcher(old_watcher).await;
        }
    }

    let cols = data.cols.unwrap_or(120);
    let rows = data.rows.unwrap_or(40);
    let watcher_id = *conn_id;
    let count = handle.add_watcher(watcher_id, cols, rows).await;

    let snap = handle.snapshot();
    *session = Some((instance_id, watcher_id));
    *output_rx = Some(handle.output_tx.subscribe());
    *state_rx = Some(handle.state_tx.subscribe());

    // 响应:opened
    let _ = out_tx
        .send(response_ok(
            id.clone(),
            json!({"opened": {
                "instanceId": instance_id,
                "pid": snap.pid,
                "status": status_str(snap.status),
                "sessionId": watcher_id,
                "watchers": count,
            }}),
        ))
        .await;
    // watcher 数变化
    let _ = out_tx
        .send(event_frame("watchers", Some(instance_id), json!({"count": count})))
        .await;

    // 回放(契约:replay 事件 → state 事件 → 实时二进制)。
    // 数据源 = 实例落盘日志(全部日志文件按时间序拼接,取末尾 REPLAY_MAX 行),
    // 使 daemon 重启 / 多轮启动的历史输出也能在进入控制台时完整呈现。
    if data.replay {
        let lines: Vec<serde_json::Value> = state
            .procs
            .replay_log(instance_id, REPLAY_MAX)
            .await
            .into_iter()
            .enumerate()
            .map(|(seq, text)| json!({"seq": seq, "text": text}))
            .collect();
        let _ = out_tx
            .send(event_frame("replay", Some(instance_id), json!({"lines": lines, "nextSeq": lines.len()})))
            .await;
    }
    let mut state_data = json!({"status": status_str(snap.status)});
    if let Some(code) = snap.exit_code {
        state_data["exitCode"] = json!(code);
    }
    let _ = out_tx
        .send(event_frame("state", Some(instance_id), state_data))
        .await;
}

fn status_str(status: InstanceStatus) -> &'static str {
    match status {
        InstanceStatus::Busy => "busy",
        InstanceStatus::Stopped => "stopped",
        InstanceStatus::Stopping => "stopping",
        InstanceStatus::Starting => "starting",
        InstanceStatus::Running => "running",
    }
}

fn proc_msg(e: &crate::proc::ProcError) -> String {
    match e {
        crate::proc::ProcError::Busy => "instance is already starting/running".into(),
        crate::proc::ProcError::NotRunning => "instance is not running".into(),
        crate::proc::ProcError::Spawn(m) => m.clone(),
    }
}

fn response_ok(id: serde_json::Value, data: serde_json::Value) -> Message {
    Message::Text(json!({"type": "response", "id": id, "status": "ok", "data": data}).to_string().into())
}

fn response_error(id: serde_json::Value, code: &str, message: &str) -> Message {
    Message::Text(
        json!({"type": "response", "id": id, "status": "error", "data": {"code": code, "message": message}})
            .to_string()
            .into(),
    )
}

fn event_frame(event: &str, instance_id: Option<Uuid>, data: serde_json::Value) -> Message {
    let ts = chrono::Utc::now().timestamp_millis();
    let mut frame = json!({"type": "event", "event": event, "data": data, "ts": ts});
    if let Some(id) = instance_id {
        frame["instanceId"] = json!(id);
    }
    Message::Text(frame.to_string().into())
}

fn error_frame(code: &str, message: &str) -> Message {
    Message::Text(json!({"type": "error", "code": code, "message": message}).to_string().into())
}
