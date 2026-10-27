//! FRP 实例的运行：**一条隧道配置 = 一个可以独立运行的实例**。
//!
//! # 单位是「隧道配置」，不是游戏实例
//!
//! 一个 `config/frp/toml/<local_id>.toml` 就是一个 FRP 实例 —— 它有自己的
//! frpc 进程、自己启停，与游戏实例**没有从属关系**。游戏实例那边只是一个
//! **引用**（`InstanceConfig::frp_tunnel_id`）：起游戏实例时顺手把那条隧道也
//! 拉起来。于是：
//!
//! * 好几条游戏实例可以指向**同一条**隧道（各写各的 id）；
//! * 一条隧道**同时只有一个进程** —— 表以 `local_id` 为键，[`FrpRunManager::start`]
//!   发现已经在跑就原样返回，不会再起一个。
//!
//! 早先的版本是「每个游戏实例一个 frpc」（键是实例 id），那样既没法共用隧道，
//! 也让「公网入口」跟着游戏实例一起生死。现在反过来了。
//!
//! # 进程怎么管
//!
//! 用普通的 `std::process::Command`（piped stdio）而不是实例服务端那套 PTY：
//! frpc 不需要交互式控制台，只要能把日志收下来排错。于是：
//!
//! * **stdout / stderr 各起一个读线程**，按行塞进一个有上限的环形缓冲
//!   （[`LOG_LINES`] 行）—— 运行页把它显示出来，出问题时用户能自己看到原因；
//! * **另一个线程 `wait()`** 守着退出，退出码写回状态。这样「进程没了」不需要
//!   谁去轮询；
//! * **状态一变就发事件**（[`TOPIC_RUN`]）—— 从线程里直接 `bus.publish`，
//!   前端不用轮询；
//! * **停止是两段**：先 `SIGTERM`（frpc 自己会优雅收尾），给 [`STOP_GRACE`]
//!   这么久；还活着就 `SIGKILL` 整个进程组。
//!
//! 不用 `tokio::process`（tokio 没开 `process` feature），也不值得为一个常驻
//! 进程去开它：`spawn_blocking` + 线程足够，而且这里的操作本来就是阻塞的。

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};

use crate::event::EventBus;
use crate::module::builtin::runtime;
use crate::util::now_ms;

/// 运行状态变了。载荷 = [`FrpRun::to_wire_summary`]（不带日志 —— 日志可能很长，
/// 而这条事件是广播给所有连接的）。
pub const TOPIC_RUN: &str = "frp.run";

/// 日志环形缓冲留多少行。够排查就行，别把内存交给一个可能刷屏的子进程。
pub const LOG_LINES: usize = 200;

/// 优雅停止的等待上限：先 SIGTERM 等这么久，还活着再 SIGKILL。
const STOP_GRACE: std::time::Duration = std::time::Duration::from_secs(5);

/// 能拿来跑隧道的包类型（「运行环境」里 frp 的那个）。
const FRPC_PACKAGE_TYPE: &str = "frpc";

/// 一个 FRP 实例现在处于什么状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrpState {
    /// 起了，还没退出。
    Running,
    /// 自己退出了（或被杀）。`exit_code` 说清楚是怎么没的。
    Exited,
    /// 根本没起来（找不到可执行文件、隧道不存在、命令拼错了）。
    Failed,
}

impl FrpState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Exited => "exited",
            Self::Failed => "failed",
        }
    }

    /// 还在跑吗。
    pub fn alive(self) -> bool {
        matches!(self, Self::Running)
    }
}

/// 一条隧道的运行态。
pub struct FrpRun {
    /// 用的哪个 frp 环境（`frp-frpc-0.71.0-linux-x64`）。
    pub runtime_id: String,
    /// 哪条隧道（`SavedTunnel.local_id`）—— 也就是这个 FRP 实例的 id。
    pub local_id: String,
    pub tunnel_name: String,
    pub config_path: PathBuf,
    pub state: Mutex<FrpState>,
    pub pid: Mutex<Option<u32>>,
    pub started_at_ms: u64,
    /// 退出码（`state != Running` 时有意义）。
    pub exit_code: Mutex<Option<i32>>,
    /// 一句话说明：起不来 / 退出的原因。
    pub message: Mutex<Option<String>>,
    /// 最近若干行 stdout/stderr。
    pub log: Arc<Mutex<VecDeque<String>>>,
}

