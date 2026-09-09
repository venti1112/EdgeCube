//! 实例进程管理(PTY 底座):经 pty 组件(与 daemon 同目录的终端程序)启动 /
//! 停止 / 强杀实例,并承载终端 I/O。
//!
//! 启动模型(见 pty 仓库 README):
//! ```text
//! daemon spawn → pty -size C,R -coder enc -dir workdir -fifo <endpoint> -cmd '["java",…]'
//!   握手:pty stderr 首行 {"pid": N}(10s 超时;[EDGECUBE-PTY] 前缀 = 启动失败)
//!   数据通道:pty stdout = 游戏输出(已按 -coder 转码);daemon 写 pty stdin = 按键
//!   控制通道(Unix socket / Windows 命名管道):daemon→RESIZE 帧;PTY→EXIT/ERROR/INFO 帧
//! ```
//! 优雅停止 = 逐行写 stopCommand(`^C` 特判为 0x03 Ctrl+C)→ 超时(可配,
//! 默认 600s)自动升级强杀;强杀 = 杀进程树(Unix 进程组 SIGKILL / Windows
//! taskkill /T /F)。进程退出后句柄保留在注册表中(stopped + 退出码),
//! 供详情页展示上次退出码,下次启动时替换。

use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::OsString;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicI32, AtomicU8, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{broadcast, mpsc, oneshot, watch, Mutex as StdAsyncMutex};
use uuid::Uuid;

use crate::instance::{InstanceConfig, InstanceStatus, RuntimeSnapshot};

/// pty 握手超时(README 约定 daemon 侧 10s)。
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
/// 控制通道拨号重试(pty 在握手后才监听;共约 3s)。
const CONTROL_DIAL_ATTEMPTS: u32 = 30;
/// 终端输出广播缓冲(块;慢消费者丢块不阻塞进程)。
const OUTPUT_CHANNEL: usize = 1024;
/// 无退出码哨兵。
pub const EXIT_CODE_NONE: i32 = i32::MIN;

/// 控制通道帧类型(与 pty cmd/start 约定一致)。
const FRAME_ERROR: u8 = 0x02;
const FRAME_RESIZE: u8 = 0x04;
const FRAME_EXIT: u8 = 0x05;
const FRAME_INFO: u8 = 0x06;

// ────────────────────────── 错误 ──────────────────────────

#[derive(Debug)]
pub enum ProcError {
    /// 实例已在启动/运行/停止中(409 instance_busy)。
    Busy,
    /// 实例未在运行(409 instance_not_running)。
    NotRunning,
    /// pty 缺失 / spawn / 握手失败(500 spawn_error)。
    Spawn(String),
}

impl ProcError {
    /// 契约错误码(REST/WS 通用)。
    pub fn code(&self) -> &'static str {
        match self {
            ProcError::Busy => "instance_busy",
            ProcError::NotRunning => "instance_not_running",
            ProcError::Spawn(_) => "spawn_error",
        }
    }
}

// ────────────────────────── 状态广播 ──────────────────────────

/// 状态变化事件(终端 WS `state` 帧;后续 /ws/events hub 复用)。
#[derive(Debug, Clone)]
pub struct ProcStateEvent {
    pub status: InstanceStatus,
    pub exit_code: Option<i32>,
}

// ────────────────────────── 进程句柄 ──────────────────────────

/// 单个实例的进程句柄:状态原子 + 终端 I/O + 控制通道 + watcher 注册表。
/// 退出后句柄保留(注册表内),下次启动替换。
pub struct ProcHandle {
    pub instance_id: Uuid,
    /// 进程状态(0=stopped 1=starting 2=running 3=stopping)。
    state: AtomicU8,
    /// 游戏进程真实 pid(0 = 未知)。
    pid: AtomicU32,
    /// 退出码(EXIT 帧优先,child.wait 兜底)。
    exit_code: AtomicI32,
    /// 原始 PTY 输出广播(终端二进制帧)。
    pub output_tx: broadcast::Sender<Vec<u8>>,
    /// 状态变化广播。
    pub state_tx: broadcast::Sender<ProcStateEvent>,
    /// pty stdin(优雅停止后移除)。
    stdin: StdAsyncMutex<Option<tokio::process::ChildStdin>>,
    /// 控制通道命令发送端(resize);None = 通道未建立/已断。
    control_tx: Mutex<Option<mpsc::Sender<ControlCommand>>>,
    /// kill 请求(wait 任务持有 child,由它执行进程树击杀)。
    kill_tx: Mutex<Option<mpsc::Sender<oneshot::Sender<()>>>>,
    /// 终端 watcher:conn_id -> (cols, rows)。
    watchers: Mutex<HashMap<Uuid, (u32, u32)>>,
    /// 终结信号(stop/restart 等待退出)。
    done_tx: watch::Sender<bool>,
    /// EXIT 帧上报的退出码(wait 任务终结时优先采用)。
    exit_frame_code: Arc<AtomicI32>,
    /// 控制端点清理路径(Unix socket 文件)。
    control_cleanup: Mutex<Option<PathBuf>>,
}

