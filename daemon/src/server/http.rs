//! HTTP 层：把框架自带路由、模块子路由、鉴权与 CORS 组装成一棵 axum 路由树。

use std::time::Duration;

use axum::extract::{Request, State};
use axum::http::{HeaderValue, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde_json::{Value, json};
use tower_http::cors::{AllowOrigin, Any, CorsLayer};
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use crate::error::{RpcError, RpcResult};
use crate::module::HttpMount;
use crate::server::ws;
use crate::state::AppState;
use crate::util::humanize_secs;
use crate::{PRODUCT, PROTOCOL_VERSION, VERSION};

/// 组装根路由。
///
/// 结构：
///
/// ```text
/// /                    服务概览（JSON，不鉴权）
/// /healthz             存活探针（不鉴权，给 systemd / 容器用）
/// {ws_path}            WebSocket 入口
/// /api/info            服务信息
/// /api/modules         模块清单
/// /api/methods         WS 方法清单
/// /api/topics          事件主题清单
/// /api/protocol        WS 协议速查（给人看的）
/// ...各模块挂载的路由   ← 由 Module::register 提供
/// ```
///
/// 除了 `/` 与 `/healthz`，**其余接口（含所有模块路由）都要过鉴权**。
///
/// # Panics
///
/// 模块路由与框架路由路径冲突时 axum 会 panic。这是有意的：启动即失败，
/// 好过运行期出现「谁覆盖了谁」的诡异行为。
pub fn build(app: &AppState, mounts: Vec<HttpMount>) -> Router {
    let state = app.clone();
    let ws_path = app.config.server.ws_path.clone();

    // 免鉴权：探活与概览。运维工具通常没法带令牌。
    let public = Router::new()
        .route("/healthz", get(healthz))
        .route("/", get(index));

    // 框架自省接口：都是短请求，套一层超时防 handler 卡死。
    let introspect = Router::new()
        .route("/api/info", get(api_info))
        .route("/api/modules", get(api_modules))
        .route("/api/methods", get(api_methods))
        .route("/api/topics", get(api_topics))
        .route("/api/protocol", get(api_protocol))
        .layer(api_timeout_layer(app.config.server.request_timeout_secs));

    let mut protected = Router::new()
        .route(&ws_path, get(ws::upgrade))
        .merge(introspect);

    // 模块路由：和框架接口一起套鉴权，但**不套**超时层——
    // 模块可能要做长轮询，耗时由模块自己控制。
    for mount in mounts {
        tracing::debug!(mount = %mount.label, "合并模块路由");
        protected = protected.merge(mount.router);
    }

    // route_layer 只作用于当前已注册的路由，所以它必须在 merge 模块路由之后、
    // 与 public 合并之前调用。
    public
        .merge(protected.route_layer(middleware::from_fn_with_state(state.clone(), require_token)))
        .with_state(state)
        .layer(TraceLayer::new_for_http())
        .layer(cors_layer(&app.config.server.cors_origins))
}

/// 鉴权中间件。
///
/// 放行的两种情况：
///
/// 1. 配置里没有令牌（本机开发）；
/// 2. 请求带了正确的令牌：`Authorization: Bearer <token>`、
///    `X-EdgeCube-Token: <token>`，或 `?token=<token>`
///    （浏览器 WebSocket API 不能自定义请求头，查询串是唯一可行方式）。
///
/// `/healthz` 与 `/` 在鉴权层之外，方便 systemd / 容器探活。
async fn require_token(State(app): State<AppState>, req: Request, next: Next) -> Response {
    let Some(expected) = app.config.server.effective_token() else {
        return next.run(req).await;
    };

    let provided = extract_token(&req);
    match provided {
        Some(token) if constant_eq(token.as_bytes(), expected.as_bytes()) => next.run(req).await,
        Some(_) => {
            tracing::warn!(path = %req.uri().path(), "令牌不正确");
            unauthorized("令牌不正确")
        }
        None => {
            tracing::debug!(path = %req.uri().path(), "缺少令牌");
            unauthorized("缺少访问令牌")
        }
    }
}

fn unauthorized(message: &str) -> Response {
    (
        StatusCode::UNAUTHORIZED,
        [(header::WWW_AUTHENTICATE, "Bearer")],
        Json(json!({ "ok": false, "error": RpcError::unauthorized(message) })),
    )
        .into_response()
}

/// 从请求里抠出令牌。三种位置都支持，顺序：Authorization → 专用头 → 查询串。
fn extract_token(req: &Request) -> Option<String> {
    if let Some(value) = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
    {
        // 只修掉前导空白：整体 trim 会把 `Bearer   ` 变成 `Bearer`，
        // 那样「有 scheme 但没令牌」就被误当成令牌了。
        let value = value.trim_start();
        // 有 scheme 时只认 Bearer；不认识的方案直接视为「没带令牌」。
        let candidate = match value.split_once(' ') {
            Some((scheme, rest)) => {
                if !scheme.eq_ignore_ascii_case("bearer") {
                    return None;
                }
                rest
            }
            // 没写 scheme 时整串当令牌，方便 `curl -H 'Authorization: xxx'` 手测。
            None => value,
        };
        let candidate = candidate.trim();
        if !candidate.is_empty() {
            return Some(candidate.to_string());
        }
    }

    if let Some(value) = req
        .headers()
        .get("x-edgecube-token")
        .and_then(|v| v.to_str().ok())
        && !value.trim().is_empty()
    {
        return Some(value.trim().to_string());
    }

    let query = req.uri().query()?;
    for pair in query.split('&') {
        if let Some(value) = pair.strip_prefix("token=")
            && !value.is_empty()
        {
            return Some(value.to_string());
        }
    }
    None
}

/// 定长比较，避免用 `==` 提前返回泄露令牌长度信息。
fn constant_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b) {
        diff |= x ^ y;
    }
    diff == 0
}

