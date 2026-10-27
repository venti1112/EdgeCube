//! 运行环境模块：下载、解压、列出、删除 Java 运行环境。
//!
//! 目前只有 Zulu 的 JDK（[Azul Metadata API]），但整条链路是照「多家厂商」铺的：
//! 厂商与包类型在 [`model`] 里，一家的接口形状在 [`api`] 下一个文件。
//!
//! [Azul Metadata API]: https://api.azul.com/metadata/v1/docs/swagger
//!
//! # 落到哪里
//!
//! 与实例**同一套数据根**（复用 `[modules.config.instance] dir` 那条回退链），
//! 布局见 [`store`]：
//!
//! ```text
//! <data_dir>/config/runtimes/<id>.json   元数据（含「正在装」「装失败」）
//! <data_dir>/runtimes/<id>/              解压出来的 JDK
//! <data_dir>/runtimes/.staging/<id>/     下载中的压缩包（装完就删）
//! ```
//!
//! id 是 `zulu-jdk-21-linux-x64` 这种**可读且稳定**的标识：一个「厂商 + 包类型 +
//! 大版本 + 平台」组合只该有一个环境，再装就是覆盖重装。
//!
//! # 为什么走全局下载队列
//!
//! 一个 JDK 包 200 MB 上下。让本模块自己实现一遍并发/限速/校验，等于把
//! [`download`](crate::module::builtin::download) 那套再做一遍，而且两份并发额度
//! 互不知情。所以走 [`download::Queue`]：它认绝对路径（这里是模块之间的调用，
//! 没有用户输入穿过来），校验值由我们从中游的包详情里取（sha256）。
//!
//! # 一次安装的完整过程
//!
//! ```text
//! runtime.install
//!   ├── 问上游要「这个大版本最新一个构建」的详情（sha256 / size / 文件名）
//!   ├── 落一份 state=downloading 的元数据  ← 这一刻起列表里就能看到它了
//!   ├── 提交给下载队列（落到 .staging/<id>/）
//!   └── spawn 一个后台任务：
//!         等下载完 → state=extracting → 解压 → 找 bin/java
//!           ├── 找到 → state=installed（记下 java_home / java_bin），删掉压缩包
//!           └── 没找到 → state=failed（stage=extract，压缩包留着给重试）
//! ```
//!
//! **安装是 daemon 侧的**：前端发一个 `runtime.install` 就可以关掉，装完的
//! 结果落在元数据里；中间过程靠 [`TOPIC_STATE`] 推给连着的客户端。
//! 这一步刻意不做成「前端串三步」：200 MB 下完却因为 App 关了就没人解压，
//! 是那种用户完全没法自救的状态。
//!
//! # daemon 重启
//!
//! 下载队列**不持久化**，所以重启后「正在装」的环境不可能自己装完。`start()`
//! 会把它们收拾成确定的失败态（见 [`recover_after_restart`]）—— 列表不该永远
//! 停在「下载中」。若暂存目录里的压缩包大小与上游给的一致，说明死在解压那一步，
//! 重试时可以跳过下载。
//!
//! # 删除就是取消
//!
//! 在途的后台任务在**每一次落地之前**都会问一遍「我这条记账还在不在」
//! （[`owns_record`]），所以 `runtime.delete` 先删元数据就等于叫停它：
//! 任务不会再往回写，也不会把记录又建出来（真的在解压中的那一轮，结束后会把自己
//! 刚解出来的东西再清一次）。
//!
//! # 方法
//!
//! | 方法 | 参数 | 说明 |
//! | --- | --- | --- |
//! | `runtime.catalog` | — | 厂商 / 包类型表 + 本机平台（前端零硬编码） |
//! | `runtime.versions` | `provider?`、`package_type?` | 可装的大版本列表（新的在前） |
//! | `runtime.list` | — | 全部环境（含正在装与失败的） |
//! | `runtime.install` | `provider?`、`package_type?`、`java_version` | 装一个（返回环境对象，state=downloading） |
//! | `runtime.delete` | `id` | 删掉环境（元数据 + 目录 + 暂存） |
//!
//! # 错误码（前端按码分支）
//!
//! `runtime_unavailable`、`runtime_unsupported_host`、`runtime_provider_not_found`、
//! `runtime_package_type_not_found`、`runtime_version_required`、
//! `runtime_version_not_found`、`runtime_not_found`、`runtime_busy`、
//! `runtime_upstream_error`、`runtime_parse_error`、`runtime_save_failed`。

pub mod api;
pub mod extract;
pub mod install;
pub mod model;
pub mod store;

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{Value, json};

use crate::error::{Error, Result, RpcError, RpcResult};
use crate::module::builtin::instance::resolve_data_dir;
use crate::module::{CallCtx, Module, ModuleDescriptor, ModuleEnv, Registration};
use crate::state::AppState;
use crate::util::cache::Cache;
use crate::util::fetch::{self, FetchError};
use crate::util::now_ms;

use model::{Env, EnvState, Stage};
use store::DATA_SUB_DIR;

/// 环境状态变化。**载荷就是列表里那一份完整的对象**（与 `runtime.list` 同形），
/// 前端一套模型吃两种来源。
///
/// 删除**不推事件**：删掉之后没有「这个环境」可以描述了，前端自己刷新列表即可。
const TOPIC_STATE: &str = "runtime.state";

const CODE_UNAVAILABLE: &str = "runtime_unavailable";
const CODE_UNSUPPORTED_HOST: &str = "runtime_unsupported_host";
const CODE_PROVIDER_NOT_FOUND: &str = "runtime_provider_not_found";
const CODE_TYPE_NOT_FOUND: &str = "runtime_package_type_not_found";
const CODE_VERSION_REQUIRED: &str = "runtime_version_required";
const CODE_VERSION_NOT_FOUND: &str = "runtime_version_not_found";
const CODE_NOT_FOUND: &str = "runtime_not_found";
const CODE_BUSY: &str = "runtime_busy";
const CODE_UPSTREAM: &str = "runtime_upstream_error";
const CODE_PARSE: &str = "runtime_parse_error";
const CODE_SAVE_FAILED: &str = "runtime_save_failed";

/// 默认厂商。前端不传就按它办 —— 目前也只有它。
const DEFAULT_PROVIDER: &str = "zulu";

// ---------------------------------------------------------------------------
// 配置与模块状态
// ---------------------------------------------------------------------------

