//! 「下载 → 解压」工作流（`runtime-install`）。
//!
//! 以前是一次 `runtime.install` 调用里在 daemon 侧自己 spawn 一个后台任务把
//! 两件事做完。现在拆成工作流的两个步骤，好处是**两件事各自可见**：
//! 前端能从任务对象里看到「正在下载」还是「正在解压」、下载进度是多少、
//! 失败在哪一步，而不是只有一个笼统的 `state=downloading`。
//!
//! ```text
//! download（解析上游 + 抢占位 + 落元数据 + 交给下载队列并等到下完）
//!   ↓ output: id / archive
//! extract（解压 → 找可执行文件 → 落终态）
//! ```
//!
//! ## 两家厂商、一条路径
//!
//! JDK 与 frp 的上游完全不同（Azul 的「一个版本一个包」vs GitHub 的
//! 「一个 release 里十几个平台的产物」），但**下游是一模一样的**：
//! 落元数据 → 交给下载队列 → 解压 → 找一个可执行文件。
//!
//! 所以这里在两处收口：
//!
//! * [`resolve`] 把各家的响应压成同一个 [`Resolved`]（上游告诉我们的一切）；
//! * 解压后找哪个文件由 [`model::Provider::launcher`] 描述，
//!   [`extract::find_binary`] 只有一份实现。
//!
//! 加第三家厂商要动的就是这两处 + [`api`](super::api) 下那个适配器。
//!
//! ## 并发挡板
//!
//! 「同一个环境并发装两次」会给同一份包互相覆盖，所以解析出 id 就抢一个
//! `RunningGuard` 占位。**占位放在任务级暂存（`StepEnv::scratch`）里**，
//! 于是它的生命周期天然等于这个任务 —— 任务一结束（成功 / 失败 / 取消）
//! 暂存表析构，guard drop，占位摘掉。不需要任何「收尾步骤」或钩子。
//!
//! ## 失败清理
//!
//! 用户要求「彻底清干净」：**半截的解压目录与暂存压缩包一起删掉**。
//! 两条路径都覆盖：
//!
//! * 下载阶段失败 → [`run_download`] 的失败分支直接清；
//! * 解压阶段失败 → `download` 步骤的**回滚**清（`flow.rollback_on_failure` +
//!   `download` 标 `rollbackable`）。
//!
//! 元数据记录**保留为 `failed`** —— `runtime.list` 里看得见它和失败原因，
//! 用户知道刚才发生了什么；「删除」这个动作仍然归用户（`runtime.delete`）。
//!
//! 注意**取消不触发回滚**（szal 的语义：skipped ≠ failed）：用户主动取消时
//! 半截产物会留下，需要自己删。这与实例那条流程的取舍一致。
//!
//! ## 为什么核心逻辑拆成 `*_with` / `*_core`
//!
//! 上游是真的（Zulu 一个包 200 MB、frp 一个包 14 MB，而且 GitHub 有配额），
//! 测试没法当夹具。所以每一步都拆成「解析输入」与「拿到输入之后干活」两半，
//! 后者**不打上游**，测试直接调它，就能用本地 HTTP 源把整条链路跑通
//! （见 `mod.rs` 里那几条 `flow_*` 测试）。

use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde_json::{Value, json};
use szal::flow::{FlowDef, FlowMode};
use szal::step::StepDef;

use super::api::{azul, github};
use super::model::{self, Env, EnvState, Provider, Stage, Target};
use super::{
    CODE_BUSY, CODE_PROVIDER_NOT_FOUND, CODE_TYPE_NOT_FOUND, CODE_VERSION_NOT_FOUND,
    CODE_VERSION_REQUIRED, DEFAULT_PROVIDER, Ready, RunningGuard, RuntimeState, extract,
    host_target, map_fetch_error, now_ms, owns_record, save_and_publish, store,
};
use crate::module::builtin::download::{self, InternalRequest, Owner};
use crate::module::builtin::task::flows::{
    self, FlowStepInfo, FlowTemplate, StepEnv, StepSpec, TIMEOUT_UNLIMITED,
};
use crate::state::AppState;

