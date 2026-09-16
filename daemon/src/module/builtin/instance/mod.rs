//! 实例管理模块：新建 / 删除 / 列表 / 状态。
//!
//! 存储方式照搬 V1（`EdgeCube/lib/instance/`）：索引 + 单实例元数据 + 工作目录
//! 三分离，详见 [`store`] 的模块文档。
//!
//! # 边界（先说清楚，免得误用）
//!
//! 本模块只管**磁盘上的实例**：元数据、目录、体积。**不管进程**。
//! 启动/停止服务端进程属于进程管理模块，`instance.status` 里的 `phase`
//! 是按 V1 的 `ServerStatus` 定义好的位置，等那个模块接进来才会动；
//! 当前一律 `stopped`，并用 `process_managed: false` 明说。
//!
//! # 方法
//!
//! | 方法 | 说明 |
//! | --- | --- |
//! | `instance.list` | 实例列表（可选带状态） |
//! | `instance.get` | 单个实例的完整元数据 |
//! | `instance.create` | 新建实例 |
//! | `instance.delete` | 删除实例（默认连目录一起删） |
//! | `instance.status` | 状态（一个或全部） |
//! | `instance.select` | 设置/清除"当前选中" |
//! | `instance.scan` | 重新扫描磁盘，补齐索引、清理缺失 |

pub mod model;
pub mod store;

use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use axum::extract::{Path as AxumPath, Query, State as AxumState};
use axum::routing::{delete as http_delete, get as http_get, post as http_post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::sync::Mutex;

use self::model::{
    InstanceConfig, InstanceStatus, LINE_ENDING_CRLF, LINE_ENDING_LF, RUNTIMES, ServerPhase,
    is_known_runtime,
};
use self::store::{InstanceStore, generate_id, validate_id, validate_instance_dir};
use crate::error::{Result, RpcError, RpcResult};
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::server::http::api_result;
use crate::state::AppState;
use crate::util::{humanize_bytes, now_ms};

/// 事件主题。
const TOPIC_CREATED: &str = "instance.created";
const TOPIC_DELETED: &str = "instance.deleted";
const TOPIC_UPDATED: &str = "instance.updated";

/// `maxMemory` 的合法区间（MB）。
const MEMORY_MIN_MB: u32 = 128;
const MEMORY_MAX_MB: u32 = 1_048_576;
/// 实例名长度上限（按字符数）。
const NAME_MAX_CHARS: usize = 64;

// ══════════════════════════════════════════════════════════════════════════
// 模块配置
// ══════════════════════════════════════════════════════════════════════════

/// `[modules.config.instance]`
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct InstanceModuleConfig {
    /// 数据根目录。留空 = 平台默认：
    /// `$EDGECUBE_DATA_DIR` → `$XDG_DATA_HOME/edgecube`
    /// → `$HOME/.local/share/edgecube` → `./edgecube-data`。
    pub dir: String,

    /// 启动时扫描一次磁盘（补齐索引 + 清理缺失）。
    pub scan_on_start: bool,

    /// 扫描时是否把「元数据还在、目录没了」的实例移出索引。
    ///
    /// 与 V1 的 `_pruneMissingInstances` 同义。关掉它就永远不会自动删元数据，
    /// 代价是列表里会留下指向空目录的实例（状态里会给出 warning）。
    pub prune_missing: bool,

    /// 目录体积统计的条目上限（防止扫几十 GB 的存档卡住）。
    pub scan_max_entries: u64,

    /// 目录体积统计的深度上限。
    pub scan_max_depth: usize,
}

impl Default for InstanceModuleConfig {
    fn default() -> Self {
        Self {
            dir: String::new(),
            scan_on_start: true,
            prune_missing: true,
            scan_max_entries: 20_000,
            scan_max_depth: 12,
        }
    }
}

impl InstanceModuleConfig {
    /// 实际使用的数据目录（配置留空时回退到平台默认）。
    pub fn resolved_dir(&self) -> PathBuf {
        let trimmed = self.dir.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
        default_data_dir()
    }

    /// 体积统计的两条上限，至少 1。
    fn limits(&self) -> (u64, usize) {
        (self.scan_max_entries.max(1), self.scan_max_depth.max(1))
    }
}

/// 平台默认数据目录。
pub fn default_data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("EDGECUBE_DATA_DIR")
        && !dir.trim().is_empty()
    {
        return PathBuf::from(dir.trim());
    }
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME")
        && !xdg.trim().is_empty()
    {
        return PathBuf::from(xdg.trim()).join("edgecube");
    }
    if let Ok(home) = std::env::var("HOME")
        && !home.trim().is_empty()
    {
        return PathBuf::from(home.trim()).join(".local/share/edgecube");
    }
    PathBuf::from("edgecube-data")
}

// ══════════════════════════════════════════════════════════════════════════
// 模块状态
// ══════════════════════════════════════════════════════════════════════════

/// 已解析好的「存储 + 配置」。
///
/// `register()` 阶段还拿不到模块配置（那要等 `start()`），所以先做成
/// 惰性解析：`start()` 里定下来，方法被调用时再用（两条路径读的是同一份
/// `[modules.config.instance]`，不会打架）。
#[derive(Debug, Clone)]
struct Resolved {
    store: InstanceStore,
    config: InstanceModuleConfig,
}

struct InstanceState {
    resolved: OnceLock<Resolved>,
    /// 串行化「读索引 → 改 → 写索引」这段临界区。
    ///
    /// 不加锁的话，两个客户端同时建实例会一个覆盖掉另一个（经典的
    /// 读-改-写丢更新）。
    lock: Mutex<()>,
}

impl InstanceState {
    fn new() -> Self {
        Self {
            resolved: OnceLock::new(),
            lock: Mutex::new(()),
        }
    }

    /// 取已解析的存储；还没初始化就用传入的配置初始化一次。
    fn resolved(&self, fallback: Option<InstanceModuleConfig>) -> RpcResult<Resolved> {
        if let Some(resolved) = self.resolved.get() {
            return Ok(resolved.clone());
        }
        let config = fallback
            .ok_or_else(|| RpcError::unavailable("实例模块尚未初始化（模块配置读取失败）"))?;
        let resolved = Resolved::new(config);
        // 另一个调用抢先设置也无所谓，值是一样的
        let _ = self.resolved.set(resolved);
        self.resolved
            .get()
            .cloned()
            .ok_or_else(|| RpcError::internal("实例模块初始化失败"))
    }
}

impl Resolved {
    fn new(config: InstanceModuleConfig) -> Self {
        let store = InstanceStore::new(config.resolved_dir());
        Self { store, config }
    }

    // ── 读 ────────────────────────────────────────────────────────────────