#[derive(Debug)]
enum ControlCommand {
    Resize(u32, u32),
}

impl ProcHandle {
    fn new(instance_id: Uuid) -> Arc<Self> {
        let (output_tx, _) = broadcast::channel(OUTPUT_CHANNEL);
        let (state_tx, _) = broadcast::channel(64);
        let (done_tx, _) = watch::channel(false);
        Arc::new(ProcHandle {
            instance_id,
            state: AtomicU8::new(1), // starting
            pid: AtomicU32::new(0),
            exit_code: AtomicI32::new(EXIT_CODE_NONE),
            output_tx,
            state_tx,
            stdin: StdAsyncMutex::new(None),
            control_tx: Mutex::new(None),
            kill_tx: Mutex::new(None),
            watchers: Mutex::new(HashMap::new()),
            done_tx,
            exit_frame_code: Arc::new(AtomicI32::new(EXIT_CODE_NONE)),
            control_cleanup: Mutex::new(None),
        })
    }

    pub fn status(&self) -> InstanceStatus {
        match self.state.load(Ordering::Relaxed) {
            1 => InstanceStatus::Starting,
            2 => InstanceStatus::Running,
            3 => InstanceStatus::Stopping,
            _ => InstanceStatus::Stopped,
        }
    }

    fn set_state(&self, status: InstanceStatus) {
        let v = match status {
            InstanceStatus::Starting => 1,
            InstanceStatus::Running => 2,
            InstanceStatus::Stopping => 3,
            _ => 0,
        };
        self.state.store(v, Ordering::Relaxed);
        self.broadcast_state(None);
    }

    /// 广播状态事件(可附退出码;缺省读当前值)。
    pub fn broadcast_state(&self, exit_code: Option<i32>) {
        let code = exit_code.or_else(|| self.exit_code());
        let _ = self.state_tx.send(ProcStateEvent {
            status: self.status(),
            exit_code: code,
        });
    }

    pub fn pid(&self) -> Option<u32> {
        let pid = self.pid.load(Ordering::Relaxed);
        (pid != 0).then_some(pid)
    }

    pub fn exit_code(&self) -> Option<i32> {
        let code = self.exit_code.load(Ordering::Relaxed);
        (code != EXIT_CODE_NONE).then_some(code)
    }

    /// 实例运行时快照。
    pub fn snapshot(&self) -> RuntimeSnapshot {
        RuntimeSnapshot {
            status: self.status(),
            pid: self.pid(),
            exit_code: self.exit_code(),
        }
    }

    /// 进程已终结(stopped)。
    pub fn is_done(&self) -> bool {
        self.status() == InstanceStatus::Stopped
    }

    /// 等待进程终结(已终结立即返回)。
    pub async fn wait_done(&self) {
        let mut rx = self.done_tx.subscribe();
        while !*rx.borrow_and_update() {
            if rx.changed().await.is_err() {
                return;
            }
        }
    }

    /// 写原始按键(终端 write 帧 / 二进制帧)。
    pub async fn write_bytes(&self, data: &[u8]) -> Result<(), ProcError> {
        let mut stdin = self.stdin.lock().await;
        let Some(stdin) = stdin.as_mut() else {
            return Err(ProcError::NotRunning);
        };
        stdin
            .write_all(data)
            .await
            .map_err(|e| ProcError::Spawn(format!("write stdin: {e}")))?;
        stdin
            .flush()
            .await
            .map_err(|e| ProcError::Spawn(format!("flush stdin: {e}")))?;
        Ok(())
    }

    /// 写一行命令(命令框 input;自动补 \r)。
    pub async fn write_line(&self, command: &str) -> Result<(), ProcError> {
        let mut line = command.to_string();
        line.push('\r');
        self.write_bytes(line.as_bytes()).await
    }

    /// 优雅停止:逐行写 stopCommand(`^C` 特判 0x03 Ctrl+C)→ 等待退出
    /// [timeout_secs] 秒 → 超时升级强杀。写完关闭 stdin(半关闭)。
    pub async fn stop(&self, stop_command: &str, timeout_secs: u64) -> Result<(), ProcError> {
        if self.status() != InstanceStatus::Running {
            return Err(ProcError::NotRunning);
        }
        self.set_state(InstanceStatus::Stopping);

        // 逐行写停止命令(多行 stopCommand 由 daemon 拆行;^C → Ctrl+C 字节)
        {
            let mut stdin = self.stdin.lock().await;
            if let Some(stdin) = stdin.as_mut() {
                for line in stop_command.lines() {
                    let line = line.trim_end_matches('\r');
                    let payload: Vec<u8> = if line == "^C" {
                        vec![0x03]
                    } else {
                        let mut b = line.as_bytes().to_vec();
                        b.push(b'\r');
                        b
                    };
                    if let Err(e) = stdin.write_all(&payload).await {
                        tracing::warn!(instance = %self.instance_id, error = %e, "write stop command failed");
                        break;
                    }
                    let _ = stdin.flush().await;
                }
            }
            // 半关闭 stdin(pty 上报 stdin_closed;进程不受影响)
            *stdin = None;
        }

        // 等待退出,超时升级强杀
        match tokio::time::timeout(Duration::from_secs(timeout_secs), self.wait_done()).await {
            Ok(_) => Ok(()),
            Err(_) => {
                tracing::warn!(instance = %self.instance_id, timeout = timeout_secs, "graceful stop timeout, escalating to kill");
                self.kill().await
            }
        }
    }

