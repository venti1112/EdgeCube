//! 模组 / 插件目录模块：Modrinth 上的搜索、版本列表、下载计划，以及实例里
//! 已装文件的列表 / 更新检查 / 启停 / 删除。
//!
//! # 为什么网络在 daemon
//!
//! 与 [`mcserver`](super::mcserver) 同一条理由：搜索、版本列表、更新检查都要打
//! Modrinth。放在前端意味着**每个客户端各打一遍**（还各自撞 300 次/分钟的限流），
//! 而客户端所在网络不一定通。放 daemon 就是「一处出网、一处缓存」。
//!
//! # 它自己不下载
//!
//! 本模块只回答「下什么、放到哪、校验值是什么」，真正下文件交给
//! [`download`](super::download) 模块（全局队列 + 断点续传 + 校验），
//! 编排交给 [`task`](super::task)：
//!
//! ```text
//! mods.plan（解析地址 + 目标目录）→ mods.download（落盘 + 清理被替换的旧版本）
//! ```
//!
//! 前端只发一次 `task.submit("mods-install", …)`。
//!
//! # 三个决策
//!
//! 1. **落到哪个目录按项目类型定**（`mod` → `mods/`、`plugin` → `plugins/`），
//!    不让用户选：选错了（插件丢进 `mods/`）服务端只会静默不加载，最难查。
//! 2. **「启用 / 禁用」是改名**（`X.jar` ↔ `X.jar.disabled`），不搬家。
//! 3. **更新检查按「上游最新」比，不筛游戏版本**（除非调用方给 `game_version`）：
//!    实例元数据里没记它跑的是哪个 MC 版本，硬猜不如让用户按需筛。
//!
//! # 方法
//!
//! | 方法 | 参数 | 说明 |
//! | --- | --- | --- |
//! | `mods.sources` | — | 源 / 项目类型 / 加载器 / 排序表（前端零硬编码） |
//! | `mods.tags` | `project_type?` | 可选的游戏版本（上游）+ 该类型可筛的加载器 |
//! | `mods.search` | `project_type`、`query?`、`loader?`、`game_version?`、`sort?`、`offset?`、`limit?` | 搜索 / 浏览 |
//! | `mods.project` | `project_id`、`source?` | 项目详情（刷新用） |
//! | `mods.versions` | `project_id`、`loader?`、`game_version?` | 项目的版本列表 |
//! | `mods.installed` | `instance_id` | 已装的模组与插件（含 jar 内元数据） |
//! | `mods.check_updates` | `instance_id`、`project_type?`、`loader?`、`game_version?` | 按 sha1 批量反查上游最新版 |
//! | `mods.set_enabled` | `instance_id`、`project_type`、`file_name`、`enabled` | 启用 / 禁用（改名） |
//! | `mods.remove` | `instance_id`、`project_type`、`file_name` | 删除一个已装文件 |
//! | `mods.plan` | `instance_id`、`project_id`、`project_type`、`version_id?`、`loader?`、`game_version?` | 解析下载地址与目标路径 |
//!
//! 工作流 `mods-install`：`mods.plan` → `mods.download`。
//!
//! # 错误码（前端按码分支）
//!
//! `mods_type_not_found`、`mods_source_not_found`、`mods_not_found`（这个 jar / 项目没有）、
//! `mods_version_not_found`、`mods_loader_unsupported`、`mods_no_file`（上游没给可下载文件）、
//! `mods_target_exists`（重名，不覆盖）、`mods_io_error`、`mods_not_a_file`、
//! `mods_instance_not_found`、`mods_upstream_error`（可重试）、
//! `mods_parse_error`（上游改接口了，得升级 daemon）、`mods_unavailable`。
//!
//! # 上游改接口了怎么办
//!
//! 解析都在 `api/modrinth.rs` 的纯函数里，测试拿**真实抓下来的响应体**钉住。

pub mod api;
pub mod installed;
pub mod model;

use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};

use self::api::{FetchError, modrinth};
use crate::error::{Error, Result, RpcError, RpcResult};
use crate::module::CallCtx;
use crate::module::builtin::download::{self, InternalRequest, Owner};
use crate::module::builtin::instance;
use crate::module::builtin::task::flows::{
    self, FlowStepInfo, FlowTemplate, StepSpec, TIMEOUT_UNLIMITED,
};
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration};
use crate::state::AppState;
use crate::util::cache::Cache;

// ---------------------------------------------------------------------------
// 错误码
// ---------------------------------------------------------------------------

const CODE_TYPE_NOT_FOUND: &str = "mods_type_not_found";
const CODE_SOURCE_NOT_FOUND: &str = "mods_source_not_found";
const CODE_NOT_FOUND: &str = "mods_not_found";
const CODE_VERSION_NOT_FOUND: &str = "mods_version_not_found";
const CODE_LOADER_UNSUPPORTED: &str = "mods_loader_unsupported";
const CODE_NO_FILE: &str = "mods_no_file";
const CODE_TARGET_EXISTS: &str = "mods_target_exists";
const CODE_IO_ERROR: &str = "mods_io_error";
const CODE_INSTANCE_NOT_FOUND: &str = "mods_instance_not_found";
const CODE_UPSTREAM_ERROR: &str = "mods_upstream_error";
const CODE_PARSE_ERROR: &str = "mods_parse_error";
const CODE_UNAVAILABLE: &str = "mods_unavailable";

/// 已装列表变了（装 / 删 / 启用 / 禁用）。
///
/// 前端订阅它来回刷列表 —— 否则「另一个客户端装了个模组」在本机要等用户手动刷新
/// 才看得见。
const TOPIC_CHANGED: &str = "mods.changed";

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// `[modules.config.mods]`
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ModsConfig {
    /// 搜索 / 版本列表的缓存时长（秒）。0 = 不缓存。clamp 到 [0, 86400]。
    pub cache_ttl_secs: u64,
    /// 游戏版本清单的缓存时长（秒）。它变得很慢，所以默认给得长。clamp 到 [0, 604800]。
    pub tags_cache_ttl_secs: u64,
    /// 单次上游请求的超时（秒），至少 1。
    pub request_timeout_secs: u64,
    /// 搜索不传 `limit` 时的条数。clamp 到 [1, 100]。
    pub search_default_limit: u64,
    /// 搜索 `limit` 的上限。clamp 到 [1, 100]。
    pub search_max_limit: u64,
    /// 每个目录（mods / plugins）最多列多少个文件。clamp 到 [1, 100000]。
    pub scan_max_files: usize,
    /// 读 jar 元数据时单个 zip 条目的字节上限。clamp 到 [1024, 16777216]。
    pub meta_max_entry_bytes: u64,
    /// `.phar` 的整文件上限（`.phar` 必须整读进内存才能定位 tar 段）。
    /// clamp 到 [1048576, 1073741824]。
    pub phar_max_bytes: u64,
    /// 更新检查一次提交给上游多少个哈希。clamp 到 [1, 1000]。
    pub hash_batch: usize,
    /// 一次更新检查最多算多少个文件的哈希。clamp 到 [1, 5000]。
    pub update_max_files: usize,
}

impl Default for ModsConfig {
    fn default() -> Self {
        Self {
            cache_ttl_secs: 300,
            tags_cache_ttl_secs: 3600,
            request_timeout_secs: 20,
            search_default_limit: 20,
            search_max_limit: 50,
            scan_max_files: 2_000,
            meta_max_entry_bytes: 256 * 1024,
            phar_max_bytes: 64 * 1024 * 1024,
            hash_batch: modrinth::HASH_BATCH,
            update_max_files: 200,
        }
    }
}

/// 生效的配置（数值都已 clamp）。
struct Limits {
    search_default_limit: u64,
    search_max_limit: u64,
    hash_batch: usize,
    update_max_files: usize,
}

// ---------------------------------------------------------------------------
// 模块状态
// ---------------------------------------------------------------------------

/// 建好的运行环境。`start()` 里定下来之后不再变。
struct Ready {
    http: reqwest::Client,
    limits: Limits,
    /// 搜索结果：key = 全部查询参数拼起来。
    searches: Cache<model::Page>,
    /// 版本列表：key = `项目id|加载器|游戏版本`。
    versions: Cache<Vec<model::VersionEntry>>,
    /// 游戏版本清单（上游 `/tag/game_version` 的 release 部分）。
    tags: Cache<Vec<model::GameVersion>>,
    /// 元数据缓存与扫描上限（读 jar 用）。
    meta: Arc<installed::MetaCache>,
    /// SHA1 缓存（「配图标」与「检查更新」共用同一批哈希，别算两遍）。
    hashes: Arc<installed::HashCache>,
    scan: installed::Limits,
}

#[derive(Default)]
struct ModsState {
    ready: OnceLock<Ready>,
}