/// 工作流名（`task.submit` 的 `flow`）。
pub const FLOW: &str = "runtime-install";

/// 步骤**类型**（注册表里的键，也是 `StepDef` 的 `step_type`）。
const STEP_DOWNLOAD: &str = "runtime.download";
const STEP_EXTRACT: &str = "runtime.extract";

/// 步骤在 flow 里的**名字**。
///
/// **`StepEnv::output(..)` 用的是名字，不是 `step_type`** —— 产出表是按
/// `StepDef.name` 建的（同一个步骤类型可以在一条 flow 里出现多次，名字才是唯一的）。
/// 这两者混用会得到「上一步没有产出压缩包」这种下游报错、而上游明明成功了，
/// 而且回滚也一起失联（它同样按名字取产出）—— 实测踩过。
const NAME_DOWNLOAD: &str = "download";
const NAME_EXTRACT: &str = "extract";

/// 暂存里放 `RunningGuard` 的键（见模块注释）。
const GUARD_KEY: &str = "runtime.running_guard";

/// 把这条工作流挂到任务系统的注册表里。`start()` 里调。
pub(super) fn register(state: &Arc<RuntimeState>, app: &AppState) {
    if !crate::module::builtin::task::enabled(app) {
        tracing::debug!("task 模块未启用，`{FLOW}` 工作流跳过注册");
        return;
    }

    let registry = flows::registry(app);
    registry.register_step_or_warn(STEP_DOWNLOAD, download_step(state.clone()));
    registry.register_step_or_warn(STEP_EXTRACT, extract_step(state.clone()));
    registry.register_flow_or_warn(FLOW, template());
}

// ---------------------------------------------------------------------------
// 上游解析：两家厂商 → 同一个 Resolved
// ---------------------------------------------------------------------------

/// 「上游告诉我们的一切」。
///
/// 两家厂商的响应形状差得很远（Azul 要问两次、GitHub 一次就全给），但**下游
/// 需要的东西是一样的**，就这九项。收口在这儿，落元数据与下载那段就与厂商无关了。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Resolved {
    /// 进 id 的版本：Zulu 的 `21`，frp 的 `0.71.0`。
    pub version: String,
    /// 更完整的版本串（展示副标题）：Zulu 的 `21.0.12.1`；frp 与 `version` 相同。
    pub version_name: String,
    /// 厂商自己的版本号（Zulu 的 `21.52.203`）。frp 没有这一层，空串。
    pub vendor_version: String,
    /// 上游的包标识：Zulu 是 `package_uuid`，frp 是 release tag（`v0.71.0`）。
    pub upstream_id: String,
    pub file_name: String,
    pub url: String,
    /// **一定有** —— 没有就拒绝下载（两家都是这条规矩）。
    pub sha256: String,
    pub md5: Option<String>,
    pub size: Option<u64>,
    /// 支持期 / 构建日期之类的额外信息，展示用。
    pub support_term: Option<String>,
    pub build_date: Option<String>,
}

/// 按厂商把上游解析成 [`Resolved`]。
async fn resolve(
    ready: &Ready,
    target: &Target,
    provider: &'static Provider,
    package_type: &'static str,
    version: &str,
) -> Result<Resolved, String> {
    match provider.id {
        "frp" => resolve_frp(ready, target, version).await,
        // 默认走 Zulu（也是唯一剩下的那个）
        _ => resolve_zulu(ready, target, package_type, version).await,
    }
}

/// Zulu：清单（找大版本）→ 详情（校验值 / 体积 / 平台核对）。
async fn resolve_zulu(
    ready: &Ready,
    target: &Target,
    package_type: &str,
    version: &str,
) -> Result<Resolved, String> {
    let list = azul::versions(&ready.http, target, package_type)
        .await
        .map_err(|e| rpc_message(map_fetch_error(e)))?;
    let Some(found) = list.iter().find(|v| v.java_major.to_string() == version) else {
        return Err(format!(
            "{}：Zulu 没有 Java {version}（可选：{}）",
            CODE_VERSION_NOT_FOUND,
            list.iter()
                .map(|v| v.java_major.to_string())
                .collect::<Vec<_>>()
                .join(", ")
        ));
    };

    let detail = azul::detail(&ready.http, target, &found.package_uuid)
        .await
        .map_err(|e| rpc_message(map_fetch_error(e)))?;

    Ok(Resolved {
        version: detail.java_major.to_string(),
        version_name: detail.java_version.clone(),
        vendor_version: detail.vendor_version.clone(),
        upstream_id: detail.package_uuid.clone(),
        file_name: detail.file_name.clone(),
        url: detail.download_url.clone(),
        sha256: detail.sha256.clone(),
        md5: detail.md5.clone(),
        size: detail.size,
        support_term: detail.support_term.clone(),
        build_date: detail.build_date.clone(),
    })
}

