//! Frp 隧道管理(契约 /frp/*)。
//!
//! 数据目录布局:
//!   frp/tunnels.json    全部隧道(数组;daemon 自行维护,损坏时跳过并告警)
//!
//! 隧道为「自定义隧道」模型:用户直接填写 frps 服务端地址与代理(不依赖任何
//! 第三方 frp 供应商),运行 `frpc` 时把隧道渲染为 TOML 配置。frpc 二进制
//! 由运行时模块(fatedier/frp GitHub Releases)安装,路径从 RuntimeManager 取。

use std::collections::VecDeque;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Duration;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::process::Stdio;
use tokio::io::AsyncBufReadExt;
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::proc::EXIT_CODE_NONE;

/// 隧道数据目录/文件名(相对 daemon 数据目录)。
const FRP_DIR: &str = "frp";
const TUNNELS_FILE: &str = "tunnels.json";

/// 代理名称长度上限(避免拼进 TOML 时失控)。
const MAX_NAME_LEN: usize = 64;
/// frpc 内存日志上限(行)。
const LOG_LIMIT: usize = 2000;
/// 停止等待进程退出的上限(50 × 100ms = 5s)。
const STOP_POLLS: u32 = 50;

/// frpc 二进制路径解析器(由 main 装配注入 RuntimeManager::frpc_binary)。
pub type FrpcBinaryResolver = Arc<dyn Fn() -> Option<PathBuf> + Send + Sync>;

/// 当前 frpc 进程句柄(全局唯一;退出后保留到惰性清理,供 status/logs 读取)。
pub struct FrpcProcess {
    pub tunnel_id: Uuid,
    pub started_at: DateTime<Utc>,
    /// stop() 触发 kill。
    kill_tx: mpsc::Sender<()>,
    /// 进程已退出(含被杀)。
    done: Arc<AtomicBool>,
    /// 退出码(EXIT_CODE_NONE = 未知/未退出)。
    exit_code: Arc<AtomicI32>,
    /// 输出行(合并 stdout/stderr,上限 LOG_LIMIT)。
    logs: Arc<RwLock<VecDeque<String>>>,
}

/// frpc 运行状态(契约 FrpStatus)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FrpStatus {
    pub running: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tunnel_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub started_at: Option<DateTime<Utc>>,
    /// 未运行时的上次退出码。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
}

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

/// 代理协议类型(契约 ProxyType)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProxyType {
    Tcp,
    Udp,
    Http,
    Https,
}

impl ProxyType {
    pub fn as_str(self) -> &'static str {
        match self {
            ProxyType::Tcp => "tcp",
            ProxyType::Udp => "udp",
            ProxyType::Http => "http",
            ProxyType::Https => "https",
        }
    }
}

/// 单个代理(契约 TunnelProxy)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TunnelProxy {
    pub name: String,
    #[serde(rename = "type")]
    pub proxy_type: ProxyType,
    pub local_ip: String,
    pub local_port: u16,
    /// tcp/udp 必填;http/https 无需(用 custom_domains 路由)。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remote_port: Option<u16>,
    /// http/https 必填(至少一个域名);tcp/udp 忽略。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_domains: Option<Vec<String>>,
}

/// 隧道(契约 TunnelInfo;不含运行状态,运行状态见 GET /frp/status)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TunnelInfo {
    pub id: Uuid,
    pub name: String,
    pub server_addr: String,
    pub server_port: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth_token: Option<String>,
    pub proxies: Vec<TunnelProxy>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// 创建/更新隧道请求(契约 TunnelInput)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TunnelInput {
    pub name: String,
    pub server_addr: String,
    pub server_port: u16,
    #[serde(default)]
    pub user: Option<String>,
    #[serde(default)]
    pub auth_token: Option<String>,
    pub proxies: Vec<TunnelProxy>,
}

// ────────────────────────── 错误 ──────────────────────────

#[derive(Debug)]
pub enum FrpError {
    /// 隧道不存在(404 tunnel_not_found)。
    NotFound(String),
    /// 隧道名重复(409 duplicate_name)。
    DuplicateName(String),
    /// 参数非法(400 invalid_request)。
    Invalid(String),
    /// 已有 frpc 在运行(409 frpc_busy)。
    Busy(String),
    /// frpc 未在运行(409 frpc_not_running)。
    NotRunning(String),
    /// 未安装 frpc 运行时(409 frpc_runtime_missing)。
    RuntimeMissing(String),
    /// 进程启动失败(500 frpc_spawn_failed)。
    Spawn(String),
    Io(std::io::Error),
}