impl ModsState {
    fn ready(&self) -> RpcResult<&Ready> {
        self.ready
            .get()
            .ok_or_else(|| RpcError::new(CODE_UNAVAILABLE, "模组目录尚未就绪"))
    }
}

// ---------------------------------------------------------------------------
// 上游结果 → 稳定错误码
// ---------------------------------------------------------------------------

fn fetch_error(err: FetchError) -> RpcError {
    match err {
        // 「上游说没有」与「我们这一侧的校验没过」对前端是同一件事：回上一页重选
        FetchError::NotFound(message) => RpcError::new(CODE_NOT_FOUND, message),
        FetchError::Upstream(message) => RpcError::new(CODE_UPSTREAM_ERROR, message),
        FetchError::Parse(message) => RpcError::new(CODE_PARSE_ERROR, message),
    }
}

fn unknown_type(id: &str) -> RpcError {
    RpcError::new(
        CODE_TYPE_NOT_FOUND,
        format!(
            "不认识的项目类型 `{id}`；可选：{}",
            model::project_type_ids().join(", ")
        ),
    )
}

fn unknown_source(id: &str) -> RpcError {
    RpcError::new(
        CODE_SOURCE_NOT_FOUND,
        format!(
            "不认识的下载源 `{id}`；可选：{}",
            model::source_ids().join(", ")
        ),
    )
}

/// 去空白；空白串当作「没给」。
fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

/// 校验要拼进上游 URL 的标识符。
fn check_id(id: &str, field: &str) -> RpcResult<()> {
    modrinth::check_id(id, field).map_err(|message| RpcError::new(CODE_NOT_FOUND, message))
}

// ---------------------------------------------------------------------------
// 取实例目录
// ---------------------------------------------------------------------------

/// 实例 id → 实例工作目录。
///
/// 读的是 `[modules.config.instance]` 那一节而不是 instance 模块的运行态，
/// 所以 instance 被 `modules.disabled` 关掉时也照样算得对。
fn instance_root(app: &AppState, instance_id: &str) -> RpcResult<PathBuf> {
    let instance_id = instance_id.trim();
    let data_dir = instance::resolve_data_dir(app.config.modules.section("instance"));
    instance::resolve_instance_root(&data_dir, instance_id)
        .map_err(|message| RpcError::new(CODE_INSTANCE_NOT_FOUND, message))
}

/// 把「项目类型」校验成已知取值。
fn project_type_of(raw: &str) -> RpcResult<&'static model::ProjectType> {
    let trimmed = raw.trim();
    model::find_project_type(trimmed).ok_or_else(|| unknown_type(trimmed))
}

/// 校验「加载器属于这个项目类型」。
///
/// 上游自己不会拦这种组合（`categories:fabric` 加 `project_type:plugin` 只会
/// 返回空列表），提前拦住能给一句说得清的话。
fn check_loader(project_type: &model::ProjectType, loader: Option<&str>) -> RpcResult<()> {
    let Some(loader) = loader else {
        return Ok(());
    };
    if model::loader_supported(project_type.id, loader) {
        return Ok(());
    }
    Err(RpcError::new(
        CODE_LOADER_UNSUPPORTED,
        format!(
            "`{}` 不支持加载器 `{loader}`；可选：{}",
            project_type.id,
            project_type.loaders.join(", ")
        ),
    ))
}

// ---------------------------------------------------------------------------
// 取数据（带缓存）
// ---------------------------------------------------------------------------

/// 游戏版本清单（只要正式版）。
///
/// 上游给了 900 多条（含快照 / beta / alpha）。对一个服务端管理器来说快照是噪音
/// —— 模组基本不支持快照 —— 所以只留 `release`（100 条上下）。
async fn game_versions(
    ready: &Ready,
) -> std::result::Result<Arc<Vec<model::GameVersion>>, FetchError> {
    let key = "game_versions";
    if let Some(hit) = ready.tags.get(key) {
        return Ok(hit);
    }
    let value = api::get_value(
        &ready.http,
        &format!("{}/tag/game_version", modrinth::API_BASE),
    )
    .await?;
    let versions = parse_game_versions(&value)?;
    let versions = Arc::new(versions);
    ready.tags.put(key, Arc::clone(&versions));
    Ok(versions)
}

/// 解析 `GET /tag/game_version`：**全部都留**，按上游给的顺序。
///
/// 上游就是「新的在前」（实测：`26.4-snapshot-2`, `26.4-snapshot-1`, `26.3`, …），
/// 这里直接用这个顺序 —— 把正式版挑到前面、其余排后面并带上类型副标题是
/// **选项菜单**的事。所以这里既不排序也不过滤：
/// **把快照滤掉，用户就选不了快照版本了**。
pub fn parse_game_versions(
    value: &Value,
) -> std::result::Result<Vec<model::GameVersion>, FetchError> {
    let items = value
        .as_array()
        .ok_or_else(|| FetchError::Parse("游戏版本清单不是数组".to_string()))?;

    Ok(items
        .iter()
        .filter_map(|item| {
            let version = item.get("version").and_then(Value::as_str)?.to_string();
            let version_type = item
                .get("version_type")
                .and_then(Value::as_str)
                .unwrap_or("release")
                .to_string();
            Some(model::GameVersion {
                version,
                version_type,
            })
        })
        .collect())
}

/// 搜索（带缓存）。
#[allow(clippy::too_many_arguments)]
async fn search_cached(
    ready: &Ready,
    source: &'static str,
    query: &str,
    project_type: &str,
    loader: Option<&str>,
    game_version: Option<&str>,
    sort: &str,
    offset: u64,
    limit: u64,
) -> std::result::Result<Arc<model::Page>, FetchError> {
    let key = format!(
        "search|{source}|{query}|{project_type}|{loader:?}|{game_version:?}|{sort}|{offset}|{limit}"
    );
    if let Some(hit) = ready.searches.get(&key) {
        return Ok(hit);
    }
    let page = Arc::new(
        modrinth::search(
            &ready.http,
            source,
            query,
            project_type,
            loader,
            game_version,
            sort,
            offset,
            limit,
        )
        .await?,
    );
    ready.searches.put(key, Arc::clone(&page));
    Ok(page)
}

/// 版本列表（带缓存）。
async fn versions_cached(
    ready: &Ready,
    project_id: &str,
    loader: Option<&str>,
    game_version: Option<&str>,
) -> std::result::Result<Arc<Vec<model::VersionEntry>>, FetchError> {
    let key = format!("versions|{project_id}|{loader:?}|{game_version:?}");
    if let Some(hit) = ready.versions.get(&key) {
        return Ok(hit);
    }
    let list = Arc::new(modrinth::versions(&ready.http, project_id, loader, game_version).await?);
    ready.versions.put(key, Arc::clone(&list));
    Ok(list)
}

// ---------------------------------------------------------------------------
// 方法
// ---------------------------------------------------------------------------

/// `mods.sources` —— 源 / 项目类型 / 加载器 / 排序表。
///
/// 前端据此渲染全部筛选器，**零硬编码**：加一个源、加一个加载器都只改 daemon。
fn sources() -> RpcResult<Value> {
    Ok(json!({
        "sources": model::SOURCES,
        "project_types": model::PROJECT_TYPES,
        "loaders": model::LOADERS,
        "sorts": model::SORTS,
        // 前端要用它判断「哪些文件算模组」以及「禁用之后叫什么名字」
        "file_exts": model::FILE_EXTS,
        "disabled_suffix": model::DISABLED_SUFFIX,
    }))
}

/// `mods.tags`
async fn tags(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let project_type = match clean(ctx.optional::<String>("project_type")?) {
        Some(raw) => project_type_of(&raw)?,
        // 不指定类型时给模组的加载器（最常见的用法）
        None => &model::PROJECT_TYPES[0],
    };

    let versions = game_versions(ready).await.map_err(fetch_error)?;
    let loaders: Vec<Value> = project_type
        .loaders
        .iter()
        .filter_map(|id| model::find_loader(id))
        .map(|loader| json!({ "id": loader.id, "name": loader.name }))
        .collect();

    Ok(json!({
        "project_type": project_type.id,
        "game_versions": versions.as_ref(),
        "loaders": loaders,
    }))
}

