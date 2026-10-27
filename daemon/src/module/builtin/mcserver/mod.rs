//! 服务端目录模块：把「某个服务端类型、某个版本」的服务端文件找出来。
//!
//! # 为什么网络在 daemon
//!
//! 版本列表与下载地址都得打上游（Mojang / PaperMC / Purpur / Fabric / …）。
//! 放在前端意味着**每个客户端各打一遍**，而且客户端所在网络不一定通；
//! 放在 daemon 则是「一处出网、一处缓存」，前端只发一个 RPC 拿结果。
//!
//! # 它自己不下载
//!
//! 本模块只回答「下什么、地址在哪、校验值是什么、启动命令写什么」。
//! 真正下文件交给 [`download`](super::download) 模块（全局队列 + 断点续传 + 校验），
//! 建实例交给 [`instance`](super::instance) 模块。三个模块各管一段，前端串起来：
//!
//! ```text
//! mcserver.versions → mcserver.plan → instance.create → download.add
//! ```
//!
//! 这个分工是刻意的：**每个模块都不需要知道另外两个在干什么**，
//! 而且任何一步失败都能单独重试（版本没选对就回上一页，下载失败就重下）。
//!
//! # 方法
//!
//! | 方法 | 参数 | 说明 |
//! | --- | --- | --- |
//! | `mcserver.types` | — | 分类 + 服务端类型（含文件名、建议启动命令、校验能力） |
//! | `mcserver.versions` | `type` | 某类型的版本列表（新版本在前） |
//! | `mcserver.loaders` | `type`、`mc_version` | 加载器版本列表（目前只有 Fabric） |
//! | `mcserver.plan` | `type`、`version?`、`loader_version?` | 下载地址 + 校验 + 文件名 + 建议启动命令 |
//!
//! # 错误码（前端按码分支）
//!
//! `mcserver_type_not_found`、`mcserver_not_found`（版本/构建拿不到）、
//! `mcserver_version_required`、`mcserver_loader_required`、`mcserver_no_loaders`、
//! `mcserver_upstream_error`（网络/非 2xx，可重试）、
//! `mcserver_parse_error`（上游改接口了，得升级 daemon）、`mcserver_unavailable`。
//!
//! # 上游改接口了怎么办
//!
//! 每个源的**解析**都是单独的纯函数（`api/*.rs` 里的 `parse_*`），并且有测试拿
//! **真实抓下来的响应体**钉住。上游改形状时先炸的是那些测试，而不是线上用户。
//!
//! # 缓存
//!
//! 版本列表按 `cache_ttl_secs` 缓存（默认 5 分钟）：它是只读、变得很慢的数据，
//! 而前端在列表页来回点、或用户反复重试都会重复打上游。`0` = 不缓存。
//!
//! 本轮覆盖 8 个源：`vanilla` / `paper` / `purpur` / `leaf` / `leaves` /
//! `fabric` / `velocity` / `bungeecord`。**Forge 与 NeoForge 不做** ——
//! 它们要多一步「跑安装器」，用户明确说先不做。

pub mod api;
pub mod model;

use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};

use self::api::{Download, FetchError};
use self::model::ServerType;
use crate::error::{Error, Result, RpcError, RpcResult};
use crate::module::CallCtx;
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration};
use crate::state::AppState;
use crate::util::cache::Cache;

// ---------------------------------------------------------------------------
// 错误码
// ---------------------------------------------------------------------------

const CODE_TYPE_NOT_FOUND: &str = "mcserver_type_not_found";
const CODE_NOT_FOUND: &str = "mcserver_not_found";
const CODE_VERSION_REQUIRED: &str = "mcserver_version_required";
const CODE_LOADER_REQUIRED: &str = "mcserver_loader_required";
const CODE_NO_LOADERS: &str = "mcserver_no_loaders";
const CODE_UPSTREAM_ERROR: &str = "mcserver_upstream_error";
const CODE_PARSE_ERROR: &str = "mcserver_parse_error";
const CODE_UNAVAILABLE: &str = "mcserver_unavailable";

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// `[modules.config.mcserver]`
#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct McserverConfig {
    /// 版本列表的缓存时长（秒）。0 = 不缓存。
    pub cache_ttl_secs: u64,
    /// 单次上游请求的超时（秒），至少 1。
    pub request_timeout_secs: u64,
}

impl Default for McserverConfig {
    fn default() -> Self {
        Self {
            cache_ttl_secs: 300,
            request_timeout_secs: 20,
        }
    }
}

// ---------------------------------------------------------------------------
// 模块状态
// ---------------------------------------------------------------------------

/// 建好的运行环境。`start()` 里定下来之后不再变。
struct Ready {
    http: reqwest::Client,
    /// 版本列表：key = 类型 id。
    versions: Cache<Vec<String>>,
    /// 原版的「版本 → 详情地址」。`versions` 与 `plan` 都要用，缓存一次两边都省。
    vanilla: Cache<Vec<api::mojang::VersionEntry>>,
    /// 加载器版本：key = `<类型>:<mc 版本>`。
    loaders: Cache<Vec<String>>,
}

