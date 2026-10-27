//! 主机终端：daemon 所在机器上的一个交互式 shell。
//!
//! 与实例控制台（`instance::process`）是两条独立的 PTY：控制台那个跑的是
//! Minecraft 服务端，这里跑的是系统 shell（`$SHELL` / bash / sh；Windows 上是
//! `cmd.exe`）。两者共用 [`crate::pty`] 里的历史与订阅层，协议也完全一样
//! （`history_begin` / 二进制历史 / `history_end` + state / 实时二进制 / `exit`），
//! 所以前端的终端组件不用为它写第二套解析。
//!
//! # 为什么只有一个会话
//!
//! 单会话（对齐 V1）：一个 daemon 一台机器，`/shell` 连上来就是那一个 shell。
//! 多客户端会共享同一条 PTY —— 谁敲的字都进同一个终端，历史也只有一份。
//!
//! # 生命周期
//!
//! * 第一条连接进来时若没在跑，自动起一个；
//! * 连接断开**不杀** shell（跑着的东西不该因为没人看就没了）；
//! * shell 自己 `exit` 后保留历史，下次连接自动重开；
//! * `shell.restart` 杀掉当前进程并立即重开（卡死时的逃生口）。

use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use axum::Router;
use axum::extract::WebSocketUpgrade;
use axum::extract::ws::{Message, WebSocket};
use axum::routing::get;
use futures_util::{SinkExt, StreamExt};
use portable_pty::{ChildKiller, CommandBuilder, MasterPty, PtySize, native_pty_system};
use serde_json::{Value, json};

use crate::error::Result;
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::pty::{Broadcast, Input, OutFrame, SUBSCRIBER_BUFFER, input_loop};
use crate::state::AppState;
use crate::util::now_ms;

/// PTY 输出历史的上限（与实例控制台一致）。
const HISTORY_BYTES: usize = 1024 * 1024;

/// 默认 PTY 尺寸；客户端连上后按自己的终端尺寸 resize。
const DEFAULT_COLS: u16 = 80;
const DEFAULT_ROWS: u16 = 24;

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

/// 一个在跑的 shell。
struct Run {
    /// 会话内唯一；等待线程靠它判断「要不要把自己的记录清掉」——
    /// 重开之后旧进程的退出线程**不能**把新一轮的记录清掉。
    id: u64,
    input: Sender<Input>,
    killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
    pid: Option<u32>,
    started_at_ms: u64,
}

/// 主机终端会话（全局唯一）。
pub struct ShellSession {
    broadcast: Mutex<Broadcast>,
    run: Mutex<Option<Run>>,
    next_sub: AtomicU64,
    next_run: AtomicU64,
    /// 上一次退出的退出码。
    last_exit: Mutex<Option<i32>>,
}

impl Default for ShellSession {
    fn default() -> Self {
        Self::new()
    }
}

impl ShellSession {
    pub fn new() -> Self {
        Self {
            broadcast: Mutex::new(Broadcast::new(HISTORY_BYTES)),
            run: Mutex::new(None),
            next_sub: AtomicU64::new(1),
            next_run: AtomicU64::new(1),
            last_exit: Mutex::new(None),
        }
    }

    /// 订阅输出：**原子地**取历史快照 + 注册订阅者。
    pub fn subscribe(&self, tx: tokio::sync::mpsc::Sender<OutFrame>) -> (Vec<u8>, u64) {
        let id = self.next_sub.fetch_add(1, Ordering::Relaxed);
        let mut state = self.broadcast.lock().unwrap_or_else(|e| e.into_inner());
        let snapshot = state.subscribe(id, tx);
        (snapshot, id)
    }