/// `mods.search`
async fn search(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;

    let source_id = clean(ctx.optional::<String>("source")?).unwrap_or_else(|| "modrinth".into());
    let source =
        model::find_source(source_id.trim()).ok_or_else(|| unknown_source(source_id.trim()))?;

    let project_type = project_type_of(&ctx.param::<String>("project_type")?)?;
    let query = clean(ctx.optional::<String>("query")?).unwrap_or_default();

    let loader = clean(ctx.optional::<String>("loader")?);
    check_loader(project_type, loader.as_deref())?;
    if let Some(loader) = loader.as_deref() {
        check_id(loader, "loader")?;
    }

    let game_version = clean(ctx.optional::<String>("game_version")?);
    if let Some(game_version) = game_version.as_deref() {
        check_id(game_version, "game_version")?;
    }

    // 有搜索词时按相关度，纯浏览时按下载量 —— 空查询下的「相关度」没有意义
    let default_sort = if query.is_empty() {
        "downloads"
    } else {
        "relevance"
    };
    let sort_id = clean(ctx.optional::<String>("sort")?).unwrap_or_else(|| default_sort.into());
    let sort = model::find_sort(sort_id.trim())
        .ok_or_else(|| RpcError::new(CODE_NOT_FOUND, format!("不认识的排序方式 `{sort_id}`")))?;
    if !source.sorts.contains(&sort.id) {
        return Err(RpcError::new(
            CODE_NOT_FOUND,
            format!("`{}` 不支持按 `{}` 排序", source.name, sort.name),
        ));
    }

    let offset = ctx.optional::<u64>("offset")?.unwrap_or(0);
    let limit = ctx
        .optional::<u64>("limit")?
        .unwrap_or(ready.limits.search_default_limit)
        // 至少给 1 条；上限防「一次拉一万条」把上游和内存都拖垮
        .clamp(1, ready.limits.search_max_limit);

    let page = search_cached(
        ready,
        source.id,
        &query,
        project_type.id,
        loader.as_deref(),
        game_version.as_deref(),
        sort.id,
        offset,
        limit,
    )
    .await
    .map_err(fetch_error)?;

    Ok(json!({
        "source": source.id,
        "source_name": source.name,
        "query": query,
        "project_type": project_type.id,
        "loader": loader,
        "game_version": game_version,
        "sort": sort.id,
        "offset": page.offset,
        "limit": page.limit,
        "total": page.total,
        "has_more": page.has_more(),
        "hits": page.hits,
    }))
}

/// `mods.project` —— 项目详情。
async fn project(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let project_id = ctx.param::<String>("project_id")?.trim().to_string();
    check_id(&project_id, "project_id")?;

    let source_id = clean(ctx.optional::<String>("source")?).unwrap_or_else(|| "modrinth".into());
    let source =
        model::find_source(source_id.trim()).ok_or_else(|| unknown_source(source_id.trim()))?;

    let value = api::get_value(
        &ready.http,
        &format!("{}/project/{project_id}", modrinth::API_BASE),
    )
    .await
    .map_err(fetch_error)?;
    let hit = modrinth::parse_project(&value, source.id).map_err(fetch_error)?;

    Ok(json!({ "project": hit }))
}

/// `mods.versions` —— 项目的版本列表。
async fn versions(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let project_id = ctx.param::<String>("project_id")?.trim().to_string();
    check_id(&project_id, "project_id")?;

    let loader = clean(ctx.optional::<String>("loader")?);
    if let Some(loader) = loader.as_deref() {
        check_id(loader, "loader")?;
    }
    let game_version = clean(ctx.optional::<String>("game_version")?);
    if let Some(game_version) = game_version.as_deref() {
        check_id(game_version, "game_version")?;
    }

    let list = versions_cached(
        ready,
        &project_id,
        loader.as_deref(),
        game_version.as_deref(),
    )
    .await
    .map_err(fetch_error)?;

    Ok(json!({
        "project_id": project_id,
        "loader": loader,
        "game_version": game_version,
        "versions": list.as_ref(),
    }))
}

/// `mods.installed` —— 已装的模组与插件。
async fn list_installed(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    let root = instance_root(&ctx.app, &instance_id)?;

    let limits = ready.scan;
    let cache = Arc::clone(&ready.meta);
    // 读目录 + 开 zip 都是阻塞 IO，丢给阻塞池
    let dirs = tokio::task::spawn_blocking(move || installed::scan(&root, &limits, &cache))
        .await
        .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("扫描实例目录失败：{e}")))?;

    // 这个实例是不是 PocketMine —— 插件那一栏据此认 `.jar` 还是 `.phar`，
    // 界面上的标签也要跟着换（「插件下载」vs「Poggit 插件」）。
    // **判断在 daemon**：V2 的实例元数据里没有 runtime 字段，
    // 从启动命令推属于「读磁盘的事」。
    let data_dir = instance::resolve_data_dir(ctx.app.config.modules.section("instance"));
    let pmmp = instance::is_pocketmine(&data_dir, &instance_id);

    Ok(json!({
        "instance_id": instance_id,
        "pmmp": pmmp,
        "dirs": dirs_payload(&dirs),
    }))
}

/// 把扫描结果转成线上形状。
fn dirs_payload(dirs: &[installed::DirListing]) -> Vec<Value> {
    dirs.iter()
        .map(|listing| {
            json!({
                "project_type": listing.project_type,
                "dir": listing.dir,
                "exists": listing.exists,
                "count": listing.files.len(),
                "files": listing.files,
            })
        })
        .collect()
}

/// `mods.check_updates` —— 按 sha1 批量反查上游最新版本。
///
/// 只查**启用中**的文件：被禁用的那些服务端根本不加载，它们有没有更新无所谓。
async fn check_updates(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    let root = instance_root(&ctx.app, &instance_id)?;

    // 只想查某一类时传它；不传就两类都查
    let only = match clean(ctx.optional::<String>("project_type")?) {
        Some(raw) => Some(project_type_of(&raw)?.id),
        None => None,
    };
    let loader = clean(ctx.optional::<String>("loader")?);
    if let Some(loader) = loader.as_deref() {
        check_id(loader, "loader")?;
    }
    let game_version = clean(ctx.optional::<String>("game_version")?);
    if let Some(game_version) = game_version.as_deref() {
        check_id(game_version, "game_version")?;
    }

    // ── 扫目录 + 算 sha1（阻塞池）──
    let scan_limits = ready.scan;
    let cache = Arc::clone(&ready.meta);
    let hash_cache = Arc::clone(&ready.hashes);
    let max_files = ready.limits.update_max_files;
    let scan_root = root.clone();
    let scanned = tokio::task::spawn_blocking(move || {
        let dirs = installed::scan(&scan_root, &scan_limits, &cache);
        collect_hashes(&scan_root, dirs, only, max_files, &hash_cache, true)
    })
    .await
    .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("扫描实例目录失败：{e}")))?;

    // ── 批量问上游 ──
    let hashes = scanned.hashes();
    let mut found: std::collections::HashMap<String, model::VersionEntry> =
        std::collections::HashMap::new();
    for chunk in hashes.chunks(ready.limits.hash_batch.max(1)) {
        let batch = modrinth::latest_for_hashes(
            &ready.http,
            chunk,
            loader.as_deref(),
            game_version.as_deref(),
        )
        .await
        .map_err(fetch_error)?;
        found.extend(batch);
    }

    let checks: Vec<model::UpdateCheck> = scanned
        .files
        .iter()
        .map(|file| {
            let latest = file.sha1.as_ref().and_then(|hash| found.get(hash)).cloned();
            // 「上游认不认识这个文件」：认得的会回一个版本对象
            let known = latest.is_some();
            // 「有没有更新」：回来的那个版本里**不含我们手上这个 sha1**
            // （当前文件就是最新版时上游照样会把它回给我们，所以只能这么判）
            let has_update = latest
                .as_ref()
                .map(|version| {
                    !version
                        .files
                        .iter()
                        .any(|candidate| candidate.sha1.as_deref() == file.sha1.as_deref())
                })
                .unwrap_or(false);
            model::UpdateCheck {
                file_name: file.file_name.clone(),
                sha1: file.sha1.clone(),
                known,
                has_update,
                latest,
            }
        })
        .collect();

    Ok(json!({
        "instance_id": instance_id,
        "loader": loader,
        "game_version": game_version,
        "checked": checks.len(),
        // 超过 `update_max_files` 时只查了前面这些，前端要如实告诉用户
        "truncated": scanned.truncated,
        "updates": checks,
    }))
}

