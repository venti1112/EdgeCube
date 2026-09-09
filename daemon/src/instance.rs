//! 实例管理(配置生命周期)。
//!
//! 目录布局(均在 daemon 数据目录下):
//!   instances/{id}/config.json   实例配置(完整 InstanceConfig 的 JSON)
//!   files/{id}/                  工作目录(进程 cwd 与 /fs/* 沙箱根)
//!
//! 与契约约定一致:delete 仅删除 `instances/{id}/`(配置),不触碰 `files/{id}/`(用户数据)。
//! 进程运行时(状态机/pty/日志)由 proc 模块承担;装配时经 [`InstanceManager::set_runtime`]
//! 注入状态解析钩子,列表/详情/统计据此反映实时五态(未注入/未运行恒 Stopped)。

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use uuid::Uuid;

/// 实例配置目录名 / 工作目录根名(相对 daemon 数据目录;proc 模块复用)。
pub(crate) const INSTANCES_DIR: &str = "instances";
const FILES_DIR: &str = "files";
const CONFIG_FILE: &str = "config.json";

/// 实例名限制(对齐契约 maxLength: 64)。
const NAME_MAX_CHARS: usize = 64;

// ────────────────────────── 运行时状态注入(proc 模块) ──────────────────────────

/// 进程运行时快照(proc::ProcManager 提供;注册表中无句柄 = 未运行)。
#[derive(Debug, Clone, Copy)]
pub struct RuntimeSnapshot {
    pub status: InstanceStatus,
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
}

/// 运行时状态解析钩子:uuid -> 快照。由 main 装配时注入,避免模块循环依赖。
pub type RuntimeResolver = Arc<dyn Fn(Uuid) -> Option<RuntimeSnapshot> + Send + Sync>;

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

/// 五态状态机(契约 InstanceStatus)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InstanceStatus {
    Busy,
    Stopped,
    Stopping,
    Starting,
    Running,
}

/// 附加层类型(契约 InstanceType);创建时缺省 generic。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum InstanceType {
    #[default]
    Generic,
    MinecraftJava,
    MinecraftBedrock,
    Pocketmine,
}

/// 终端字符编码(契约 Encoding)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum Encoding {
    #[default]
    #[serde(rename = "utf-8")]
    Utf8,
    #[serde(rename = "gbk")]
    Gbk,
    #[serde(rename = "big5")]
    Big5,
    #[serde(rename = "shift_jis")]
    ShiftJis,
    #[serde(rename = "euckr")]
    Euckr,
    #[serde(rename = "gb18030")]
    Gb18030,
    #[serde(rename = "utf-16")]
    Utf16,
}

/// 终端配置(契约 InstanceConfig.terminal)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalConfig {
    #[serde(default = "default_true")]
    pub pty: bool,
    #[serde(default = "default_cols")]
    pub initial_cols: u32,
    #[serde(default = "default_rows")]
    pub initial_rows: u32,
    #[serde(default = "default_true")]
    pub have_color: bool,
}

impl Default for TerminalConfig {
    fn default() -> Self {
        TerminalConfig {
            pty: true,
            initial_cols: 164,
            initial_rows: 40,
            have_color: true,
        }
    }
}