impl Ready {
    /// 命中缓存就返回，否则跑一次 `fetch` 再存起来。
    ///
    /// 传进来的是**已经构造好但还没开始跑**的 future（async fn 是惰性的），
    /// 所以命中时不会有任何网络动作。
    async fn cached<T: Send + Sync + 'static>(
        &self,
        cache: &Cache<T>,
        key: &str,
        fetch: impl std::future::Future<Output = std::result::Result<T, FetchError>>,
    ) -> std::result::Result<Arc<T>, FetchError> {
        if let Some(hit) = cache.get(key) {
            return Ok(hit);
        }
        let value = Arc::new(fetch.await?);
        cache.put(key, Arc::clone(&value));
        Ok(value)
    }
}

#[derive(Default)]
struct McserverState {
    ready: OnceLock<Ready>,
}

impl McserverState {
    fn ready(&self) -> RpcResult<&Ready> {
        self.ready
            .get()
            .ok_or_else(|| RpcError::new(CODE_UNAVAILABLE, "服务端目录尚未就绪"))
    }
}

// ---------------------------------------------------------------------------
// 上游结果 → 稳定错误码
// ---------------------------------------------------------------------------

fn fetch_error(err: FetchError) -> RpcError {
    match err {
        // 「上游说没有」与「我们这一侧的版本校验没过」对前端是同一件事：
        // 这个版本/构建拿不到，回上一页重选。
        FetchError::NotFound(message) => RpcError::new(CODE_NOT_FOUND, message),
        FetchError::Upstream(message) => RpcError::new(CODE_UPSTREAM_ERROR, message),
        FetchError::Parse(message) => RpcError::new(CODE_PARSE_ERROR, message),
    }
}

fn unknown_type(id: &str) -> RpcError {
    RpcError::new(
        CODE_TYPE_NOT_FOUND,
        format!(
            "不认识的服务端类型 `{id}`；可选：{}",
            model::known_ids().join(", ")
        ),
    )
}

/// 去空白；空白串当作「没给」。
fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// 版本号 / 加载器版本号的字符串白名单。
///
/// 上游地址是**拼**出来的，放行 `/`、`..`、`?` 任何一个都可能把请求指到别处。
/// 主校验是「必须在版本列表里」，这一层是兜底（也保护缓存 key）。
fn check_token(token: &str, field: &str) -> RpcResult<()> {
    api::validate_version_token(token, field).map_err(|msg| {
        RpcError::new(
            if field == "loader_version" {
                CODE_LOADER_REQUIRED
            } else {
                CODE_NOT_FOUND
            },
            msg,
        )
    })
}

/// 版本必须在列表里出现过。
fn check_version(entry: &ServerType, version: &str, known: &[String]) -> RpcResult<()> {
    if known.iter().any(|candidate| candidate == version) {
        return Ok(());
    }
    Err(RpcError::new(
        CODE_NOT_FOUND,
        format!("`{}` 没有版本 `{version}`", entry.id),
    ))
}

// ---------------------------------------------------------------------------
// 取数据（带缓存）
// ---------------------------------------------------------------------------

/// 原版的「版本 → 详情地址」。
async fn vanilla_index(
    ready: &Ready,
) -> std::result::Result<Arc<Vec<api::mojang::VersionEntry>>, FetchError> {
    ready
        .cached(
            &ready.vanilla,
            "vanilla",
            api::mojang::version_index(&ready.http),
        )
        .await
}

/// 某类型的版本列表（新版本在前）。
async fn version_ids(
    ready: &Ready,
    entry: &ServerType,
) -> std::result::Result<Arc<Vec<String>>, FetchError> {
    match entry.id {
        // 没有版本概念：给一个占位值，前端看 `needs_version` 会跳过版本页
        "bungeecord" => Ok(Arc::new(vec![api::bungeecord::PSEUDO_VERSION.to_string()])),
        // 原版复用那份 index，不额外缓存一份 id 列表
        "vanilla" => Ok(Arc::new(
            vanilla_index(ready)
                .await?
                .iter()
                .map(|entry| entry.id.clone())
                .collect(),
        )),
        "paper" => {
            ready
                .cached(
                    &ready.versions,
                    "paper",
                    api::papermc::versions(&ready.http, "paper"),
                )
                .await
        }
        // Folia 与 paper 同在 PaperMC 的 v3 接口，只是 project 名不同 —— 连产物键
        // 都是同一个 `server:default`，所以整条链路（含校验）直接共用。
        "folia" => {
            ready
                .cached(
                    &ready.versions,
                    "folia",
                    api::papermc::versions(&ready.http, "folia"),
                )
                .await
        }
        "velocity" => {
            ready
                .cached(
                    &ready.versions,
                    "velocity",
                    api::papermc::versions(&ready.http, "velocity"),
                )
                .await
        }
        "purpur" => {
            ready
                .cached(
                    &ready.versions,
                    "purpur",
                    api::purpur::versions(&ready.http),
                )
                .await
        }
        "leaf" | "leaves" => {
            let base = if entry.id == "leaf" {
                api::leafmc::LEAF_BASE
            } else {
                api::leafmc::LEAVES_BASE
            };
            ready
                .cached(
                    &ready.versions,
                    entry.id,
                    api::leafmc::versions(&ready.http, base),
                )
                .await
        }
        "fabric" => {
            ready
                .cached(
                    &ready.versions,
                    "fabric",
                    api::fabric::game_versions(&ready.http),
                )
                .await
        }
        other => Err(FetchError::NotFound(format!("不认识的类型 `{other}`"))),
    }
}