/// frp：先在「最新那个」里找（多半就命中，命中不了 0 次额外请求），
/// 找不到再拉历史列表找。
///
/// 这样安排是因为默认场景就是「装最新版」：`versions(all: false)` 已经把
/// 最新那个缓存下来了，装它时一次上游请求都不用发。
async fn resolve_frp(ready: &Ready, target: &Target, version: &str) -> Result<Resolved, String> {
    let latest = if let Some(hit) = ready.releases.get("latest") {
        hit
    } else {
        let fetched = Arc::new(vec![
            github::latest(&ready.http, target)
                .await
                .map_err(|e| rpc_message(map_fetch_error(e)))?,
        ]);
        ready.releases.put("latest", fetched.clone());
        fetched
    };

    if let Some(found) = latest.iter().find(|r| r.version == version) {
        return Ok(frp_resolved(found));
    }

    // 老版本（用户点了「历史版本」选的）。列表也有缓存，所以连着装两个老版本
    // 不会连着打两次 GitHub。
    let history = if let Some(hit) = ready.releases.get("history") {
        hit
    } else {
        let fetched = Arc::new(
            github::history(&ready.http, target)
                .await
                .map_err(|e| rpc_message(map_fetch_error(e)))?,
        );
        ready.releases.put("history", fetched.clone());
        fetched
    };

    let Some(found) = history.iter().find(|r| r.version == version) else {
        return Err(format!(
            "{}：frp 的最近版本里没有 `{version}`（可选：{}）",
            CODE_VERSION_NOT_FOUND,
            history
                .iter()
                .map(|r| r.version.clone())
                .collect::<Vec<_>>()
                .join(", ")
        ));
    };
    Ok(frp_resolved(found))
}

fn frp_resolved(release: &github::Version) -> Resolved {
    Resolved {
        version: release.version.clone(),
        // GitHub 上只有一个版本号，没有「更完整的」那一层
        version_name: release.version.clone(),
        vendor_version: String::new(),
        upstream_id: release.tag.clone(),
        file_name: release.asset.name.clone(),
        url: release.asset.url.clone(),
        sha256: release.asset.sha256.clone(),
        md5: None,
        size: release.asset.size,
        support_term: None,
        build_date: release.published_at.as_deref().map(super::published_date),
    }
}

// ---------------------------------------------------------------------------
// 步骤「下载」
// ---------------------------------------------------------------------------

fn download_step(state: Arc<RuntimeState>) -> StepSpec {
    let rollback_state = state.clone();
    StepSpec {
        title: "下载运行环境".into(),
        run: Arc::new(move |step, progress, env| {
            let state = state.clone();
            Box::pin(async move { run_download(&state, &step, &env, |f| progress.report(f)).await })
        }),
        // 回滚 = 解压失败之后的彻底清理（见模块注释的「失败清理」）
        rollback: Some(Arc::new(move |_step, env| {
            let state = rollback_state.clone();
            Box::pin(async move { rollback_download(&state, &env).await })
        })),
    }
}