/// 创建/更新请求(契约 POST/PUT body 的 InstanceConfig 裁剪:readOnly 字段忽略,
/// workingDirectory 缺省由 daemon 分配/保留)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstanceInput {
    pub name: String,
    #[serde(default)]
    pub start_command: String,
    #[serde(default = "default_stop_command")]
    pub stop_command: String,
    #[serde(default = "default_stop_timeout")]
    pub stop_timeout_seconds: u64,
    pub working_directory: Option<PathBuf>,
    #[serde(default)]
    pub environment: HashMap<String, String>,
    #[serde(default)]
    pub input_encoding: Encoding,
    #[serde(default)]
    pub output_encoding: Encoding,
    #[serde(default)]
    pub auto_restart: bool,
    #[serde(default = "default_max_times")]
    pub auto_restart_max_times: i32,
    #[serde(default)]
    pub auto_start_on_boot: bool,
    #[serde(default)]
    pub terminal: TerminalConfig,
    #[serde(rename = "type", default)]
    pub instance_type: InstanceType,
    /// 引用已安装运行时(runtimes 的 RuntimeInfo.id),None = 未指定。
    #[serde(default)]
    pub runtime_id: Option<String>,
    /// 创建时的服务端下载链接(http/https),仅创建时生效;更新实例时忽略(契约 downloadUrl)。
    #[serde(default)]
    pub download_url: Option<String>,
    /// 下载目标文件名(仅与 downloadUrl 配合,创建时生效;缺省由 daemon 从 URL 末段推导)。
    #[serde(default)]
    pub file_name: Option<String>,
    /// 下载校验值,"sha1:<hex>" 或 "sha256:<hex>",仅创建时生效(契约 checksum)。
    #[serde(default)]
    pub checksum: Option<String>,
}

/// 完整实例配置(持久化于 instances/{id}/config.json)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstanceConfig {
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub start_command: String,
    #[serde(default = "default_stop_command")]
    pub stop_command: String,
    #[serde(default = "default_stop_timeout")]
    pub stop_timeout_seconds: u64,
    pub working_directory: PathBuf,
    #[serde(default)]
    pub environment: HashMap<String, String>,
    #[serde(default)]
    pub input_encoding: Encoding,
    #[serde(default)]
    pub output_encoding: Encoding,
    #[serde(default)]
    pub auto_restart: bool,
    #[serde(default = "default_max_times")]
    pub auto_restart_max_times: i32,
    #[serde(default)]
    pub auto_start_on_boot: bool,
    #[serde(default)]
    pub terminal: TerminalConfig,
    #[serde(rename = "type", default)]
    pub instance_type: InstanceType,
    #[serde(default)]
    pub runtime_id: Option<String>,
    #[serde(default)]
    pub download_url: Option<String>,
    #[serde(default)]
    pub file_name: Option<String>,
    #[serde(default)]
    pub checksum: Option<String>,
    /// 创建触发的下载任务 id(契约 downloadTaskId,只读)。
    #[serde(default)]
    pub download_task_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// 实例概要(契约 InstanceSummary)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstanceSummary {
    pub id: Uuid,
    pub name: String,
    pub status: InstanceStatus,
    #[serde(rename = "type")]
    pub instance_type: InstanceType,
    pub pid: Option<u32>,
    pub running_since: Option<DateTime<Utc>>,
    pub auto_restart: bool,
    pub auto_start_on_boot: bool,
    pub port: Option<u16>,
    pub online_players: Option<u32>,
}

/// 运行状态(契约 RunStatus;本模块仅配置,恒为 stopped)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RunStatus {
    pub status: InstanceStatus,
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
    pub server_port: Option<u16>,
    pub online_mode: Option<bool>,
    pub online_players: Vec<String>,
    pub log_seq: i64,
}

/// 实例详情(契约 InstanceDetail)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstanceDetail {
    pub config: InstanceConfig,
    pub status: RunStatus,
}

/// 分页实例列表(契约 InstancePage)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstancePage {
    pub items: Vec<InstanceSummary>,
    pub total: u64,
    pub page: u64,
    pub page_size: u64,
}

/// 首页看板聚合(契约 InstanceOverview)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstanceOverview {
    pub items: Vec<InstanceSummary>,
    pub running: u32,
    pub total: u32,
}

// ────────────────────────── 管理错误 ──────────────────────────

/// 配置操作错误(handler 层映射 HTTP 状态码)。
#[derive(Debug)]
pub enum ManagerError {
    NotFound(Uuid),
    DuplicateName(String),
    Invalid(String),
    Io(std::io::Error),
    Serde(serde_json::Error),
}

