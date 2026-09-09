//! HTTP 服务:phase 0 中与初始化直接相关的端点
//! (`GET /api/v1/health` 未配对可访问,`POST /api/v1/auth/login` 换取长期 token),
//! 以及实例配置管理(`/api/v1/instances` CRUD / overview)。
//! 其余端点按 openapi.yaml 阶段计划后续补充。
//!
//! 鉴权:除 /auth/* 与 /health 外全部需要 `Authorization: Bearer <token>`。

use std::sync::Arc;
use std::time::Instant;

use axum::body::Body;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, Query, Request, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::middleware::{self, Next};
use axum::response::Response;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::auth::AuthStore;
use crate::catalog::{Catalog, CatalogError};
use crate::download::{DownloadManager, run_download_task};
use crate::frp::{FrpError, FrpManager, FrpStatus, TunnelInfo, TunnelInput};
use crate::fs::{
    complete_file_upload, compress_file, create_directory, delete_file, download_file,
    extract_file, init_file_upload, list_files, move_file, upload_file_piece, write_file,
    ensure_within, rel_path, resolve, FsManager, MAX_PIECE_BYTES, MAX_WRITE_BYTES,
};
use crate::instance::{InstanceManager, ManagerError};
use crate::mod_market::ModMarket;
use crate::mod_meta::{ModMetaManager, list_metadata, run_analyze_task};
use crate::monitor::{MonitorManager, MonitorSnapshot};
use crate::proc::{ProcError, ProcManager};
use crate::runtime::{
    InstallPlan, RuntimeCatalog, RuntimeError, RuntimeInfo, RuntimeInstallRequest, RuntimeManager,
    RuntimeType, run_runtime_install_task,
};
use crate::server_core::{self, ServerCoreManager, ServerCoreUpdateRequest};
use crate::task::model::{Task, TaskKind, TaskFailure};
use crate::task::service::TaskService;
use crate::transfer::{self, TransferManager};
use tower_http::cors::CorsLayer;

#[derive(Clone)]
pub struct AppState {
    pub auth: Arc<Mutex<AuthStore>>,
    pub instances: Arc<InstanceManager>,
    pub tasks: TaskService,
    /// 服务端下载引擎(内部能力,创建实例触发的下载)。
    pub download: Arc<DownloadManager>,
    /// 服务端版本目录(「下载服务端」向导数据源,代理第三方源)。
    pub catalog: Arc<Catalog>,
    /// 运行时环境管理(/runtimes/*:Java 等环境下载与卸载)。
    pub runtimes: Arc<RuntimeManager>,
    /// 系统监控(/monitor/snapshot:CPU/内存/磁盘/网络速率)。
    pub monitor: Arc<MonitorManager>,
    /// 实例进程管理(PTY 启动/停止/强杀 + 终端 I/O)。
    pub procs: Arc<ProcManager>,
    /// 文件管理(/fs/*):分片上传会话等有状态。
    pub fs: Arc<FsManager>,
    /// 插件/模组元数据解析缓存(/instances/{id}/mods/*)。
    pub mod_meta: Arc<ModMetaManager>,
    /// 插件/模组市场代理(Modrinth / Poggit,网络调用收敛在后端)。
    pub mod_market: Arc<ModMarket>,
    /// Frp 内网穿透(隧道注册表 + 全局唯一 frpc 进程)。
    pub frp: Arc<FrpManager>,
    /// 实例迁移(导出打包 + 导入还原)。
    pub transfer: Arc<TransferManager>,
    /// 服务端核心更新(PaperMC 源)。
    pub server_core: Arc<ServerCoreManager>,
    pub started_at: Instant,
}

/// 组装路由(挂载于 /api/v1)。
#[allow(clippy::too_many_arguments)]
pub fn router(
    auth: AuthStore,
    instances: InstanceManager,
    tasks: TaskService,
    download: Arc<DownloadManager>,
    catalog: Arc<Catalog>,
    runtimes: Arc<RuntimeManager>,
    monitor: Arc<MonitorManager>,
    procs: Arc<ProcManager>,
    fs: Arc<FsManager>,
    mod_meta: Arc<ModMetaManager>,
    mod_market: Arc<ModMarket>,
    frp: Arc<FrpManager>,
    transfer: Arc<TransferManager>,
    server_core: Arc<ServerCoreManager>,
) -> Router {
    let state = AppState {
        auth: Arc::new(Mutex::new(auth)),
        instances: Arc::new(instances),
        tasks,
        download,
        catalog,
        runtimes,
        monitor,
        procs,
        fs,
        mod_meta,
        mod_market,
        frp,
        transfer,
        server_core,
        started_at: Instant::now(),
    };
    Router::new()
        .route("/api/v1/health", get(health))
        .route("/api/v1/auth/login", post(login))
        .route("/api/v1/auth/local-login/challenge", post(local_challenge))
        .route("/api/v1/auth/local-login", post(local_login))
        .route("/api/v1/auth/change-password", post(change_password))
        .route("/api/v1/auth/change-username", post(change_username))
        .route("/api/v1/auth/tokens", get(list_devices))
        .route(
            "/api/v1/auth/tokens/{deviceId}",
            delete(revoke_device).patch(rename_device),
        )
        .route("/api/v1/instances", get(list_instances).post(create_instance))
        .route("/api/v1/instances/overview", get(instances_overview))
        .route(
            "/api/v1/instances/{instanceId}",
            get(get_instance)
                .put(update_instance)
                .delete(delete_instance),
        )
        .route(
            "/api/v1/instances/{instanceId}/start",
            post(start_instance),
        )
        .route("/api/v1/instances/{instanceId}/stop", post(stop_instance))
        .route(
            "/api/v1/instances/{instanceId}/restart",
            post(restart_instance),
        )
        .route("/api/v1/instances/{instanceId}/kill", post(kill_instance))
        .route(
            "/api/v1/instances/{instanceId}/command",
            post(send_instance_command),
        )
        .route(
            "/api/v1/instances/{instanceId}/players",
            get(get_instance_players),
        )
        .route(
            "/api/v1/instances/{instanceId}/outputlog",
            get(get_instance_output_log),
        )
        .route(
            "/api/v1/instances/{instanceId}/mods/analyze",
            post(analyze_mods),
        )
        .route(
            "/api/v1/instances/{instanceId}/mods/metadata",
            get(get_mods_metadata),
        )
        .route(
            "/api/v1/instances/{instanceId}/mods/download",
            post(download_mod),
        )
        .route(
            "/api/v1/instances/{instanceId}/mods/downloads",
            delete(clear_finished_mod_downloads),
        )
        .route("/api/v1/mods/modrinth/search", get(modrinth_search))
        .route(
            "/api/v1/mods/modrinth/project/{projectId}/versions",
            get(modrinth_project_versions),
        )
        .route("/api/v1/mods/modrinth/projects", get(modrinth_projects))
        .route(
            "/api/v1/mods/modrinth/version-files",
            post(modrinth_version_files),
        )
        .route(
            "/api/v1/mods/modrinth/game-versions",
            get(modrinth_game_versions),
        )
        .route("/api/v1/mods/poggit/plugins", get(poggit_plugins))
        .route(
            "/api/v1/ws/terminal",
            get(crate::terminal::terminal_upgrade),
        )
        .route(
            "/api/v1/tasks/{taskId}",
            get(get_task).delete(cancel_task),
        )
        .route("/api/v1/catalog/server-types", get(list_server_types))
        .route("/api/v1/catalog/versions", get(list_catalog_versions))
        .route("/api/v1/catalog/loaders", get(list_catalog_loaders))
        .route("/api/v1/catalog/download-info", get(get_catalog_download_info))
        .route("/api/v1/runtimes", get(list_runtimes))
        .route("/api/v1/runtimes/catalog", get(get_runtime_catalog))
        .route("/api/v1/runtimes/install", post(install_runtime))
        .route("/api/v1/runtimes/{runtimeId}", delete(delete_runtime))
        .route("/api/v1/frp/tunnels", get(list_frp_tunnels).post(create_frp_tunnel))
        .route(
            "/api/v1/frp/tunnels/{tunnelId}",
            get(get_frp_tunnel).put(update_frp_tunnel).delete(delete_frp_tunnel),
        )
        .route("/api/v1/frp/start", post(start_frpc))
        .route("/api/v1/frp/stop", post(stop_frpc))
        .route("/api/v1/frp/status", get(get_frp_status))
        .route("/api/v1/frp/logs", get(get_frp_logs))
        .route("/api/v1/monitor/snapshot", get(get_monitor_snapshot))
        .route("/api/v1/fs/list", get(list_files))
        .route("/api/v1/fs/download", get(download_file))
        .route("/api/v1/fs/upload-init", post(init_file_upload))
        .route(
            "/api/v1/fs/upload-piece",
            post(upload_file_piece).layer(DefaultBodyLimit::max(MAX_PIECE_BYTES)),
        )
        .route("/api/v1/fs/upload-complete", post(complete_file_upload))
        .route("/api/v1/fs/mkdir", post(create_directory))
        .route("/api/v1/fs/move", post(move_file))
        .route("/api/v1/fs/delete", post(delete_file))
        .route(
            "/api/v1/fs/write",
            post(write_file).layer(DefaultBodyLimit::max(MAX_WRITE_BYTES)),
        )
        .route("/api/v1/fs/compress", post(compress_file))
        .route("/api/v1/fs/extract", post(extract_file))
        .route(
            "/api/v1/instances/{instanceId}/export",
            post(export_instance),
        )
        .route(
            "/api/v1/instances/{instanceId}/export/download",
            get(download_instance_export),
        )
        .route("/api/v1/instances/import", post(import_instance))
        .route(
            "/api/v1/instances/{instanceId}/core-update/check",
            get(check_server_core_update),
        )
        .route(
            "/api/v1/instances/{instanceId}/core-update",
            post(update_server_core),
        )
        .fallback(not_found)
        .layer(CorsLayer::permissive())
        .layer(middleware::from_fn(trace_request))
        .with_state(state)
}

