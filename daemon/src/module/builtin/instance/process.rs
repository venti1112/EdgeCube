//! 实例的进程管理：PTY 会话 + 启动 / 停止 / 强制停止。
//!
//! # 方案来自 `pty-terminal-demo`
//!
//! 三件事照抄那个 demo 验证过的做法：
//!
//! 1. **PTY 用 [`portable_pty`]**（不是 `std::process` + 管道）：服务端大多按
//!    「是不是终端」判断要不要开控制台，管道会让它退化成非交互模式 ——
//!    Minecraft 的 JLine 控制台、PocketMine 的交互提示都依赖真 tty。
//! 2. **输出保留一段环形历史**（[`Broadcast`]，默认 8 KiB）：控制台随时连上来
//!    都能看到之前的输出，而不是从空白开始。
//! 3. **「取历史快照」与「注册订阅者」在同一把锁里原子完成**：分两步做必然
//!    要么在两步之间漏掉一帧，要么把这帧发两遍。demo 里那句注释说得对，
//!    这是关键。
//!
//! 与 demo 的差别：
//!
//! * 会话按**实例 id** 分，不是一个固定的 "demo" 会话；
//! * 订阅通道用 `tokio::sync::mpsc`，WS 任务直接 `await`，不用再起一个搬运任务；
//! * 退出/状态这类**控制消息**与**原始输出**走同一条通道（[`OutFrame`]），
//!   保证顺序 —— 客户端按帧类型区分即可；
//! * 会话**跨 WS 断开保留、跨重启保留历史**，能连着看两轮。
//!
//! # 线程模型
//!
//! PTY 读写都是阻塞 IO，所以用 `std::thread`：
//!
//! | 线程 | 干什么 |
//! | --- | --- |
//! | 输入 | 从 `std::sync::mpsc` 收字节 / resize，写进 PTY |
//! | 输出 | 阻塞读 PTY，进历史、扇给订阅者、扫「就绪」标记 |
//! | 等待 | `child.wait()`，退出了就落阶段、推事件、必要时自动重启 |
//!
//! 事件往 `app.bus` 发（`broadcast::Sender` 本来就线程安全），这几个线程不需要
//! tokio 运行时。

use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use portable_pty::{Child, ChildKiller, CommandBuilder, MasterPty, PtySize, native_pty_system};
use tokio::sync::mpsc::Sender as TokioSender;

use super::model::{InstanceConfig, ServerPhase, stop_payload};
use super::players::OnlinePlayers;
use crate::pty::{Broadcast, Input, OutFrame, input_loop};
use crate::state::AppState;
use crate::util::now_ms;

/// 阶段变化事件。控制台与实例卡片都靠它刷新。
pub const TOPIC_PHASE: &str = "instance.phase";

/// 在线玩家变化事件（加入 / 退出 / `list` 响应 / 退出进程清空）。
pub const TOPIC_PLAYERS: &str = "instance.players";

/// PTY 输出历史的上限（字节）。
const DEFAULT_HISTORY_BYTES: usize = 1024 * 1024;

/// 默认 PTY 尺寸；客户端连上后会按自己的终端尺寸 resize。
const DEFAULT_COLS: u16 = 80;
const DEFAULT_ROWS: u16 = 24;

/// 判定「服务端就绪」的输出标记。
///
/// Minecraft 系服务端起完会打印
/// `Done (1.234s)! For help, type "help"`。非标准服务端用「兼容模式」跳过这个
/// 判定（进程一起来就算运行中）。
const READY_MARKER: &str = "Done (";

/// 就绪标记的扫描窗口：只看最近这么多字节。
const READY_SCAN_BYTES: usize = 512;

/// 自动重启前的等待，避免「秒退 → 秒起」把 CPU 打满。
const AUTO_RESTART_DELAY: Duration = Duration::from_secs(1);

/// 同一轮启动里自动重启的次数上限。
///
/// 没有上限的话，一条「跑完就退」的命令会变成死循环，用户只能看着 CPU 烧起来。
/// 到顶就停下，控制台里留下说明。
const MAX_AUTO_RESTARTS: u32 = 10;

// ---------------------------------------------------------------------------
// 帧
// ---------------------------------------------------------------------------

/// 进程操作失败的原因。
///
/// 做成枚举而不是字符串，是为了让上层能给出**稳定的错误码** ——
/// 前端按码分支，不靠匹配 message（daemon README 里那条约定）。
#[derive(Debug)]
pub enum ProcessError {
    /// 没配启动命令。
    NotConfigured,
    /// 已经在跑了。
    AlreadyRunning { pid: Option<u32> },
    /// 没在跑。
    NotRunning,
    /// 拉起失败（PTY、spawn、起线程……）。
    Spawn(String),
    /// 配置里没有可用的停止命令。
    NoStopCommand,
    /// 杀进程失败。
    Kill(String),
}

impl ProcessError {
    /// 稳定的错误码。
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotConfigured => "instance_not_configured",
            Self::AlreadyRunning { .. } => "instance_already_running",
            Self::NotRunning => "instance_not_running",
            Self::Spawn(_) => "instance_start_failed",
            Self::NoStopCommand => "instance_stop_command_missing",
            Self::Kill(_) => "instance_kill_failed",
        }
    }
}

impl std::fmt::Display for ProcessError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotConfigured => write!(f, "未配置启动命令，无法启动"),
            Self::AlreadyRunning { pid } => match pid {
                Some(pid) => write!(f, "实例已经在运行（pid {pid}）"),
                None => write!(f, "实例已经在运行"),
            },
            Self::NotRunning => write!(f, "实例没在运行"),
            Self::Spawn(detail) => write!(f, "{detail}"),
            Self::NoStopCommand => {
                write!(f, "没有可用的停止命令，请改用强制停止")
            }
            Self::Kill(detail) => write!(f, "强制停止失败：{detail}"),
        }
    }
}