    /// 实例列表。
    fn list(&self, with_status: bool) -> RpcResult<Value> {
        let index = self.store.read_index();
        let mut items = Vec::with_capacity(index.instances.len());
        for summary in &index.instances {
            let selected = index.selected.as_deref() == Some(summary.id.as_str());
            let mut item = json!({
                "id": summary.id,
                "name": summary.name,
                "path": summary.path,
                "selected": selected,
            });
            if with_status {
                let config = self.store.read_config(&summary.id).ok().flatten();
                let status = self.build_status(&summary.id, &summary.name, config.as_ref());
                item["status"] = serde_json::to_value(status)?;
            }
            items.push(item);
        }
        Ok(json!({
            "instances": items,
            "count": items.len(),
            "selected": index.selected,
            "data_dir": self.store.root().display().to_string(),
        }))
    }

    /// 单个实例的完整元数据。
    fn get(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?;
        let Some(config) = config else {
            return Err(not_found(id));
        };
        let dir = self.store.instance_dir(&config);
        Ok(json!({
            "instance": config.to_wire_value(),
            "dir": dir.display().to_string(),
            "lint": config.lint(),
        }))
    }

    /// 状态：给了 id 就只看一个，否则全量。
    fn status(&self, id: Option<&str>) -> RpcResult<Value> {
        let index = self.store.read_index();

        if let Some(id) = id {
            validate_id(id).map_err(RpcError::invalid_params)?;
            let summary = index.instances.iter().find(|s| s.id == id);
            let config = self.store.read_config(id)?;
            if summary.is_none() && config.is_none() {
                return Err(not_found(id));
            }
            let name = summary
                .map(|s| s.name.clone())
                .or_else(|| config.as_ref().map(|c| c.name.clone()))
                .unwrap_or_else(|| id.to_string());
            let status = self.build_status(id, &name, config.as_ref());
            return Ok(json!({ "status": status }));
        }

        let statuses: Vec<InstanceStatus> = index
            .instances
            .iter()
            .map(|summary| {
                let config = self.store.read_config(&summary.id).ok().flatten();
                self.build_status(&summary.id, &summary.name, config.as_ref())
            })
            .collect();
        Ok(json!({
            "statuses": statuses,
            "count": statuses.len(),
            "data_dir": self.store.root().display().to_string(),
        }))
    }

    /// 组装单个实例的状态。
    fn build_status(
        &self,
        id: &str,
        name: &str,
        config: Option<&InstanceConfig>,
    ) -> InstanceStatus {
        let (max_entries, max_depth) = self.config.limits();
        let dir = match config {
            Some(config) => self.store.instance_dir(config),
            None => self.store.default_dir(id),
        };
        let stats = self.store.dir_stats(&dir, max_entries, max_depth);

        let mut warnings = Vec::new();
        if !stats.exists {
            warnings.push("实例目录不存在".to_string());
        }
        match config {
            None => warnings.push("元数据文件缺失（索引里有、磁盘上没有）".to_string()),
            Some(config) => {
                warnings.extend(config.lint());
                if let Some(file) = entry_file(config)
                    && stats.exists
                    && !dir.join(&file).exists()
                {
                    warnings.push(format!("元数据里的入口文件 `{file}` 不在实例目录中"));
                }
            }
        }
        if stats.truncated {
            warnings.push(format!(
                "目录条目超过 {max_entries} 或层级超过 {max_depth}，体积只是下界"
            ));
        }

        InstanceStatus {
            id: id.to_string(),
            name: name.to_string(),
            // 进程管理模块还没接进来，阶段一律 stopped
            phase: ServerPhase::Stopped,
            running: false,
            process_managed: false,
            dir: dir.display().to_string(),
            dir_exists: stats.exists,
            size_bytes: stats.size_bytes,
            size_human: humanize_bytes(stats.size_bytes),
            file_count: stats.file_count,
            dir_count: stats.dir_count,
            size_truncated: stats.truncated,
            created_at_ms: config.and_then(|c| c.created_at_ms),
            updated_at_ms: config.and_then(|c| c.updated_at_ms),
            warnings,
        }
    }

    // ── 写 ────────────────────────────────────────────────────────────────

    /// 新建实例。
    fn create(&self, params: Value) -> RpcResult<Value> {
        // 直接用元数据模型接收：客户端传什么字段就是什么，
        // id / 时间戳由服务端覆盖，不给客户端决定权。
        let mut config: InstanceConfig = serde_json::from_value(params)
            .map_err(|e| RpcError::invalid_params(format!("创建参数不合法: {e}")))?;

        let name = config.name.trim().to_string();
        if name.is_empty() {
            return Err(RpcError::invalid_params("实例名称不能为空"));
        }
        if name.chars().count() > NAME_MAX_CHARS {
            return Err(RpcError::invalid_params(format!(
                "实例名称过长（上限 {NAME_MAX_CHARS} 字）"
            )));
        }
        if !is_known_runtime(&config.runtime) {
            return Err(RpcError::invalid_params(format!(
                "未知运行环境 `{}`，可选：{}",
                config.runtime,
                RUNTIMES.join(" / ")
            )));
        }
        if let Some(memory) = config.max_memory
            && !(MEMORY_MIN_MB..=MEMORY_MAX_MB).contains(&memory)
        {
            return Err(RpcError::invalid_params(format!(
                "maxMemory 需在 {MEMORY_MIN_MB}–{MEMORY_MAX_MB} MB 之间"
            )));
        }
        config.path = match config.path.as_deref().map(str::trim) {
            Some(path) if !path.is_empty() => {
                validate_instance_dir(Path::new(path)).map_err(RpcError::invalid_params)?;
                Some(path.to_string())
            }
            _ => None,
        };

        let mut index = self.store.read_index();
        if index.name_taken(&name, None) {
            return Err(RpcError::new(
                "instance_name_taken",
                format!("已存在名为 `{name}` 的实例"),
            ));
        }

        // id 要同时避开索引与磁盘上已存在的目录
        let mut id = generate_id();
        for _ in 0..8 {
            if !index.contains(&id) && !self.store.default_dir(&id).exists() {
                break;
            }
            id = generate_id();
        }
        if index.contains(&id) {
            return Err(RpcError::internal("无法生成唯一的实例 id，请重试"));
        }

        let created = now_ms();
        config.id = id.clone();
        config.name = name;
        config.created_at_ms = Some(created);
        config.updated_at_ms = Some(created);

        // 顺序：目录 → 元数据 → 索引。中途失败不会留下"半条"记录：
        // 目录建了但元数据没写成，下次启动的 adopt 会把它捡回来。
        let dir = self.store.instance_dir(&config);
        self.store.create_dir(&dir)?;
        self.store.write_config(&config)?;
        index.instances.push(config.summary());
        index.selected = Some(id.clone());
        self.store.write_index(&index)?;

        Ok(json!({
            "instance": config.to_wire_value(),
            "dir": dir.display().to_string(),
            "selected": id,
            "count": index.instances.len(),
        }))
    }