impl std::fmt::Display for ManagerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ManagerError::NotFound(id) => write!(f, "instance {id} not found"),
            ManagerError::DuplicateName(name) => write!(f, "duplicate instance name: {name}"),
            ManagerError::Invalid(msg) => f.write_str(msg),
            ManagerError::Io(e) => write!(f, "io error: {e}"),
            ManagerError::Serde(e) => write!(f, "json error: {e}"),
        }
    }
}

// ────────────────────────── 管理器 ──────────────────────────

/// 实例配置管理器:内存注册表 + `instances/{id}/config.json` 持久化。
pub struct InstanceManager {
    /// `{data}/instances`(配置目录根)。
    root: PathBuf,
    /// `{data}/files`(工作目录根,不随实例删除)。
    files_root: PathBuf,
    /// 内存注册表:uuid -> 完整配置。
    instances: RwLock<HashMap<Uuid, InstanceConfig>>,
    /// 运行时状态钩子(proc 模块注入;None = 未注入,恒 Stopped)。
    runtime: Mutex<Option<RuntimeResolver>>,
}

impl InstanceManager {
    /// 注入运行时状态解析钩子(main 装配时调用一次)。
    pub fn set_runtime(&self, resolver: RuntimeResolver) {
        *self.runtime.lock().unwrap() = Some(resolver);
    }

    /// 查询实例的实时运行快照。
    fn runtime_snapshot(&self, id: Uuid) -> Option<RuntimeSnapshot> {
        let guard = self.runtime.lock().unwrap();
        let resolver = guard.as_ref()?;
        resolver(id)
    }
    /// 扫描 `{data}/instances` 加载全部实例配置。
    pub fn load(data_dir: &Path) -> std::io::Result<Self> {
        let root = data_dir.join(INSTANCES_DIR);
        let files_root = data_dir.join(FILES_DIR);
        fs::create_dir_all(&root)?;
        fs::create_dir_all(&files_root)?;

        let mut instances = HashMap::new();
        for entry in fs::read_dir(&root)?.flatten() {
            let dir = entry.path();
            if !dir.is_dir() {
                continue;
            }
            // 目录名 = 实例 uuid;config.json 中的 id 以目录为准
            let Some(name) = dir.file_name().and_then(|n| n.to_str()) else {
                tracing::warn!(path = %dir.display(), "skipping instance dir with invalid name");
                continue;
            };
            let Ok(id) = Uuid::parse_str(name) else {
                tracing::warn!(path = %dir.display(), "skipping non-uuid instance dir");
                continue;
            };
            match fs::read(dir.join(CONFIG_FILE)) {
                Ok(bytes) => match serde_json::from_slice::<InstanceConfig>(&bytes) {
                    Ok(mut config) => {
                        // 信任 config.json 的 workingDirectory;目录名与 config.id 不一致时以目录名为准
                        config.id = id;
                        instances.insert(id, config);
                    }
                    Err(e) => {
                        tracing::warn!(path = %dir.display(), "skipping unparsable config: {e}");
                    }
                },
                Err(_) => {
                    tracing::warn!(path = %dir.display(), "skipping dir without config.json");
                }
            }
        }

        tracing::info!(count = instances.len(), "instances loaded");
        Ok(InstanceManager {
            root,
            files_root,
            instances: RwLock::new(instances),
            runtime: Mutex::new(None),
        })
    }

