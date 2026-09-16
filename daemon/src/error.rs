//! 统一错误类型。
//!
//! 分两层：
//!
//! * [`Error`] —— 进程内的普通错误（配置、IO、模块初始化……），只进日志、不上线。
//! * [`RpcError`] —— **要发给客户端**的错误。`code` 是稳定的字符串枚举，
//!   前端可以直接 `switch`；`message` 给人看；`data` 留扩展位。

use serde::{Deserialize, Serialize};

/// 客户端可见的错误。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RpcError {
    /// 稳定错误码，如 `method_not_found`。前端按这个分支，不要匹配 message。
    pub code: String,
    /// 人类可读描述。可能带细节（哪个参数不对），不保证稳定。
    pub message: String,
    /// 附加上下文，可选。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

impl std::fmt::Display for RpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for RpcError {}

impl RpcError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            data: None,
        }
    }

    /// 请求格式/字段不合法。
    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new("bad_request", message)
    }

    /// 方法存在，但参数不合法。
    pub fn invalid_params(message: impl Into<String>) -> Self {
        Self::new("invalid_params", message)
    }

    /// 没有这个方法。
    pub fn method_not_found(message: impl Into<String>) -> Self {
        Self::new("method_not_found", message)
    }

    /// 未通过鉴权。
    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self::new("unauthorized", message)
    }

    /// 已鉴权但无权执行。
    pub fn forbidden(message: impl Into<String>) -> Self {
        Self::new("forbidden", message)
    }

    /// 服务端内部错误（细节留在日志里，别往线上抛）。
    pub fn internal(message: impl Into<String>) -> Self {
        Self::new("internal", message)
    }

    /// 处理超时。
    pub fn timeout(message: impl Into<String>) -> Self {
        Self::new("timeout", message)
    }

    /// 并发/资源已满。
    pub fn busy(message: impl Into<String>) -> Self {
        Self::new("busy", message)
    }

    /// 功能暂时不可用（如服务正在关闭）。
    pub fn unavailable(message: impl Into<String>) -> Self {
        Self::new("unavailable", message)
    }

    pub fn with_data(mut self, data: serde_json::Value) -> Self {
        self.data = Some(data);
        self
    }
}

/// 进程内错误。
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("配置错误: {0}")]
    Config(String),

    #[error("配置文件不存在: {0}")]
    ConfigNotFound(String),

    #[error("{0}")]
    Io(#[from] std::io::Error),

    #[error("解析 TOML 失败: {0}")]
    TomlDecode(#[from] toml::de::Error),

    #[error("生成 TOML 失败: {0}")]
    TomlEncode(#[from] toml::ser::Error),

    #[error("JSON 错误: {0}")]
    Json(#[from] serde_json::Error),

    #[error("模块 `{module}` 出错: {message}")]
    Module { module: String, message: String },

    #[error("RPC 错误: {0}")]
    Rpc(#[from] RpcError),

    #[error("{0}")]
    Other(String),
}

impl Error {
    pub fn config(msg: impl Into<String>) -> Self {
        Self::Config(msg.into())
    }

    pub fn module(module: impl Into<String>, msg: impl Into<String>) -> Self {
        Self::Module {
            module: module.into(),
            message: msg.into(),
        }
    }

    pub fn other(msg: impl Into<String>) -> Self {
        Self::Other(msg.into())
    }
}

impl From<Error> for RpcError {
    /// 进程内错误可以安全地转成 RPC 错误；但不该发生的情况（`internal` 之外）
    /// 都在这里退化成通用码，避免把内部路径泄给客户端。
    fn from(err: Error) -> Self {
        match err {
            Error::Rpc(e) => e,
            Error::Config(m) => RpcError::bad_request(m),
            other => RpcError::internal(other.to_string()),
        }
    }
}

impl From<serde_json::Error> for RpcError {
    /// 方法处理器里序列化/反序列化失败一律算服务端问题（调用方传错参数
    /// 应该在更早的地方被拦成 `invalid_params`）。
    fn from(err: serde_json::Error) -> Self {
        RpcError::internal(format!("JSON 处理失败: {err}"))
    }
}

pub type Result<T, E = Error> = std::result::Result<T, E>;

/// 供 WS 方法处理器使用的结果别名。
pub type RpcResult<T> = std::result::Result<T, RpcError>;