/// 步骤本体：解析厂商/类型/版本 → 打上游 → 交给核心逻辑。
///
/// 任何失败都走 [`cleanup_failed`]，保证「不留半截产物 + 元数据落失败态」。
async fn run_download(
    state: &Arc<RuntimeState>,
    step: &StepDef,
    env: &StepEnv,
    report: impl Fn(Value) + Send + Sync,
) -> Result<Value, String> {
    let ready = state.ready().map_err(rpc_message)?;
    let data_dir = ready.data_dir.clone();
    let target = host_target().map_err(rpc_message)?;

    // ── 厂商 / 包类型 / 版本（都是表校验，不打上游）──
    let (provider, package_type) = read_kind(step)?;
    let version = read_version(step)?;

    let id = model::env_id(provider.id, package_type, &version, &target);

    // ── 并发挡板：抢不到说明已经有一轮在装这个 id 了 ──
    {
        let mut running = state.running.lock().unwrap_or_else(|e| e.into_inner());
        if !running.insert(id.clone()) {
            return Err(format!("{}：`{id}` 正在安装中，等它结束再试", CODE_BUSY));
        }
    }
    // 占位交给**任务级暂存**：任务一结束（含取消）自动摘掉，不用收尾钩子
    env.scratch_put(
        GUARD_KEY,
        RunningGuard {
            state: state.clone(),
            id: id.clone(),
        },
    );

    report(json!({ "percent": null, "message": "正在查询可用版本" }));
    let resolved = match resolve(ready, &target, provider, package_type, &version).await {
        Ok(resolved) => resolved,
        Err(message) => {
            cleanup_failed(&data_dir, &env.app, &id, Stage::Download, message.clone());
            return Err(message);
        }
    };

    // ── 核心：不打上游的那一半 ──
    match run_download_with(
        &download::queue_of(&env.app).ok_or_else(|| "下载队列尚未就绪".to_string())?,
        &data_dir,
        &target,
        provider,
        package_type,
        resolved,
        &env.app,
        &env.cancel,
        &report,
    )
    .await
    {
        Ok(value) => Ok(value),
        Err(message) => {
            cleanup_failed(&data_dir, &env.app, &id, Stage::Download, message.clone());
            Err(message)
        }
    }
}

/// 从「上游已经解析完」开始把下载做完。**不打上游**，所以测试能用本地 HTTP 源
/// 把「下载 → 落元数据」整条跑通。
///
/// 返回值交给下一步（`extract`）：`{ id, archive, file_name, resumed }`。
/// 失败时也在这里把自己造的烂摊子收了（清暂存 + 落失败态）。
#[allow(clippy::too_many_arguments)]
pub(super) async fn run_download_with(
    queue: &download::Queue,
    data_dir: &Path,
    target: &Target,
    provider: &'static Provider,
    package_type: &'static str,
    resolved: Resolved,
    app: &AppState,
    cancel: &tokio_util::sync::CancellationToken,
    report: &(impl Fn(Value) + Send + Sync),
) -> Result<Value, String> {
    let id = model::env_id(provider.id, package_type, &resolved.version, target);
    let now = now_ms();
    let mut record = Env {
        id: id.clone(),
        vendor: provider.id.to_string(),
        package_type: package_type.to_string(),
        version: resolved.version.clone(),
        version_name: resolved.version_name.clone(),
        vendor_version: resolved.vendor_version.clone(),
        os: target.os.to_string(),
        arch: target.arch.to_string(),
        archive_type: target.archive_type.to_string(),
        package_uuid: resolved.upstream_id.clone(),
        file_name: resolved.file_name.clone(),
        url: resolved.url.clone(),
        sha256: Some(resolved.sha256.clone()),
        md5: resolved.md5.clone(),
        size: resolved.size,
        support_term: resolved.support_term.clone(),
        build_date: resolved.build_date.clone(),
        state: EnvState::Downloading,
        stage: None,
        error: None,
        task_id: None,
        home: None,
        binary: None,
        created_at_ms: now,
        installed_at_ms: None,
        updated_at_ms: now,
    };

    let staging = store::staging_dir(data_dir, &id);

    // 上一轮留下「下载完了但没解压」的包？核对 sha256 后跳过下载。
    // **必须核对**：隔几天上游可能出了新构建，暂存那份是旧的，拿它解压出来的
    // 东西与刚写下的元数据对不上。
    let resumable = store::load(data_dir, &id)
        .filter(|previous| previous.stage == Some(Stage::Extract))
        .filter(|previous| previous.sha256.as_deref() == Some(resolved.sha256.as_str()))
        .map(|previous| staging.join(&previous.file_name))
        .filter(|archive| archive.is_file());

    if let Some(archive) = resumable {
        record.state = EnvState::Extracting;
        save_and_publish(data_dir, app, &record).map_err(rpc_message)?;
        tracing::info!(env = %id, archive = %archive.display(), "暂存里的包还能用，跳过下载直接解压");
        return Ok(json!({
            "id": id,
            "archive": archive.display().to_string(),
            "file_name": record.file_name,
            "resumed": true,
        }));
    }

    // 顺序刻意：先有记账再有下载任务，否则「下载提交成功但没记账」会留下
    // 一条谁也管不着的下载。
    save_and_publish(data_dir, app, &record).map_err(rpc_message)?;

    let file_name = record.file_name.clone();
    let url = record.url.clone();

    let downloaded = download::fetch(
        queue,
        app,
        InternalRequest {
            dir: staging,
            filename: file_name.clone(),
            url,
            checksum: Some(("sha256", resolved.sha256.clone())),
            owner: Owner::Runtime {
                runtime_id: id.clone(),
            },
        },
        cancel,
        // 提交成功就先把队列任务 id 记下来：前端拿 `env.task_id` 订
        // `download.progress`，等下载结束再写就太晚了。
        |task_id| {
            super::mutate(data_dir, app, &id, |record| {
                record.task_id = Some(task_id.to_string());
            });
        },
        report,
    )
    .await;

    match downloaded {
        Ok(path) => {
            tracing::info!(env = %id, file = %file_name, "运行环境下载完成");
            Ok(json!({
                "id": id,
                "archive": path.display().to_string(),
                "file_name": file_name,
                "resumed": false,
            }))
        }
        Err(message) => {
            cleanup_failed(data_dir, app, &id, Stage::Download, message.clone());
            Err(message)
        }
    }
}

