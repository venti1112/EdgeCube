//! 实例管理模块：元数据、目录、状态，以及进程启停与控制台。
//!
//! 存储方式：索引 + 单实例元数据 + 工作目录
//! 三分离，详见 [`store`] 的模块文档。
//!
//! # 边界
//!
//! 管**实例的一切**：磁盘侧（元数据、目录、体积，见 [`store`]）与进程侧
//! （启停、PTY 控制台、退出码，见 [`process`]）。
//!
//! 「只管磁盘不管进程」是它早期的边界 —— 那时进程管理还没落地。现在两者都在
//! 这里，因为 `phase` / 退出码本来就是**实例**的属性，拆成两个模块只会让
//! 「这台实例到底在不在跑」有两个来源。两块代码在文件层面是分开的，互不依赖。
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
//! | `instance.config.get` | 读服务端配置（后端认哪种，见 [`config`]） |
//! | `instance.config.save` | 写回服务端配置 |
//! | `instance.config.icon.get` | 读服务端图标（`server-icon.png`） |
//! | `instance.config.icon.save` | 写服务端图标（必须 64×64 PNG） |
//! | `instance.eula.get` | 读 EULA 状态（`eula.txt` 里有没有 `eula=true`） |
//! | `instance.eula.accept` | 同意 EULA（写入 `eula.txt`，没有就建） |

pub mod archive;
pub mod config;
pub mod eula;
pub mod files;
pub mod model;
pub mod players;
pub mod process;
pub mod provision;
pub mod store;

use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use axum::body::{Body, Bytes};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{DefaultBodyLimit, Path as AxumPath, Query, State as AxumState};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete as http_delete, get as http_get, post as http_post};
use axum::{Json, Router};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::io::AsyncWriteExt;
use tokio::sync::Mutex;

use self::model::{
    CUSTOM_JVM_ARGS_MAX_CHARS, InstanceConfig, InstanceStatus, LINE_ENDING_CRLF, LINE_ENDING_LF,
    MAX_MEMORY_MB_LIMIT, STARTUP_COMMAND_MAX_CHARS, STOP_COMMAND_MAX_CHARS, ServerPhase,
    UPNP_PROTOCOL_TCP, UPNP_PROTOCOL_UDP, compose_java_command,
};
use self::process::ProcessManager;
use self::store::{InstanceStore, generate_id, validate_id, validate_instance_dir};
use crate::error::{Result, RpcError, RpcResult};
use crate::module::builtin::runtime;
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration, ok};
use crate::server::http::api_result;
use crate::state::AppState;
use crate::util::{humanize_bytes, now_ms};

/// 事件主题。
///
/// `pub` 是给 **upnp 模块**用的：它靠监听这些主题跟随实例的启停与配置变更
/// （见 `module::builtin::upnp` 的说明），不再是「谁也不知道的字符串」。
pub const TOPIC_CREATED: &str = "instance.created";
pub const TOPIC_DELETED: &str = "instance.deleted";
pub const TOPIC_UPDATED: &str = "instance.updated";
/// 实例名长度上限（按字符数）。
const NAME_MAX_CHARS: usize = 64;

/// 重启时等旧进程退下去的上限（优雅停一次、再强杀一次，各用这么久）。
const RESTART_GRACE: std::time::Duration = std::time::Duration::from_secs(15);

/// 删除实例时等进程退下去的上限。
const DELETE_STOP_GRACE: std::time::Duration = std::time::Duration::from_secs(3);

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
    /// 关掉它就永远不会自动删元数据，
    /// 代价是列表里会留下指向空目录的实例（状态里会给出 warning）。
    pub prune_missing: bool,

    /// 目录体积统计的条目上限（防止扫几十 GB 的存档卡住）。
    pub scan_max_entries: u64,

    /// 目录体积统计的深度上限。
    pub scan_max_depth: usize,

    /// 内置编辑器读写的单文件上限（字节），也是上传的单文件上限。
    pub text_max_bytes: u64,

    /// 上传接口的单文件上限（字节）。超过就中断连接并删掉半截文件。
    pub upload_max_bytes: u64,

    /// 文件搜索一次最多返回多少条。
    pub search_max_results: usize,

    /// 单个归档（压缩/解压/下载打包）最多收多少条目。
    pub archive_max_entries: u64,
}

impl Default for InstanceModuleConfig {
    fn default() -> Self {
        Self {
            dir: String::new(),
            scan_on_start: true,
            prune_missing: true,
            scan_max_entries: 20_000,
            scan_max_depth: 12,
            text_max_bytes: 4 * 1024 * 1024,
            upload_max_bytes: 2 * 1024 * 1024 * 1024,
            search_max_results: 2_000,
            archive_max_entries: 200_000,
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

    /// 文件管理那几条上限。
    fn file_limits(&self) -> files::Limits {
        files::Limits {
            text_max_bytes: self.text_max_bytes.max(1024),
            search_max: self.search_max_results.max(1),
            archive_max_entries: self.archive_max_entries.max(1),
        }
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

/// 从 `[modules.config.instance]` 这一节解析出数据根。
///
/// **所有落到 EdgeCube 自己目录里的模块共用它**：实例在 `<root>/instances/`、
/// 下载队列的暂存在 `<root>/download/`、运行环境在 `<root>/runtimes/` ——
/// 「EdgeCube 的数据放哪」只该有一个答案。
///
/// 读的是**配置节本身**而不是 instance 模块的运行时状态，所以 instance 被
/// `modules.disabled` 关掉时也照样算得对。这一节坏了（比如字段类型写错）时
/// 退回平台默认值：那种情况下 instance 模块自己会先报错，不该连累别人跟着崩。
pub fn resolve_data_dir(section: Option<&toml::Value>) -> PathBuf {
    let Some(value) = section else {
        return default_data_dir();
    };
    match InstanceModuleConfig::deserialize(value.clone()) {
        Ok(config) => config.resolved_dir(),
        Err(e) => {
            tracing::warn!(error = %e, "读取 [modules.config.instance] 失败，改用平台默认数据根");
            default_data_dir()
        }
    }
}

/// 实例 id → 实例工作目录（绝对路径）。
///
/// 这是**给别的模块用的**入口：任何「以实例根目录为根」的相对路径都得先知道
/// 根在哪。而「元数据里自定义了 `path` 就用它、否则 `<root>/instances/<id>`」
/// 这套回退是 [`store`] 的知识，不该在别处再实现一遍 —— 所以只留这一个纯函数，
/// 实例模块与调用方共用同一份规则，不会各写一套然后慢慢漂移。
///
/// 只读磁盘上的元数据，因此**不依赖 instance 模块是否被启用**：
/// `[modules.config.instance]` 这一节即使模块被 `modules.disabled` 排除也仍然在
/// `Config` 里，调用方自己取出来、把 `dir` 解析好传 `data_dir` 即可。
///
/// 返回 `Err(String)` 而不是 [`RpcError`]：错误码是模块自己的事，调用方
/// 按自己的前缀往上抛（下载模块给的是 `download_instance_not_found`）。
pub fn resolve_instance_root(data_dir: &Path, id: &str) -> std::result::Result<PathBuf, String> {
    validate_id(id)?;
    let store = InstanceStore::new(data_dir);

    let config = store
        .read_config(id)
        .map_err(|e| format!("读取实例 `{id}` 的元数据失败: {e}"))?;
    if let Some(config) = config {
        return Ok(store.instance_dir(&config));
    }

    // 元数据缺失时按默认位置兜底（外部直接建的目录、`instance.scan` 还没跑过）。
    // 与 `build_status` 取目录的方式一致 —— 否则会出现「列表里有、下载说没有」。
    let fallback = store.default_dir(id);
    if fallback.is_dir() {
        return Ok(fallback);
    }

    Err(format!("实例 `{id}` 不存在"))
}

/// 这个实例是不是 PocketMine 系（`.phar` 服务端）。
///
/// 判据是**启动命令或服务端文件名里出现 `.phar` / `pocketmine`**（忽略大小写）
/// —— V2 的实例元数据里没有「运行时是什么」这个字段，所以从这两处文本判。
/// 这是给 `mods` 用的：它据此决定插件那一栏认 `.jar` 还是 `.phar`。
///
/// 只读磁盘上的元数据，`instance` 模块被禁用也照样算得对；读不出来就是 `false`
/// （宁可当 Java 实例，也不要把一个普通实例判成 PocketMine）。
pub fn is_pocketmine(data_dir: &Path, id: &str) -> bool {
    let store = InstanceStore::new(data_dir);
    let Ok(Some(config)) = store.read_config(id) else {
        return false;
    };
    let haystack = format!(
        "{} {}",
        config.startup_command.as_deref().unwrap_or_default(),
        config.server_file.as_deref().unwrap_or_default()
    )
    .to_ascii_lowercase();
    haystack.contains(".phar") || haystack.contains("pocketmine")
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
    /// 进程表。`Arc` 是必须的：每个请求都会 `resolve()` 出一份 `Resolved`，
    /// 而进程表必须是全局唯一那份。
    process: Arc<ProcessManager>,
}

struct InstanceState {
    resolved: OnceLock<Resolved>,
    /// PTY 进程表。全局唯一 —— 阶段、退出码、控制台订阅都从这里读。
    process: Arc<ProcessManager>,
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
            process: Arc::new(ProcessManager::default()),
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
        let resolved = Resolved::new(config, self.process.clone());
        // 另一个调用抢先设置也无所谓，值是一样的
        let _ = self.resolved.set(resolved);
        self.resolved
            .get()
            .cloned()
            .ok_or_else(|| RpcError::internal("实例模块初始化失败"))
    }
}

impl Resolved {
    fn new(config: InstanceModuleConfig, process: Arc<ProcessManager>) -> Self {
        Self {
            store: InstanceStore::new(config.resolved_dir()),
            config,
            process,
        }
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
            "instance": self.wire(&config),
            "dir": dir.display().to_string(),
            "lint": config.lint(),
        }))
    }

    /// 读服务端配置：认哪种 + 内容。
    ///
    /// 实例目录不存在时**不算错**：目录刚被删、或元数据指向一个还没建过的自定义
    /// 路径都会走到这儿。这时按「三种都没有」回，前端给「先启动一次服务端」的提示。
    fn config_load(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);

        if !dir.is_dir() {
            return Ok(config::Detected {
                kind: None,
                content: String::new(),
            }
            .to_wire());
        }