    /// 强杀进程树:Unix 杀进程组(SIGKILL),Windows taskkill /T /F。
    pub async fn kill(&self) -> Result<(), ProcError> {
        if self.is_done() {
            return Err(ProcError::NotRunning);
        }
        if self.status() != InstanceStatus::Stopping {
            self.set_state(InstanceStatus::Stopping);
        }
        let req = {
            let tx = self.kill_tx.lock().unwrap().clone();
            tx.map(|tx| (tx, oneshot::channel()))
        };
        match req {
            Some((tx, (ack_tx, ack_rx))) => {
                if tx.send(ack_tx).await.is_err() {
                    return Err(ProcError::Spawn("kill channel closed".into()));
                }
                // wait 任务收到请求即执行进程树击杀;ack 后等待终结
                let _ = ack_rx.await;
            }
            None => return Err(ProcError::Spawn("kill channel unavailable".into())),
        }
        match tokio::time::timeout(Duration::from_secs(10), self.wait_done()).await {
            Ok(_) => Ok(()),
            Err(_) => Err(ProcError::Spawn("kill timeout".into())),
        }
    }

    // ── watcher(终端多端共享) ─────────────────────────────────

    /// 注册 watcher,返回当前 watcher 数;尺寸变化即触发最小行列仲裁。
    pub async fn add_watcher(&self, conn_id: Uuid, cols: u32, rows: u32) -> u32 {
        let count = {
            let mut w = self.watchers.lock().unwrap();
            w.insert(conn_id, (cols.max(2), rows.max(2)));
            w.len() as u32
        };
        self.arbitrate_size().await;
        count
    }

    /// 注销 watcher,返回当前 watcher 数。
    pub async fn remove_watcher(&self, conn_id: Uuid) -> u32 {
        let count = {
            let mut w = self.watchers.lock().unwrap();
            w.remove(&conn_id);
            w.len() as u32
        };
        self.arbitrate_size().await;
        count
    }

    /// 更新 watcher 尺寸,返回当前 watcher 数。
    pub async fn update_watcher(&self, conn_id: Uuid, cols: u32, rows: u32) -> u32 {
        let count = {
            let mut w = self.watchers.lock().unwrap();
            if let Some(entry) = w.get_mut(&conn_id) {
                *entry = (cols.max(2), rows.max(2));
            }
            w.len() as u32
        };
        self.arbitrate_size().await;
        count
    }

    pub fn watcher_count(&self) -> u32 {
        self.watchers.lock().unwrap().len() as u32
    }

    /// 尺寸裁决:全部 watcher 的最小行列 → RESIZE 帧(无 watcher 不动)。
    async fn arbitrate_size(&self) {
        let (cols, rows) = {
            let w = self.watchers.lock().unwrap();
            if w.is_empty() {
                return;
            }
            w.values().fold((u32::MAX, u32::MAX), |acc, (c, r)| {
                (acc.0.min(*c), acc.1.min(*r))
            })
        };
        let tx = self.control_tx.lock().unwrap().clone();
        if let Some(tx) = tx {
            let _ = tx.try_send(ControlCommand::Resize(cols, rows));
        }
    }
}

// ────────────────────────── 管理器 ──────────────────────────

/// 运行时主目录解析钩子(instance 的 `runtime_id` → 运行时主目录,如
/// `{data}/runtimes/java-25.0.4.1+1`)。由 main 装配时注入 [`RuntimeManager::get`]
/// 的查询;None = 未指定 / 未安装 / 未注入。
pub type RuntimePathResolver =
    Arc<dyn Fn(&str) -> Pin<Box<dyn Future<Output = Option<PathBuf>> + Send>> + Send + Sync>;

/// 进程管理器:实例 -> 句柄注册表 + pty 程序定位(与 daemon 同目录)。
pub struct ProcManager {
    procs: RwLock<HashMap<Uuid, Arc<ProcHandle>>>,
    /// 在线玩家集合:实例 id -> 在线玩家名(由 stdout 泵解析控制台输出维护)。
    online_players: Arc<RwLock<HashMap<Uuid, HashSet<String>>>>,
    pty_bin: PathBuf,
    /// 控制通道端点目录(Unix socket)。
    run_dir: PathBuf,
    /// 实例配置目录根 `{data}/instances`(实例输出日志按 `{id}/logs` 归置)。
    instances_root: PathBuf,
    /// 运行时主目录解析钩子(None = 未注入;启动时不注入 PATH)。
    runtime_resolver: Mutex<Option<RuntimePathResolver>>,
}