/// `download` 步骤的回滚：解压失败之后的彻底清理。
///
/// 用户要求「彻底清干净」—— 半截的解压目录与暂存压缩包一起删，元数据留
/// `failed`（`runtime.list` 里能看到失败原因）。
async fn rollback_download(state: &Arc<RuntimeState>, env: &StepEnv) -> Result<(), String> {
    let Some(downloaded) = env.output(NAME_DOWNLOAD).await else {
        return Ok(());
    };
    let Some(id) = downloaded.get("id").and_then(Value::as_str) else {
        return Ok(());
    };
    let id = id.to_string();

    let ready = state.ready().map_err(rpc_message)?;
    let data_dir = ready.data_dir.clone();
    let _ = store::remove_dir(&store::env_dir(&data_dir, &id));
    let _ = store::remove_dir(&store::staging_dir(&data_dir, &id));
    super::mark_failed(
        &data_dir,
        &env.app,
        &id,
        None,
        Stage::Extract,
        "解压失败，已清掉半截产物与压缩包".to_string(),
    );
    tracing::info!(env = %id, "安装失败，已清掉半截的解压目录与暂存压缩包");
    Ok(())
}

/// 失败时的统一收尾：清掉半截产物 + 把元数据落成失败态。
pub(super) fn cleanup_failed(
    data_dir: &Path,
    app: &AppState,
    id: &str,
    stage: Stage,
    message: String,
) {
    let _ = store::remove_dir(&store::env_dir(data_dir, id));
    let _ = store::remove_dir(&store::staging_dir(data_dir, id));
    super::mark_failed(data_dir, app, id, None, stage, message);
}

// ---------------------------------------------------------------------------
// 步骤「解压」
// ---------------------------------------------------------------------------

fn extract_step(state: Arc<RuntimeState>) -> StepSpec {
    StepSpec {
        title: "解压运行环境".into(),
        run: Arc::new(move |_step, _progress, env| {
            let state = state.clone();
            Box::pin(async move {
                let downloaded = env
                    .output(NAME_DOWNLOAD)
                    .await
                    .ok_or("上一步（下载）没有产出压缩包")?;
                let id = downloaded
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or("下载结果里缺环境 id")?
                    .to_string();
                let archive = PathBuf::from(
                    downloaded
                        .get("archive")
                        .and_then(Value::as_str)
                        .ok_or("下载结果里缺压缩包路径")?,
                );
                let ready = state.ready().map_err(rpc_message)?;
                let installed = extract_core(&ready.data_dir, &id, &archive, &env.app).await?;
                serde_json::to_value(installed).map_err(|e| format!("环境对象序列化失败：{e}"))
            })
        }),
        rollback: None,
    }
}

