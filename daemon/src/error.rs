//! daemon 统一错误类型。

use std::fmt;

#[derive(Debug)]
pub enum DaemonError {
    Io(std::io::Error),
    Serde(serde_json::Error),
    Argon2(argon2::password_hash::Error),
    Env(std::env::VarError),
    Addr(std::net::AddrParseError),
    Msg(String),
}

impl fmt::Display for DaemonError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DaemonError::Io(e) => write!(f, "io error: {e}"),
            DaemonError::Serde(e) => write!(f, "json error: {e}"),
            DaemonError::Argon2(e) => write!(f, "password hash error: {e}"),
            DaemonError::Env(e) => write!(f, "env var error: {e}"),
            DaemonError::Addr(e) => write!(f, "address parse error: {e}"),
            DaemonError::Msg(m) => f.write_str(m),
        }
    }
}

impl std::error::Error for DaemonError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            DaemonError::Io(e) => Some(e),
            DaemonError::Serde(e) => Some(e),
            // argon2::password_hash::Error 未实现 std::error::Error,这里返回 None
            DaemonError::Argon2(_) | DaemonError::Env(_) | DaemonError::Addr(_) => None,
            DaemonError::Msg(_) => None,
        }
    }
}

pub type Result<T> = std::result::Result<T, DaemonError>;

impl From<std::io::Error> for DaemonError {
    fn from(e: std::io::Error) -> Self {
        DaemonError::Io(e)
    }
}

impl From<serde_json::Error> for DaemonError {
    fn from(e: serde_json::Error) -> Self {
        DaemonError::Serde(e)
    }
}

impl From<argon2::password_hash::Error> for DaemonError {
    fn from(e: argon2::password_hash::Error) -> Self {
        DaemonError::Argon2(e)
    }
}

impl From<std::env::VarError> for DaemonError {
    fn from(e: std::env::VarError) -> Self {
        DaemonError::Env(e)
    }
}

impl From<std::net::AddrParseError> for DaemonError {
    fn from(e: std::net::AddrParseError) -> Self {
        DaemonError::Addr(e)
    }
}

impl From<String> for DaemonError {
    fn from(m: String) -> Self {
        DaemonError::Msg(m)
    }
}