    /// 删除实例。`keep_files = true` 时只把它从列表里摘掉，目录留在磁盘上。
    fn delete(&self, id: &str, keep_files: bool) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;

        let mut index = self.store.read_index();
        let summary = index.instances.iter().find(|s| s.id == id).cloned();
        let config = self.store.read_config(id)?;
        if summary.is_none() && config.is_none() {
            return Err(not_found(id));
        }
        let name = summary
            .as_ref()
            .map(|s| s.name.clone())
            .or_else(|| config.as_ref().map(|c| c.name.clone()))
            .unwrap_or_else(|| id.to_string());

        // 目录以元数据里的 path 为准（可能被手工改过，所以删除前**重新**校验）
        let dir = match (&config, &summary) {
            (Some(config), _) => self.store.instance_dir(config),
            (None, Some(summary)) => summary
                .path
                .as_deref()
                .filter(|p| !p.trim().is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| self.store.default_dir(id)),
            (None, None) => self.store.default_dir(id),
        };

        let mut files_deleted = false;
        let mut note = None;
        if keep_files {
            note = Some("按要求保留了实例目录，只移除了元数据与索引项");
        } else {
            // 万一元数据被改成了 /etc 这种位置，这里必须拦住
            validate_instance_dir(&dir).map_err(RpcError::forbidden)?;
            files_deleted = self.store.remove_dir(&dir)?;
        }

        let metadata_deleted = self.store.delete_config(id)?;
        index.instances.retain(|s| s.id != id);
        let selection_moved = index.selected.as_deref() == Some(id);
        if selection_moved {
            // 与 V1 一致：删掉选中项后顺位到第一个
            index.selected = index.instances.first().map(|s| s.id.clone());
        }
        self.store.write_index(&index)?;

        Ok(json!({
            "deleted": true,
            "id": id,
            "name": name,
            "dir": dir.display().to_string(),
            "files_deleted": files_deleted,
            "metadata_deleted": metadata_deleted,
            "selected": index.selected,
            "remaining": index.instances.len(),
            "note": note,
        }))
    }

    /// 修改实例的元数据（只改传过来的字段）。
    ///
    /// **语义**：字段缺席 = 不动；显式传 `null`（或空串）= 清空该可选字段。
    /// `id` / `createdAtMs` 不可改；`path` 只改元数据里的记录，
    /// **不会移动磁盘上的文件**（V1 的 `updatePath` 也是这个语义）。
    fn update(&self, id: &str, patch: serde_json::Map<String, Value>) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;

        let mut index = self.store.read_index();
        let Some(mut config) = self.store.read_config(id)? else {
            return Err(not_found(id));
        };

        // 先全部校验，再一次性落盘：避免"改了一半"的元数据
        for key in patch.keys() {
            if !UPDATABLE_FIELDS.contains(&key.as_str()) {
                return Err(RpcError::invalid_params(format!(
                    "不认识的字段 `{key}`，可改的是：{}",
                    UPDATABLE_FIELDS.join(" / ")
                )));
            }
        }

        let mut changed = false;
        let mut apply = |flag: bool| changed |= flag;

        if let Some(value) = patch.get("name") {
            let name = string_field(value, "name")?;
            if name.is_empty() {
                return Err(RpcError::invalid_params("实例名称不能为空"));
            }
            if name.chars().count() > NAME_MAX_CHARS {
                return Err(RpcError::invalid_params(format!(
                    "实例名称过长（上限 {NAME_MAX_CHARS} 字）"
                )));
            }
            if index.name_taken(&name, Some(id)) {
                return Err(RpcError::new(
                    "instance_name_taken",
                    format!("已存在名为 `{name}` 的实例"),
                ));
            }
            apply(config.name != name);
            config.name = name;
        }

        if let Some(value) = patch.get("runtime") {
            let runtime = string_field(value, "runtime")?;
            if !is_known_runtime(&runtime) {
                return Err(RpcError::invalid_params(format!(
                    "未知运行环境 `{runtime}`，可选：{}",
                    RUNTIMES.join(" / ")
                )));
            }
            apply(config.runtime != runtime);
            config.runtime = runtime;
        }

        if let Some(value) = patch.get("max_memory") {
            let memory = match value {
                Value::Null => None,
                other => {
                    let number = other.as_u64().ok_or_else(|| {
                        RpcError::invalid_params("maxMemory 必须是整数（MB）或 null")
                    })?;
                    let number = u32::try_from(number).map_err(|_| {
                        RpcError::invalid_params(format!(
                            "maxMemory 需在 {MEMORY_MIN_MB}–{MEMORY_MAX_MB} MB 之间"
                        ))
                    })?;
                    if !(MEMORY_MIN_MB..=MEMORY_MAX_MB).contains(&number) {
                        return Err(RpcError::invalid_params(format!(
                            "maxMemory 需在 {MEMORY_MIN_MB}–{MEMORY_MAX_MB} MB 之间"
                        )));
                    }
                    Some(number)
                }
            };
            apply(config.max_memory != memory);
            config.max_memory = memory;
        }

        for (key, slot) in [
            ("runtime_env_id", &mut config.runtime_env_id),
            ("server_file", &mut config.server_file),
            ("custom_jvm_args", &mut config.custom_jvm_args),
            ("proot_startup_command", &mut config.proot_startup_command),
        ] {
            if let Some(value) = patch.get(key) {
                // 空串与 null 一样当作"清掉"，界面上就是"清空输入框"
                let next = match value {
                    Value::Null => None,
                    other => {
                        let text = string_field(other, key)?;
                        if text.is_empty() { None } else { Some(text) }
                    }
                };
                apply(*slot != next);
                *slot = next;
            }
        }

        for (key, slot) in [
            ("compat_mode", &mut config.compat_mode),
            ("auto_restart_on_exit", &mut config.auto_restart_on_exit),
        ] {
            if let Some(value) = patch.get(key) {
                let flag = value
                    .as_bool()
                    .ok_or_else(|| RpcError::invalid_params(format!("{key} 必须是布尔值")))?;
                apply(*slot != flag);
                *slot = flag;
            }
        }

        if let Some(value) = patch.get("line_ending") {
            let ending = string_field(value, "line_ending")?;
            if ending != LINE_ENDING_LF && ending != LINE_ENDING_CRLF {
                return Err(RpcError::invalid_params(
                    "line_endings 只能是 \"\\n\" 或 \"\\r\\n\"",
                ));
            }
            apply(config.line_ending != ending);
            config.line_ending = ending;
        }

        if let Some(value) = patch.get("path") {
            let next = match value {
                Value::Null => None,
                other => {
                    let text = string_field(other, "path")?;
                    if text.is_empty() {
                        None
                    } else {
                        validate_instance_dir(Path::new(&text))
                            .map_err(RpcError::invalid_params)?;
                        Some(text)
                    }
                }
            };
            apply(config.path != next);
            config.path = next;
        }

        if !changed {
            return Ok(json!({
                "instance": config.to_wire_value(),
                "changed": false,
                "dir": self.store.instance_dir(&config).display().to_string(),
                "lint": config.lint(),
            }));
        }

        self.store.write_config(&config)?;
        // 索引里也存了名称与路径，必须同步，否则列表显示的是旧名字
        if let Some(position) = index.position(id) {
            index.instances[position] = config.summary();
        }
        self.store.write_index(&index)?;

        Ok(json!({
            "instance": config.to_wire_value(),
            "changed": true,
            "dir": self.store.instance_dir(&config).display().to_string(),
            "lint": config.lint(),
        }))
    }

    /// 设置「当前选中」；传 `null` 表示取消选中。
    fn select(&self, id: Option<&str>) -> RpcResult<Value> {
        let mut index = self.store.read_index();
        match id {
            Some(id) => {
                validate_id(id).map_err(RpcError::invalid_params)?;
                if !index.contains(id) {
                    return Err(not_found(id));
                }
                index.selected = Some(id.to_string());
            }
            None => index.selected = None,
        }
        self.store.write_index(&index)?;
        Ok(json!({ "selected": index.selected, "count": index.instances.len() }))
    }

    /// 重新扫描磁盘：清理「目录没了」的索引项，把「有目录没索引」的补进来。
    fn scan(&self) -> RpcResult<Value> {
        let mut index = self.store.read_index();
        let mut pruned: Vec<String> = Vec::new();
        let mut adopted: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();

        // 目录都读不了时**绝不动索引**（存储没挂载 / 权限不足的场景）
        let Some(existing) = self.store.discover_dirs() else {
            return Ok(json!({
                "skipped": true,
                "reason": "实例根目录不可用，已跳过扫描以免误删索引",
                "pruned": [],
                "adopted": [],
            }));
        };

        // 1) 元数据还在、目录没了 → 移出索引
        if self.config.prune_missing {
            let mut kept = Vec::with_capacity(index.instances.len());
            for summary in index.instances.drain(..) {
                let exists = match summary.path.as_deref().filter(|p| !p.trim().is_empty()) {
                    Some(custom) => Path::new(custom).is_dir(),
                    None => existing.contains(&summary.id),
                };
                if exists {
                    kept.push(summary);
                } else {
                    tracing::warn!(
                        id = %summary.id,
                        name = %summary.name,
                        "实例目录已消失，从索引中移除"
                    );
                    let _ = self.store.delete_config(&summary.id);
                    pruned.push(summary.id.clone());
                }
            }
            index.instances = kept;
        }

        // 2) 磁盘有目录、索引里没有 → 用文件夹名当 id 与名称补进来
        //    （用户在外部文件管理器里建过目录，或索引丢过）
        for dir_name in &existing {
            if index.contains(dir_name) {
                continue;
            }
            if validate_id(dir_name).is_err() {
                tracing::warn!(dir = %dir_name, "实例目录名不是合法 id，已跳过（不自动接管）");
                skipped.push(dir_name.clone());
                continue;
            }
            let config = InstanceConfig::new(dir_name.clone(), dir_name.clone());
            match self.store.write_config(&config) {
                Ok(()) => {
                    tracing::info!(id = %dir_name, "发现未登记的实例目录，已自动接管");
                    index.instances.push(config.summary());
                    adopted.push(dir_name.clone());
                }
                Err(e) => {
                    tracing::warn!(dir = %dir_name, error = %e, "接管实例目录失败");
                    skipped.push(dir_name.clone());
                }
            }
        }

        // 选中项指向不存在的实例时顺位
        if index
            .selected
            .as_deref()
            .is_some_and(|id| !index.contains(id))
        {
            index.selected = index.instances.first().map(|s| s.id.clone());
        }

        self.store.write_index(&index)?;
        Ok(json!({
            "skipped": false,
            "pruned": pruned,
            "adopted": adopted,
            "ignored": skipped,
            "pruned_count": pruned.len(),
            "adopted_count": adopted.len(),
            "total": index.instances.len(),
            "selected": index.selected,
            "data_dir": self.store.root().display().to_string(),
        }))
    }
}

