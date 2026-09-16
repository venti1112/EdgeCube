//! 服务端下载(内部能力,不对外暴露下载接口)。
//!
//! 用途:创建实例时客户端提供 `downloadUrl`(+可选 `checksum`),daemon 自动发起
//! 下载到实例工作目录,下载完成(任务终结)后实例方可启动;进度经任务队列
//! `GET /tasks/{taskId}` / WS `task/progress` 查询。
//!
//! 实现:基于 aria2-core(RequestGroupMan + DownloadEngine 事件循环):
//! - 引擎为进程级单例,启动即常驻(keep_alive),接收任意数量的下载任务;
//! - 每个 downloadUrl 提交一个 request group(gid),一次性下载完成(不续传);
//! - 下载完成后按需对目标文件做 sha256 强校验(契约 checksum),不一致视为失败;
//! - 取消:任务取消标志置位后 force_remove_group 中止在途请求。

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use aria2_core::engine::download_engine::DownloadEngine;
use aria2_core::engine::engine_command::{EngineCommand, EngineCommandSender};
use aria2_core::request::request_group::{
    DownloadOptions, DownloadStatus, DownloadStatusSnapshot, GroupId, RequestGroup,
};
use aria2_core::request::request_group_man::RequestGroupMan;
use tokio::time::{Duration, sleep};

use crate::task::model::{TaskFailure, TaskProgress};
use crate::task::service::TaskHandle;

/// 引擎事件循环 tick / 进度轮询间隔。
const TICK_INTERVAL_MS: u64 = 250;
const POLL_INTERVAL: Duration = Duration::from_millis(300);
/// 分片数(aria2 并发连接)。
const DEFAULT_SPLIT: u16 = 4;
/// 引擎停机后轮询仍拿不到状态的兜底次数(约 6s),避免死循环。
const MAX_IDLE_POLLS: u32 = 20;

/// 下载引擎单例:共享 handle(克隆 = 同一引擎)。
#[derive(Clone)]
pub struct DownloadManager {
    man: Arc<RequestGroupMan>,
    /// 引擎命令通道:提交/取消下载必须经此唤醒引擎事件循环
    /// (直接改 man 队列不会触发 promote,易造成下载永久卡在 reserved)。
    cmd_tx: EngineCommandSender,
    /// 引擎事件循环任务(常驻;daemon 退出时随 runtime 终结)。
    _engine: Arc<tokio::task::JoinHandle<()>>,
}

impl Default for DownloadManager {
    fn default() -> Self {
        Self::new()
    }
}

impl DownloadManager {
    /// 启动常驻下载引擎(RequestGroupMan + DownloadEngine 事件循环)。
    pub fn new() -> Self {
        let man = Arc::new(RequestGroupMan::new());
        let mut engine = DownloadEngine::new(TICK_INTERVAL_MS);
        engine.set_request_group_man(Arc::clone(&man));
        // 空闲时保持事件循环,等待后续下载任务
        engine.set_keep_alive(true);

        // 命令通道须在 engine.run() 之前取出(一旦 move 进 task 便无法再访问 engine)
        let cmd_tx = engine.engine_command_sender();

        let _engine = tokio::spawn(async move {
            if let Err(e) = engine.run().await {
                tracing::error!(error = %e, "download engine stopped");
            }
        });
        tracing::info!("download engine ready");
        DownloadManager {
            man,
            cmd_tx,
            _engine: Arc::new(_engine),
        }
    }

    /// 提交一个下载 group:分片多线程下载到 `dir`。
    /// [out] 指定落盘文件名(缺省取 URL 末段,契约 fileName)。
    /// [overwrite] 目标文件已存在时是否直接覆盖(默认 false → aria2 自动 `.1` 重命名)。
    /// 经引擎命令通道入队(AddDownload),引擎事件循环随即 promote 并开始下载。
    /// 返回 gid(Copy 值,供轮询/取消定位)。
    pub fn add(
        &self,
        url: &str,
        dir: &Path,
        out: Option<&str>,
        overwrite: bool,
    ) -> Result<GroupId, String> {
        let gid = self.man.next_available_gid();
        let file_name = out.unwrap_or_else(|| filename_from_url(url));
        let opts = DownloadOptions {
            split: Some(DEFAULT_SPLIT),
            max_connection_per_server: Some(DEFAULT_SPLIT),
            dir: Some(dir.to_string_lossy().into_owned()),
            out: Some(file_name.to_string()),
            allow_overwrite: overwrite,
            ..Default::default()
        };
        let group = Arc::new(RwLock::new(RequestGroup::new(
            gid,
            vec![url.to_string()],
            opts,
        )));
        self.cmd_tx
            .send(EngineCommand::AddDownload { group })
            .map_err(|e| e.to_string())?;
        Ok(gid)
    }

    /// 当下进度快照(group 已终结返回 None)。
    pub fn snapshot(&self, gid: GroupId) -> Option<DownloadStatusSnapshot> {
        let group = self.man.get_group(gid)?;
        Some(group.read().unwrap().status_snapshot())
    }