/// `[modules.config.runtime]`。
///
/// **没有 `dir`**：数据根与实例共用（见模块头注释），多一个配置项只会多一个
/// 「两边指向不同目录」的机会。
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RuntimeConfig {
    /// 单次上游请求的超时（秒），至少 1。
    #[serde(default = "default_request_timeout_secs")]
    pub request_timeout_secs: u64,
    /// 版本清单的缓存时长（秒），0 = 不缓存。
    ///
    /// 默认 5 分钟，与 `mcserver` 同一个口径。**对 frp 尤其重要**：它的清单走
    /// GitHub API，未认证配额只有 60 次/小时，「历史版本」按钮点几次就见底了。
    #[serde(default = "default_cache_ttl_secs")]
    pub cache_ttl_secs: u64,
}

fn default_cache_ttl_secs() -> u64 {
    300
}

fn default_request_timeout_secs() -> u64 {
    20
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            request_timeout_secs: default_request_timeout_secs(),
            cache_ttl_secs: default_cache_ttl_secs(),
        }
    }
}

/// `start()` 里定下来之后不再变的东西。
struct Ready {
    http: reqwest::Client,
    /// 与实例共用同一个数据根。
    data_dir: PathBuf,
    /// frp 的 release 清单。
    ///
    /// key 是 `"latest"` / `"history"` —— 两个入口的响应形状不同（一个对象 /
    /// 一个数组），缓存键分开。**GitHub 未认证只有 60 次/小时**，所以这两个
    /// 缓存是「能不能用」的问题，不是「快不快」的问题。
    releases: Cache<Vec<api::github::Version>>,
}

#[derive(Default)]
struct RuntimeState {
    ready: OnceLock<Ready>,
    /// 正在装的环境 id。挡的是「同一个环境并发装两次」：两次下载同一份包互相覆盖，
    /// 谁先解压完谁赢，纯属自找麻烦。
    ///
    /// 用 id 集合而不是计数：同一个 id 最多一条，语义更直白。
    running: Mutex<HashSet<String>>,
}

impl RuntimeState {
    fn ready(&self) -> RpcResult<&Ready> {
        self.ready
            .get()
            .ok_or_else(|| RpcError::new(CODE_UNAVAILABLE, "运行环境模块尚未就绪"))
    }
}

/// 「这个环境正在装」的占位。后台任务结束时（含 panic 展开）自动摘掉。
struct RunningGuard {
    state: Arc<RuntimeState>,
    id: String,
}

impl Drop for RunningGuard {
    fn drop(&mut self) {
        self.state
            .running
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&self.id);
    }
}

pub struct RuntimeModule {
    state: Arc<RuntimeState>,
}

impl Default for RuntimeModule {
    fn default() -> Self {
        Self::new()
    }
}

impl RuntimeModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RuntimeState::default()),
        }
    }
}

// ---------------------------------------------------------------------------
// 取参数（都是纯函数，单独测）
// ---------------------------------------------------------------------------

