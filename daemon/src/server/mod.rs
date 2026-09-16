//! 服务层：绑定端口、组装路由、对外服务、优雅关闭。
//!
//! 拆成 [`bind`] 与 [`Bound::serve`] 两步，是为了让集成测试能先绑到
//! `127.0.0.1:0` 拿到真实端口，再在后台把服务跑起来。

pub mod http;
pub mod ws;

use std::net::SocketAddr;
use std::time::Duration;

use axum::Router;
use serde_json::json;
use tokio::net::TcpListener;

use crate::error::{Error, Result};
use crate::event::topics;
use crate::state::AppState;
use crate::util::now_ms;

/// 已绑定端口、路由已组装，但还没开始接受连接。
pub struct Bound {
    listener: TcpListener,
    /// 实际监听地址（端口配 0 时这里是系统分配的真实端口）。
    pub local_addr: SocketAddr,
    router: Router,
}

/// 绑定监听端口并组装路由树。
///
/// 到这一步为止的任何失败（端口被占、模块路由冲突）都是启动失败，
/// 不会留下半个跑起来的服务。
pub async fn bind(app: &AppState) -> Result<Bound> {
    let addr = format!("{}:{}", app.config.server.host, app.config.server.port);
    let listener = TcpListener::bind(&addr)
        .await
        .map_err(|e| Error::other(format!("无法监听 {addr}: {e}")))?;
    let local_addr = listener.local_addr()?;

    let router = http::build(app, app.registry.take_http_mounts());
    // 记下真实地址：配置里写 port = 0 时，只有这里能拿到实际端口
    app.set_bound_addr(local_addr);
    Ok(Bound {
        listener,
        local_addr,
        router,
    })
}

impl Bound {
    /// 开始服务，直到 [`AppState::cancel`] 被触发。
    pub async fn serve(self, app: &AppState) -> Result<()> {
        let Bound {
            listener,
            local_addr,
            router,
        } = self;
        let cancel = app.cancel.clone();

        tracing::info!(
            addr = %local_addr,
            ws_path = %app.config.server.ws_path,
            auth = app.config.server.auth_required(),
            modules = app.registry.enabled_descriptors().len(),
            methods = app.registry.method_count(),
            "服务已就绪"
        );

        app.bus.publish_from(
            Some("core"),
            topics::STARTED,
            json!({
                "addr": local_addr.to_string(),
                "ws_path": app.config.server.ws_path,
                "auth_required": app.config.server.auth_required(),
                "ts": now_ms(),
            }),
        );

        axum::serve(
            listener,
            router.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .with_graceful_shutdown(async move { cancel.cancelled().await })
        .await?;

        Ok(())
    }
}

/// 一条龙：启动模块 → 绑定 → 服务 → 关闭。
pub async fn run(app: AppState) -> Result<()> {
    // 1) 模块后台任务先起，这样它们推的第一条事件不会因为「服务还没监听」而丢。
    app.registry.start_all(&app).await?;

    // 2) 绑定（失败就把刚起来的模块关掉，别留下孤儿任务）
    let bound = match bind(&app).await {
        Ok(b) => b,
        Err(e) => {
            app.registry.stop_all().await;
            return Err(e);
        }
    };
    let local_addr = bound.local_addr;

    // 3) 服务
    let serve_result = bound.serve(&app).await;

    // 4) 关闭
    tracing::info!("开始优雅关闭");
    app.bus.publish_from(
        Some("core"),
        topics::SHUTTING_DOWN,
        json!({ "grace_secs": app.config.server.shutdown_grace_secs, "ts": now_ms() }),
    );

    // 先给连接发告别帧，再等它们自己收尾。
    let notified = app.conns.close_all(1001, "server shutting down").await;
    if notified > 0 {
        tracing::info!(notified, "已通知连接断开");
        drain(&app).await;
    }

    let failures = app.registry.stop_all().await;
    if !failures.is_empty() {
        tracing::warn!(?failures, "部分模块关闭异常");
    }

    tracing::info!(addr = %local_addr, uptime = crate::util::humanize_secs(app.uptime_secs()), "已停止");
    serve_result
}

/// 等连接自己退出，最多等 `shutdown_grace_secs`。超时就放它走。
async fn drain(app: &AppState) {
    let grace = Duration::from_secs(app.config.server.shutdown_grace_secs);
    let deadline = tokio::time::Instant::now() + grace;

    loop {
        let remaining = app.conns.count().await;
        if remaining == 0 {
            return;
        }
        if tokio::time::Instant::now() >= deadline {
            tracing::warn!(remaining, "关闭宽限期已到，仍有连接未退出");
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}