impl std::error::Error for ProcessError {}

// ---------------------------------------------------------------------------
// 运行信息
// ---------------------------------------------------------------------------

/// 一轮运行的快照（给 `instance.status` 与控制台用）。
#[derive(Debug, Clone, serde::Serialize)]
pub struct RunInfo {
    pub phase: ServerPhase,
    /// 进程 id；没在跑时为 `None`。
    pub pid: Option<u32>,
    /// 上一次退出的退出码。
    pub exit_code: Option<i32>,
    /// 本轮启动时刻（Unix 毫秒）。
    pub started_at_ms: Option<u64>,
    /// 本轮结束时刻。
    pub stopped_at_ms: Option<u64>,
    /// 是我们主动要求停的（用来区分「正常停止」与「异常退出」）。
    pub stop_requested: bool,
    /// 本轮已经自动重启过几次。
    pub auto_restarts: u32,
}

impl Default for RunInfo {
    fn default() -> Self {
        Self {
            phase: ServerPhase::Stopped,
            pid: None,
            exit_code: None,
            started_at_ms: None,
            stopped_at_ms: None,
            stop_requested: false,
            auto_restarts: 0,
        }
    }
}

impl RunInfo {
    /// 进程是否活着（含过渡态）。
    pub fn alive(&self) -> bool {
        !matches!(self.phase, ServerPhase::Stopped | ServerPhase::Crashed)
    }
}

/// 一轮运行持有的句柄。
struct Run {
    input: Sender<Input>,
    killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
    /// 与输出/等待线程共享。
    info: Arc<Mutex<RunInfo>>,
}

/// 起一轮进程需要的东西（在等待线程里自动重启时还要用）。
struct Launch {
    config: InstanceConfig,
    dir: PathBuf,
    command: String,
    attempt: u32,
}

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

/// 一个实例的 PTY 会话。
///
/// **跨运行保留**：输出历史、订阅者、上一次的退出信息都留着 —— 控制台断了再连、
/// 服务端停了再起，都能接着看。
pub struct Session {
    pub instance_id: String,
    broadcast: Mutex<Broadcast>,
    /// 当前这一轮；`None` = 没在跑。
    run: Mutex<Option<Run>>,
    /// 最近一次运行的信息（`run` 为 `None` 时就靠它）。
    last: Mutex<RunInfo>,
    next_sub: AtomicU64,
    /// 本轮已自动重启次数（手动启动时清零）。
    auto_restarts: AtomicU32,
    /// 在线玩家（从输出里解析出来的那份状态，见 [`players`](super::players)）。
    ///
    /// 挂在会话上而不是运行轮次上：控制台断开、进程重启都不影响它，
    /// 进程退出时由 [`Session::clear_players`] 清空。
    online: Mutex<OnlinePlayers>,
}

impl Session {
    fn new(instance_id: impl Into<String>) -> Self {
        Self {
            instance_id: instance_id.into(),
            broadcast: Mutex::new(Broadcast::new(DEFAULT_HISTORY_BYTES)),
            run: Mutex::new(None),
            last: Mutex::new(RunInfo::default()),
            next_sub: AtomicU64::new(1),
            auto_restarts: AtomicU32::new(0),
            online: Mutex::new(OnlinePlayers::new()),
        }
    }

    /// 当前状态：在跑看运行的，没在跑看上一次的。
    pub fn info(&self) -> RunInfo {
        let running = self
            .run
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| r.info.clone()));
        match running {
            Some(info) => info.lock().map(|i| i.clone()).unwrap_or_default(),
            None => self.last.lock().map(|i| i.clone()).unwrap_or_default(),
        }
    }

    /// 输入通道；没在跑时是 `None`。
    fn input_sender(&self) -> Option<Sender<Input>> {
        self.run.lock().ok()?.as_ref().map(|r| r.input.clone())
    }

    /// 往 PTY 里写原始字节（用户在控制台敲的键）。
    pub fn write(&self, data: Vec<u8>) -> Result<(), ProcessError> {
        let tx = self.input_sender().ok_or(ProcessError::NotRunning)?;
        // std 的无界通道，send 不会阻塞
        tx.send(Input::Data(data))
            .map_err(|_| ProcessError::NotRunning)
    }

    /// 调整 PTY 尺寸。
    pub fn resize(&self, cols: u16, rows: u16) -> Result<(), ProcessError> {
        let tx = self.input_sender().ok_or(ProcessError::NotRunning)?;
        tx.send(Input::Resize(cols, rows))
            .map_err(|_| ProcessError::NotRunning)
    }

    /// 订阅输出：**原子地**取历史快照 + 注册订阅者，返回 `(快照, 订阅 id)`。
    pub fn subscribe(&self, tx: TokioSender<OutFrame>) -> (Vec<u8>, u64) {
        let id = self.next_sub.fetch_add(1, Ordering::Relaxed);
        let mut state = self.broadcast.lock().unwrap_or_else(|e| e.into_inner());
        let snapshot = state.subscribe(id, tx);
        (snapshot, id)
    }

    /// 退订。PTY 继续跑 —— 断开连接不等于停进程（照 demo）。
    pub fn unsubscribe(&self, sub_id: u64) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.unsubscribe(sub_id);
        }
    }

    /// 清掉输出历史（控制台的「清屏」）。
    pub fn clear_history(&self) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.clear();
        }
    }

    /// 往控制台里写一条提示。
    fn notice(&self, text: &str) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.notice(text);
        }
    }

    /// 给所有订阅者广播一条控制消息。
    fn control(&self, json: String) {
        if let Ok(mut state) = self.broadcast.lock() {
            state.control(json);
        }
    }

    /// 订阅者数量（测试/自省用）。
    pub fn subscriber_count(&self) -> usize {
        self.broadcast
            .lock()
            .map(|s| s.subscriber_count())
            .unwrap_or(0)
    }

    /// 喂一块输出给在线玩家跟踪器；返回名单是否因此变了。
    ///
    /// 由输出线程调用 —— 解析必须在**读到的当下**做：控制台历史是有上限的，
    /// 谁都不能靠「回看历史」把事件补回来（见 [`super::players`]）。
    pub fn feed_players(&self, chunk: &[u8]) -> bool {
        match self.online.lock() {
            Ok(mut state) => state.feed(chunk),
            Err(_) => false,
        }
    }

    /// 当前在线玩家（插入序）。
    pub fn online_players(&self) -> Vec<String> {
        self.online
            .lock()
            .map(|state| state.names().to_vec())
            .unwrap_or_default()
    }

    /// 清空在线玩家；返回之前是否有内容。
    fn clear_players(&self) -> bool {
        self.online.lock().map(|mut s| s.clear()).unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// 进程管理器
// ---------------------------------------------------------------------------

/// 实例 id → PTY 会话。
#[derive(Default)]
pub struct ProcessManager {
    sessions: Mutex<HashMap<String, Arc<Session>>>,
}

impl std::fmt::Debug for ProcessManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProcessManager")
            .field("sessions", &self.len())
            .finish()
    }
}