impl FrpError {
    /// 契约错误码。
    pub fn code(&self) -> &'static str {
        match self {
            FrpError::NotFound(_) => "tunnel_not_found",
            FrpError::DuplicateName(_) => "duplicate_name",
            FrpError::Invalid(_) => "invalid_request",
            FrpError::Busy(_) => "frpc_busy",
            FrpError::NotRunning(_) => "frpc_not_running",
            FrpError::RuntimeMissing(_) => "frpc_runtime_missing",
            FrpError::Spawn(_) => "frpc_spawn_failed",
            FrpError::Io(_) => "frp_store_error",
        }
    }

    /// 对应 HTTP 状态码。
    pub fn status(&self) -> u16 {
        match self {
            FrpError::NotFound(_) => 404,
            FrpError::DuplicateName(_) | FrpError::Busy(_) | FrpError::NotRunning(_)
            | FrpError::RuntimeMissing(_) => 409,
            FrpError::Invalid(_) => 400,
            FrpError::Spawn(_) | FrpError::Io(_) => 500,
        }
    }
}

impl std::fmt::Display for FrpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrpError::NotFound(m)
            | FrpError::DuplicateName(m)
            | FrpError::Invalid(m)
            | FrpError::Busy(m)
            | FrpError::NotRunning(m)
            | FrpError::RuntimeMissing(m)
            | FrpError::Spawn(m) => f.write_str(m),
            FrpError::Io(e) => write!(f, "io error: {e}"),
        }
    }
}

impl std::error::Error for FrpError {}

impl From<std::io::Error> for FrpError {
    fn from(e: std::io::Error) -> Self {
        FrpError::Io(e)
    }
}

// ────────────────────────── 管理器 ──────────────────────────

pub struct FrpManager {
    /// `{data}/frp`。
    root: PathBuf,
    /// 内存注册表:保持落盘顺序,list 原样返回。
    tunnels: RwLock<Vec<TunnelInfo>>,
    /// 全局唯一的 frpc 进程(None = 未运行)。
    running: RwLock<Option<Arc<FrpcProcess>>>,
    /// 上次退出信息(惰性清理时记录;供 status 展示退出码)。
    last_exit: RwLock<Option<(Uuid, i32)>>,
    /// 上次进程日志快照(退出后仍可读取)。
    last_logs: RwLock<Option<VecDeque<String>>>,
    /// frpc 二进制路径解析器(main 装配注入;None = 未注入)。
    frpc_resolver: std::sync::Mutex<Option<FrpcBinaryResolver>>,
}

impl FrpManager {
    /// 扫描 `{data}/frp/tunnels.json` 加载全部隧道;文件缺失视为空,
    /// 损坏仅告警跳过(不阻塞 daemon 启动)。
    pub fn load(data_dir: &Path) -> std::io::Result<Self> {
        let root = data_dir.join(FRP_DIR);
        fs::create_dir_all(&root)?;

        let path = root.join(TUNNELS_FILE);
        let tunnels = match fs::read(&path) {
            Ok(bytes) => match serde_json::from_slice::<Vec<TunnelInfo>>(&bytes) {
                Ok(list) => list,
                Err(e) => {
                    tracing::warn!(path = %path.display(), "skipping unparsable tunnels: {e}");
                    Vec::new()
                }
            },
            Err(_) => Vec::new(),
        };

        tracing::info!(count = tunnels.len(), "frp tunnels loaded");
        Ok(FrpManager {
            root,
            tunnels: RwLock::new(tunnels),
            running: RwLock::new(None),
            last_exit: RwLock::new(None),
            last_logs: RwLock::new(None),
            frpc_resolver: std::sync::Mutex::new(None),
        })
    }

    /// 注入 frpc 二进制路径解析器(main 装配时调用一次)。
    pub fn set_frpc_resolver(&self, resolver: FrpcBinaryResolver) {
        *self.frpc_resolver.lock().unwrap() = Some(resolver);
    }