    /// 创建实例(契约 POST /instances)。
    ///
    /// 校验 name 非空且唯一;生成 uuid;workingDirectory 缺省分配
    /// `{data}/files/{id}`;落盘后再进内存注册表(失败不留半成品)。
    pub async fn create(&self, req: InstanceInput) -> Result<InstanceConfig, ManagerError> {
        let name = validate_name(&req.name)?;
        // 下载参数仅创建时落地:校验 scheme、文件名与 checksum 格式(更新实例时忽略)
        let download_url = validate_download_url(req.download_url)?;
        let file_name = validate_file_name(req.file_name)?;
        let checksum = validate_checksum(req.checksum)?;

        let id = Uuid::new_v4();
        let now = Utc::now();
        let dir = self.root.join(id.to_string());
        let working_directory = req
            .working_directory
            .unwrap_or_else(|| self.files_root.join(id.to_string()));

        let mut instances = self.instances.write().await;
        if instances.values().any(|c| c.name == name) {
            return Err(ManagerError::DuplicateName(name));
        }

        let config = InstanceConfig {
            id,
            name,
            start_command: req.start_command,
            stop_command: req.stop_command,
            stop_timeout_seconds: req.stop_timeout_seconds,
            working_directory,
            environment: req.environment,
            input_encoding: req.input_encoding,
            output_encoding: req.output_encoding,
            auto_restart: req.auto_restart,
            auto_restart_max_times: req.auto_restart_max_times,
            auto_start_on_boot: req.auto_start_on_boot,
            terminal: req.terminal,
            instance_type: req.instance_type,
            runtime_id: req.runtime_id,
            download_url,
            file_name,
            checksum,
            download_task_id: None,
            created_at: now,
            updated_at: now,
        };

        // 先建目录再写配置,避免半成品;失败时清理目录
        fs::create_dir_all(&dir).map_err(ManagerError::Io)?;
        fs::create_dir_all(&config.working_directory).map_err(ManagerError::Io)?;
        if let Err(e) = persist_config(&dir, &config) {
            let _ = fs::remove_dir_all(&dir);
            return Err(e);
        }

        instances.insert(id, config.clone());
        Ok(config)
    }

    /// 更新实例(契约 PUT /instances/{id}):全量替换,name 唯一校验排除自身,
    /// workingDirectory 缺省保留原值,其余字段按请求覆盖。
    pub async fn update(
        &self,
        id: Uuid,
        req: InstanceInput,
    ) -> Result<InstanceConfig, ManagerError> {
        let name = validate_name(&req.name)?;

        let mut instances = self.instances.write().await;
        let existing = instances.get(&id).ok_or(ManagerError::NotFound(id))?;
        if instances.values().any(|c| c.id != id && c.name == name) {
            return Err(ManagerError::DuplicateName(name));
        }

        let mut config = existing.clone();
        config.name = name;
        config.start_command = req.start_command;
        config.stop_command = req.stop_command;
        config.stop_timeout_seconds = req.stop_timeout_seconds;
        if let Some(wd) = req.working_directory {
            config.working_directory = wd;
        }
        config.environment = req.environment;
        config.input_encoding = req.input_encoding;
        config.output_encoding = req.output_encoding;
        config.auto_restart = req.auto_restart;
        config.auto_restart_max_times = req.auto_restart_max_times;
        config.auto_start_on_boot = req.auto_start_on_boot;
        config.terminal = req.terminal;
        config.instance_type = req.instance_type;
        config.runtime_id = req.runtime_id;
        config.updated_at = Utc::now();

        let dir = self.root.join(id.to_string());
        fs::create_dir_all(&config.working_directory).map_err(ManagerError::Io)?;
        persist_config(&dir, &config)?;
        instances.insert(id, config.clone());
        Ok(config)
    }

    /// 创建后回写下载任务 id(契约 downloadTaskId,只读;由 createInstance 提交下载后调用)。
    pub async fn set_download_task_id(
        &self,
        id: Uuid,
        task_id: Uuid,
    ) -> Result<InstanceConfig, ManagerError> {
        let mut instances = self.instances.write().await;
        let config = instances.get_mut(&id).ok_or(ManagerError::NotFound(id))?;
        config.download_task_id = Some(task_id);
        config.updated_at = Utc::now();

        let dir = self.root.join(id.to_string());
        persist_config(&dir, config)?;
        Ok(config.clone())
    }

