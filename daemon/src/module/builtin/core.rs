//! 核心模块：框架自省与基础运维。
//!
//! 这个模块不碰任何业务，只回答「你是谁、能做什么、现在怎么样」。
//! 标记为 `always_on`，配置里禁用不掉——否则客户端连不上来会完全瞎掉。

use async_trait::async_trait;
use serde_json::json;
use sysinfo::{CpuRefreshKind, System};

use crate::error::Result;
use crate::module::{Module, ModuleDescriptor, Registration, Scope, ok};
use crate::util::humanize_secs;
use crate::{PRODUCT, PROTOCOL_VERSION, VERSION};

pub struct CoreModule;

impl CoreModule {
    pub fn new() -> Self {
        Self
    }
}

impl Default for CoreModule {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Module for CoreModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("core", "核心", VERSION)
            .description("框架自省：连通性、服务信息、模块/方法/主题清单、连接列表。")
            .always_on()
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        // 框架自己会推的事件，在这里声明，客户端订阅时就能看到。
        reg.topic(crate::event::topics::STARTED, "守护进程已就绪，开始监听");
        reg.topic(
            crate::event::topics::SHUTTING_DOWN,
            "收到退出信号，开始优雅关闭",
        );
        reg.topic(crate::event::topics::CONN_OPENED, "有新连接接入");
        reg.topic(crate::event::topics::CONN_CLOSED, "有连接断开");

        reg.method(
            "core.ping",
            "连通性探测，原样回一个时间戳",
            |ctx| async move {
                ok(json!({
                    "pong": true,
                    "ts": crate::util::now_ms(),
                    "conn_id": ctx.conn_id,
                }))
            },
        );

        reg.method(
            "core.echo",
            "把参数原样回显，用于联调协议",
            |ctx| async move {
                ok(json!({
                    "method": ctx.method,
                    "params": ctx.params,
                    "peer": ctx.peer,
                }))
            },
        );

        reg.method("core.info", "服务与运行环境信息", |ctx| async move {
            let app = &ctx.app;
            let server = &app.config.server;
            ok(json!({
                "product": PRODUCT,
                "version": VERSION,
                "protocol_version": PROTOCOL_VERSION,
                "pid": std::process::id(),
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
                "bind": app.bind_display(),
                "ws_path": server.ws_path,
                "auth_required": server.auth_required(),
                "config_path": app.config_path_string(),
                "started_at_ms": app.started_at_ms,
                "uptime_ms": app.uptime_ms(),
                "uptime_human": humanize_secs(app.uptime_secs()),
                "connections": app.conns.count().await,
                "subscribers": app.bus.subscriber_count(),
                "shutting_down": app.is_shutting_down(),
            }))
        });

        // 「关于」页的**后端设备**框：机器视角（主机名 / 系统 / CPU / 内存）。
        // 与 `core.info` 的分工：info 是服务视角（连接数、订阅数、监听地址），
        // host 是「这台机器是什么」。两边的字段都只读，调用成本是几个系统调用。
        reg.method(
            "core.host",
            "守护进程所在机器的软硬件信息",
            |_| async move { ok(host_info()) },
        );

        reg.method("core.modules", "已装载模块清单", |ctx| async move {
            ok(ctx.app.registry.summary())
        });

        reg.method("core.methods", "所有可调用的 WS 方法", |ctx| async move {
            ok(json!({ "methods": ctx.app.registry.method_infos() }))
        });

        reg.method("core.topics", "所有可订阅的事件主题", |ctx| async move {
            ok(json!({ "topics": ctx.app.registry.topics() }))
        });

        reg.method("core.connections", "当前连接列表", |ctx| async move {
            let conns = ctx.app.conns.snapshots().await;
            ok(json!({ "count": conns.len(), "connections": conns }))
        });

        // 配置里有监听地址、令牌形状这类信息，限定本机可看。
        reg.method_with_scope(
            "core.config",
            "最终生效的配置（令牌已遮蔽）",
            Scope::Local,
            |ctx| async move { ok(ctx.app.redacted_config()) },
        );

        // 让 App 能主动让守护进程下线，省得还要 SSH 上去按 Ctrl-C。
        reg.method_with_scope(
            "core.shutdown",
            "请求守护进程优雅退出",
            Scope::Local,
            |ctx| async move {
                tracing::info!(peer = %ctx.peer, "收到远程关闭请求");
                ctx.app.cancel.cancel();
                ok(json!({ "shutting_down": true }))
            },
        );

        Ok(())
    }
}

/// 采集守护进程所在机器的静态信息。
///
/// 和 `core.info` 的分工：那边是服务视角（连接数、订阅数、监听地址），
/// 这里是「这台机器是什么」。成本是几个系统调用，所以不做缓存。
///
/// 读不到的字段是 `null`（主机名/系统版本在个别平台可能拿不到），
/// 数字字段为 0 表示平台不支持，前端统一按「未知」处理。
fn host_info() -> serde_json::Value {
    let mut sys = System::new();
    // `System::new()` 只建空表；CPU 型号与核心数要显式刷一次列表。
    sys.refresh_cpu_list(CpuRefreshKind::nothing());
    sys.refresh_memory();

    let cpu_brand = sys
        .cpus()
        .first()
        .map(|cpu| cpu.brand().trim())
        .filter(|brand| !brand.is_empty());

    json!({
        "hostname": System::host_name(),
        "os_name": System::name(),
        "os_version": System::os_version(),
        "kernel_version": System::kernel_version(),
        "arch": System::cpu_arch(),
        "cpu_brand": cpu_brand,
        "cpu_cores": std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0),
        "cpu_physical_cores": System::physical_core_count(),
        "memory_total_mb": sys.total_memory() / 1024 / 1024,
        "uptime_secs": System::uptime(),
    })
}