fn cors_layer(origins: &[String]) -> CorsLayer {
    let base = CorsLayer::new()
        .allow_methods(Any)
        .allow_headers(Any)
        .max_age(Duration::from_secs(600));

    if origins.iter().any(|o| o.trim() == "*") {
        tracing::debug!("CORS: 放开全部来源");
        return base.allow_origin(Any);
    }

    let list: Vec<HeaderValue> = origins
        .iter()
        .filter_map(|o| match o.parse::<HeaderValue>() {
            Ok(v) => Some(v),
            Err(_) => {
                tracing::warn!(origin = %o, "忽略非法的 CORS 来源");
                None
            }
        })
        .collect();
    tracing::debug!(count = list.len(), "CORS: 白名单");
    base.allow_origin(AllowOrigin::list(list))
}

// ---------------------------------------------------------------------------
// 处理器
// ---------------------------------------------------------------------------

async fn healthz() -> &'static str {
    "ok"
}

async fn index(State(app): State<AppState>) -> Json<Value> {
    Json(json!({
        "product": PRODUCT,
        "version": VERSION,
        "protocol_version": PROTOCOL_VERSION,
        "uptime_ms": app.uptime_ms(),
        "uptime_human": humanize_secs(app.uptime_secs()),
        "ws_path": app.config.server.ws_path,
        "endpoints": ["/healthz", "/api/info", "/api/modules", "/api/methods", "/api/topics", "/api/protocol"],
    }))
}

async fn api_info(State(app): State<AppState>) -> Json<Value> {
    Json(json!({
        "product": PRODUCT,
        "version": VERSION,
        "protocol_version": PROTOCOL_VERSION,
        "pid": std::process::id(),
        "os": std::env::consts::OS,
        "arch": std::env::consts::ARCH,
        "bind": app.bind_display(),
        "ws_path": app.config.server.ws_path,
        "auth_required": app.config.server.auth_required(),
        "config_path": app.config_path_string(),
        "started_at_ms": app.started_at_ms,
        "uptime_ms": app.uptime_ms(),
        "uptime_human": humanize_secs(app.uptime_secs()),
        "connections": app.conns.count().await,
        "subscribers": app.bus.subscriber_count(),
        "shutting_down": app.is_shutting_down(),
    }))
}

async fn api_modules(State(app): State<AppState>) -> Json<Value> {
    Json(app.registry.summary())
}

async fn api_methods(State(app): State<AppState>) -> Json<Value> {
    Json(json!({ "methods": app.registry.method_infos() }))
}

async fn api_topics(State(app): State<AppState>) -> Json<Value> {
    Json(json!({ "topics": app.registry.topics() }))
}

async fn api_protocol() -> Json<Value> {
    Json(ws::protocol_doc())
}

// ---------------------------------------------------------------------------
// 给模块用的响应工具
// ---------------------------------------------------------------------------

/// 把 [`RpcResult`] 转成 HTTP 响应。
///
/// 模块写 REST 接口时统一用它，错误码与 WS 侧保持同一套，前端不用维护两份映射。
pub fn api_result(result: RpcResult<Value>) -> Response {
    match result {
        Ok(value) => (StatusCode::OK, Json(json!({ "ok": true, "result": value }))).into_response(),
        Err(error) => (
            status_for(&error.code),
            Json(json!({ "ok": false, "error": error })),
        )
            .into_response(),
    }
}