/// `mods.match_projects` —— 把已装文件按 SHA1 对回上游项目（**配图标用**）。
///
/// 进列表页就做这件事：算 SHA1 → 反查项目 → 拿 `icon_url`，图标显示在每个
/// 条目的左侧（拿不到就退回「按加载器上色」的方块）。
///
/// **与「检查更新」是两个接口**，别合并：这个要的是「这个哈希属于哪个项目」（准），
/// 那个要的是「这个项目现在最新是哪个版本」（新）。V2 这里靠
/// [`installed::HashCache`] 共享同一份 SHA1，只算一遍。
async fn match_projects(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    let root = instance_root(&ctx.app, &instance_id)?;

    let only = match clean(ctx.optional::<String>("project_type")?) {
        Some(raw) => Some(project_type_of(&raw)?.id),
        None => None,
    };

    let scan_limits = ready.scan;
    let cache = Arc::clone(&ready.meta);
    let hash_cache = Arc::clone(&ready.hashes);
    let max_files = ready.limits.update_max_files;
    let scan_root = root.clone();
    let scanned = tokio::task::spawn_blocking(move || {
        let dirs = installed::scan(&scan_root, &scan_limits, &cache);
        // 禁用过的也要配图标 —— 它们在列表里照样显示
        collect_hashes(&scan_root, dirs, only, max_files, &hash_cache, false)
    })
    .await
    .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("扫描实例目录失败：{e}")))?;

    // ── 哈希 → 版本（拿到 project_id）──
    let hashes = scanned.hashes();
    let mut versions: std::collections::HashMap<String, model::VersionEntry> =
        std::collections::HashMap::new();
    for chunk in hashes.chunks(ready.limits.hash_batch.max(1)) {
        versions.extend(
            modrinth::versions_for_hashes(&ready.http, chunk)
                .await
                .map_err(fetch_error)?,
        );
    }

    // ── 项目 id → 项目摘要（图标在这里）──
    let mut project_ids: Vec<String> = versions
        .values()
        .map(|version| version.project_id.clone())
        .filter(|id| !id.is_empty())
        .collect();
    project_ids.sort();
    project_ids.dedup();

    let mut projects: std::collections::HashMap<String, model::ProjectRef> =
        std::collections::HashMap::new();
    for chunk in project_ids.chunks(ready.limits.hash_batch.max(1)) {
        projects.extend(
            modrinth::projects(&ready.http, chunk)
                .await
                .map_err(fetch_error)?,
        );
    }

    // ── 组装：每个已装文件一条 ──
    let matches: Vec<model::Match> = scanned
        .files
        .iter()
        .map(|file| {
            let version = file.sha1.as_ref().and_then(|hash| versions.get(hash));
            let project = version
                .and_then(|version| projects.get(&version.project_id))
                .cloned();
            model::Match {
                file_name: file.file_name.clone(),
                sha1: file.sha1.clone(),
                known: version.is_some(),
                project,
            }
        })
        .collect();

    Ok(json!({
        "instance_id": instance_id,
        "matched": matches.len(),
        "truncated": scanned.truncated,
        "matches": matches,
    }))
}

/// 扫描结果里「要拿去算哈希的东西」。
///
/// 只带文件名与算好的哈希：算哈希不需要元数据，而元数据在 [`installed::scan`]
/// 那一步已经顺带读过了（有缓存，不额外开 zip）。
struct HashTarget {
    file_name: String,
    /// 算出来的 sha1。读不动那个文件时是 `None`（列表里照样要显示它）。
    sha1: Option<String>,
}

/// 一次更新检查的输入与「被截断了吗」。
struct Scanned {
    files: Vec<HashTarget>,
    truncated: bool,
}

impl Scanned {
    /// 要提交给上游的哈希（只挑算出来的那些）。
    fn hashes(&self) -> Vec<String> {
        self.files
            .iter()
            .filter_map(|file| file.sha1.clone())
            .collect()
    }
}

/// 从扫描结果里挑出要查的文件，并**算好 sha1**（同步，调用方保证在阻塞池里）。
///
/// 算哈希要整读一遍文件，是这里最贵的一步 —— 所以只在用户**主动点「检查更新」**
/// 时做，`mods.installed` 那条路完全不碰它。哈希走 [`installed::HashCache`]，
/// 所以「配图标」那次算过的不会再算一遍。
fn collect_hashes(
    root: &std::path::Path,
    dirs: Vec<installed::DirListing>,
    only: Option<&'static str>,
    max_files: usize,
    hashes: &installed::HashCache,
    enabled_only: bool,
) -> Scanned {
    let mut files: Vec<HashTarget> = Vec::new();
    let mut truncated = false;

    'outer: for dir in &dirs {
        if only.is_some_and(|only| only != dir.project_type) {
            continue;
        }
        for file in &dir.files {
            // 检查更新只关心启用中的（被禁用的服务端根本不加载）；
            // **配图标两类都要**（禁用过的 `.jar.disabled` 也算），
            // 否则禁用过的模组左侧会掉成占位图标。
            if enabled_only && !file.enabled {
                continue;
            }
            if files.len() >= max_files.max(1) {
                truncated = true;
                break 'outer;
            }
            let path = dir_path(root, dir, file);
            files.push(HashTarget {
                file_name: file.file_name.clone(),
                sha1: hashes.sha1_of(&path),
            });
        }
    }

    Scanned { files, truncated }
}

/// 还原一个已装文件的**绝对路径**。
///
/// `installed::DirListing` 里的 `dir` 是相对实例根的（`"mods"` / `"plugins"`），
/// 那是给前端看的形状；要落盘操作就得把它并回实例根。抽成函数是为了
/// **只有一处**知道「列表里的名字怎么变回路径」—— 别处再拼一次就会漂。
fn dir_path(
    root: &std::path::Path,
    dir: &installed::DirListing,
    file: &model::Installed,
) -> PathBuf {
    root.join(dir.dir).join(&file.file_name)
}

/// `mods.set_enabled`
async fn set_enabled(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    let project_type = project_type_of(&ctx.param::<String>("project_type")?)?.id;
    let file_name: String = ctx.param("file_name")?;
    let enabled: bool = ctx.param("enabled")?;

    let root = instance_root(&ctx.app, &instance_id)?;
    let file_name = file_name.trim().to_string();

    let renamed_root = root.clone();
    let renamed = file_name.clone();
    let new_name = tokio::task::spawn_blocking(move || {
        installed::set_enabled(&renamed_root, project_type, &renamed, enabled)
    })
    .await
    .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("重命名任务失败：{e}")))??;

    // 改了名字，缓存里那条记录就没用了（虽然 mtime 变了也会失效，但省一条陈旧记录）
    ready.meta.forget(&root.join(&file_name));
    ready.meta.forget(&root.join(&new_name));

    publish_changed(
        &ctx.app,
        &instance_id,
        project_type,
        Some(&new_name),
        if enabled { "enabled" } else { "disabled" },
    );
    Ok(json!({
        "instance_id": instance_id,
        "project_type": project_type,
        "file_name": new_name,
        "enabled": enabled,
    }))
}

/// `mods.remove`
async fn remove(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    let project_type = project_type_of(&ctx.param::<String>("project_type")?)?.id;
    let file_name = ctx.param::<String>("file_name")?.trim().to_string();

    let root = instance_root(&ctx.app, &instance_id)?;
    let removed_root = root.clone();
    let removed_name = file_name.clone();
    tokio::task::spawn_blocking(move || {
        installed::remove(&removed_root, project_type, &removed_name)
    })
    .await
    .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("删除任务失败：{e}")))??;
    ready.meta.forget(&root.join(&file_name));

    publish_changed(
        &ctx.app,
        &instance_id,
        project_type,
        Some(&file_name),
        "removed",
    );
    Ok(json!({
        "instance_id": instance_id,
        "project_type": project_type,
        "file_name": file_name,
    }))
}

/// `mods.plan`
async fn plan(state: &ModsState, ctx: &CallCtx) -> RpcResult<Value> {
    plan_of(state, &ctx.app, PlanRequest::from_params(&ctx.params)?).await
}

/// 往总线上报一条「已装清单变了」。
///
/// 与 `instance` / `frp` 的做法一致：**事件里带完整事实**（哪个实例、哪一类、
/// 哪个文件、什么动作），前端据此决定刷新还是忽略。
fn publish_changed(
    app: &AppState,
    instance_id: &str,
    project_type: &str,
    file_name: Option<&str>,
    action: &str,
) {
    app.bus.publish_from(
        Some("mods"),
        TOPIC_CHANGED,
        json!({
            "instance_id": instance_id,
            "project_type": project_type,
            "file_name": file_name,
            "action": action,
            "ts": crate::util::now_ms(),
        }),
    );
}

// ---------------------------------------------------------------------------
// 下载计划
// ---------------------------------------------------------------------------

/// 解析下载计划要的全部输入。
///
/// 抽成结构体（而不是直接读 `CallCtx`）是为了**给工作流步骤复用** ——
/// 任务步骤里没有 `CallCtx`，参数来自 `StepDef.config`。
#[derive(Debug)]
struct PlanRequest {
    instance_id: String,
    project_id: String,
    project_type: &'static str,
    version_id: Option<String>,
    loader: Option<String>,
    game_version: Option<String>,
}