/// DEBUG 级 HTTP 接口调用日志(REST + 静态服务 + WS 升级请求,含 404):
/// 记录方法、URI(含 query)、响应状态码与耗时。仅在 log_level=debug 时可见。
async fn trace_request(request: Request, next: Next) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    tracing::debug!(method = %method, uri = %uri, "http request");
    let started = Instant::now();
    let response = next.run(request).await;
    tracing::debug!(
        method = %method,
        uri = %uri,
        status = response.status().as_u16(),
        elapsed_ms = started.elapsed().as_millis() as u64,
        "http response"
    );
    response
}

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
    /// 客户端持久化的设备标识;存在则复用该设备记录。
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub device_type: Option<crate::auth::DeviceType>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginResponse {
    pub token: String,
    pub device_id: String,
}

/// 本机免密登录请求(openapi LocalLoginRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalLoginRequest {
    pub challenge: String,
    pub signature: String,
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub device_name: Option<String>,
    #[serde(default)]
    pub device_type: Option<crate::auth::DeviceType>,
}

/// 重命名设备请求(openapi RenameDeviceRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameDeviceRequest {
    pub name: String,
}

/// 修改密码请求(openapi ChangePasswordRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangePasswordRequest {
    pub new_password: String,
}

/// 修改用户名请求(openapi ChangeUsernameRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangeUsernameRequest {
    pub new_username: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub status: &'static str,
    pub version: &'static str,
    pub daemon: &'static str,
    pub platform: String,
    pub uptime_seconds: u64,
    pub instances: Instances,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Instances {
    pub running: u32,
    pub total: u32,
}

/// 机器可读错误(openapi ErrorResponse)。
#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
}

/// 异步任务受理回执(openapi JobAccepted;jobId = Task.id)。
#[derive(Debug, Serialize)]
pub struct JobAccepted {
    #[serde(rename = "jobId")]
    pub job_id: Uuid,
}

/// 导出归档下载查询参数(openapi ExportTaskId)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportDownloadQuery {
    pub export_task_id: Uuid,
}

// ────────────────────────── 处理器 ──────────────────────────

/// GET /api/v1/health:健康检查(未配对可访问)。
async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let (running, total) = state.instances.counts().await;
    Json(HealthResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        daemon: "rust",
        platform: format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH),
        uptime_seconds: state.started_at.elapsed().as_secs(),
        instances: Instances { running, total },
    })
}

/// POST /api/v1/auth/login:用户名密码登录,换取长期 token。
///
/// 说明:verify 为阻塞的 argon2 校验(默认参数 ~几十 ms),本地 daemon 场景可接受;
/// 实例服务落地后如需严格非阻塞,可拆入 spawn_blocking。
async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, Json<ErrorBody>)> {
    let valid = {
        let auth = state.auth.lock().await;
        auth.verify(&req.username, &req.password)
    };
    if !valid {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(ErrorBody {
                code: "invalid_credentials",
                message: "invalid username or password".into(),
            }),
        ));
    }

    let device = {
        let mut auth = state.auth.lock().await;
        auth.issue_token(
            req.device_id.as_deref(),
            req.device_name.as_deref(),
            req.device_type,
        )
            .map_err(internal_error)?
    };

    Ok(Json(LoginResponse {
        token: device.token,
        device_id: device.id,
    }))
}

/// POST /api/v1/auth/local-login/challenge:签发一次性本机免密挑战。
///
/// 免密凭据为 daemon 数据目录内的 `local.key`;TCP 端口映射仅转发流量、
/// 无法读取该文件,因此经映射访问的远端无法免密(与来源 IP 无关)。
/// 另严格限制来源必须为回环地址(127.0.0.1/::1):映射场景下 peer 即本机回环,
/// 不受影响;未开映射时(如局域网绑定)即使凭证泄露,非回环来源一律 403。
async fn local_challenge(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<std::net::SocketAddr>,
) -> Result<Json<crate::auth::LocalChallenge>, (StatusCode, Json<ErrorBody>)> {
    ensure_loopback(peer)?;
    let challenge = { state.auth.lock().await.issue_local_challenge() };
    Ok(Json(challenge))
}

/// POST /api/v1/auth/local-login:提交 HMAC 签名换取长期 token(与 /auth/login 等价)。
async fn local_login(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<std::net::SocketAddr>,
    Json(req): Json<LocalLoginRequest>,
) -> Result<Json<LoginResponse>, (StatusCode, Json<ErrorBody>)> {
    ensure_loopback(peer)?;
    let valid = {
        let mut auth = state.auth.lock().await;
        auth.verify_local_login(&req.challenge, &req.signature)
    };
    if !valid {
        return Err((
            StatusCode::UNAUTHORIZED,
            Json(ErrorBody {
                code: "invalid_credentials",
                message: "invalid local login signature".into(),
            }),
        ));
    }

    let device = {
        let mut auth = state.auth.lock().await;
        auth.issue_token(
            req.device_id.as_deref(),
            req.device_name.as_deref(),
            req.device_type,
        )
            .map_err(internal_error)?
    };

    Ok(Json(LoginResponse {
        token: device.token,
        device_id: device.id,
    }))
}