/// 厂商 + 包类型。两者都要在我们表里，且厂商得真的提供这个包类型。
///
/// 返回整个 [`model::Provider`] 而不是 id：调用方多半还要用它的
/// [`version_prefix`](model::Provider::version_prefix) / [`launcher`](model::Provider::launcher)。
fn resolve_kind(ctx: &CallCtx) -> RpcResult<(&'static model::Provider, &'static str)> {
    let provider_id = ctx.param_or("provider", DEFAULT_PROVIDER.to_string())?;
    let provider = model::find_provider(provider_id.trim()).ok_or_else(|| {
        RpcError::new(
            CODE_PROVIDER_NOT_FOUND,
            format!(
                "不认识的厂商 `{provider_id}`（可选：{}）",
                model::PROVIDERS
                    .iter()
                    .map(|p| p.id)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        )
    })?;

    // 不传包类型时**按厂商自己的第一项**兜底，不是全局的 `jdk` ——
    // frp 只提供 `frpc`，拿 `jdk` 去兜会直接报「frp 不提供 jdk」（踩过）。
    let default_type = provider
        .package_types
        .first()
        .copied()
        .unwrap_or(model::DEFAULT_PACKAGE_TYPE);
    let type_id = ctx.param_or("package_type", default_type.to_string())?;
    let package_type = model::find_package_type(type_id.trim()).ok_or_else(|| {
        RpcError::new(
            CODE_TYPE_NOT_FOUND,
            format!(
                "不认识的包类型 `{type_id}`（可选：{}）",
                model::PACKAGE_TYPES
                    .iter()
                    .map(|t| t.id)
                    .collect::<Vec<_>>()
                    .join("、")
            ),
        )
    })?;

    if !provider.package_types.contains(&package_type.id) {
        return Err(RpcError::new(
            CODE_TYPE_NOT_FOUND,
            format!(
                "`{}` 目前不提供 {}（可选：{}）",
                provider.id,
                package_type.id,
                provider.package_types.join(", ")
            ),
        ));
    }
    Ok((provider, package_type.id))
}

/// 上游失败 → 我们的错误码。三类的区分见 [`FetchError`]。
fn map_fetch_error(err: FetchError) -> RpcError {
    match err {
        FetchError::NotFound(message) => RpcError::new(CODE_VERSION_NOT_FOUND, message),
        FetchError::Upstream(message) => RpcError::new(CODE_UPSTREAM, message),
        FetchError::Parse(message) => RpcError::new(CODE_PARSE, message),
    }
}

/// 目标平台；这台机器没有对应的 Zulu 构建时报错。
fn host_target() -> RpcResult<model::Target> {
    model::host_target().ok_or_else(|| {
        RpcError::new(
            CODE_UNSUPPORTED_HOST,
            format!(
                "这台机器（{}/{}）没有对应的 Zulu 构建",
                std::env::consts::OS,
                std::env::consts::ARCH
            ),
        )
    })
}

// ---------------------------------------------------------------------------
// 方法
// ---------------------------------------------------------------------------

/// `runtime.catalog` —— 厂商 / 包类型表 + 本机平台。前端据此渲染，**零硬编码**。
fn catalog() -> RpcResult<Value> {
    let host = model::host_target();
    Ok(json!({
        "providers": model::PROVIDERS,
        "package_types": model::PACKAGE_TYPES,
        "default_provider": DEFAULT_PROVIDER,
        "default_package_type": model::DEFAULT_PACKAGE_TYPE,
        // 本机平台：装的就是给这台机器用的那份，所以没有「选平台」这回事
        "host": host.map(|target| json!({
            "os": target.os,
            "arch": target.arch,
            "archive_type": target.archive_type,
            "libc": target.libc,
        })),
        // false = 这台机器装不了（前端据此把入口置灰并说明）
        "supported": host.is_some(),
    }))
}

/// `runtime.versions` —— 可装的大版本列表（新的在前）。
async fn versions(state: &Arc<RuntimeState>, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let target = host_target()?;
    let (provider, package_type) = resolve_kind(ctx)?;

    // 默认只给**最新那个**。frp 那种 GitHub 源特别需要这个默认值：
    // 多数人用最新版就够，一次请求也省一次配额。
    let all = ctx.optional::<bool>("all")?.unwrap_or(false);

    let items = match provider.id {
        "frp" => github_versions(ready, &target, all).await?,
        // Zulu：一个版本一个包，列表里就够挑的了（详情装的时候再问）
        _ => azul_versions(ready, &target, package_type).await?,
    };

    Ok(json!({
        "provider": provider.id,
        "package_type": package_type,
        // `all = false` 时列表里只有最新那个 —— 前端据此决定要不要显示
        // 「历史版本」按钮（已经拉到全部了就没必要再显示）
        "all": all,
        "os": target.os,
        "arch": target.arch,
        "archive_type": target.archive_type,
        "versions": items,
    }))
}

/// Azul：一个大版本一项。
async fn azul_versions(
    ready: &Ready,
    target: &model::Target,
    package_type: &str,
) -> RpcResult<Vec<Value>> {
    let provider = model::find_provider("zulu").expect("zulu 一定在厂商表里");
    let list = api::azul::versions(&ready.http, target, package_type)
        .await
        .map_err(map_fetch_error)?;

    // 只把「用户要选的东西」放出去：`package_uuid` 是实现的细节，安装时我们按
    // 大版本重查一遍最新的那个构建（这样列表过期也不会装到旧的）
    Ok(list
        .iter()
        .map(|version| {
            json!({
                "version": version.java_major.to_string(),
                "label": format!("{}{}", provider.version_prefix, version.java_major),
                "subtitle": version.java_version,
            })
        })
        .collect())
}

/// frp：GitHub Releases。`all = false` 只要最新（一次请求），
/// `true` 才拉历史列表（前端点「历史版本」时才走这条）。
async fn github_versions(
    ready: &Ready,
    target: &model::Target,
    all: bool,
) -> RpcResult<Vec<Value>> {
    let provider = model::find_provider("frp").expect("frp 一定在厂商表里");
    let key = if all { "history" } else { "latest" };
    let releases = match ready.releases.get(key) {
        Some(hit) => hit,
        None => {
            let fetched = if all {
                api::github::history(&ready.http, target)
                    .await
                    .map_err(map_fetch_error)?
            } else {
                vec![
                    api::github::latest(&ready.http, target)
                        .await
                        .map_err(map_fetch_error)?,
                ]
            };
            let fetched = Arc::new(fetched);
            ready.releases.put(key, fetched.clone());
            fetched
        }
    };

    Ok(releases
        .iter()
        .map(|version| {
            json!({
                "version": version.version,
                "label": format!("{}{}", provider.version_prefix, version.version),
                // 副行放发布日期：frp 上游只有一个版本号，日期是唯一的额外信息
                "subtitle": version
                    .published_at
                    .as_deref()
                    .map(published_date)
                    .unwrap_or_default(),
            })
        })
        .collect())
}

/// `2026-08-14T06:36:29Z` → `2026-08-14`。拿不到合理解析就原样回。
fn published_date(iso: &str) -> String {
    iso.get(..10).unwrap_or(iso).to_string()
}

/// `runtime.list` —— 全部环境（含正在装与失败的）。
fn list(state: &Arc<RuntimeState>) -> RpcResult<Value> {
    let ready = state.ready()?;
    let environments = store::load_all(&ready.data_dir);
    Ok(json!({
        "environments": environments,
        "count": environments.len(),
        // 环境目录（<数据根>/runtimes）：让前端能显示「装到哪儿了」。
        // 注意是 runtimes 这一层而不是数据根 —— 用户关心的是环境在哪。
        "dir": ready.data_dir.join(DATA_SUB_DIR).display().to_string(),
    }))
}

/// `runtime.delete` —— 删掉一个环境（元数据 + 目录 + 暂存）。
///
/// **删元数据就是取消**：在途的后台任务每次落地前都会查它在不在（[`owns_record`]）。
fn delete(state: &Arc<RuntimeState>, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let id = ctx.param::<String>("id")?.trim().to_string();
    store::validate_id(&id).map_err(RpcError::invalid_params)?;

    let env_dir = store::env_dir(&ready.data_dir, &id);
    let meta_deleted =
        store::remove(&ready.data_dir, &id).map_err(|e| RpcError::new(CODE_SAVE_FAILED, e))?;

    if !meta_deleted && !env_dir.exists() {
        return Err(RpcError::new(
            CODE_NOT_FOUND,
            format!("没有 id 为 `{id}` 的运行环境"),
        ));
    }

    let files_deleted = store::remove_dir(&env_dir).is_ok();
    store::remove_dir(&store::staging_dir(&ready.data_dir, &id))
        .map_err(|e| RpcError::new(CODE_SAVE_FAILED, e))?;

    tracing::info!(env = %id, "运行环境已删除");
    Ok(json!({
        "deleted": true,
        "id": id,
        "meta_deleted": meta_deleted,
        "files_deleted": files_deleted,
        "dir": env_dir.display().to_string(),
    }))
}
/// 这个环境还是「我们这一轮要处理的那个」吗？
///
/// 删除就是取消：用户把环境删掉之后，在途的后台任务不该再往回写任何东西
/// （更不该把记录又建出来）。所以每次落地之前都问一遍。
///
/// `task_id` 给 `Some` 时连「是不是同一条下载任务」一起核对；覆盖重装的场景下
/// 记录会被换掉，只比 id 是抓不住那种情况的。
fn owns_record(data_dir: &Path, id: &str, task_id: Option<&gosh_dl::DownloadId>) -> bool {
    let Some(env) = store::load(data_dir, id) else {
        return false;
    };
    let Some(task_id) = task_id else {
        // 只问「还在不在」
        return true;
    };
    let expected = task_id.as_uuid().to_string();
    env.task_id.as_deref() == Some(expected.as_str())
}

/// 改一条记录、落盘、推事件。
fn mutate(data_dir: &Path, app: &AppState, id: &str, edit: impl FnOnce(&mut Env)) -> Option<Env> {
    let mut env = store::load(data_dir, id)?;
    edit(&mut env);
    env.updated_at_ms = now_ms();
    publish(data_dir, app, env)
}

/// 整份写下去（`install` 建新记录时用）。
fn save_and_publish(data_dir: &Path, app: &AppState, env: &Env) -> RpcResult<()> {
    store::save(data_dir, env).map_err(|e| RpcError::new(CODE_SAVE_FAILED, e))?;
    publish_env(app, env);
    Ok(())
}

fn publish(data_dir: &Path, app: &AppState, env: Env) -> Option<Env> {
    match store::save(data_dir, &env) {
        Ok(()) => {
            publish_env(app, &env);
            Some(env)
        }
        Err(e) => {
            tracing::error!(env = %env.id, error = %e, "运行环境元数据落盘失败");
            None
        }
    }
}

fn publish_env(app: &AppState, env: &Env) {
    match serde_json::to_value(env) {
        Ok(payload) => {
            app.bus.publish_from(Some("runtime"), TOPIC_STATE, payload);
        }
        Err(e) => tracing::error!(env = %env.id, error = %e, "运行环境事件序列化失败"),
    }
}

/// 落一个失败态。
fn mark_failed(
    data_dir: &Path,
    app: &AppState,
    id: &str,
    task_id: Option<&gosh_dl::DownloadId>,
    stage: Stage,
    message: String,
) {
    if !owns_record(data_dir, id, task_id) {
        return;
    }
    tracing::warn!(env = %id, stage = ?stage, error = %message, "运行环境安装失败");
    let _ = mutate(data_dir, app, id, |env| {
        env.state = EnvState::Failed;
        env.stage = Some(stage);
        env.error = Some(message);
        // 任务已经结束了，留着 task_id 只会让前端继续订阅一条不会再有动静的任务
        env.task_id = None;
    });
}

// ---------------------------------------------------------------------------
// 启停
// ---------------------------------------------------------------------------

/// daemon 重启后把「正在装」的环境收拾成可以重试的失败态。
///
/// 返回是否真的改了这一条（`start()` 据此决定要不要落盘）。
///
/// `staging_size` 是暂存目录里那个压缩包的**实际大小**：与上游给的一致就说明
/// 下载早就完了、死在解压那一步，于是把 stage 记成 `extract` —— 重试时能跳过下载。
/// 大小未知（文件不在、或上游没给 size）就按 `download` 算，重试重下，成本高但正确。
fn recover_after_restart(env: &mut Env, staging_size: Option<u64>) -> bool {
    if !env.state.is_busy() {
        return false;
    }

    let downloaded = match (staging_size, env.size) {
        (Some(actual), Some(expected)) => actual == expected,
        _ => false,
    };
    env.state = EnvState::Failed;
    env.task_id = None;
    env.stage = Some(if downloaded {
        Stage::Extract
    } else {
        Stage::Download
    });
    env.error = Some(if downloaded {
        "守护进程重启时正在解压；压缩包还在，重试可直接解压".to_string()
    } else {
        "守护进程重启时正在下载（下载队列不持久化），请重试".to_string()
    });
    env.updated_at_ms = now_ms();
    true
}

/// 启动时扫一遍磁盘：收拾「正在装」的环境，并清掉已经没有主人的暂存目录。
fn reconcile(data_dir: &Path) -> usize {
    let mut recovered = 0;
    for mut env in store::load_all(data_dir) {
        if !env.state.is_busy() {
            continue;
        }
        let archive = store::staging_dir(data_dir, &env.id).join(&env.file_name);
        let staging_size = fs::metadata(&archive).ok().map(|meta| meta.len());
        if recover_after_restart(&mut env, staging_size) && store::save(data_dir, &env).is_ok() {
            recovered += 1;
        }
    }

    // 暂存目录里的残留：有主的留着（上面刚判定成「可续解压」的那份要靠它），
    // 没主的清掉 —— 环境都删了，包还占 200 MB 没道理。
    let staging_root = data_dir.join(DATA_SUB_DIR).join(store::STAGING_SUB_DIR);
    if let Ok(entries) = fs::read_dir(&staging_root) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if store::load(data_dir, &name).is_none() {
                tracing::info!(staging = %name, "清掉没有对应环境的下载暂存");
                let _ = store::remove_dir(&entry.path());
            }
        }
    }
    recovered
}