impl ProcessManager {
    /// 取已有会话。
    pub fn get(&self, id: &str) -> Option<Arc<Session>> {
        self.sessions.lock().ok()?.get(id).cloned()
    }

    /// 取会话，没有就建一个空会话。
    ///
    /// 控制台连上来时用：即使进程没在跑，也要有地方挂历史与退出信息。
    pub fn ensure(&self, id: &str) -> Arc<Session> {
        let mut sessions = self.sessions.lock().unwrap_or_else(|e| e.into_inner());
        sessions
            .entry(id.to_string())
            .or_insert_with(|| Arc::new(Session::new(id)))
            .clone()
    }

    /// 丢掉会话（删除实例时用）。
    pub fn remove(&self, id: &str) -> Option<Arc<Session>> {
        self.sessions
            .lock()
            .ok()
            .and_then(|mut sessions| sessions.remove(id))
    }

    pub fn len(&self) -> usize {
        self.sessions.lock().map(|s| s.len()).unwrap_or(0)
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

// ---------------------------------------------------------------------------
// 启动 / 停止
// ---------------------------------------------------------------------------

/// 启动一个实例的进程。
pub fn start(
    manager: &ProcessManager,
    app: &AppState,
    config: &InstanceConfig,
    dir: &Path,
) -> Result<RunInfo, ProcessError> {
    let command = config
        .startup_command()
        .ok_or(ProcessError::NotConfigured)?
        .to_string();

    let session = manager.ensure(&config.id);
    let existing = session.info();
    if existing.alive() {
        return Err(ProcessError::AlreadyRunning { pid: existing.pid });
    }

    session.auto_restarts.store(0, Ordering::Relaxed);
    let launch = Launch {
        config: config.clone(),
        dir: dir.to_path_buf(),
        command,
        attempt: 0,
    };
    session.notice(&format!("[EdgeCube] 启动 `{}` …", launch.command));
    match spawn_run(&session, app, &launch) {
        Ok(info) => Ok(info),
        Err(e) => {
            session.notice(&format!("[EdgeCube] 启动失败：{e}"));
            Err(e)
        }
    }
}

/// 拉起一轮进程。
fn spawn_run(
    session: &Arc<Session>,
    app: &AppState,
    launch: &Launch,
) -> Result<RunInfo, ProcessError> {
    let pty = native_pty_system();
    let pair = pty
        .openpty(PtySize {
            rows: DEFAULT_ROWS,
            cols: DEFAULT_COLS,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| ProcessError::Spawn(format!("创建 PTY 失败: {e}")))?;

    let mut cmd = shell_command(&launch.command);
    cmd.cwd(&launch.dir);
    cmd.env("TERM", "xterm-256color");
    let child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| ProcessError::Spawn(format!("拉起进程失败: {e}")))?;
    drop(pair.slave);

    let pid = child.process_id();
    let killer = child.clone_killer();
    let writer = pair
        .master
        .take_writer()
        .map_err(|e| ProcessError::Spawn(format!("取 PTY writer 失败: {e}")))?;
    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|e| ProcessError::Spawn(format!("取 PTY reader 失败: {e}")))?;
    let master: Arc<Mutex<Box<dyn MasterPty + Send>>> = Arc::new(Mutex::new(pair.master));

    let info = Arc::new(Mutex::new(RunInfo {
        phase: if launch.config.compat_mode {
            // 兼容模式：不认那个 Done 标记，进程起来就算运行中
            ServerPhase::Running
        } else {
            ServerPhase::Starting
        },
        pid,
        started_at_ms: Some(now_ms()),
        auto_restarts: launch.attempt,
        ..RunInfo::default()
    }));

    let (input_tx, input_rx) = mpsc::channel::<Input>();

    // 先把这一轮挂上，再起线程：等待线程可能在任何一刻收尾，
    // 反过来的话它写的 `None` 会被我们随后写的 `Some` 覆盖掉。
    {
        let mut guard = session
            .run
            .lock()
            .map_err(|_| ProcessError::Spawn("会话锁损坏".into()))?;
        *guard = Some(Run {
            input: input_tx,
            killer: Mutex::new(killer),
            info: info.clone(),
        });
    }

    let spawn_thread = |name: String, f: Box<dyn FnOnce() + Send>| -> Result<(), ProcessError> {
        std::thread::Builder::new()
            .name(name)
            .spawn(f)
            .map(|_| ())
            .map_err(|e| ProcessError::Spawn(format!("起线程失败: {e}")))
    };

    let id = launch.config.id.clone();
    let out_session = session.clone();
    let out_info = info.clone();
    let out_app = app.clone();
    let wait_session = session.clone();
    let wait_info = info.clone();
    let wait_app = app.clone();
    let wait_launch = Launch {
        config: launch.config.clone(),
        dir: launch.dir.clone(),
        command: launch.command.clone(),
        attempt: launch.attempt,
    };

    let launched = spawn_thread(
        format!("ec-pty-in-{id}"),
        Box::new(move || input_loop(writer, master, input_rx)),
    )
    .and_then(|()| {
        spawn_thread(
            format!("ec-pty-out-{id}"),
            Box::new(move || output_loop(reader, out_session, out_info, out_app)),
        )
    })
    .and_then(|()| {
        spawn_thread(
            format!("ec-pty-wait-{id}"),
            Box::new(move || wait_loop(child, wait_session, wait_info, wait_app, wait_launch)),
        )
    });

    if let Err(e) = launched {
        // 半死不活的会话比没有更糟：清掉，让用户能重试。
        // （起线程失败基本只可能是内存耗尽；这种时候连进程都未必收得干净，
        //   所以这里只保证「状态不骗人」。）
        if let Ok(mut run) = session.run.lock() {
            *run = None;
        }
        return Err(e);
    }

    let snapshot = info.lock().map(|i| i.clone()).unwrap_or_default();
    if let Ok(mut last) = session.last.lock() {
        *last = snapshot.clone();
    }
    publish(app, &session.instance_id, &snapshot);
    Ok(snapshot)
}

/// 停止（优雅）：把停止命令写进 PTY。
pub fn stop(
    session: &Arc<Session>,
    config: &InstanceConfig,
    app: &AppState,
) -> Result<(), ProcessError> {
    let info = session.info();
    if !info.alive() {
        return Err(ProcessError::NotRunning);
    }
    let payload = stop_payload(Some(config.stop_command()), &config.line_ending)
        .ok_or(ProcessError::NoStopCommand)?;

    // 先落「停止中」再写命令：反过来可能命令刚发出进程就没了，
    // 那个窗口里状态还是「运行中」，前端会闪一下。
    transition(session, app, ServerPhase::Stopping, true);
    session.write(payload)
}

/// 强制停止：直接杀。
///
/// Unix 上额外给整个进程组补一刀 SIGKILL —— PTY 的子进程被 `setsid()` 提成了
/// 会话首进程（pgid == pid），所以 `sh -c` 里再 fork 出来的子孙也能一起清掉。
pub fn kill(session: &Arc<Session>, app: &AppState) -> Result<(), ProcessError> {
    let info = session.info();
    if !info.alive() {
        return Err(ProcessError::NotRunning);
    }
    transition(session, app, ServerPhase::Stopping, true);

    // 守卫要活到 killer 用完（借出去会被当成悬垂）
    let run_guard = session
        .run
        .lock()
        .map_err(|_| ProcessError::Kill("会话锁损坏".into()))?;
    let Some(run) = run_guard.as_ref() else {
        return Err(ProcessError::NotRunning);
    };
    let mut killer = run
        .killer
        .lock()
        .map_err(|_| ProcessError::Kill("杀进程句柄损坏".into()))?;
    let result = killer.kill().map_err(|e| ProcessError::Kill(e.to_string()));
    drop(killer);
    drop(run_guard);

    #[cfg(unix)]
    if let Some(pid) = info.pid {
        kill_process_group(pid);
    }
    result
}

/// 给整个进程组补一刀（见 [`kill`]）。
#[cfg(unix)]
fn kill_process_group(pid: u32) {
    // SAFETY: 只是把两个整数交给 kill(2)；失败也无所谓（进程可能已经没了）。
    unsafe {
        libc::kill(-(pid as i32), libc::SIGKILL);
    }
}

/// 静默收掉一个会话（删除实例时用）：不等事件、不发通知，杀掉就走。
///
/// 调用方接着要 `ProcessManager::remove(id)` —— 会话连着 PTY 一起被丢掉，
/// PTY 一关子进程就没有控制终端了，内核会给它的前台进程组补一发 SIGHUP。
pub fn shutdown_quiet(session: &Session) {
    let Ok(guard) = session.run.lock() else {
        return;
    };
    let Some(run) = guard.as_ref() else { return };
    if let Ok(mut killer) = run.killer.lock() {
        let _ = killer.kill();
    }
    let pid = run.info.lock().ok().and_then(|i| i.pid);
    #[cfg(unix)]
    if let Some(pid) = pid {
        kill_process_group(pid);
    }
    #[cfg(not(unix))]
    let _ = pid;
}

// ---------------------------------------------------------------------------
// 三个线程
// ---------------------------------------------------------------------------

/// 输出线程：阻塞读 PTY，进历史、扇订阅者、扫就绪标记。
fn output_loop(
    mut reader: Box<dyn Read + Send>,
    session: Arc<Session>,
    info: Arc<Mutex<RunInfo>>,
    app: AppState,
) {
    let mut buf = [0u8; 4096];
    let mut tail: Vec<u8> = Vec::with_capacity(READY_SCAN_BYTES * 2);
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let data = buf[..n].to_vec();
                if let Ok(mut state) = session.broadcast.lock() {
                    state.append(data.clone());
                }
                // 在线玩家：边读边解析，名单一变就推事件（前端只读结果，不解析日志）
                if session.feed_players(&data) {
                    publish_players(&app, &session);
                }
                // 就绪判定：只在不处于「运行中」时才扫，省得白扫一整轮
                let scanning = info
                    .lock()
                    .map(|i| i.phase == ServerPhase::Starting)
                    .unwrap_or(false);
                if scanning {
                    tail.extend_from_slice(&data);
                    if tail.len() > READY_SCAN_BYTES {
                        let cut = tail.len() - READY_SCAN_BYTES;
                        tail.drain(..cut);
                    }
                    if tail
                        .windows(READY_MARKER.len())
                        .any(|w| w == READY_MARKER.as_bytes())
                    {
                        tail.clear();
                        transition_shared(&session, &info, &app, ServerPhase::Running, false);
                    }
                }
            }
            Err(_) => break,
        }
    }
}