/// POST /api/v1/auth/change-password:修改密码(需 Bearer 鉴权)。
async fn change_password(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ChangePasswordRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    let mut auth = state.auth.lock().await;
    let token = bearer_token(&headers)
        .ok_or_else(|| unauthorized("invalid_token", "missing bearer token"))?;
    if !auth.verify_token(token) {
        return Err(unauthorized("invalid_token", "invalid bearer token"));
    }
    if req.new_password.len() < 8 || req.new_password.len() > 128 {
        return Err(bad_request(
            "invalid_password",
            "new password must be 8-128 characters",
        ));
    }
    auth.change_password(&req.new_password)
        .map_err(internal_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/auth/change-username:修改用户名(需 Bearer 鉴权)。
async fn change_username(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ChangeUsernameRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    let mut auth = state.auth.lock().await;
    let token = bearer_token(&headers)
        .ok_or_else(|| unauthorized("invalid_token", "missing bearer token"))?;
    if !auth.verify_token(token) {
        return Err(unauthorized("invalid_token", "invalid bearer token"));
    }
    let new_username = req.new_username.trim();
    if new_username.is_empty() || new_username.chars().count() > 64 {
        return Err(bad_request(
            "invalid_username",
            "username must be 1-64 characters",
        ));
    }
    auth.change_username(new_username)
        .map_err(internal_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// GET /api/v1/auth/tokens:已登录设备列表(需 Bearer 鉴权,openapi listDevices)。
async fn list_devices(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<crate::auth::DeviceInfo>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let devices = { state.auth.lock().await.list_devices() };
    Ok(Json(devices))
}

/// DELETE /api/v1/auth/tokens/{deviceId}:吊销指定设备的 token(openapi revokeDevice)。
/// 吊销后该 token 立即失效(包括吊销自身,前端据此断开连接);设备不存在返回 404。
async fn revoke_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let revoked = {
        let mut auth = state.auth.lock().await;
        auth.revoke_device(&device_id).map_err(internal_error)?
    };
    if revoked.is_none() {
        return Err(not_found().await);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// PATCH /api/v1/auth/tokens/{deviceId}:重命名设备(openapi renameDevice)。
async fn rename_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
    Json(req): Json<RenameDeviceRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let name = req.name.trim();
    if name.is_empty() || name.chars().count() > 64 {
        return Err(bad_request(
            "invalid_name",
            "device name must be 1-64 characters",
        ));
    }
    let updated = {
        let mut auth = state.auth.lock().await;
        auth.rename_device(&device_id, name)
            .map_err(internal_error)?
    };
    if updated.is_none() {
        return Err(not_found().await);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// 未匹配路由:统一 404(openapi ErrorResponse)。其余 REST 端点后续阶段接入。
async fn not_found() -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::NOT_FOUND,
        Json(ErrorBody {
            code: "not_found",
            message: "resource not found".into(),
        }),
    )
}

// ────────────────────────── 实例处理器(openapi instances) ──────────────────────────

/// GET /api/v1/instances:实例列表(分页 + 关键字过滤)。
#[derive(Debug, Deserialize)]
struct ListInstancesQuery {
    #[serde(default = "default_page")]
    page: u64,
    #[serde(default = "default_page_size")]
    page_size: u64,
    #[serde(default)]
    keyword: Option<String>,
}

async fn list_instances(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<ListInstancesQuery>,
) -> Result<Json<crate::instance::InstancePage>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let page = state
        .instances
        .list(query.keyword.as_deref(), query.page, query.page_size)
        .await;
    Ok(Json(page))
}

/// POST /api/v1/instances:创建实例(仅 name 必填,缺省字段由 daemon 分配)。
///
/// 带 downloadUrl 时:创建配置后自动向任务队列提交下载任务(下载到实例工作目录),
/// 回写 downloadTaskId 并返回 202 完整配置(含 downloadTaskId;下载完成该任务终结,
/// 实例方可启动)。不带 downloadUrl:同步返回 201 完整配置。
async fn create_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<crate::instance::InstanceInput>,
) -> Result<(StatusCode, Json<crate::instance::InstanceConfig>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state.instances.create(req).await.map_err(map_manager_error)?;

    let Some(url) = config.download_url.clone() else {
        return Ok((
            StatusCode::CREATED,
            Json(config),
        ));
    };

    // ── 带下载链接:提交下载任务(分组绑实例,FIFO 串行,完成后才轮到实例操作) ──
    let checksum = config.checksum.clone();
    let file_name = config.file_name.clone();
    let work_dir = config.working_directory.clone();
    let dm = state.download.clone();
    let task = match state
        .tasks
        .submit(TaskKind::Download, Some(config.id), move |handle| {
            run_download_task(handle, (*dm).clone(), url, work_dir, file_name, checksum, None, false)
        })
        .await
    {
        Ok(task) => task,
        Err(e) => {
            tracing::error!(error = %e, "submit download task failed");
            // 回滚刚创建的实例,避免"实例已建但无下载任务"的半成品
            if let Err(rollback) = state.instances.delete(config.id).await {
                tracing::error!(error = %rollback, "rollback instance after submit failed");
            }
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorBody {
                    code: "internal_error",
                    message: "failed to start download task".into(),
                }),
            ));
        }
    };

    // 回写下载任务 id(只读,便于客户端经 GET /tasks/{taskId} 查询进度)
    let updated = state
        .instances
        .set_download_task_id(config.id, task.id)
        .await
        .map_err(map_manager_error)?;

    // 202 同样返回完整配置(含 downloadTaskId):客户端无需解析 jobId 分支,
    // 生成的 createInstance 客户端可统一按 InstanceConfig 反序列化。
    Ok((StatusCode::ACCEPTED, Json(updated)))
}

/// GET /api/v1/instances/overview:全部实例状态聚合(首页看板)。
async fn instances_overview(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<crate::instance::InstanceOverview>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(state.instances.overview().await))
}

/// GET /api/v1/instances/{instanceId}:实例详情(配置 + 运行状态)。
async fn get_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<Json<crate::instance::InstanceDetail>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let detail = state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    Ok(Json(detail))
}

/// PUT /api/v1/instances/{instanceId}:更新实例配置(全量替换)。
async fn update_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<crate::instance::InstanceInput>,
) -> Result<Json<crate::instance::InstanceConfig>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .update(instance_id, req)
        .await
        .map_err(map_manager_error)?;
    Ok(Json(config))
}

/// DELETE /api/v1/instances/{instanceId}:删除实例(仅删配置,保留工作目录)。
/// 运行中/启动中/停止中拒绝(409);已停止的退出句柄一并清理。
async fn delete_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if let Some(snap) = state.procs.snapshot(instance_id) {
        if !matches!(snap.status, crate::instance::InstanceStatus::Stopped) {
            return Err((
                StatusCode::CONFLICT,
                Json(ErrorBody {
                    code: "instance_busy",
                    message: "instance is running, stop it before delete".into(),
                }),
            ));
        }
    }
    state
        .instances
        .delete(instance_id)
        .await
        .map_err(map_manager_error)?;
    state.procs.remove(instance_id);
    Ok(StatusCode::NO_CONTENT)
}

/// GET /api/v1/instances/{instanceId}/outputlog:返回实例完整落盘日志
/// (text/plain;供终端回放/复制/导出,openapi getInstanceOutputLog)。
async fn get_instance_output_log(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<(HeaderMap, String), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if state
        .instances
        .get_config(instance_id)
        .await
        .is_none()
    {
        return Err(instance_not_found(instance_id));
    }
    // 全量(不截行数);按文件时间序拼接,无日志目录/文件 → 空串
    let log = state.procs.replay_log(instance_id, usize::MAX).await.join("\n");
    let mut resp_headers = HeaderMap::new();
    resp_headers.insert(
        header::CONTENT_TYPE,
        "text/plain; charset=utf-8".parse().unwrap(),
    );
    Ok((resp_headers, log))
}