/// 解压核心：不打上游、也不读步骤产出 —— 直接给「环境 id + 压缩包」。
///
/// 拆出来同样是为了测试能整条跑（见模块注释）。**去哪儿找可执行文件**由厂商表
/// 里的 [`Provider::launcher`] 决定，所以这里对两家是同一份代码。
pub(super) async fn extract_core(
    data_dir: &Path,
    id: &str,
    archive: &Path,
    app: &AppState,
) -> Result<Env, String> {
    let Some(record) = store::load(data_dir, id) else {
        return Err(format!("环境 `{id}` 的记录不见了，这一轮不再继续"));
    };
    let provider = model::find_provider(&record.vendor)
        .ok_or_else(|| format!("不认识的厂商 `{}`（记录被改过？）", record.vendor))?;

    // 用户可能在我们等着下载的时候把环境删了 —— 删除就是取消，别再往回写
    if !owns_record(data_dir, id, None) {
        return Err(format!("环境 `{id}` 已被删除，这一轮不再继续"));
    }

    let Some(record) = super::mutate(data_dir, app, id, |record| {
        record.state = EnvState::Extracting;
        record.stage = None;
        record.error = None;
    }) else {
        return Err(format!("环境 `{id}` 的记录不见了，这一轮不再继续"));
    };

    let dest = store::env_dir(data_dir, id);
    let archive_type = record.archive_type.clone();
    let (dest_task, archive_task) = (dest.clone(), archive.to_path_buf());
    let launcher = provider.launcher;
    let outcome = tokio::task::spawn_blocking(move || {
        // 覆盖重装：先把上一份（可能是半份）清掉，免得新旧混在一起
        store::remove_dir(&dest_task)?;
        extract::unpack(&archive_task, &dest_task, &archive_type)?;
        extract::find_binary(&dest_task, launcher.sub_dir, launcher.names).ok_or_else(|| {
            format!(
                "解压出来的包里没有 `{}` —— 这不是一份能用的 {}",
                launcher.names.first().copied().unwrap_or(""),
                provider.name
            )
        })
    })
    .await;

    let (home, binary) = match outcome {
        Ok(Ok(found)) => found,
        Ok(Err(message)) => return Err(message),
        Err(join) => return Err(format!("解压任务异常结束：{join}")),
    };

    // 解压期间用户又把它删了：把刚落地的目录清掉，别留一个没主的环境
    if !owns_record(data_dir, id, None) {
        let _ = store::remove_dir(&dest);
        return Err(format!("环境 `{id}` 已被删除，刚解压出来的目录已清理"));
    }

    // 压缩包不留（重装会重新下）
    let _ = store::remove_dir(&store::staging_dir(data_dir, id));

    super::mutate(data_dir, app, id, |record| {
        record.state = EnvState::Installed;
        record.stage = None;
        record.error = None;
        record.task_id = None;
        record.home = Some(home.clone());
        record.binary = Some(binary.clone());
        record.installed_at_ms = Some(now_ms());
    })
    .ok_or_else(|| format!("环境 `{id}` 的记录不见了，装好的信息没落盘"))
}

// ---------------------------------------------------------------------------
// 模板
// ---------------------------------------------------------------------------