/// 等待线程：`child.wait()` 阻塞；退出后收尾，必要时自动重启。
fn wait_loop(
    mut child: Box<dyn Child + Send + Sync>,
    session: Arc<Session>,
    info: Arc<Mutex<RunInfo>>,
    app: AppState,
    launch: Launch,
) {
    let code = match child.wait() {
        Ok(status) => i32::try_from(status.exit_code()).ok(),
        Err(e) => {
            tracing::warn!(session = %session.instance_id, error = %e, "等待进程退出失败");
            None
        }
    };

    let (stop_requested, phase_before) = info
        .lock()
        .map(|i| (i.stop_requested, i.phase))
        .unwrap_or((false, ServerPhase::Stopped));

    // 只有还停在过渡态/运行态时才由我们收尾；已经被收过（比如强制停完又手动起了
    // 一轮）就别改人家的状态了。
    if !matches!(phase_before, ServerPhase::Stopped | ServerPhase::Crashed) {
        // 退出码 0 或者是我们主动停的 → 已停止；否则算异常退出
        let phase = if stop_requested || code == Some(0) {
            ServerPhase::Stopped
        } else {
            ServerPhase::Crashed
        };
        finish(&session, &info, &app, phase, code);
    }

    // 自己正常退出（不是我们让它停的、退出码 0）且开了自动重启
    if code == Some(0) && !stop_requested && launch.config.auto_restart_on_exit {
        if app.is_shutting_down() {
            return;
        }
        let done = session.auto_restarts.fetch_add(1, Ordering::Relaxed) + 1;
        if done > MAX_AUTO_RESTARTS {
            session.notice(&format!(
                "[EdgeCube] 已自动重启 {MAX_AUTO_RESTARTS} 次仍立即退出，停止重试"
            ));
            return;
        }
        // 只有「当前挂的还是刚退出的那一轮」才重启，避免和手动启动抢
        let stale = session
            .run
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| !Arc::ptr_eq(&r.info, &info)))
            .unwrap_or(true);
        if stale {
            return;
        }
        session.notice("[EdgeCube] 服务端已正常退出，正在自动重启…");
        std::thread::sleep(AUTO_RESTART_DELAY);
        if app.is_shutting_down() {
            return;
        }
        let next = Launch {
            attempt: launch.attempt + 1,
            ..launch
        };
        if let Err(e) = spawn_run(&session, &app, &next) {
            session.notice(&format!("[EdgeCube] 自动重启失败：{e}"));
        }
    }
}