/// GET /api/v1/instances/{instanceId}/players:玩家管理聚合快照(契约 players)。
///
/// 在线玩家集合由 daemon 从实例控制台输出解析维护(join/leave/list;
/// 见 `proc.rs` stdout 泵 + `players::record_player_event`);四类名单
/// (白名单/OP/封禁/IP封禁)直接读取实例 cwd 下各服务端格式文件(JSON 优先,
/// txt 回退)。数据仅只读;增删操作经 `POST .../command` 下发命令。
async fn get_instance_players(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<Json<crate::players::PlayerSnapshot>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let detail = state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let cwd = detail.config.working_directory;
    let files = crate::players::snapshot_files(&cwd, detail.config.instance_type).await;
    let status = state
        .procs
        .snapshot(instance_id)
        .map_or(crate::instance::InstanceStatus::Stopped, |s| s.status);
    Ok(Json(crate::players::PlayerSnapshot {
        instance_status: status,
        online: state.procs.online_players(instance_id),
        whitelist: files.whitelist,
        ops: files.ops,
        bans: files.bans,
        ban_ips: files.ban_ips,
    }))
}

// ────────────────────────── 实例迁移(export/import,openapi transfer) ──────────────────────────

/// POST /api/v1/instances/{instanceId}/export:导出实例(打包工作目录为归档)。
///
/// 实例必须 Stopped(运行中返回 409 instance_busy);同实例同 kind(Export)未结束
/// 任务由任务队列去重(409 task_conflict)。完成后经 GET .../export/download 下载。
async fn export_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<transfer::ExportRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if let Some(snap) = state.procs.snapshot(instance_id) {
        if !matches!(snap.status, crate::instance::InstanceStatus::Stopped) {
            return Err(conflict(
                "instance_busy",
                "instance is running, stop it before export",
            ));
        }
    }
    let im = state.instances.clone();
    let tm = (*state.transfer).clone();
    let task = state
        .tasks
        .submit(TaskKind::Export, Some(instance_id), move |handle| {
            transfer::run_export_task(handle, tm, im, instance_id, req)
        })
        .await
        .map_err(map_task_error)?;
    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

/// GET /api/v1/instances/{instanceId}/export/download:下载已完成的导出归档。
async fn download_instance_export(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(_instance_id): Path<Uuid>,
    Query(query): Query<ExportDownloadQuery>,
) -> Result<Response, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let export_task_id = query.export_task_id;
    let Some(file) = state.transfer.get_export_archive(export_task_id) else {
        return Err((
            StatusCode::NOT_FOUND,
            Json(ErrorBody {
                code: "not_found",
                message: format!("export archive for task {export_task_id} not found"),
            }),
        ));
    };
    let meta = std::fs::metadata(&file).map_err(|e| {
        (
            StatusCode::NOT_FOUND,
            Json(ErrorBody {
                code: "not_found",
                message: format!("export archive unreadable: {e}"),
            }),
        )
    })?;
    let len = meta.len();
    let name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "instance-export.zip".into());

    let file_for_read = file.clone();
    let data = tokio::task::spawn_blocking(move || std::fs::read(&file_for_read))
        .await
        .map_err(|e| internal_error(crate::error::DaemonError::Io(std::io::Error::other(
            format!("read export task panic: {e}"),
        ))))?;
    let data = match data {
        Ok(d) => d,
        Err(e) => {
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorBody {
                    code: "internal_error",
                    message: format!("cannot read export archive: {e}"),
                }),
            ))
        }
    };

    let body = Body::from(data);
    let mut response = Response::new(body);
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, "application/octet-stream".parse().unwrap());
    headers.insert(header::CONTENT_LENGTH, len.to_string().parse().unwrap());
    headers.insert(
        header::CONTENT_DISPOSITION,
        format!("attachment; filename=\"{name}\"").parse().unwrap(),
    );
    Ok(response)
}

/// POST /api/v1/instances/import:导入实例(从导出归档还原为新实例)。
///
/// 归档文件须已上传到 sourceInstanceId 的 cwd(经 /fs/upload-*)。任务挂在该
/// 源实例下(FIFO 串行);完成后新实例出现在实例列表。
async fn import_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<transfer::ImportRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    // 校验源实例存在(避免任务跑一半才发现)
    if state
        .instances
        .get_config(req.source_instance_id)
        .await
        .is_none()
    {
        return Err(instance_not_found(req.source_instance_id));
    }
    let im = state.instances.clone();
    let tm = (*state.transfer).clone();
    let task = state
        .tasks
        .submit_named(
            TaskKind::Import,
            Some(req.source_instance_id),
            Some("导入实例".to_string()),
            move |handle| transfer::run_import_task(handle, tm, im, req),
        )
        .await
        .map_err(map_task_error)?;
    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

// ────────────────────────── 服务端核心更新(openapi server-core) ──────────────────────────