/// `instance.update` 允许改的字段。
///
/// `id` 与时间戳由服务端管，不在其列；其余字段缺席 = 不动、传 null = 清空。
const UPDATABLE_FIELDS: [&str; 11] = [
    "name",
    "runtime",
    "max_memory",
    "runtime_env_id",
    "server_file",
    "custom_jvm_args",
    "compat_mode",
    "auto_restart_on_exit",
    "proot_startup_command",
    "path",
    "line_ending",
];

/// 取字符串字段（顺带去掉首尾空白）。
fn string_field(value: &Value, key: &str) -> RpcResult<String> {
    value
        .as_str()
        .map(|text| text.trim().to_string())
        .ok_or_else(|| RpcError::invalid_params(format!("{key} 必须是字符串")))
}

/// 取元数据里的入口文件（现代 Forge/NeoForge 写的是 `@<argfile>` 哨兵，
/// 去掉 `@` 之后仍然是个相对路径）。
fn entry_file(config: &InstanceConfig) -> Option<String> {
    let raw = config.server_file.as_deref()?.trim();
    if raw.is_empty() {
        return None;
    }
    Some(raw.strip_prefix('@').unwrap_or(raw).to_string())
}

fn not_found(id: &str) -> RpcError {
    RpcError::new("instance_not_found", format!("没有 id 为 `{id}` 的实例"))
}