impl FrpRun {
    fn state(&self) -> FrpState {
        *self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// 还在跑吗。
    pub fn alive(&self) -> bool {
        self.state().alive()
    }

    /// 线上形状（`frp.run.get`）—— **带日志**，给运行页看。
    pub fn to_wire(&self) -> Value {
        let mut wire = self.to_wire_summary();
        let log: Vec<String> = self
            .log
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .cloned()
            .collect();
        wire["log"] = json!(log);
        wire
    }

    /// 线上形状（列表 / 事件）—— **不带日志**。
    pub fn to_wire_summary(&self) -> Value {
        json!({
            "local_id": self.local_id,
            "tunnel_name": self.tunnel_name,
            "state": self.state().as_str(),
            "runtime_id": self.runtime_id,
            "config_path": self.config_path.display().to_string(),
            "pid": *self.pid.lock().unwrap_or_else(|e| e.into_inner()),
            "started_at_ms": self.started_at_ms,
            "exit_code": *self.exit_code.lock().unwrap_or_else(|e| e.into_inner()),
            "message": self.message.lock().unwrap_or_else(|e| e.into_inner()).clone(),
        })
    }
}

/// 「这条隧道起不来」的原因。都是**给人看的一句话**。
#[derive(Debug)]
pub enum FrpStartError {
    /// 还没选（或选的那个）frpc 环境没装。
    RuntimeMissing(String),
    /// 环境记录里没有可执行文件（装了一半？）。
    RuntimeBroken(String),
    /// 隧道不存在 / 配置生成失败。
    Tunnel(String),
    /// 别的（起进程本身失败）。
    Spawn(String),
}

impl FrpStartError {
    pub fn message(&self) -> String {
        match self {
            Self::RuntimeMissing(id) => {
                format!("frp 环境 `{id}` 没装（去「网络映射」里换一个，或去「运行环境」装一个）")
            }
            Self::RuntimeBroken(id) => {
                format!("frp 环境 `{id}` 的记录里没有可执行文件，重装一次试试")
            }
            Self::Tunnel(reason) => reason.clone(),
            Self::Spawn(reason) => format!("起 frpc 失败：{reason}"),
        }
    }
}

/// 一个已装的 frpc 运行环境（「网络映射」页那个下拉的一项）。
#[derive(Debug, Clone)]
pub struct FrpcRuntime {
    pub id: String,
    /// 显示名：`frp 0.71.0`。
    pub name: String,
    /// 可执行文件的绝对路径（**不给前端**，只在起进程时用）。
    pub binary: PathBuf,
}

impl FrpcRuntime {
    pub fn to_wire(&self) -> Value {
        json!({ "id": self.id, "name": self.name })
    }
}

/// 找出这台机器上所有能跑隧道的 frpc 环境（已装好的那些）。
///
/// 「哪个包类型能跑隧道」这件事问 `runtime` 的厂商表，不在这儿另立一张。
pub fn frpc_runtimes(data_dir: &Path) -> Vec<FrpcRuntime> {
    let mut out: Vec<FrpcRuntime> = runtime::store::load_all(data_dir)
        .into_iter()
        .filter(|env| {
            env.package_type == FRPC_PACKAGE_TYPE
                && env.state == runtime::model::EnvState::Installed
        })
        .filter_map(|env| {
            let binary = env.binary.clone()?;
            let dir = runtime::store::env_dir(data_dir, &env.id);
            Some(FrpcRuntime {
                id: env.id.clone(),
                name: format!("frp {}", env.version),
                binary: dir.join(binary),
            })
        })
        .collect();
    // 稳定的顺序：装了好几个时，界面上的顺序不该每次都变
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

/// 所有 FRP 实例的进程表。**键是隧道的 `local_id`。**
pub struct FrpRunManager {
    runs: Mutex<HashMap<String, Arc<FrpRun>>>,
    /// 状态一变就往这儿发事件（克隆成本 = 一次 Arc 自增）。
    bus: EventBus,
}

impl std::fmt::Debug for FrpRunManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FrpRunManager")
            .field("count", &self.lock().len())
            .finish()
    }
}