        config::load(&dir)
            .map(|detected| detected.to_wire())
            .map_err(|e| {
                RpcError::new("instance_config_unreadable", format!("读配置文件失败：{e}"))
            })
    }

    // ── EULA ──────────────────────────────────────────────────────────────

    /// 读一个实例的 EULA 状态。
    ///
    /// 实例目录还不存在（元数据在、目录被删了）时也返回「没同意」——
    /// 前端据此弹框，而不是弹一个「读不到」的错误。
    fn eula_status(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);
        let status = eula::status(&dir);
        Ok(json!({
            "id": id,
            "file": eula::FILE,
            "exists": status.exists,
            "agreed": status.agreed,
        }))
    }

    /// 同意 EULA：把固定内容写进 `eula.txt`（没有就建）。
    ///
    /// 内容由 daemon 定（见 [`eula::ACCEPTED_CONTENT`]）—— 前端**给不了内容**，
    /// 与 `instance.config.save` 的「文件名由封闭枚举算」是同一条约束。
    fn eula_accept(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);
        eula::accept(&dir).map_err(|e| {
            RpcError::new(
                "instance_eula_unwritable",
                format!("写入 {} 失败：{e}", eula::FILE),
            )
        })?;
        Ok(json!({
            "id": id,
            "file": eula::FILE,
            "exists": true,
            "agreed": true,
        }))
    }

    /// 写服务端配置。`kind` 决定写哪个文件（见 [`config::ConfigKind::file_name`]）。
    ///
    /// 这里**不需要**额外校验「文件真在实例目录里」：文件名是从一个封闭枚举算出来的
    /// （三个固定字符串之一），前端传的 `kind` 解析不过就直接拒。
    fn config_save(&self, id: &str, kind_wire: &str, content: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);

        let kind = config::ConfigKind::parse(kind_wire).ok_or_else(|| {
            RpcError::invalid_params(format!(
                "不认识的配置类型 `{kind_wire}`（可选：pnx、allay、java、pmmp）"
            ))
        })?;

        if !dir.is_dir() {
            return Err(RpcError::new(
                "instance_dir_missing",
                format!("实例目录不存在：{}", dir.display()),
            ));
        }

        config::save(&dir, kind, content).map_err(|message| {
            // 文件不在（让用户先启动一次）与写失败是两件事，码分开
            let code = if message.contains("不存在") {
                "instance_config_missing"
            } else {
                "instance_config_save_failed"
            };
            RpcError::new(code, message)
        })?;

        Ok(json!({ "kind": kind.wire_name(), "file": kind.file_name() }))
    }

    /// 读服务端图标（`server-icon.png`）。没有图标**不是错误**。
    ///
    /// 与 [`config_load`](Self::config_load) 一样，实例目录不存在时按「没有」回 ——
    /// 那多半是目录刚被删或还没建，不该在这一层报错。
    fn icon_load(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);

        if !dir.is_dir() {
            return Ok(config::Icon::Missing.to_wire());
        }

        config::load_icon(&dir)
            .map(|icon| icon.to_wire())
            .map_err(|e| RpcError::new("instance_icon_unreadable", format!("读图标失败：{e}")))
    }

    /// 写服务端图标。`data` 是 base64 的 PNG（**必须 64×64**，见 `config::check_icon`）。
    fn icon_save(&self, id: &str, data_base64: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);

        if !dir.is_dir() {
            return Err(RpcError::new(
                "instance_dir_missing",
                format!("实例目录不存在：{}", dir.display()),
            ));
        }

        let bytes = config::decode_icon(data_base64).map_err(RpcError::invalid_params)?;
        config::save_icon(&dir, &bytes)
            .map_err(|message| RpcError::new("instance_icon_invalid", message))?;

        Ok(json!({ "file": config::ICON_FILE, "size": bytes.len() }))
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
                // 元数据自身的问题（含「表单没填全 / 没写启动命令」）
                warnings.extend(config.lint());
                // 表单模式还要看磁盘：环境装没装、jar 在不在
                if !config.manual_command() && stats.exists {
                    warnings.extend(self.form_warnings(config, &dir));
                }
            }
        }
        if stats.truncated {
            warnings.push(format!(
                "目录条目超过 {max_entries} 或层级超过 {max_depth}，体积只是下界"
            ));
        }

        // 进程视角：没在跑就看上一次退出的结果
        let run = self
            .process
            .get(id)
            .map(|session| session.info())
            .unwrap_or_default();

        InstanceStatus {
            id: id.to_string(),
            name: name.to_string(),
            phase: run.phase,
            running: run.phase == ServerPhase::Running,
            // 进程管理已经接进来了：阶段真的会动
            process_managed: true,
            pid: run.pid,
            exit_code: run.exit_code,
            started_at_ms: run.started_at_ms,
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
        config.startup_command = normalize_command(
            config.startup_command,
            "启动命令",
            STARTUP_COMMAND_MAX_CHARS,
        )?;
        config.stop_command =
            normalize_command(config.stop_command, "停止命令", STOP_COMMAND_MAX_CHARS)?;
        config.path = match config.path.as_deref().map(str::trim) {
            Some(path) if !path.is_empty() => {
                validate_instance_dir(Path::new(path)).map_err(RpcError::invalid_params)?;
                Some(path.to_string())
            }
            _ => None,
        };
        // 启动配置：表单那四个字段与手动开关，和 update 走同一套规范化
        config.runtime_env_id = normalize_optional_text(config.runtime_env_id);
        config.server_file = normalize_server_file(config.server_file)?;
        config.max_memory = check_max_memory(config.max_memory.map(u64::from))?;
        config.custom_jvm_args = normalize_command(
            config.custom_jvm_args,
            "自定义 JVM 参数",
            CUSTOM_JVM_ARGS_MAX_CHARS,
        )?;
        // UPnP 三字段：和 update 走同一套校验（create 是直接反序列化的，
        // 协议字符串与端口 0 得在这里补上把关）
        config.upnp_protocol = normalize_upnp_protocol(&config.upnp_protocol)?;
        config.upnp_external_port = config.upnp_external_port.map(check_upnp_port).transpose()?;
        // STUN 目标端口：0 同样拦住（留空才表示「跟随服务端端口」）
        config.stun_target_port = config
            .stun_target_port
            .map(check_stun_target_port)
            .transpose()?;

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
            "instance": self.wire(&config),
            "dir": dir.display().to_string(),
            "selected": id,
            "count": index.instances.len(),
        }))
    }

    /// 删除实例。`keep_files = true` 时只把它从列表里摘掉，目录留在磁盘上。
    fn delete(&self, id: &str, keep_files: bool) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;

        // 删之前先把进程收掉：服务端还在跑的时候把目录删了，它会带着一堆
        // 「文件不见了」的报错继续跑，用户还以为是删失败了。
        // 这里用静默版（不发事件、不等收尾），反正紧接着整个实例就没了。
        if let Some(session) = self.process.get(id)
            && session.info().alive()
        {
            process::shutdown_quiet(&session);
            let deadline = std::time::Instant::now() + DELETE_STOP_GRACE;
            while session.info().alive() && std::time::Instant::now() < deadline {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
        self.process.remove(id);

        // frpc **不**跟着收：隧道是独立实例（可能还被别的游戏实例连着），
        // 删掉一个游戏实例不该把公网入口一起拔了。要停去「管理隧道」里停。

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
            // 删掉选中项后顺位到第一个
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
    /// **不会移动磁盘上的文件**。
    fn update(&self, id: &str, mut patch: serde_json::Map<String, Value>) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;

        // `id` 是**寻址参数**，不是可改字段：WS 那边 `params` 里本来就带着它
        // （`{ "id": …, "name": … }`），HTTP 那边客户端也可能把它重复塞进 body。
        // 所以这里直接丢掉 —— 它不该被报成「不认识的字段」，否则每个客户端都得
        // 为「寻址键」做一次特例（前端已经踩过一次）。
        //
        // 丢掉是安全的：`config.id` 在 update 里从来不赋值，改名更名不存在。
        patch.remove("id");

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

        if let Some(value) = patch.get("startup_command") {
            // 空串与 null 一样当作"清掉"，界面上就是"清空输入框"
            let raw = match value {
                Value::Null => None,
                other => Some(string_field(other, "startup_command")?),
            };
            let next = normalize_command(raw, "启动命令", STARTUP_COMMAND_MAX_CHARS)?;
            apply(config.startup_command != next);
            config.startup_command = next;
        }

        if let Some(value) = patch.get("stop_command") {
            // 与启动命令同一套语义：缺席 = 不动、null 或空白 = 清掉（回落到默认的
            // `stop`）。前端「清空输入框」发的是 null，所以这里必须接受 null。
            let raw = match value {
                Value::Null => None,
                other => Some(string_field(other, "stop_command")?),
            };
            let next = normalize_command(raw, "停止命令", STOP_COMMAND_MAX_CHARS)?;
            apply(config.stop_command != next);
            config.stop_command = next;
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

        if let Some(value) = patch.get("manual_command") {
            // 与其它可选字段一致：`null` = 清掉这个显式选择，回到「按字段推断」
            let next = match value {
                Value::Null => None,
                other => Some(
                    other
                        .as_bool()
                        .ok_or_else(|| RpcError::invalid_params("manual_command 必须是布尔值"))?,
                ),
            };
            apply(config.manual_command != next);
            config.manual_command = next;
        }

        // 「选一个」的字段（运行环境的 id、连带启动的隧道、服务端 jar 的名字）
        // 同一套存法：缺席 = 不动、null 或空白 = 清掉
        for (key, slot) in [
            ("runtime_env_id", &mut config.runtime_env_id),
            ("frp_tunnel_id", &mut config.frp_tunnel_id),
        ] {
            if let Some(value) = patch.get(key) {
                let next = match value {
                    Value::Null => None,
                    other => normalize_optional_text(Some(string_field(other, key)?)),
                };
                apply(*slot != next);
                *slot = next;
            }
        }

        if let Some(value) = patch.get("server_file") {
            let next = match value {
                Value::Null => None,
                other => normalize_server_file(Some(string_field(other, "server_file")?))?,
            };
            apply(config.server_file != next);
            config.server_file = next;
        }

        if let Some(value) = patch.get("max_memory") {
            let next = match value {
                Value::Null => None,
                other => check_max_memory(Some(other.as_u64().ok_or_else(|| {
                    RpcError::invalid_params("max_memory 必须是整数（单位 MB）")
                })?))?,
            };
            apply(config.max_memory != next);
            config.max_memory = next;
        }

        if let Some(value) = patch.get("custom_jvm_args") {
            let raw = match value {
                Value::Null => None,
                other => Some(string_field(other, "custom_jvm_args")?),
            };
            let next = normalize_command(raw, "自定义 JVM 参数", CUSTOM_JVM_ARGS_MAX_CHARS)?;
            apply(config.custom_jvm_args != next);
            config.custom_jvm_args = next;
        }

        // UPnP 端口映射：开关 / 协议 / 外网端口（`null` = 回到「用服务端端口」）
        if let Some(value) = patch.get("upnp_enabled") {
            let flag = value
                .as_bool()
                .ok_or_else(|| RpcError::invalid_params("upnp_enabled 必须是布尔值"))?;
            apply(config.upnp_enabled != flag);
            config.upnp_enabled = flag;
        }

        if let Some(value) = patch.get("upnp_protocol") {
            let text = value
                .as_str()
                .ok_or_else(|| RpcError::invalid_params("upnp_protocol 必须是字符串"))?;
            let next = normalize_upnp_protocol(text)?;
            apply(config.upnp_protocol != next);
            config.upnp_protocol = next;
        }

        if let Some(value) = patch.get("upnp_external_port") {
            let next = match value {
                Value::Null => None,
                other => {
                    let port = other
                        .as_u64()
                        .and_then(|port| u16::try_from(port).ok())
                        .ok_or_else(|| {
                            RpcError::invalid_params("upnp_external_port 必须在 1-65535 之间")
                        })?;
                    Some(check_upnp_port(port)?)
                }
            };
            apply(config.upnp_external_port != next);
            config.upnp_external_port = next;
        }

        // STUN 隧道：开关 / PROXY protocol v2 / 转发目标端口
        // （`null` = 回到「跟随服务端端口」）
        if let Some(value) = patch.get("stun_enabled") {
            let flag = value
                .as_bool()
                .ok_or_else(|| RpcError::invalid_params("stun_enabled 必须是布尔值"))?;
            apply(config.stun_enabled != flag);
            config.stun_enabled = flag;
        }

        if let Some(value) = patch.get("stun_proxy_protocol") {
            let flag = value
                .as_bool()
                .ok_or_else(|| RpcError::invalid_params("stun_proxy_protocol 必须是布尔值"))?;
            apply(config.stun_proxy_protocol != flag);
            config.stun_proxy_protocol = flag;
        }

        if let Some(value) = patch.get("stun_target_port") {
            let next = match value {
                Value::Null => None,
                other => {
                    let port = other
                        .as_u64()
                        .and_then(|port| u16::try_from(port).ok())
                        .ok_or_else(|| {
                            RpcError::invalid_params("stun_target_port 必须在 1-65535 之间")
                        })?;
                    Some(check_stun_target_port(port)?)
                }
            };
            apply(config.stun_target_port != next);
            config.stun_target_port = next;
        }

        if let Some(value) = patch.get("line_ending") {
            // **不能用 `string_field`**：它会把首尾空白去掉，而换行符本身**就是**
            // 空白 —— `"\n"` 被 trim 成空串之后永远过不了校验，于是「改换行符」
            // 这件事在 update 里从来就没成功过。
            let ending = value
                .as_str()
                .ok_or_else(|| RpcError::invalid_params("line_ending 必须是字符串"))?
                .to_string();
            if ending != LINE_ENDING_LF && ending != LINE_ENDING_CRLF {
                return Err(RpcError::invalid_params(
                    "line_ending 只能是 \"\\n\" 或 \"\\r\\n\"",
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
                "instance": self.wire(&config),
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
            "instance": self.wire(&config),
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

    // ── 进程 ──────────────────────────────────────────────────────────────

    /// 进程操作都要的「元数据 + 工作目录」。
    fn launch_target(&self, id: &str) -> RpcResult<(InstanceConfig, PathBuf)> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        let config = self.store.read_config(id)?.ok_or_else(|| not_found(id))?;
        let dir = self.store.instance_dir(&config);
        if !dir.is_dir() {
            return Err(RpcError::new(
                "instance_dir_missing",
                format!("实例目录不存在：{}", dir.display()),
            ));
        }
        Ok((config, dir))
    }

    /// 这次启动**真正要跑**的那条命令。
    ///
    /// * 手动模式：用户自己写的那条，原样交给 shell；
    /// * 表单模式：现拼一条（见 [`compose_java_command`]）—— 运行环境装在
    ///   哪、实例目录在哪，只有 daemon 算得对，所以拼在这一层而不是前端。
    ///
    /// 拼不出来就报错，且**错误里要说清差的是哪一步**：原因多半在界面上看不见
    /// （数据根下面的环境目录、实例目录里的文件），含糊一句「启动失败」会让用户
    /// 完全无从下手。
    fn launch_command(&self, config: &InstanceConfig, dir: &Path) -> RpcResult<String> {
        if config.manual_command() {
            return config.startup_command().map(str::to_string).ok_or_else(|| {
                RpcError::new("instance_not_configured", "未配置启动命令，无法启动")
            });
        }
        let (java, jar) = self.resolve_launch_form(config, dir)?;
        Ok(compose_java_command(&java, jar, config))
    }

    /// 表单模式：把「运行环境 + 服务端 jar」解析成拼命令要的两样东西
    /// （java 可执行文件的**绝对路径**、jar 名）。
    ///
    /// 顺带把所有能提前看到的问题都报掉：这两项都只存了名字，可执行文件与 jar
    /// 是不是真在磁盘上、环境记录还在不在，都得现算现看 —— 少一样都起不来。
    fn resolve_launch_form<'a>(
        &self,
        config: &'a InstanceConfig,
        dir: &Path,
    ) -> RpcResult<(PathBuf, &'a str)> {
        let incomplete = |what: &str| {
            RpcError::new(
                "instance_launch_incomplete",
                format!(
                    "{what}，该实例起不来（去「实例设置」里补上，或者打开「手动命令」自己写一条）"
                ),
            )
        };
        let env_id = config
            .runtime_env_id()
            .ok_or_else(|| incomplete("还没选运行环境"))?;
        let jar = config
            .server_file()
            .ok_or_else(|| incomplete("还没选服务端 jar"))?;

        let data_dir = self.store.root();
        let Some(env) = runtime::store::load(data_dir, env_id) else {
            return Err(RpcError::new(
                "instance_runtime_missing",
                format!("选好的运行环境 `{env_id}` 不在了（去「运行环境」里装一个，或换一个）"),
            ));
        };
        let Some(binary) = env.binary.as_deref() else {
            return Err(RpcError::new(
                "instance_runtime_missing",
                format!("运行环境 `{env_id}` 的记录里没有可执行文件，重装一次试试"),
            ));
        };
        if !dir.join(jar).is_file() {
            return Err(RpcError::new(
                "instance_server_file_missing",
                format!("实例目录里没有 `{jar}`，该实例起不来（去「实例设置」里重新选一个）"),
            ));
        }
        Ok((runtime::store::env_dir(data_dir, env_id).join(binary), jar))
    }

    /// 表单模式的「磁盘侧」问题清单（进 `instance.status` 的 warnings）。
    ///
    /// 与 [`Resolved::resolve_launch_form`] 查的是同一批东西，只是这里**只提醒
    /// 不报错**：配好了环境但还没装，是很正常的一个中间状态，不该让状态查询失败。
    fn form_warnings(&self, config: &InstanceConfig, dir: &Path) -> Vec<String> {
        let mut warnings = Vec::new();
        let data_dir = self.store.root();
        if let Some(env_id) = config.runtime_env_id() {
            match runtime::store::load(data_dir, env_id) {
                None => warnings.push(format!("选好的运行环境 `{env_id}` 不在了")),
                Some(env) if env.binary.is_none() => warnings.push(format!(
                    "运行环境 `{env_id}` 里没有可执行文件，重装一次试试"
                )),
                Some(_) => {}
            }
        }
        if let Some(jar) = config.server_file()
            && dir.is_dir()
            && !dir.join(jar).is_file()
        {
            warnings.push(format!("实例目录里没有 `{jar}`"));
        }
        warnings
    }

    /// 进程管理要的那份配置：把 `startup_command` 换成这次真正要跑的命令。
    ///
    /// **只影响这一轮，不落盘** —— `process::start` 只认 `startup_command`
    /// （自动重启也复用它），而元数据里那个字段（手动模式的历史值 / 表单模式的
    /// 留档）不该被一次启动改写。
    fn launch_config(config: &InstanceConfig, command: &str) -> InstanceConfig {
        InstanceConfig {
            startup_command: Some(command.to_string()),
            ..config.clone()
        }
    }

    /// 线上形态：`launch_command` 尽力算（算不出来就是 `null`，原因见 `lint` 与
    /// 状态里的 warnings）。
    fn wire(&self, config: &InstanceConfig) -> Value {
        let launch = self
            .launch_command(config, &self.store.instance_dir(config))
            .ok();
        config.to_wire_value(launch.as_deref())
    }

    // ── 玩家名单 ──────────────────────────────────────────────────────────

    /// 在线玩家（daemon 从控制台输出里解析出来的那份）。
    ///
    /// 实例存在但没在跑 → 空名单：没有会话就没人上过线。
    fn online_players(&self, id: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        if self.store.read_config(id)?.is_none() {
            return Err(not_found(id));
        }
        let players = self
            .process
            .get(id)
            .map(|session| session.online_players())
            .unwrap_or_default();
        Ok(json!({
            "id": id,
            "players": players,
            "count": players.len(),
        }))
    }

    /// 一份名单文件：`entries` 给标签页，`names` 给在线页打标签（两套规则，
    /// 见 [`players::read_list`]）。
    fn players_list(&self, id: &str, spec: &players::ListSpec) -> RpcResult<Value> {
        let (_, dir) = self.launch_target(id)?;
        let list = players::read_list(&dir, spec);
        Ok(json!({
            "id": id,
            "entries": list.entries,
            "names": list.names,
        }))
    }

    /// 往控制台写一段输入（就是「敲键」：命令与行尾由调用方拼好）。
    ///
    /// 与控制台 WS 走同一条路（[`process::Session::write`]）—— 前端为「发一条
    /// 命令」不必再开一条订阅整个输出的长连接。
    fn console_write(&self, id: &str, data: &str) -> RpcResult<Value> {
        validate_id(id).map_err(RpcError::invalid_params)?;
        if self.store.read_config(id)?.is_none() {
            return Err(not_found(id));
        }
        let session = self
            .process
            .get(id)
            .ok_or_else(|| RpcError::new("instance_not_running", "实例没在运行"))?;
        let written = data.len();
        session
            .write(data.as_bytes().to_vec())
            .map_err(|e| RpcError::new(e.code(), e.to_string()))?;
        Ok(json!({ "written": written }))
    }

    /// 启动。
    async fn start(&self, app: &AppState, id: &str) -> RpcResult<Value> {
        let (config, dir) = self.launch_target(id)?;
        // 命令在这里定下来：手动模式取用户写的，表单模式按运行环境 + jar 现拼
        let command = self.launch_command(&config, &dir)?;
        tracing::info!(id, command = %command, "启动实例");
        let run = process::start(
            &self.process,
            app,
            &Self::launch_config(&config, &command),
            &dir,
        )
        .map_err(|e| RpcError::new(e.code(), e.to_string()))?;

        // 「连带启动」：这个游戏实例引用了某条隧道的话，顺手把那个 **FRP 实例**
        // 也拉起来（`frp_tunnel_id`，见它的文档）。
        //
        // 三件事要注意：
        // * **失败不影响实例启动** —— 隧道是附带的，起不来只记一条 `failed`
        //   在 FRP 那边的进程表里，「网络映射 → 管理隧道」看得到原因；
        // * 已经跑着就什么都不做（一条隧道同时只有一个进程，多条游戏实例
        //   引用同一条隧道是安全的）；
        // * **只连带启动，不连带停止** —— 隧道是独立实例，可能还被别的游戏
        //   实例用着，跟着停会误伤。
        if let Some(tunnel_id) = config.frp_tunnel_id.as_deref() {
            match crate::module::builtin::frp::start_tunnel(app, tunnel_id).await {
                Ok(_) => {
                    tracing::info!(instance = %id, tunnel = %tunnel_id, "映射隧道已随实例启动")
                }
                Err(message) => {
                    tracing::warn!(instance = %id, tunnel = %tunnel_id, %message, "映射隧道没能随实例启动");
                }
            }
        }

        Ok(json!({
            "instance": config.to_wire_value(Some(&command)),
            "run": run,
        }))
    }

    /// 优雅停止（把停止命令写进 PTY）。
    fn stop(&self, app: &AppState, id: &str) -> RpcResult<Value> {
        let (config, _) = self.launch_target(id)?;
        let session = self
            .process
            .get(id)
            .ok_or_else(|| RpcError::new("instance_not_running", "实例没在运行"))?;
        process::stop(&session, &config, app)
            .map_err(|e| RpcError::new(e.code(), e.to_string()))?;
        Ok(json!({ "stopping": true, "run": session.info() }))
    }

    /// 强制停止（直接杀进程组）。
    fn kill(&self, app: &AppState, id: &str) -> RpcResult<Value> {
        let (_, _) = self.launch_target(id)?;
        let session = self
            .process
            .get(id)
            .ok_or_else(|| RpcError::new("instance_not_running", "实例没在运行"))?;
        process::kill(&session, app).map_err(|e| RpcError::new(e.code(), e.to_string()))?;
        Ok(json!({ "killed": true, "run": session.info() }))
    }

    /// 重启：先优雅停（停不动就强杀），等它真退下去再起。
    ///
    /// 这里**不用**「发完停止命令立刻 start」—— 那个时序下旧进程可能还占着端口，
    /// 新一轮会以「端口被占用」的报错退出。所以等旧进程真的收尾。
    async fn restart(&self, app: &AppState, id: &str) -> RpcResult<Value> {
        let (config, dir) = self.launch_target(id)?;
        // 先定命令再停旧进程：配得不对就别白停一次（改完设置再重启是常见操作）
        let command = self.launch_command(&config, &dir)?;
        if let Some(session) = self.process.get(id)
            && session.info().alive()
        {
            let _ = process::stop(&session, &config, app);
            let deadline = std::time::Instant::now() + RESTART_GRACE;
            while session.info().alive() && std::time::Instant::now() < deadline {
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            }
            if session.info().alive() {
                // 停不动就来硬的
                let _ = process::kill(&session, app);
                let hard_deadline = std::time::Instant::now() + RESTART_GRACE;
                while session.info().alive() && std::time::Instant::now() < hard_deadline {
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
            }
            if session.info().alive() {
                return Err(RpcError::new(
                    "instance_stop_timeout",
                    "旧进程没能停下来，重启已放弃（可再试一次强制停止）",
                ));
            }
        }
        let run = process::start(
            &self.process,
            app,
            &Self::launch_config(&config, &command),
            &dir,
        )
        .map_err(|e| RpcError::new(e.code(), e.to_string()))?;
        Ok(json!({ "instance": config.to_wire_value(Some(&command)), "run": run }))
    }
}

/// `instance.update` 允许改的字段。
///
/// `id` 与时间戳由服务端管，不在其列 —— 传了 `id` 会被**忽略**（见
/// [`Resolved::update`]：它是寻址参数）；其余字段缺席 = 不动、传 null = 清空。
///
/// **加了新字段记得同时加到这里**，否则前端发上来会得到「不认识的字段」。
/// 这份清单也是给用户的报错文案，顺序即展示顺序。
const UPDATABLE_FIELDS: [&str; 19] = [
    "name",
    "startup_command",
    "stop_command",
    "compat_mode",
    "auto_restart_on_exit",
    "path",
    "line_ending",
    "manual_command",
    "runtime_env_id",
    "server_file",
    "max_memory",
    "custom_jvm_args",
    "frp_tunnel_id",
    "upnp_enabled",
    "upnp_protocol",
    "upnp_external_port",
    "stun_enabled",
    "stun_proxy_protocol",
    "stun_target_port",
];

/// 取字符串字段（顺带去掉首尾空白）。
fn string_field(value: &Value, key: &str) -> RpcResult<String> {
    value
        .as_str()
        .map(|text| text.trim().to_string())
        .ok_or_else(|| RpcError::invalid_params(format!("{key} 必须是字符串")))
}

/// 「可选 id / 文本」字段的落库形态：trim 后为空一律当作清空。
///
/// 与 `path` 同一条语义 —— 界面上「清空输入框」不该留下一个
/// 空串（那会让「配了但配错」和「没配」在磁盘上分不出来）。
fn normalize_optional_text(raw: Option<String>) -> Option<String> {
    raw.map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

/// 「服务端 jar」只收**文件名**：它会被拼进启动命令，带路径就等于允许
/// 「拿一条元数据去执行任意文件」。
fn normalize_server_file(raw: Option<String>) -> RpcResult<Option<String>> {
    let Some(text) = normalize_optional_text(raw) else {
        return Ok(None);
    };
    if text.contains('/') || text.contains('\\') {
        return Err(RpcError::invalid_params(
            "服务端 jar 只填文件名，不能带路径（它相对实例目录）",
        ));
    }
    if text == "." || text == ".." {
        return Err(RpcError::invalid_params("服务端 jar 的名称不合法"));
    }
    Ok(Some(text))
}

/// 「最大内存」（MB）：`None` / `0` = 不传 `-Xmx`（JVM 自己按机器内存定）；
/// 有值就卡在 [`MAX_MEMORY_MB_LIMIT`] 以内。
fn check_max_memory(mb: Option<u64>) -> RpcResult<Option<u32>> {
    let Some(mb) = mb.filter(|mb| *mb > 0) else {
        return Ok(None);
    };
    if mb > u64::from(MAX_MEMORY_MB_LIMIT) {
        return Err(RpcError::invalid_params(format!(
            "最大内存过大（上限 {MAX_MEMORY_MB_LIMIT} MB）"
        )));
    }
    Ok(Some(mb as u32))
}

/// UPnP 协议：只认 `tcp` / `udp`（大小写不敏感，统一存小写）。
fn normalize_upnp_protocol(text: &str) -> RpcResult<String> {
    let normalized = text.trim().to_ascii_lowercase();
    if normalized == UPNP_PROTOCOL_TCP || normalized == UPNP_PROTOCOL_UDP {
        Ok(normalized)
    } else {
        Err(RpcError::invalid_params(
            "upnp_protocol 只能是 \"tcp\" 或 \"udp\"",
        ))
    }
}

/// UPnP 外网端口：1–65535（0 单独拦住 —— 那是「让路由器随便挑」的意思，
/// 映射出来的端口对不上任何预期）。
fn check_upnp_port(port: u16) -> RpcResult<u16> {
    if port == 0 {
        return Err(RpcError::invalid_params(
            "upnp_external_port 必须在 1-65535 之间",
        ));
    }
    Ok(port)
}

/// STUN 转发目标端口：1–65535（0 拦住 —— 留空的表达法是 `null`，
/// 不是 0）。
fn check_stun_target_port(port: u16) -> RpcResult<u16> {
    if port == 0 {
        return Err(RpcError::invalid_params(
            "stun_target_port 必须在 1-65535 之间",
        ));
    }
    Ok(port)
}

/// 规范化一条「命令」字段：去掉首尾空白、空白串一律当作「清空」，
/// 并卡住长度上限。
///
/// 启动命令与停止命令共用 —— 两者的规则本来就一样，只有文案与上限不同。
fn normalize_command(raw: Option<String>, label: &str, max: usize) -> RpcResult<Option<String>> {
    let Some(text) = raw
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
    else {
        return Ok(None);
    };
    if text.chars().count() > max {
        return Err(RpcError::invalid_params(format!(
            "{label}过长（上限 {max} 字）"
        )));
    }
    Ok(Some(text))
}

fn not_found(id: &str) -> RpcError {
    RpcError::new("instance_not_found", format!("没有 id 为 `{id}` 的实例"))
}

/// 一条控制台连接：把 PTY 输出推下去，把击键写回去。
///
/// # 协议（照 `pty-terminal-demo`）
///
/// 服务端 → 客户端：
///
/// 1. 文本帧 `{"type":"history_begin"}`
/// 2. 二进制帧：**历史快照**（可能没有，历史为空时跳过）
/// 3. 文本帧 `{"type":"history_end","state":{...}}` —— 历史到此为止，`state` 是
///    当前的 [`process::RunInfo`]。**客户端读到它才开始算「实时」**。
/// 4. 之后：二进制帧 = 原始输出；文本帧 `{"type":"exit","code":N,"phase":"..."}`
///    = 进程退出了（连接**不关** —— 服务端可能被重新启动，控制台接着看）。
///
/// 客户端 → 服务端：
///
/// * 二进制帧 = 原样写进 PTY 的字节（击键、粘贴……）；
/// * 文本帧 = `{"resize":{"cols":N,"rows":M}}`。
///
/// 「取历史快照」与「注册订阅者」是 `Session::subscribe` 里**原子**完成的，
/// 所以既不会漏帧也不会重复 —— 这是整个方案的关键，别改成两步。
async fn serve_pty(instance: String, socket: WebSocket, session: Arc<process::Session>) {
    let (mut sender, mut receiver) = socket.split();
    let (tx, mut rx) =
        tokio::sync::mpsc::channel::<crate::pty::OutFrame>(crate::pty::SUBSCRIBER_BUFFER);
    let (history, sub_id) = session.subscribe(tx);
    let info = session.info();

    // 控制台连接不经过 `server::ws`（那是主 API 连接），主连接那套
    // 「连接已建立 / 已断开」的日志照不到这里，所以在本函数头尾各补一条 ——
    // 否则「谁在看控制台」在后端日志里完全查不到。
    tracing::info!(
        instance = %instance,
        phase = info.phase.as_str(),
        history_bytes = history.len(),
        "控制台连接已建立"
    );

    // 1~3：历史 + 当前状态
    let head = Message::Text(r#"{"type":"history_begin"}"#.into());
    if sender.send(head).await.is_err() {
        session.unsubscribe(sub_id);
        tracing::info!(instance = %instance, "控制台连接已断开（握手未完成）");
        return;
    }
    if !history.is_empty() && sender.send(Message::Binary(history.into())).await.is_err() {
        session.unsubscribe(sub_id);
        tracing::info!(instance = %instance, "控制台连接已断开（历史发送失败）");
        return;
    }
    let state = serde_json::to_string(&session.info()).unwrap_or_else(|_| "null".into());
    let end = Message::Text(format!(r#"{{"type":"history_end","state":{state}}}"#).into());
    if sender.send(end).await.is_err() {
        session.unsubscribe(sub_id);
        tracing::info!(instance = %instance, "控制台连接已断开（状态发送失败）");
        return;
    }

    // 4a：PTY → 客户端
    let output = tokio::spawn(async move {
        while let Some(frame) = rx.recv().await {
            let msg = match frame {
                crate::pty::OutFrame::Data(data) => Message::Binary(data.into()),
                crate::pty::OutFrame::Control(json) => Message::Text(json.into()),
            };
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    // 4b：客户端 → PTY
    let in_session = session.clone();
    let in_instance = instance.clone();
    let input = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Binary(data) => {
                    let _ = in_session.write(data.to_vec());
                }
                Message::Text(text) => {
                    let Ok(value) = serde_json::from_str::<Value>(&text) else {
                        continue;
                    };
                    if let Some(resize) = value.get("resize") {
                        let cols = resize.get("cols").and_then(Value::as_u64).unwrap_or(80);
                        let rows = resize.get("rows").and_then(Value::as_u64).unwrap_or(24);
                        // 拖窗口时这条会连着来，放 debug：排查「服务端按 80×24 换行」
                        // 之类的尺寸问题时再临时打开。
                        tracing::debug!(instance = %in_instance, cols, rows, "控制台尺寸调整");
                        let _ = in_session.resize(cols as u16, rows as u16);
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    tokio::select! {
        _ = output => {},
        _ = input => {},
    }

    // 断开只是退订：PTY 与进程照旧（照 demo），别的客户端还能连上来看。
    session.unsubscribe(sub_id);
    tracing::info!(instance = %instance, "控制台连接已断开");
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

        // ── 启动 / 停止 / 重启 / 强制停止 ──
        //
        // 四个回调几乎一样，但 axum 的处理器要求每个都是独立的异步闭包，
        // 所以照上面的写法铺开 —— 比抽一层 trait 好懂。
        let start = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        resolved.start(&app, &id).await
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let stop = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        resolved.stop(&app, &id)
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let restart = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        resolved.restart(&app, &id).await
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        let kill = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>, AxumPath(id): AxumPath<String>| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        resolved.kill(&app, &id)
                    }
                    .await;
                    api_result(result)
                }
            }
        };

        // ── 控制台（PTY 流；协议见 `serve_pty`）──
        let pty = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>,
                  AxumPath(id): AxumPath<String>,
                  upgrade: WebSocketUpgrade| {
                let state = state.clone();
                async move {
                    let resolved = match state.resolved(module_config_of(&app)) {
                        Ok(resolved) => resolved,
                        Err(e) => {
                            return (StatusCode::SERVICE_UNAVAILABLE, e.to_string())
                                .into_response();
                        }
                    };
                    if validate_id(&id).is_err() {
                        return (StatusCode::BAD_REQUEST, "实例 id 不合法").into_response();
                    }
                    // 实例不存在就别开个空终端骗人
                    match resolved.store.read_config(&id) {
                        Ok(Some(_)) => {}
                        Ok(None) => {
                            return (StatusCode::NOT_FOUND, "没有这个实例").into_response();
                        }
                        Err(e) => {
                            return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
                                .into_response();
                        }
                    }
                    // 没在跑也要给会话：历史与上一次的退出信息都在里面
                    let session = resolved.process.ensure(&id);
                    upgrade.on_upgrade(move |socket| serve_pty(id, socket, session))
                }
            }
        };

        // ── 文件下载 / 上传 ──
        //
        // 这两个必须走 HTTP 而不是 WS：世界存档、服务端 jar 都是几十上百 MB，
        // 塞进 JSON 一问一答里不现实。令牌用查询串带（与 PTY 流同一套）。
        //
        // 下载：文件原样发；目录现场打个 zip，所以前端「导出文件夹」只要一次请求。
        // 上传：请求体就是文件内容，边收边写同目录的临时文件，收完 rename 落定。
        let download = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>,
                  AxumPath(id): AxumPath<String>,
                  Query(query): Query<FileDownloadQuery>| {
                let state = state.clone();
                async move {
                    let wanted = query.path;
                    let outcome = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let (_, dir) = resolved.launch_target(&id)?;
                        let limits = resolved.config.file_limits();
                        blocking(move || files::prepare_download(&dir, &wanted, &limits)).await
                    }
                    .await;

                    match outcome {
                        Ok(files::Download::File { path, name, size }) => {
                            let file = match std::fs::File::open(&path) {
                                Ok(file) => file,
                                Err(e) => return api_result(Err(files::io_error(&path, e))),
                            };
                            stream_response(
                                file,
                                None,
                                &name,
                                Some(size),
                                "application/octet-stream",
                            )
                        }
                        Ok(files::Download::Zip {
                            archive,
                            name,
                            size,
                        }) => {
                            let file = match std::fs::File::open(&archive) {
                                Ok(file) => file,
                                Err(e) => return api_result(Err(files::io_error(&archive, e))),
                            };
                            stream_response(
                                file,
                                Some(archive),
                                &name,
                                Some(size),
                                "application/zip",
                            )
                        }
                        Err(error) => api_result(Err(error)),
                    }
                }
            }
        };

        let upload = {
            let state = state.clone();
            move |AxumState(app): AxumState<AppState>,
                  AxumPath(id): AxumPath<String>,
                  Query(query): Query<FileUploadQuery>,
                  body: Body| {
                let state = state.clone();
                async move {
                    let result = async {
                        let resolved = state.resolved(module_config_of(&app))?;
                        let (_, dir) = resolved.launch_target(&id)?;
                        let max_bytes = resolved.config.upload_max_bytes.max(1024);
                        // 目标目录与文件名先校验完，再开始收数据 —— 收了一半才发现
                        // 名字不合法，白传。
                        let target_dir = files::resolve(&dir, &query.path)?;
                        if !target_dir.is_dir() {
                            return Err(RpcError::invalid_params(format!(
                                "{} 不是目录",
                                files::display_path(&dir, &target_dir)
                            )));
                        }
                        let name = files::validate_name(&query.name)?;
                        let final_path = if query.overwrite.unwrap_or(false) {
                            let existing = target_dir.join(&name);
                            if existing.is_dir() {
                                return Err(RpcError::new(
                                    "file_exists",
                                    format!("{name} 是个文件夹，不能覆盖"),
                                ));
                            }
                            existing
                        } else {
                            files::unique_target(&target_dir, &name)?
                        };

                        let temp = files::upload_temp_name(&target_dir);
                        let written = receive_upload(body, &temp, max_bytes).await;
                        let written = match written {
                            Ok(written) => written,
                            Err(error) => {
                                let _ = tokio::fs::remove_file(&temp).await;
                                return Err(error);
                            }
                        };
                        tokio::fs::rename(&temp, &final_path).await.map_err(|e| {
                            let _ = std::fs::remove_file(&temp);
                            RpcError::new("file_io", format!("落盘失败：{e}"))
                        })?;

                        tracing::info!(
                            id,
                            path = %files::display_path(&dir, &final_path),
                            bytes = written,
                            "文件上传完成"
                        );
                        blocking({
                            let dir = dir.clone();
                            let final_path = final_path.clone();
                            move || files::describe(&dir, &final_path)
                        })
                        .await
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
            .route("/api/instances/{id}/start", http_post(start))
            .route("/api/instances/{id}/stop", http_post(stop))
            .route("/api/instances/{id}/restart", http_post(restart))
            .route("/api/instances/{id}/kill", http_post(kill))
            .route("/api/instances/{id}/files/download", http_get(download))
            .route(
                "/api/instances/{id}/files/upload",
                // axum 默认的请求体上限是 2 MB，服务端 jar 一下就超；这里改成
                // 自己在收流时按 upload_max_bytes 计数，超了就断。
                http_post(upload).layer(DefaultBodyLimit::disable()),
            )
            .route("/pty/{id}", http_get(pty))
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

/// `GET /api/instances/{id}/files/download?path=<相对路径>`
#[derive(Debug, Deserialize)]
struct FileDownloadQuery {
    #[serde(default)]
    path: String,
}

/// `POST /api/instances/{id}/files/upload?path=<目录>&name=<文件名>&overwrite=true`
#[derive(Debug, Deserialize)]
struct FileUploadQuery {
    #[serde(default)]
    path: String,
    name: String,
    #[serde(default)]
    overwrite: Option<bool>,
}

/// 把请求体流式写到 [temp]，返回写入字节数。
///
/// 超上限就立即中断（并让调用方删掉临时文件）—— `DefaultBodyLimit` 已经
/// 在这条路由上关掉了，否则 axum 的 2 MB 默认值会把服务端 jar 挡在门外。
async fn receive_upload(body: Body, temp: &Path, max_bytes: u64) -> RpcResult<u64> {
    let mut file = tokio::fs::File::create(temp)
        .await
        .map_err(|e| files::io_error(temp, e))?;
    let mut stream = body.into_data_stream();
    let mut written: u64 = 0;

    while let Some(chunk) = stream.next().await {
        let chunk =
            chunk.map_err(|e| RpcError::new("file_io", format!("接收上传数据失败：{e}")))?;
        written = written.saturating_add(chunk.len() as u64);
        if written > max_bytes {
            return Err(RpcError::new(
                "file_too_large",
                format!("文件超过上传上限 {max_bytes} 字节，已中断"),
            ));
        }
        file.write_all(&chunk)
            .await
            .map_err(|e| files::io_error(temp, e))?;
    }

    file.flush().await.map_err(|e| files::io_error(temp, e))?;
    Ok(written)
}

/// 构造一个「下载」响应：流式响应体 + 附件头。
///
/// [cleanup] 是读完（或客户端提前断开）后要删掉的临时文件。
fn stream_response(
    reader: std::fs::File,
    cleanup: Option<PathBuf>,
    name: &str,
    size: Option<u64>,
    content_type: &str,
) -> Response {
    let mut builder = Response::builder()
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_DISPOSITION, content_disposition(name));
    if let Some(size) = size {
        builder = builder.header(header::CONTENT_LENGTH, size);
    }
    match builder.body(stream_body(reader, cleanup)) {
        Ok(response) => response,
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("构造下载响应失败：{e}"),
        )
            .into_response(),
    }
}

/// 把阻塞读取器变成响应体流。
///
/// 读在 `spawn_blocking` 里做：`Read` 是阻塞的，直接在 reactor 里读会卡住
/// 这台 daemon 上的所有连接。客户端提前断开时 `blocking_send` 会失败，
/// 循环随之中止，临时文件也就在那时被删掉。
fn stream_body<R: std::io::Read + Send + 'static>(reader: R, cleanup: Option<PathBuf>) -> Body {
    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Bytes, std::io::Error>>(4);
    tokio::task::spawn_blocking(move || {
        let mut reader = reader;
        let mut buffer = vec![0u8; 64 * 1024];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(count) => {
                    if tx
                        .blocking_send(Ok(Bytes::copy_from_slice(&buffer[..count])))
                        .is_err()
                    {
                        break;
                    }
                }
                Err(error) => {
                    let _ = tx.blocking_send(Err(error));
                    break;
                }
            }
        }
        if let Some(path) = cleanup {
            let _ = std::fs::remove_file(path);
        }
    });

    Body::from_stream(futures_util::stream::unfold(rx, |mut rx| async move {
        rx.recv().await.map(|item| (item, rx))
    }))
}

/// `Content-Disposition: attachment` 头。
///
/// 两套文件名都给：ASCII 回退给老工具，`filename*`（RFC 5987）保证中文
/// 文件名在浏览器 / curl 里能落对。
fn content_disposition(name: &str) -> String {
    let ascii: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_graphic() && c != '"' && c != '\\' {
                c
            } else {
                '_'
            }
        })
        .collect();
    format!(
        "attachment; filename=\"{ascii}\"; filename*=UTF-8''{}",
        percent_encode(name)
    )
}

fn percent_encode(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for byte in text.as_bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(*byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
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
            .description("服务器实例：元数据 / 目录 / 状态，以及进程启停与 PTY 控制台。")
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(TOPIC_CREATED, "新建了实例");
        reg.topic(TOPIC_DELETED, "删除了实例");
        reg.topic(
            TOPIC_UPDATED,
            "实例元数据被修改（改名/改配置），或扫描后有变化",
        );
        reg.topic(
            process::TOPIC_PHASE,
            "实例的生命周期阶段变了（启动中/运行中/已停止/异常退出）",
        );
        reg.topic(
            process::TOPIC_PLAYERS,
            "实例的在线玩家变了（加入 / 退出 / list 响应 / 进程退出清空）",
        );

        // ── 启动 / 停止 / 重启 / 强制停止 ──
        //
        // 这四个不进 `module.lock`：它们改的是进程表，不是索引，和「读索引→改→
        // 写索引」那段临界区没有交集。真拿去串行化反而会让「一边启动一边建实例」
        // 互相等。
        for (method, description) in [
            ("instance.start", "启动实例"),
            ("instance.stop", "优雅停止（把停止命令写进控制台）"),
            ("instance.restart", "重启实例"),
            ("instance.kill", "强制停止（直接杀进程组）"),
        ] {
            let module = self.state.clone();
            reg.method(method, description, move |ctx| {
                let module = module.clone();
                let method = method.to_string();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let id: String = ctx.param("id")?;
                    match method.as_str() {
                        "instance.start" => resolved.start(&ctx.app, &id).await,
                        "instance.stop" => resolved.stop(&ctx.app, &id),
                        "instance.kill" => resolved.kill(&ctx.app, &id),
                        _ => resolved.restart(&ctx.app, &id).await,
                    }
                }
            });
        }

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

        // ── 服务端配置 ──
        //
        // 「这个实例有哪种配置」的判断在后端（`config::detect_kind`），前端拿
        // `kind` 选字段表。所以前端那边是**一个通用页**，不认识优先级。
        {
            let module = self.state.clone();
            reg.method(
                "instance.config.get",
                "读服务端配置（后端认哪种：pnx.yml > server-settings.yml > server.properties）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.config_load(&id)).await
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "instance.config.save",
                "写回服务端配置（kind 决定写哪个文件，路径不接受前端指定）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let kind: String = ctx.param("kind")?;
                        let content: String = ctx.param("content")?;
                        let guard = module.lock.lock().await;
                        let result =
                            blocking(move || resolved.config_save(&id, &kind, &content)).await;
                        drop(guard);
                        result
                    }
                },
            );
        }

        // ── 服务端图标（server-icon.png）──
        //
        // 单独一对方法而不是塞进上面的 `config.*`：它是**另一个文件**，而且只有
        // Java 系服务端认它（pnx / allay 都是基岩系，没这东西）。走 WS 传 base64
        // 而不是复用 HTTP 上传：图标只有几 KB，而**校验必须在 daemon 侧**
        // （Minecraft 只认 64×64，尺寸不对会静默忽略 —— 那种「改了没反应」最难查）。
        {
            let module = self.state.clone();
            reg.method(
                "instance.config.icon.get",
                "读服务端图标（server-icon.png，base64；没有不是错误）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.icon_load(&id)).await
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "instance.config.icon.save",
                "写服务端图标（base64 的 PNG，必须 64×64）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let data: String = ctx.param("data")?;
                        let guard = module.lock.lock().await;
                        let result = blocking(move || resolved.icon_save(&id, &data)).await;
                        drop(guard);
                        result
                    }
                },
            );
        }

        // ── EULA ──
        //
        // 启动前要过的那一道。判断与写入都在这里：
        // `eula.txt` 在服务端机器上，而 `instance.files.write` 又只写**已存在**的
        // 文件（新实例上服务端还没生成它）—— 所以不能靠「文件编辑」那条路。
        {
            let module = self.state.clone();
            reg.method(
                "instance.eula.get",
                "读 EULA 状态（`eula.txt` 里有没有 `eula=true`）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.eula_status(&id)).await
                    }
                },
            );
        }
        {
            let module = self.state.clone();
            reg.method(
                "instance.eula.accept",
                "同意 EULA：往 eula.txt 写入 eula=true（没有就建）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.eula_accept(&id)).await
                    }
                },
            );
        }

        // ── 文件管理 ──
        //
        // 每个方法都只是「取参数 → 调 `files::xxx` → 把结果原样回给前端」，
        // 所以用一张表驱动，别抄十二遍闭包。它们全都进 `spawn_blocking`：
        // 同步 FS 调用（删除几万个文件的目录、打包 zip）会卡住 reactor。
        //
        // 路径参数一律是**相对实例目录**的字符串，`files::resolve` 负责挡越界。
        {
            for (method, description) in [
                (
                    "instance.files.list",
                    "列出实例目录（目录在前，忽略大小写排序）",
                ),
                ("instance.files.search", "按名称搜索文件（可含子目录）"),
                ("instance.files.mkdir", "新建文件夹"),
                ("instance.files.create", "新建空文件"),
                ("instance.files.rename", "重命名（同目录内）"),
                (
                    "instance.files.delete",
                    "删除文件/文件夹/符号链接（目录递归）",
                ),
                ("instance.files.copy", "复制到指定目录（重名自动加 ` (n)`）"),
                ("instance.files.move", "移动到指定目录（重名报错）"),
                (
                    "instance.files.read",
                    "读文本文件（raw=true 时按 latin1 兜底）",
                ),
                ("instance.files.write", "覆盖写入文本文件"),
                (
                    "instance.files.compress",
                    "把若干个条目压缩成归档（zip / tar.gz / tar.xz / tar.zst）",
                ),
                (
                    "instance.files.extract",
                    "解压归档到新文件夹（zip / tar 家族 / 7z / rar / 单流）",
                ),
            ] {
                let module = self.state.clone();
                reg.method(method, description, move |ctx| {
                    let module = module.clone();
                    let method = method.to_string();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let limits = resolved.config.file_limits();
                        // 所有文件操作的前置：实例存在，且它的工作目录还在
                        let (_, dir) = resolved.launch_target(&id)?;

                        let result = match method.as_str() {
                            "instance.files.list" => {
                                let path = ctx.param_or("path", String::new())?;
                                blocking(move || files::list(&dir, &path)).await?
                            }
                            "instance.files.search" => {
                                let path = ctx.param_or("path", String::new())?;
                                let query: String = ctx.param("query")?;
                                let recursive = ctx.param_or("recursive", false)?;
                                blocking(move || {
                                    files::search(&dir, &path, &query, recursive, &limits)
                                })
                                .await?
                            }
                            "instance.files.mkdir" => {
                                let path = ctx.param_or("path", String::new())?;
                                let name: String = ctx.param("name")?;
                                blocking(move || files::create_dir(&dir, &path, &name)).await?
                            }
                            "instance.files.create" => {
                                let path = ctx.param_or("path", String::new())?;
                                let name: String = ctx.param("name")?;
                                blocking(move || files::create_file(&dir, &path, &name)).await?
                            }
                            "instance.files.rename" => {
                                let path: String = ctx.param("path")?;
                                let name: String = ctx.param("name")?;
                                blocking(move || files::rename(&dir, &path, &name)).await?
                            }
                            "instance.files.delete" => {
                                let path: String = ctx.param("path")?;
                                blocking(move || files::delete(&dir, &path)).await?
                            }
                            "instance.files.copy" => {
                                let path: String = ctx.param("path")?;
                                let dest: String = ctx.param("dest")?;
                                blocking(move || files::copy(&dir, &path, &dest)).await?
                            }
                            "instance.files.move" => {
                                let path: String = ctx.param("path")?;
                                let dest: String = ctx.param("dest")?;
                                blocking(move || files::move_entry(&dir, &path, &dest)).await?
                            }
                            "instance.files.read" => {
                                let path: String = ctx.param("path")?;
                                let raw = ctx.param_or("raw", false)?;
                                blocking(move || files::read_text(&dir, &path, raw, &limits))
                                    .await?
                            }
                            "instance.files.write" => {
                                let path: String = ctx.param("path")?;
                                let content: String = ctx.param("content")?;
                                blocking(move || files::write_text(&dir, &path, &content, &limits))
                                    .await?
                            }
                            "instance.files.compress" => {
                                let paths: Vec<String> = ctx.param("paths")?;
                                let dest: String = ctx.param("dest")?;
                                let name: Option<String> = ctx.optional("name")?;
                                let format = ctx.param_or("format", String::new())?;
                                blocking(move || {
                                    let format = archive::parse_compress_format(&format)?;
                                    files::compress(
                                        &dir,
                                        &paths,
                                        &dest,
                                        name.as_deref(),
                                        format,
                                        &limits,
                                    )
                                })
                                .await?
                            }
                            _ => {
                                let path: String = ctx.param("path")?;
                                let dest: String = ctx.param("dest")?;
                                let name: Option<String> = ctx.optional("name")?;
                                blocking(move || {
                                    files::extract(&dir, &path, &dest, name.as_deref(), &limits)
                                })
                                .await?
                            }
                        };
                        ok(result)
                    }
                });
            }
        }

        // ── 玩家名单 ──
        //
        // 在线玩家由 daemon 从控制台输出里解析（见 `players` 模块文档）——
        // 前端不解析日志，只读结果；四份名单文件也由 daemon 直接读盘，
        // 因为同一个文件有**两套**读取规则（标签页 / 打标签），
        // 只放一处实现才不会两边走偏。
        {
            let module = self.state.clone();
            reg.method(
                "instance.players.online",
                "在线玩家（daemon 从控制台输出里解析）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        blocking(move || resolved.online_players(&id)).await
                    }
                },
            );
        }
        for (method, spec, description) in [
            (
                "instance.players.whitelist",
                &players::WHITELIST,
                "白名单（whitelist.json → white-list.txt）",
            ),
            (
                "instance.players.ops",
                &players::OPS,
                "OP 名单（ops.json → ops.txt）",
            ),
            (
                "instance.players.bans",
                &players::BANS,
                "封禁名单（banned-players.json → banned-players.txt）",
            ),
            (
                "instance.players.ip_bans",
                &players::IP_BANS,
                "IP 封禁名单（banned-ips.json → banned-ips.txt）",
            ),
        ] {
            let module = self.state.clone();
            reg.method(method, description, move |ctx| {
                let module = module.clone();
                async move {
                    let resolved = resolve_for(&module, &ctx)?;
                    let id: String = ctx.param("id")?;
                    blocking(move || resolved.players_list(&id, spec)).await
                }
            });
        }

        // ── 控制台写输入 ──
        {
            let module = self.state.clone();
            reg.method(
                "instance.console.write",
                "往控制台写一段输入（命令 + 行尾，与 WS 控制台同一条路）",
                move |ctx| {
                    let module = module.clone();
                    async move {
                        let resolved = resolve_for(&module, &ctx)?;
                        let id: String = ctx.param("id")?;
                        let data: String = ctx.param("data")?;
                        blocking(move || resolved.console_write(&id, &data)).await
                    }
                },
            );
        }

        // ── HTTP ──
        reg.router("api/instances", self.http_router());
        Ok(())
    }

    /// 优雅关闭。
    ///
    /// **不用管 frpc**：它现在归 frp 模块（一条隧道一个进程），那边收摊时
    /// 自己会收（见 `frp` 模块的 `stop`）。服务端进程也不用管 —— 它们挂在
    /// PTY 上，主端一关就吃到 SIGHUP 自己退。
    async fn stop(&self) -> Result<()> {
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: InstanceModuleConfig = env.config()?;
        let resolved = Resolved::new(config, self.state.process.clone());
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

        // 「创建实例 → 下载服务端」工作流（task 模块没启用时它自己会跳过）
        provision::register(&self.state, &env.app);
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
            let resolved = Resolved::new(
                InstanceModuleConfig {
                    dir: root.display().to_string(),
                    ..Default::default()
                },
                Arc::new(ProcessManager::default()),
            );
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

    /// 建一个「配置完整」的实例：带上启动命令，这样 lint 不该有任何告警。
    fn create(temp: &TempData, name: &str) -> Value {
        temp.1
            .create(json!({ "name": name, "startup_command": "java -jar server.jar nogui" }))
            .unwrap_or_else(|e| panic!("创建 `{name}` 失败: {e}"))
    }

    fn id_of(created: &Value) -> String {
        created["instance"]["id"]
            .as_str()
            .expect("应有 id")
            .to_string()
    }

    /// `resolve_instance_root` 是**给别的模块用**的入口（下载队列靠它把
    /// 「相对实例根目录」变成绝对路径），四条分支都得钉住。
    #[test]
    fn resolve_instance_root_prefers_metadata_then_falls_back_to_default() {
        let temp = TempData::new("resolve-root");

        // 1) 元数据里自定义了 path → 用它
        let custom = temp.dir().join("elsewhere/custom-dir");
        std::fs::create_dir_all(&custom).unwrap();
        let created = temp
            .1
            .create(json!({
                "name": "custom",
                "path": custom.display().to_string(),
            }))
            .expect("应能建实例");
        assert_eq!(
            resolve_instance_root(temp.dir(), &id_of(&created)).unwrap(),
            custom
        );

        // 2) 没写 path → <root>/instances/<id>
        let created = create(&temp, "plain");
        let id = id_of(&created);
        assert_eq!(
            resolve_instance_root(temp.dir(), &id).unwrap(),
            temp.instance_dir(&id)
        );

        // 3) 元数据缺失、但目录在（外部建的目录，scan 还没跑）→ 默认位置兜底
        let orphan = temp.instance_dir("orphan0000000001");
        std::fs::create_dir_all(&orphan).unwrap();
        assert_eq!(
            resolve_instance_root(temp.dir(), "orphan0000000001").unwrap(),
            orphan
        );

        // 4) 什么都不存在 → 报「不存在」，而不是给一个凭空拼出来的目录
        let err = resolve_instance_root(temp.dir(), "missing000000000").unwrap_err();
        assert!(err.contains("不存在"), "{err}");

        // 5) id 会被直接拼进路径，非法字符必须在前一步就被挡住
        let err = resolve_instance_root(temp.dir(), "../escape").unwrap_err();
        assert!(err.contains("非法字符"), "{err}");
    }

    /// 从 `status` 的返回里取出告警列表。
    fn warnings_of(status: &Value) -> Vec<String> {
        status["status"]["warnings"]
            .as_array()
            .expect("应有 warnings")
            .iter()
            .map(|w| w.as_str().unwrap().to_string())
            .collect()
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
        assert_eq!(
            created["instance"]["startup_command"],
            json!("java -jar server.jar nogui")
        );
        assert!(created["instance"]["created_at_ms"].as_u64().unwrap() > 0);
        assert!(temp.instance_dir(&id).is_dir(), "工作目录应已建好");
        assert!(temp.config_file(&id).is_file(), "元数据应已落盘");
        // 新建的实例自动成为选中项
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
        assert_eq!(
            status["status"]["process_managed"],
            json!(true),
            "进程管理已经接进来了"
        );
        assert!(status["status"]["pid"].is_null(), "没在跑就没有 pid");
        assert!(status["status"]["exit_code"].is_null(), "还没跑过");
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
            .create(json!({ "name": "x", "startup_command": "x".repeat(STARTUP_COMMAND_MAX_CHARS + 1) }))
            .unwrap_err();
        assert!(err.message.contains("启动命令过长"), "{}", err.message);

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
    fn create_accepts_full_metadata_and_omits_defaults() {
        let temp = TempData::new("full");
        let created = temp
            .1
            .create(json!({
                "name": "模组服",
                "startupCommand": "java -Xmx4G -jar server.jar nogui",
                "compatMode": true,
                "autoRestartOnExit": true,
                "lineEnding": "\r\n"
            }))
            .unwrap();
        let id = id_of(&created);
        let got = temp.1.get(&id).unwrap();
        assert_eq!(
            got["instance"]["startup_command"],
            json!("java -Xmx4G -jar server.jar nogui")
        );
        assert_eq!(got["instance"]["compat_mode"], json!(true));
        assert_eq!(got["instance"]["auto_restart_on_exit"], json!(true));
        assert_eq!(got["instance"]["line_ending"], json!("\r\n"));
        // 启动命令配了、换行符合法 → 一行 lint 都不该有
        assert!(
            got["lint"].as_array().unwrap().is_empty(),
            "不该有告警: {}",
            got["lint"]
        );
        // 默认值不该被写进文件
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(raw.contains("\"startupCommand\""));
        assert!(!raw.contains("\"path\""), "未设置的字段不该落盘");
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

        // 空配置（默认是表单模式）→ 状态里要提醒差哪两项
        // （进程管理接进来之后这种实例起不来）
        let bare = id_of(&temp.1.create(json!({ "name": "空配置" })).unwrap());
        let warnings = warnings_of(&temp.1.status(Some(&bare)).unwrap());
        assert!(
            warnings.iter().any(|w| w.contains("还没选运行环境")),
            "应提示没选运行环境: {warnings:?}"
        );
        assert!(
            warnings.iter().any(|w| w.contains("还没选服务端 jar")),
            "应提示没选服务端 jar: {warnings:?}"
        );

        // 只写了启动命令的实例（下载向导建出来的那种）→ 手动模式，不该有告警
        let created = create(&temp, "服");
        let id = id_of(&created);
        assert!(
            warnings_of(&temp.1.status(Some(&id)).unwrap()).is_empty(),
            "只写了启动命令 = 手动模式，不该有告警"
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
            warnings_of(&status).is_empty(),
            "文件齐了就不该再有告警: {}",
            status["status"]["warnings"]
        );

        // 目录被外部删掉 → 状态里明说
        std::fs::remove_dir_all(temp.instance_dir(&id)).unwrap();
        let status = temp.1.status(Some(&id)).unwrap();
        assert_eq!(status["status"]["dir_exists"], json!(false));
        let warnings = warnings_of(&status);
        assert!(
            warnings.iter().any(|w| w.contains("目录不存在")),
            "{warnings:?}"
        );
    }

    /// 摆一个「装好的运行环境」：一份元数据 + 一个假的可执行文件。
    ///
    /// 只摆记录，不碰真实下载流程（那条路归 runtime 模块自己的用例管）——
    /// 这里要验的是「实例启动时找不找得到它、拼出来的路径对不对」。
    fn seed_runtime(temp: &TempData, id: &str, binary: &str) -> PathBuf {
        let env = runtime::model::Env {
            id: id.to_string(),
            vendor: "zulu".into(),
            package_type: "jdk".into(),
            version: "21".into(),
            version_name: "21.0.12.1".into(),
            vendor_version: "21.52.203".into(),
            os: "linux".into(),
            arch: "x64".into(),
            archive_type: "tar.gz".into(),
            package_uuid: "uuid".into(),
            file_name: "zulu.tar.gz".into(),
            url: "https://cdn.azul.com/zulu/bin/zulu.tar.gz".into(),
            sha256: None,
            md5: None,
            size: None,
            support_term: None,
            build_date: None,
            state: runtime::model::EnvState::Installed,
            stage: None,
            error: None,
            task_id: None,
            home: binary.rsplit_once('/').map(|(dir, _)| dir.to_string()),
            binary: Some(binary.to_string()),
            created_at_ms: now_ms(),
            installed_at_ms: Some(now_ms()),
            updated_at_ms: now_ms(),
        };
        let executable = runtime::store::env_dir(temp.dir(), id).join(binary);
        std::fs::create_dir_all(executable.parent().expect("应有父目录")).unwrap();
        std::fs::write(&executable, b"#!/bin/sh\n").unwrap();
        runtime::store::ensure_dirs(temp.dir()).expect("应能建运行环境目录");
        runtime::store::save(temp.dir(), &env).expect("应能写环境元数据");
        executable
    }

    /// 表单模式：启动命令现拼，java 用**选好的那个环境里的**。
    #[test]
    fn launch_command_composes_from_the_form() {
        let temp = TempData::new("launch-form");
        let created = temp
            .1
            .create(json!({
                "name": "表单服",
                "manual_command": false,
                "runtime_env_id": "zulu-jdk-21-linux-x64",
                "server_file": "paper.jar",
                "max_memory": 4096,
                "custom_jvm_args": "-XX:+UseG1GC -Dfile.encoding=UTF-8"
            }))
            .unwrap();
        let id = id_of(&created);
        let dir = temp.instance_dir(&id);
        std::fs::write(dir.join("paper.jar"), b"jar").unwrap();

        // 环境还没装：要指名道姓说清是哪一个
        let config = temp.1.store.read_config(&id).unwrap().unwrap();
        let err = temp.1.launch_command(&config, &dir).unwrap_err();
        assert_eq!(err.code, "instance_runtime_missing");
        assert!(
            err.message.contains("zulu-jdk-21-linux-x64"),
            "{}",
            err.message
        );
        // 状态里也提醒（设置页之外的地方能看见）
        let warnings = warnings_of(&temp.1.status(Some(&id)).unwrap());
        assert!(
            warnings.iter().any(|w| w.contains("不在了")),
            "{warnings:?}"
        );

        // 环境装好之后：命令就是拼出来的那条（java 走绝对路径）
        let java = seed_runtime(&temp, "zulu-jdk-21-linux-x64", "zulu21/bin/java");
        let command = temp.1.launch_command(&config, &dir).unwrap();
        assert_eq!(
            command,
            format!(
                "{} -Xmx4096M -XX:+UseG1GC -Dfile.encoding=UTF-8 -jar paper.jar nogui",
                java.display()
            )
        );
        // 线上把这条生效命令一起给前端（设置页与实例卡片直接显示它）
        assert_eq!(temp.1.wire(&config)["launch_command"], json!(command));

        // jar 不在实例目录里 → 同样在启动之前就拦住
        std::fs::remove_file(dir.join("paper.jar")).unwrap();
        let err = temp.1.launch_command(&config, &dir).unwrap_err();
        assert_eq!(err.code, "instance_server_file_missing");
        assert!(err.message.contains("paper.jar"), "{}", err.message);
    }

    /// 表单没填全 / 手动模式没写命令：错误码分开，文案说清差什么。
    #[test]
    fn launch_command_reports_what_is_missing() {
        let temp = TempData::new("launch-gaps");

        // 空配置（默认表单模式）→ 先缺运行环境
        let bare = id_of(&temp.1.create(json!({ "name": "空" })).unwrap());
        let dir = temp.instance_dir(&bare);
        let config = temp.1.store.read_config(&bare).unwrap().unwrap();
        let err = temp.1.launch_command(&config, &dir).unwrap_err();
        assert_eq!(err.code, "instance_launch_incomplete");
        assert!(err.message.contains("运行环境"), "{}", err.message);

        // 选了环境没选 jar → 缺 jar
        update(
            &temp,
            &bare,
            json!({ "runtime_env_id": "zulu-jdk-21-linux-x64" }),
        )
        .unwrap();
        let config = temp.1.store.read_config(&bare).unwrap().unwrap();
        let err = temp.1.launch_command(&config, &dir).unwrap_err();
        assert_eq!(err.code, "instance_launch_incomplete");
        assert!(err.message.contains("服务端 jar"), "{}", err.message);

        // 手动模式但没写命令 → 老错误码（前端已经有这句文案了）
        let manual = id_of(
            &temp
                .1
                .create(json!({ "name": "手动", "manual_command": true }))
                .unwrap(),
        );
        let dir = temp.instance_dir(&manual);
        let config = temp.1.store.read_config(&manual).unwrap().unwrap();
        let err = temp.1.launch_command(&config, &dir).unwrap_err();
        assert_eq!(err.code, "instance_not_configured");

        // 显式切到手动模式：命令说了算，表单字段只是留档
        let kept = id_of(
            &temp
                .1
                .create(json!({
                    "name": "留档",
                    "manual_command": true,
                    "startup_command": "./run.sh",
                    "runtime_env_id": "zulu-jdk-21-linux-x64",
                    "server_file": "server.jar"
                }))
                .unwrap(),
        );
        let dir = temp.instance_dir(&kept);
        let config = temp.1.store.read_config(&kept).unwrap().unwrap();
        assert_eq!(temp.1.launch_command(&config, &dir).unwrap(), "./run.sh");
    }

    /// 交给进程管理的那份配置：命令换掉，**元数据本身一动不动**
    /// （重启与自动重启都复用这一轮的命令）。
    #[test]
    fn launch_config_swaps_the_command_without_touching_metadata() {
        let config = InstanceConfig {
            startup_command: Some("./留档.sh".into()),
            manual_command: Some(false),
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            server_file: Some("paper.jar".into()),
            max_memory: Some(2048),
            ..InstanceConfig::new("a", "服")
        };
        let launch = Resolved::launch_config(&config, "java -jar paper.jar nogui");
        assert_eq!(
            launch.startup_command(),
            Some("java -jar paper.jar nogui"),
            "进程管理只认 startup_command"
        );
        assert_eq!(
            config.startup_command(),
            Some("./留档.sh"),
            "原配置不能被改掉：它是要落盘的元数据"
        );
        assert_eq!(launch.manual_command, Some(false));
        assert_eq!(launch.max_memory, Some(2048));
    }

    /// 表单那五个字段能存能清（与其它可选字段同一套语义）。
    #[test]
    fn update_round_trips_the_form_fields() {
        let temp = TempData::new("form-fields");
        let id = id_of(&create(&temp, "服"));

        let result = update(
            &temp,
            &id,
            json!({
                "manual_command": false,
                "runtime_env_id": "zulu-jdk-21-linux-x64",
                "server_file": "paper.jar",
                "max_memory": 2048,
                "custom_jvm_args": "-Xss4M"
            }),
        )
        .unwrap();
        assert_eq!(result["changed"], json!(true));
        assert_eq!(result["instance"]["manual_command"], json!(false));
        assert_eq!(result["instance"]["max_memory"], json!(2048));
        assert_eq!(result["instance"]["server_file"], json!("paper.jar"));
        // 落盘用的是 camelCase 的 key（实例文件搬过来就能用，反过来也一样）
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        for key in [
            "\"manualCommand\"",
            "\"runtimeEnvId\"",
            "\"serverFile\"",
            "\"maxMemory\"",
            "\"customJvmArgs\"",
        ] {
            assert!(raw.contains(key), "文件里应写着 {key}: {raw}");
        }

        // 内存 0 = 不传 -Xmx，与 null 一样是「清掉」
        let cleared = update(&temp, &id, json!({ "max_memory": 0 })).unwrap();
        assert!(cleared["instance"]["max_memory"].is_null());

        let cleared = update(
            &temp,
            &id,
            json!({
                "runtime_env_id": null,
                "server_file": "   ",
                "custom_jvm_args": null,
                "manual_command": null
            }),
        )
        .unwrap();
        assert!(cleared["instance"]["runtime_env_id"].is_null());
        assert!(cleared["instance"]["server_file"].is_null());
        assert!(cleared["instance"]["custom_jvm_args"].is_null());
        // 开关清掉 → 回到按字段推断：命令还在、表单字段没了 = 手动模式
        assert_eq!(cleared["instance"]["manual_command"], json!(true));
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
        // 只按去空白后的字符串比，不做大小写折叠
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
            (json!({ "startup_command": 42 }), "必须是字符串"),
            (
                json!({ "startup_command": "x".repeat(STARTUP_COMMAND_MAX_CHARS + 1) }),
                "启动命令过长",
            ),
            (json!({ "line_ending": "\r" }), "line_ending 只能是"),
            (json!({ "line_ending": " " }), "line_ending 只能是"),
            (json!({ "compat_mode": "yes" }), "布尔值"),
            (json!({ "path": "/etc" }), "层级过浅"),
            (json!({ "nope": 1 }), "不认识的字段"),
            (json!({ "stop_command": 42 }), "必须是字符串"),
            (
                json!({ "stop_command": "x".repeat(STOP_COMMAND_MAX_CHARS + 1) }),
                "停止命令过长",
            ),
            // 服务端类型那一套（`runtime`）没有对应物：现在传过来属于
            // 「不认识的字段」，而不是被静默忽略 —— 免得前端还按老字段发补丁
            (json!({ "runtime": "java" }), "不认识的字段"),
            // 表单那几个字段是**认识的**，但值要合法
            (json!({ "manual_command": "yes" }), "布尔值"),
            (json!({ "max_memory": "4G" }), "必须是整数"),
            (json!({ "max_memory": -1 }), "必须是整数"),
            (
                json!({ "max_memory": MAX_MEMORY_MB_LIMIT + 1 }),
                "最大内存过大",
            ),
            (json!({ "server_file": "mods/server.jar" }), "不能带路径"),
            (json!({ "server_file": ".." }), "不合法"),
            (json!({ "runtime_env_id": 42 }), "必须是字符串"),
            (json!({ "custom_jvm_args": 42 }), "必须是字符串"),
            (
                json!({ "custom_jvm_args": "x".repeat(CUSTOM_JVM_ARGS_MAX_CHARS + 1) }),
                "自定义 JVM 参数过长",
            ),
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
                "startupCommand": "java -jar server.jar",
                "compatMode": true
            }))
            .unwrap();
        let id = id_of(&created);

        let result = update(
            &temp,
            &id,
            json!({ "startup_command": "java -Xmx4G -jar server.jar nogui" }),
        )
        .unwrap();
        assert_eq!(
            result["instance"]["startup_command"],
            json!("java -Xmx4G -jar server.jar nogui")
        );
        // 其它字段原封不动
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
                "startupCommand": "java -jar server.jar",
                "compatMode": true
            }))
            .unwrap();
        let id = id_of(&created);

        // 清空启动命令（空串与 null 等价）+ 关掉兼容模式
        let result = update(
            &temp,
            &id,
            json!({ "startup_command": "   ", "compat_mode": false }),
        )
        .unwrap();
        assert_eq!(result["changed"], json!(true));
        assert!(result["instance"]["startup_command"].is_null());
        assert_eq!(result["instance"]["compat_mode"], json!(false));

        // 清掉之后 lint 要提醒。这个实例是「只写了启动命令」建出来的（模式靠推断），
        // 命令一清就回到**表单模式**，于是提醒的是表单缺的那两项。
        // （设置页里走的是另一条路：开关是显式存的，关了表单就一直提醒没写命令。）
        assert!(
            result["lint"]
                .as_array()
                .unwrap()
                .iter()
                .any(|w| w.as_str().unwrap().contains("还没选运行环境")),
            "{}",
            result["lint"]
        );

        // 落盘的文件里也不该再有这些 key（默认值就是省字段）
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(!raw.contains("startupCommand"), "{raw}");
        assert!(!raw.contains("compatMode"), "{raw}");
    }

    /// 客户端（app 的 `InstanceApi.update`）是把寻址用的 `id` 一起合进补丁发上来的，
    /// 这里把「前端实际发出来的那个形状」整个钉住 —— 它一度被报成「不认识的字段」，
    /// 导致实例设置完全存不下去。
    #[test]
    fn update_accepts_the_client_shaped_patch_including_id() {
        let temp = TempData::new("update-client-shape");
        let id = id_of(&create(&temp, "服"));

        let result = update(
            &temp,
            &id,
            json!({
                "id": id, // ← 寻址参数混在补丁里，必须被忽略而不是报错
                "name": "新名字",
                "startup_command": "java -jar server.jar",
                "stop_command": "^C",
                "compat_mode": true,
                "auto_restart_on_exit": false,
                "line_ending": "\r\n",
            }),
        )
        .unwrap();

        assert_eq!(result["changed"], json!(true));
        assert_eq!(result["instance"]["id"], json!(id), "id 不该被改掉");
        assert_eq!(result["instance"]["name"], json!("新名字"));
        assert_eq!(result["instance"]["stop_command"], json!("^C"));
        // 换行符里全是空白字符，一度被 trim 掉而永远改不了
        assert_eq!(result["instance"]["line_ending"], json!("\r\n"));

        // 只带 id 的补丁 = 没有任何改动：不报错、不落盘
        let untouched = update(&temp, &id, json!({ "id": id })).unwrap();
        assert_eq!(untouched["changed"], json!(false));
        assert_eq!(untouched["instance"]["name"], json!("新名字"));
    }

    /// 停止命令可写可清：清掉之后线上一律回**生效值**（默认的 `stop`）。
    #[test]
    fn update_accepts_and_clears_stop_command() {
        let temp = TempData::new("update-stop-command");
        let id = id_of(&create(&temp, "服"));

        // 没配过时线上回的是生效默认值，而不是 null —— 前端不用自己拼默认
        let bare = update(&temp, &id, json!({})).unwrap();
        assert_eq!(
            bare["instance"]["stop_command"],
            json!(model::DEFAULT_STOP_COMMAND)
        );

        let set = update(&temp, &id, json!({ "stop_command": "  ^C  " })).unwrap();
        assert_eq!(set["changed"], json!(true));
        assert_eq!(
            set["instance"]["stop_command"],
            json!("^C"),
            "首尾空白应去掉"
        );
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(raw.contains("\"stopCommand\""), "落盘是 camelCase: {raw}");

        // 清掉（空串与 null 等价）→ 回到默认值，且不再落盘
        let cleared = update(&temp, &id, json!({ "stop_command": "   " })).unwrap();
        assert_eq!(cleared["changed"], json!(true));
        assert_eq!(
            cleared["instance"]["stop_command"],
            json!(model::DEFAULT_STOP_COMMAND)
        );
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        assert!(!raw.contains("stopCommand"), "默认值不该落盘: {raw}");
    }

    /// UPnP 三字段：可写可清、非法值被挡（协议白名单、端口范围），
    /// 默认值不落盘、线上显式给生效值。
    #[test]
    fn update_round_trips_upnp_fields_and_rejects_bad_values() {
        let temp = TempData::new("update-upnp");
        let id = id_of(&create(&temp, "服"));

        // 没配过时线上显式给默认值：关闭 / tcp / 端口 null
        let bare = update(&temp, &id, json!({})).unwrap();
        assert_eq!(bare["instance"]["upnp_enabled"], json!(false));
        assert_eq!(bare["instance"]["upnp_protocol"], json!("tcp"));
        assert!(bare["instance"]["upnp_external_port"].is_null());

        // 打开 + udp + 自定义外网端口（前端发的 snake_case）
        let set = update(
            &temp,
            &id,
            json!({
                "upnp_enabled": true,
                "upnp_protocol": "UDP",
                "upnp_external_port": 25570
            }),
        )
        .unwrap();
        assert_eq!(set["changed"], json!(true));
        assert_eq!(set["instance"]["upnp_enabled"], json!(true));
        assert_eq!(
            set["instance"]["upnp_protocol"],
            json!("udp"),
            "大小写应统一成小写"
        );
        assert_eq!(set["instance"]["upnp_external_port"], json!(25570));
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        for key in [
            "\"upnpEnabled\"",
            "\"upnpProtocol\"",
            "\"upnpExternalPort\"",
        ] {
            assert!(raw.contains(key), "落盘是 camelCase，缺少 {key}: {raw}");
        }

        // 非法值（协议白名单、端口 1-65535）：报错，且不碰已有值
        for bad in [
            json!({ "upnp_protocol": "sctp" }),
            json!({ "upnp_protocol": null }),
            json!({ "upnp_external_port": 0 }),
            json!({ "upnp_external_port": 70000 }),
            json!({ "upnp_external_port": "25565" }),
            json!({ "upnp_enabled": "yes" }),
        ] {
            let err = update(&temp, &id, bad.clone()).unwrap_err();
            assert_eq!(err.code, "invalid_params", "补丁 {bad} 应被拒绝");
        }
        let got = temp.1.get(&id).unwrap();
        assert_eq!(got["instance"]["upnp_protocol"], json!("udp"));
        assert_eq!(got["instance"]["upnp_external_port"], json!(25570));

        // 端口 null = 回到「用服务端端口」（协议不动）
        let cleared = update(&temp, &id, json!({ "upnp_external_port": null })).unwrap();
        assert!(cleared["instance"]["upnp_external_port"].is_null());
        assert_eq!(cleared["instance"]["upnp_protocol"], json!("udp"));

        // 关掉 + 协议回默认 → 三个 key 都从文件里消失
        let off = update(
            &temp,
            &id,
            json!({ "upnp_enabled": false, "upnp_protocol": "tcp" }),
        )
        .unwrap();
        assert_eq!(off["changed"], json!(true));
        assert_eq!(off["instance"]["upnp_enabled"], json!(false));
        assert_eq!(off["instance"]["upnp_protocol"], json!("tcp"));
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        for gone in ["upnpEnabled", "upnpProtocol", "upnpExternalPort"] {
            assert!(!raw.contains(gone), "默认值不该落盘，{gone}: {raw}");
        }
    }

    /// STUN 三字段：可写可清、非法值被挡，默认值不落盘、线上显式给。
    #[test]
    fn update_round_trips_stun_fields_and_rejects_bad_values() {
        let temp = TempData::new("update-stun");
        let id = id_of(&create(&temp, "服"));

        // 没配过时线上显式给默认值：关闭 / 无 PROXY / 端口 null
        let bare = update(&temp, &id, json!({})).unwrap();
        assert_eq!(bare["instance"]["stun_enabled"], json!(false));
        assert_eq!(bare["instance"]["stun_proxy_protocol"], json!(false));
        assert!(bare["instance"]["stun_target_port"].is_null());

        // 打开 + PROXY + 自定义目标端口（前端发的 snake_case）
        let set = update(
            &temp,
            &id,
            json!({
                "stun_enabled": true,
                "stun_proxy_protocol": true,
                "stun_target_port": 25570
            }),
        )
        .unwrap();
        assert_eq!(set["changed"], json!(true));
        assert_eq!(set["instance"]["stun_enabled"], json!(true));
        assert_eq!(set["instance"]["stun_proxy_protocol"], json!(true));
        assert_eq!(set["instance"]["stun_target_port"], json!(25570));
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        for key in [
            "\"stunEnabled\"",
            "\"stunProxyProtocol\"",
            "\"stunTargetPort\"",
        ] {
            assert!(raw.contains(key), "落盘是 camelCase，缺少 {key}: {raw}");
        }

        // 非法值（端口 1-65535、布尔类型）：报错，且不碰已有值
        for bad in [
            json!({ "stun_target_port": 0 }),
            json!({ "stun_target_port": 70000 }),
            json!({ "stun_target_port": "25565" }),
            json!({ "stun_enabled": "yes" }),
            json!({ "stun_proxy_protocol": 1 }),
        ] {
            let err = update(&temp, &id, bad.clone()).unwrap_err();
            assert_eq!(err.code, "invalid_params", "补丁 {bad} 应被拒绝");
        }
        let got = temp.1.get(&id).unwrap();
        assert_eq!(got["instance"]["stun_target_port"], json!(25570));
        assert_eq!(got["instance"]["stun_enabled"], json!(true));

        // 端口 null = 回到「跟随服务端端口」（其它不动）
        let cleared = update(&temp, &id, json!({ "stun_target_port": null })).unwrap();
        assert!(cleared["instance"]["stun_target_port"].is_null());
        assert_eq!(cleared["instance"]["stun_proxy_protocol"], json!(true));

        // 全部关掉 → 三个 key 都从文件里消失
        let off = update(
            &temp,
            &id,
            json!({ "stun_enabled": false, "stun_proxy_protocol": false }),
        )
        .unwrap();
        assert_eq!(off["changed"], json!(true));
        let raw = std::fs::read_to_string(temp.config_file(&id)).unwrap();
        for gone in ["stunEnabled", "stunProxyProtocol", "stunTargetPort"] {
            assert!(!raw.contains(gone), "默认值不该落盘，{gone}: {raw}");
        }
    }

    // ── 玩家名单 ──

    #[test]
    fn players_lists_read_from_the_instance_dir() {
        let temp = TempData::new("players-list");
        let id = id_of(&create(&temp, "服"));
        let dir = temp.instance_dir(&id);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("whitelist.json"),
            r#"[{"name":"Steve","uuid":"u1"}]"#,
        )
        .unwrap();
        std::fs::write(dir.join("white-list.txt"), "TxtOnly\n").unwrap();
        std::fs::write(dir.join("ops.txt"), "Alex\n").unwrap();

        let whitelist = temp.1.players_list(&id, &players::WHITELIST).unwrap();
        assert_eq!(whitelist["entries"][0]["name"], json!("Steve"));
        assert_eq!(whitelist["names"], json!(["steve"]), "打标签用的小写名字");

        // 没有 JSON 的名单直接吃纯文本
        let ops = temp.1.players_list(&id, &players::OPS).unwrap();
        assert_eq!(ops["entries"][0]["name"], json!("Alex"));
        assert_eq!(ops["entries"][0]["uuid"], json!(""));

        // 文件都没有 → 空名单，不是错误
        let bans = temp.1.players_list(&id, &players::BANS).unwrap();
        assert_eq!(bans["entries"], json!([]));
    }

    #[test]
    fn players_list_rejects_unknown_instance() {
        let temp = TempData::new("players-missing");
        let error = temp
            .1
            .players_list("nope", &players::WHITELIST)
            .unwrap_err();
        assert_eq!(error.code, "instance_not_found");
    }

    #[test]
    fn online_players_are_empty_without_a_running_process() {
        let temp = TempData::new("players-offline");
        let id = id_of(&create(&temp, "服"));

        let online = temp.1.online_players(&id).unwrap();
        assert_eq!(online["players"], json!([]));
        assert_eq!(online["count"], json!(0));

        // 写命令同理：没在跑就报 instance_not_running（前端据此走禁用态）
        let error = temp.1.console_write(&id, "list\n").unwrap_err();
        assert_eq!(error.code, "instance_not_running");

        let error = temp.1.online_players("nope").unwrap_err();
        assert_eq!(error.code, "instance_not_found");
    }
}
