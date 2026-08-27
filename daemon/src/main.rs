//! EdgeCube daemon(守护进程)。
//!
//! 初始化流程:
//! 1. 载入配置(缺失则生成默认配置落盘,支持 CLI 覆盖监听地址);
//! 2. 创建初始账户(首次启动生成随机凭证并打印到控制台,见 openapi /auth/login);
//! 3. 开始监听 HTTP 服务 `/api/v1`(listen 地址来自 config:network)。

mod auth;
mod config;
mod error;
mod server;

use std::fs;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::Parser;

use crate::auth::AuthStore;
use crate::config::{data_dir, DaemonConfig, Overrides};
use crate::error::Result;

#[derive(Debug, Parser)]
#[command(
    name = "edgecube-daemon",
    version,
    about = "EdgeCube 守护进程:载入配置、初始化账户并开始监听 API",
    max_term_width = 100
)]
struct Args {
    /// 数据目录(默认 EDGECUBE_HOME 或系统数据目录/edgecube)
    #[arg(long)]
    data_dir: Option<PathBuf>,

    /// 监听地址,覆盖配置 network.bind(默认 127.0.0.1)
    #[arg(long)]
    bind: Option<String>,

    /// 监听端口,覆盖配置 network.port(默认 8760)
    #[arg(long)]
    port: Option<u16>,
}

#[tokio::main]
async fn main() -> ExitCode {
    init_tracing();

    let args = Args::parse();
    match run(args).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("daemon failed: {e}");
            tracing::error!("daemon exited with error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn init_tracing() {
    use tracing_subscriber::EnvFilter;

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

async fn run(args: Args) -> Result<()> {
    // ── 1. 载入配置 ──────────────────────────────────────────────
    let dir = match args.data_dir {
        Some(dir) => dir,
        None => data_dir()?,
    };
    fs::create_dir_all(&dir)?;
    tracing::info!(data_dir = %dir.display(), "data directory ready");

    let overrides = Overrides {
        bind: args.bind,
        port: args.port,
    };
    let cfg = DaemonConfig::load(&dir.join("config.json"), &overrides)?;
    tracing::info!(
        bind = %cfg.network.bind,
        port = cfg.network.port,
        "config loaded"
    );

    // ── 2. 初始账户 ──────────────────────────────────────────────
    let mut store = AuthStore::new(&dir)?;
    let created_creds = store.ensure_account()?;
    store.load_devices();

    // ── 3. 开始监听 ──────────────────────────────────────────────
    let addr: SocketAddr = format!("{}:{}", cfg.network.bind, cfg.network.port).parse()?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(addr = %addr, "daemon listening");

    if let Some(cred) = created_creds {
        // openapi /auth/login:首次启动生成随机凭证并打印到控制台
        println!("===================================================================");
        println!("EdgeCube 首次启动,请使用以下随机凭证登录(登录后可通过 API 修改):");
        println!("  用户名: {}", cred.username);
        println!("  密  码: {}", cred.password);
        println!("  登录:   POST http://{addr}/api/v1/auth/login");
        println!("===================================================================");
        tracing::warn!("initial credentials printed to console");
    }

    axum::serve(
        listener,
        server::router(store).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    tracing::info!("daemon stopped");
    Ok(())
}

/// Ctrl+C / SIGTERM 优雅停机信号。
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
    tracing::info!("shutdown signal received");
}