/// GET /api/v1/instances/{instanceId}/core-update/check:检查服务端核心是否有新版本。
async fn check_server_core_update(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<Json<server_core::ServerCoreUpdateCheck>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .get_config(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    match state.server_core.check(&config).await {
        Ok(check) => Ok(Json(check)),
        Err(e) => Err((
            StatusCode::BAD_GATEWAY,
            Json(ErrorBody {
                code: "upstream_error",
                message: e,
            }),
        )),
    }
}

/// POST /api/v1/instances/{instanceId}/core-update:更新服务端核心(下载替换 jar)。
async fn update_server_core(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<ServerCoreUpdateRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if let Some(snap) = state.procs.snapshot(instance_id) {
        if !matches!(snap.status, crate::instance::InstanceStatus::Stopped) {
            return Err(conflict(
                "instance_busy",
                "instance is running, stop it before updating core",
            ));
        }
    }
    let im = state.instances.clone();
    let dm = state.download.clone();
    let task = state
        .tasks
        .submit(TaskKind::CoreUpdate, Some(instance_id), move |handle| {
            server_core::run_core_update_task(handle, (*dm).clone(), im, instance_id, req)
        })
        .await
        .map_err(map_task_error)?;
    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

// ────────────────────────── 插件/模组元数据处理器(openapi mods) ──────────────────────────

/// 解析任务请求(契约 ModsAnalyzeRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModsAnalyzeRequest {
    /// 相对实例 cwd 的目录,如 plugins / mods。
    pub path: String,
}

/// POST /api/v1/instances/{instanceId}/mods/analyze:提交插件/模组元数据解析任务。
///
/// 元数据检查放在后端:前端先经 /fs/list 展示文件列表,再提交本接口创建解析任务;
/// 任务按 instanceId 分组 FIFO 串行,进度经 GET /tasks/{jobId} 轮询,
/// 成功后经 GET /instances/{instanceId}/mods/metadata 拉取结果。
async fn analyze_mods(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<ModsAnalyzeRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let detail = state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let cwd = detail.config.working_directory;
    let rel_dir = req.path.trim().to_string();

    // 目录须存在且为目录:立即失败,不占用任务队列
    let dir = crate::fs::resolve(&cwd, &rel_dir)
        .map_err(|e| bad_request("invalid_path", &e.to_string()))?;
    crate::fs::ensure_within(&cwd, &dir)
        .map_err(|e| bad_request("invalid_path", &e.to_string()))?;
    if !dir.is_dir() {
        return Err(bad_request(
            "invalid_path",
            &format!("{rel_dir} is not a directory"),
        ));
    }

    let mgr = state.mod_meta.clone();
    let task = state
        .tasks
        .submit(TaskKind::Analyze, Some(instance_id), move |handle| {
            run_analyze_task(handle, mgr, instance_id, cwd, rel_dir)
        })
        .await
        .map_err(map_task_error)?;

    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

/// 元数据列表查询(契约 GET mods/metadata)。
#[derive(Debug, Deserialize)]
struct ModsMetadataQuery {
    /// 相对实例 cwd 的目录,如 plugins / mods。
    path: String,
}

/// GET /api/v1/instances/{instanceId}/mods/metadata:列出目录内插件/模组的解析结果
/// (未识别/未解析为 null,供前端展示元数据)。
async fn get_mods_metadata(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Query(query): Query<ModsMetadataQuery>,
) -> Result<
    Json<crate::mod_meta::ModMetadataListResponse>,
    (StatusCode, Json<ErrorBody>),
> {
    require_auth(&state, &headers).await?;
    let detail = state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let cwd = detail.config.working_directory;
    let list = list_metadata(&state.mod_meta, instance_id, &cwd, &query.path)
        .await
        .map_err(|e| -> (StatusCode, Json<ErrorBody>) { e.into() })?;
    Ok(Json(list))
}

// ────────────────────────── 插件/模组下载与市场处理器 ──────────────────────────

/// 单文件下载请求(契约 ModDownloadRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModDownloadRequest {
    pub url: String,
    /// 目标目录,相对实例 cwd(如 mods / plugins)。
    pub dest_path: String,
    /// 落盘文件名;缺省取 URL 末段。
    pub file_name: Option<String>,
    /// 用户可读展示标题(如「模组名 v1.2」),用于任务列表显示。
    pub display_name: Option<String>,
    /// 更新替换:下载成功后把该旧文件(相对实例 cwd)重命名 `<path>.disabled`,
    /// 用于模组/插件升级时禁用旧版而非删除。
    pub replace_path: Option<String>,
}

/// POST /api/v1/instances/{instanceId}/mods/download:提交通用单文件下载任务
/// (TaskKind::download_single_file)。
///
/// 每个任务内部绑定一个 aria2 gid(经 run_download_task 轮询进度/取消),同一实例
/// 允许多个排队 FIFO 串行,同名目标文件直接覆盖(前端负责按目标路径去重)。
/// 进度/状态经 GET /tasks/{jobId} 轮询,可 DELETE /tasks/{jobId} 取消。
async fn download_mod(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<ModDownloadRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if req.url.trim().is_empty() {
        return Err(bad_request("invalid_path", "url is required"));
    }
    if !(req.url.starts_with("http://") || req.url.starts_with("https://")) {
        return Err(bad_request(
            "invalid_path",
            "url must use http/https protocol",
        ));
    }
    let detail = state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let cwd = detail.config.working_directory;

    let dest_dir = crate::fs::resolve(&cwd, &req.dest_path)
        .map_err(|e| bad_request("invalid_path", &e.to_string()))?;
    crate::fs::ensure_within(&cwd, &dest_dir)
        .map_err(|e| bad_request("invalid_path", &e.to_string()))?;

    let dm = state.download.clone();
    let url = req.url;
    let file_name = req.file_name;
    let display_name = req.display_name;
    // 更新替换目标(相对 cwd 解析并校验仍在沙箱内)
    let replace = match req.replace_path {
        Some(p) if !p.trim().is_empty() => {
            let abs = crate::fs::resolve(&cwd, &p)
                .map_err(|e| bad_request("invalid_path", &e.to_string()))?;
            crate::fs::ensure_within(&cwd, &abs)
                .map_err(|e| bad_request("invalid_path", &e.to_string()))?;
            Some(abs)
        }
        _ => None,
    };
    let task = state
        .tasks
        .submit_named(
            TaskKind::DownloadSingleFile,
            Some(instance_id),
            display_name,
            move |handle| {
                run_download_task(handle, (*dm).clone(), url, dest_dir, file_name, None, replace, true)
            },
        )
        .await
        .map_err(map_task_error)?;

    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

/// DELETE /api/v1/instances/{instanceId}/mods/downloads:清除该实例已终结的
/// download_single_file 任务(下载队列「清除已完成」)。queued/running 不受影响。
async fn clear_finished_mod_downloads(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    state
        .instances
        .get_detail(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let cleared = state.tasks.clear_finished_downloads(instance_id).await;
    Ok(Json(serde_json::json!({ "cleared": cleared })))
}

/// Modrinth 搜索查询参数(契约 mods/modrinth/search)。
#[derive(Debug, Deserialize)]
pub struct ModrinthSearchQuery {
    query: String,
    offset: Option<u64>,
    limit: Option<u64>,
    game_version: Option<String>,
    loader: Option<String>,
    sort: Option<String>,
    project_type: Option<String>,
}

/// GET /api/v1/mods/modrinth/search:Modrinth 搜索代理。
async fn modrinth_search(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<ModrinthSearchQuery>,
) -> Result<
    Json<crate::mod_market::ModrinthSearchResponse>,
    (StatusCode, Json<ErrorBody>),
> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .modrinth_search(
            &query.query,
            query.offset.unwrap_or(0),
            query.limit.unwrap_or(20),
            query.game_version.as_deref(),
            query.loader.as_deref(),
            &query.sort.unwrap_or_else(|| "relevance".into()),
            &query.project_type.unwrap_or_else(|| "mod".into()),
        )
        .await
        .map_err(|e| proxy_error("modrinth_search", &e))?;
    Ok(Json(result))
}

/// 项目版本查询参数(契约 mods/modrinth/project/{id}/versions)。
#[derive(Debug, Deserialize)]
pub struct ModrinthProjectVersionsQuery {
    game_version: Option<String>,
    loader: Option<String>,
}

/// GET /api/v1/mods/modrinth/project/{projectId}/versions:项目版本列表代理。
async fn modrinth_project_versions(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(project_id): Path<String>,
    Query(query): Query<ModrinthProjectVersionsQuery>,
) -> Result<
    Json<Vec<crate::mod_market::ModrinthVersion>>,
    (StatusCode, Json<ErrorBody>),
> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .modrinth_versions(
            &project_id,
            query.game_version.as_deref(),
            query.loader.as_deref(),
        )
        .await
        .map_err(|e| proxy_error("modrinth_versions", &e))?;
    Ok(Json(result))
}

/// 批量项目信息查询参数(契约 mods/modrinth/projects;ids 为重复 query 键)。
#[derive(Debug, Deserialize)]
pub struct ModrinthProjectsQuery {
    ids: Vec<String>,
}

/// GET /api/v1/mods/modrinth/projects:批量项目信息(图标/标题)代理。
async fn modrinth_projects(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<ModrinthProjectsQuery>,
) -> Result<
    Json<Vec<crate::mod_market::ModrinthProject>>,
    (StatusCode, Json<ErrorBody>),
> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .modrinth_projects(&query.ids)
        .await
        .map_err(|e| proxy_error("modrinth_projects", &e))?;
    Ok(Json(result))
}

/// 按 SHA1 查版本请求(契约 mods/modrinth/version-files)。
#[derive(Debug, Deserialize)]
pub struct ModrinthVersionFilesRequest {
    hashes: Vec<String>,
}

/// POST /api/v1/mods/modrinth/version-files:按 SHA1 查最新版本(更新检查)代理。
async fn modrinth_version_files(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ModrinthVersionFilesRequest>,
) -> Result<
    Json<std::collections::HashMap<String, crate::mod_market::ModrinthVersion>>,
    (StatusCode, Json<ErrorBody>),
> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .modrinth_version_files(&req.hashes)
        .await
        .map_err(|e| proxy_error("modrinth_version_files", &e))?;
    Ok(Json(result))
}