/// 错误码 → HTTP 状态码。
pub fn status_for(code: &str) -> StatusCode {
    match code {
        "bad_request" | "invalid_params" => StatusCode::BAD_REQUEST,
        "unauthorized" => StatusCode::UNAUTHORIZED,
        "forbidden" => StatusCode::FORBIDDEN,
        "not_found" | "method_not_found" => StatusCode::NOT_FOUND,
        "timeout" => StatusCode::GATEWAY_TIMEOUT,
        "busy" => StatusCode::TOO_MANY_REQUESTS,
        "unavailable" => StatusCode::SERVICE_UNAVAILABLE,
        // 领域模块自己的 `*_not_found` / `*_taken` 也跟着走 404 / 409，
        // 免得每个新模块都要回来改这里（如 instance_not_found、instance_name_taken）
        other if other.ends_with("_not_found") => StatusCode::NOT_FOUND,
        other if other.ends_with("_taken") => StatusCode::CONFLICT,
        other if other.ends_with("_exists") => StatusCode::CONFLICT,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

/// 用超时包裹框架自带的 `/api/*` 路由。
///
/// 注意：**不**给 WS 路由和模块路由套这一层——长连接与长轮询会被它误杀，
/// 模块若要限制耗时请自己 `tokio::time::timeout`。
pub fn api_timeout_layer(secs: u64) -> TimeoutLayer {
    TimeoutLayer::with_status_code(
        StatusCode::REQUEST_TIMEOUT,
        Duration::from_secs(secs.max(1)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request as HttpRequest;

    fn req(auth: Option<&str>, query: Option<&str>) -> Request {
        let mut builder = HttpRequest::builder().uri(match query {
            Some(q) => format!("/api/info?{q}"),
            None => "/api/info".to_string(),
        });
        if let Some(a) = auth {
            builder = builder.header(header::AUTHORIZATION, a);
        }
        builder.body(Body::empty()).unwrap()
    }

    #[test]
    fn token_from_bearer_header() {
        assert_eq!(
            extract_token(&req(Some("Bearer s3cret"), None)).as_deref(),
            Some("s3cret")
        );
        assert_eq!(
            extract_token(&req(Some("s3cret"), None)).as_deref(),
            Some("s3cret")
        );
        assert_eq!(
            extract_token(&req(Some("Bearer   spaced  "), None)).as_deref(),
            Some("spaced")
        );
    }

    #[test]
    fn token_from_dedicated_header() {
        let r = HttpRequest::builder()
            .uri("/api/info")
            .header("x-edgecube-token", "abc")
            .body(Body::empty())
            .unwrap();
        assert_eq!(extract_token(&r).as_deref(), Some("abc"));
    }

    #[test]
    fn token_from_query_string() {
        assert_eq!(
            extract_token(&req(None, Some("token=abc&x=1"))).as_deref(),
            Some("abc")
        );
        assert_eq!(
            extract_token(&req(None, Some("x=1&token=abc"))).as_deref(),
            Some("abc")
        );
        assert_eq!(extract_token(&req(None, Some("x=1"))), None);
        assert_eq!(extract_token(&req(None, None)), None);
    }

    #[test]
    fn empty_credentials_are_treated_as_absent() {
        assert_eq!(extract_token(&req(Some("Bearer    "), None)), None);
        assert_eq!(extract_token(&req(None, Some("token="))), None);
    }

    #[test]
    fn constant_eq_matches_exactly() {
        assert!(constant_eq(b"abc", b"abc"));
        assert!(!constant_eq(b"abc", b"abd"));
        assert!(!constant_eq(b"abc", b"ab"));
        assert!(constant_eq(b"", b""));
    }

    #[test]
    fn status_mapping_covers_protocol_codes() {
        assert_eq!(status_for("method_not_found"), StatusCode::NOT_FOUND);
        assert_eq!(status_for("invalid_params"), StatusCode::BAD_REQUEST);
        assert_eq!(status_for("busy"), StatusCode::TOO_MANY_REQUESTS);
        assert_eq!(status_for("timeout"), StatusCode::GATEWAY_TIMEOUT);
        assert_eq!(status_for("unavailable"), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(status_for("forbidden"), StatusCode::FORBIDDEN);
        assert_eq!(status_for("internal"), StatusCode::INTERNAL_SERVER_ERROR);
        // 模块自定义码按后缀归类
        assert_eq!(status_for("instance_not_found"), StatusCode::NOT_FOUND);
        assert_eq!(status_for("instance_name_taken"), StatusCode::CONFLICT);
    }
}