    /// 隧道列表(契约 GET /frp/tunnels)。
    pub fn list(&self) -> Vec<TunnelInfo> {
        self.tunnels.read().unwrap().clone()
    }

    /// 按 id 查询(未找到 → None)。
    pub fn get(&self, id: Uuid) -> Option<TunnelInfo> {
        self.tunnels.read().unwrap().iter().find(|t| t.id == id).cloned()
    }

    /// 创建隧道(契约 POST /frp/tunnels):校验 → 生成 id → 落盘 → 登记。
    pub fn create(&self, input: TunnelInput) -> std::result::Result<TunnelInfo, FrpError> {
        validate_input(&input)?;
        let now = Utc::now();
        let tunnel = TunnelInfo {
            id: Uuid::new_v4(),
            name: input.name.trim().to_string(),
            server_addr: input.server_addr.trim().to_string(),
            server_port: input.server_port,
            user: trim_opt(input.user),
            auth_token: trim_opt(input.auth_token),
            proxies: input.proxies,
            created_at: now,
            updated_at: now,
        };

        let mut tunnels = self.tunnels.write().unwrap();
        if tunnels.iter().any(|t| t.name == tunnel.name) {
            return Err(FrpError::DuplicateName(format!(
                "隧道名「{}」已存在",
                tunnel.name
            )));
        }
        self.persist_locked(&tunnels, &tunnel)?;
        tunnels.push(tunnel.clone());
        Ok(tunnel)
    }

    /// 更新隧道(契约 PUT /frp/tunnels/{tunnelId}):全量替换,保留 id 与创建时间。
    pub fn update(&self, id: Uuid, input: TunnelInput) -> std::result::Result<TunnelInfo, FrpError> {
        validate_input(&input)?;
        let mut tunnels = self.tunnels.write().unwrap();
        let Some(index) = tunnels.iter().position(|t| t.id == id) else {
            return Err(FrpError::NotFound(format!("隧道 {id} 不存在")));
        };
        if tunnels
            .iter()
            .enumerate()
            .any(|(i, t)| i != index && t.name == input.name.trim())
        {
            return Err(FrpError::DuplicateName(format!(
                "隧道名「{}」已存在",
                input.name.trim()
            )));
        }

        let old = &tunnels[index];
        let tunnel = TunnelInfo {
            id,
            name: input.name.trim().to_string(),
            server_addr: input.server_addr.trim().to_string(),
            server_port: input.server_port,
            user: trim_opt(input.user),
            auth_token: trim_opt(input.auth_token),
            proxies: input.proxies,
            created_at: old.created_at,
            updated_at: Utc::now(),
        };
        self.persist_locked(&tunnels, &tunnel)?;
        tunnels[index] = tunnel.clone();
        Ok(tunnel)
    }

    /// 删除隧道(契约 DELETE /frp/tunnels/{tunnelId})。
    pub fn delete(&self, id: Uuid) -> std::result::Result<(), FrpError> {
        let mut tunnels = self.tunnels.write().unwrap();
        let Some(index) = tunnels.iter().position(|t| t.id == id) else {
            return Err(FrpError::NotFound(format!("隧道 {id} 不存在")));
        };
        let before = tunnels.len();
        let removed = tunnels.remove(index);
        self.persist(&tunnels)?;
        tracing::info!(tunnel = %id, name = %removed.name, "frp tunnel deleted");
        debug_assert_eq!(before, tunnels.len() + 1);
        Ok(())
    }

    // ── 进程控制(全局唯一 frpc) ────────────────────────────────