impl FrpRunManager {
    pub fn new(bus: EventBus) -> Self {
        Self {
            runs: Mutex::new(HashMap::new()),
            bus,
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Arc<FrpRun>>> {
        self.runs.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn get(&self, local_id: &str) -> Option<Arc<FrpRun>> {
        self.lock().get(local_id).cloned()
    }

    /// 这个隧道现在有进程在跑吗。
    pub fn is_alive(&self, local_id: &str) -> bool {
        self.get(local_id).is_some_and(|run| run.alive())
    }

    /// 全部运行态（含已退出 / 起不来的记录），按隧道 id 排序。
    pub fn list(&self) -> Vec<Arc<FrpRun>> {
        let mut runs: Vec<Arc<FrpRun>> = self.lock().values().cloned().collect();
        runs.sort_by(|a, b| a.local_id.cmp(&b.local_id));
        runs
    }

    /// 停掉并摘掉某个隧道的进程（幂等：本来就没跑就直接返回 `None`）。
    ///
    /// 摘掉之后这条隧道在列表里就回到「未运行」。
    pub async fn stop_and_forget(&self, local_id: &str) -> Option<Arc<FrpRun>> {
        let run = self.lock().remove(local_id)?;
        stop_run(&run).await;
        self.publish(&run);
        Some(run)
    }

    /// 停掉所有（daemon 收摊时用）。
    pub async fn stop_all(&self) {
        let runs: Vec<Arc<FrpRun>> = self.lock().drain().map(|(_, run)| run).collect();
        for run in runs {
            stop_run(&run).await;
        }
    }

    /// 把一条运行态的现状广播出去。
    fn publish(&self, run: &FrpRun) {
        self.bus.publish(TOPIC_RUN, run.to_wire_summary());
    }
}

/// 起一个 frpc：`<环境目录>/<binary> -c <隧道 toml>`。
///
/// **已经在跑就原样返回**，不会再起一个 —— 「一条隧道同时只有一个进程」这条
/// 约束落在这里（顺带让「多条游戏实例连带启动同一条隧道」天然安全）。
pub fn start(
    local_id: &str,
    binary: PathBuf,
    runtime_id: &str,
    tunnel_name: &str,
    config_path: PathBuf,
    manager: &FrpRunManager,
) -> Result<Arc<FrpRun>, FrpStartError> {
    if let Some(running) = manager.get(local_id).filter(|run| run.alive()) {
        tracing::debug!(tunnel = %local_id, "这条隧道已经在跑了，不重复起");
        return Ok(running);
    }

    let mut command = Command::new(&binary);
    command.arg("-c").arg(&config_path);
    let run = spawn(
        local_id,
        &mut command,
        runtime_id,
        tunnel_name,
        config_path,
        manager,
    )
    .map_err(|e| match e {
        FrpStartError::Spawn(reason) => {
            FrpStartError::Spawn(format!("`{}` 起不来：{reason}", binary.display()))
        }
        other => other,
    })?;
    manager.publish(&run);
    Ok(run)
}

/// 起进程 + 挂上监视（日志 / 退出 / 独立进程组）。
///
/// 与 [`start`] 分开是为了让测试能塞一条别的命令进来 ——
/// 这一层要验的是「进程管理与日志收集」，跟 frp 本身无关。
fn spawn(
    local_id: &str,
    command: &mut Command,
    runtime_id: &str,
    tunnel_name: &str,
    config_path: PathBuf,
    manager: &FrpRunManager,
) -> Result<Arc<FrpRun>, FrpStartError> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // 单独开一个进程组：停止时能连它的子进程一起收掉，也不会被 Ctrl-C 波及
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }

    let mut child = command
        .spawn()
        .map_err(|e| FrpStartError::Spawn(e.to_string()))?;

    let pid = child.id();
    let log = Arc::new(Mutex::new(VecDeque::with_capacity(LOG_LINES)));
    let run = Arc::new(FrpRun {
        runtime_id: runtime_id.to_string(),
        local_id: local_id.to_string(),
        tunnel_name: tunnel_name.to_string(),
        config_path,
        state: Mutex::new(FrpState::Running),
        pid: Mutex::new(Some(pid)),
        started_at_ms: now_ms(),
        exit_code: Mutex::new(None),
        message: Mutex::new(None),
        log: log.clone(),
    });

    // stdout / stderr 各一个读线程
    if let Some(out) = child.stdout.take() {
        spawn_reader(out, log.clone());
    }
    if let Some(err) = child.stderr.take() {
        spawn_reader(err, log.clone());
    }

    // 退出守候：进程没了由它落状态 + 发事件，不需要谁去轮询
    {
        let run = run.clone();
        // 线程要 `'static`，借不了 `&FrpRunManager`；发事件只需要总线本身
        let bus = manager.bus.clone();
        std::thread::spawn(move || {
            let code = child.wait().ok().and_then(|status| status.code());
            let mut state = run.state.lock().unwrap_or_else(|e| e.into_inner());
            // 已经被人标成 Failed 就别覆盖（那条消息更重要）
            if *state != FrpState::Failed {
                *state = FrpState::Exited;
            }
            *run.exit_code.lock().unwrap_or_else(|e| e.into_inner()) = code;
            *run.pid.lock().unwrap_or_else(|e| e.into_inner()) = None;
            if run
                .message
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .is_none()
            {
                let text = match code {
                    Some(0) => "frpc 已退出".to_string(),
                    Some(code) => format!("frpc 异常退出（退出码 {code}）"),
                    None => "frpc 被信号终止".to_string(),
                };
                *run.message.lock().unwrap_or_else(|e| e.into_inner()) = Some(text);
            }
            drop(state);
            bus.publish(TOPIC_RUN, run.to_wire_summary());
        });
    }

    // 同一条隧道重复 start 时，旧进程先收掉 —— 否则两个 frpc 抢同一份配置。
    // 正常情况下走不到这里（上面已经挡了「还在跑」），留给「记录是死的但
    // 进程还在」这种边角（比如守候线程还没跑完）。
    if let Some(previous) = manager.lock().insert(local_id.to_string(), run.clone()) {
        shutdown_quiet(&previous);
    }
    Ok(run)
}

/// 一行一行地收进环形缓冲。
fn spawn_reader<R: std::io::Read + Send + 'static>(reader: R, log: Arc<Mutex<VecDeque<String>>>) {
    std::thread::spawn(move || {
        use std::io::BufRead;
        let lines = std::io::BufReader::new(reader).lines();
        for line in lines {
            let Ok(line) = line else { break };
            let mut buffer = log.lock().unwrap_or_else(|e| e.into_inner());
            if buffer.len() == LOG_LINES {
                buffer.pop_front();
            }
            buffer.push_back(line);
        }
    });
}