/// 收尾：落阶段 + 推事件 + 在控制台留一句。
fn finish(
    session: &Arc<Session>,
    info: &Arc<Mutex<RunInfo>>,
    app: &AppState,
    phase: ServerPhase,
    code: Option<i32>,
) {
    let snapshot = {
        let Ok(mut i) = info.lock() else { return };
        i.phase = phase;
        i.exit_code = code;
        i.stopped_at_ms = Some(now_ms());
        i.pid = None;
        i.clone()
    };
    if let Ok(mut last) = session.last.lock() {
        *last = snapshot.clone();
    }
    if let Ok(mut run) = session.run.lock() {
        *run = None;
    }

    // 进程没了就不该再有人在线（服务端退出的那一刻就没人了）
    if session.clear_players() {
        publish_players(app, session);
    }

    let code_text = code.map(|c| c.to_string()).unwrap_or_else(|| "未知".into());
    match phase {
        ServerPhase::Crashed => {
            session.notice(&format!("[EdgeCube] 服务端异常退出（退出码 {code_text}）"))
        }
        _ => session.notice(&format!("[EdgeCube] 服务端已退出（退出码 {code_text}）")),
    }
    publish(app, &session.instance_id, &snapshot);
    session.control(
        serde_json::json!({
            "type": "exit",
            "code": code,
            "phase": phase.as_str(),
        })
        .to_string(),
    );
}

/// 改阶段并推事件。
fn transition(session: &Arc<Session>, app: &AppState, phase: ServerPhase, stop_requested: bool) {
    let running = session
        .run
        .lock()
        .ok()
        .and_then(|g| g.as_ref().map(|r| r.info.clone()));
    if let Some(info) = running {
        transition_shared(session, &info, app, phase, stop_requested);
    }
}