/// 工作流模板：展示用的步骤清单 + 参数 → [`FlowDef`]。
fn template() -> FlowTemplate {
    FlowTemplate {
        title: "下载并安装运行环境".into(),
        steps: vec![
            FlowStepInfo {
                name: NAME_DOWNLOAD.into(),
                title: "下载运行环境".into(),
                step_type: STEP_DOWNLOAD.into(),
            },
            FlowStepInfo {
                name: NAME_EXTRACT.into(),
                title: "解压运行环境".into(),
                step_type: STEP_EXTRACT.into(),
            },
        ],
        build: Arc::new(|params| {
            let version = read_version_value(params)?;

            let mut config = json!({ "version": version });
            if let Some(provider) = optional_str(params, "provider") {
                config["provider"] = json!(provider);
            }
            if let Some(package_type) = optional_str(params, "package_type") {
                config["package_type"] = json!(package_type);
            }

            let mut flow = FlowDef::new(FLOW, FlowMode::Sequential);
            // 没有这一行引擎不会回滚，`download` 标了 rollbackable 也没用
            flow.rollback_on_failure = true;
            flow.add_step(
                StepDef::new(NAME_DOWNLOAD)
                    .with_step_type(STEP_DOWNLOAD)
                    .with_config(config)
                    .with_rollback()
                    .with_timeout(TIMEOUT_UNLIMITED),
            );
            flow.add_step(
                StepDef::new(NAME_EXTRACT)
                    .with_step_type(STEP_EXTRACT)
                    .with_timeout(TIMEOUT_UNLIMITED),
            );
            Ok(flow)
        }),
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 把 `RpcError` 压成步骤错误字符串（szal 的步骤只认字符串）。
fn rpc_message(error: crate::error::RpcError) -> String {
    format!("{}：{}", error.code, error.message)
}

/// 从步骤 config 里读厂商 + 包类型，并做表校验。
fn read_kind(step: &StepDef) -> Result<(&'static Provider, &'static str), String> {
    let pick = |key: &str| {
        step.config
            .as_ref()
            .and_then(|c| c.get(key))
            .and_then(Value::as_str)
            .map(str::to_string)
    };

    let provider_id = pick("provider").unwrap_or_else(|| DEFAULT_PROVIDER.to_string());
    let provider = model::find_provider(provider_id.trim()).ok_or_else(|| {
        format!(
            "{}：不认识的厂商 `{provider_id}`（可选：{}）",
            CODE_PROVIDER_NOT_FOUND,
            model::PROVIDERS
                .iter()
                .map(|p| p.id)
                .collect::<Vec<_>>()
                .join(", ")
        )
    })?;

    let type_id = pick("package_type").unwrap_or_else(|| {
        provider
            .package_types
            .first()
            .copied()
            .unwrap_or(model::DEFAULT_PACKAGE_TYPE)
            .to_string()
    });
    let package_type = model::find_package_type(type_id.trim())
        .ok_or_else(|| format!("{}：不认识的包类型 `{type_id}`", CODE_TYPE_NOT_FOUND))?;

    if !provider.package_types.contains(&package_type.id) {
        return Err(format!(
            "{}：`{}` 目前不提供 {}（可选：{}）",
            CODE_TYPE_NOT_FOUND,
            provider.id,
            package_type.id,
            provider.package_types.join(", ")
        ));
    }
    Ok((provider, package_type.id))
}

/// 从步骤 config 里读版本。**是字符串** —— JDK 是 `21`，frp 是 `0.71.0`。
///
/// 这里把错误**带上稳定码** `runtime_version_required`：步骤错误在任务对象里
/// 只留一个字符串，前端要按码分支（「错误码前缀即模块」是既有约定）。
/// `build` 那条路不带码 —— 它的错误最终会包进 `task_invalid_params`，
/// 再叠一个模块码只会让用户看到两串前缀。
fn read_version(step: &StepDef) -> Result<String, String> {
    let raw = step.config.as_ref().and_then(|c| c.get("version"));
    match raw {
        Some(raw) => parse_version_value(raw)
            .map_err(|message| format!("{CODE_VERSION_REQUIRED}：{message}")),
        None => Err(format!(
            "{CODE_VERSION_REQUIRED}：缺少 `version`（要装的版本号，如 JDK 的 21、frp 的 0.71.0）"
        )),
    }
}

/// 从任意 JSON 里读版本号。
///
/// **数字与字符串都收**：JDK 的大版本从列表里拿到的是数字（前端顺手就发了），
/// frp 的 `0.71.0` 只能是字符串。统一转成字符串再走后面。
fn parse_version_value(raw: &Value) -> Result<String, String> {
    let version = match raw {
        Value::Number(number) => number.to_string(),
        Value::String(text) => text.trim().to_string(),
        _ => String::new(),
    };
    if version.is_empty() {
        return Err(format!("`version` 不能为空，收到 {raw}"));
    }
    // 版本号要拼进环境 id 与上游 URL，所以只允许安全字符
    // （与 `mcserver` 的 `validate_version_token` 同一条规矩）
    if !version
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '+'))
    {
        return Err(format!("`version` 里有不允许的字符：{raw}"));
    }
    Ok(version)
}