    /// 终结后的下载结果(group 未终结或不存在返回 None;
    /// runtime 安装等外部 runner 用它区分「未就绪」与「已终结」)。
    pub fn stopped_result(
        &self,
        gid: GroupId,
    ) -> Option<aria2_core::request::request_group::DownloadResult> {
        self.man.find_stopped_result(&gid.to_hex_string())
    }

    /// 取消下载:经引擎命令通道强制移除 gid(引擎摘除在途请求并 demote 终结)。
    pub fn cancel(&self, gid: GroupId) {
        if let Err(e) = self
            .cmd_tx
            .send(EngineCommand::ForceRemoveDownload { gid })
        {
            tracing::warn!(gid = gid.to_hex_string(), error = %e, "send force-remove download command failed");
        }
    }
}

/// 下载任务执行体(task 队列 runner):驱动 gid 至终结,期间上报进度,可选校验 checksum。
/// [file_name] 指定落盘文件名(缺省取 URL 末段);[checksum] 格式 "sha256:<hex>" / "sha1:<hex>"。
/// [overwrite] 目标文件已存在时直接覆盖(download_single_file 用 true;实例创建用 false)。
pub async fn run_download_task(
    handle: TaskHandle,
    dm: DownloadManager,
    url: String,
    dir: PathBuf,
    file_name: Option<String>,
    checksum: Option<String>,
    // 更新替换:下载成功后把该旧文件重命名为 `<path>.disabled`(而非删除)。
    // 传相对实例 cwd 的绝对路径;文件不存在时静默跳过(幂等)。
    replace: Option<PathBuf>,
    overwrite: bool,
) -> Result<(), TaskFailure> {
    handle.set_phase("starting").await;
    fs::create_dir_all(&dir)
        .map_err(|e| TaskFailure::new("download_start_failed", format!("cannot create dir: {e}")))?;

    let gid = dm
        .add(&url, &dir, file_name.as_deref(), overwrite)
        .map_err(|e| TaskFailure::new("download_start_failed", format!("add download: {e}")))?;
    tracing::info!(gid = gid.to_hex_string(), url, dir = %dir.display(), "download started");

    handle.set_phase("downloading").await;
    let mut idle_polls: u32 = 0;
    loop {
        if handle.is_cancelled() {
            dm.cancel(gid);
            return Err(TaskFailure::new("cancelled", "cancelled"));
        }

        match dm.snapshot(gid) {
            Some(snapshot) => {
                idle_polls = 0;
                update_progress(&handle, &snapshot).await;
                match snapshot.status {
                    DownloadStatus::Complete => break,
                    DownloadStatus::Error(_) => {
                        return Err(stopped_failure(&dm, gid, "download failed"));
                    }
                    DownloadStatus::Removed => {
                        return Err(TaskFailure::new(
                            "download_failed",
                            "download removed unexpectedly",
                        ));
                    }
                    // Active / Waiting / Paused:继续轮询
                    _ => {
                        sleep(POLL_INTERVAL).await;
                    }
                }
            }
            None => {
                // group 已完成 demotion(active → stopped):查终结结果确认成败
                if let Some(result) = dm.stopped_result(gid) {
                    if result.status.is_completed() {
                        break;
                    }
                    return Err(TaskFailure::new("download_failed", result.message));
                }
                idle_polls += 1;
                if idle_polls > MAX_IDLE_POLLS {
                    return Err(TaskFailure::new(
                        "download_failed",
                        "download engine stopped while waiting",
                    ));
                }
                sleep(POLL_INTERVAL).await;
            }
        }
    }

    // ── 下载完成:可选强校验 ─────────────────────────────────────
    let file = dir.join(file_name.unwrap_or_else(|| filename_from_url(&url).to_string()));
    if let Some(checksum) = checksum {
        handle.set_phase("verifying").await;
        // "sha256:<hex>" / "sha1:<hex>",缺省按 sha256
        let (algo, expected) = match checksum.split_once(':') {
            Some(("sha256", hex)) => (HashAlgo::Sha256, hex),
            Some(("sha1", hex)) => (HashAlgo::Sha1, hex),
            _ => (
                HashAlgo::Sha256,
                checksum.strip_prefix("sha256:").unwrap_or(&checksum),
            ),
        };
        let expected = expected.to_lowercase();
        let file_for_hash = file.clone();
        let file_for_err = file.clone();
        let actual = tokio::task::spawn_blocking(move || hash_hex(&file_for_hash, algo))
            .await
            .map_err(|e| TaskFailure::new("checksum_failed", format!("hash task panic: {e}")))?
            .map_err(|e| {
                TaskFailure::new("checksum_failed", format!("cannot read {file_for_err:?}: {e}"))
            })?;
        if actual != expected {
            tracing::warn!(
                gid = gid.to_hex_string(),
                file = %file.display(),
                "checksum mismatch"
            );
            return Err(TaskFailure::new(
                "checksum_mismatch",
                format!("checksum mismatch: expected {expected}, actual {actual}"),
            ));
        }
        tracing::info!(
            gid = gid.to_hex_string(),
            file = %file.display(),
            "checksum verified"
        );
    }

    // ── 下载成功:更新替换——旧文件重命名 .disabled(而非删除) ──
    if let Some(old) = replace {
        handle.set_phase("replacing").await;
        if old.exists() {
            let disabled = PathBuf::from(format!("{}.disabled", old.to_string_lossy()));
            fs::rename(&old, &disabled).map_err(|e| {
                TaskFailure::new(
                    "replace_failed",
                    format!(
                        "cannot rename {} to {}: {e}",
                        old.display(),
                        disabled.display()
                    ),
                )
            })?;
            tracing::info!(
                old = %old.display(),
                new = %disabled.display(),
                "old file replaced (.disabled)"
            );
        }
    }

    tracing::info!(
        gid = gid.to_hex_string(),
        file = %file.display(),
        "download completed"
    );
    Ok(())
}

