//! EdgeCube Daemon 入口。
//!
//! 这里只做「编排」：解析参数 → 读配置 → 装日志 → 建注册表 → 装信号 → 起服务。
//! 任何一块具体逻辑都在库里对应模块，方便测试与复用。

use std::process::ExitCode;
use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use edgecube_daemon::cli::{Action, Cli, HELP, ParseOutcome};
use edgecube_daemon::config::{Config, default_config_path};
use edgecube_daemon::error::{Error, Result};
use edgecube_daemon::logging;
use edgecube_daemon::module::registry::{ModuleRegistry, builtin_modules};
use edgecube_daemon::state::AppState;
use edgecube_daemon::{PRODUCT, VERSION, server};

fn main() -> ExitCode {
    let cli = match Cli::parse(std::env::args()) {
        Ok(ParseOutcome::Run(cli)) => cli,
        Ok(ParseOutcome::Help) => {
            println!("{HELP}");
            return ExitCode::SUCCESS;
        }
        Ok(ParseOutcome::Version) => {
            println!("{PRODUCT} {VERSION}");
            return ExitCode::SUCCESS;
        }
        Err(e) => {
            eprintln!("参数错误: {e}\n\n{HELP}");
            return ExitCode::FAILURE;
        }
    };

    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("无法创建 runtime: {e}");
            return ExitCode::FAILURE;
        }
    };

    match runtime.block_on(run(cli)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            // 此时日志可能还没装上，所以 stdout 与 stderr 各留一份。
            tracing::error!(error = %e, "启动失败");
            eprintln!("启动失败: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run(cli: Cli) -> Result<()> {
    // `--init-config` 必须在读配置之前处理：它的用途正是「创建一份还不存在的配置」，
    // 走正常的加载路径会先因为文件不存在而失败。
    if cli.action == Action::InitConfig {
        return init_config(&cli);
    }

    // ---- 配置 ----
    // 日志的格式与上色决定 subscriber 的类型、没法热切换，所以顺序是
    // 「先读配置 → 再装日志」，一次到位。
    let loaded = Config::load(&cli)?;
    let config = loaded.config;
    logging::init(&config.log)?;

    if let Some(notice) = &loaded.notice {
        tracing::warn!("{notice}");
    }
    tracing::info!(
        version = VERSION,
        config = loaded
            .path
            .as_ref()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "<默认值>".into()),
        "配置已加载"
    );

    // ---- 一次性动作 ----
    match cli.action {
        Action::PrintConfig => {
            print!("{}", toml::to_string_pretty(&config)?);
            return Ok(());
        }
        Action::Check => return check(&config),
        Action::Run => {}
        Action::InitConfig => unreachable!("已在函数入口处理"),
    }

    // ---- 模块注册表 ----
    let modules = builtin_modules();
    let registry = Arc::new(ModuleRegistry::build(modules, &config)?);
    let enabled: Vec<&str> = registry
        .enabled_descriptors()
        .iter()
        .map(|d| d.id.as_str())
        .collect();
    tracing::info!(
        modules = %enabled.join(", "),
        methods = registry.method_count(),
        topics = registry.topics().len(),
        "模块注册完成"
    );

    // ---- 运行时状态与退出信号 ----
    let cancel = CancellationToken::new();
    let app = AppState::new(config, loaded.path.clone(), registry, cancel.clone());
    install_signal_handlers(cancel.clone());

    // ---- 起服务 ----
    server::run(app).await
}

/// 生成默认配置文件。已存在则不覆盖——配置文件是用户的东西。
fn init_config(cli: &Cli) -> Result<()> {
    let path = cli.config.clone().unwrap_or_else(default_config_path);
    if path.exists() {
        return Err(Error::config(format!(
            "{} 已存在，为免覆盖你的配置，请先移走或改用 -c 指定别的路径",
            path.display()
        )));
    }
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&path, Config::template())?;
    println!("已生成配置文件: {}", path.display());
    Ok(())
}

/// `--check`：只校验，不监听端口、不起后台任务。
fn check(config: &Config) -> Result<()> {
    let registry = ModuleRegistry::build(builtin_modules(), config)?;
    println!("配置自检通过");
    println!(
        "  监听        {}:{}",
        config.server.host, config.server.port
    );
    println!("  WS 路径     {}", config.server.ws_path);
    println!(
        "  鉴权        {}",
        if config.server.auth_required() {
            "开启"
        } else {
            "关闭"
        }
    );
    println!(
        "  日志        {} ({:?})",
        config.log.level, config.log.format
    );
    for d in registry.enabled_descriptors() {
        println!("  模块        {} v{} — {}", d.id, d.version, d.description);
    }
    let disabled: Vec<&str> = registry
        .all_descriptors()
        .iter()
        .filter(|d| !registry.enabled_descriptors().iter().any(|e| e.id == d.id))
        .map(|d| d.id.as_str())
        .collect();
    if !disabled.is_empty() {
        println!("  已禁用      {}", disabled.join(", "));
    }
    println!("  WS 方法     {} 个", registry.method_count());
    println!("  事件主题    {} 个", registry.topics().len());
    Ok(())
}

/// Ctrl-C / SIGTERM → 取消令牌。信号只能装一次，重复装上会互相抢。
fn install_signal_handlers(cancel: CancellationToken) {
    tokio::spawn(async move {
        #[cfg(unix)]
        {
            use tokio::signal::unix::{SignalKind, signal};
            let mut term = match signal(SignalKind::terminate()) {
                Ok(s) => s,
                Err(e) => {
                    tracing::warn!(error = %e, "无法监听 SIGTERM，仅响应 Ctrl-C");
                    let _ = tokio::signal::ctrl_c().await;
                    cancel.cancel();
                    return;
                }
            };
            tokio::select! {
                _ = tokio::signal::ctrl_c() => tracing::info!("收到 SIGINT"),
                _ = term.recv() => tracing::info!("收到 SIGTERM"),
            }
        }
        #[cfg(not(unix))]
        {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("收到 Ctrl-C");
        }
        cancel.cancel();
    });
}