impl PlanRequest {
    fn from_params(params: &Value) -> RpcResult<Self> {
        let pick = |key: &str| {
            params
                .get(key)
                .and_then(Value::as_str)
                .map(|text| text.trim().to_string())
                .filter(|text| !text.is_empty())
        };
        let required = |key: &str| {
            pick(key).ok_or_else(|| RpcError::invalid_params(format!("参数 `{key}` 不能为空")))
        };

        Ok(Self {
            instance_id: required("instance_id")?,
            project_id: required("project_id")?,
            project_type: project_type_of(&required("project_type")?)?.id,
            version_id: pick("version_id"),
            loader: pick("loader"),
            game_version: pick("game_version"),
        })
    }
}

/// 解析一次下载计划。
async fn plan_of(state: &ModsState, app: &AppState, req: PlanRequest) -> RpcResult<Value> {
    let ready = state.ready()?;
    let project_type =
        model::find_project_type(req.project_type).ok_or_else(|| unknown_type(req.project_type))?;

    check_id(&req.project_id, "project_id")?;
    check_loader(project_type, req.loader.as_deref())?;
    if let Some(loader) = req.loader.as_deref() {
        check_id(loader, "loader")?;
    }
    if let Some(game_version) = req.game_version.as_deref() {
        check_id(game_version, "game_version")?;
    }

    let root = instance_root(app, &req.instance_id)?;

    // ── 选版本 ──
    let version = match req.version_id.as_deref() {
        Some(version_id) => {
            check_id(version_id, "version_id")?;
            // 指定了版本就用它：从项目的版本列表里找（顺便校验这个 id 真的属于这个项目，
            // 否则前端传错 id 会下到一个完全不相干的文件）
            let list = versions_cached(ready, &req.project_id, None, None)
                .await
                .map_err(fetch_error)?;
            list.iter()
                .find(|candidate| candidate.id == version_id)
                .cloned()
                .ok_or_else(|| {
                    RpcError::new(
                        CODE_VERSION_NOT_FOUND,
                        format!("项目 `{}` 里没有版本 `{version_id}`", req.project_id),
                    )
                })?
        }
        None => {
            let list = versions_cached(
                ready,
                &req.project_id,
                req.loader.as_deref(),
                req.game_version.as_deref(),
            )
            .await
            .map_err(fetch_error)?;
            // 优先正式版：服务端上跑 beta/alpha 是用户明确的选择，不该是默认
            list.iter()
                .find(|candidate| candidate.is_release() && candidate.primary_file().is_some())
                .or_else(|| {
                    list.iter()
                        .find(|candidate| candidate.primary_file().is_some())
                })
                .cloned()
                .ok_or_else(|| {
                    RpcError::new(
                        CODE_VERSION_NOT_FOUND,
                        format!(
                            "`{}` 没有可下载的版本{}",
                            req.project_id,
                            describe_filter(req.loader.as_deref(), req.game_version.as_deref())
                        ),
                    )
                })?
        }
    };

    let file = version
        .primary_file()
        .ok_or_else(|| {
            RpcError::new(
                CODE_NO_FILE,
                format!("版本 `{}` 没有可下载的文件", version.version_number),
            )
        })?
        .clone();

    // ── 目标路径 ──
    let dir = project_type.dir;
    let relative_path = format!("{dir}/{}", file.filename);
    let absolute = root.join(dir).join(&file.filename);

    // **不覆盖**：队列对已存在的目标文件是**静默覆盖**（gofsh-dl 的语义），
    // 所以必须在提交前自己拦。同名的情形多半是「同一个版本下过两次」。
    if absolute.exists() {
        return Err(RpcError::new(
            CODE_TARGET_EXISTS,
            format!("`{relative_path}` 已经存在，先删掉它或换一个版本"),
        ));
    }

    // ── 有没有旧版本要替换 ──
    //
    // 这一步要**开每一个 jar 读元数据**，是这个方法里最贵的一段 —— 所以丢进
    // 阻塞池，并且复用模块自己的元数据缓存（用户通常刚看过已装列表，缓存是热的）。
    let replaces = {
        let scan_root = root.clone();
        let cache = Arc::clone(&ready.meta);
        let limits = ready.scan;
        let incoming = file.filename.clone();
        let project_id = req.project_id.clone();
        let dir = dir.to_string();
        tokio::task::spawn_blocking(move || {
            find_replaced(&scan_root, &dir, &incoming, &project_id, &cache, limits)
        })
        .await
        .map_err(|e| RpcError::new(CODE_IO_ERROR, format!("查找旧版本失败：{e}")))?
    };

    Ok(json!({
        "source": "modrinth",
        "project_id": req.project_id,
        "project_type": project_type.id,
        "project_type_name": project_type.name,
        "version_id": version.id,
        "version_number": version.version_number,
        "version_name": version.name,
        "version_kind": version.kind,
        "game_versions": version.game_versions,
        "loaders": version.loaders,
        "dependencies": version.dependencies,
        "url": file.url,
        "file_name": file.filename,
        "file_size": file.size,
        // `algorithm` 的取值**直接就是 download.add 的参数名**，前端不用做映射表
        "checksum": match &file.sha1 {
            Some(value) => json!({ "algorithm": "sha1", "value": value }),
            None => Value::Null,
        },
        "instance_id": req.instance_id,
        "dir": dir,
        "relative_path": relative_path,
        "replaces": replaces,
    }))
}

/// 挑出「装了新版本之后该删掉的旧文件」。
///
/// # 这是启发式，说清楚边界
///
/// 上游不提供「这个 jar 属于哪个项目」的反查（我们手上只有文件名）。所以按
/// 两条线索匹配，任意一条命中就算：
///
/// 1. **jar 内的 `meta.id` 等于项目 slug** —— Fabric / Bukkit 的元数据里就是这样；
/// 2. **文件名等于要下的那个文件名**（同一个文件重复下）。
///
/// 认不出来时**什么都不删**：宁可留下一个重复文件让用户自己处理，也不要凭猜
/// 删掉一个无关的模组。
fn find_replaced(
    root: &std::path::Path,
    dir: &str,
    incoming: &str,
    project_id: &str,
    cache: &installed::MetaCache,
    limits: installed::Limits,
) -> Vec<Value> {
    let listing = installed::scan(root, &limits, cache)
        .into_iter()
        .find(|listing| listing.dir == dir);

    let Some(listing) = listing else {
        return Vec::new();
    };

    let slug = project_id.to_ascii_lowercase();
    listing
        .files
        .iter()
        .filter(|file| {
            if file.file_name == incoming {
                return true;
            }
            file.meta
                .as_ref()
                .and_then(|meta| meta.id.as_deref())
                .map(|id| id.to_ascii_lowercase() == slug)
                .unwrap_or(false)
        })
        .map(|file| {
            json!({
                "file_name": file.file_name,
                "base_name": file.base_name,
                "enabled": file.enabled,
                "meta": file.meta,
            })
        })
        .collect()
}

/// 拼一句「筛选条件是什么」给人看。
fn describe_filter(loader: Option<&str>, game_version: Option<&str>) -> String {
    match (loader, game_version) {
        (None, None) => String::new(),
        (loader, game_version) => {
            let mut parts = Vec::new();
            if let Some(loader) = loader {
                parts.push(format!("加载器 `{loader}`"));
            }
            if let Some(game_version) = game_version {
                parts.push(format!("游戏版本 `{game_version}`"));
            }
            format!("（筛选中：{}）", parts.join(" / "))
        }
    }
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct ModsModule {
    state: Arc<ModsState>,
}

impl Default for ModsModule {
    fn default() -> Self {
        Self::new()
    }
}

impl ModsModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(ModsState::default()),
        }
    }
}