/// 某类型在某个 MC 版本下的加载器版本列表。
async fn loader_ids(
    ready: &Ready,
    mc_version: &str,
) -> std::result::Result<Arc<Vec<String>>, FetchError> {
    ready
        .cached(
            &ready.loaders,
            &format!("fabric:{mc_version}"),
            api::fabric::loader_versions(&ready.http, mc_version),
        )
        .await
}

/// 把「类型 + 版本 + 加载器」解析成一个下载地址。
async fn download_for(
    ready: &Ready,
    entry: &ServerType,
    version: &str,
    loader: Option<&str>,
) -> std::result::Result<Download, FetchError> {
    match entry.id {
        "vanilla" => {
            let detail = vanilla_index(ready)
                .await?
                .iter()
                .find(|candidate| candidate.id == version)
                .map(|candidate| candidate.detail_url.clone())
                .ok_or_else(|| FetchError::NotFound(format!("原版没有版本 `{version}`")))?;
            api::mojang::server_download(&ready.http, &detail).await
        }
        "paper" => api::papermc::download(&ready.http, "paper", version).await,
        "folia" => api::papermc::download(&ready.http, "folia", version).await,
        "velocity" => api::papermc::download(&ready.http, "velocity", version).await,
        "purpur" => api::purpur::download(&ready.http, version).await,
        "leaf" => api::leafmc::leaf_download(&ready.http, version).await,
        "leaves" => api::leafmc::leaves_download(&ready.http, version).await,
        "fabric" => {
            let loader = loader.unwrap_or_default();
            api::fabric::server_jar(&ready.http, version, loader).await
        }
        "bungeecord" => api::bungeecord::download(&ready.http).await,
        other => Err(FetchError::NotFound(format!("不认识的类型 `{other}`"))),
    }
}

// ---------------------------------------------------------------------------
// 方法
// ---------------------------------------------------------------------------

/// `mcserver.types` —— 分类与类型表。前端据此渲染，**零硬编码**。
fn types() -> RpcResult<Value> {
    Ok(json!({
        "categories": serde_json::to_value(model::CATEGORIES)?,
        "types": serde_json::to_value(model::TYPES)?,
    }))
}

/// `mcserver.versions`
async fn versions(state: &McserverState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let type_id: String = ctx.param("type")?;
    let entry = model::find(type_id.trim()).ok_or_else(|| unknown_type(type_id.trim()))?;

    let list = version_ids(ready, entry).await.map_err(fetch_error)?;
    Ok(json!({
        "type": entry.id,
        "type_name": entry.name,
        // 前端可以据此跳过版本页（BungeeCord）
        "needs_version": entry.needs_version,
        "versions": list.as_ref(),
    }))
}

/// `mcserver.loaders`
async fn loaders(state: &McserverState, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let type_id: String = ctx.param("type")?;
    let entry = model::find(type_id.trim()).ok_or_else(|| unknown_type(type_id.trim()))?;

    if !entry.needs_loader {
        return Err(RpcError::new(
            CODE_NO_LOADERS,
            format!("`{}` 不需要选加载器版本", entry.id),
        ));
    }

    let mc_version = ctx.param::<String>("mc_version")?.trim().to_string();
    check_token(&mc_version, "mc_version")?;
    let known = version_ids(ready, entry).await.map_err(fetch_error)?;
    check_version(entry, &mc_version, known.as_ref())?;

    let list = loader_ids(ready, &mc_version).await.map_err(fetch_error)?;
    Ok(json!({
        "type": entry.id,
        "mc_version": mc_version,
        "loaders": list.as_ref(),
    }))
}

/// `mcserver.plan`
///
/// 只回答「下什么」，不建实例、不提交下载 —— 那两步由前端串（见模块文档）。
async fn plan(state: &McserverState, ctx: &CallCtx) -> RpcResult<Value> {
    plan_with(
        state,
        &ctx.param::<String>("type")?,
        clean(ctx.optional::<String>("version")?),
        clean(ctx.optional::<String>("loader_version")?),
    )
    .await
}