impl ProcManager {
    /// pty 程序路径:与 daemon 可执行文件同目录(pty / pty.exe)。
    pub fn pty_path() -> PathBuf {
        let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
        let dir = exe.parent().unwrap_or(Path::new("."));
        dir.join(if cfg!(windows) { "pty.exe" } else { "pty" })
    }

    pub fn new(data_dir: &Path) -> Self {
        let run_dir = data_dir.join("run");
        let _ = std::fs::create_dir_all(&run_dir);
        ProcManager {
            procs: RwLock::new(HashMap::new()),
            online_players: Arc::new(RwLock::new(HashMap::new())),
            pty_bin: Self::pty_path(),
            run_dir,
            instances_root: data_dir.join(crate::instance::INSTANCES_DIR),
            runtime_resolver: Mutex::new(None),
        }
    }

    /// 注入运行时主目录解析钩子(main 装配时调用一次;
    /// 使全裸 `java`/`php` 等启动命令命中实例声明的运行时)。
    pub fn set_runtime_resolver(&self, resolver: RuntimePathResolver) {
        *self.runtime_resolver.lock().unwrap() = Some(resolver);
    }

    /// 实例声明的运行时 id → 运行时主目录(未声明 / 未安装 → None)。
    async fn resolve_runtime(&self, runtime_id: &str) -> Option<PathBuf> {
        // 先取出 resolver 再 await,避免持有 std Mutex 越过 .await
        let resolver = self.runtime_resolver.lock().unwrap().clone()?;
        resolver(runtime_id).await
    }

    /// 实例运行时快照(注册表中无句柄 → None)。
    pub fn snapshot(&self, id: Uuid) -> Option<RuntimeSnapshot> {
        let procs = self.procs.read().unwrap();
        procs.get(&id).map(|h| h.snapshot())
    }

    /// 实例当前在线玩家名(由 stdout 泵解析维护;在线集合拷贝返回)。
    pub fn online_players(&self, id: Uuid) -> Vec<String> {
        let online = self.online_players.read().unwrap();
        match online.get(&id) {
            Some(set) => {
                let mut names: Vec<String> = set.iter().cloned().collect();
                names.sort();
                names
            }
            None => Vec::new(),
        }
    }

    /// 取句柄(含已退出保留的句柄)。
    pub fn get(&self, id: Uuid) -> Option<Arc<ProcHandle>> {
        self.procs.read().unwrap().get(&id).cloned()
    }

    /// 删除实例时清理句柄(运行中由调用方先行拒绝)。
    pub fn remove(&self, id: Uuid) {
        self.procs.write().unwrap().remove(&id);
        self.online_players.write().unwrap().remove(&id);
    }