/// 把同步的磁盘操作丢到阻塞线程池，别卡住 tokio 的工作线程。
async fn blocking<T, F>(f: F) -> RpcResult<T>
where
    F: FnOnce() -> RpcResult<T> + Send + 'static,
    T: Send + 'static,
{
    match tokio::task::spawn_blocking(f).await {
        Ok(result) => result,
        Err(join) => Err(RpcError::internal(format!(
            "实例操作的后台任务失败: {join}"
        ))),
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 模块本体
// ══════════════════════════════════════════════════════════════════════════

pub struct InstanceModule {
    state: Arc<InstanceState>,
}

impl InstanceModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(InstanceState::new()),
        }
    }

    fn http_router(&self) -> Router<AppState> {
        let state = self.state.clone();

        let list = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        blocking(move || resolved.list(false)).await
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let get = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        blocking(move || resolved.status(Some(&id))).await
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let create = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, Json(body): Json<Value>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let guard = state.lock.lock().await;
                        let outcome = blocking(move || resolved.create(body)).await;
                        drop(guard);
                        outcome
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let patch = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>,
                  AxumPath(id): AxumPath<String>,
                  Json(body): Json<Value>| {
                let state = state.clone();
                async move {
                    let patch = body.as_object().cloned().unwrap_or_default();
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let guard = state.lock.lock().await;
                        let outcome = blocking({
                            let id = id.clone();
                            move || resolved.update(&id, patch)
                        })
                        .await;
                        drop(guard);
                        outcome
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let remove = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>,
                  AxumPath(id): AxumPath<String>,
                  Query(query): Query<DeleteQuery>| {
                let state = state.clone();
                async move {
                    let keep_files = query.keep_files.unwrap_or(false);
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let guard = state.lock.lock().await;
                        let outcome = blocking(move || resolved.delete(&id, keep_files)).await;
                        drop(guard);
                        outcome
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let select = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let guard = state.lock.lock().await;
                        let outcome = blocking(move || resolved.select(Some(&id))).await;
                        drop(guard);
                        outcome
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        Router::new()
            .route("/api/instances", http_get(list).post(create))
            .route(
                "/api/instances/{id}",
                http_get(get).patch(patch).delete(http_delete(remove)),
            )
            .route("/api/instances/{id}/select", http_post(select))
    }
}

/// `DELETE /api/instances/{id}?keep_files=true`
#[derive(Debug, Deserialize)]
struct DeleteQuery {
    #[serde(default)]
    keep_files: Option<bool>,
}

/// 从 `AppState` 读模块配置（HTTP 路径没有 `CallCtx`，无法用 `ctx.module_config()`）。
fn module_config_of(app: &AppState) -> Option<InstanceModuleConfig> {
    let value = app.config.modules.section("instance")?;
    InstanceModuleConfig::deserialize(value.clone()).ok()
}

impl Default for InstanceModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for InstanceModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("instance", "实例管理", env!("CARGO_PKG_VERSION"))
            .description("服务器实例的元数据：新建 / 删除 / 列表 / 状态。不含进程管理。")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(TOPIC_CREATED, "新建了实例");
        reg.topic(TOPIC_DELETED, "删除了实例");
        reg.topic(
            TOPIC_UPDATED,
            "实例元数据被修改（改名/改配置），或扫描后有变化",
        );

        // ── 列表 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.list",
                "实例列表（可选带状态）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let with_status = ctx.param_or("with_status", false)?;
                        blocking(move || resolved.list(with_status)).await
                    }
                },
            );
        }

        // ── 单个详情 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.get",
                "单个实例的完整元数据",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.get(&id)).await
                    }
                },
            );
        }

        // ── 新建 ──
        {
            let module = self.state.clone();
            reg.method("instance.create", "新建实例", move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let params = ctx.params.clone();
                    let guard = module.lock.lock().await;
                    let result = blocking(move || resolved.create(params)).await;
                    drop(guard);
                    let value = result?;
                    ctx.publish(
                        TOPIC_CREATED,
                        json!({
                            "id": value["instance"]["id"],
                            "name": value["instance"]["name"],
                            "ts": now_ms(),
                        }),
                    );
                    ok(value)
                }
            });
        }

        // ── 删除 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.delete",
                "删除实例（默认连目录一起删）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let keep_files = ctx.param_or("keep_files", false)?;
                        let guard = module.lock.lock().await;
                        let result = blocking({
                            let id = id.clone();
                            move || resolved.delete(&id, keep_files)
                        })
                        .await;
                        drop(guard);
                        let value = result?;
                        ctx.publish(
                            TOPIC_DELETED,
                            json!({
                                "id": id,
                                "name": value["name"],
                                "files_deleted": value["files_deleted"],
                                "ts": now_ms(),
                            }),
                        );
                        ok(value)
                    }
                },
            );
        }

        // ── 状态 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.status",
                "实例状态（给 id 看一个，不给看全部）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: Option<String> = ctx.optional("id")?;
                        blocking(move || resolved.status(id.as_deref())).await
                    }
                },
            );
        }

        // ── 修改元数据 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.update",
                "修改实例元数据（只改传过来的字段，传 null 表示清空）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let patch = ctx.params.as_object().cloned().unwrap_or_default();
                        let guard = module.lock.lock().await;
                        let result = blocking({
                            let id = id.clone();
                            move || resolved.update(&id, patch)
                        })
                        .await;
                        drop(guard);
                        let value = result?;
                        if value["changed"] == json!(true) {
                            ctx.publish(
                                TOPIC_UPDATED,
                                json!({
                                    "id": id,
                                    "name": value["instance"]["name"],
                                    "ts": now_ms(),
                                }),
                            );
                        }
                        ok(value)
                    }
                },
            );
        }

        // ── 选中 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.select",
                "设置当前选中的实例（id 传 null 取消）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: Option<String> = ctx.optional("id")?;
                        let guard = module.lock.lock().await;
                        let result = blocking(move || resolved.select(id.as_deref())).await;
                        drop(guard);
                        ok(result?)
                    }
                },
            );
        }

        // ── 重新扫描 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.scan",
                "重新扫描磁盘：补齐索引、清理缺失",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let guard = module.lock.lock().await;
                        let result = blocking(move || resolved.scan()).await;
                        drop(guard);
                        let value = result?;
                        ctx.publish(
                            TOPIC_UPDATED,
                            json!({
                                "pruned": value["pruned"],
                                "adopted": value["adopted"],
                                "ts": now_ms(),
                            }),
                        );
                        ok(value)
                    }
                },
            );
        }

        // ── HTTP ──
        reg.router("api/instances", self.http_router());
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: InstanceModuleConfig = env.config()?;
        let resolved = Resolved::new(config);
        resolved.store.ensure_dirs()?;

        tracing::info!(
            dir = %resolved.store.root().display(),
            scan_on_start = resolved.config.scan_on_start,
            prune_missing = resolved.config.prune_missing,
            "instance 模块已加载"
        );

        if resolved.config.scan_on_start {
            let scanning = resolved.clone();
            let report = tokio::task::spawn_blocking(move || scanning.scan())
                .await
                .map_err(|e| crate::error::Error::other(format!("实例扫描任务失败: {e}")))?
                .map_err(crate::error::Error::Rpc)?;
            tracing::info!(
                pruned = %report["pruned_count"],
                adopted = %report["adopted_count"],
                total = %report["total"],
                "实例扫描完成"
            );
        }

        let _ = self.state.resolved.set(resolved);
        Ok(())
    }
}