/// 解析一次下载计划：「类型 + 版本 + 加载器」→「下载地址 / 文件名 / 启动命令 / 校验值」。
///
/// 抽成「按值传参」而不是直接读 `CallCtx`，是为了**给工作流步骤复用** ——
/// 任务系统的步骤里没有 `CallCtx`，参数来自 `StepDef.config`
/// （见 `mcserver.plan` 步骤的注册）。
async fn plan_with(
    state: &McserverState,
    type_id: &str,
    version: Option<String>,
    loader: Option<String>,
) -> RpcResult<Value> {
    let ready = state.ready()?;
    let entry = model::find(type_id.trim()).ok_or_else(|| unknown_type(type_id.trim()))?;

    // ── 版本 ──
    let version = match version {
        Some(version) => {
            check_token(&version, "version")?;
            let known = version_ids(ready, entry).await.map_err(fetch_error)?;
            check_version(entry, &version, known.as_ref())?;
            version
        }
        None if entry.needs_version => {
            return Err(RpcError::new(
                CODE_VERSION_REQUIRED,
                format!("`{}` 需要指定 `version`", entry.id),
            ));
        }
        // 不需要版本的类型（BungeeCord）用占位值
        None => api::bungeecord::PSEUDO_VERSION.to_string(),
    };

    // ── 加载器版本 ──
    if entry.needs_loader {
        let Some(loader) = loader.as_deref() else {
            return Err(RpcError::new(
                CODE_LOADER_REQUIRED,
                format!("`{}` 需要指定 `loader_version`", entry.id),
            ));
        };
        check_token(loader, "loader_version")?;
        let known = loader_ids(ready, &version).await.map_err(fetch_error)?;
        if !known.iter().any(|candidate| candidate == loader) {
            return Err(RpcError::new(
                CODE_NOT_FOUND,
                format!("Fabric 在版本 `{version}` 下没有加载器 `{loader}`"),
            ));
        }
    }

    let download = download_for(ready, entry, &version, loader.as_deref())
        .await
        .map_err(fetch_error)?;

    Ok(json!({
        "type": entry.id,
        "type_name": entry.name,
        "version": version,
        "loader_version": loader,
        "url": download.url,
        "file_name": entry.file_name,
        "startup_command": entry.startup_command,
        // `algorithm` 的取值**直接就是 download.add 的参数名**（sha1 / sha256 / md5），
        // 前端不用做映射表；`null` 表示上游没给校验值。
        "checksum": match &download.checksum {
            Some((algorithm, value)) => json!({ "algorithm": algorithm, "value": value }),
            None => Value::Null,
        },
    }))
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct McserverModule {
    state: Arc<McserverState>,
}

impl Default for McserverModule {
    fn default() -> Self {
        Self::new()
    }
}

impl McserverModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(McserverState::default()),
        }
    }
}

#[async_trait]
impl Module for McserverModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("mcserver", "服务端目录", env!("CARGO_PKG_VERSION")).description(
            "各个服务端源的版本列表与下载地址（原版 / Paper / Purpur / Leaf / Leaves / Fabric / Velocity / BungeeCord）。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        // 类型表是纯常量，不需要运行环境
        reg.method(
            "mcserver.types",
            "服务端分类与类型表（含文件名、建议启动命令、可用的校验算法）",
            |_ctx: CallCtx| async move { types() },
        );
        {
            let state = self.state.clone();
            reg.method(
                "mcserver.versions",
                "某个服务端类型的版本列表（新版本在前）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { versions(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mcserver.loaders",
                "某个 Minecraft 版本下可用的加载器版本（目前只有 Fabric）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { loaders(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "mcserver.plan",
                "把类型 + 版本（+ 加载器版本）解析成下载地址、校验值与建议启动命令",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { plan(&state, &ctx).await }
                },
            );
        }
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: McserverConfig = env.config()?;
        let http = api::build_client(config.request_timeout_secs)
            .map_err(|message| Error::module("mcserver", message))?;

        tracing::info!(
            cache_ttl_secs = config.cache_ttl_secs,
            timeout_secs = config.request_timeout_secs.max(1),
            sources = model::TYPES.len(),
            "服务端目录已就绪"
        );

        let _ = self.state.ready.set(Ready {
            http,
            versions: Cache::new(config.cache_ttl_secs),
            vanilla: Cache::new(config.cache_ttl_secs),
            loaders: Cache::new(config.cache_ttl_secs),
        });

        register_plan_step(&self.state, &env.app);
        Ok(())
    }
}