/// 将引擎快照映射为契约 TaskProgress(percent 为 0..1 比率)。
async fn update_progress(handle: &TaskHandle, snapshot: &DownloadStatusSnapshot) {
    let total = snapshot.total_length;
    let received = if total > 0 {
        snapshot.completed_length.min(total)
    } else {
        snapshot.completed_length
    };
    let speed = (snapshot.download_speed > 0).then_some(snapshot.download_speed);
    // 预计剩余时间 = (总大小 - 已下载) / 速度;信息不全时缺省。
    let eta_seconds = match (total, received, speed) {
        (t, r, Some(s)) if t > r && s > 0 => Some((t - r) / s),
        _ => None,
    };
    let progress = TaskProgress {
        received_bytes: Some(received),
        total_bytes: (total > 0).then_some(total),
        speed_bytes_per_sec: speed,
        eta_seconds,
        percent: if total > 0 {
            Some((received as f32 / total as f32).min(1.0))
        } else {
            None
        },
    };
    handle.set_progress(progress).await;
}

/// 从终结结果取错误信息(带可选 gid 上下文)。
fn stopped_failure(dm: &DownloadManager, gid: GroupId, prefix: &str) -> TaskFailure {
    let detail = dm
        .stopped_result(gid)
        .map(|r| r.message)
        .unwrap_or_else(|| "no result".into());
    TaskFailure::new("download_failed", format!("{prefix}: {detail}"))
}

/// 由 URL 末段推导目标文件名(下载到实例工作目录)。
///
/// 规则:去掉 query/fragment 与 scheme 前缀后,取路径最后一个 '/' 之后的段;
/// URL 以 '/' 结尾(路径末段为空)或无路径(纯 host)时返回默认名 "download"。
fn filename_from_url(url: &str) -> &str {
    let clean = url.split(['?', '#']).next().unwrap_or(url);
    if clean.ends_with('/') {
        return "download";
    }
    let without_scheme = clean.split_once("://").map(|(_, rest)| rest).unwrap_or(clean);
    match without_scheme.rsplit_once('/') {
        Some((_, last)) if !last.is_empty() => last,
        _ => "download",
    }
}

/// 文件哈希算法(校验值前缀决定)。
#[derive(Debug, Clone, Copy)]
enum HashAlgo {
    Sha1,
    Sha256,
}

/// 文件哈希,hex 小写(契约 "sha256:<hex>" / "sha1:<hex>")。
fn hash_hex(path: &Path, algo: HashAlgo) -> std::io::Result<String> {
    use sha1::Sha1;
    use sha2::{Digest, Sha256};

    let bytes = std::fs::read(path)?;
    let hex = match algo {
        HashAlgo::Sha1 => {
            let mut hasher = Sha1::new();
            hasher.update(&bytes);
            format!("{:x}", hasher.finalize())
        }
        HashAlgo::Sha256 => {
            let mut hasher = Sha256::new();
            hasher.update(&bytes);
            format!("{:x}", hasher.finalize())
        }
    };
    Ok(hex)
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn filename_from_url_extracts_last_segment() {
        assert_eq!(filename_from_url("http://example.com/a/b/file.zip"), "file.zip");
        assert_eq!(filename_from_url("https://example.com/server.jar"), "server.jar");
        assert_eq!(filename_from_url("https://example.com/a/b/"), "download");
        assert_eq!(filename_from_url("https://example.com"), "download");
    }

    #[test]
    fn sha256_hex_matches_known_digest() {
        let dir = std::env::temp_dir().join(format!("edgecube-test-{}", Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("a.bin");
        fs::write(&path, b"hello").unwrap();
        // sha256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        assert_eq!(
            hash_hex(&path, HashAlgo::Sha256).unwrap(),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        // sha1("hello") = aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d
        assert_eq!(
            hash_hex(&path, HashAlgo::Sha1).unwrap(),
            "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"
        );
        fs::remove_dir_all(dir).unwrap();
    }
}