/// 从 `CallCtx` 取模块配置并解析存储（方法处理器里反复用到）。
fn resolve_for(state: &Arc<InstanceState>, ctx: &crate::module::CallCtx) -> RpcResult<Resolved> {
    let config = ctx.module_config::<InstanceModuleConfig>().ok();
    state.resolved(config)
}

// ══════════════════════════════════════════════════════════════════════════
// 测试：直接打存储层（不走 WS，跑得快）
// ══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    /// 一个临时数据目录 + 对应的 `Resolved`；析构时清盘。
    struct TempData(PathBuf, Resolved);

    impl TempData {
        fn new(tag: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "edgecube-instance-mod-{tag}-{}-{}",
                std::process::id(),
                now_ms()
            ));
            std::fs::create_dir_all(&root).expect("应能建临时目录");
            let resolved = Resolved::new(InstanceModuleConfig {
                dir: root.display().to_string(),
                ..Default::default()
            });
            resolved.store.ensure_dirs().expect("应能建目录");
            Self(root, resolved)
        }

        fn dir(&self) -> &Path {
            &self.0
        }

        fn instance_dir(&self, id: &str) -> PathBuf {
            self.0.join("instances").join(id)
        }

        fn config_file(&self, id: &str) -> PathBuf {
            self.0
                .join("config")
                .join("instances")
                .join(format!("{id}.json"))
        }
    }

    impl Drop for TempData {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn create(temp: &TempData, name: &str) -> Value {
        temp.1
            .create(json!({ "name": name }))
            .unwrap_or_else(|e| panic!("创建 `{name}` 失败: {e}"))
    }

    fn id_of(created: &Value) -> String {
        created["instance"]["id"]
            .as_str()
            .expect("应有 id")
            .to_string()
    }

    #[test]
    fn create_list_get_delete_round_trip() {
        let temp = TempData::new("crud");

        // 一开始什么都没有
        let list = temp.1.list(false).unwrap();
        assert_eq!(list["count"], json!(0));
        assert!(list["selected"].is_null());
        assert_eq!(list["data_dir"], json!(temp.dir().display().to_string()));

        // 创建
        let created = create(&temp, "生存服");
        let id = id_of(&created);
        assert_eq!(created["instance"]["name"], json!("生存服"));
        assert_eq!(created["instance"]["runtime"], json!("java"));
        assert!(created["instance"]["created_at_ms"].as_u64().unwrap() > 0);
        assert!(temp.instance_dir(&id).is_dir(), "工作目录应已建好");
        assert!(temp.config_file(&id).is_file(), "元数据应已落盘");
        // 新建的实例自动成为选中项（与 V1 一致）
        assert_eq!(created["selected"], json!(id));

        // 列表（索引里有摘要 + 选中标记）
        let list = temp.1.list(false).unwrap();
        assert_eq!(list["count"], json!(1));
        assert_eq!(list["selected"], json!(id));
        assert_eq!(list["instances"][0]["id"], json!(id));
        assert_eq!(list["instances"][0]["name"], json!("生存服"));
        assert_eq!(list["instances"][0]["selected"], json!(true));

        // 详情
        let got = temp.1.get(&id).unwrap();
        assert_eq!(got["instance"]["id"], json!(id));
        assert_eq!(
            got["dir"],
            json!(temp.instance_dir(&id).display().to_string())
        );
        assert_eq!(got["lint"].as_array().unwrap().len(), 0);

        // 状态（单个 / 全部）
        let status = temp.1.status(Some(&id)).unwrap();
        assert_eq!(status["status"]["phase"], json!("stopped"));
        assert_eq!(status["status"]["running"], json!(false));
        assert_eq!(status["status"]["process_managed"], json!(false));
        assert_eq!(status["status"]["dir_exists"], json!(true));
        assert!(status["status"]["warnings"].as_array().unwrap().is_empty());

        let all = temp.1.status(None).unwrap();
        assert_eq!(all["count"], json!(1));
        assert_eq!(all["statuses"][0]["id"], json!(id));

        // 删除（连目录一起）
        let deleted = temp.1.delete(&id, false).unwrap();
        assert_eq!(deleted["deleted"], json!(true));
        assert_eq!(deleted["files_deleted"], json!(true));
        assert_eq!(deleted["metadata_deleted"], json!(true));
        assert_eq!(deleted["remaining"], json!(0));
        assert!(!temp.instance_dir(&id).exists(), "目录应已被删掉");
        assert!(!temp.config_file(&id).exists(), "元数据应已被删掉");
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(0));

        // 再删就找不到了
        let err = temp.1.delete(&id, false).unwrap_err();
        assert_eq!(err.code, "instance_not_found");
        assert_eq!(temp.1.get(&id).unwrap_err().code, "instance_not_found");
        assert_eq!(
            temp.1.status(Some(&id)).unwrap_err().code,
            "instance_not_found"
        );
    }

    #[test]
    fn create_validates_input() {
        let temp = TempData::new("validate");

        let err = temp.1.create(json!({ "name": "   " })).unwrap_err();
        assert_eq!(err.code, "invalid_params");
        assert!(err.message.contains("名称"));

        let err = temp
            .1
            .create(json!({ "name": "x", "runtime": "native" }))
            .unwrap_err();
        assert!(err.message.contains("未知运行环境"), "{}", err.message);

        let err = temp
            .1
            .create(json!({ "name": "x", "maxMemory": 8 }))
            .unwrap_err();
        assert!(err.message.contains("maxMemory"), "{}", err.message);

        let err = temp
            .1
            .create(json!({ "name": "x", "path": "/etc" }))
            .unwrap_err();
        assert!(err.message.contains("层级过浅"), "{}", err.message);

        let err = temp
            .1
            .create(json!({ "name": "x", "path": "relative/dir" }))
            .unwrap_err();
        assert!(err.message.contains("绝对路径"), "{}", err.message);

        // 重名（忽略首尾空白）
        create(&temp, "生存服");
        let err = temp.1.create(json!({ "name": " 生存服 " })).unwrap_err();
        assert_eq!(err.code, "instance_name_taken");
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(1));

        // 名称过长
        let err = temp
            .1
            .create(json!({ "name": "x".repeat(NAME_MAX_CHARS + 1) }))
            .unwrap_err();
        assert!(err.message.contains("过长"), "{}", err.message);
    }

    #[test]
    fn create_accepts_full_v1_metadata() {
        let temp = TempData::new("full");
        let created = temp
            .1
            .create(json!({
                "name": "模组服",
                "runtime": "java",
                "maxMemory": 4096,
                "runtimeEnvId": "jre21",
                "serverFile": "server.jar",
                "customJvmArgs": "-XX:+UseZGC",
                "compatMode": true,
                "autoRestartOnExit": true,
                "lineEnding": "\r\n"
            }))
            .unwrap();
        let id = id_of(&created);
        let got = temp.1.get(&id).unwrap();
        assert_eq!(got["instance"]["max_memory"], json!(4096));
        assert_eq!(got["instance"]["runtime_env_id"], json!("jre21"));
        assert_eq!(got["instance"]["compat_mode"], json!(true));
        // 默认值不该被写进文件
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(raw.contains("\"serverFile\""));
        assert!(
            !raw.contains("\"prootStartupCommand\""),
            "未设置的字段不该落盘"
        );
    }

    #[test]
    fn id_cannot_escape_the_data_dir() {
        let temp = TempData::new("traversal");
        let created = create(&temp, "服");
        let id = id_of(&created);

        // 这些 id 一律要在**碰磁盘之前**被拒掉
        for bad in ["../config", "..", "a/b", "/etc/passwd", "a\\b"] {
            let err = temp.1.delete(bad, false).unwrap_err();
            assert_eq!(err.code, "invalid_params", "`{bad}` 应被拒绝");
            assert_eq!(temp.1.get(bad).unwrap_err().code, "invalid_params");
        }
        // 原来的实例毫发无损
        assert!(temp.instance_dir(&id).is_dir());
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(1));
    }

    #[test]
    fn delete_refuses_unsafe_dir_from_tampered_metadata() {
        let temp = TempData::new("tamper");
        let created = create(&temp, "服");
        let id = id_of(&created);

        // 手工把元数据里的 path 改成系统目录（模拟被人改坏）
        let mut config: InstanceConfig =
            serde_json::from_str(&std::fs::read_to_string(temp.config_file(&id)).unwrap()).unwrap();
        config.path = Some("/etc".into());
        std::fs::write(
            temp.config_file(&id),
            serde_json::to_string(&config).unwrap(),
        )
        .unwrap();

        let err = temp.1.delete(&id, false).unwrap_err();
        assert_eq!(err.code, "forbidden", "浅层系统目录必须拒绝删除");
        assert!(Path::new("/etc").exists(), "当然，/etc 得还在");
        // 元数据与索引也不该被动过
        assert!(temp.config_file(&id).is_file());
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(1));
    }

    #[test]
    fn delete_keep_files_removes_only_metadata() {
        let temp = TempData::new("keep");
        let created = create(&temp, "服");
        let id = id_of(&created);
        std::fs::write(temp.instance_dir(&id).join("server.jar"), b"jar").unwrap();

        let deleted = temp.1.delete(&id, true).unwrap();
        assert_eq!(deleted["files_deleted"], json!(false));
        assert_eq!(deleted["metadata_deleted"], json!(true));
        assert!(!temp.config_file(&id).exists());
        assert!(
            temp.instance_dir(&id).join("server.jar").is_file(),
            "文件应当保留"
        );
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(0));
    }

    #[test]
    fn deleting_selected_falls_back_to_first_remaining() {
        let temp = TempData::new("selected");
        let first = id_of(&create(&temp, "甲"));
        let second = id_of(&create(&temp, "乙"));
        // 新建的会成为选中项
        assert_eq!(temp.1.list(false).unwrap()["selected"], json!(second));

        temp.1.delete(&second, false).unwrap();
        assert_eq!(temp.1.list(false).unwrap()["selected"], json!(first));

        temp.1.delete(&first, false).unwrap();
        assert!(temp.1.list(false).unwrap()["selected"].is_null());
    }

    #[test]
    fn select_validates_target() {
        let temp = TempData::new("select");
        let id = id_of(&create(&temp, "甲"));

        let picked = temp.1.select(None).unwrap();
        assert!(picked["selected"].is_null());
        let picked = temp.1.select(Some(&id)).unwrap();
        assert_eq!(picked["selected"], json!(id));

        let err = temp.1.select(Some("nope")).unwrap_err();
        assert_eq!(err.code, "instance_not_found");
        assert_eq!(
            temp.1.select(Some("../x")).unwrap_err().code,
            "invalid_params"
        );
    }

    #[test]
    fn status_reports_size_and_warnings() {
        let temp = TempData::new("status");
        let created = temp
            .1
            .create(json!({ "name": "服", "serverFile": "server.jar" }))
            .unwrap();
        let id = id_of(&created);

        // 入口文件还没上传 → 要提醒
        let status = temp.1.status(Some(&id)).unwrap();
        let warnings: Vec<String> = status["status"]["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .map(|w| w.as_str().unwrap().to_string())
            .collect();
        assert!(
            warnings.iter().any(|w| w.contains("server.jar")),
            "应提示入口文件缺失: {warnings:?}"
        );

        // 放进文件与子目录 → 体积/数量/可读体积
        std::fs::write(temp.instance_dir(&id).join("server.jar"), vec![0u8; 2048]).unwrap();
        std::fs::create_dir_all(temp.instance_dir(&id).join("world")).unwrap();
        std::fs::write(
            temp.instance_dir(&id).join("world").join("level.dat"),
            vec![0u8; 1024],
        )
        .unwrap();

        let status = temp.1.status(Some(&id)).unwrap();
        assert_eq!(status["status"]["size_bytes"], json!(3072));
        assert_eq!(status["status"]["size_human"], json!("3.0 KiB"));
        assert_eq!(status["status"]["file_count"], json!(2));
        assert_eq!(status["status"]["dir_count"], json!(1));
        assert_eq!(status["status"]["size_truncated"], json!(false));
        assert!(
            status["status"]["warnings"].as_array().unwrap().is_empty(),
            "文件齐了就不该再有告警: {}",
            status["status"]["warnings"]
        );

        // 目录被外部删掉 → 状态里明说
        std::fs::remove_dir_all(temp.instance_dir(&id)).unwrap();
        let status = temp.1.status(Some(&id)).unwrap();
        assert_eq!(status["status"]["dir_exists"], json!(false));
        let warnings = status["status"]["warnings"].as_array().unwrap();
        assert!(
            warnings
                .iter()
                .any(|w| w.as_str().unwrap().contains("目录不存在")),
            "{warnings:?}"
        );
    }

    #[test]
    fn scan_prunes_missing_and_adopts_unknown_dirs() {
        let temp = TempData::new("scan");
        let kept = id_of(&create(&temp, "留着"));
        let gone = id_of(&create(&temp, "被删了"));

        // 1) 外部把目录删了 → prune
        std::fs::remove_dir_all(temp.instance_dir(&gone)).unwrap();
        // 2) 外部新建了一个目录 → adopt
        std::fs::create_dir_all(temp.instance_dir("deadbeefdeadbeef")).unwrap();
        // 3) 目录名不是合法 id → 跳过
        std::fs::create_dir_all(temp.instance_dir("我的服务器")).unwrap();
        // 4) 隐藏目录 → 忽略
        std::fs::create_dir_all(temp.instance_dir(".tmp-migration")).unwrap();

        let report = temp.1.scan().unwrap();
        assert_eq!(report["skipped"], json!(false));
        assert_eq!(report["pruned"], json!([gone.clone()]));
        assert_eq!(report["adopted"], json!(["deadbeefdeadbeef"]));
        assert_eq!(report["ignored"], json!(["我的服务器"]));
        assert_eq!(report["total"], json!(2));
        assert_eq!(report["selected"], json!(kept), "选中项应顺位到还在的实例");

        // 被 prune 的元数据应当已被清掉
        assert!(!temp.config_file(&gone).is_file());
        // 被 adopt 的元数据应当已写好，且 name 默认取目录名
        let adopted = temp.1.get("deadbeefdeadbeef").unwrap();
        assert_eq!(adopted["instance"]["name"], json!("deadbeefdeadbeef"));
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(2));
    }

    #[test]
    fn scan_can_be_told_to_keep_metadata() {
        let temp = TempData::new("no-prune");
        let mut resolved = TempData::new("no-prune-2");
        // 换成 prune_missing = false 的配置
        resolved.1.config.prune_missing = false;
        let id = id_of(&create(&resolved, "服"));
        std::fs::remove_dir_all(resolved.instance_dir(&id)).unwrap();

        let report = resolved.1.scan().unwrap();
        assert_eq!(report["pruned_count"], json!(0));
        assert_eq!(report["total"], json!(1), "元数据保留，只是目录没了");
        let status = resolved.1.status(Some(&id)).unwrap();
        assert_eq!(status["status"]["dir_exists"], json!(false));
        let _ = temp;
    }

    #[test]
    fn same_name_different_case_is_allowed() {
        // 与 V1 一致：只按去空白后的字符串比，不做大小写折叠
        let temp = TempData::new("case");
        create(&temp, "Server");
        create(&temp, "server");
        assert_eq!(temp.1.list(false).unwrap()["count"], json!(2));
    }

    // ── 修改元数据 ────────────────────────────────────────────────────────

    fn update(temp: &TempData, id: &str, patch: Value) -> RpcResult<Value> {
        temp.1
            .update(id, patch.as_object().cloned().unwrap_or_default())
    }

    #[test]
    fn update_renames_and_syncs_index() {
        let temp = TempData::new("update-name");
        let id = id_of(&create(&temp, "旧名字"));

        let result = update(&temp, &id, json!({ "name": "新名字" })).unwrap();
        assert_eq!(result["changed"], json!(true));
        assert_eq!(result["instance"]["name"], json!("新名字"));
        // 索引里的摘要也要跟着改，否则列表显示旧名
        let list = temp.1.list(false).unwrap();
        assert_eq!(list["instances"][0]["name"], json!("新名字"));
        // 落盘的文件里也是新名字
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(raw.contains("新名字"), "{raw}");
    }

    #[test]
    fn update_rejects_duplicate_name_and_bad_values() {
        let temp = TempData::new("update-validate");
        let first = id_of(&create(&temp, "甲"));
        create(&temp, "乙");

        let err = update(&temp, &first, json!({ "name": "乙" })).unwrap_err();
        assert_eq!(err.code, "instance_name_taken");

        // 改成自己现在的名字不算重名，也不算改动
        let same = update(&temp, &first, json!({ "name": "甲" })).unwrap();
        assert_eq!(same["changed"], json!(false));

        for (patch, hint) in [
            (json!({ "name": "  " }), "名称"),
            (json!({ "runtime": "native" }), "未知运行环境"),
            (json!({ "max_memory": 8 }), "maxMemory"),
            (json!({ "max_memory": "2G" }), "maxMemory"),
            (json!({ "line_ending": "\r" }), "line_endings"),
            (json!({ "compat_mode": "yes" }), "布尔值"),
            (json!({ "path": "/etc" }), "层级过浅"),
            (json!({ "nope": 1 }), "不认识的字段"),
            (json!({ "id": "hack" }), "不认识的字段"),
        ] {
            let err = update(&temp, &first, patch.clone()).unwrap_err();
            assert_eq!(
                err.code, "invalid_params",
                "补丁 {patch} 应当被拒绝，实际: {err}"
            );
            assert!(
                err.message.contains(hint),
                "补丁 {patch} 的提示: {}",
                err.message
            );
        }

        // 认错的实例
        assert_eq!(
            update(&temp, "ffffffffffffffff", json!({ "name": "x" }))
                .unwrap_err()
                .code,
            "instance_not_found"
        );
        assert_eq!(
            update(&temp, "../x", json!({ "name": "x" }))
                .unwrap_err()
                .code,
            "invalid_params"
        );
    }

    #[test]
    fn update_only_touches_provided_fields() {
        let temp = TempData::new("update-partial");
        let created = temp
            .1
            .create(json!({
                "name": "服",
                "maxMemory": 2048,
                "runtimeEnvId": "jre21",
                "serverFile": "server.jar",
                "compatMode": true
            }))
            .unwrap();
        let id = id_of(&created);

        let result = update(&temp, &id, json!({ "max_memory": 4096 })).unwrap();
        assert_eq!(result["instance"]["max_memory"], json!(4096));
        // 其它字段原封不动
        assert_eq!(result["instance"]["runtime_env_id"], json!("jre21"));
        assert_eq!(result["instance"]["server_file"], json!("server.jar"));
        assert_eq!(result["instance"]["compat_mode"], json!(true));
        assert_eq!(result["instance"]["name"], json!("服"));
    }

    #[test]
    fn update_clears_optional_fields_with_null_or_empty_string() {
        let temp = TempData::new("update-clear");
        let created = temp
            .1
            .create(json!({
                "name": "服",
                "maxMemory": 2048,
                "runtimeEnvId": "jre21",
                "customJvmArgs": "-Xmx1G",
                "compatMode": true
            }))
            .unwrap();
        let id = id_of(&created);

        let result = update(
            &temp,
            &id,
            json!({ "max_memory": null, "custom_jvm_args": "   ", "compat_mode": false }),
        )
        .unwrap();
        assert_eq!(result["changed"], json!(true));
        assert!(result["instance"]["max_memory"].is_null());
        assert!(result["instance"]["custom_jvm_args"].is_null());
        assert_eq!(result["instance"]["compat_mode"], json!(false));
        // 没传的还留着
        assert_eq!(result["instance"]["runtime_env_id"], json!("jre21"));

        // 落盘的文件里也不该再有这些 key（V1 的序列化就是这么省字段的）
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(!raw.contains("maxMemory"), "{raw}");
        assert!(!raw.contains("customJvmArgs"), "{raw}");
        assert!(!raw.contains("compatMode"), "{raw}");
    }
}