    pub fn unsubscribe(&self, sub_id: u64) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.unsubscribe(sub_id);
        }
    }

    /// 客户端敲的键 → PTY。shell 没在跑时直接忽略（前端会收到 exit 帧）。
    pub fn write(&self, data: Vec<u8>) {
        if let Some(run) = self
            .run
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| r.input.clone()))
        {
            let _ = run.send(Input::Data(data));
        }
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        if let Some(run) = self
            .run
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| r.input.clone()))
        {
            let _ = run.send(Input::Resize(cols, rows));
        }
    }

    /// 当前状态（给 `history_end` 与 `shell.status` 用）。
    ///
    /// 字段名与实例的 `RunInfo` 对齐（`phase` / `exit_code`），前端那套
    /// `PtyStatus.fromState` 才能直接吃。
    pub fn state(&self) -> Value {
        let running = self
            .run
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| (r.pid, r.started_at_ms)));
        match running {
            Some((pid, started_at_ms)) => json!({
                "phase": "running",
                "pid": pid,
                "started_at_ms": started_at_ms,
                "exit_code": Value::Null,
            }),
            None => {
                let exit_code = self.last_exit.lock().ok().and_then(|g| *g);
                json!({
                    "phase": "stopped",
                    "pid": Value::Null,
                    "exit_code": exit_code,
                })
            }
        }
    }

    /// 没有在跑就起一个（第一条连接 / 重启之后）。
    pub fn ensure_running(self: &Arc<Self>) -> std::result::Result<(), String> {
        let mut guard = self.run.lock().map_err(|_| "会话锁损坏".to_string())?;
        if guard.is_some() {
            return Ok(());
        }
        let run = spawn(self.clone())?;
        *guard = Some(run);
        Ok(())
    }

    /// 杀掉当前 shell；下一次连接会自动重开。
    pub fn kill(self: &Arc<Self>) -> std::result::Result<(), String> {
        let run = self
            .run
            .lock()
            .map_err(|_| "会话锁损坏".to_string())?
            .take();
        if let Some(run) = run
            && let Ok(mut killer) = run.killer.lock()
        {
            let _ = killer.kill();
        }
        Ok(())
    }

    /// 杀掉并立即重开（卡死时的逃生口）。
    pub fn restart(self: &Arc<Self>) -> std::result::Result<(), String> {
        self.kill()?;
        self.ensure_running()
    }

    /// 往终端里写一条提示（进历史）。
    fn notice(&self, text: &str) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.notice(text);
        }
    }

    /// 广播一条控制帧（`exit` 这类瞬时状态，不进历史）。
    fn control(&self, json: String) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.control(json);
        }
    }

    pub fn subscriber_count(&self) -> usize {
        self.broadcast
            .lock()
            .map(|s| s.subscriber_count())
            .unwrap_or(0)
    }
}

// ---------------------------------------------------------------------------
// 拉起 shell
// ---------------------------------------------------------------------------

fn spawn(session: Arc<ShellSession>) -> std::result::Result<Run, String> {
    let pty = native_pty_system();
    let pair = pty
        .openpty(PtySize {
            rows: DEFAULT_ROWS,
            cols: DEFAULT_COLS,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| format!("创建 PTY 失败：{e}"))?;

    let mut cmd = shell_command();
    if let Some(home) = home_dir() {
        cmd.cwd(home);
    }
    cmd.env("TERM", "xterm-256color");

    let mut child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| format!("拉起 shell 失败：{e}"))?;
    drop(pair.slave);

    let pid = child.process_id();
    let killer = child.clone_killer();
    let writer = pair
        .master
        .take_writer()
        .map_err(|e| format!("取 PTY writer 失败：{e}"))?;
    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|e| format!("取 PTY reader 失败：{e}"))?;
    let master: Arc<Mutex<Box<dyn MasterPty + Send>>> = Arc::new(Mutex::new(pair.master));

    let (input_tx, input_rx) = mpsc::channel::<Input>();
    let run_id = session.next_run.fetch_add(1, Ordering::Relaxed);

    let spawn_thread = |name: &str, f: Box<dyn FnOnce() + Send>| {
        let _ = std::thread::Builder::new().name(name.to_string()).spawn(f);
    };

    spawn_thread(
        "ec-shell-in",
        Box::new(move || input_loop(writer, master, input_rx)),
    );

    // 输出线程：阻塞读 PTY，进历史 + 扇给订阅者
    {
        let session = session.clone();
        spawn_thread(
            "ec-shell-out",
            Box::new(move || {
                let mut reader = reader;
                let mut buf = [0u8; 8192];
                loop {
                    match reader.read(&mut buf) {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            if let Ok(mut state) = session.broadcast.lock() {
                                state.append(buf[..n].to_vec());
                            }
                        }
                    }
                }
            }),
        );
    }

    // 等待线程：收尸、记退出码、推 exit 帧
    {
        let session = session.clone();
        spawn_thread(
            "ec-shell-wait",
            Box::new(move || {
                let code = child.wait().ok().map(|status| status.exit_code() as i32);
                if let Ok(mut guard) = session.run.lock()
                    && guard.as_ref().map(|r| r.id) == Some(run_id)
                {
                    *guard = None;
                }
                if let Ok(mut guard) = session.last_exit.lock() {
                    *guard = code;
                }
                let text = match code {
                    Some(code) => format!("[EdgeCube] shell 已退出（退出码 {code}）"),
                    None => "[EdgeCube] shell 已退出".to_string(),
                };
                session.notice(&text);
                session
                    .control(json!({"type": "exit", "code": code, "phase": "stopped"}).to_string());
            }),
        );
    }

    let run = Run {
        id: run_id,
        input: input_tx,
        killer: Mutex::new(killer),
        pid,
        started_at_ms: now_ms(),
    };
    session.notice(&format!(
        "[EdgeCube] 已打开主机终端{}",
        pid.map(|pid| format!("（pid {pid}）")).unwrap_or_default()
    ));
    Ok(run)
}