/// 停一个 frpc：SIGTERM → 等一会儿 → SIGKILL。
async fn stop_run(run: &Arc<FrpRun>) {
    let Some(pid) = *run.pid.lock().unwrap_or_else(|e| e.into_inner()) else {
        return;
    };

    #[cfg(unix)]
    {
        // frpc 自己监听 SIGTERM（Go 那边装了 handler），所以先礼后兵
        unsafe {
            libc::kill(pid as i32, libc::SIGTERM);
        }
        let deadline = std::time::Instant::now() + STOP_GRACE;
        while run.alive() && std::time::Instant::now() < deadline {
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
        if run.alive() {
            // 整个进程组一起收：frpc 自己不会再拉子进程，但这样更稳
            unsafe {
                libc::kill(-(pid as i32), libc::SIGKILL);
            }
            // 给守候线程一点时间把状态落下来
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
    }
    #[cfg(not(unix))]
    {
        // 非 unix 没有信号这一套：只能硬杀。留着这个分支是为了别让编译在这里断掉。
        let _ = pid;
    }
}

/// 记一次「没起来」：**在表里留一条 `failed`**，前端才看得到原因。
///
/// 为什么要留记录而不是「没进程就是没跑」：隧道起不来是用户要处理的事
/// （frpc 没装、隧道被删了、配置生成失败），列表里没有它就等于静默失败 ——
/// 尤其「游戏实例连带启动失败」这条路径，游戏实例本身是起得来的，
/// 不在这儿留一条用户根本不知道公网入口没起来。
pub fn record_failure(
    local_id: &str,
    runtime_id: Option<&str>,
    tunnel_name: &str,
    message: String,
    manager: &FrpRunManager,
) -> Arc<FrpRun> {
    let run = Arc::new(FrpRun {
        runtime_id: runtime_id.unwrap_or_default().to_string(),
        local_id: local_id.to_string(),
        tunnel_name: tunnel_name.to_string(),
        config_path: PathBuf::new(),
        state: Mutex::new(FrpState::Failed),
        pid: Mutex::new(None),
        started_at_ms: now_ms(),
        exit_code: Mutex::new(None),
        message: Mutex::new(Some(message)),
        log: Arc::new(Mutex::new(VecDeque::new())),
    });
    manager.lock().insert(local_id.to_string(), run.clone());
    manager.publish(&run);
    run
}

/// 清空某条隧道的日志缓冲。
pub fn clear_log(run: &FrpRun) {
    run.log.lock().unwrap_or_else(|e| e.into_inner()).clear();
}

/// 硬杀（不发信号、不等）—— 只在「同一条隧道被新的 start 顶掉」时用。
pub fn shutdown_quiet(run: &FrpRun) {
    let Some(pid) = *run.pid.lock().unwrap_or_else(|e| e.into_inner()) else {
        return;
    };
    #[cfg(unix)]
    unsafe {
        libc::kill(-(pid as i32), libc::SIGKILL);
    }
    #[cfg(not(unix))]
    let _ = pid;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 一个干净的事件总线（测试只关心「发得出去、不 panic」）。
    fn manager() -> FrpRunManager {
        FrpRunManager::new(EventBus::new(64))
    }

    /// 起一条**不是 frpc** 的假进程：这一层要验的是「进程管理与日志收集」，
    /// 跟 frp 本身无关 —— 所以直接给命令，不经过隧道配置那一套解析。
    fn start_fake(local_id: &str, script: &str, manager: &FrpRunManager) -> Arc<FrpRun> {
        #[cfg(unix)]
        let (program, args) = ("/bin/sh", vec!["-c", script]);
        #[cfg(not(unix))]
        let (program, args) = ("cmd", vec!["/C", script]);

        let mut command = Command::new(program);
        command.args(args);
        spawn(
            local_id,
            &mut command,
            "frp-frpc-test",
            "假隧道",
            PathBuf::from("/tmp/fake.toml"),
            manager,
        )
        .expect("假进程应当起得来")
    }

    /// 等到某个条件成立（日志 / 退出是别的线程落下来的，得等它一会儿）。
    fn wait_until(mut check: impl FnMut() -> bool) -> bool {
        for _ in 0..200 {
            if check() {
                return true;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        false
    }

    #[test]
    fn spawn_collects_logs_and_reports_the_pid() {
        let manager = manager();
        let run = start_fake("t1", "echo 第一行; echo 第二行", &manager);

        assert!(run.alive(), "刚起来应当是 running");
        assert!(run.to_wire_summary()["pid"].is_u64(), "应当有 pid");
        assert!(
            wait_until(|| {
                run.log
                    .lock()
                    .unwrap()
                    .iter()
                    .any(|line| line.contains("第二行"))
            }),
            "stdout 应当被收进日志：{:?}",
            run.log.lock().unwrap()
        );
    }

    /// **一条隧道同时只有一个进程**：重复 start 不会起第二个。
    #[test]
    fn starting_the_same_tunnel_twice_keeps_one_process() {
        let manager = manager();
        let first = start_fake("t1", "sleep 5", &manager);
        // 第二次走 start 那条路（会先查 is_alive）
        let second = start(
            "t1",
            PathBuf::from("/bin/true"),
            "frp-frpc-test",
            "假隧道",
            PathBuf::from("/tmp/fake.toml"),
            &manager,
        )
        .expect("已经在跑时不该报错");
        assert!(
            Arc::ptr_eq(&first, &second),
            "应当原样返回那个跑着的进程，而不是起一个新的"
        );
        assert!(manager.is_alive("t1"));

        shutdown_quiet(&first);
    }

    #[test]
    fn exit_code_and_state_are_written_when_the_process_dies() {
        let manager = manager();
        let run = start_fake("t1", "exit 3", &manager);
        assert!(
            wait_until(|| !run.alive()),
            "进程退出后 state 应当变成 exited"
        );
        let wire = run.to_wire();
        assert_eq!(wire["state"], json!("exited"));
        assert_eq!(wire["exit_code"], json!(3));
        assert_eq!(wire["pid"], json!(null));
        // 退出原因也留一句
        assert!(
            wire["message"].as_str().unwrap_or_default().contains('3'),
            "{wire}"
        );
    }

    /// 停掉之后记录被摘掉 —— 列表里这条回到「未运行」。
    #[tokio::test]
    async fn stop_removes_the_record() {
        let manager = manager();
        let _run = start_fake("t1", "sleep 30", &manager);
        assert!(manager.is_alive("t1"));

        assert!(manager.stop_and_forget("t1").await.is_some());
        assert!(manager.get("t1").is_none(), "记录应当被摘掉");
        assert!(!manager.is_alive("t1"));
        // 幂等：再停一次什么都不发生
        assert!(manager.stop_and_forget("t1").await.is_none());
    }

    /// 起不来的时候**要留一条 `failed`**，否则用户看不到任何原因
    /// （尤其「游戏实例连带启动失败」那条路径，游戏实例本身是起得来的）。
    #[test]
    fn failures_leave_a_visible_record() {
        let manager = manager();
        let run = record_failure(
            "t9",
            Some("frp-frpc-0.71.0"),
            "隧道",
            "没装 frpc".into(),
            &manager,
        );

        assert_eq!(run.state().as_str(), "failed");
        let wire = run.to_wire_summary();
        assert_eq!(wire["local_id"], json!("t9"));
        assert_eq!(wire["state"], json!("failed"));
        assert_eq!(wire["message"], json!("没装 frpc"));
        // 表里查得到，列表也看得到
        assert!(manager.get("t9").is_some());
        assert_eq!(manager.list().len(), 1);
    }

    /// 状态一变就发事件（前端不用轮询）。
    ///
    /// 走 [`start`] 而不是 [`spawn`]：发事件的逻辑在「起进程」那一层。
    /// `/bin/true` 不认 `-c`，起来就退 —— 正好一条用例同时验到
    /// 「起来推一条」与「退出再推一条」。
    #[cfg(unix)]
    #[test]
    fn state_changes_are_published() {
        let bus = EventBus::new(64);
        let mut events = bus.subscribe();
        let manager = FrpRunManager::new(bus);

        let run = start(
            "t1",
            PathBuf::from("/bin/true"),
            "frp-frpc-test",
            "假隧道",
            PathBuf::from("/tmp/fake.toml"),
            &manager,
        )
        .expect("应当能起");

        let first = events.try_recv().expect("起进程应当推一条事件");
        assert_eq!(first.topic, TOPIC_RUN);
        assert_eq!(first.data["local_id"], json!("t1"));
        assert_eq!(first.data["runtime_id"], json!("frp-frpc-test"));

        // 进程会立刻退出，再推一条 `exited`
        assert!(wait_until(|| !run.alive()));
        assert!(
            wait_until(|| {
                std::iter::from_fn(|| events.try_recv().ok())
                    .any(|event| event.data["state"] == json!("exited"))
            }),
            "退出也应当推一条事件"
        );
    }

    #[test]
    fn clear_log_empties_the_buffer() {
        let manager = manager();
        let run = start_fake("t1", "echo 要清掉的", &manager);
        assert!(wait_until(|| !run.log.lock().unwrap().is_empty()));
        clear_log(&run);
        assert!(run.log.lock().unwrap().is_empty());
    }

    /// 日志缓冲是有上限的：一个刷屏的子进程不该把内存吃光。
    #[test]
    fn the_log_buffer_is_bounded() {
        let manager = manager();
        // 印比上限多一倍的行
        let run = start_fake(
            "t1",
            "i=0; while [ $i -lt 400 ]; do echo 行$i; i=$((i+1)); done",
            &manager,
        );
        assert!(wait_until(|| !run.alive()), "这条应当很快跑完");
        let log = run.log.lock().unwrap();
        assert!(
            log.len() <= LOG_LINES,
            "日志不该超过 {LOG_LINES} 行：{}",
            log.len()
        );
        // 留下的是**最后**那些（前面的被挤掉了）
        assert!(
            log.iter().any(|line| line.contains("行399")),
            "应当留最新的"
        );
    }

    /// 装没装 frpc 决定「能不能跑隧道」—— 一条都没有时清单是空的。
    #[test]
    fn frpc_runtimes_lists_nothing_in_a_empty_data_dir() {
        let dir = std::env::temp_dir().join(format!(
            "ec-frp-runtimes-{}-{}",
            std::process::id(),
            crate::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        assert!(frpc_runtimes(&dir).is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