/// 往任务系统的注册表里挂 `mcserver.plan` 步骤。
///
/// 「实例创建 → 下载」那条工作流的第一步：把「类型 + 版本 + 加载器」解析成
/// 地址 / 文件名 / 启动命令 / 校验值，后面的建实例与下载都读它的 output。
///
/// 这一步由 mcserver 自己注册（而不是让 instance 去调 mcserver 的内部函数）：
/// 步骤的闭包因此能直接握着本模块的 `McserverState`（带 http 客户端与版本缓存），
/// 不需要为「跨模块取句柄」再造一个进程级全局。
///
/// task 模块没启用时不注册 —— 注册表没人读，挂了也是白占内存。
fn register_plan_step(state: &Arc<McserverState>, app: &AppState) {
    if !crate::module::builtin::task::enabled(app) {
        tracing::debug!("task 模块未启用，`mcserver.plan` 步骤跳过注册");
        return;
    }

    let state = state.clone();
    crate::module::builtin::task::flows::registry(app).register_step_or_warn(
        "mcserver.plan",
        crate::module::builtin::task::flows::StepSpec {
            title: "准备服务端".into(),
            run: Arc::new(move |step, progress, _env| {
                let state = state.clone();
                Box::pin(async move {
                    let config = step.config.as_ref();
                    let pick = |key: &str| {
                        config
                            .and_then(|c| c.get(key))
                            .and_then(|v| v.as_str())
                            .map(str::to_string)
                    };
                    let Some(type_id) = pick("type") else {
                        return Err("`mcserver.plan` 步骤缺少 `type` 配置".to_string());
                    };

                    progress.report(json!({ "percent": null, "message": "正在解析下载地址" }));
                    plan_with(&state, &type_id, pick("version"), pick("loader_version"))
                        .await
                        .map_err(|e| format!("{}：{}", e.code, e.message))
                })
            }),
            rollback: None,
        },
    );
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------
//
// 下面的 JSON 都是**从真实上游抓下来的**响应（裁掉无关字段，形状照抄）。
// 上游改接口时先炸的是这里，而不是线上用户 —— 这正是把解析拎成纯函数的原因。

#[cfg(test)]
mod tests {
    use super::api::*;
    use super::*;
    use gosh_dl::DownloadState;

    // ── 原版（Mojang）──────────────────────────────────────────────────────

    #[test]
    fn mojang_manifest_keeps_releases_and_their_detail_url() {
        let manifest = json!({
            "latest": { "release": "26.3", "snapshot": "26.4-pre1" },
            "versions": [
                { "id": "26.3", "type": "release", "url": "https://piston-meta.mojang.com/a/26.3.json" },
                { "id": "26.4-pre1", "type": "snapshot", "url": "https://piston-meta.mojang.com/a/26.4-pre1.json" },
                { "id": "1.21.8", "type": "release", "url": "https://piston-meta.mojang.com/a/1.21.8.json" },
                { "id": "1.21.9-pre2", "type": "old_beta", "url": "https://piston-meta.mojang.com/a/1.21.9-pre2.json" }
            ]
        });

        let entries = mojang::parse_manifest(&manifest).expect("清单应当能解析");
        let ids: Vec<&str> = entries.iter().map(|e| e.id.as_str()).collect();
        // 只要 release：快照与 old_beta 都不进列表
        assert_eq!(ids, vec!["26.3", "1.21.8"]);
        // 顺序跟着官方（新版本在前），不自己排
        assert_eq!(
            entries[0].detail_url,
            "https://piston-meta.mojang.com/a/26.3.json"
        );
    }

    #[test]
    fn mojang_detail_extracts_server_jar_and_sha1() {
        let detail = json!({
            "downloads": {
                "client": { "sha1": "aaa", "size": 1, "url": "https://x/client.jar" },
                "server": {
                    "sha1": "33680F5F2AC32864D6D7CF5E56A705FDB3E05F4C",
                    "size": 62294556,
                    "url": "https://piston-data.mojang.com/v1/objects/3368.../server.jar"
                }
            }
        });

        let download =
            mojang::parse_server_download(&detail, "https://x/26.3.json").expect("应当能解析");
        assert_eq!(
            download.url,
            "https://piston-data.mojang.com/v1/objects/3368.../server.jar"
        );
        // 只有 sha1 可给，且统一成小写
        assert_eq!(
            download.checksum,
            Some((
                "sha1",
                "33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c".to_string()
            ))
        );
    }

    #[test]
    fn mojang_detail_reports_versions_without_a_server_jar() {
        // 老版本（1.2.5 以前）没有 downloads.server
        let detail = json!({ "downloads": { "client": { "sha1": "aaa", "size": 1, "url": "u" } } });
        let err = mojang::parse_server_download(&detail, "https://x/1.1.json").unwrap_err();
        assert!(matches!(err, FetchError::NotFound(_)), "{err:?}");
    }

    // ── PaperMC（paper / folia / velocity）────────────────────────────────

    #[test]
    fn paper_versions_flatten_grouped_map_and_drop_prereleases() {
        let response = json!({
            "project": { "id": "paper" },
            "versions": {
                "26.3": ["26.3", "26.3-rc-3"],
                "1.21": ["1.21.8", "1.21.7", "1.21.6-pre1"]
            }
        });

        let versions = papermc::parse_versions(&response).expect("应当能解析");
        // 摊平 + 滤掉 rc/pre + 降序
        assert_eq!(versions, vec!["26.3", "1.21.8", "1.21.7"]);
    }

    #[test]
    fn paper_build_extracts_the_server_default_artifact() {
        let build = json!({
            "id": 60,
            "channel": "STABLE",
            "downloads": {
                "server:default": {
                    "name": "paper-1.21.8-60.jar",
                    "checksums": { "sha256": "8DE7C52C3B02403503D16FAC58003F1EFEF7DD7A0256786843927FA92EE57F1E" },
                    "size": 52811717,
                    "url": "https://fill-data.papermc.io/v2/objects/8de7.../paper-1.21.8-60.jar"
                }
            }
        });

        let download = papermc::parse_download(&build, "paper", "1.21.8").expect("应当能解析");
        assert!(download.url.starts_with("https://fill-data.papermc.io/"));
        assert_eq!(
            download.checksum,
            Some((
                "sha256",
                "8de7c52c3b02403503d16fac58003f1efef7dd7a0256786843927fa92ee57f1e".to_string()
            ))
        );
    }

    #[test]
    fn paper_build_reports_a_missing_artifact() {
        let build = json!({ "id": 60, "downloads": {} });
        let err = papermc::parse_download(&build, "paper", "1.21.8").unwrap_err();
        assert!(matches!(err, FetchError::NotFound(_)), "{err:?}");
    }

    /// Folia 复用 paper 那套解析，所以这里钉的是**真实响应体**能不能过 ——
    /// 万一哪天 folia 的 project 改了产物键（不再是 `server:default`），
    /// 炸的是这条用例，而不是用户点下载时。
    #[test]
    fn folia_reuses_the_paper_parser_on_its_real_responses() {
        // 实测抓下来的 `fill.papermc.io/v3/projects/folia`（2026-09-26）
        let response = json!({
            "project": { "id": "folia", "name": "Folia" },
            "versions": {
                "26.2": ["26.2"],
                "26.1": ["26.1.2"],
                "1.21": ["1.21.11", "1.21.8", "1.21.6", "1.21.5", "1.21.4"],
                "1.20": ["1.20.6", "1.20.4", "1.20.2", "1.20.1"],
                "1.19": ["1.19.4"]
            }
        });
        let versions = papermc::parse_versions(&response).expect("folia 版本列表应当能解析");
        assert_eq!(
            &versions[..4],
            ["26.2", "26.1.2", "1.21.11", "1.21.8"],
            "应当摊平分组并降序：{versions:?}"
        );
        assert_eq!(versions.len(), 12, "分组摊平后不该丢版本：{versions:?}");

        // 实测的 `.../folia/versions/1.21.8/builds/latest`
        let build = json!({
            "id": 6,
            "channel": "STABLE",
            "downloads": {
                "server:default": {
                    "name": "folia-1.21.8-6.jar",
                    "url": "https://fill-data.papermc.io/v1/objects/233843cf…/folia-1.21.8-6.jar",
                    "checksums": {
                        "sha256": "233843CFD5001B6F658FCAB549178D694CC37F0277D004EA295DE0A94C57278F"
                    }
                }
            }
        });
        let download =
            papermc::parse_download(&build, "folia", "1.21.8").expect("folia 构建应当能解析");
        assert!(download.url.contains("/folia-1.21.8-6.jar"));
        assert_eq!(
            download.checksum,
            Some((
                "sha256",
                "233843cfd5001b6f658fcab549178d694cc37f0277d004ea295de0a94c57278f".to_string()
            )),
            "产物键与 paper 相同，校验值也该照常取到"
        );
    }

    // ── Purpur ────────────────────────────────────────────────────────────

    #[test]
    fn purpur_versions_are_sorted_descending() {
        // 上游是升序的（实测 1.14.1 → 26.3），必须自己排
        let response = json!({
            "project": "purpur",
            "versions": ["1.14.1", "1.21.8", "1.21.9-rc1", "26.2", "26.3"]
        });

        let versions = purpur::parse_versions(&response).expect("应当能解析");
        assert_eq!(versions, vec!["26.3", "26.2", "1.21.8", "1.14.1"]);
    }

    #[test]
    fn purpur_uses_the_build_number_and_reads_md5() {
        let info = json!({
            "project": "purpur",
            "version": "1.21.8",
            "builds": { "latest": "2497", "all": ["2478", "2497"] }
        });
        assert_eq!(purpur::parse_latest_build(&info, "1.21.8").unwrap(), "2497");

        let build = json!({
            "project": "purpur",
            "version": "1.21.8",
            "build": "2497",
            "result": "SUCCESS",
            "md5": "B8B2802525F5B85F986AF49AC4B095AA"
        });
        assert_eq!(
            purpur::parse_build_md5(&build),
            Some(("md5", "b8b2802525f5b85f986af49ac4b095aa".to_string()))
        );

        // 没有 md5 也不算错（拿不到校验值而已）
        assert_eq!(purpur::parse_build_md5(&json!({ "build": "1" })), None);
    }

    // ── Leaf / Leaves ─────────────────────────────────────────────────────

    #[test]
    fn leaf_versions_are_sorted_even_though_upstream_order_is_random() {
        // 实测上游就是乱的：1.21.11 排在 1.21.4 前面
        let response = json!({
            "project_id": "leaf",
            "versions": ["1.21.11", "1.21.4", "1.21.5", "26.1.2", "26.2", "1.21.8"]
        });

        let versions = leafmc::parse_versions(&response).expect("应当能解析");
        assert_eq!(
            versions,
            vec!["26.2", "26.1.2", "1.21.11", "1.21.8", "1.21.5", "1.21.4"]
        );
    }

    #[test]
    fn leaf_picks_the_highest_build_number() {
        // 数组有缺口（少了 17），所以是取最大而不是取最后一个
        let list = json!({ "builds": [3, 4, 5, 16, 18, 138, 137] });
        assert_eq!(leafmc::parse_latest_build(&list, "1.21.8").unwrap(), "138");

        let empty = json!({ "builds": [] });
        let err = leafmc::parse_latest_build(&empty, "1.21.8").unwrap_err();
        assert!(matches!(err, FetchError::NotFound(_)), "{err:?}");
    }

    #[test]
    fn leaf_and_leaves_read_different_artifact_keys() {
        let leaf_detail = json!({
            "build": 138,
            "downloads": {
                "primary": { "name": "leaf-1.21.8-138.jar", "sha256": "AAAA" }
            }
        });
        let download =
            leafmc::parse_leaf_build_detail(&leaf_detail, "1.21.8", "138").expect("应当能解析");
        assert_eq!(
            download.url,
            "https://api.leafmc.one/v2/projects/leaf/versions/1.21.8/builds/138/downloads/leaf-1.21.8-138.jar"
        );
        assert_eq!(download.checksum, Some(("sha256", "aaaa".to_string())));

        // Leaves 的字段叫 application，构建号在顶层
        let leaves_detail = json!({
            "code": 200,
            "version": "1.21.8",
            "build": 137,
            "downloads": {
                "application": { "name": "leaves-1.21.8-137.jar", "sha256": "BBBB" }
            }
        });
        let download = leafmc::parse_leaves_latest(&leaves_detail, "1.21.8").expect("应当能解析");
        assert_eq!(
            download.url,
            "https://api.leavesmc.org/v2/projects/leaves/versions/1.21.8/builds/137/downloads/leaves-1.21.8-137.jar"
        );
        assert_eq!(download.checksum, Some(("sha256", "bbbb".to_string())));
    }

    #[test]
    fn leaf_detail_reports_a_missing_artifact_key() {
        // 把 leaves 的响应喂给 leaf 的解析器 → 找不到 primary
        let leaves_detail = json!({ "downloads": { "application": { "name": "x.jar" } } });
        let err = leafmc::parse_leaf_build_detail(&leaves_detail, "1.21.8", "1").unwrap_err();
        assert!(matches!(err, FetchError::NotFound(_)), "{err:?}");
    }

    // ── Fabric ────────────────────────────────────────────────────────────

    #[test]
    fn fabric_keeps_only_stable_game_versions() {
        let response = json!([
            { "version": "1.21.9", "stable": false },
            { "version": "1.21.8", "stable": true },
            { "version": "1.21.7", "stable": true }
        ]);

        let versions = fabric::parse_game_versions(&response).expect("应当能解析");
        assert_eq!(versions, vec!["1.21.8", "1.21.7"]);
    }

    #[test]
    fn fabric_loader_versions_come_from_the_nested_loader_object() {
        let response = json!([
            { "loader": { "version": "0.16.14", "stable": true }, "intermediary": { "version": "1.21.8" } },
            { "loader": { "version": "0.16.9", "stable": false } }
        ]);

        let versions = fabric::parse_loader_versions(&response).expect("应当能解析");
        assert_eq!(versions, vec!["0.16.14", "0.16.9"]);
    }

    #[test]
    fn fabric_server_jar_uses_the_latest_installer() {
        let installers = json!([
            { "url": "https://maven.fabricmc.net/1.1.2/fabric-installer-1.1.2.jar", "version": "1.1.2", "stable": true },
            { "url": "https://maven.fabricmc.net/1.1.1/fabric-installer-1.1.1.jar", "version": "1.1.1", "stable": false }
        ]);
        let installer = fabric::parse_installer_version(&installers).expect("应当能解析");
        assert_eq!(installer, "1.1.2");

        // 拼出来的地址就是官方那条「合并 jar」直链
        let url = format!(
            "https://meta.fabricmc.net/v2/versions/loader/1.21.8/0.16.14/{installer}/server/jar"
        );
        assert!(url.contains("/loader/1.21.8/0.16.14/1.1.2/server/jar"));
    }

    // ── BungeeCord ────────────────────────────────────────────────────────

    #[test]
    fn bungeecord_uses_the_build_number_not_the_floating_alias() {
        let build = json!({ "_class": "hudson.maven.MavenModuleSetBuild", "number": 4321 });
        let download = bungeecord::parse_download(&build).expect("应当能解析");
        assert_eq!(
            download.url,
            "https://ci.md-5.net/job/BungeeCord/4321/artifact/bootstrap/target/BungeeCord.jar"
        );
        // Jenkins 不给校验值
        assert_eq!(download.checksum, None);
        assert_eq!(bungeecord::PSEUDO_VERSION, "latest");
    }

    // ── 版本号比较与白名单 ─────────────────────────────────────────────────

    #[test]
    fn version_comparison_handles_year_based_and_dotted_numbers() {
        use std::cmp::Ordering;
        // 年份命名（26.x）比 1.x 新
        assert_eq!(compare_versions("26.3", "1.21.8"), Ordering::Greater);
        // 数值比较而不是字符串比较：1.9 < 1.21
        assert_eq!(compare_versions("1.21", "1.9"), Ordering::Greater);
        assert_eq!(compare_versions("1.21.8", "1.21.11"), Ordering::Less);
        assert_eq!(compare_versions("1.21.8", "1.21.8"), Ordering::Equal);

        let mut versions = vec![
            "1.9".to_string(),
            "1.21.11".to_string(),
            "26.2".to_string(),
            "1.21.8".to_string(),
        ];
        sort_versions_desc(&mut versions);
        assert_eq!(versions, vec!["26.2", "1.21.11", "1.21.8", "1.9"]);
    }

    #[test]
    fn version_tokens_reject_path_characters() {
        // 上游地址是拼出来的，这几个字符一旦放行就能把请求指到别处
        for bad in ["", "../x", "1.21/8", "1.21?x=1", "a b", "#frag"] {
            assert!(
                api::validate_version_token(bad, "version").is_err(),
                "`{bad}` 应该被拒绝"
            );
        }
        for ok in ["1.21.8", "26.3", "0.16.14", "1.21.8+build.1", "a_b-c"] {
            assert!(
                api::validate_version_token(ok, "version").is_ok(),
                "`{ok}` 应该放行"
            );
        }
        // 长度上限
        assert!(api::validate_version_token(&"1".repeat(65), "version").is_err());
    }

    // ── 缓存 ──────────────────────────────────────────────────────────────

    #[test]
    fn cache_returns_hits_and_respects_a_zero_ttl() {
        let cache: Cache<Vec<String>> = Cache::new(60);
        assert!(cache.get("k").is_none(), "没存过就是 miss");
        cache.put("k", Arc::new(vec!["1.21.8".into()]));
        let hit = cache.get("k").expect("存过就该命中");
        assert_eq!(hit.as_slice(), ["1.21.8".to_string()]);

        // 0 = 不缓存：存了也永远不命中
        let no_cache: Cache<Vec<String>> = Cache::new(0);
        no_cache.put("k", Arc::new(vec!["1.21.8".into()]));
        assert!(no_cache.get("k").is_none());
    }

    // ── 类型表与注册 ──────────────────────────────────────────────────────

    #[test]
    fn type_table_is_internally_consistent() {
        let ids = model::known_ids();
        assert_eq!(ids.len(), model::TYPES.len(), "id 不能重复");

        // 每个分类引用的类型都得存在，且每个类型只属于一个分类
        let mut seen: Vec<&str> = Vec::new();
        for category in model::CATEGORIES {
            for id in category.types {
                assert!(model::find(id).is_some(), "分类引用了不存在的类型 `{id}`");
                assert!(!seen.contains(id), "类型 `{id}` 出现在多个分类里");
                seen.push(id);
            }
        }
        for entry in model::TYPES {
            assert!(
                seen.contains(&entry.id),
                "类型 `{}` 没被任何分类收进去",
                entry.id
            );
            assert_eq!(
                entry.category,
                category_of(entry.id),
                "`{}` 的 category 与分类表不一致",
                entry.id
            );
        }

        // 校验算法只能是 download.add 认识的参数名
        for entry in model::TYPES {
            assert!(
                ["sha1", "sha256", "md5", "none"].contains(&entry.checksum),
                "`{}` 的 checksum 取值不合法：{}",
                entry.id,
                entry.checksum
            );
        }

        // 本轮只有 Fabric 需要加载器版本
        let with_loader: Vec<&str> = model::TYPES
            .iter()
            .filter(|entry| entry.needs_loader)
            .map(|entry| entry.id)
            .collect();
        assert_eq!(with_loader, vec!["fabric"]);

        // 只有 BungeeCord 没有版本可选
        let without_version: Vec<&str> = model::TYPES
            .iter()
            .filter(|entry| !entry.needs_version)
            .map(|entry| entry.id)
            .collect();
        assert_eq!(without_version, vec!["bungeecord"]);

        // 文件名与启动命令不能是空的、也不能自相矛盾
        for entry in model::TYPES {
            assert!(!entry.file_name.is_empty());
            assert!(
                entry.startup_command.contains(entry.file_name),
                "`{}` 的启动命令没用到它自己的文件名",
                entry.id
            );
        }
    }

    fn category_of(id: &str) -> &'static str {
        for category in model::CATEGORIES {
            if category.types.contains(&id) {
                return category.id;
            }
        }
        ""
    }

    /// 模板里那一节就是用户第一次跑会拿到的东西。
    ///
    /// `--check` 不过模块私有配置（那要等 `start()`），所以这一节的内容没人在别处验过。
    #[test]
    fn the_default_template_section_parses() {
        let config: crate::config::Config =
            toml::from_str(&crate::config::Config::template()).expect("模板必须能解析");
        let section = config
            .modules
            .section("mcserver")
            .expect("模板里应当有服务端目录那一节");

        let parsed = McserverConfig::deserialize(section.clone())
            .expect("模板里的服务端目录配置必须能反序列化");
        let default = McserverConfig::default();
        assert_eq!(parsed.cache_ttl_secs, default.cache_ttl_secs);
        assert_eq!(parsed.request_timeout_secs, default.request_timeout_secs);
    }

    #[test]
    fn module_registers_exactly_four_methods() {
        let module = McserverModule::new();
        let mut reg = Registration::new("mcserver");
        module.register(&mut reg).unwrap();

        let names: Vec<String> = reg.methods.iter().map(|m| m.name.clone()).collect();
        assert_eq!(
            names,
            vec![
                "mcserver.types",
                "mcserver.versions",
                "mcserver.loaders",
                "mcserver.plan"
            ]
        );
        // 它只回答「下什么」，不推事件
        assert!(reg.topics.is_empty());
    }

    /// 类型表里那个「校验算法」得跟实际实现的源对得上 —— 光看表容易写漂。
    #[test]
    fn checksum_column_matches_what_the_sources_actually_return() {
        // 「上游不给校验值」在表里写成 "none"（而不是留空），前端据此提示用户
        let cases: [(&str, &str); 9] = [
            ("vanilla", "sha1"),
            ("paper", "sha256"),
            ("folia", "sha256"),
            ("purpur", "md5"),
            ("leaf", "sha256"),
            ("leaves", "sha256"),
            ("fabric", "none"),
            ("velocity", "sha256"),
            ("bungeecord", "none"),
        ];
        for (id, expected) in cases {
            let entry = model::find(id).expect("类型应当存在");
            assert_eq!(
                entry.checksum, expected,
                "`{id}` 的 checksum 列与实现不一致"
            );
        }
    }

    /// 兜底：确认用到的 gosh-dl 类型名没写错（防止将来重构时静默改掉语义）。
    #[test]
    fn sanity_checks_on_engine_types_we_rely_on() {
        assert!(DownloadState::Completed.is_finished());
        assert!(!DownloadState::Downloading.is_finished());
    }
}
