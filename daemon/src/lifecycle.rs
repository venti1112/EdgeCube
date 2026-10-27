//! 进程生命周期辅助：就绪文件与父进程看门狗。
//!
//! 被 App 以子进程方式拉起时（Android 本地服务、桌面本地服务），
//! 前端不知道 `--port 0` 最终落在哪个端口，也无法从子进程退出码里
//! 分辨「还没起来」和「起来了又挂了」。就绪文件把「绑定成功」这一
//! 时刻显式落盘，父进程看门狗则负责「App 没了，daemon 也别赖着」。

use std::net::SocketAddr;
use std::path::Path;
use std::time::Duration;

use serde::Serialize;
use tokio_util::sync::CancellationToken;

use crate::VERSION;
use crate::error::{Error, Result};
use crate::state::AppState;

/// 就绪文件内容。
///
/// 字段只增不改：前端按需读，老版本忽略多余字段。
#[derive(Debug, Clone, Serialize)]
pub struct ReadyInfo {
    pub pid: u32,
    pub version: &'static str,
    /// 实际监听地址，形如 `127.0.0.1:54321`。
    pub addr: String,
    pub host: String,
    pub port: u16,
    pub ws_path: String,
    pub auth_required: bool,
    pub started_at_ms: u64,
}

impl ReadyInfo {
    fn new(app: &AppState, addr: SocketAddr) -> Self {
        Self {
            pid: std::process::id(),
            version: VERSION,
            addr: addr.to_string(),
            host: addr.ip().to_string(),
            port: addr.port(),
            ws_path: app.config.server.ws_path.clone(),
            auth_required: app.config.server.auth_required(),
            started_at_ms: app.started_at_ms,
        }
    }
}

/// 把就绪信息原子写入 `path`。
///
/// 先写同目录临时文件、`fsync` 后 `rename`：前端轮询时要么看不到文件，
/// 要么看到完整内容，不会读到写了一半的 JSON。
pub fn write_ready_file(path: &Path, app: &AppState, addr: SocketAddr) -> Result<()> {
    let info = ReadyInfo::new(app, addr);
    let body = serde_json::to_vec_pretty(&info)?;

    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)?;
    }

    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("ready.json");
    let tmp = path.with_file_name(format!(".{file_name}.{}.tmp", info.pid));

    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&tmp)?;
    use std::io::Write;
    file.write_all(&body)?;
    file.sync_all()?;
    drop(file);

    if let Err(first) = std::fs::rename(&tmp, path) {
        // Windows 上 rename 不覆盖已存在的目标；只有这种情况下才先删再试。
        if path.exists() {
            std::fs::remove_file(path)?;
            std::fs::rename(&tmp, path).map_err(|_| first)?;
        } else {
            let _ = std::fs::remove_file(&tmp);
            return Err(first.into());
        }
    }
    Ok(())
}

/// 退出时清掉就绪文件，但只清「确实是自己写的」那一份。
///
/// 若新实例已经覆盖了同一个路径，这里不能把新实例的文件删掉。
pub fn remove_ready_file(path: &Path) {
    let ours = std::fs::read(path)
        .ok()
        .and_then(|body| serde_json::from_slice::<serde_json::Value>(&body).ok())
        .and_then(|value| value.get("pid").and_then(|v| v.as_u64()))
        .is_some_and(|pid| pid == u64::from(std::process::id()));
    if ours && let Err(e) = std::fs::remove_file(path) {
        tracing::warn!(path = %path.display(), error = %e, "清理就绪文件失败");
    }
}

/// 进程是否还活着。`EPERM` 说明进程存在但没权限发信号，同样算活着。
#[cfg(unix)]
pub fn process_alive(pid: u32) -> bool {
    let Ok(pid) = libc::pid_t::try_from(pid) else {
        return false;
    };
    if pid <= 0 {
        return false;
    }
    // SAFETY: `kill(pid, 0)` 只做存在性与权限检查，不递送任何信号。
    if unsafe { libc::kill(pid, 0) } == 0 {
        return true;
    }
    std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
}

#[cfg(not(unix))]
pub fn process_alive(pid: u32) -> bool {
    // 没有免费且可靠的跨平台存在性检查；Windows 本地服务后续单独实现。
    let _ = pid;
    true
}

/// 起一个后台任务，父进程没了就取消 daemon。
pub fn spawn_parent_watchdog(parent: u32, cancel: CancellationToken) {
    if !cfg!(unix) {
        tracing::warn!("当前平台不支持 --exit-with-parent，已忽略");
        return;
    }
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(Duration::from_secs(1));
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            tokio::select! {
                _ = cancel.cancelled() => return,
                _ = ticker.tick() => {}
            }
            if !process_alive(parent) {
                tracing::warn!(parent, "父进程已退出，随之关闭");
                cancel.cancel();
                return;
            }
        }
    });
}

/// 命令行里 `--exit-with-parent` 的取值校验。
pub fn parse_parent_pid(raw: &str) -> Result<u32> {
    let pid: u32 = raw
        .trim()
        .parse()
        .map_err(|_| Error::other(format!("--exit-with-parent 不是合法进程号: `{raw}`")))?;
    if pid == 0 {
        return Err(Error::other("--exit-with-parent 不接受 0"));
    }
    Ok(pid)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::registry::ModuleRegistry;
    use std::path::PathBuf;
    use std::sync::Arc;

    fn state() -> AppState {
        let config = Config::default();
        let registry = Arc::new(ModuleRegistry::build(vec![], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    fn temp_path(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-ready-test-{tag}-{}-{}",
            std::process::id(),
            crate::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("ready.json")
    }

    #[test]
    fn ready_file_is_complete_json() {
        let path = temp_path("write");
        let app = state();
        let addr: SocketAddr = "127.0.0.1:54321".parse().unwrap();
        write_ready_file(&path, &app, addr).unwrap();

        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(value["pid"], std::process::id());
        assert_eq!(value["addr"], "127.0.0.1:54321");
        assert_eq!(value["host"], "127.0.0.1");
        assert_eq!(value["port"], 54321);
        assert_eq!(value["ws_path"], app.config.server.ws_path.as_str());
        assert_eq!(value["auth_required"], false);
        assert_eq!(value["version"], VERSION);

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }

        remove_ready_file(&path);
        assert!(!path.exists());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn stale_ready_file_is_replaced() {
        let path = temp_path("replace");
        std::fs::write(&path, b"{\"pid\":1}").unwrap();
        write_ready_file(&path, &state(), "127.0.0.1:1".parse().unwrap()).unwrap();
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(value["pid"], std::process::id());
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn removal_skips_a_file_written_by_someone_else() {
        let path = temp_path("foreign");
        std::fs::write(&path, b"{\"pid\":1}").unwrap();
        remove_ready_file(&path);
        assert!(path.exists(), "别的实例的文件不能被我们删掉");
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }

    #[test]
    fn current_process_is_alive_and_bogus_is_not() {
        assert!(process_alive(std::process::id()));
        #[cfg(unix)]
        assert!(!process_alive(4_000_000_000));
    }

    #[test]
    fn parent_pid_parsing() {
        assert_eq!(parse_parent_pid(" 123 ").unwrap(), 123);
        assert!(parse_parent_pid("abc").is_err());
        assert!(parse_parent_pid("0").is_err());
        assert!(parse_parent_pid("-1").is_err());
    }
}