    /// 汇总实例全部历史输出日志(按文件名时间序拼接),返回最后 [max_lines] 行。
    /// 供终端 `replay` 使用:即使 daemon 重启、内存日志环已清,也能从落盘日志
    /// 恢复历史。实例无日志目录 → 空 Vec。
    pub async fn replay_log(&self, id: Uuid, max_lines: usize) -> Vec<String> {
        let dir = self.instances_root.join(id.to_string()).join("logs");
        let mut paths: Vec<PathBuf> = match std::fs::read_dir(&dir) {
            Ok(rd) => rd
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().map_or(false, |e| e == "log"))
                .collect(),
            Err(_) => return Vec::new(),
        };
        // 文件名 = {id}-{UTC 时间戳}.log,字典序即时间序
        paths.sort();
        let mut tail: VecDeque<String> = VecDeque::with_capacity(max_lines.min(64));
        for path in paths {
            let Ok(content) = tokio::fs::read_to_string(&path).await else {
                continue;
            };
            for line in content.lines() {
                // lines() 按 \n 切分,CRLF 日志的行尾 \r 残留于行内容;剔除,
                // 由前端拼 \r\n 回看行时保证行首对齐
                tail.push_back(line.trim_end_matches('\r').to_string());
                if tail.len() > max_lines {
                    tail.pop_front();
                }
            }
        }
        tail.into_iter().collect()
    }

    /// 启动实例(spawn pty + 握手;由 start 任务执行)。
    pub async fn start(&self, config: InstanceConfig) -> Result<u32, ProcError> {
        let id = config.id;
        // 已有句柄:启动/运行/停止中 → Busy;已退出(stopped)→ 替换
        {
            let procs = self.procs.read().unwrap();
            if let Some(h) = procs.get(&id) {
                if !h.is_done() {
                    return Err(ProcError::Busy);
                }
            }
        }

        let handle = ProcHandle::new(id);
        self.procs.write().unwrap().insert(id, handle.clone());

        match self.spawn_pty(&handle, &config).await {
            Ok(pid) => {
                handle.pid.store(pid, Ordering::Relaxed);
                handle.set_state(InstanceStatus::Running);
                tracing::info!(instance = %id, pid, "instance started");
                Ok(pid)
            }
            Err(e) => {
                self.procs.write().unwrap().remove(&id);
                handle.state.store(0, Ordering::Relaxed);
                handle.exit_code.store(-1, Ordering::Relaxed);
                handle.broadcast_state(Some(-1));
                tracing::warn!(instance = %id, error = ?e, "instance start failed");
                Err(e)
            }
        }
    }

    /// 优雅停止(实例配置的 stopTimeoutSeconds)。
    pub async fn stop(&self, config: &InstanceConfig) -> Result<(), ProcError> {
        let Some(handle) = self.get(config.id) else {
            return Err(ProcError::NotRunning);
        };
        if handle.is_done() {
            return Err(ProcError::NotRunning);
        }
        let timeout = config.stop_timeout_seconds;
        handle.stop(&config.stop_command, timeout).await
    }

    /// 强杀。
    pub async fn kill(&self, id: Uuid) -> Result<(), ProcError> {
        let Some(handle) = self.get(id) else {
            return Err(ProcError::NotRunning);
        };
        handle.kill().await
    }

    /// 控制通道端点:(pty -fifo 参数, Unix socket 清理路径)。
    fn control_endpoint(&self, id: Uuid) -> (String, Option<PathBuf>) {
        #[cfg(unix)]
        {
            let path = self.run_dir.join(format!("{id}.sock"));
            (path.to_string_lossy().into_owned(), Some(path))
        }
        #[cfg(windows)]
        {
            let _ = &self.run_dir;
            (format!(r"\\.\pipe\edgecube-pty-{id}"), None)
        }
    }

    /// spawn pty + 握手 + 启动各泵任务;返回游戏进程 pid。
    async fn spawn_pty(&self, handle: &Arc<ProcHandle>, config: &InstanceConfig) -> Result<u32, ProcError> {
        if !self.pty_bin.exists() {
            return Err(ProcError::Spawn(
                "pty 程序未找到(需与 daemon 程序放在同一目录)".into(),
            ));
        }
        let cmds = shell_words::split(&config.start_command)
            .map_err(|e| ProcError::Spawn(format!("start command parse: {e}")))?;
        if cmds.is_empty() {
            return Err(ProcError::Spawn("启动命令为空".into()));
        }
        let cmd_json = serde_json::to_string(&cmds)
            .map_err(|e| ProcError::Spawn(format!("start command encode: {e}")))?;
        std::fs::create_dir_all(&config.working_directory)
            .map_err(|e| ProcError::Spawn(format!("workdir: {e}")))?;

        let (endpoint, cleanup) = self.control_endpoint(config.id);
        let term = &config.terminal;
        let (kill_tx, mut kill_rx) = mpsc::channel::<oneshot::Sender<()>>(1);
        {
            let mut slot = handle.kill_tx.lock().unwrap();
            *slot = Some(kill_tx);
        }
        if let Some(path) = cleanup {
            *handle.control_cleanup.lock().unwrap() = Some(path);
        }

        tracing::info!(
            instance = %config.id,
            cmd = %config.start_command,
            dir = %config.working_directory.display(),
            pty = %self.pty_bin.display(),
            "spawning pty"
        );

        let mut command = tokio::process::Command::new(&self.pty_bin);
        command
            .args(["-size", &format!("{},{}", term.initial_cols, term.initial_rows)])
            .args(["-coder", coder_for(config.output_encoding)])
            .args(["-dir"])
            .arg(&config.working_directory)
            .args(["-fifo", &endpoint])
            .args(["-cmd", &cmd_json])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        #[cfg(unix)]
        command.process_group(0);

        // 实例声明了运行时:把 `{运行时}/bin` 前置注入 pty 进程的 PATH,使
        // 全裸 `java`/`php` 等启动命令命中该运行时(pty 用 os.Environ() 继承环境,
        // exec.LookPath 沿用此 PATH)。运行时缺失/目录异常仅告警,回退系统 PATH。
        if let Some(runtime_id) = config.runtime_id.as_deref() {
            match self.resolve_runtime(runtime_id).await {
                Some(root) => {
                    let bin_dir = root.join("bin");
                    if bin_dir.is_dir() {
                        if let Some(prefixed) =
                            std::env::var_os("PATH").and_then(|p| prepend_path(&bin_dir, &p))
                        {
                            command.env("PATH", prefixed);
                        }
                        tracing::info!(
                            instance = %config.id,
                            runtime = runtime_id,
                            bin = %bin_dir.display(),
                            "runtime PATH injected"
                        );
                    } else {
                        tracing::warn!(
                            instance = %config.id,
                            runtime = runtime_id,
                            bin = %bin_dir.display(),
                            "runtime bin dir missing; falling back to system PATH"
                        );
                    }
                }
                None => {
                    tracing::warn!(
                        instance = %config.id,
                        runtime = runtime_id,
                        "declared runtime not installed; falling back to system PATH"
                    );
                }
            }
        }

        let mut child = command
            .spawn()
            .map_err(|e| ProcError::Spawn(format!("spawn pty: {e}")))?;
        let pty_pid = child.id().unwrap_or(0);

        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| ProcError::Spawn("pty stdin unavailable".into()))?;
        let mut stderr = child
            .stderr
            .take()
            .ok_or_else(|| ProcError::Spawn("pty stderr unavailable".into()))?;
        let mut stdout = child
            .stdout
            .take()
            .ok_or_else(|| ProcError::Spawn("pty stdout unavailable".into()))?;

        // ── 握手:stderr 首行 {"pid": N}(10s 超时;失败 = 启动失败) ──
        let game_pid = handshake_pid(&mut stderr).await?;

        // stdin 交给句柄(终端写入)
        {
            let mut slot = handle.stdin.lock().await;
            *slot = Some(stdin);
        }

        // ── 控制通道(拨号重试至 pty 监听就绪) ───────────────────
        match dial_control(&endpoint).await {
            Some(conn) => spawn_control_tasks(handle, conn),
            None => {
                tracing::warn!(instance = %config.id, "control channel dial failed (resize unavailable)");
            }
        }

        // ── 实例输出日志文件(每次启动新建;尽力而为,失败仅告警) ──
        let log_file = open_log_file(&self.instances_root, config.id).await;

        // ── stdout 泵:进程输出 → 日志文件 + 终端广播 + 在线玩家事件解析 ──
        {
            let handle = handle.clone();
            let online_players = self.online_players.clone();
            let instance_id = config.id;
            tokio::spawn(async move {
                let mut log_file = log_file;
                let mut buf = [0u8; 4096];
                let mut partial = String::new();
                loop {
                    match stdout.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(n) => {
                            let chunk = &buf[..n];
                            let _ = handle.output_tx.send(chunk.to_vec());
                            // 拆行(保留 ANSI;跨块拼接半行),逐行写日志文件 + 解析玩家事件
                            partial.push_str(&String::from_utf8_lossy(chunk));
                            while let Some(pos) = partial.find('\n') {
                                let line: String = partial.drain(..=pos).collect();
                                if let Some(f) = log_file.as_mut() {
                                    if f.write_all(line.as_bytes()).await.is_ok() {
                                        let _ = f.flush().await;
                                    }
                                }
                                // join/leave/list 预过滤后加锁更新在线玩家集合。
                                if crate::players::line_may_contain_player_event(&line) {
                                    let mut online = online_players.write().unwrap();
                                    let set = online.entry(instance_id).or_default();
                                    crate::players::record_player_event(set, &line);
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
                // 无尾随换行的最后一行:写文件
                if !partial.is_empty() {
                    if let Some(f) = log_file.as_mut() {
                        let _ = f.write_all(partial.as_bytes()).await;
                        let _ = f.flush().await;
                    }
                }
                // 显式冲刷后由 drop 关闭日志文件
                if let Some(f) = log_file.as_mut() {
                    let _ = f.flush().await;
                }
                tracing::debug!(instance = %handle.instance_id, "pty stdout closed");
            });
        }

        // ── stderr 兜底排空(避免管道写端阻塞;[EDGECUBE-PTY] 日志) ──
        tokio::spawn(async move {
            let mut buf = Vec::new();
            if stderr.read_to_end(&mut buf).await.is_ok() {
                let text = String::from_utf8_lossy(&buf);
                for line in text.lines() {
                    tracing::debug!(target: "pty", "{line}");
                }
            }
        });

        // ── wait 任务:持有 child,等待退出 / 处理 kill 请求 → 终结 ──
        {
            let handle = handle.clone();
            let exit_frame_code = handle.exit_frame_code.clone();
            let online_players = self.online_players.clone();
            let instance_id = config.id;
            tokio::spawn(async move {
                let mut code: i32 = -1;
                loop {
                    tokio::select! {
                        biased;
                        ack = kill_rx.recv() => {
                            if let Some(ack) = ack {
                                platform_kill(pty_pid).await;
                                let _ = ack.send(());
                                // 继续等 child.wait() 收尾
                            } else {
                                // 句柄已弃(kill_tx 被清空):仅等退出
                            }
                        }
                        st = child.wait() => {
                            code = st.ok().and_then(|s| s.code()).unwrap_or(-1);
                            break;
                        }
                    }
                }

                // 终结:EXIT 帧退出码优先,child.wait 兜底
                let reported = exit_frame_code.load(Ordering::Relaxed);
                let final_code = if reported != EXIT_CODE_NONE {
                    reported
                } else {
                    code
                };
                handle.exit_code.store(final_code, Ordering::Relaxed);
                handle.state.store(0, Ordering::Relaxed);
                *handle.stdin.lock().await = None;
                *handle.control_tx.lock().unwrap() = None;
                *handle.kill_tx.lock().unwrap() = None;
                if let Some(path) = handle.control_cleanup.lock().unwrap().take() {
                    let _ = std::fs::remove_file(path);
                }
                // 进程已退出:清空在线玩家集合(下次启动重建),避免残留。
                online_players.write().unwrap().remove(&instance_id);
                handle.broadcast_state(Some(final_code));
                let _ = handle.done_tx.send(true);
                tracing::info!(instance = %handle.instance_id, code = final_code, "instance exited");
            });
        }

        Ok(game_pid)
    }
}

// ────────────────────────── 内部工具 ──────────────────────────

/// 握手:读 pty stderr 首行,解析 {"pid": N};非 JSON(= [EDGECUBE-PTY] 报错)
/// 或超时视为启动失败。
async fn handshake_pid(stderr: &mut tokio::process::ChildStderr) -> Result<u32, ProcError> {
    let mut line = Vec::new();
    loop {
        let mut byte = [0u8; 1];
        let read = tokio::time::timeout(HANDSHAKE_TIMEOUT, stderr.read(&mut byte))
            .await
            .map_err(|_| ProcError::Spawn("pty 握手超时(10s)".into()))?
            .map_err(|e| ProcError::Spawn(format!("pty stderr read: {e}")))?;
        if read == 0 {
            return Err(ProcError::Spawn("pty 提前退出(无握手行)".into()));
        }
        if byte[0] == b'\n' {
            break;
        }
        line.push(byte[0]);
    }
    let text = String::from_utf8_lossy(&line).trim().to_string();
    if !text.starts_with('{') {
        return Err(ProcError::Spawn(format!("pty 启动失败: {text}")));
    }
    #[derive(serde::Deserialize)]
    struct PtyInfo {
        pid: u32,
    }
    let info: PtyInfo = serde_json::from_str(&text)
        .map_err(|e| ProcError::Spawn(format!("pty 握手解析失败: {e}")))?;
    Ok(info.pid)
}

/// 平台进程树击杀(Unix 进程组 SIGKILL / Windows taskkill /T /F)。
async fn platform_kill(pty_pid: u32) {
    if pty_pid == 0 {
        return;
    }
    #[cfg(unix)]
    unsafe {
        // pty 以独立进程组启动(process_group(0)),pgid = pty_pid;
        // 组内含游戏进程,整组 SIGKILL
        libc::kill(-(pty_pid as i32), libc::SIGKILL);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt as _;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let _ = tokio::process::Command::new("taskkill")
            .args(["/PID", &pty_pid.to_string(), "/T", "/F"])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .await;
    }
    tracing::debug!(pty_pid, "process tree killed");
}

/// 实例输出编码 → pty `-coder` 参数。
fn coder_for(encoding: crate::instance::Encoding) -> &'static str {
    match encoding {
        crate::instance::Encoding::Utf8 => "utf-8",
        crate::instance::Encoding::Gbk => "gbk",
        crate::instance::Encoding::Big5 => "big5",
        crate::instance::Encoding::ShiftJis => "shift-jis",
        crate::instance::Encoding::Euckr => "euckr",
        crate::instance::Encoding::Gb18030 => "gb18030",
        crate::instance::Encoding::Utf16 => "utf-16",
    }
}

/// 把 bin 目录前置到 PATH(按平台路径分隔符拆分/重组;失败返回 None)。
fn prepend_path(bin_dir: &Path, path_var: &std::ffi::OsStr) -> Option<OsString> {
    let mut entries: Vec<PathBuf> = std::env::split_paths(path_var).collect();
    entries.insert(0, bin_dir.to_path_buf());
    std::env::join_paths(entries).ok()
}

/// 打开实例输出日志文件(每次启动新建一个;尽力而为,失败仅告警不影响启动)。
///
/// 路径:`{data}/instances/{id}/logs/{id}-{启动时间}.log`,时间采用 UTC
/// `%Y%m%d-%H%M%S%3f`(含毫秒,避免同一秒内重启覆盖上一份日志)。返回
/// None = 目录/文件创建失败。
async fn open_log_file(instances_root: &Path, id: Uuid) -> Option<tokio::fs::File> {
    let dir = instances_root.join(id.to_string()).join("logs");
    if let Err(e) = std::fs::create_dir_all(&dir) {
        tracing::warn!(instance = %id, error = %e, "create instance log dir failed");
        return None;
    }
    let ts = chrono::Utc::now().format("%Y%m%d-%H%M%S%3f");
    let path = dir.join(format!("{id}-{ts}.log"));
    match tokio::fs::File::create(&path).await {
        Ok(file) => {
            tracing::info!(instance = %id, path = %path.display(), "instance log file opened");
            Some(file)
        }
        Err(e) => {
            tracing::warn!(instance = %id, error = %e, "open instance log file failed");
            None
        }
    }
}

// ────────────────────────── 控制通道 ──────────────────────────

/// 拨号控制通道(Unix socket / Windows 命名管道),带重试(pty 就绪竞态)。
async fn dial_control(endpoint: &str) -> Option<ControlStream> {
    for _ in 0..CONTROL_DIAL_ATTEMPTS {
        match try_dial(endpoint).await {
            Ok(stream) => return Some(stream),
            Err(_) => tokio::time::sleep(Duration::from_millis(100)).await,
        }
    }
    None
}

#[cfg(unix)]
type ControlStream = tokio::net::UnixStream;

#[cfg(unix)]
async fn try_dial(endpoint: &str) -> std::io::Result<ControlStream> {
    tokio::net::UnixStream::connect(endpoint).await
}

#[cfg(windows)]
type ControlStream = tokio::net::windows::named_pipe::NamedPipeClient;

#[cfg(windows)]
async fn try_dial(endpoint: &str) -> std::io::Result<ControlStream> {
    use tokio::net::windows::named_pipe::ClientOptions;
    ClientOptions::new().open(endpoint)
}

/// 建立控制通道读写任务:
/// - 写:mpsc ControlCommand → RESIZE 帧(daemon → pty)
/// - 读:ERROR / EXIT / INFO 帧(pty → daemon);EXIT 写回退出码并唤醒等待者
fn spawn_control_tasks(handle: &Arc<ProcHandle>, conn: ControlStream) {
    let (mut reader, mut writer) = tokio::io::split(conn);
    let (tx, mut rx) = mpsc::channel::<ControlCommand>(16);
    {
        let mut slot = handle.control_tx.lock().unwrap();
        *slot = Some(tx);
    }

    // 写任务
    tokio::spawn(async move {
        while let Some(cmd) = rx.recv().await {
            let (frame_type, payload): (u8, Vec<u8>) = match cmd {
                ControlCommand::Resize(w, h) => (
                    FRAME_RESIZE,
                    serde_json::json!({"width": w, "height": h})
                        .to_string()
                        .into_bytes(),
                ),
            };
            let mut frame = Vec::with_capacity(3 + payload.len());
            frame.push(frame_type);
            frame.extend_from_slice(&(payload.len() as u16).to_be_bytes());
            frame.extend_from_slice(&payload);
            if writer.write_all(&frame).await.is_err() {
                break;
            }
            let _ = writer.flush().await;
        }
    });

    // 读任务(ERROR/EXIT/INFO;进程退出时 pty 上报 EXIT 后自行退出)
    let exit_code = handle.exit_frame_code.clone();
    let notified = handle.clone();
    tokio::spawn(async move {
        loop {
            let mut header = [0u8; 3];
            if reader.read_exact(&mut header).await.is_err() {
                break;
            }
            let frame_type = header[0];
            let len = u16::from_be_bytes([header[1], header[2]]) as usize;
            let mut payload = vec![0u8; len];
            if len > 0 && reader.read_exact(&mut payload).await.is_err() {
                break;
            }
            match frame_type {
                FRAME_EXIT => {
                    #[derive(serde::Deserialize)]
                    struct ExitMsg {
                        code: i32,
                    }
                    if let Ok(msg) = serde_json::from_slice::<ExitMsg>(&payload) {
                        exit_code.store(msg.code, Ordering::Relaxed);
                    }
                }
                FRAME_ERROR => {
                    let msg = String::from_utf8_lossy(&payload);
                    tracing::warn!(target: "pty", "control error frame: {msg}");
                }
                FRAME_INFO => {
                    let msg = String::from_utf8_lossy(&payload);
                    tracing::debug!(target: "pty", "control info frame: {msg}");
                }
                _ => {}
            }
        }
        tracing::debug!(instance = %notified.instance_id, "control channel closed");
    });
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handshake_json_parses_pid() {
        let text = String::from_utf8_lossy(b"{\"pid\": 12345}").trim().to_string();
        #[derive(serde::Deserialize)]
        struct PtyInfo {
            pid: u32,
        }
        let info: PtyInfo = serde_json::from_str(&text).unwrap();
        assert_eq!(info.pid, 12345);
    }

    #[tokio::test]
    async fn manager_handles_absent_instances() {
        let dir = std::env::temp_dir().join(format!("edgecube-proc-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let mgr = ProcManager::new(&dir);

        assert!(mgr.snapshot(Uuid::new_v4()).is_none());
        assert!(mgr.get(Uuid::new_v4()).is_none());
        mgr.remove(Uuid::new_v4()); // 不存在不报错
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn prepend_path_prepends_bin_dir() {
        let path_var = std::env::join_paths([
            PathBuf::from("/usr/bin"),
            PathBuf::from("/usr/local/bin"),
        ])
        .unwrap();
        let joined = prepend_path(Path::new("/rt/bin"), &path_var).unwrap();
        let entries: Vec<PathBuf> = std::env::split_paths(&joined).collect();
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0], PathBuf::from("/rt/bin"));
        assert_eq!(entries[1], PathBuf::from("/usr/bin"));
        assert_eq!(entries[2], PathBuf::from("/usr/local/bin"));
    }
}
