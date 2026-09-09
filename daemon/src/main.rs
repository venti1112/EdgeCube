//! EdgeCube daemon(守护进程)。
//!
//! 初始化流程:
//! 1. 载入配置(缺失则生成默认配置落盘,支持 CLI 覆盖监听地址);
//! 2. 创建初始账户(首次启动生成随机凭证并打印到控制台,见 openapi /auth/login);
//! 3. 开始监听 HTTP 服务 `/api/v1`(listen 地址来自 config:network)。

mod auth;
mod catalog;
mod config;
mod download;
mod error;
mod frp;
mod fs;
mod instance;
mod mod_market;
mod mod_meta;
mod monitor;
mod players;
mod proc;
mod runtime;
mod server;
mod server_core;
mod task;
mod terminal;
mod transfer;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;

use clap::Parser;

use crate::auth::AuthStore;
use crate::catalog::Catalog;
use crate::config::{data_dir, DaemonConfig, Overrides};
use crate::download::DownloadManager;
use crate::error::Result;
use crate::fs::FsManager;
use crate::instance::InstanceManager;
use crate::mod_market::ModMarket;
use crate::task::service::TaskService;

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
    let args = Args::parse();

    // 日志初始化依赖 config.json 的 log_level:先解析数据目录并尽力读取配置
    // (缺失/损坏时回退 info,不阻塞启动;RUST_LOG 环境变量始终优先)。
    let dir = match args.data_dir.clone() {
        Some(dir) => dir,
        None => match data_dir() {
            Ok(dir) => dir,
            Err(e) => {
                eprintln!("failed to resolve data directory: {e}");
                return ExitCode::FAILURE;
            }
        },
    };
    let log_level = read_config_log_level(&dir.join("config.json"));
    init_tracing(&log_level);

    match run(args, dir).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("daemon failed: {e}");
            tracing::error!("daemon exited with error: {e}");
            ExitCode::FAILURE
        }
    }
}

/// 从配置文件尽力读取日志等级;文件缺失/损坏时回退 "info"。
fn read_config_log_level(path: &std::path::Path) -> String {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str::<DaemonConfig>(&raw).ok())
        .map(|cfg| cfg.log_level)
        .unwrap_or_else(|| "info".into())
}

/// 初始化 tracing:配置文件 `log_level` 优先;解析失败时回退 `RUST_LOG`
/// 环境变量,最后兜底 info。
fn init_tracing(level: &str) {
    use tracing_subscriber::EnvFilter;

    let filter = EnvFilter::try_new(level)
        .unwrap_or_else(|_| {
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"))
        });
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

async fn run(args: Args, dir: PathBuf) -> Result<()> {
    // ── 1. 载入配置 ──────────────────────────────────────────────
    std::fs::create_dir_all(&dir)?;
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

    // ── 3. 实例配置管理 ──────────────────────────────────────────
    let instances = InstanceManager::load(&dir)?;
    tracing::info!("instance manager ready");

    // ── 4. 任务队列服务(实例操作/下载等异步任务调度) ────────────
    let tasks = TaskService::new();
    tracing::info!("task service ready");

    // ── 5. 下载引擎(创建实例触发的服务端下载,内部能力) ──────────
    let download = Arc::new(DownloadManager::new());
    tracing::info!("download engine ready");

    // ── 6. 服务端版本目录(「下载服务端」向导数据源) ────────────────
    let catalog = Arc::new(Catalog::new());
    tracing::info!("server catalog ready");

    // ── 7. 运行时环境管理(/runtimes/*:Java 等环境下载与卸载) ──────
    let runtimes = Arc::new(runtime::RuntimeManager::load(&dir)?);
    tracing::info!("runtime manager ready");

    // ── 8. 系统监控(/monitor/snapshot:CPU/内存/磁盘/网络) ─────────
    let monitor = Arc::new(monitor::MonitorManager::new());
    tracing::info!("monitor manager ready");

    // ── 9. 实例进程管理(PTY 启动/停止/强杀 + 终端 I/O) ────────────
    let procs = Arc::new(proc::ProcManager::new(&dir));
    tracing::info!(
        pty = %proc::ProcManager::pty_path().display(),
        "process manager ready"
    );
    let procs_for_resolver = procs.clone();
    instances.set_runtime(Arc::new(move |id| procs_for_resolver.snapshot(id)));

    // 实例声明的 runtimeId → 运行时主目录:让启动的 pty 将 `{运行时}/bin`
    // 前置注入 PATH,使裸 `java`/`php` 启动命令命中该运行时。
    let runtimes_for_procs = runtimes.clone();
    procs.set_runtime_resolver(Arc::new(move |id| {
        let runtimes = runtimes_for_procs.clone();
        let id = id.to_string();
        Box::pin(async move { runtimes.get(&id).await.map(|info| PathBuf::from(info.path)) })
    }));

    // ── 10. 文件管理(/fs/*:分片上传会话等) ──────────────────────
    let fs = Arc::new(FsManager::default());
    tracing::info!("file manager ready");

    // ── 11. 插件/模组元数据解析与缓存(/instances/{id}/mods/*) ──
    let mod_meta = Arc::new(mod_meta::ModMetaManager::new());
    tracing::info!("mod metadata manager ready");

    // ── 11b. 插件/模组市场代理(Modrinth/Poggit,网络收敛在后端) ──
    let mod_market = Arc::new(ModMarket::new());
    tracing::info!("mod market proxy ready");

    // ── 11c. Frp 内网穿透(隧道注册表 + 全局唯一 frpc 进程) ──────
    let frp = Arc::new(frp::FrpManager::load(&dir)?);
    // frpc 二进制来自运行时管理(fatedier/frp GitHub Releases,按当前平台安装)
    let runtimes_for_frp = runtimes.clone();
    frp.set_frpc_resolver(Arc::new(move || runtimes_for_frp.frpc_binary()));
    tracing::info!("frp manager ready");

    // ── 11d. 实例迁移(/instances/{id}/export:导出归档 + /instances/import 还原) ──
    let transfer = Arc::new(transfer::TransferManager::new(&dir)?);
    tracing::info!("transfer manager ready");

    // ── 11e. 服务端核心更新(PaperMC 源,检查 + 更新任务) ──────────
    let server_core = Arc::new(server_core::ServerCoreManager::new());
    tracing::info!("server core manager ready");

    // ── 12. 开始监听 ─────────────────────────────────────────────
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
        server::router(
            store,
            instances,
            tasks,
            download,
            catalog,
            runtimes,
            monitor,
            procs,
            fs,
            mod_meta,
            mod_market,
            frp.clone(),
            transfer,
            server_core,
        )
        .into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    tracing::info!("daemon stopped");
    // 优雅停机:终止仍运行的 frpc
    frp.shutdown().await;
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