#[async_trait]
impl Module for ModsModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("mods", "模组与插件", env!("CARGO_PKG_VERSION")).description(
            "Modrinth 上的模组 / 插件搜索、版本列表与下载计划，以及实例里已装文件的列表、更新检查、启停与删除。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        // 表都是纯常量，不需要运行环境
        reg.method(
            "mods.sources",
            "可用的下载源、项目类型、加载器与排序方式（前端据此渲染筛选器）",
            |_ctx: CallCtx| async move { sources() },
        );
        {
            let state = self.state.clone();
            reg.method(
                "mods.tags",
                "可选的游戏版本（上游）与该项目类型可筛的加载器",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { tags(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.search",
                "搜索或浏览模组 / 插件（支持加载器与游戏版本筛选、排序、分页）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { search(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.project",
                "一个项目的详情（图标、描述、支持的加载器与游戏版本）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { project(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.versions",
                "一个项目的版本列表（可按加载器与游戏版本筛）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { versions(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.installed",
                "实例里已装的模组与插件（含从 jar 内读到的名字 / 版本 / 加载器）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { list_installed(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.check_updates",
                "按已装文件的 sha1 批量反查上游最新版本（只查启用中的）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { check_updates(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.match_projects",
                "按已装文件的 sha1 对回上游项目（列表左侧的图标靠它）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { match_projects(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.set_enabled",
                "启用或禁用一个已装文件（改名为 .disabled）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { set_enabled(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.remove",
                "删除一个已装的模组或插件",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { remove(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mods.plan",
                "把「项目 + 版本」解析成下载地址、目标目录与校验值",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { plan(&state, &ctx).await }
                },
            );
        }

        reg.topic(TOPIC_CHANGED, "某个实例的已装模组 / 插件清单变了");

        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: ModsConfig = env.config()?;
        let http = api::build_client(config.request_timeout_secs)
            .map_err(|message| Error::module("mods", message))?;

        let limits = Limits {
            search_default_limit: config.search_default_limit.clamp(1, 100),
            search_max_limit: config.search_max_limit.clamp(1, 100),
            hash_batch: config.hash_batch.clamp(1, 1000),
            update_max_files: config.update_max_files.clamp(1, 5000),
        };
        let scan = installed::Limits {
            max_files: config.scan_max_files.clamp(1, 100_000),
            max_entry_bytes: config.meta_max_entry_bytes.clamp(1024, 16 * 1024 * 1024),
            max_phar_bytes: config.phar_max_bytes.clamp(1024 * 1024, 1024 * 1024 * 1024),
        };

        tracing::info!(
            cache_ttl_secs = config.cache_ttl_secs,
            sources = model::SOURCES.len(),
            project_types = model::PROJECT_TYPES.len(),
            "模组与插件目录已就绪"
        );

        let _ = self.state.ready.set(Ready {
            http,
            limits,
            searches: Cache::new(config.cache_ttl_secs.min(86_400)),
            versions: Cache::new(config.cache_ttl_secs.min(86_400)),
            tags: Cache::new(config.tags_cache_ttl_secs.min(604_800)),
            meta: Arc::new(installed::MetaCache::default()),
            hashes: Arc::new(installed::HashCache::default()),
            scan,
        });

        install::register(&self.state, &env.app);
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// 工作流（`mods-install`）
// ---------------------------------------------------------------------------

mod install {
    //! 「下载并安装一个模组 / 插件」工作流（`mods-install`）。
    //!
    //! 与服务端那条（`instance-provision`）同构，但只有两步、且**没有回滚**：
    //!
    //! ```text
    //! plan（解析地址 + 目标目录）→ download（落盘 + 清掉被替换的旧版本）
    //! ```
    //!
    //! 不需要回滚的理由：这条流程只在**已经存在的实例**里放一个文件，
    //! 不会创建任何东西。旧版本文件是**下载成功之后**才删的，所以下载失败时
    //! 用户的旧模组完好无损。
    //!
    //! 两个步骤而不是一个：解析要打上游（异步），塞不进 `FlowTemplate::build`
    //! （它是同步的、只做参数校验）。拆出来还有个好处 —— 解析失败时用户看到的
    //! 是「解析下载地址」这一步挂了，而不是莫名其妙的「安装失败」。

    use super::*;

    /// 工作流名（`task.submit` 的 `flow`）。
    pub(super) const FLOW: &str = "mods-install";

    const STEP_PLAN: &str = "mods.plan";
    const STEP_DOWNLOAD: &str = "mods.download";

    /// 步骤在 flow 里的**名字**。
    ///
    /// 与 `step_type` 是两回事：产出表按 `StepDef.name` 建（`StepEnv::output(..)`
    /// 用的键就是这个名字）。混用会得到「上一步没有产出」这种下游报错、
    /// 而上游明明成功了 —— runtime 那边实测踩过。
    const NAME_PLAN: &str = "plan";
    const NAME_DOWNLOAD: &str = "download";

    /// 把这条工作流挂到任务系统的注册表里。`start()` 里调。
    pub(super) fn register(state: &Arc<ModsState>, app: &AppState) {
        if !crate::module::builtin::task::enabled(app) {
            tracing::debug!("task 模块未启用，`{FLOW}` 工作流跳过注册");
            return;
        }

        let registry = flows::registry(app);
        registry.register_step_or_warn(STEP_PLAN, plan_step(state.clone()));
        registry.register_step_or_warn(STEP_DOWNLOAD, download_step(state.clone()));
        registry.register_flow_or_warn(FLOW, template());
    }

    /// 步骤「解析下载地址」：把「项目 + 版本」变成地址 / 文件名 / 目标目录。
    fn plan_step(state: Arc<ModsState>) -> StepSpec {
        StepSpec {
            title: "解析下载地址".into(),
            run: Arc::new(move |step, progress, env| {
                let state = state.clone();
                Box::pin(async move {
                    let config = step.config.clone().unwrap_or(Value::Null);
                    progress.report(json!({ "percent": null, "message": "正在解析下载地址" }));
                    // 步骤的约定是「错误是给人看的字符串」，所以这里把错误码前缀留着
                    // 一起带上（前端有 `stepErrorCode` 剥前缀）
                    let request = PlanRequest::from_params(&config)
                        .map_err(|e| format!("{}：{}", e.code, e.message))?;
                    plan_of(&state, &env.app, request)
                        .await
                        .map_err(|e| format!("{}：{}", e.code, e.message))
                })
            }),
            rollback: None,
        }
    }

    /// 步骤「下载」：把文件落进实例目录，然后清掉被替换的旧版本。
    fn download_step(state: Arc<ModsState>) -> StepSpec {
        StepSpec {
            title: "下载并安装".into(),
            run: Arc::new(move |step, progress, env| {
                let state = state.clone();
                Box::pin(async move {
                    let _ = step;
                    let plan = env
                        .output(NAME_PLAN)
                        .await
                        .ok_or("上一步（解析下载地址）没有产出下载计划")?;

                    let instance_id = str_field(&plan, "instance_id")?;
                    let project_type = str_field(&plan, "project_type")?;
                    let dir = str_field(&plan, "dir")?;
                    let file_name = str_field(&plan, "file_name")?;
                    let url = str_field(&plan, "url")?;
                    let checksum = checksum_of(&plan)?;

                    let ready = state
                        .ready()
                        .map_err(|e| format!("{}：{}", e.code, e.message))?;
                    let root = instance_root(&env.app, &instance_id)
                        .map_err(|e| format!("{}：{}", e.code, e.message))?;
                    let target_dir = root.join(&dir);

                    // 复用全局下载队列：`download::fetch` 负责报进度与协作取消，
                    // 落盘目录是我们算好的绝对路径（模块间调用没有用户输入穿过）
                    let queue = download::queue_of(&env.app)
                        .ok_or("下载队列尚未就绪（download 模块没起来）")?;
                    let path = download::fetch(
                        &queue,
                        &env.app,
                        InternalRequest {
                            dir: target_dir.clone(),
                            filename: file_name.clone(),
                            url,
                            checksum,
                            owner: Owner::Instance {
                                instance_id: instance_id.clone(),
                                // 目标子目录（mods / plugins），不是实例根
                                path: dir.clone(),
                            },
                        },
                        &env.cancel,
                        // 队列任务 id 不往元数据里写：归属与进度都走任务对象
                        |_task_id| {},
                        |frame| progress.report(frame),
                    )
                    .await?;

                    // ── 收尾：把被替换掉的旧版本文件删掉 ──
                    //
                    // **下载成功之后**才做：失败时旧模组必须还在（否则用户既没新版本
                    // 也没旧版本，服务端起不来）。
                    progress.report(json!({ "percent": null, "message": "正在清理旧版本" }));
                    let replaces = plan
                        .get("replaces")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default();

                    // 删文件是同步 IO，丢进阻塞池；一次收集再返回，避免逐条往返
                    let names: Vec<String> = replaces
                        .iter()
                        .filter_map(|old| old.get("file_name").and_then(Value::as_str))
                        .map(str::to_string)
                        // 别把刚下下来的这个删了（同名情形下上游给的依然是同一个名字）
                        .filter(|name| *name != file_name)
                        .collect();

                    let (removed, failed) = {
                        let clean_root = root.clone();
                        let clean_dir = target_dir.clone();
                        let clean_type = project_type.clone();
                        let cache = Arc::clone(&ready.meta);
                        tokio::task::spawn_blocking(move || {
                            let mut removed = Vec::new();
                            let mut failed = Vec::new();
                            for old_name in names {
                                match installed::remove(&clean_root, &clean_type, &old_name) {
                                    Ok(()) => {
                                        cache.forget(&clean_dir.join(&old_name));
                                        removed.push(old_name);
                                    }
                                    // 删不掉**不算失败**：新文件已经就位，用户能在列表里
                                    // 看到两个同名模组，也就能自己删一个。如实报告出来。
                                    Err(e) => failed.push(json!({
                                        "file_name": old_name,
                                        "message": e.message,
                                    })),
                                }
                            }
                            (removed, failed)
                        })
                        .await
                        .map_err(|e| format!("清理旧版本的任务失败：{e}"))?
                    };

                    publish_changed(
                        &env.app,
                        &instance_id,
                        &project_type,
                        Some(&file_name),
                        "installed",
                    );

                    Ok(json!({
                        "path": path.display().to_string(),
                        "instance_id": instance_id,
                        "project_type": project_type,
                        "dir": dir,
                        "file_name": file_name,
                        "removed": removed,
                        "remove_failed": failed,
                    }))
                })
            }),
            rollback: None,
        }
    }

    /// 工作流模板：展示用的步骤清单 + 参数 → [`FlowDef`]。
    ///
    /// `pub(super)` 是给同模块的测试用的 —— 那几条断言（参数校验、步骤清单与
    /// 声明一致）是这条流程唯一能被钉住的地方，不上线跑就该在单测里炸。
    pub(super) fn template() -> FlowTemplate {
        FlowTemplate {
            title: "下载并安装模组 / 插件".into(),
            steps: vec![
                FlowStepInfo {
                    name: NAME_PLAN.into(),
                    title: "解析下载地址".into(),
                    step_type: STEP_PLAN.into(),
                },
                FlowStepInfo {
                    name: NAME_DOWNLOAD.into(),
                    title: "下载并安装".into(),
                    step_type: STEP_DOWNLOAD.into(),
                },
            ],
            build: Arc::new(|params| {
                // 参数校验都在这里做完（同步、不碰网络）：坏参数不该拿到任务 id
                let request = PlanRequest::from_params(params)
                    .map_err(|e| format!("{}：{}", e.code, e.message))?;

                let mut plan_config = json!({
                    "instance_id": request.instance_id,
                    "project_id": request.project_id,
                    "project_type": request.project_type,
                });
                if let Some(version_id) = &request.version_id {
                    plan_config["version_id"] = json!(version_id);
                }
                if let Some(loader) = &request.loader {
                    plan_config["loader"] = json!(loader);
                }
                if let Some(game_version) = &request.game_version {
                    plan_config["game_version"] = json!(game_version);
                }

                let mut flow = szal::flow::FlowDef::new(FLOW, szal::flow::FlowMode::Sequential);
                flow.add_step(
                    szal::step::StepDef::new(NAME_PLAN)
                        .with_step_type(STEP_PLAN)
                        .with_config(plan_config)
                        // 解析要打上游，可能慢；默认 30 秒的超时对网络请求太紧
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                flow.add_step(
                    szal::step::StepDef::new(NAME_DOWNLOAD)
                        .with_step_type(STEP_DOWNLOAD)
                        // 下载大模组包 / 慢网络必须不限时，否则 30 秒就被判失败
                        .with_timeout(TIMEOUT_UNLIMITED),
                );
                Ok(flow)
            }),
        }
    }

    /// 从 plan 的产出里取一个非空字符串。
    fn str_field(plan: &Value, key: &str) -> std::result::Result<String, String> {
        plan.get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
            .ok_or_else(|| format!("下载计划里缺 `{key}`"))
    }

    /// 把计划里的校验值翻成下载队列要的 `(算法, 值)`。
    ///
    /// 认不出的算法**报错而不是静默跳过** —— 悄悄不校验比下载失败更糟。
    pub(super) fn checksum_of(
        plan: &Value,
    ) -> std::result::Result<Option<(&'static str, String)>, String> {
        let Some(checksum) = plan.get("checksum").filter(|value| !value.is_null()) else {
            return Ok(None);
        };
        let algorithm = checksum
            .get("algorithm")
            .and_then(Value::as_str)
            .ok_or("下载计划里的校验值缺 `algorithm`")?;
        let value = checksum
            .get("value")
            .and_then(Value::as_str)
            .ok_or("下载计划里的校验值缺 `value`")?
            .to_string();

        match algorithm {
            "sha1" => Ok(Some(("sha1", value))),
            "sha256" => Ok(Some(("sha256", value))),
            "md5" => Ok(Some(("md5", value))),
            other => Err(format!("不认识的校验算法 `{other}`")),
        }
    }
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sources_payload_lists_every_table() {
        let payload = sources().expect("类型表是纯常量，不该失败");
        assert_eq!(
            payload["sources"].as_array().unwrap().len(),
            model::SOURCES.len()
        );
        assert_eq!(
            payload["project_types"].as_array().unwrap().len(),
            model::PROJECT_TYPES.len()
        );
        assert_eq!(
            payload["loaders"].as_array().unwrap().len(),
            model::LOADERS.len()
        );
        assert_eq!(payload["file_exts"], json!(["jar", "phar"]));
        assert_eq!(payload["disabled_suffix"], json!(".disabled"));
    }

    #[test]
    fn game_versions_keep_every_type_in_upstream_order() {
        // 上游真实形状（实测）：version / version_type / date / major
        let value = json!([
            { "version": "26.4-snapshot-2", "version_type": "snapshot", "date": "2026-09-29T11:32:57Z", "major": false },
            { "version": "26.3", "version_type": "release", "date": "2026-09-15T11:23:02Z", "major": false },
            { "version": "26.4-pre1", "version_type": "beta", "date": "2026-09-20T00:00:00Z", "major": false },
            { "version": "1.21.8", "version_type": "release", "date": "2025-07-17T00:00:00Z", "major": false }
        ]);

        let versions = parse_game_versions(&value).expect("游戏版本清单应当能解析");
        // **不过滤**：快照 / 测试版都要留下 —— 菜单里要能选到它们
        let names: Vec<&str> = versions.iter().map(|v| v.version.as_str()).collect();
        assert_eq!(
            names,
            vec!["26.4-snapshot-2", "26.3", "26.4-pre1", "1.21.8"],
            "顺序就是上游给的顺序（这里不自己排）"
        );
        // 类型要跟着一起来：菜单里非正式版的副标题写的就是它
        assert_eq!(versions[0].version_type, "snapshot");
        assert_eq!(versions[1].version_type, "release");
        assert_eq!(versions[2].version_type, "beta");
    }

    /// 加载器表就是筛选器里能选到的东西 —— **按项目类型分成两张表**。
    /// 串了就会出现「插件下载里能筛 fabric」这种一眼就错的东西。
    #[test]
    fn loader_tables_never_mix() {
        let r#mod = model::find_project_type("mod").expect("应当有模组类型");
        let plugin = model::find_project_type("plugin").expect("应当有插件类型");

        assert_eq!(
            r#mod.loaders,
            vec!["fabric", "forge", "quilt", "neoforge"],
            "Modrinth 模组加载器表（顺序也要一样）"
        );
        assert_eq!(
            plugin.loaders,
            vec![
                "paper",
                "spigot",
                "bukkit",
                "bungeecord",
                "velocity",
                "waterfall",
                "folia",
                "purpur"
            ],
            "Modrinth 插件加载器表（含 waterfall）"
        );

        // 两张表绝不能有交集
        for id in plugin.loaders {
            assert!(
                !r#mod.loaders.contains(id),
                "插件表里不该出现模组加载器 `{id}`"
            );
        }
        // 表里引用的 id 必须在 LOADERS 表里存在（否则前端拿不到展示名）
        for entry in model::PROJECT_TYPES {
            for id in entry.loaders {
                assert!(
                    model::find_loader(id).is_some(),
                    "`{id}` 在 LOADERS 表里没有对应项"
                );
            }
        }
    }

    #[test]
    fn game_versions_reject_a_non_array() {
        let err = parse_game_versions(&json!({ "versions": [] })).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
    }

    #[test]
    fn loader_must_belong_to_the_project_type() {
        let plugin = model::find_project_type("plugin").unwrap();
        let r#mod = model::find_project_type("mod").unwrap();

        assert!(check_loader(plugin, Some("paper")).is_ok());
        assert!(check_loader(plugin, None).is_ok(), "不筛加载器也要放行");
        // 给插件筛 fabric 上游只会回空列表，不如提前说清楚
        let err = check_loader(plugin, Some("fabric")).unwrap_err();
        assert_eq!(err.code, CODE_LOADER_UNSUPPORTED);
        assert!(check_loader(r#mod, Some("fabric")).is_ok());
        assert!(check_loader(r#mod, Some("paper")).is_err());
    }

    #[test]
    fn plan_request_requires_the_three_essential_params() {
        let empty = json!({});
        assert!(PlanRequest::from_params(&empty).is_err());

        // 少 instance_id
        let no_instance = json!({ "project_id": "sodium", "project_type": "mod" });
        assert!(PlanRequest::from_params(&no_instance).is_err());

        // 空白串等于没给
        let blank = json!({ "instance_id": "  ", "project_id": "sodium", "project_type": "mod" });
        assert!(PlanRequest::from_params(&blank).is_err());

        // 项目类型不认识
        let bad_type =
            json!({ "instance_id": "i", "project_id": "sodium", "project_type": "shader" });
        let err = PlanRequest::from_params(&bad_type).unwrap_err();
        assert_eq!(err.code, CODE_TYPE_NOT_FOUND);
    }

    #[test]
    fn plan_request_normalizes_the_project_type() {
        let params = json!({
            "instance_id": " my-instance ",
            "project_id": " sodium ",
            "project_type": " plugin ",
            "version_id": "abc123",
        });
        let request = PlanRequest::from_params(&params).expect("应当能解析");
        assert_eq!(request.instance_id, "my-instance");
        assert_eq!(request.project_id, "sodium");
        assert_eq!(request.project_type, "plugin");
        assert_eq!(request.version_id.as_deref(), Some("abc123"));
        assert!(request.loader.is_none());
        // 可选参数留空时是 None，不是空串 —— 空串拼进 URL 会变成一个真筛选条件
        assert!(request.game_version.is_none());
    }

    #[test]
    fn checksum_translates_known_algorithms_and_rejects_others() {
        // 它在 `install` 子模块里（只有工作流用得到），所以这里带路径
        let plan = json!({ "checksum": { "algorithm": "sha1", "value": "abc" } });
        assert_eq!(
            install::checksum_of(&plan).unwrap(),
            Some(("sha1", "abc".into()))
        );

        // 上游没给校验值 → 不校验（不是错误）
        assert!(
            install::checksum_of(&json!({ "checksum": null }))
                .unwrap()
                .is_none()
        );
        assert!(install::checksum_of(&json!({})).unwrap().is_none());

        // 认不出的算法必须报错，不能静默放过
        let bad = json!({ "checksum": { "algorithm": "crc32", "value": "x" } });
        assert!(install::checksum_of(&bad).is_err());
    }

    #[test]
    fn flow_build_rejects_missing_params_before_a_task_exists() {
        let build = install::template().build;
        assert!(build(&json!({})).is_err());
        assert!(build(&json!({ "instance_id": "i", "project_id": "sodium" })).is_err());
    }

    #[test]
    fn flow_build_produces_two_steps_without_rollback() {
        let build = install::template().build;
        let flow = build(&json!({
            "instance_id": "i1",
            "project_id": "sodium",
            "project_type": "mod",
        }))
        .expect("参数齐全应当能构造流程");

        assert_eq!(flow.steps.len(), 2);
        assert_eq!(flow.steps[0].name, "plan");
        assert_eq!(flow.steps[0].step_type.as_deref(), Some("mods.plan"));
        assert_eq!(flow.steps[1].name, "download");
        assert_eq!(flow.steps[1].step_type.as_deref(), Some("mods.download"));
        // 这条流程不创建任何东西，所以没有回滚点
        assert!(!flow.rollback_on_failure);
        assert!(!flow.steps[0].rollbackable);
        assert!(!flow.steps[1].rollbackable);
    }

    #[test]
    fn flow_build_passes_optional_params_into_plan_config() {
        let build = install::template().build;
        let flow = build(&json!({
            "instance_id": "i1",
            "project_id": "sodium",
            "project_type": "mod",
        }))
        .unwrap();
        let config = flow.steps[0].config.clone().unwrap();
        assert_eq!(config["project_type"], json!("mod"));
        assert!(
            config.get("version_id").is_none(),
            "没给版本就不该造一个出来"
        );
        assert!(config.get("loader").is_none());
    }

    #[test]
    fn template_steps_match_the_declared_list() {
        let template = install::template();
        let flow = (template.build)(&json!({
            "instance_id": "i1",
            "project_id": "sodium",
            "project_type": "mod",
        }))
        .unwrap();

        // 声明的步骤清单与实际构造出来的必须一一对应（前端按声明的清单画进度）
        assert_eq!(template.steps.len(), flow.steps.len());
        for (declared, built) in template.steps.iter().zip(&flow.steps) {
            assert_eq!(declared.name, built.name);
            assert_eq!(
                Some(declared.step_type.as_str()),
                built.step_type.as_deref()
            );
        }
    }

    #[test]
    fn module_registers_eleven_methods_and_one_topic() {
        let module = ModsModule::new();
        let mut reg = Registration::new("mods");
        module.register(&mut reg).unwrap();

        let names: Vec<String> = reg.methods.iter().map(|m| m.name.clone()).collect();
        assert_eq!(
            names,
            vec![
                "mods.sources",
                "mods.tags",
                "mods.search",
                "mods.project",
                "mods.versions",
                "mods.installed",
                "mods.check_updates",
                "mods.match_projects",
                "mods.set_enabled",
                "mods.remove",
                "mods.plan",
            ]
        );
        let topics: Vec<String> = reg.topics.iter().map(|t| t.topic.clone()).collect();
        assert_eq!(topics, vec![TOPIC_CHANGED]);
    }

    /// 模板里那一节就是用户第一次跑会拿到的东西。
    ///
    /// `--check` 不过模块私有配置（那要等 `start()`），所以这一节的内容
    /// 没人在别处验过 —— 字段名写错就在这里炸。
    #[test]
    fn the_default_template_section_parses() {
        let config: crate::config::Config =
            toml::from_str(&crate::config::Config::template()).expect("模板必须能解析");
        let section = config
            .modules
            .section("mods")
            .expect("模板里应当有模组与插件那一节");

        let parsed =
            ModsConfig::deserialize(section.clone()).expect("模板里的模组与插件配置必须能反序列化");
        let default = ModsConfig::default();
        assert_eq!(parsed.cache_ttl_secs, default.cache_ttl_secs);
        assert_eq!(parsed.tags_cache_ttl_secs, default.tags_cache_ttl_secs);
        assert_eq!(parsed.request_timeout_secs, default.request_timeout_secs);
        assert_eq!(parsed.search_default_limit, default.search_default_limit);
        assert_eq!(parsed.search_max_limit, default.search_max_limit);
        assert_eq!(parsed.scan_max_files, default.scan_max_files);
        assert_eq!(parsed.meta_max_entry_bytes, default.meta_max_entry_bytes);
        assert_eq!(parsed.hash_batch, default.hash_batch);
        assert_eq!(parsed.update_max_files, default.update_max_files);
    }

    /// 配置节多写一个字段就必须报错（`deny_unknown_fields`），
    /// 否则「配错了但没人知道」会变成常态。
    #[test]
    fn unknown_config_fields_are_rejected() {
        let section: toml::Value = toml::from_str("typo_ttl = 5").unwrap();
        assert!(ModsConfig::deserialize(section).is_err());
    }

    #[test]
    fn sha1_matches_the_known_vector() {
        // 空文件的 sha1 是公开已知值，用来确认走的不是别的算法
        let dir = std::env::temp_dir().join("edgecube-mods-sha1-test");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("empty.bin");
        std::fs::write(&path, b"").unwrap();
        assert_eq!(
            installed::sha1_file(&path).as_deref(),
            Some("da39a3ee5e6b4b0d3255bfef95601890afd80709")
        );

        std::fs::write(&path, b"abc").unwrap();
        assert_eq!(
            installed::sha1_file(&path).as_deref(),
            Some("a9993e364706816aba3e25717850c26c9cd0d89d")
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn dir_path_rebuilds_an_absolute_path_from_the_listing() {
        let listing = installed::DirListing {
            project_type: "mod",
            dir: "mods",
            exists: true,
            files: Vec::new(),
        };
        let file = model::Installed {
            file_name: "sodium.jar".into(),
            base_name: "sodium.jar".into(),
            enabled: true,
            size: 1,
            modified_ms: 0,
            meta: None,
        };
        // 列表里的 `dir` 是相对实例根的 —— 算哈希必须并回实例根，
        // 拿它当绝对路径会变成「相对当前工作目录」，文件永远找不到
        assert_eq!(
            dir_path(std::path::Path::new("/srv/instances/a"), &listing, &file).to_string_lossy(),
            "/srv/instances/a/mods/sodium.jar"
        );
    }

    #[test]
    fn describe_filter_is_empty_when_nothing_is_filtered() {
        assert_eq!(describe_filter(None, None), "");
        assert!(describe_filter(Some("fabric"), None).contains("fabric"));
        assert!(describe_filter(None, Some("1.21.8")).contains("1.21.8"));
        assert!(describe_filter(Some("fabric"), Some("1.21.8")).contains(" / "));
    }
}