// ---------------------------------------------------------------------------
// 模块实现
// ---------------------------------------------------------------------------

#[async_trait]
impl Module for RuntimeModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("runtime", "运行环境", env!("CARGO_PKG_VERSION")).description(
            "下载与管理运行环境（Zulu 的 JDK、fatedier 的 frp）：下载到暂存、解压到环境目录、列表、删除。安装走 runtime-install 工作流。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        reg.topic(
            TOPIC_STATE,
            "运行环境状态变化（下载中 / 解压中 / 装好 / 失败）；载荷与 `runtime.list` 里的单项同形",
        );

        // 厂商表是纯常量，不需要运行环境
        reg.method(
            "runtime.catalog",
            "可用的厂商 / 包类型表 + 本机平台",
            |_ctx: CallCtx| async move { catalog() },
        );

        {
            let state = self.state.clone();
            reg.method(
                "runtime.versions",
                "某个厂商与包类型下可装的 Java 大版本（新的在前）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { versions(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "runtime.list",
                "全部运行环境（含正在装与装失败的）",
                move |_ctx: CallCtx| {
                    let state = state.clone();
                    async move { list(&state) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "runtime.delete",
                "删掉一个运行环境（元数据 + 目录 + 下载暂存）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { delete(&state, &ctx) }
                },
            );
        }
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: RuntimeConfig = env.config()?;
        // 与实例同一个数据根：这里是「EdgeCube 自己的目录」唯一的定义处
        let data_dir = resolve_data_dir(env.app.config.modules.section("instance"));
        store::ensure_dirs(&data_dir)
            .map_err(|e| Error::module("runtime", format!("建运行环境目录失败: {e}")))?;

        let http = fetch::build_client(config.request_timeout_secs)
            .map_err(|message| Error::module("runtime", message))?;

        let recovered = reconcile(&data_dir);
        tracing::info!(
            dir = %data_dir.display(),
            timeout_secs = config.request_timeout_secs.max(1),
            providers = model::PROVIDERS.len(),
            recovered,
            "运行环境已就绪"
        );

        let _ = self.state.ready.set(Ready {
            http,
            data_dir,
            releases: Cache::new(config.cache_ttl_secs),
        });

        // 「下载 → 解压」工作流（task 模块没启用时它自己会跳过）。
        // 注意 `runtime.install` 那条一次调用做完的旧路径已经去掉 ——
        // 安装现在只有这一条路。
        install::register(&self.state, &env.app);
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        // 没有常驻循环要停。在途的安装任务会自己发现队列没了
        // （`DownloadOutcome::Gone`）或者随进程结束 —— 它们的中间状态
        // 由下次启动的 reconcile 收拾。
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::builtin::download;
    use crate::module::registry::ModuleRegistry;
    use tokio_util::sync::CancellationToken;

    fn test_app() -> AppState {
        let config = Config::default();
        let registry = Arc::new(ModuleRegistry::build(vec![], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    fn call_ctx(params: Value) -> CallCtx {
        CallCtx {
            app: test_app(),
            module: "runtime".into(),
            method: "runtime.versions".into(),
            params,
            conn_id: 1,
            peer: "127.0.0.1:12345".into(),
            is_local: true,
        }
    }

    // ── 表与注册 ──────────────────────────────────────────────────────────

    #[test]
    fn module_registers_exactly_four_methods_and_one_topic() {
        let module = RuntimeModule::new();
        let mut reg = Registration::new("runtime");
        module.register(&mut reg).unwrap();

        let names: Vec<String> = reg.methods.iter().map(|m| m.name.clone()).collect();
        assert_eq!(
            names,
            vec![
                "runtime.catalog",
                "runtime.versions",
                "runtime.list",
                "runtime.delete",
            ]
        );
        // 状态变化要推给前端（装的过程可能几十秒）
        assert_eq!(reg.topics.len(), 1);
        assert_eq!(reg.topics[0].topic, TOPIC_STATE);
    }

    #[test]
    fn the_default_template_section_parses() {
        let config: Config = toml::from_str(&Config::template()).expect("模板必须能解析");
        let section = config
            .modules
            .section("runtime")
            .expect("模板里应当有运行环境那一节");

        let parsed = RuntimeConfig::deserialize(section.clone())
            .expect("模板里的运行环境配置必须能反序列化");
        assert_eq!(
            parsed.request_timeout_secs,
            RuntimeConfig::default().request_timeout_secs
        );
    }

    #[test]
    fn catalog_reports_the_host_platform() {
        let value = catalog().expect("catalog 是纯常量，不该失败");
        assert_eq!(value["default_provider"], json!("zulu"));
        assert_eq!(value["default_package_type"], json!("jdk"));
        assert_eq!(value["providers"][0]["id"], json!("zulu"));
        // 这台机器能装（CI / 开发机都是 linux x64 或 aarch64）
        assert_eq!(value["supported"], json!(model::host_target().is_some()));
        if let Some(target) = model::host_target() {
            assert_eq!(value["host"]["os"], json!(target.os));
            assert_eq!(value["host"]["arch"], json!(target.arch));
        }
    }

    // ── 取参 ──────────────────────────────────────────────────────────────

    #[test]
    fn kind_defaults_and_rejects_unknown_values() {
        let (provider, package_type) = resolve_kind(&call_ctx(json!({}))).unwrap();
        assert_eq!((provider.id, package_type), ("zulu", "jdk"));

        let err = resolve_kind(&call_ctx(json!({ "provider": "temurin" }))).unwrap_err();
        assert_eq!(err.code, CODE_PROVIDER_NOT_FOUND);

        // JRE 在表里有、但 Zulu 这一档目前没开放下载
        let err = resolve_kind(&call_ctx(json!({ "package_type": "jre" }))).unwrap_err();
        assert_eq!(err.code, CODE_TYPE_NOT_FOUND);

        let err = resolve_kind(&call_ctx(json!({ "package_type": "graal" }))).unwrap_err();
        assert_eq!(err.code, CODE_TYPE_NOT_FOUND);
    }

    /// frp 的版本清单：GitHub 的 release 被压成 `{version, label, subtitle}`。
    ///
    /// 缓存**预置好**，所以这条用例不打上游 —— 它钉的是线上形状（前端就吃这个）。
    #[tokio::test]
    async fn versions_for_frp_maps_releases_into_the_wire_shape() {
        let temp = TempDir::new("frpver");
        let (state, _queue, _app, _cancel) = start_runtime(&temp.0).await;

        let release = api::github::Version {
            version: "0.71.0".into(),
            tag: "v0.71.0".into(),
            published_at: Some("2026-08-14T06:36:29Z".into()),
            asset: api::github::Asset {
                name: "frp_0.71.0_linux_amd64.tar.gz".into(),
                url: "https://example.invalid/frp.tar.gz".into(),
                size: Some(13_932_092),
                sha256: "a".repeat(64),
            },
        };
        state
            .ready()
            .unwrap()
            .releases
            .put("latest", Arc::new(vec![release]));

        let value = versions(&state, &call_ctx(json!({ "provider": "frp" })))
            .await
            .unwrap();
        assert_eq!(value["provider"], json!("frp"));
        assert_eq!(value["package_type"], json!("frpc"));
        // 默认只要最新 —— 前端靠这个决定要不要显示「历史版本」按钮
        assert_eq!(value["all"], json!(false));
        assert_eq!(value["versions"].as_array().unwrap().len(), 1);
        assert_eq!(value["versions"][0]["version"], json!("0.71.0"));
        // frp 的版本前缀是空的（`Java ` 那种前缀只有 Zulu 要）
        assert_eq!(value["versions"][0]["label"], json!("0.71.0"));
        // 副行是发布日期，不是完整版本串
        assert_eq!(value["versions"][0]["subtitle"], json!("2026-08-14"));
    }

    // ── 重启收拾 ──────────────────────────────────────────────────────────

    fn busy_env(size: Option<u64>) -> Env {
        let mut env = Env {
            id: "zulu-jdk-21-linux-x64".into(),
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
            sha256: Some("a".repeat(64)),
            md5: None,
            size,
            support_term: Some("lts".into()),
            build_date: None,
            state: EnvState::Downloading,
            stage: None,
            error: None,
            task_id: Some("task".into()),
            home: None,
            binary: None,
            created_at_ms: 1,
            installed_at_ms: None,
            updated_at_ms: 1,
        };
        env.state = EnvState::Extracting;
        env
    }

    #[test]
    fn restart_turns_busy_environments_into_failed_and_keeps_task_id_out_of_the_way() {
        let mut env = busy_env(Some(1000));
        assert!(recover_after_restart(&mut env, Some(1000)));

        assert_eq!(env.state, EnvState::Failed);
        assert_eq!(
            env.stage,
            Some(Stage::Extract),
            "包已经下完了（大小对得上），重试应当直接解压"
        );
        assert_eq!(env.task_id, None, "任务早就不存在了，留着只会让前端空等");
        assert!(env.error.is_some());
    }

    #[test]
    fn restart_falls_back_to_download_when_the_archive_is_incomplete() {
        let mut env = busy_env(Some(1000));
        // 大小对不上 = 还在下载中被打断
        assert!(recover_after_restart(&mut env, Some(400)));
        assert_eq!(env.stage, Some(Stage::Download));

        // 上游没给 size / 压缩包根本不在 → 同样按「重新下载」算，宁可多下一次
        let mut env = busy_env(None);
        recover_after_restart(&mut env, Some(1000));
        assert_eq!(env.stage, Some(Stage::Download));
    }

    #[test]
    fn restart_leaves_settled_environments_alone() {
        for state in [EnvState::Installed, EnvState::Failed] {
            let mut env = busy_env(Some(1000));
            env.state = state;
            env.stage = Some(Stage::Extract);
            assert!(!recover_after_restart(&mut env, Some(1000)));
            assert_eq!(env.state, state, "已经落定的状态不该被重启改写");
        }
    }

    // ── 安装全流程（下载 → 解压 → 落元数据）─────────────────────────────
    //
    // 上游不打真的：Zulu 一个包 200 MB，夹具用不起。所以 `install` 拆成了
    // 「问上游」与 `begin_install` 两半，这里测的是**后半段整条**，
    // 下载源是本地 HTTP 服务。

    /// 一个用完就删的临时数据根。
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "edgecube-runtime-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        /// 造一个「Zulu 那样」的 tar.gz：一个顶层目录 + `bin/java`（0755）。
        /// frp 形状的包：顶层目录里直接躺 `frpc` / `frps`（实测的实干包长这样）。
        fn make_frp_archive(&self, top: &str) -> Vec<u8> {
            use flate2::Compression;
            use flate2::write::GzEncoder;

            let buffer = std::io::Cursor::new(Vec::new());
            let encoder = GzEncoder::new(buffer, Compression::default());
            let mut builder = tar::Builder::new(encoder);

            for name in ["frpc", "frps"] {
                let mut header = tar::Header::new_gnu();
                header.set_size(4);
                header.set_mode(0o755);
                header.set_cksum();
                builder
                    .append_data(&mut header, format!("{top}/{name}"), &b"bin!"[..])
                    .unwrap();
            }

            builder.into_inner().unwrap().finish().unwrap().into_inner()
        }

        fn make_archive(&self, top: &str, with_java: bool) -> Vec<u8> {
            use flate2::Compression;
            use flate2::write::GzEncoder;

            let buffer = std::io::Cursor::new(Vec::new());
            let encoder = GzEncoder::new(buffer, Compression::default());
            let mut builder = tar::Builder::new(encoder);

            let mut header = tar::Header::new_gnu();
            if with_java {
                header.set_size(4);
                header.set_mode(0o755);
                header.set_cksum();
                builder
                    .append_data(&mut header, format!("{top}/bin/java"), &b"java"[..])
                    .unwrap();
            }
            let mut header = tar::Header::new_gnu();
            header.set_size(7);
            header.set_mode(0o644);
            header.set_cksum();
            builder
                .append_data(&mut header, format!("{top}/release"), &b"release"[..])
                .unwrap();

            builder.into_inner().unwrap().finish().unwrap().into_inner()
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// 本机是否把回环也塞进了代理（gosh-dl 的 reqwest 会读环境变量）。
    fn loopback_is_proxied() -> bool {
        let proxy = std::env::var("HTTP_PROXY")
            .or_else(|_| std::env::var("http_proxy"))
            .unwrap_or_default();
        if proxy.trim().is_empty() {
            return false;
        }
        let no_proxy = std::env::var("NO_PROXY")
            .or_else(|_| std::env::var("no_proxy"))
            .unwrap_or_default();
        !no_proxy
            .split(',')
            .any(|item| matches!(item.trim(), "127.0.0.1" | "localhost" | "::1" | "*"))
    }

    /// 一台只服务一个文件的极简 HTTP 服务，返回它的 URL。
    async fn serve_file(body: Vec<u8>) -> String {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("应当能监听回环端口");
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                let body = body.clone();
                tokio::spawn(async move {
                    let mut scratch = [0u8; 2048];
                    let _ = socket.read(&mut scratch).await;
                    let head = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n\
                         Content-Length: {}\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = socket.write_all(head.as_bytes()).await;
                    let _ = socket.write_all(&body).await;
                    let _ = socket.flush().await;
                });
            }
        });

        format!("http://{addr}/zulu.tar.gz")
    }

    /// 起「runtime + 一只真实下载引擎」，共用同一个 AppState。
    async fn start_runtime(
        data_dir: &Path,
    ) -> (
        Arc<RuntimeState>,
        download::Queue,
        AppState,
        CancellationToken,
    ) {
        let http = fetch::build_client(10).expect("客户端应当能建");
        store::ensure_dirs(data_dir).expect("应当能建目录");

        let state = Arc::new(RuntimeState::default());
        let _ = state.ready.set(Ready {
            http,
            data_dir: data_dir.to_path_buf(),
            releases: Cache::new(60),
        });

        let queue_state = download::QueueState::test_queue(data_dir)
            .await
            .expect("队列应当能起来");
        (
            state,
            download::Queue::from_state(queue_state),
            test_app(),
            CancellationToken::new(),
        )
    }

    /// 一分「上游已经解析完」的结果（`run_download_with` 的输入）。
    ///
    /// 造这个而不是 Azul 的 `Detail`，是因为下载那一段现在与厂商无关 ——
    /// 夹具也跟着不依赖某一家的响应形状。
    fn resolved(file_name: &str, url: String, sha256: String) -> install::Resolved {
        install::Resolved {
            version: "21".into(),
            version_name: "21.0.12.1".into(),
            vendor_version: "21.52.203".into(),
            upstream_id: "11111111-2222-3333-4444-555555555555".into(),
            file_name: file_name.into(),
            url,
            sha256,
            md5: None,
            size: Some(1000),
            support_term: None,
            build_date: None,
        }
    }

    fn target() -> model::Target {
        // 测试里固定用 linux/x64 的口径（id 与文件名都从它拼出来）；
        // 在别的平台上跑测试也没关系 —— `begin_install` 不打上游、不解压到
        // 真实平台相关的地方，解压结果按 `detail` 里的 archive_type 走。
        model::Target {
            os: "linux",
            query_os: "linux-glibc",
            arch: "x64",
            archive_type: "tar.gz",
            libc: Some("glibc"),
        }
    }

    /// 轮询直到环境进入给定状态（本地下载 + 解压在几秒内该完成）。
    /// 夹具压缩包的 sha256（十六进制小写，与 `download.add` 的算法名一致）。
    fn sha256_of(bytes: &[u8]) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(bytes);
        hasher
            .finalize()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }

    fn archive_len(bytes: &[u8]) -> u64 {
        bytes.len() as u64
    }

    /// 下载 → 解压整条：**不打上游**（`run_download_with` 从「详情已拿到」开始），
    /// 所以能用本地 HTTP 源把「落元数据 → 下载 → 解压 → 找 bin/java」跑通。
    #[tokio::test]
    async fn flow_downloads_then_extracts() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempDir::new("install");
        let top = "zulu21.52.203-ca-jdk21.0.12.1-linux_x64";
        let archive = temp.make_archive(top, true);
        let sha256 = sha256_of(&archive);
        let url = serve_file(archive).await;

        let (_state, queue, app, cancel) = start_runtime(&temp.0).await;

        // 1) 下载步骤：落元数据 + 把包下到暂存目录
        let downloaded = install::run_download_with(
            &queue,
            &temp.0,
            &target(),
            model::find_provider("zulu").unwrap(),
            "jdk",
            resolved(
                "zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz",
                url,
                sha256,
            ),
            &app,
            &cancel,
            &|_| {},
        )
        .await
        .expect("下载应当成功");
        assert_eq!(downloaded["resumed"], json!(false));
        let id = downloaded["id"].as_str().unwrap().to_string();
        assert_eq!(id, "zulu-jdk-21-linux-x64");

        // 下载完、还没解压：记录仍是 downloading，这正是「两步」的意义
        let mid = store::load(&temp.0, &id).expect("下载阶段就该有记录了");
        assert_eq!(mid.state, EnvState::Downloading);
        assert!(
            store::staging_dir(&temp.0, &id)
                .join(&mid.file_name)
                .is_file(),
            "包应当落在暂存目录里"
        );

        // 2) 解压步骤
        let archive_path = PathBuf::from(downloaded["archive"].as_str().unwrap());
        let env = install::extract_core(&temp.0, &id, &archive_path, &app)
            .await
            .expect("解压应当成功");

        // home / binary 指到解压出来的那一份，且是**相对路径**
        assert_eq!(env.home.as_deref(), Some(top));
        assert_eq!(
            env.binary.as_deref(),
            Some(format!("{top}/bin/java").as_str())
        );
        assert_eq!(env.state, EnvState::Installed);
        assert!(env.installed_at_ms.is_some());
        assert_eq!(env.task_id, None, "装完了就别留着，免得前端空等");

        // 文件真的在、可执行位真的留着；压缩包真的删了
        let java = store::env_dir(&temp.0, &id).join(top).join("bin/java");
        assert_eq!(std::fs::read(&java).unwrap(), b"java");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&java).unwrap().permissions().mode();
            assert_eq!(mode & 0o111, 0o111, "bin/java 必须可执行（{mode:o}）");
        }
        assert!(!store::staging_dir(&temp.0, &id).exists());
    }

    /// frp 整条：下载 → 解压 → 找到 `frpc`（**不是** `bin/java`）。
    ///
    /// 这条用例同时钉住「同一份下载/解压代码能吃下第二个厂商」——
    /// 上游解析被绕开了（`run_download_with` 从「已解析」开始），
    /// 但落元数据、目录布局、找可执行文件、落终态都是真的。
    #[tokio::test]
    async fn flow_installs_frp_and_finds_the_frpc_binary() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempDir::new("frp");
        let top = "frp_0.71.0_linux_amd64";
        let archive = temp.make_frp_archive(top);
        let sha256 = sha256_of(&archive);
        let url = serve_file(archive).await;
        let file_name = "frp_0.71.0_linux_amd64.tar.gz";

        let (_state, queue, app, cancel) = start_runtime(&temp.0).await;
        let provider = model::find_provider("frp").expect("frp 在厂商表里");

        let downloaded = install::run_download_with(
            &queue,
            &temp.0,
            &target(),
            provider,
            "frpc",
            install::Resolved {
                version: "0.71.0".into(),
                version_name: "0.71.0".into(),
                vendor_version: String::new(),
                upstream_id: "v0.71.0".into(),
                file_name: file_name.to_string(),
                url,
                sha256,
                md5: None,
                size: Some(1000),
                support_term: None,
                build_date: Some("2026-08-14".into()),
            },
            &app,
            &cancel,
            &|_| {},
        )
        .await
        .expect("下载应当成功");

        let id = downloaded["id"].as_str().unwrap().to_string();
        // 版本是字符串（semver），不再是数字
        assert_eq!(id, "frp-frpc-0.71.0-linux-x64");

        let archive_path = std::path::PathBuf::from(downloaded["archive"].as_str().unwrap());
        let env = install::extract_core(&temp.0, &id, &archive_path, &app)
            .await
            .expect("解压应当成功");

        assert_eq!(env.vendor, "frp");
        assert_eq!(env.version, "0.71.0");
        // 家目录是那一层、可执行文件是 frpc（而不是 JDK 的 bin/java）
        assert_eq!(env.home.as_deref(), Some(top));
        assert_eq!(env.binary.as_deref(), Some(format!("{top}/frpc").as_str()));
        assert_eq!(env.state, EnvState::Installed);

        let frpc = store::env_dir(&temp.0, &id).join(top).join("frpc");
        assert_eq!(std::fs::read(&frpc).unwrap(), b"bin!");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&frpc).unwrap().permissions().mode();
            assert_eq!(mode & 0o111, 0o111, "frpc 必须可执行（{mode:o}）");
        }
        // frps 也在同一个包里（自建服务端将来要用）
        assert!(
            store::env_dir(&temp.0, &id)
                .join(top)
                .join("frps")
                .is_file()
        );
    }

    /// **整条 flow 走真引擎**：这条用例是冲着「步骤之间怎么传产出」来的。
    ///
    /// 前面几条直接调 `run_download_with` / `extract_core`，绕开了引擎 ——
    /// 于是 `env.output(...)` 用错键（`step_type` 而不是步骤名）这种错**测不出来**，
    /// 而它恰恰是最难查的一类：上游明明成功了，下游报「上一步没有产出」。
    /// 实测就是在真跑一次之后才暴露的，所以这里补上。
    #[tokio::test]
    async fn the_whole_flow_runs_through_the_engine() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempDir::new("engine-frp");
        let top = "frp_0.71.0_linux_amd64";
        let archive = temp.make_frp_archive(top);
        let sha256 = sha256_of(&archive);
        let url = serve_file(archive).await;

        let (state, queue, app, _cancel) = start_runtime(&temp.0).await;

        // 离线：把「上游已经解析好」的结果**预置进缓存**，于是整条流程不碰 GitHub。
        // 真实上游只差这一层（`api::github` 的解析有自己的单测）。
        let host = model::host_target().expect("本机平台应当认得出来");
        state.ready().unwrap().releases.put(
            "latest",
            Arc::new(vec![api::github::Version {
                version: "0.71.0".into(),
                tag: "v0.71.0".into(),
                published_at: Some("2026-08-14T06:36:29Z".into()),
                asset: api::github::Asset {
                    name: format!("frp_0.71.0_{}_{}.{}", host.os, host.arch, host.archive_type),
                    url,
                    size: None,
                    sha256,
                },
            }]),
        );

        // 队列与注册表都从 `AppState` 的跨模块槽里拿 —— 这正是 services 的用法
        let _ = app.services.insert(Arc::new(queue));
        install::register(&state, &app);

        let runner = Arc::new(crate::module::builtin::task::runner::TaskRunner::new(
            app.clone(),
            Default::default(),
            crate::module::builtin::task::flows::registry(&app),
        ));
        let submitted = runner
            .submit(
                "runtime-install",
                json!({ "provider": "frp", "version": "0.71.0" }),
            )
            .expect("提交应当成功");
        let id = submitted["id"].as_str().unwrap().to_string();

        // 等终态
        let mut view = submitted;
        for _ in 0..200 {
            if matches!(
                view["state"].as_str(),
                Some("completed") | Some("failed") | Some("cancelled")
            ) {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            view = runner.view(&id).expect("任务应当还在");
        }

        assert_eq!(view["state"], json!("completed"), "{view}");
        assert_eq!(view["steps"][0]["status"], json!("completed"), "{view}");
        assert_eq!(view["steps"][1]["status"], json!("completed"), "{view}");

        // 落盘的东西对：frpc 在、可执行
        let env = store::load(&temp.0, "frp-frpc-0.71.0-linux-x64").expect("应当装好了");
        assert_eq!(env.state, EnvState::Installed);
        assert_eq!(env.binary.as_deref(), Some(format!("{top}/frpc").as_str()));
        let frpc = store::env_dir(&temp.0, "frp-frpc-0.71.0-linux-x64")
            .join(top)
            .join("frpc");
        assert!(frpc.is_file(), "frpc 应当落在环境目录里");
    }

    /// 校验不过时不但要失败，还要**把半截产物清干净**（用户要求「彻底清干净」）。
    #[tokio::test]
    async fn flow_cleans_up_when_the_checksum_does_not_match() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempDir::new("badsum");
        let archive = temp.make_archive("zulu21", true);
        let url = serve_file(archive).await;
        let (_state, queue, app, cancel) = start_runtime(&temp.0).await;

        let failed = install::run_download_with(
            &queue,
            &temp.0,
            &target(),
            model::find_provider("zulu").unwrap(),
            "jdk",
            resolved("zulu21.tar.gz", url, "0".repeat(64)),
            &app,
            &cancel,
            &|_| {},
        )
        .await;
        assert!(failed.is_err(), "校验值不对必须失败");

        // 失败态落盘了（列表里看得见原因），且暂存目录被清掉
        let env = store::load(&temp.0, "zulu-jdk-21-linux-x64").expect("失败也要留记录");
        assert_eq!(env.state, EnvState::Failed);
        assert_eq!(env.stage, Some(Stage::Download));
        assert!(env.error.is_some(), "失败原因要写进记录里");
        assert!(
            !store::staging_dir(&temp.0, "zulu-jdk-21-linux-x64").exists(),
            "半截的压缩包不该留"
        );
    }

    /// 暂存里的包还对得上（stage=extract 且 sha256 一致）时跳过下载。
    #[tokio::test]
    async fn flow_resumes_extraction_when_the_staged_archive_still_matches() {
        let temp = TempDir::new("resume");
        let top = "zulu21.52.203-ca-jdk21.0.12.1-linux_x64";
        let archive = temp.make_archive(top, true);
        let sha256 = sha256_of(&archive);
        let file_name = "zulu21.tar.gz";

        let (_state, queue, app, cancel) = start_runtime(&temp.0).await;

        // 造一份「上一轮下载完了、死在解压」的记录 + 暂存里的包
        let saved = {
            let env = Env {
                id: "zulu-jdk-21-linux-x64".into(),
                vendor: "zulu".into(),
                package_type: "jdk".into(),
                version: "21".into(),
                version_name: "21.0.12.1".into(),
                vendor_version: "21.52.203".into(),
                os: target().os.to_string(),
                arch: target().arch.to_string(),
                archive_type: target().archive_type.to_string(),
                package_uuid: "11111111-2222-3333-4444-555555555555".into(),
                file_name: file_name.into(),
                url: "http://127.0.0.1:1/never.tar.gz".into(),
                sha256: Some(sha256.clone()),
                md5: None,
                size: Some(archive_len(&archive)),
                support_term: None,
                build_date: None,
                state: EnvState::Failed,
                stage: Some(Stage::Extract),
                error: None,
                task_id: None,
                home: None,
                binary: None,
                created_at_ms: 1,
                installed_at_ms: None,
                updated_at_ms: 1,
            };
            store::save(&temp.0, &env).unwrap();
            env
        };
        let staging = store::staging_dir(&temp.0, &saved.id);
        std::fs::create_dir_all(&staging).unwrap();
        std::fs::write(staging.join(file_name), &archive).unwrap();

        // 下载地址指向一个**没人监听的端口**：真去下载必然失败，
        // 所以只要结果 resumed=true，就说明这一次没有下载
        let downloaded = install::run_download_with(
            &queue,
            &temp.0,
            &target(),
            model::find_provider("zulu").unwrap(),
            "jdk",
            resolved(file_name, saved.url.clone(), sha256),
            &app,
            &cancel,
            &|_| {},
        )
        .await
        .expect("暂存可用时应当直接跳过下载");

        assert_eq!(downloaded["resumed"], json!(true));
        let mid = store::load(&temp.0, &saved.id).unwrap();
        assert_eq!(mid.state, EnvState::Extracting, "应当直接进入解压");

        let archive_path = PathBuf::from(downloaded["archive"].as_str().unwrap());
        let env = install::extract_core(&temp.0, &saved.id, &archive_path, &app)
            .await
            .expect("解压应当成功");
        assert_eq!(
            env.binary.as_deref(),
            Some(format!("{top}/bin/java").as_str())
        );
    }
}
