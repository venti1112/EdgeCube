//! EdgeCube Daemon —— 后端框架库。
//!
//! 这里只放「框架」，不放具体业务：
//!
//! | 关注点 | 位置 |
//! | --- | --- |
//! | 配置加载与合并 | [`config`] |
//! | 可插拔功能模块 | [`module`] |
//! | HTTP / WebSocket 服务 | [`server`] |
//! | 连接内广播（服务端主动推送） | [`event`] |
//! | 连接表 | [`conn`] |
//! | 全局运行时状态 | [`state`] |
//!
//! 加一个新功能模块只需要两步：实现 [`module::Module`]，然后在
//! [`module::registry::builtin_modules`] 里加一行。详见 `daemon/README.md`。

pub mod cli;
pub mod config;
pub mod conn;
pub mod error;
pub mod event;
pub mod logging;
pub mod module;
pub mod server;
pub mod state;
pub mod util;

/// 产品名（用于握手、HTTP 信息页）。
pub const PRODUCT: &str = "edgecube-daemon";

/// 版本号，取自 `Cargo.toml`。
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// WebSocket 应用层协议版本。
///
/// 信封结构发生**不兼容**变更时 +1，客户端据此拒绝连接而不是解析出错。
pub const PROTOCOL_VERSION: u32 = 1;