    /// 启动 frpc(契约 POST /frp/start):渲染隧道 TOML → 写运行目录 →
    /// spawn 全局唯一 frpc。已在运行 → 409。
    pub async fn start(&self, tunnel_id: Uuid) -> std::result::Result<(), FrpError> {
        let tunnel = self
            .get(tunnel_id)
            .ok_or_else(|| FrpError::NotFound(format!("隧道 {tunnel_id} 不存在")))?;

        // 已有进程(含已退出未清理的残留)则拒绝
        {
            let mut running = self.running.write().unwrap();
            if let Some(proc) = running.as_ref() {
                if !proc.done.load(Ordering::Acquire) {
                    return Err(FrpError::Busy(format!(
                        "frpc 已在运行(隧道 {})",
                        proc.tunnel_id
                    )));
                }
            }
            let resolver = self.frpc_resolver.lock().unwrap();
            let binary = resolver
                .as_ref()
                .and_then(|r| r())
                .ok_or_else(|| {
                    FrpError::RuntimeMissing(
                        "未安装 frpc 运行时,请先在「运行时管理」中安装 frpc".into(),
                    )
                })?;

            // 运行目录:每次启动重建,避免旧配置残留
            let run_dir = self.root.join("run").join(tunnel_id.to_string());
            if run_dir.exists() {
                fs::remove_dir_all(&run_dir)
                    .map_err(|e| FrpError::Spawn(format!("清理运行目录失败:{e}")))?;
            }
            fs::create_dir_all(&run_dir).map_err(FrpError::Io)?;
            let config_path = run_dir.join("frpc.toml");
            fs::write(&config_path, self.render_toml(&tunnel)).map_err(FrpError::Io)?;

            let mut child = Command::new(&binary)
                .arg("-c")
                .arg(&config_path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .kill_on_drop(true)
                .spawn()
                .map_err(|e| {
                    FrpError::Spawn(format!("启动 frpc 失败({}):{e}", binary.display()))
                })?;
            let stdout = child
                .stdout
                .take()
                .ok_or_else(|| FrpError::Spawn("无法接管 frpc 标准输出".into()))?;
            let stderr = child
                .stderr
                .take()
                .ok_or_else(|| FrpError::Spawn("无法接管 frpc 错误输出".into()))?;

            let (kill_tx, kill_rx) = mpsc::channel(1);
            let proc = Arc::new(FrpcProcess {
                tunnel_id,
                started_at: Utc::now(),
                kill_tx,
                done: Arc::new(AtomicBool::new(false)),
                exit_code: Arc::new(AtomicI32::new(EXIT_CODE_NONE)),
                logs: Arc::new(RwLock::new(VecDeque::new())),
            });

            spawn_wait_task(child, kill_rx, Arc::clone(&proc));
            *running = Some(Arc::clone(&proc));
            tracing::info!(tunnel = %tunnel_id, binary = %binary.display(), "frpc started");
        }
        Ok(())
    }

    /// 停止 frpc(契约 POST /frp/stop):触发 kill 并等待退出(约 5s)。
    /// 未在运行 → 409。
    pub async fn stop(&self) -> std::result::Result<(), FrpError> {
        let proc = {
            let running = self.running.read().unwrap();
            match running.as_ref() {
                Some(proc) if !proc.done.load(Ordering::Acquire) => Arc::clone(proc),
                _ => return Err(FrpError::NotRunning("frpc 未在运行".into())),
            }
        };
        let _ = proc.kill_tx.send(()).await;
        for _ in 0..STOP_POLLS {
            if proc.done.load(Ordering::Acquire) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        tracing::info!(tunnel = %proc.tunnel_id, "frpc stopped");
        Ok(())
    }

    /// 运行状态(契约 GET /frp/status);惰性清理已退出进程并记录退出码/日志。
    pub fn status(&self) -> FrpStatus {
        let mut running = self.running.write().unwrap();
        match running.take() {
            Some(proc) if !proc.done.load(Ordering::Acquire) => {
                *running = Some(Arc::clone(&proc));
                FrpStatus {
                    running: true,
                    tunnel_id: Some(proc.tunnel_id),
                    started_at: Some(proc.started_at),
                    exit_code: None,
                }
            }
            Some(proc) => {
                // 已退出:记录退出码与日志快照,供 status/logs 继续读取
                let code = proc.exit_code.load(Ordering::Relaxed);
                let code = (code != EXIT_CODE_NONE).then_some(code);
                if let Some(code) = code {
                    *self.last_exit.write().unwrap() = Some((proc.tunnel_id, code));
                }
                *self.last_logs.write().unwrap() = Some(proc.logs.read().unwrap().clone());
                FrpStatus {
                    running: false,
                    tunnel_id: None,
                    started_at: None,
                    exit_code: code,
                }
            }
            None => {
                let last = self.last_exit.read().unwrap();
                FrpStatus {
                    running: false,
                    tunnel_id: None,
                    started_at: None,
                    exit_code: last.map(|(_, c)| c),
                }
            }
        }
    }

    /// frpc 日志(契约 GET /frp/logs?tail=):最近 tail 行(默认 200)。
    /// 退出后仍返回最后快照。
    pub fn logs(&self, tail: usize) -> Vec<String> {
        let tail = tail.clamp(1, LOG_LIMIT);
        let running = self.running.read().unwrap();
        let source = match running.as_ref() {
            Some(proc) => proc.logs.read().unwrap().clone(),
            None => self
                .last_logs
                .read()
                .unwrap()
                .clone()
                .unwrap_or_default(),
        };
        source.iter().rev().take(tail).cloned().collect::<Vec<_>>().into_iter().rev().collect()
    }

    /// daemon 关闭时调用:终止正在运行的 frpc(尽力而为)。
    pub async fn shutdown(&self) {
        let proc = self.running.read().unwrap().clone();
        if let Some(proc) = proc {
            if !proc.done.load(Ordering::Acquire) {
                let _ = proc.kill_tx.send(()).await;
            }
        }
    }

    /// 渲染隧道为 frpc TOML 配置(写入临时目录后由进程控制层启动)。
    pub fn render_toml(&self, tunnel: &TunnelInfo) -> String {
        render_toml(tunnel)
    }

    /// 全量落盘(带写入校验);内存与磁盘不一致时不落盘。
    fn persist(&self, tunnels: &[TunnelInfo]) -> std::result::Result<(), FrpError> {
        let path = self.root.join(TUNNELS_FILE);
        let json = serde_json::to_string_pretty(tunnels).map_err(|e| {
            FrpError::Invalid(format!("隧道序列化失败:{e}"))
        })?;
        fs::write(&path, json)?;
        Ok(())
    }

    /// 落盘并返回目标隧道(追加/替换后的内存视图由调用方维护)。
    fn persist_locked(
        &self,
        tunnels: &[TunnelInfo],
        target: &TunnelInfo,
    ) -> std::result::Result<(), FrpError> {
        let mut next = tunnels.to_vec();
        match next.iter_mut().find(|t| t.id == target.id) {
            Some(slot) => *slot = target.clone(),
            None => next.push(target.clone()),
        }
        self.persist(&next)
    }
}

// ────────────────────────── 校验 ──────────────────────────

/// 请求级校验(不含名称唯一性,唯一性依赖注册表由 create/update 处理)。
fn validate_input(input: &TunnelInput) -> std::result::Result<(), FrpError> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(FrpError::Invalid("隧道名不能为空".into()));
    }
    if name.chars().count() > MAX_NAME_LEN {
        return Err(FrpError::Invalid(format!(
            "隧道名过长(上限 {MAX_NAME_LEN} 字符)"
        )));
    }