    /// 删除实例(契约 DELETE /instances/{id}):仅删配置目录 `instances/{id}`,
    /// 工作目录 `files/{id}` 保留(契约约定"不删除工作目录")。
    pub async fn delete(&self, id: Uuid) -> Result<(), ManagerError> {
        let mut instances = self.instances.write().await;
        if !instances.contains_key(&id) {
            return Err(ManagerError::NotFound(id));
        }
        fs::remove_dir_all(self.root.join(id.to_string())).map_err(ManagerError::Io)?;
        instances.remove(&id);
        Ok(())
    }

    /// 实例列表(契约 GET /instances):keyword 模糊过滤 + 分页,按更新时间倒序。
    pub async fn list(
        &self,
        keyword: Option<&str>,
        page: u64,
        page_size: u64,
    ) -> InstancePage {
        let instances = self.instances.read().await;
        let keyword = keyword.map(|k| k.trim()).filter(|k| !k.is_empty());

        let mut matched: Vec<&InstanceConfig> = instances
            .values()
            .filter(|c| keyword.is_none_or(|k| c.name.contains(k)))
            .collect();
        matched.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));

        let total = matched.len() as u64;
        let items = matched
            .into_iter()
            .skip(((page.saturating_sub(1)) * page_size) as usize)
            .take(page_size as usize)
            .map(|c| c.summary_with(self.runtime_snapshot(c.id)))
            .collect();

        InstancePage {
            items,
            total,
            page,
            page_size,
        }
    }

    /// 状态聚合(契约 GET /instances/overview)。
    pub async fn overview(&self) -> InstanceOverview {
        let instances = self.instances.read().await;
        let total = instances.len() as u32;
        let items: Vec<InstanceSummary> = instances
            .values()
            .map(|c| c.summary_with(self.runtime_snapshot(c.id)))
            .collect();
        let running = items
            .iter()
            .filter(|s| matches!(s.status, InstanceStatus::Running))
            .count() as u32;
        InstanceOverview {
            items,
            running,
            total,
        }
    }

    /// 全量计数(供 /health 的 running/total)。
    pub async fn counts(&self) -> (u32, u32) {
        let instances = self.instances.read().await;
        let total = instances.len() as u32;
        let running = instances
            .values()
            .filter(|c| c.is_running_with(self.runtime_snapshot(c.id)))
            .count() as u32;
        (running, total)
    }

    /// 实例详情(契约 GET /instances/{id}):配置 + 实时运行状态。
    pub async fn get_detail(&self, id: Uuid) -> Option<InstanceDetail> {
        let rt = self.runtime_snapshot(id);
        let instances = self.instances.read().await;
        instances.get(&id).map(|config| InstanceDetail {
            config: config.clone(),
            status: config.run_status(rt),
        })
    }

    /// 完整实例配置(启动前读取;不存在返回 None)。
    pub async fn get_config(&self, id: Uuid) -> Option<InstanceConfig> {
        self.instances.read().await.get(&id).cloned()
    }
}

impl InstanceConfig {
    /// 转为概要(契约 InstanceSummary;rt = 实时运行快照)。
    pub(crate) fn summary_with(&self, rt: Option<RuntimeSnapshot>) -> InstanceSummary {
        InstanceSummary {
            id: self.id,
            name: self.name.clone(),
            status: rt.map(|r| r.status).unwrap_or(InstanceStatus::Stopped),
            instance_type: self.instance_type,
            pid: rt.and_then(|r| r.pid),
            running_since: None,
            auto_restart: self.auto_restart,
            auto_start_on_boot: self.auto_start_on_boot,
            port: None,
            online_players: None,
        }
    }

    /// 实时运行状态(契约 RunStatus;rt 缺省 = 全部停止/未知)。
    fn run_status(&self, rt: Option<RuntimeSnapshot>) -> RunStatus {
        RunStatus {
            status: rt.map(|r| r.status).unwrap_or(InstanceStatus::Stopped),
            pid: rt.and_then(|r| r.pid),
            exit_code: rt.and_then(|r| r.exit_code),
            server_port: None,
            online_mode: None,
            online_players: Vec::new(),
            log_seq: 0,
        }
    }