fn transition_shared(
    session: &Arc<Session>,
    info: &Arc<Mutex<RunInfo>>,
    app: &AppState,
    phase: ServerPhase,
    stop_requested: bool,
) {
    let snapshot = {
        let Ok(mut i) = info.lock() else { return };
        if i.phase == phase && !stop_requested {
            return;
        }
        i.phase = phase;
        if stop_requested {
            i.stop_requested = true;
        }
        i.clone()
    };
    if let Ok(mut last) = session.last.lock() {
        *last = snapshot.clone();
    }
    tracing::info!(session = %session.instance_id, phase = phase.as_str(), "实例阶段变化");
    publish(app, &session.instance_id, &snapshot);
}

/// 推一份在线玩家快照。
fn publish_players(app: &AppState, session: &Session) {
    let players = session.online_players();
    app.bus.publish_from(
        Some("instance"),
        TOPIC_PLAYERS,
        serde_json::json!({
            "id": session.instance_id,
            "players": players,
            "count": players.len(),
            "ts": now_ms(),
        }),
    );
}

fn publish(app: &AppState, instance_id: &str, info: &RunInfo) {
    app.bus.publish_from(
        Some("instance"),
        TOPIC_PHASE,
        serde_json::json!({
            "id": instance_id,
            "phase": info.phase,
            "pid": info.pid,
            "exit_code": info.exit_code,
            "started_at_ms": info.started_at_ms,
            "stopped_at_ms": info.stopped_at_ms,
            "stop_requested": info.stop_requested,
            "auto_restarts": info.auto_restarts,
            "ts": now_ms(),
        }),
    );
}

// ---------------------------------------------------------------------------
// 平台差异
// ---------------------------------------------------------------------------

/// 拼一条「交给 shell 跑」的命令。
///
/// 启动命令是用户写的**一整行**（`java -Xmx2G -jar server.jar nogui`），
/// 直接 exec 是跑不起来的，得交给系统 shell 解析。
#[cfg(windows)]
fn shell_command(command: &str) -> CommandBuilder {
    let mut cmd = CommandBuilder::new("cmd");
    cmd.arg("/C");
    cmd.arg(command);
    cmd
}

#[cfg(not(windows))]
fn shell_command(command: &str) -> CommandBuilder {
    let mut cmd = CommandBuilder::new("sh");
    cmd.arg("-c");
    cmd.arg(command);
    cmd
}