    if input.server_addr.trim().is_empty() {
        return Err(FrpError::Invalid("frps 服务器地址不能为空".into()));
    }
    if input.server_port == 0 {
        return Err(FrpError::Invalid("frps 服务器端口必须为 1-65535".into()));
    }

    if input.proxies.is_empty() {
        return Err(FrpError::Invalid("至少需要一个代理".into()));
    }
    let mut seen = std::collections::HashSet::new();
    for proxy in &input.proxies {
        let pname = proxy.name.trim();
        if pname.is_empty() {
            return Err(FrpError::Invalid("代理名称不能为空".into()));
        }
        if !seen.insert(pname.to_string()) {
            return Err(FrpError::Invalid(format!(
                "代理名称「{pname}」重复"
            )));
        }
        if proxy.local_ip.trim().is_empty() {
            return Err(FrpError::Invalid(format!(
                "代理「{pname}」的本地地址不能为空"
            )));
        }
        if proxy.local_port == 0 {
            return Err(FrpError::Invalid(format!(
                "代理「{pname}」的本地端口必须为 1-65535"
            )));
        }
        match proxy.proxy_type {
            ProxyType::Tcp | ProxyType::Udp => {
                let rp = proxy.remote_port.ok_or_else(|| {
                    FrpError::Invalid(format!("tcp/udp 代理「{pname}」需要远程端口"))
                })?;
                if rp == 0 {
                    return Err(FrpError::Invalid(format!(
                        "代理「{pname}」的远程端口必须为 1-65535"
                    )));
                }
            }
            ProxyType::Http | ProxyType::Https => {
                let domains = proxy
                    .custom_domains
                    .as_deref()
                    .map(|d| d.iter().map(|s| s.trim()).filter(|s| !s.is_empty()).collect::<Vec<_>>())
                    .unwrap_or_default();
                if domains.is_empty() {
                    return Err(FrpError::Invalid(format!(
                        "http/https 代理「{pname}」需要至少一个自定义域名"
                    )));
                }
            }
        }
    }
    Ok(())
}