/// GET /api/v1/mods/modrinth/game-versions:游戏版本列表(筛选数据源)代理。
async fn modrinth_game_versions(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<String>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .modrinth_game_versions()
        .await
        .map_err(|e| proxy_error("modrinth_game_versions", &e))?;
    Ok(Json(result))
}

/// GET /api/v1/mods/poggit/plugins:Poggit 全量发布列表(带缓存)代理。
/// releases.min.json 为数组,原样透传(字段命名对齐 Poggit 原生)。
async fn poggit_plugins(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let result = state
        .mod_market
        .poggit_plugins()
        .await
        .map_err(|e| proxy_error("poggit_plugins", &e))?;
    Ok(Json(result))
}

/// 市场代理网络错误 → HTTP 502(错误码对齐 ws.md `proxy_error`)。
fn proxy_error(code: &str, message: &str) -> (StatusCode, Json<ErrorBody>) {
    tracing::warn!(code, error = %message, "mod market proxy error");
    (
        StatusCode::BAD_GATEWAY,
        Json(ErrorBody {
            code: "proxy_error",
            message: format!("{code}: {message}"),
        }),
    )
}

// ────────────────────────── 实例操作处理器(openapi start/stop/restart/kill/command) ──────────────────────────

/// POST /api/v1/instances/{instanceId}/start:启动实例(202 受理,409 冲突)。
///
/// 经任务队列执行(同实例同 kind FIFO 串行);实际 spawn/握手在任务内完成,
/// 状态经轮询实例详情或 /ws/terminal 跟进。
async fn start_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .get_config(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    ensure_stopped(&state.procs, instance_id)?;

    let procs = state.procs.clone();
    state
        .tasks
        .submit(crate::task::model::TaskKind::Start, Some(instance_id), move |handle| async move {
            // 任务取消(排队期间被撤)直接放弃
            if handle.is_cancelled() {
                return Err(crate::task::model::TaskFailure::new("cancelled", "cancelled"));
            }
            procs.start(config)
                .await
                .map(|_| ())
                .map_err(|e| crate::task::model::TaskFailure::new(e.code(), proc_error_message(&e)))
        })
        .await
        .map_err(map_task_error)?;
    Ok(StatusCode::ACCEPTED)
}

/// POST /api/v1/instances/{instanceId}/stop:优雅停止(写 stopCommand,
/// 超时自动升级强杀;202 受理,409 冲突)。
async fn stop_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .get_config(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    ensure_running(&state.procs, instance_id)?;

    let procs = state.procs.clone();
    state
        .tasks
        .submit(crate::task::model::TaskKind::Stop, Some(instance_id), move |handle| async move {
            // 排队期间被取消 → 直接升级强杀,尽快释放
            if handle.is_cancelled() {
                let _ = procs.kill(instance_id).await;
                return Err(crate::task::model::TaskFailure::new("cancelled", "cancelled"));
            }
            procs.stop(&config)
                .await
                .map_err(|e| crate::task::model::TaskFailure::new(e.code(), proc_error_message(&e)))
        })
        .await
        .map_err(map_task_error)?;
    Ok(StatusCode::ACCEPTED)
}

/// POST /api/v1/instances/{instanceId}/restart:重启(运行中才行;优雅停止后再启动)。
async fn restart_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .get_config(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    ensure_running(&state.procs, instance_id)?;

    let procs = state.procs.clone();
    state
        .tasks
        .submit(crate::task::model::TaskKind::Restart, Some(instance_id), move |handle| async move {
            if handle.is_cancelled() {
                return Err(crate::task::model::TaskFailure::new("cancelled", "cancelled"));
            }
            let restart = async {
                procs.stop(&config).await?;
                procs.start(config).await.map(|_| ())
            };
            restart
                .await
                .map_err(|e| crate::task::model::TaskFailure::new(e.code(), proc_error_message(&e)))
        })
        .await
        .map_err(map_task_error)?;
    Ok(StatusCode::ACCEPTED)
}

/// POST /api/v1/instances/{instanceId}/kill:强杀(进程树)。
async fn kill_instance(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let config = state
        .instances
        .get_config(instance_id)
        .await
        .ok_or(instance_not_found(instance_id))?;
    let _ = config;
    ensure_running(&state.procs, instance_id)?;

    let procs = state.procs.clone();
    state
        .tasks
        .submit(crate::task::model::TaskKind::Kill, Some(instance_id), move |_| async move {
            procs.kill(instance_id)
                .await
                .map_err(|e| crate::task::model::TaskFailure::new(e.code(), proc_error_message(&e)))
        })
        .await
        .map_err(map_task_error)?;
    Ok(StatusCode::ACCEPTED)
}

/// POST /api/v1/instances/{instanceId}/command:程序化发送一行命令
/// (命令框通道;自动补换行;202 受理,409 未运行)。
async fn send_instance_command(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(instance_id): Path<Uuid>,
    Json(req): Json<CommandRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    if state
        .instances
        .get_config(instance_id)
        .await
        .is_none()
    {
        return Err(instance_not_found(instance_id));
    }
    let Some(handle) = state.procs.get(instance_id) else {
        return Err(conflict("instance_not_running", "instance is not running"));
    };
    if handle.is_done() {
        return Err(conflict("instance_not_running", "instance is not running"));
    }
    handle
        .write_line(&req.command)
        .await
        .map_err(map_proc_error)?;
    Ok(StatusCode::ACCEPTED)
}

/// 命令框请求(契约 CommandRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandRequest {
    pub command: String,
}

/// 实例须处于停止态,否则 409 instance_busy(启动语义)。
fn ensure_stopped(
    procs: &Arc<ProcManager>,
    instance_id: Uuid,
) -> Result<(), (StatusCode, Json<ErrorBody>)> {
    if let Some(snap) = procs.snapshot(instance_id) {
        if !matches!(snap.status, crate::instance::InstanceStatus::Stopped) {
            return Err(conflict(
                "instance_busy",
                "instance is starting/running/stopping",
            ));
        }
    }
    Ok(())
}

/// 实例须处于运行态,否则 409 instance_not_running(停止/重启/强杀语义)。
fn ensure_running(
    procs: &Arc<ProcManager>,
    instance_id: Uuid,
) -> Result<(), (StatusCode, Json<ErrorBody>)> {
    match procs.snapshot(instance_id) {
        Some(snap) if matches!(snap.status, crate::instance::InstanceStatus::Running) => Ok(()),
        Some(_) => Err(conflict(
            "instance_not_running",
            "instance is starting/stopping",
        )),
        None => Err(conflict("instance_not_running", "instance is not running")),
    }
}

fn conflict(code: &'static str, message: &str) -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::CONFLICT,
        Json(ErrorBody {
            code,
            message: message.into(),
        }),
    )
}

fn map_proc_error(e: ProcError) -> (StatusCode, Json<ErrorBody>) {
    match e {
        ProcError::Spawn(message) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ErrorBody {
                code: "spawn_error",
                message,
            }),
        ),
        other => conflict(other.code(), &proc_error_message(&other)),
    }
}

fn proc_error_message(e: &ProcError) -> String {
    match e {
        ProcError::Busy => "instance is already starting/running".into(),
        ProcError::NotRunning => "instance is not running".into(),
        ProcError::Spawn(message) => message.clone(),
    }
}

// ────────────────────────── 目录处理器(openapi catalog) ──────────────────────────

/// GET /api/v1/catalog/server-types:可用服务端类型列表(静态定义)。
async fn list_server_types(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<crate::catalog::ServerTypeInfo>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(crate::catalog::server_types()))
}

/// GET /api/v1/catalog/versions:版本列表(按服务端类型)。
#[derive(Debug, Deserialize)]
struct CatalogVersionsQuery {
    #[serde(rename = "type")]
    type_id: String,
}