/// 默认的 PTY 尺寸（HTTP 层建会话时用）。
pub fn default_pty_size() -> (u16, u16) {
    (DEFAULT_COLS, DEFAULT_ROWS)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::registry::ModuleRegistry;
    use std::time::Instant;
    use tokio_util::sync::CancellationToken;

    /// 进程测试只用到事件总线，注册表给个空的即可。
    fn test_app() -> AppState {
        let config = Config::default();
        let registry = Arc::new(ModuleRegistry::build(vec![], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    /// 建一个临时工作目录；测试结束自动清掉。
    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-process-test-{tag}-{}-{}",
            std::process::id(),
            now_ms()
        ));
        std::fs::create_dir_all(&dir).expect("应能建临时目录");
        dir
    }

    fn config_for(startup: &str, stop: Option<&str>) -> InstanceConfig {
        InstanceConfig {
            id: "t1".into(),
            name: "测试实例".into(),
            startup_command: Some(startup.into()),
            stop_command: stop.map(str::to_string),
            ..Default::default()
        }
    }

    /// 轮询等待某个阶段，超时就 panic（把当前阶段一起报出来）。
    fn wait_phase(session: &Session, want: ServerPhase) -> RunInfo {
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            let info = session.info();
            if info.phase == want {
                return info;
            }
            assert!(
                Instant::now() < deadline,
                "等 {want:?} 超时，当前是 {:?}（exit_code={:?}）",
                info.phase,
                info.exit_code
            );
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    /// 一边等条件成立，一边把 `instance.phase` 事件里的阶段收下来。
    ///
    /// 阶段流转是异步的：`start()` 返回的那一份快照是「拉起那一刻」的，
    /// 进程可能在它返回之前就已经就绪甚至退出了 —— 所以断言「看到过哪些阶段」
    /// 比断言某一份快照的阶段稳得多（后者是竞态，会间歇性失败）。
    fn watch_phases(
        rx: &mut tokio::sync::broadcast::Receiver<std::sync::Arc<crate::event::Event>>,
        mut done: impl FnMut(&str) -> bool,
    ) -> Vec<String> {
        let mut seen = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(20);
        while Instant::now() < deadline {
            match rx.try_recv() {
                Ok(event) if event.topic == TOPIC_PHASE => {
                    let phase = event.data["phase"].as_str().unwrap_or_default().to_string();
                    let hit = done(&phase);
                    seen.push(phase);
                    if hit {
                        return seen;
                    }
                }
                Ok(_) => {}
                Err(tokio::sync::broadcast::error::TryRecvError::Empty) => {
                    std::thread::sleep(Duration::from_millis(10));
                }
                Err(_) => break,
            }
        }
        seen
    }

    #[test]
    fn runs_a_command_and_keeps_its_output_in_history() {
        let app = test_app();
        let dir = temp_dir("echo");
        let manager = ProcessManager::default();
        let config = config_for("echo hello-from-pty", None);

        // 先订阅再启动，才能不漏掉「启动中」这一拍
        let mut rx = app.bus.subscribe();
        let started = start(&manager, &app, &config, &dir).unwrap();
        assert!(started.pid.is_some(), "应拿到 pid");

        let session = manager.ensure(&config.id);
        let info = wait_phase(&session, ServerPhase::Stopped);
        assert_eq!(info.exit_code, Some(0), "正常退出应当是 0");

        let phases = watch_phases(&mut rx, |p| p == "stopped");
        assert_eq!(phases.first().map(String::as_str), Some("starting"));
        assert!(phases.iter().any(|p| p == "stopped"), "事件: {phases:?}");

        // 历史里能看到输出（这就是控制台连上来会收到的东西）
        let (history, sub) = session.subscribe(tokio::sync::mpsc::channel(4).0);
        let text = String::from_utf8_lossy(&history);
        assert!(
            text.contains("hello-from-pty"),
            "历史里应有命令输出: {text:?}"
        );
        assert!(
            text.contains("[EdgeCube] 启动"),
            "应有一条启动提示: {text:?}"
        );
        session.unsubscribe(sub);

        std::fs::remove_dir_all(&dir).ok();
    }

    /// 在线玩家由输出线程边读边解析，名单一变就推事件；进程退出时清空。
    #[test]
    fn online_players_are_parsed_from_output_and_published() {
        let app = test_app();
        let dir = temp_dir("players-online");
        let manager = ProcessManager::default();
        // 三段输出之间留出间隔：输出是**按读到的块**解析的，连着喷出来的几行
        // 可能落在同一次 read 里，那样中间状态本来就不存在（也就不会推事件）。
        let config = config_for(
            "printf 'Steve[/127.0.0.1:5000] logged in with entity id 1\\nAlex 加入了游戏\\n'; \
             sleep 0.3; \
             printf 'There are 1 of a max of 20 players online: Alex\\n'; \
             sleep 0.3",
            None,
        );

        let mut rx = app.bus.subscribe();
        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);
        wait_phase(&session, ServerPhase::Stopped);

        // 退出后的清空发生在「阶段变 stopped」之后一拍，等它落定
        let deadline = Instant::now() + Duration::from_secs(5);
        while !session.online_players().is_empty() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(session.online_players().is_empty(), "退出后名单应清空");

        let mut seen: Vec<Vec<String>> = Vec::new();
        while let Ok(event) = rx.try_recv() {
            if event.topic != TOPIC_PLAYERS {
                continue;
            }
            let names = event.data["players"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap_or_default().to_string())
                .collect::<Vec<_>>();
            assert_eq!(event.data["count"], serde_json::json!(names.len()));
            seen.push(names);
        }

        assert!(
            seen.contains(&vec!["Steve".to_string(), "Alex".to_string()]),
            "加入应当推事件: {seen:?}"
        );
        assert!(
            seen.contains(&vec!["Alex".to_string()]),
            "`list` 响应应当整份替换: {seen:?}"
        );
        assert_eq!(
            seen.last().map(Vec::len),
            Some(0),
            "退出后应推空名单: {seen:?}"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn exit_code_and_crash_are_distinguished() {
        let app = test_app();
        let dir = temp_dir("crash");
        let manager = ProcessManager::default();
        let config = config_for("exit 3", None);

        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);
        let info = wait_phase(&session, ServerPhase::Crashed);

        assert_eq!(info.exit_code, Some(3));
        assert!(!info.stop_requested, "没人叫它停，属于异常退出");
        assert!(!info.alive());

        std::fs::remove_dir_all(&dir).ok();
    }

    /// 停止命令是**普通命令**时，末尾要补换行符再写进去。
    #[test]
    fn stop_writes_the_configured_command() {
        let app = test_app();
        let dir = temp_dir("stop");
        let manager = ProcessManager::default();
        // 读一行就退出 7；用来验证「停止命令真的到了 stdin」
        let config = config_for("read line; exit 7", Some("please-stop"));

        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);
        assert!(session.info().alive());

        stop(&session, &config, &app).unwrap();
        let info = wait_phase(&session, ServerPhase::Stopped);

        assert_eq!(info.exit_code, Some(7), "应当读到那一行并 exit 7");
        assert!(info.stop_requested, "是我们让它停的");
        // 终端会把输入回显出来，所以历史里能看到这条命令
        let (history, _) = session.subscribe(tokio::sync::mpsc::channel(4).0);
        assert!(
            String::from_utf8_lossy(&history).contains("please-stop"),
            "停止命令应被回显在输出里"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    /// `^C` = 把 0x03 写进 PTY，终端驱动给前台进程组发 SIGINT。
    #[test]
    fn stop_with_caret_c_interrupts_the_process() {
        let app = test_app();
        let dir = temp_dir("sigint");
        let manager = ProcessManager::default();
        let config = config_for("sleep 300", Some("^C"));

        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);
        assert!(session.info().alive(), "sleep 应当还在跑");

        stop(&session, &config, &app).unwrap();
        let info = wait_phase(&session, ServerPhase::Stopped);
        assert!(info.stop_requested);
        assert!(!info.alive());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn kill_terminates_a_stubborn_process() {
        let app = test_app();
        let dir = temp_dir("kill");
        let manager = ProcessManager::default();
        // 没有停止命令的服务端：只能强杀
        let config = config_for("sleep 300", None);

        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);
        assert!(session.info().alive());

        kill(&session, &app).unwrap();
        let info = wait_phase(&session, ServerPhase::Stopped);
        assert!(info.stop_requested, "强杀也算主动停，不该报成崩溃");

        std::fs::remove_dir_all(&dir).ok();
    }

    /// 兼容模式：不等 `Done (` 标记，进程一起来就算运行中。
    #[test]
    fn compat_mode_skips_the_ready_marker() {
        let app = test_app();
        let dir = temp_dir("compat");
        let manager = ProcessManager::default();
        let mut config = config_for("sleep 300", Some("^C"));
        config.compat_mode = true;

        let started = start(&manager, &app, &config, &dir).unwrap();
        assert_eq!(started.phase, ServerPhase::Running);

        let session = manager.ensure(&config.id);
        kill(&session, &app).unwrap();
        wait_phase(&session, ServerPhase::Stopped);

        std::fs::remove_dir_all(&dir).ok();
    }

    /// 非兼容模式下，输出里出现 `Done (` 才切到运行中。
    #[test]
    fn ready_marker_moves_starting_to_running() {
        let app = test_app();
        let dir = temp_dir("ready");
        let manager = ProcessManager::default();
        let config = config_for("printf 'Done (1.2s)! For help\\n'; sleep 300", Some("^C"));

        let mut rx = app.bus.subscribe();
        start(&manager, &app, &config, &dir).unwrap();

        let session = manager.ensure(&config.id);
        let info = wait_phase(&session, ServerPhase::Running);
        assert!(!info.stop_requested, "是自己就绪的，不是谁叫它停");

        // 事件里应当看到「启动中 → 运行中」这一对
        let phases = watch_phases(&mut rx, |p| p == "running");
        assert!(phases.iter().any(|p| p == "starting"), "事件: {phases:?}");
        assert!(phases.iter().any(|p| p == "running"), "事件: {phases:?}");

        kill(&session, &app).unwrap();
        wait_phase(&session, ServerPhase::Stopped);

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn phase_changes_are_published_on_the_bus() {
        let app = test_app();
        let dir = temp_dir("events");
        let manager = ProcessManager::default();
        let config = config_for("echo done", None);
        let mut rx = app.bus.subscribe();

        start(&manager, &app, &config, &dir).unwrap();

        let mut seen = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(20);
        while Instant::now() < deadline && !seen.iter().any(|p| p == "stopped") {
            match rx.try_recv() {
                Ok(event) if event.topic == TOPIC_PHASE => {
                    assert_eq!(event.source.as_deref(), Some("instance"));
                    assert_eq!(event.data["id"], serde_json::json!("t1"));
                    seen.push(event.data["phase"].as_str().unwrap_or_default().to_string());
                }
                Ok(_) => {}
                Err(_) => std::thread::sleep(Duration::from_millis(20)),
            }
        }
        assert!(seen.contains(&"starting".to_string()), "事件: {seen:?}");
        assert!(seen.contains(&"stopped".to_string()), "事件: {seen:?}");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn rejects_bad_lifecycle_calls_with_stable_codes() {
        let app = test_app();
        let dir = temp_dir("errors");
        let manager = ProcessManager::default();

        // 没配启动命令
        let bare = InstanceConfig {
            id: "t1".into(),
            name: "空".into(),
            ..Default::default()
        };
        let err = start(&manager, &app, &bare, &dir).unwrap_err();
        assert_eq!(err.code(), "instance_not_configured");

        // 没在跑就停 / 强杀
        let idle = manager.ensure("t1");
        let config = config_for("echo x", None);
        assert_eq!(
            stop(&idle, &config, &app).unwrap_err().code(),
            "instance_not_running"
        );
        assert_eq!(
            kill(&idle, &app).unwrap_err().code(),
            "instance_not_running"
        );

        // 已经在跑
        let running = config_for("sleep 300", Some("^C"));
        start(&manager, &app, &running, &dir).unwrap();
        let err = start(&manager, &app, &running, &dir).unwrap_err();
        assert_eq!(err.code(), "instance_already_running");
        assert!(err.to_string().contains("pid"), "{err}");

        let session = manager.ensure("t1");
        kill(&session, &app).unwrap();
        wait_phase(&session, ServerPhase::Stopped);

        // 没配停止命令 → 只能强杀
        let session = manager.ensure("t1");
        assert!(!session.info().alive());
        let err = stop(&session, &config, &app).unwrap_err();
        assert_eq!(err.code(), "instance_not_running", "没在跑优先报这个");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn session_manager_is_keyed_by_instance() {
        let manager = ProcessManager::default();
        assert!(manager.is_empty());

        let a = manager.ensure("a");
        let b = manager.ensure("b");
        assert!(!Arc::ptr_eq(&a, &b));
        assert!(
            Arc::ptr_eq(&a, &manager.ensure("a")),
            "同一个 id 应是同一个会话"
        );
        assert_eq!(manager.len(), 2);

        assert!(manager.remove("a").is_some());
        assert_eq!(manager.len(), 1);
        assert!(manager.get("a").is_none());
    }

    /// 断开连接只退订，进程照跑（demo 的语义）。
    #[test]
    fn unsubscribe_does_not_touch_the_process() {
        let app = test_app();
        let dir = temp_dir("unsub");
        let manager = ProcessManager::default();
        let config = config_for("sleep 300", Some("^C"));

        start(&manager, &app, &config, &dir).unwrap();
        let session = manager.ensure(&config.id);

        let (tx, _rx) = tokio::sync::mpsc::channel(4);
        let (_, sub) = session.subscribe(tx);
        assert_eq!(session.subscriber_count(), 1);
        session.unsubscribe(sub);
        assert_eq!(session.subscriber_count(), 0);
        assert!(session.info().alive(), "退订不该把进程带走");

        kill(&session, &app).unwrap();
        wait_phase(&session, ServerPhase::Stopped);

        std::fs::remove_dir_all(&dir).ok();
    }
}