    /// 是否运行中(供 overview/health 统计)。
    fn is_running_with(&self, rt: Option<RuntimeSnapshot>) -> bool {
        matches!(
            rt.map(|r| r.status),
            Some(InstanceStatus::Running) | Some(InstanceStatus::Starting)
        )
    }
}

// ────────────────────────── 内部工具 ──────────────────────────

/// 校验并规范化实例名(非空、<=64 字符、去首尾空白)。
fn validate_name(name: &str) -> Result<String, ManagerError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(ManagerError::Invalid("name must not be empty".into()));
    }
    if name.chars().count() > NAME_MAX_CHARS {
        return Err(ManagerError::Invalid(format!(
            "name must be at most {NAME_MAX_CHARS} characters"
        )));
    }
    Ok(name.to_string())
}

/// 校验下载链接(创建时):仅接受 http/https(对外不暴露下载接口,链接由客户端提供)。
fn validate_download_url(url: Option<String>) -> Result<Option<String>, ManagerError> {
    match url {
        None => Ok(None),
        Some(url) => {
            let url = url.trim().to_string();
            if url.is_empty() {
                return Ok(None);
            }
            if url.starts_with("http://") || url.starts_with("https://") {
                Ok(Some(url))
            } else {
                Err(ManagerError::Invalid(
                    "downloadUrl must be an http(s) url".into(),
                ))
            }
        }
    }
}

/// 校验下载目标文件名(创建时):相对路径单段,禁止路径分隔符与空串。
fn validate_file_name(file_name: Option<String>) -> Result<Option<String>, ManagerError> {
    match file_name {
        None => Ok(None),
        Some(file_name) => {
            let file_name = file_name.trim().to_string();
            if file_name.is_empty() {
                return Ok(None);
            }
            let invalid: Vec<&str> = ["/", "\\", "..", "\0"].to_vec();
            if invalid.iter().any(|p| file_name.contains(p)) {
                return Err(ManagerError::Invalid(
                    "fileName 必须为单段文件名,不得包含路径分隔符".into(),
                ));
            }
            Ok(Some(file_name))
        }
    }
}

/// 校验下载校验值(创建时):"sha256:<64 位 hex>" 或 "sha1:<40 位 hex>";不填或空串视为不校验。
fn validate_checksum(checksum: Option<String>) -> Result<Option<String>, ManagerError> {
    match checksum {
        None => Ok(None),
        Some(checksum) => {
            let checksum = checksum.trim().to_string();
            if checksum.is_empty() {
                return Ok(None);
            }
            for (prefix, len) in [("sha256:", 64usize), ("sha1:", 40usize)] {
                if let Some(hex) = checksum.strip_prefix(prefix) {
                    if hex.len() == len && hex.chars().all(|c| c.is_ascii_hexdigit()) {
                        return Ok(Some(checksum));
                    }
                }
            }
            Err(ManagerError::Invalid(
                "checksum 必须为 \"sha256:<64 hex digits>\" 或 \"sha1:<40 hex digits>\"".into(),
            ))
        }
    }
}

/// 将配置写为 instances/{id}/config.json(pretty JSON)。
fn persist_config(dir: &Path, config: &InstanceConfig) -> Result<(), ManagerError> {
    let json = serde_json::to_string_pretty(config).map_err(ManagerError::Serde)?;
    fs::write(dir.join(CONFIG_FILE), json).map_err(ManagerError::Io)
}

fn default_true() -> bool {
    true
}

fn default_cols() -> u32 {
    164
}

fn default_rows() -> u32 {
    40
}

fn default_stop_command() -> String {
    "^C".into()
}

fn default_stop_timeout() -> u64 {
    600
}

fn default_max_times() -> i32 {
    -1
}