async fn list_catalog_versions(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<CatalogVersionsQuery>,
) -> Result<Json<Vec<crate::catalog::ServerVersion>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let versions = state
        .catalog
        .versions(&query.type_id)
        .await
        .map_err(map_catalog_error)?;
    Ok(Json(versions))
}

/// GET /api/v1/catalog/loaders:加载器版本列表(hasLoader 类型,如 fabric)。
#[derive(Debug, Deserialize)]
struct CatalogLoadersQuery {
    #[serde(rename = "type")]
    _type_id: String,
    #[serde(rename = "mcVersion")]
    mc_version: String,
}

async fn list_catalog_loaders(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<CatalogLoadersQuery>,
) -> Result<Json<Vec<String>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let loaders = state
        .catalog
        .loaders(&query.mc_version)
        .await
        .map_err(map_catalog_error)?;
    Ok(Json(loaders))
}

/// GET /api/v1/catalog/download-info:服务端下载信息(直链 + 校验值 + 落盘文件名)。
#[derive(Debug, Deserialize)]
struct CatalogDownloadInfoQuery {
    #[serde(rename = "type")]
    type_id: String,
    #[serde(default)]
    version: Option<String>,
    #[serde(rename = "mcVersion", default)]
    mc_version: Option<String>,
    #[serde(rename = "loaderVersion", default)]
    loader_version: Option<String>,
}

async fn get_catalog_download_info(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<CatalogDownloadInfoQuery>,
) -> Result<Json<crate::catalog::ServerDownloadInfo>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let info = state
        .catalog
        .download_info(
            &query.type_id,
            query.version.as_deref(),
            query.mc_version.as_deref(),
            query.loader_version.as_deref(),
        )
        .await
        .map_err(map_catalog_error)?;
    Ok(Json(info))
}

/// 目录错误 → HTTP(openapi:400 参数/类型、404 版本不存在、502 上游)。
fn map_catalog_error(e: CatalogError) -> (StatusCode, Json<ErrorBody>) {
    match e {
        CatalogError::UnsupportedType(t) => (
            StatusCode::BAD_REQUEST,
            Json(ErrorBody {
                code: "unsupported_server_type",
                message: format!("unsupported server type: {t}"),
            }),
        ),
        CatalogError::BadRequest(message) => (
            StatusCode::BAD_REQUEST,
            Json(ErrorBody {
                code: "invalid_request",
                message,
            }),
        ),
        CatalogError::NotFound(message) => (
            StatusCode::NOT_FOUND,
            Json(ErrorBody {
                code: "not_found",
                message,
            }),
        ),
        CatalogError::Upstream(message) | CatalogError::NoResult(message) => {
            tracing::warn!("catalog upstream error: {message}");
            (
                StatusCode::BAD_GATEWAY,
                Json(ErrorBody {
                    code: "upstream_error",
                    message,
                }),
            )
        }
    }
}

// ────────────────────────── 运行时处理器(openapi runtimes) ──────────────────────────

/// GET /api/v1/runtimes:已安装运行时列表(openapi listRuntimes)。
async fn list_runtimes(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<RuntimeInfo>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(state.runtimes.list().await))
}

/// GET /api/v1/runtimes/catalog?type=&includeAll=:可安装版本清单(openapi getRuntimeCatalog)。
#[derive(Debug, Deserialize)]
struct RuntimeCatalogQuery {
    #[serde(rename = "type")]
    runtime_type: RuntimeType,
    /// 默认 false:frpc 仅返回最新 release;true 拉全量(openapi includeAll)。
    #[serde(rename = "includeAll", default)]
    include_all: bool,
}

async fn get_runtime_catalog(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<RuntimeCatalogQuery>,
) -> Result<Json<RuntimeCatalog>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let catalog = state
        .runtimes
        .catalog(query.runtime_type, query.include_all)
        .await
        .map_err(map_runtime_error)?;
    Ok(Json(catalog))
}

/// POST /api/v1/runtimes/install:安装运行时(openapi installRuntime)。
///
/// 解析为安装计划后提交全局任务(kind=download,instanceId 为空;同一时间仅
/// 允许一个安装任务,重复提交返回 409 task_conflict),进度经 GET /tasks/{jobId}
/// 或 WS task/progress 查询。
async fn install_runtime(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<RuntimeInstallRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let plan: InstallPlan = state
        .runtimes
        .plan_install(req)
        .await
        .map_err(map_runtime_error)?;

    let dm = state.download.clone();
    let runtimes = state.runtimes.clone();
    let task = state
        .tasks
        .submit(TaskKind::Download, None, move |handle| {
            run_runtime_install_task(handle, (*dm).clone(), runtimes, plan)
        })
        .await
        .map_err(map_task_error)?;

    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

/// DELETE /api/v1/runtimes/{runtimeId}:卸载运行时(openapi deleteRuntime)。
async fn delete_runtime(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(runtime_id): Path<String>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    state
        .runtimes
        .delete(&runtime_id)
        .await
        .map_err(map_runtime_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// 运行时错误 → HTTP(openapi:400 不支持/参数、404 版本或运行时不存在、502 上游)。
fn map_runtime_error(e: RuntimeError) -> (StatusCode, Json<ErrorBody>) {
    match e {
        RuntimeError::NotFound(message) => (
            StatusCode::NOT_FOUND,
            Json(ErrorBody {
                code: "not_found",
                message,
            }),
        ),
        RuntimeError::Unsupported(message) => (
            StatusCode::BAD_REQUEST,
            Json(ErrorBody {
                code: "unsupported_runtime_type",
                message,
            }),
        ),
        RuntimeError::BadRequest(message) => (
            StatusCode::BAD_REQUEST,
            Json(ErrorBody {
                code: "invalid_request",
                message,
            }),
        ),
        RuntimeError::Upstream(message) | RuntimeError::NoResult(message) => {
            tracing::warn!("runtime catalog upstream error: {message}");
            (
                StatusCode::BAD_GATEWAY,
                Json(ErrorBody {
                    code: "upstream_error",
                    message,
                }),
            )
        }
        RuntimeError::Io(e) => {
            tracing::error!("runtime io error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorBody {
                    code: "internal_error",
                    message: "internal server error".into(),
                }),
            )
        }
    }
}

// ────────────────────────── Frp 处理器(openapi frp) ──────────────────────────

/// 隧道列表(openapi listFrpTunnels)。
async fn list_frp_tunnels(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<TunnelInfo>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(state.frp.list()))
}

/// 创建隧道(openapi createFrpTunnel)。
async fn create_frp_tunnel(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<TunnelInput>,
) -> Result<(StatusCode, Json<TunnelInfo>), (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let tunnel = state.frp.create(input).map_err(map_frp_error)?;
    Ok((StatusCode::CREATED, Json(tunnel)))
}

/// 隧道详情(openapi getFrpTunnel)。
async fn get_frp_tunnel(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(tunnel_id): Path<Uuid>,
) -> Result<Json<TunnelInfo>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let tunnel = state
        .frp
        .get(tunnel_id)
        .ok_or_else(|| map_frp_error(FrpError::NotFound(format!("隧道 {tunnel_id} 不存在"))))?;
    Ok(Json(tunnel))
}

/// 更新隧道(openapi updateFrpTunnel)。
async fn update_frp_tunnel(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(tunnel_id): Path<Uuid>,
    Json(input): Json<TunnelInput>,
) -> Result<Json<TunnelInfo>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let tunnel = state.frp.update(tunnel_id, input).map_err(map_frp_error)?;
    Ok(Json(tunnel))
}