/// None 或空白字符串 → None(TOML 生成时跳过该行)。
fn trim_opt(s: Option<String>) -> Option<String> {
    s.map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

// ────────────────────────── 进程 wait 任务 ──────────────────────────

/// 后台任务:泵 stdout/stderr 到日志 → 等待退出(kill 信号或自然退出)→
/// 写退出码并标记 done。
fn spawn_wait_task(mut child: Child, mut kill_rx: mpsc::Receiver<()>, proc: Arc<FrpcProcess>) {
    let logs = Arc::clone(&proc.logs);
    tokio::spawn(async move {
        let out_logs = Arc::clone(&logs);
        let err_logs = Arc::clone(&logs);
        let out = tokio::spawn(pump_lines(child.stdout.take(), out_logs));
        let err = tokio::spawn(pump_lines(child.stderr.take(), err_logs));

        let code = tokio::select! {
            _ = kill_rx.recv() => {
                let _ = child.kill().await;
                let _ = child.wait().await;
                None
            }
            status = child.wait() => status.ok().and_then(|s| s.code()),
        };
        out.abort();
        err.abort();

        proc.exit_code
            .store(code.unwrap_or(EXIT_CODE_NONE), Ordering::Relaxed);
        proc.done.store(true, Ordering::Release);
        tracing::debug!(tunnel = %proc.tunnel_id, exit_code = ?code, "frpc exited");
    });
}

/// 逐行泵取子进程输出到共享日志缓冲(超过上限丢最旧)。
async fn pump_lines<R>(reader: Option<R>, logs: Arc<RwLock<VecDeque<String>>>)
where
    R: tokio::io::AsyncRead + Unpin,
{
    let Some(reader) = reader else { return };
    let mut lines = tokio::io::BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut guard = logs.write().unwrap();
        if guard.len() >= LOG_LIMIT {
            guard.pop_front();
        }
        guard.push_back(line);
    }
}

// ────────────────────────── TOML 渲染 ──────────────────────────

/// 隧道 → frpc.toml(仅自定义隧道支持;顺序:serverAddr/serverPort/user/
/// auth.token/log + 每个代理一个 [[proxies]] 段)。
pub fn render_toml(tunnel: &TunnelInfo) -> String {
    let mut b = String::new();
    b += &format!("serverAddr = {}\n", toml_q(&tunnel.server_addr));
    b += &format!("serverPort = {}\n", tunnel.server_port);
    if let Some(u) = tunnel.user.as_deref().filter(|s| !s.is_empty()) {
        b += &format!("user = {}\n", toml_q(u));
    }
    if let Some(t) = tunnel.auth_token.as_deref().filter(|s| !s.is_empty()) {
        b += &format!("auth.token = {}\n", toml_q(t));
    }
    b += "log.to = \"console\"\nlog.level = \"info\"\n\n";

    for p in &tunnel.proxies {
        b += "[[proxies]]\n";
        b += &format!("name = {}\n", toml_q(&p.name));
        b += &format!("type = {}\n", toml_q(p.proxy_type.as_str()));
        b += &format!("localIP = {}\n", toml_q(&p.local_ip));
        b += &format!("localPort = {}\n", p.local_port);
        if let Some(rp) = p.remote_port {
            b += &format!("remotePort = {rp}\n");
        }
        if let Some(ds) = &p.custom_domains {
            let list = ds
                .iter()
                .map(|d| toml_q(d.trim()))
                .collect::<Vec<_>>()
                .join(", ");
            b += &format!("customDomains = [{list}]\n");
        }
        b += "\n";
    }
    b
}