/// 起哪个 shell。
///
/// Unix 认 `$SHELL`（存在才用），否则 bash → sh；Windows 用 `COMSPEC`
/// （默认 `cmd.exe`）—— **不用 PowerShell**：ExecutionPolicy 与编码在
/// 不同机器上差异太大，`cmd` 才是「一定有、一定能进」的那个。
#[cfg(not(windows))]
fn shell_command() -> CommandBuilder {
    let program = std::env::var("SHELL")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && Path::new(value).is_file())
        .unwrap_or_else(|| {
            if Path::new("/bin/bash").is_file() {
                "/bin/bash".to_string()
            } else {
                "/bin/sh".to_string()
            }
        });
    CommandBuilder::new(program)
}

#[cfg(windows)]
fn shell_command() -> CommandBuilder {
    let program = std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string());
    CommandBuilder::new(program)
}

#[cfg(not(windows))]
fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

#[cfg(windows)]
fn home_dir() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE").map(PathBuf::from)
}

// ---------------------------------------------------------------------------
// WS 端点
// ---------------------------------------------------------------------------

/// 一条主机终端连接。协议与 `/pty/{id}` 完全一致（见 `instance::serve_pty`）：
///
/// * 服务端 → 客户端：`history_begin` → 二进制历史 → `history_end` + `state`
///   → 实时二进制 → `exit`；
/// * 客户端 → 服务端：二进制帧原样写进 PTY，文本帧 `{"resize":{…}}`。
async fn serve_shell(socket: WebSocket, session: Arc<ShellSession>) {
    // 没在跑就起一个；起不来就把原因写进历史，前端在终端里能看见。
    let started = match session.ensure_running() {
        Ok(()) => true,
        Err(error) => {
            session.notice(&format!("[EdgeCube] 主机终端启动失败：{error}"));
            false
        }
    };

    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) = tokio::sync::mpsc::channel::<OutFrame>(SUBSCRIBER_BUFFER);
    let (history, sub_id) = session.subscribe(tx);

    tracing::info!(
        history_bytes = history.len(),
        subscribers = session.subscriber_count(),
        started,
        "主机终端连接已建立"
    );

    let head = Message::Text(r#"{"type":"history_begin"}"#.into());
    if sender.send(head).await.is_err() {
        session.unsubscribe(sub_id);
        return;
    }
    if !history.is_empty() && sender.send(Message::Binary(history.into())).await.is_err() {
        session.unsubscribe(sub_id);
        return;
    }
    let state = session.state().to_string();
    let end = Message::Text(format!(r#"{{"type":"history_end","state":{state}}}"#).into());
    if sender.send(end).await.is_err() {
        session.unsubscribe(sub_id);
        return;
    }

    // 输出：订阅通道 → WS
    let output = tokio::spawn(async move {
        while let Some(frame) = rx.recv().await {
            let msg = match frame {
                OutFrame::Data(data) => Message::Binary(data.into()),
                OutFrame::Control(json) => Message::Text(json.into()),
            };
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    // 输入：WS → PTY
    let in_session = session.clone();
    let input = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Binary(data) => in_session.write(data.to_vec()),
                Message::Text(text) => {
                    let Ok(value) = serde_json::from_str::<Value>(&text) else {
                        continue;
                    };
                    if let Some(resize) = value.get("resize") {
                        let cols = resize.get("cols").and_then(Value::as_u64).unwrap_or(80);
                        let rows = resize.get("rows").and_then(Value::as_u64).unwrap_or(24);
                        in_session.resize(cols as u16, rows as u16);
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    tokio::select! {
        _ = output => {}
        _ = input => {}
    }
    session.unsubscribe(sub_id);
    tracing::info!("主机终端连接已断开");
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct ShellModule {
    session: Arc<ShellSession>,
}

impl ShellModule {
    pub fn new() -> Self {
        Self {
            session: Arc::new(ShellSession::new()),
        }
    }

    fn http_router(&self) -> Router<AppState> {
        let session = self.session.clone();
        Router::new().route(
            "/shell",
            get(move |upgrade: WebSocketUpgrade| {
                let session = session.clone();
                async move { upgrade.on_upgrade(move |socket| serve_shell(socket, session)) }
            }),
        )
    }
}

impl Default for ShellModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for ShellModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("shell", "主机终端", env!("CARGO_PKG_VERSION"))
            .description("daemon 所在机器上的交互式 shell：单会话、断线不杀、历史保留。")
            // 用户明确要「总是启用、不给开关」—— 卸载它就等于把入口藏了，
            // 前端会连到一个 404 上，不如让它一直在。
            .always_on()
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        {
            let session = self.session.clone();
            reg.method("shell.status", "主机终端的运行状态", move |_ctx| {
                let session = session.clone();
                async move { ok(session.state()) }
            });
        }
        {
            let session = self.session.clone();
            reg.method(
                "shell.restart",
                "结束当前主机终端并立即重开",
                move |_ctx| {
                    let session = session.clone();
                    async move {
                        let result = tokio::task::spawn_blocking(move || session.restart())
                            .await
                            .unwrap_or_else(|e| Err(format!("重启任务失败：{e}")));
                        match result {
                            Ok(()) => ok(restart_ack()),
                            Err(error) => Err(crate::error::RpcError::new(
                                "shell_restart",
                                format!("重启主机终端失败：{error}"),
                            )),
                        }
                    }
                },
            );
        }

        reg.router("shell", self.http_router());
        Ok(())
    }

    async fn start(&self, _env: ModuleEnv) -> Result<()> {
        // 不在 daemon 启动时抢起 shell：没人要看的时候挂一个空终端没意义。
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        self.session.kill().ok();
        Ok(())
    }
}

/// `shell.restart` 成功时回的内容。
///
/// 只回一句「已重开」，具体状态由 `shell.status` 或连接上的 `history_end` 给 ——
/// 重启是**同步**完成后才返回的，所以调用方拿到它时进程已经起好了。
fn restart_ack() -> Value {
    json!({"restarted": true})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_starts_as_stopped() {
        let session = ShellSession::new();
        let state = session.state();
        assert_eq!(state["phase"], "stopped");
        assert!(state["exit_code"].is_null());
    }

    #[test]
    fn subscribe_is_atomic_with_snapshot() {
        let session = ShellSession::new();
        {
            let mut state = session.broadcast.lock().unwrap();
            state.append(b"before".to_vec());
        }

        let (tx, mut rx) = tokio::sync::mpsc::channel(4);
        let (history, id) = session.subscribe(tx);
        assert_eq!(history, b"before");

        {
            let mut state = session.broadcast.lock().unwrap();
            state.append(b"after".to_vec());
        }
        match rx.try_recv() {
            Ok(OutFrame::Data(data)) => assert_eq!(data, b"after"),
            other => panic!("应当收到实时帧: {other:?}"),
        }

        session.unsubscribe(id);
        assert_eq!(session.subscriber_count(), 0);
    }

    #[test]
    fn state_reports_running_fields() {
        let session = ShellSession::new();
        {
            let mut guard = session.run.lock().unwrap();
            *guard = Some(Run {
                id: 1,
                input: mpsc::channel::<Input>().0,
                killer: Mutex::new(Box::new(NoopKiller) as Box<dyn ChildKiller + Send + Sync>),
                pid: Some(4321),
                started_at_ms: 99,
            });
        }
        let state = session.state();
        assert_eq!(state["phase"], "running");
        assert_eq!(state["pid"], 4321);
        assert_eq!(state["started_at_ms"], 99);
    }

    /// 只用来占位的 killer：`kill()` 什么都不做。
    #[derive(Debug)]
    struct NoopKiller;

    impl ChildKiller for NoopKiller {
        fn kill(&mut self) -> std::io::Result<()> {
            Ok(())
        }

        fn clone_killer(&self) -> Box<dyn ChildKiller + Send + Sync> {
            Box::new(NoopKiller)
        }
    }
}
