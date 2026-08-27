//! HTTP 服务:phase 0 中与初始化直接相关的端点
//! (`GET /api/v1/health` 未配对可访问,`POST /api/v1/auth/login` 换取长期 token),
//! 其余端点按 openapi.yaml 阶段计划后续补充。
//!
//! 鉴权:除 /auth/* 与 /health 外全部需要 `Authorization: Bearer <token>`。

use std::sync::Arc;
use std::time::Instant;

use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use crate::auth::AuthStore;

#[derive(Clone)]
pub struct AppState {
    pub auth: Arc<Mutex<AuthStore>>,
    pub started_at: Instant,
}

/// 组装路由(挂载于 /api/v1)。
pub fn router(auth: AuthStore) -> Router {
    let state = AppState {
        auth: Arc::new(Mutex::new(auth)),
        started_at: Instant::now(),
    };
    Router::new()
        .route("/api/v1/health", get(health))
        .route("/api/v1/auth/login", post(login))
        .route("/api/v1/auth/local-login/challenge", post(local_challenge))
        .route("/api/v1/auth/local-login", post(local_login))
        .route("/api/v1/auth/change-password", post(change_password))
        .route("/api/v1/auth/change-username", post(change_username))
        .fallback(not_found)
        .with_state(state)
}

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
    #[serde(default)]
    pub device_name: Option<String>,
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
    pub device_name: Option<String>,
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

// ────────────────────────── 处理器 ──────────────────────────

/// GET /api/v1/health:健康检查(未配对可访问)。
async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        daemon: "rust",
        platform: format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH),
        uptime_seconds: state.started_at.elapsed().as_secs(),
        instances: Instances { running: 0, total: 0 },
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
        auth.issue_token(req.device_name.as_deref())
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
        auth.issue_token(req.device_name.as_deref())
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

/// 从 Authorization 头提取 Bearer token(HTTP bearer 鉴权)。
fn bearer_token(headers: &HeaderMap) -> Option<&str> {
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