/// 删除隧道(openapi deleteFrpTunnel)。
async fn delete_frp_tunnel(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(tunnel_id): Path<Uuid>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    state.frp.delete(tunnel_id).map_err(map_frp_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// 启动 frpc 请求体(openapi startFrpc)。
#[derive(Debug, Deserialize)]
struct FrpStartRequest {
    tunnel_id: Uuid,
}

/// 启动 frpc(openapi startFrpc)。
async fn start_frpc(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<FrpStartRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    state.frp.start(req.tunnel_id).await.map_err(map_frp_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// 停止 frpc(openapi stopFrpc)。
async fn stop_frpc(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    state.frp.stop().await.map_err(map_frp_error)?;
    Ok(StatusCode::NO_CONTENT)
}

/// 运行状态(openapi getFrpStatus)。
async fn get_frp_status(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<FrpStatus>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(state.frp.status()))
}

/// frpc 日志查询参数(openapi getFrpLogs)。
#[derive(Debug, Deserialize)]
struct FrpLogsQuery {
    #[serde(default)]
    tail: Option<usize>,
}

/// frpc 日志(openapi getFrpLogs)。
async fn get_frp_logs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<FrpLogsQuery>,
) -> Result<Json<Vec<String>>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    Ok(Json(state.frp.logs(query.tail.unwrap_or(200))))
}

/// Frp 错误 → HTTP(openapi:400 参数、404 隧道不存在、409 状态冲突/运行时缺失、500 内部)。
fn map_frp_error(e: FrpError) -> (StatusCode, Json<ErrorBody>) {
    let code = e.code();
    let message = e.to_string();
    let status = match code {
        "tunnel_not_found" => StatusCode::NOT_FOUND,
        "duplicate_name" | "frpc_busy" | "frpc_not_running" | "frpc_runtime_missing" => {
            StatusCode::CONFLICT
        }
        "invalid_request" => StatusCode::BAD_REQUEST,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    };
    (status, Json(ErrorBody { code, message }))
}

// ────────────────────────── 系统监控处理器(openapi monitor) ──────────────────────────

/// GET /api/v1/monitor/snapshot:系统监控快照(openapi getMonitorSnapshot;
/// 实时曲线走 WS monitor/stats,P1 后续接入)。
async fn get_monitor_snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<MonitorSnapshot>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    // sysinfo 采样为同步阻塞但微秒级,无需 spawn_blocking
    Ok(Json(state.monitor.snapshot()))
}

// ────────────────────────── 任务处理器(openapi tasks) ──────────────────────────

/// GET /api/v1/tasks/{taskId}:查询单个任务详情(openapi getTask)。
async fn get_task(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(task_id): Path<Uuid>,
) -> Result<Json<Task>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let task = state
        .tasks
        .get(task_id)
        .await
        .ok_or(task_not_found(task_id))?;
    Ok(Json(task))
}

/// DELETE /api/v1/tasks/{taskId}:取消任务(openapi cancelTask)。
///
/// queued 直接移除;running 置取消标志由执行体尽快中断;
/// 已终结任务返回 409。取消成功回显最终 Task(status=cancelled)。
async fn cancel_task(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(task_id): Path<Uuid>,
) -> Result<Json<Task>, (StatusCode, Json<ErrorBody>)> {
    require_auth(&state, &headers).await?;
    let task = state
        .tasks
        .cancel(task_id)
        .await
        .map_err(map_task_error)?;
    Ok(Json(task))
}

// ────────────────────────── 鉴权辅助 ──────────────────────────

/// instance/fs 等端点统一鉴权:Bearer token 校验(与 auth 端点一致的口径)。
pub(crate) async fn require_auth(
    state: &AppState,
    headers: &HeaderMap,
) -> Result<(), (StatusCode, Json<ErrorBody>)> {
    let auth = state.auth.lock().await;
    let token = bearer_token(headers)
        .ok_or_else(|| unauthorized("invalid_token", "missing bearer token"))?;
    if !auth.verify_token(token) {
        return Err(unauthorized("invalid_token", "invalid bearer token"));
    }
    Ok(())
}

/// 本机端点来源约束:仅允许回环地址(127.0.0.1/::1)。
/// TCP 端口映射在本机转发,peer 仍为回环,不受影响;
/// 未开映射时非回环来源(局域网等)即使持有凭证也无法访问。
fn ensure_loopback(
    peer: std::net::SocketAddr,
) -> Result<(), (StatusCode, Json<ErrorBody>)> {
    if peer.ip().is_loopback() {
        return Ok(());
    }
    Err((
        StatusCode::FORBIDDEN,
        Json(ErrorBody {
            code: "forbidden",
            message: "local login endpoint is restricted to loopback source".into(),
        }),
    ))
}

/// 从 Authorization 头提取 Bearer token(HTTP bearer 鉴权;WS 终端亦复用)。
pub(crate) fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let value = headers
        .get(axum::http::header::AUTHORIZATION)?
        .to_str()
        .ok()?;
    value.strip_prefix("Bearer ")
}

fn unauthorized(code: &'static str, message: &str) -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::UNAUTHORIZED,
        Json(ErrorBody {
            code,
            message: message.into(),
        }),
    )
}

fn bad_request(code: &'static str, message: &str) -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::BAD_REQUEST,
        Json(ErrorBody {
            code,
            message: message.into(),
        }),
    )
}

fn internal_error(e: crate::error::DaemonError) -> (StatusCode, Json<ErrorBody>) {
    tracing::error!("internal error: {e}");
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(ErrorBody {
            code: "internal_error",
            message: "internal server error".into(),
        }),
    )
}

fn default_page() -> u64 {
    1
}

fn default_page_size() -> u64 {
    20
}

fn instance_not_found(id: Uuid) -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::NOT_FOUND,
        Json(ErrorBody {
            code: "not_found",
            message: format!("instance {id} not found"),
        }),
    )
}

/// 任务不存在(openapi 404,错误码对齐 ws.md `task_not_found`)。
fn task_not_found(id: Uuid) -> (StatusCode, Json<ErrorBody>) {
    (
        StatusCode::NOT_FOUND,
        Json(ErrorBody {
            code: "task_not_found",
            message: format!("task {id} not found"),
        }),
    )
}

/// 任务服务错误 → HTTP(openapi 409 task_conflict / 404)。
fn map_task_error(
    e: crate::task::service::TaskError_,
) -> (StatusCode, Json<ErrorBody>) {
    match e {
        crate::task::service::TaskError_::NotFound(id) => task_not_found(id),
        crate::task::service::TaskError_::Conflict(..) => (
            StatusCode::CONFLICT,
            Json(ErrorBody {
                code: "task_conflict",
                message: "task is already finished or still running the same kind".into(),
            }),
        ),
    }
}

/// 管理器错误 → HTTP 状态码(openapi ErrorResponse.code)。
fn map_manager_error(e: ManagerError) -> (StatusCode, Json<ErrorBody>) {
    match e {
        ManagerError::NotFound(id) => instance_not_found(id),
        ManagerError::DuplicateName(name) => (
            StatusCode::CONFLICT,
            Json(ErrorBody {
                code: "duplicate_name",
                message: format!("duplicate instance name: {name}"),
            }),
        ),
        ManagerError::Invalid(message) => (
            StatusCode::BAD_REQUEST,
            Json(ErrorBody {
                code: "invalid_request",
                message,
            }),
        ),
        ManagerError::Io(e) => {
            tracing::error!("instance persist error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorBody {
                    code: "internal_error",
                    message: "internal server error".into(),
                }),
            )
        }
        ManagerError::Serde(e) => {
            tracing::error!("instance persist error: {e}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ErrorBody {
                    code: "internal_error",
                    message: "internal server error".into(),
                }),
            )
        }
    }
}