/// TOML 基本字符串转义(反斜杠、双引号与控制字符)。
fn toml_q(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_input() -> TunnelInput {
        TunnelInput {
            name: " 我的隧道 ".into(),
            server_addr: " frp.example.com ".into(),
            server_port: 7000,
            user: Some(" alice ".into()),
            auth_token: Some("".into()),
            proxies: vec![
                TunnelProxy {
                    name: "mc".into(),
                    proxy_type: ProxyType::Tcp,
                    local_ip: "127.0.0.1".into(),
                    local_port: 25565,
                    remote_port: Some(25565),
                    custom_domains: None,
                },
                TunnelProxy {
                    name: "web".into(),
                    proxy_type: ProxyType::Http,
                    local_ip: "127.0.0.1".into(),
                    local_port: 8080,
                    remote_port: None,
                    custom_domains: Some(vec!["mc.example.com".into(), " beta.example.com ".into()]),
                },
            ],
        }
    }

    #[test]
    fn validate_accepts_wellformed_input() {
        assert!(validate_input(&sample_input()).is_ok());
    }

    #[test]
    fn validate_rejects_bad_input() {
        let cases: Vec<fn() -> TunnelInput> = vec![
            || TunnelInput { name: "  ".into(), ..sample_input() },
            || TunnelInput { server_port: 0, ..sample_input() },
            || TunnelInput { server_addr: "".into(), ..sample_input() },
            || TunnelInput { proxies: vec![], ..sample_input() },
            || {
                let mut t = sample_input();
                t.proxies[0].name = "  ".into();
                t
            },
            || {
                let mut t = sample_input();
                t.proxies[1].name = "mc".into(); // 与第一个重复
                t
            },
            || {
                let mut t = sample_input();
                t.proxies[0].remote_port = None; // tcp 缺远程端口
                t
            },
            || {
                let mut t = sample_input();
                t.proxies[1].custom_domains = Some(vec!["  ".into()]); // http 缺域名
                t
            },
        ];
        for case in cases {
            assert!(validate_input(&case()).is_err(), "case should fail");
        }
    }

    #[test]
    fn create_trims_and_roundtrips() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let created = manager.create(sample_input()).unwrap();
        assert_eq!(created.name, "我的隧道");
        assert_eq!(created.server_addr, "frp.example.com");
        assert_eq!(created.user.as_deref(), Some("alice"));
        assert_eq!(created.proxies.len(), 2);

        let list = manager.list();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, created.id);
        assert_eq!(manager.get(created.id).unwrap().name, "我的隧道");
        assert_eq!(manager.get(Uuid::new_v4()), None);
        cleanup(&dir);
    }

    #[test]
    fn duplicate_name_rejected() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        manager.create(sample_input()).unwrap();
        let err = manager.create(sample_input()).unwrap_err();
        assert!(matches!(err, FrpError::DuplicateName(_)));
        assert_eq!(err.code(), "duplicate_name");
        cleanup(&dir);
    }

    #[test]
    fn update_replaces_except_id_and_created_at() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let created = manager.create(sample_input()).unwrap();

        let mut input = sample_input();
        input.name = "改名".into();
        input.server_port = 7500;
        let updated = manager.update(created.id, input).unwrap();
        assert_eq!(updated.id, created.id);
        assert_eq!(updated.created_at, created.created_at);
        assert_eq!(updated.name, "改名");
        assert_eq!(updated.server_port, 7500);
        assert!(updated.updated_at >= created.updated_at);

        // 不存在的 id → NotFound
        let err = manager.update(Uuid::new_v4(), sample_input()).unwrap_err();
        assert!(matches!(err, FrpError::NotFound(_)));
        cleanup(&dir);
    }

    #[test]
    fn delete_removes_and_persists() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let created = manager.create(sample_input()).unwrap();
        manager.delete(created.id).unwrap();
        assert!(manager.list().is_empty());
        // 已删除再删 → NotFound
        let err = manager.delete(created.id).unwrap_err();
        assert!(matches!(err, FrpError::NotFound(_)));
        // 重载后仍为空(已落盘)
        let reloaded = FrpManager::load(&dir).unwrap();
        assert!(reloaded.list().is_empty());
        cleanup(&dir);
    }

    #[test]
    fn persistence_survives_reload() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let created = manager.create(sample_input()).unwrap();

        let reloaded = FrpManager::load(&dir).unwrap();
        let list = reloaded.list();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, created.id);
        assert_eq!(list[0].proxies[1].custom_domains.as_deref().unwrap()[1], " beta.example.com ");
        cleanup(&dir);
    }

    #[test]
    fn render_toml_emits_expected_config() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let tunnel = manager.create(sample_input()).unwrap();
        let toml = manager.render_toml(&tunnel);

        assert!(toml.contains("serverAddr = \"frp.example.com\"\n"), "{toml}");
        assert!(toml.contains("serverPort = 7000\n"), "{toml}");
        assert!(toml.contains("user = \"alice\"\n"), "{toml}");
        assert!(!toml.contains("auth.token"), "{toml}");
        assert!(toml.contains("log.to = \"console\"\n"), "{toml}");
        assert!(toml.contains("[[proxies]]\nname = \"mc\"\ntype = \"tcp\"\n"), "{toml}");
        assert!(toml.contains("localIP = \"127.0.0.1\"\n"), "{toml}");
        assert!(toml.contains("localPort = 25565\n"), "{toml}");
        assert!(toml.contains("remotePort = 25565\n"), "{toml}");
        assert!(toml.contains("type = \"http\"\n"), "{toml}");
        assert!(
            toml.contains("customDomains = [\"mc.example.com\", \"beta.example.com\"]\n"),
            "{toml}"
        );
        cleanup(&dir);
    }

    #[test]
    fn toml_q_escapes_specials() {
        assert_eq!(toml_q("plain"), "\"plain\"");
        assert_eq!(toml_q("a\"b"), "\"a\\\"b\"");
        assert_eq!(toml_q("a\\b"), "\"a\\\\b\"");
        assert_eq!(toml_q("a\nb"), "\"a\\nb\"");
    }

    // ── 进程控制(轻量路径;真实 spawn 由 e2e 覆盖) ───────────────

    #[tokio::test]
    async fn start_without_runtime_returns_runtime_missing() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let created = manager.create(sample_input()).unwrap();

        // 未注入 resolver → frpc_runtime_missing
        let err = manager.start(created.id).await.unwrap_err();
        assert!(matches!(err, FrpError::RuntimeMissing(_)));
        assert_eq!(err.code(), "frpc_runtime_missing");
        cleanup(&dir);
    }

    #[tokio::test]
    async fn start_unknown_tunnel_returns_not_found() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let err = manager.start(Uuid::new_v4()).await.unwrap_err();
        assert!(matches!(err, FrpError::NotFound(_)));
        assert_eq!(err.code(), "tunnel_not_found");
        cleanup(&dir);
    }

    #[tokio::test]
    async fn stop_without_running_returns_not_running() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let err = manager.stop().await.unwrap_err();
        assert!(matches!(err, FrpError::NotRunning(_)));
        assert_eq!(err.code(), "frpc_not_running");
        cleanup(&dir);
    }

    #[test]
    fn status_initial_is_stopped() {
        let dir = temp_dir();
        let manager = FrpManager::load(&dir).unwrap();
        let status = manager.status();
        assert!(!status.running);
        assert_eq!(status.tunnel_id, None);
        assert_eq!(status.exit_code, None);
        cleanup(&dir);
    }

    #[tokio::test]
    async fn pump_lines_captures_lines() {
        let logs = Arc::new(RwLock::new(VecDeque::new()));
        let reader: &[u8] = b"line one\nline two\n";
        pump_lines(Some(reader), Arc::clone(&logs)).await;
        let vec: Vec<String> = logs.read().unwrap().iter().cloned().collect();
        assert_eq!(vec, ["line one", "line two"]);
    }

    #[tokio::test]
    async fn pump_lines_trims_overflow() {
        let logs = Arc::new(RwLock::new(VecDeque::new()));
        // 超过 LOG_LIMIT 只保留最新行
        let mut payload = String::new();
        for i in 0..(LOG_LIMIT + 10) {
            payload.push_str(&format!("line {i}\n"));
        }
        let reader = payload.into_bytes();
        pump_lines(Some(&reader[..]), Arc::clone(&logs)).await;
        let guard = logs.read().unwrap();
        assert_eq!(guard.len(), LOG_LIMIT);
        assert_eq!(guard.back().map(|s| s.as_str()), Some("line 2009"));
        assert_eq!(guard.front().map(|s| s.as_str()), Some("line 10"));
    }

    /// 独立临时目录(避免并行测试互相干扰),测试结束由调用方 cleanup。
    fn temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("edgecube-frp-test-{}", Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn cleanup(dir: &Path) {
        let _ = fs::remove_dir_all(dir);
    }
}