/// `build` 里用：参数对象上必须有可解析的 `version`。
fn read_version_value(params: &Value) -> Result<String, String> {
    match params.get("version") {
        Some(raw) => parse_version_value(raw),
        None => Err("缺少参数 `version`（要装的版本号，如 JDK 的 21、frp 的 0.71.0）".to_string()),
    }
}

fn optional_str(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_requires_version() {
        let build = template().build;
        assert!(build(&json!({})).is_err());
        let err = build(&json!({ "version": "  " })).unwrap_err();
        assert!(err.contains("version"), "{err}");
    }

    /// 版本号要拼进环境 id 与上游 URL，所以有字符白名单。
    #[test]
    fn version_rejects_unsafe_characters() {
        let build = template().build;
        assert!(build(&json!({ "version": "1.21.1/../x" })).is_err());
        assert!(build(&json!({ "version": "a b" })).is_err());
        // 这两种写法都要收
        assert!(build(&json!({ "version": 21 })).is_ok());
        assert!(build(&json!({ "version": "0.71.0" })).is_ok());
    }

    #[test]
    fn build_produces_two_steps_with_rollback_on_download() {
        let build = template().build;
        let flow = build(&json!({ "version": 21 })).expect("参数齐全应当能构造流程");

        assert_eq!(flow.steps.len(), 2);
        assert_eq!(flow.steps[0].name, NAME_DOWNLOAD);
        assert_eq!(flow.steps[0].step_type.as_deref(), Some(STEP_DOWNLOAD));
        assert_eq!(flow.steps[1].name, NAME_EXTRACT);
        assert_eq!(flow.steps[1].step_type.as_deref(), Some(STEP_EXTRACT));
        assert!(flow.rollback_on_failure);
        // 只有下载那步可回滚：解压失败后要清掉半截产物与压缩包
        assert!(flow.steps[0].rollbackable);
        assert!(!flow.steps[1].rollbackable);
    }

    /// 数字形式的版本号统一成字符串（JDK 从列表里拿到的就是数字）。
    #[test]
    fn build_normalizes_numeric_version() {
        let build = template().build;
        let flow = build(&json!({ "version": 21 })).unwrap();
        assert_eq!(
            flow.steps[0].config.clone().unwrap()["version"],
            json!("21")
        );
    }

    #[test]
    fn build_passes_optional_provider_and_type() {
        let build = template().build;
        let flow = build(&json!({
            "version": "0.71.0",
            "provider": "frp",
            "package_type": "frpc",
        }))
        .unwrap();
        let config = flow.steps[0].config.clone().unwrap();
        assert_eq!(config["provider"], json!("frp"));
        assert_eq!(config["package_type"], json!("frpc"));

        // 不给就用默认，不硬塞进 config
        let flow = build(&json!({ "version": 21 })).unwrap();
        let config = flow.steps[0].config.clone().unwrap();
        assert!(config.get("provider").is_none());
        assert!(config.get("package_type").is_none());
    }

    #[test]
    fn env_id_carries_the_string_version_for_both_vendors() {
        let target = model::Target {
            os: "linux",
            query_os: "linux-glibc",
            arch: "x64",
            archive_type: "tar.gz",
            libc: Some("glibc"),
        };
        assert_eq!(
            model::env_id("zulu", "jdk", "21", &target),
            "zulu-jdk-21-linux-x64"
        );
        assert_eq!(
            model::env_id("frp", "frpc", "0.71.0", &target),
            "frp-frpc-0.71.0-linux-x64"
        );
    }
}
