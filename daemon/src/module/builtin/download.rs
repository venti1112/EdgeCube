//! 下载队列模块：一个**全局**的 HTTP 下载队列（底层引擎是 `gosh-dl`）。
//!
//! # 为什么是「全局队列 + 独立模块」
//!
//! 队列只有一份 —— `gosh-dl` 的 `DownloadEngine` 本身就是进程级单例：
//! 并发上限、限速、事件流都是全局的。但它服务的每个任务都归属**某个实例**
//! （落盘路径以实例根目录为根）。所以这件事既不是某个实例的属性，也不该散进
//! `instance` 模块：单独一个 `download` 模块。
//!
//! # 数据根：本模块**没有**自己的 `dir`
//!
//! 实例在哪儿，下载就落在哪儿。数据根直接读 `[modules.config.instance] dir`
//! （复用 [`instance::resolve_data_dir`] 那一套回退链），不另配一个 ——
//! 两处各配一个根目录，迟早会配出「下载不知道实例在哪」的错位。
//!
//! 队列自己只用一个小目录 `<data_dir>/download`，作用是满足 gosh-dl
//! 「`EngineConfig::download_dir` 必须已存在」这条硬要求；每个任务都显式带
//! `save_dir`，那个目录实际不会被写进去。
//!
//! # 方法
//!
//! | 方法 | 参数 | 说明 |
//! | --- | --- | --- |
//! | `download.add` | `url`、`instance_id`、`path?`、`filename?`、`md5?`/`sha256?`/`sha1?` | 提交一个下载任务，返回任务对象 |
//! | `download.status` | `id` | 按任务 ID 查状态 |
//! | `download.list` | — | 全部任务（最新提交在前） |
//!
//! # 事件
//!
//! 推两条主题，对齐 monitor 那套「**首拉快照 + 订阅推送**」的用法：
//!
//! * `download.progress` —— 排队中 / 进行中的任务进度（固定间隔扫一遍引擎，见
//!   [`run_publish_loop`]），字段：`task_id`、`state`、`completed_size`、
//!   `total_size`、`download_speed`、`eta_seconds`、`progress_percent`、`connections`。
//! * `download.state` —— 状态**变了**的任务（含终态与校验失败），字段：
//!   `task_id`、`state`，`error` 只在失败时出现。
//!
//! 事件里只带 `task_id` 与进度；实例归属那类信息用 `download.status` 取快照。
//!
//! 刻意**不**直接转发 gosh-dl 的 `DownloadEvent`：那是每读一块就一条，一个
//! 60 MB 的 jar 能推上千条。定时扫引擎状态天然是节流过的，而且即使慢消费者丢过
//! 事件（broadcast 的 `Lagged`），下一拍也会自动收敛回真值 —— 不需要补历史。
//!
//! # sha1
//!
//! gosh-dl 的校验只支持 md5 / sha256，而**原版服务端的上游只给 sha1**
//! （Mojang 版本详情的 `downloads.server` 只有 `sha1` / `size` / `url`，已实测）。
//! 所以 sha1 由 daemon 在下载完成后自己算：匹配即 `completed`；不匹配**删掉文件**
//! 并把任务渲染成 `error`（`error.kind = "checksum_mismatch"`）。
//! 中间那一小段有我们自己的状态 `verifying`（只有带 sha1 的任务会经过它）。
//!
//! `md5` / `sha256` / `sha1` **三选一**：gosh-dl 的 `checksum` 只能放一个，
//! 而「我写了两个校验值结果只校了一个」是事后极难发现的问题，所以直接拒绝。
//!
//! # 落盘路径怎么定
//!
//! `path` 是**相对实例根目录**的目录（`""` = 实例根），`filename` 是文件名；
//! 没给 `filename` 就用 URL 里的最后一段。两者合起来才是落盘位置。
//!
//! 安全性上把 `..` / 绝对路径挡在门外靠的是 [`files::resolve`]（instance 模块
//! 那一份，**不另写一份**：安全边界有两份实现就迟早会有一份漏）。除此之外还有
//! 一层：`filename` 必须是**单段**，不许出现路径分隔符 —— 目录归 `path` 管，
//! 混着写等于给逃逸开了第二个入口。
//!
//! 与 `instance::files` 一样：**跟随符号链接的读写不在防护范围内**。能走到这里的
//! 调用方本来就持令牌、能改实例的启动命令、能开 PTY，实例目录里预先存在的
//! 符号链接不算提权面。
//!
//! # 模块自己的错误码（前端按码分支）
//!
//! `download_instance_not_found`、`download_task_not_found`、`download_url_invalid`、
//! `download_path_invalid`、`download_filename_invalid`、`download_filename_missing`、
//! `download_checksum_invalid`、`download_target_exists`、`download_save_failed`、
//! `download_engine_unavailable`、`download_failed`。
//!
//! 提交接口的错误码都是**提交时**就能判定的问题；真正的下载失败（连不上、404、
//! 校验不过）会体现为任务状态 `error`，原因在任务对象的 `error` 字段里 —— 那是
//! 异步的，不该假装成一次调用的失败。
//!
//! # 这一轮**故意没做**的事
//!
//! * **不持久化**：队列只在内存里，daemon 重启即清空（所以 `gosh-dl` 的
//!   `database_path` 留空、`storage` feature 也没开）。
//! * **没有暂停 / 取消 / 重试**：这三个接口本轮不做，`gosh-dl` 引擎本身是支持的
//!   （`pause` / `cancel` / `resume`），要加时加在这里。
//!
//! 上面两条都是取舍，不是遗漏；补的时候按这个顺序来。

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use async_trait::async_trait;
use gosh_dl::protocol::ExpectedChecksum;
use gosh_dl::{
    DownloadEngine, DownloadId, DownloadOptions, DownloadState, DownloadStatus, EngineConfig,
    EngineError, HttpConfig, StorageErrorKind,
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha1::{Digest, Sha1};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::error::{Error, Result, RpcError, RpcResult};
use crate::module::CallCtx;
use crate::module::builtin::instance::{
    files, resolve_data_dir, resolve_instance_root, store::validate_id as validate_instance_id,
};
use crate::module::{Module, ModuleDescriptor, ModuleEnv, Registration};
use crate::state::AppState;
use crate::util::now_ms;

// ---------------------------------------------------------------------------
// 错误码
// ---------------------------------------------------------------------------

const CODE_INSTANCE_NOT_FOUND: &str = "download_instance_not_found";
const CODE_TASK_NOT_FOUND: &str = "download_task_not_found";
const CODE_URL_INVALID: &str = "download_url_invalid";
const CODE_PATH_INVALID: &str = "download_path_invalid";
const CODE_FILENAME_INVALID: &str = "download_filename_invalid";
const CODE_FILENAME_MISSING: &str = "download_filename_missing";
const CODE_CHECKSUM_INVALID: &str = "download_checksum_invalid";
const CODE_TARGET_EXISTS: &str = "download_target_exists";
const CODE_SAVE_FAILED: &str = "download_save_failed";
const CODE_ENGINE_UNAVAILABLE: &str = "download_engine_unavailable";
const CODE_FAILED: &str = "download_failed";

/// 事件主题。
const TOPIC_PROGRESS: &str = "download.progress";
const TOPIC_STATE: &str = "download.state";

/// 任务对象 `error.kind` 里的一个取值：sha1 对不上（我们自己算出来的，
/// 不是 gosh-dl 的错误码）。
const KIND_CHECKSUM_MISMATCH: &str = "checksum_mismatch";

/// 我们自己加的一个状态：文件下完了、正在算 sha1。
///
/// 只有带 `sha1` 的任务会经过它，通常几百毫秒 —— 但它是**真实存在**的一段，
/// 藏起来的话前端会先看到 `completed`、过一会儿又变成 `error`，那种「终态回退」
/// 更让人费解。
const STATE_VERIFYING: &str = "verifying";

/// 进度推送的间隔下限/上限。太密会白占总线，太疏进度条会一顿一顿的。
const MIN_PROGRESS_INTERVAL_MS: u64 = 200;
const MAX_PROGRESS_INTERVAL_MS: u64 = 5_000;

/// 「等任务到终态」（[`Queue::wait`]）的兜底重查间隔。
///
/// 事件会更快叫醒它，这个只是上限：事件漏了、发布循环没起来，也不会永远等着。
const RECHECK_INTERVAL: Duration = Duration::from_millis(2_000);

/// 数据根下属于下载队列自己的子目录（只为了满足 gosh-dl 那条「目录必须存在」）。
const DOWNLOAD_SUBDIR: &str = "download";

/// 文件名的字节上限。绝大多数文件系统是 255 **字节**，中文名一个字符占 3 字节，
/// 所以按字节数卡而不是字符数 —— 卡不住的话会在写盘时变成一个语义含糊的异步失败。
const FILENAME_MAX_BYTES: usize = 255;

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// `[modules.config.download]`
///
/// 故意**没有 `dir`**：数据根跟着实例模块走，见模块文档。
#[derive(Debug, Clone, serde::Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct DownloadConfig {
    /// 同时下载的任务数上限。超出的任务停在 `queued`，由 gosh-dl 的优先级队列排队。
    pub max_concurrent: usize,
    /// 单个任务的最大连接数（HTTP 分段下载；服务端不支持 Range 时会自动退回单连接）。
    pub connections_per_download: usize,
    /// 全局限速（字节/秒）。0 = 不限速。
    pub max_download_speed: u64,
    /// 建连超时（秒）。
    pub connect_timeout_secs: u64,
    /// 读空闲超时（秒）：这么久没有新数据就放弃这一轮，按 `max_retries` 重试。
    /// 是**空闲**超时而不是总时长，大文件只要一直有数据就不会被它掐断。
    pub read_timeout_secs: u64,
    /// 单个分段的重试次数。0 = 不重试。
    pub max_retries: usize,
    /// User-Agent。留空 = `EdgeCube-daemon/<版本>`。
    pub user_agent: String,
    /// `download.progress` 的推送间隔（毫秒），clamp 到 [200, 5000]。
    /// 也是「多久扫一次引擎状态」的间隔 —— 事件就是扫出来的，不是引擎直接推的。
    pub progress_interval_ms: u64,
}

impl Default for DownloadConfig {
    fn default() -> Self {
        Self {
            max_concurrent: 3,
            connections_per_download: 8,
            max_download_speed: 0,
            connect_timeout_secs: 30,
            read_timeout_secs: 60,
            max_retries: 5,
            user_agent: String::new(),
            progress_interval_ms: 500,
        }
    }
}

impl DownloadConfig {
    fn clamped_max_concurrent(&self) -> usize {
        self.max_concurrent.clamp(1, 64)
    }

    fn clamped_connections(&self) -> usize {
        self.connections_per_download.clamp(1, 64)
    }

    /// 限速：0 视作「不限」。
    fn effective_speed_limit(&self) -> Option<u64> {
        (self.max_download_speed > 0).then_some(self.max_download_speed)
    }

    fn effective_user_agent(&self) -> String {
        let ua = self.user_agent.trim();
        if ua.is_empty() {
            format!("EdgeCube-daemon/{}", env!("CARGO_PKG_VERSION"))
        } else {
            ua.to_string()
        }
    }

    /// 超时一律至少 1 秒：gosh-dl 那边 0 不是「不限」而是「立刻超时」。
    fn clamped_connect_timeout(&self) -> u64 {
        self.connect_timeout_secs.max(1)
    }

    fn clamped_read_timeout(&self) -> u64 {
        self.read_timeout_secs.max(1)
    }

    fn clamped_progress_interval(&self) -> u64 {
        self.progress_interval_ms
            .clamp(MIN_PROGRESS_INTERVAL_MS, MAX_PROGRESS_INTERVAL_MS)
    }
}

// ---------------------------------------------------------------------------
// 模块状态
// ---------------------------------------------------------------------------

/// 引擎与数据根。`start()` 里定下来之后不再变。
struct Ready {
    engine: Arc<DownloadEngine>,
    /// 实例模块解析出来的数据根；实例根目录由它 + 实例 id 推出来。
    data_dir: PathBuf,
    /// 进度推送循环的句柄。包一层 `Mutex` 是为了 `stop()` 能把它 `take` 出来
    /// （`Ready` 本身在 `OnceLock` 里，只能借到 `&Ready`）。
    /// 测试直接手搓 `Ready`（不起循环）时留空。
    publish: Mutex<Option<PublishLoop>>,
}

/// 推送循环的句柄：停模块时要能把它叫停并等它退干净。
struct PublishLoop {
    cancel: CancellationToken,
    join: tokio::task::JoinHandle<()>,
}

/// daemon 侧自己做的校验（只有 sha1 走这条）。
///
/// 分三段是为了让它**可认领**：扫描循环每拍都会看到同一个「已完成且待校验」的任务，
/// 靠 `Pending → Running` 这次原子转换保证只开工一次。
#[derive(Debug, Clone)]
enum Verify {
    /// 等开工，带着期望的 sha1。
    Pending(String),
    /// 已经在算了（别再 spawn 一遍）。
    Running(String),
    /// 出结果了。`Ok` = 对上；`Err` 里是给人看的原因。
    Done {
        expected: String,
        result: std::result::Result<(), String>,
    },
}

/// 一条任务属于谁。
///
/// 这一层是必要的：gosh-dl 只认绝对路径，而 `download.list` 得给前端一个
/// 「这文件是给谁下的」的说法。两种归属能提供的信息不一样：
///
/// * **实例**：还能给出相对实例根的展示路径（用户认得这个路径）；
/// * **运行环境**（`runtime` 模块的 JDK 包）：目标是队列内部的暂存目录，
///   对用户没意义，所以只报环境 id，不报路径。
#[derive(Debug, Clone)]
pub enum Owner {
    Instance {
        instance_id: String,
        /// 相对实例根目录的目录（`""` = 实例根）。已规范化。
        path: String,
    },
    Runtime {
        /// 环境的可读 id（`zulu-jdk-21-linux-x64`）。
        runtime_id: String,
    },
}

/// 一个任务在 daemon 侧的记账。
///
/// gosh-dl 只认「绝对落盘路径」，不知道实例 / 环境的概念；要回答任务属于谁、
/// 展示路径是什么，只能自己记一份。**只在内存里**（与「不持久化」一致）。
#[derive(Debug, Clone)]
struct TaskMeta {
    owner: Owner,
    filename: String,
    /// 落盘的**绝对路径**。校验失败要删的就是它 —— 存下来是为了事后不必再拼一次
    /// （也就不会因为路径规则改动而删错东西）。
    abs_target: PathBuf,
    /// 交给 gosh-dl 的校验（md5 / sha256）。
    checksum: Option<ExpectedChecksum>,
    /// 我们自己的 sha1 校验；`None` = 这个任务不需要。
    verify: Option<Verify>,
    created_at_ms: u64,
}

#[derive(Default)]
pub(crate) struct QueueState {
    ready: OnceLock<Ready>,
    tasks: Mutex<HashMap<String, TaskMeta>>,
}

impl QueueState {
    /// 取引擎。`start()` 之前或构造失败时方法会拿到 `download_engine_unavailable`，
    /// 而不是一个「内部错误」—— 对前端来说「模块没起来」是可预期的一种状态。
    fn ready(&self) -> RpcResult<&Ready> {
        self.ready
            .get()
            .ok_or_else(|| RpcError::new(CODE_ENGINE_UNAVAILABLE, "下载引擎尚未就绪"))
    }

    /// **测试专用**：起一个能用的队列（建引擎 + 挂 Ready），数据根用调用方给的。
    ///
    /// 正式路径走模块的 `start()`。`runtime` 的测试要把「下载 → 解压」整条跑通，
    /// 得有一只真实引擎，但 200 MB 的 Zulu 包没法当夹具。
    #[cfg(test)]
    pub(crate) async fn test_queue(data_dir: &Path) -> crate::error::Result<Arc<Self>> {
        let engine = build_engine(&DownloadConfig::default(), data_dir).await?;
        let state = Arc::new(Self::default());
        let _ = state.ready.set(Ready {
            engine,
            data_dir: data_dir.to_path_buf(),
            publish: Mutex::new(None),
        });
        Ok(state)
    }

    fn task(&self, id: &str) -> Option<TaskMeta> {
        self.tasks
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(id)
            .cloned()
    }

    fn remember(&self, id: &str, meta: TaskMeta) {
        self.tasks
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(id.to_string(), meta);
    }

    /// 原子地改一条记账（校验流程要「认领」任务，防重复开工）。
    fn update<F>(&self, id: &str, edit: F)
    where
        F: FnOnce(&mut TaskMeta),
    {
        let mut tasks = self.tasks.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(meta) = tasks.get_mut(id) {
            edit(meta);
        }
    }
}

// ---------------------------------------------------------------------------
// 参数校验（都是纯函数，单独测）
// ---------------------------------------------------------------------------

/// 只做「是不是 HTTP 下载」的快速判断。
///
/// 真正的 URL 解析交给 gosh-dl（它已经有 `Url::parse`），这里提前挡一道只是
/// 为了让「URL 写错了」在提交时就有我们的错误码，而不是先落一个任务再异步失败。
fn check_url(url: &str) -> RpcResult<()> {
    if url.is_empty() {
        return Err(RpcError::new(CODE_URL_INVALID, "`url` 不能为空"));
    }
    let lower = url.to_ascii_lowercase();
    if !(lower.starts_with("http://") || lower.starts_with("https://")) {
        return Err(RpcError::new(
            CODE_URL_INVALID,
            format!("只支持 http / https 下载，收到 `{url}`"),
        ));
    }
    Ok(())
}

/// 从 URL 里取最后一段当文件名，取不到给 `None`。
///
/// **不做百分号解码**：`%E4%B8%AD` 那种会原样当文件名。这是刻意的取舍 ——
/// 解码后还要再防一次「解出来个 `/` 或 `..`」，而这一步没法保证与 gosh-dl
/// 内部的取名逻辑逐字一致。想要好看的名字，调用方传 `filename` 就是了。
fn url_basename(url: &str) -> Option<String> {
    let after_scheme = url.find("://").map(|at| &url[at + 3..])?;
    let after_authority = after_scheme.find('/').map(|at| &after_scheme[at + 1..])?;
    let path = after_authority.split(['?', '#']).next().unwrap_or("");
    let last = path.rsplit('/').next().unwrap_or("");
    (!last.is_empty()).then(|| last.to_string())
}

/// 校验文件名：必须是**单段**。
///
/// 目录由 `path` 负责；`filename` 里出现分隔符就等于给「路径逃逸」开了第二个
/// 入口，而逃逸防护只该有一个入口。
fn validate_filename(name: &str) -> RpcResult<String> {
    let name = name.trim();
    if name.is_empty() {
        return Err(RpcError::new(CODE_FILENAME_INVALID, "文件名不能为空"));
    }
    if name == "." || name == ".." {
        return Err(RpcError::new(
            CODE_FILENAME_INVALID,
            format!("文件名不能是 `{name}`"),
        ));
    }
    if name.contains('/') || name.contains('\\') {
        return Err(RpcError::new(
            CODE_FILENAME_INVALID,
            format!("文件名里不能有路径分隔符（`{name}`），目录请用 `path` 参数"),
        ));
    }
    if name.chars().any(char::is_control) {
        return Err(RpcError::new(
            CODE_FILENAME_INVALID,
            "文件名里不能有控制字符",
        ));
    }
    if name.len() > FILENAME_MAX_BYTES {
        return Err(RpcError::new(
            CODE_FILENAME_INVALID,
            format!(
                "文件名过长（{} 字节，上限 {FILENAME_MAX_BYTES}）",
                name.len()
            ),
        ));
    }
    Ok(name.to_string())
}

/// 提交时收下来的校验要求。
#[derive(Debug, Clone, Default)]
struct Checksums {
    /// 交给 gosh-dl 的那一种（md5 / sha256），下载时就校。
    engine: Option<ExpectedChecksum>,
    /// 我们事后自己算的 sha1。
    sha1: Option<String>,
}

/// 把 `md5` / `sha256` / `sha1` 三个可选参数收成一个校验要求。
///
/// **给了多个就报错**，不静默取一个：gosh-dl 的 `checksum` 只能放一个，
/// 而「我明明写了两个校验值，结果只校了一个」是那种事后极难发现的问题。
fn parse_checksum(
    md5: Option<String>,
    sha256: Option<String>,
    sha1: Option<String>,
) -> RpcResult<Checksums> {
    let md5 = clean(md5);
    let sha256 = clean(sha256);
    let sha1 = clean(sha1);

    let given: Vec<&str> = [
        md5.as_ref().map(|_| "md5"),
        sha256.as_ref().map(|_| "sha256"),
        sha1.as_ref().map(|_| "sha1"),
    ]
    .into_iter()
    .flatten()
    .collect();

    if given.len() > 1 {
        return Err(RpcError::new(
            CODE_CHECKSUM_INVALID,
            format!(
                "`md5` / `sha256` / `sha1` 只能给一个（只校一个值才能让失败原因唯一），收到 {}",
                given.join(" + ")
            ),
        ));
    }

    Ok(match (md5, sha256, sha1) {
        (None, None, None) => Checksums::default(),
        (Some(value), None, None) => {
            check_hex(&value, 32, "md5")?;
            Checksums {
                engine: Some(ExpectedChecksum::md5(value)),
                sha1: None,
            }
        }
        (None, Some(value), None) => {
            check_hex(&value, 64, "sha256")?;
            Checksums {
                engine: Some(ExpectedChecksum::sha256(value)),
                sha1: None,
            }
        }
        (None, None, Some(value)) => {
            check_hex(&value, 40, "sha1")?;
            Checksums {
                engine: None,
                sha1: Some(value.to_ascii_lowercase()),
            }
        }
        // 上面已经挡过「多于一个」，这里不会再走到
        _ => unreachable!("多值情况已在前面拒绝"),
    })
}

/// 去空白；空白串当作「没给」。
fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// 校验十六进制摘要：长度与字符集都要对，**在提交时**就报，而不是等下完才说。
fn check_hex(value: &str, digits: usize, field: &str) -> RpcResult<()> {
    if value.len() != digits {
        return Err(RpcError::new(
            CODE_CHECKSUM_INVALID,
            format!(
                "`{field}` 应该是 {digits} 位十六进制，当前 {} 位",
                value.len()
            ),
        ));
    }
    if !value.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(RpcError::new(
            CODE_CHECKSUM_INVALID,
            format!("`{field}` 里有非十六进制字符"),
        ));
    }
    Ok(())
}

/// gosh-dl 的错误 → 我们的稳定错误码。
///
/// 提交阶段能冒出来的只有参数类与落盘类；网络/协议问题都是异步的，走任务状态。
fn map_engine_error(err: EngineError) -> RpcError {
    let message = err.to_string();
    match err {
        EngineError::InvalidInput { field, .. } => match field {
            "url" => RpcError::new(CODE_URL_INVALID, message),
            "filename" => RpcError::new(CODE_FILENAME_INVALID, message),
            _ => RpcError::invalid_params(message),
        },
        EngineError::Storage {
            kind: StorageErrorKind::PathTraversal | StorageErrorKind::InvalidPath,
            ..
        } => RpcError::new(CODE_PATH_INVALID, message),
        EngineError::Storage { .. } => RpcError::new(CODE_SAVE_FAILED, message),
        EngineError::NotFound(_) => RpcError::new(CODE_TASK_NOT_FOUND, message),
        EngineError::Shutdown => RpcError::new(CODE_ENGINE_UNAVAILABLE, "下载引擎正在关闭"),
        other => RpcError::new(CODE_FAILED, other.to_string()),
    }
}

fn engine_error(err: EngineError) -> Error {
    Error::module("download", err.to_string())
}

/// 状态名。写全枚举而不是拿 serde 出来的 JSON 凑：gosh-dl 加一个状态时
/// 编译器会在这里拦住我们，而不是悄悄多出一个没人认识的状态字符串。
fn state_name(state: &DownloadState) -> &'static str {
    match state {
        DownloadState::Queued => "queued",
        DownloadState::Connecting => "connecting",
        DownloadState::Downloading => "downloading",
        DownloadState::Seeding => "seeding",
        DownloadState::Paused => "paused",
        DownloadState::Completed => "completed",
        DownloadState::Error { .. } => "error",
    }
}

/// 任务对外的状态。
///
/// 大部分时候就是 gosh-dl 的状态；只有「要我们自己算 sha1」的任务会多出
/// `verifying`（文件已下完、正在算），以及算完不匹配时把 `completed` 翻成 `error`。
fn effective_state(status: &DownloadStatus, meta: Option<&TaskMeta>) -> &'static str {
    let Some(verify) = meta.and_then(|m| m.verify.as_ref()) else {
        return state_name(&status.state);
    };
    match verify {
        // 还没出结果：只有引擎说「下完了」才叫校验中，否则沿用引擎的状态
        Verify::Pending(_) | Verify::Running(_) => {
            if matches!(status.state, DownloadState::Completed) {
                STATE_VERIFYING
            } else {
                state_name(&status.state)
            }
        }
        Verify::Done { result: Ok(()), .. } => "completed",
        Verify::Done { result: Err(_), .. } => "error",
    }
}

/// 任务对象的 `error` 字段。
///
/// sha1 对不上是我们自己判的，所以它**优先于**引擎的状态 —— 引擎那边这个任务
/// 仍然是 `completed`（文件确实下完了，只是内容不对）。
fn task_error(status: &DownloadStatus, meta: Option<&TaskMeta>) -> Option<Value> {
    if let Some(Verify::Done {
        result: Err(message),
        ..
    }) = meta.and_then(|m| m.verify.as_ref())
    {
        return Some(json!({
            "kind": KIND_CHECKSUM_MISMATCH,
            "message": message,
            "retryable": false,
        }));
    }
    match &status.state {
        DownloadState::Error {
            kind,
            message,
            retryable,
        } => Some(json!({
            "kind": kind,
            "message": message,
            "retryable": retryable,
        })),
        _ => None,
    }
}

/// 展示用的校验值：md5 / sha256 来自 gosh-dl 那份，sha1 来自我们自己的记账。
fn task_checksum(meta: Option<&TaskMeta>) -> Option<Value> {
    let meta = meta?;
    if let Some(checksum) = &meta.checksum {
        return Some(json!({
            "algorithm": checksum.algorithm.to_string(),
            "value": checksum.value,
        }));
    }
    let expected = match meta.verify.as_ref()? {
        Verify::Pending(value) | Verify::Running(value) => value.clone(),
        Verify::Done { expected, .. } => expected.clone(),
    };
    Some(json!({ "algorithm": "SHA1", "value": expected }))
}

/// 一个任务对象。三个方法返回的都是这个形状，事件里也复用它的核心字段。
fn render_task(status: &DownloadStatus, meta: Option<&TaskMeta>) -> Value {
    let progress = &status.progress;
    let state = effective_state(status, meta);
    let error = task_error(status, meta);
    let filename = meta.map(|m| m.filename.clone());

    // 归属决定能报哪些展示字段：实例任务给相对路径，环境任务只给 id。
    let (instance_id, dir, target, runtime_id) = match meta.map(|m| &m.owner) {
        Some(Owner::Instance { instance_id, path }) => {
            let target = match &filename {
                Some(name) if path.is_empty() => name.clone(),
                Some(name) => format!("{path}/{name}"),
                None => String::new(),
            };
            (json!(instance_id), json!(path), json!(target), Value::Null)
        }
        Some(Owner::Runtime { runtime_id }) => {
            (Value::Null, Value::Null, Value::Null, json!(runtime_id))
        }
        // 记账丢了（不该发生）：留空，不去拿绝对路径瞎猜一个「相对路径」出来
        None => (Value::Null, Value::Null, Value::Null, Value::Null),
    };

    json!({
        "id": status.id.as_uuid().to_string(),
        "instance_id": instance_id,
        // 相对实例根目录的目录（"" = 实例根）与完整落盘路径，前端展示用后者
        "path": dir,
        "filename": filename,
        "target": target,
        // 非 null = 这个任务是给某个运行环境下包的（见 `submit_internal`）
        "runtime_id": runtime_id,
        "state": state,
        "url": status.metadata.url,
        "total_size": progress.total_size,
        "completed_size": progress.completed_size,
        "download_speed": progress.download_speed,
        "eta_seconds": progress.eta_seconds,
        "connections": progress.connections,
        "checksum": task_checksum(meta),
        "created_at_ms": meta.map(|m| m.created_at_ms),
        "finished_at_ms": finished_at_ms(status),
        "error": error,
        // gosh-dl 自己的 ETA 是「按当前瞬时速度估」的，别把它当承诺
        "progress_percent": progress.percentage(),
    })
}

/// gosh-dl 的时间戳转成本项目的毫秒整数约定。
///
/// `chrono` 是 gosh-dl 的依赖、不是我们的，但这里只是**在它给的值上调一个固有
/// 方法**，不需要把 chrono 写进 Cargo.toml。
fn finished_at_ms(status: &DownloadStatus) -> Option<i64> {
    status.completed_at.map(|t| t.timestamp_millis())
}

// ---------------------------------------------------------------------------
// 进程内入口（给别的模块用）
// ---------------------------------------------------------------------------
//
// 下载引擎是**进程单例**：并发额度、限速、任务表都只有一份。别的模块
// （目前是 `runtime`，它要把 JDK 的压缩包下到自己的暂存目录）要复用队列，
// 就得拿到同一个句柄。
//
// 模块之间**没有对象查找**：`ModuleRegistry::all_modules()` 回吐的是
// `Arc<dyn Module>`，而 trait 上没有 `as_any`，拿不到具体类型。所以队列句柄
// 挂在 `AppState` 跨模块句柄槽上（见 [`crate::services`]）—— `start()` 里放进去，
// 别的模块用 [`queue_of`] 取。
//
// 为什么不是模块内的 `static OnceLock`：队列绑着数据目录与下载引擎，是**有状态**
// 的句柄；进程级全局会在「一个进程多个 `AppState`」（集成测试）下串到别的实例上。

/// 取这次运行的队列句柄；download 模块没起来时为 `None`。
pub fn queue_of(app: &AppState) -> Option<Queue> {
    app.services.get::<Queue>().map(|queue| (*queue).clone())
}

/// 队列句柄。
///
/// 包一层是为了**不把 `QueueState` 暴露出去**：那一堆内部字段没有一个是别的
/// 模块该碰的，这里只给两个动作 —— 提交、等终态。
#[derive(Clone)]
pub struct Queue(Arc<QueueState>);

impl Queue {
    /// **测试专用**：显式给一个队列状态（正式路径见 [`queue`]）。
    #[cfg(test)]
    pub(crate) fn from_state(state: Arc<QueueState>) -> Self {
        Self(state)
    }

    /// 提交一个进程内下载任务，返回任务 id。只提交，**不等下载结束**。
    pub async fn submit(&self, req: InternalRequest) -> RpcResult<DownloadId> {
        let state = &self.0;
        let ready = state.ready()?;

        check_url(&req.url)?;
        let filename = validate_filename(&req.filename)?;

        // 复用 WS 那条路同一个「校验值 → 引擎参数」的翻译，别写第二份校验逻辑
        let (md5, sha256, sha1) = match &req.checksum {
            None => (None, None, None),
            Some(("md5", value)) => (Some(value.clone()), None, None),
            Some(("sha256", value)) => (None, Some(value.clone()), None),
            Some(("sha1", value)) => (None, None, Some(value.clone())),
            Some((other, _)) => {
                return Err(RpcError::new(
                    CODE_CHECKSUM_INVALID,
                    format!("不支持的校验算法 `{other}`（只有 md5 / sha256 / sha1）"),
                ));
            }
        };
        let checksums = parse_checksum(md5, sha256, sha1)?;

        tokio::fs::create_dir_all(&req.dir).await.map_err(|e| {
            RpcError::new(
                CODE_SAVE_FAILED,
                format!("创建目录 `{}` 失败: {e}", req.dir.display()),
            )
        })?;

        let abs_target = req.dir.join(&filename);
        let options = DownloadOptions {
            save_dir: Some(req.dir.clone()),
            filename: Some(filename.clone()),
            checksum: checksums.engine.clone(),
            ..DownloadOptions::default()
        };
        let id = ready
            .engine
            .add_http(&req.url, options)
            .await
            .map_err(map_engine_error)?;

        state.remember(
            &id.as_uuid().to_string(),
            TaskMeta {
                owner: req.owner,
                filename,
                abs_target,
                checksum: checksums.engine,
                verify: checksums.sha1.map(Verify::Pending),
                created_at_ms: now_ms(),
            },
        );
        Ok(id)
    }

    /// 等一个任务到终态。
    ///
    /// **先订阅总线再查一次快照**：只订阅的话，「订阅之前就已经结束」会永远等下去；
    /// 有了这次快照兜底才闭合。之后靠 `download.state` 事件唤醒。
    ///
    /// 另外还有一个**低频兜底重查**：事件只是「快点知道」，不是唯一的真相来源。
    /// 发布循环万一没起来（测试里就是）、或者哪一拍漏了，兜底那一查仍然能收敛 ——
    /// 安装流程卡死在一个没人再发的等待上，比每两秒看一眼状态难查得多。
    pub async fn wait(&self, app: &AppState, id: DownloadId) -> DownloadOutcome {
        let state = &self.0;
        let id_str = id.as_uuid().to_string();
        let mut events = app.bus.subscribe();

        let mut seen = false;
        loop {
            // 每被唤醒一次就重查一遍：既处理「还没入账」，也处理「已经到终态了」
            if let Some(outcome) = terminal_outcome(state, id, &id_str, &mut seen) {
                return outcome;
            }

            tokio::select! {
                event = events.recv() => match event {
                    Ok(event) => {
                        // 只关心状态迁移，且只认属于这个任务的那条
                        if event.topic != TOPIC_STATE {
                            continue;
                        }
                        if event.data.get("id").and_then(Value::as_str) != Some(id_str.as_str()) {
                            continue;
                        }
                    }
                    // 丢帧：不用补历史，下一轮的快照会把真值带回来
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    // 总线关了 = daemon 在收摊
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                        return DownloadOutcome::Gone;
                    }
                },
                _ = tokio::time::sleep(RECHECK_INTERVAL) => continue,
            }
        }
    }
}

/// 一次进程内下载请求。
///
/// 与 WS 那条 `download.add` 的**关键区别**：[`dir`](Self::dir) 是调用方自己算出来的
/// 绝对路径。用户在 WS 上只能给「相对实例根的路径」，是因为根目录必须由 daemon
/// 决定；而这里是模块之间的调用，没有用户输入穿过来。
pub struct InternalRequest {
    /// 落盘目录（绝对路径）。
    pub dir: PathBuf,
    /// 文件名（单段，调用方保证）。
    pub filename: String,
    pub url: String,
    /// `(算法, 值)`；算法取值就是 `download.add` 的参数名（`sha256` / `md5` / `sha1`）。
    pub checksum: Option<(&'static str, String)>,
    /// 归属。**进程内调用必须自己说清楚** —— `download.status` / `download.list`
    /// 会拿它渲染 `instance_id` / `runtime_id`，前端据此把这条下载挂到实例或环境下。
    pub owner: Owner,
}

/// 一个任务最终怎么了。
#[derive(Debug, Clone)]
pub enum DownloadOutcome {
    /// 下完且校验通过（含我们自算的 sha1）；`path` 是落盘的绝对路径。
    Completed { path: PathBuf },
    /// 失败（连不上 / 404 / 校验不过 / 文件写不进去）。`message` 给人看。
    Failed { message: String },
    /// 任务不在了或队列已经停了 —— 这一轮没下成，但**不算「失败」**：
    /// daemon 重启、模块被关、用户取消都会走到这里。
    Gone,
}

/// **给工作流步骤用**：把一次下载交给全局队列、等到终态，边等边报进度。
///
/// 与 [`Queue::wait`] 的两点差别（也正是它存在的理由）：
///
/// * **报进度**：`wait` 只等终态；这里每收到一帧 `download.progress`、以及每
///   个兜底轮询周期，都把进度交给 `report`（中性形状，见 [`progress_payload`]）；
/// * **可取消**：`cancel` 一触发就立刻返回 `Err`，不用等下载跑完。
///   步骤的取消因此是「秒回」的。
///
/// `on_submitted` 在**提交成功、还没下完**时就回调一次队列任务 id ——
/// 调用方通常要把它先写进自己的元数据（运行环境就是靠 `env.task_id` 让前端
/// 订上 `download.progress` 的），等下载结束再写就太晚了。
///
/// 注意取消**不会**停掉队列里那次下载（队列没有「按 id 取消」的接口）：文件会
/// 安静地下完，只是没人再等它。这与任务系统「取消不触发回滚」是同一条取舍。
///
/// 错误是**给人看的字符串**（szal 的步骤约定），不是错误码。
///
/// 队列**按参数传**而不是自己 `queue()` 取全局：这样测试能塞一只本地引擎
/// （`QueueState::test_queue`）进来把整条链路跑通，不必去抢那个进程级 `OnceLock`。
pub async fn fetch(
    queue: &Queue,
    app: &AppState,
    req: InternalRequest,
    cancel: &CancellationToken,
    on_submitted: impl FnOnce(&str),
    report: impl Fn(Value) + Send + Sync,
) -> std::result::Result<PathBuf, String> {
    let id = queue
        .submit(req)
        .await
        .map_err(|e| format!("{}：{}", e.code, e.message))?;
    let id_str = id.as_uuid().to_string();
    on_submitted(&id_str);
    let state = &*queue.0;

    let mut events = app.bus.subscribe();
    let mut seen = false;
    loop {
        if let Some(outcome) = terminal_outcome(state, id, &id_str, &mut seen) {
            return match outcome {
                DownloadOutcome::Completed { path } => Ok(path),
                DownloadOutcome::Failed { message } => Err(message),
                DownloadOutcome::Gone => Err("下载已中断（队列停了或任务被撤回）".to_string()),
            };
        }
        // 报一帧当前进度：任务刚提交时也能立刻给出「已开始」的形状
        if let Some(payload) = progress_payload(state, id, &id_str) {
            report(payload);
        }

        tokio::select! {
            _ = cancel.cancelled() => return Err("已取消".to_string()),
            event = events.recv() => match event {
                Ok(event) => {
                    // 进度帧与状态帧都值得唤醒；别的主题直接跳过
                    if event.topic != TOPIC_STATE && event.topic != TOPIC_PROGRESS {
                        continue;
                    }
                    if event.data.get("id").and_then(Value::as_str) != Some(id_str.as_str()) {
                        continue;
                    }
                }
                // 丢帧不用补历史：下一轮快照/轮询会把真值带回来
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err("下载已中断（daemon 正在关闭）".to_string());
                }
            },
            _ = tokio::time::sleep(RECHECK_INTERVAL) => continue,
        }
    }
}

/// 把下载任务对象压成**步骤进度的中性形状**。
///
/// 步骤实现直接把它当 `StepProgress.data` 报出去即可 —— 两条工作流
/// （实例、运行环境）不必各自再写一遍字段映射，前端也只需认一套字段。
fn progress_payload(state: &QueueState, id: DownloadId, id_str: &str) -> Option<Value> {
    let ready = state.ready().ok()?;
    let status = ready.engine.status(id)?;
    let task = render_task(&status, state.task(id_str).as_ref());
    Some(json!({
        "percent": progress_percent(&task),
        "downloaded": task["completed_size"],
        "total": task["total_size"],
        "speed": task["download_speed"],
        "eta_seconds": task["eta_seconds"],
        "state": task["state"],
    }))
}

/// 百分比取整到 0-100。引擎还没拿到总大小时百分比为 `null` —— 那种情况
/// 报 `null`（前端画不确定进度），**不要**退化成 0，否则进度条会先跳回原点。
fn progress_percent(task: &Value) -> Value {
    let Some(percent) = task["progress_percent"].as_f64() else {
        return Value::Null;
    };
    json!(percent.clamp(0.0, 100.0))
}

/// 查一次「到终态了吗」。顺带维护 `seen`（这个任务确实入过账）。
fn terminal_outcome(
    state: &QueueState,
    id: DownloadId,
    id_str: &str,
    seen: &mut bool,
) -> Option<DownloadOutcome> {
    let ready = state.ready().ok()?;
    let Some(status) = ready.engine.status(id) else {
        // 引擎里已经没有它了：取消、或者模块正在关。**只有见过它**才敢这么判，
        // 否则「提交完但还没入账」会被误判成 Gone。
        return seen.then_some(DownloadOutcome::Gone);
    };
    *seen = true;

    let meta = state.task(id_str);
    match effective_state(&status, meta.as_ref()) {
        "completed" => Some(DownloadOutcome::Completed {
            path: meta.map(|m| m.abs_target).unwrap_or_default(),
        }),
        "error" => Some(DownloadOutcome::Failed {
            message: task_error(&status, meta.as_ref())
                .and_then(|e| {
                    e.get("message")
                        .and_then(Value::as_str)
                        .map(|s| s.to_string())
                })
                .unwrap_or_else(|| "下载失败".to_string()),
        }),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// 模块本体
// ---------------------------------------------------------------------------

pub struct DownloadModule {
    state: Arc<QueueState>,
}

impl Default for DownloadModule {
    fn default() -> Self {
        Self::new()
    }
}

impl DownloadModule {
    pub fn new() -> Self {
        Self {
            state: Arc::new(QueueState::default()),
        }
    }
}

// ── download.add ──────────────────────────────────────────────────────────

/// 提交一个下载任务。
///
/// 校验顺序是刻意的：**先确认实例存在、再解析路径、最后才碰引擎**。每一步都
/// 比上一步便宜，而且都在「任务已经进了队列」之前 —— 否则用户会拿到一个任务 ID，
/// 然后看它异步失败。
async fn add(state: &Arc<QueueState>, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;

    let url = ctx.param::<String>("url")?.trim().to_string();
    check_url(&url)?;

    let instance_id = ctx.param::<String>("instance_id")?.trim().to_string();
    validate_instance_id(&instance_id).map_err(RpcError::invalid_params)?;

    let path = ctx.param_or("path", String::new())?;
    let filename_arg = clean(ctx.optional::<String>("filename")?);
    let checksums = parse_checksum(
        ctx.optional("md5")?,
        ctx.optional("sha256")?,
        ctx.optional("sha1")?,
    )?;

    // 1) 实例根目录
    let root = resolve_instance_root(&ready.data_dir, &instance_id)
        .map_err(|msg| RpcError::new(CODE_INSTANCE_NOT_FOUND, msg))?;

    // 2) 相对路径 → 实例目录内的绝对路径。逃逸防护复用 instance 那一份。
    let dir =
        files::resolve(&root, &path).map_err(|e| RpcError::new(CODE_PATH_INVALID, e.message))?;
    let rel_dir = files::display_path(&root, &dir);

    // 3) 文件名：给了就用，没给从 URL 末段取
    let filename = match filename_arg {
        Some(name) => validate_filename(&name)?,
        None => {
            let derived = url_basename(&url).ok_or_else(|| {
                RpcError::new(
                    CODE_FILENAME_MISSING,
                    format!("URL 里没有可用的文件名，请显式传 `filename`：`{url}`"),
                )
            })?;
            validate_filename(&derived)?
        }
    };

    let target = dir.join(&filename);
    let rel_target = if rel_dir.is_empty() {
        filename.clone()
    } else {
        format!("{rel_dir}/{filename}")
    };

    // 4) 目标已存在就拒绝。
    //
    // gosh-dl 默认是**静默覆盖**（先写 `<name>.part` 再挪到终名），而这里写的是
    // 实例目录 —— 里面躺着服务端 jar、世界存档。静默盖掉是不可接受的，
    // 所以宁可让前端先删/改名。这个检查是尽力而为（检查与落盘之间有时差）。
    if target.exists() {
        return Err(RpcError::new(
            CODE_TARGET_EXISTS,
            format!("目标已存在：`{rel_target}`；要覆盖请先删掉它，或换一个 `filename`"),
        ));
    }
    // 同一个文件已经有一个**还在跑**的任务，也按「已存在」处理。同样是尽力而为，
    // 挡的是「手抖点两次」这种最常见的误操作。
    //
    // 只算**没结束**的任务：失败过的任务会一直留在记账里（列表要显示它），
    // 要是拿它挡路，用户重试同一个文件就会被自己的历史任务顶回来。
    let candidates: Vec<String> = {
        let tasks = state.tasks.lock().unwrap_or_else(|e| e.into_inner());
        tasks
            .iter()
            .filter(|(_, meta)| {
                matches!(
                    &meta.owner,
                    Owner::Instance { instance_id: owner, path }
                        if owner == &instance_id && path == &rel_dir
                ) && meta.filename == filename
            })
            .map(|(id, _)| id.clone())
            .collect()
    };
    let duplicate = candidates.into_iter().find(|id| {
        parse_task_id(id)
            .ok()
            .and_then(|parsed| ready.engine.status(parsed))
            .is_some_and(|status| !status.state.is_finished())
    });
    if let Some(existing) = duplicate {
        return Err(RpcError::new(
            CODE_TARGET_EXISTS,
            format!("`{rel_target}` 已经有一个下载任务了（任务 {existing}）"),
        ));
    }

    // 5) 把目录建出来。gosh-dl 自己也会建，这里先建是为了让「路径不可写」在
    //    **提交时**就报出来，而不是变成一个异步失败的任务。
    tokio::fs::create_dir_all(&dir).await.map_err(|e| {
        RpcError::new(
            CODE_SAVE_FAILED,
            format!("创建目录 `{}` 失败: {e}", dir.display()),
        )
    })?;

    // 6) 交给引擎。`filename` **一定**显式传：不传的话 gosh-dl 可能改用
    //    `Content-Disposition` 里的名字，落盘位置就不再由我们决定，
    //    上面的预检与记账也会跟着失真。
    //
    //    `checksum` 只填 md5/sha256 那一路；sha1 引擎不认，由我们事后自己算。
    let options = DownloadOptions {
        save_dir: Some(dir.clone()),
        filename: Some(filename.clone()),
        checksum: checksums.engine.clone(),
        ..DownloadOptions::default()
    };
    let id = ready
        .engine
        .add_http(&url, options)
        .await
        .map_err(map_engine_error)?;

    let id_str = id.as_uuid().to_string();
    let meta = TaskMeta {
        owner: Owner::Instance {
            instance_id,
            path: rel_dir,
        },
        filename,
        abs_target: target,
        checksum: checksums.engine,
        verify: checksums.sha1.map(Verify::Pending),
        created_at_ms: now_ms(),
    };
    state.remember(&id_str, meta.clone());

    let status = ready
        .engine
        .status(id)
        .ok_or_else(|| RpcError::new(CODE_TASK_NOT_FOUND, "任务刚提交就查不到了"))?;

    tracing::info!(task = %id_str, url = %url, target = %rel_target, "下载任务已提交");
    Ok(json!({ "task": render_task(&status, Some(&meta)) }))
}

// ── download.status ───────────────────────────────────────────────────────

fn status(state: &Arc<QueueState>, ctx: &CallCtx) -> RpcResult<Value> {
    let ready = state.ready()?;
    let raw = ctx.param::<String>("id")?;
    let id = parse_task_id(&raw)?;

    let status = ready
        .engine
        .status(id)
        .ok_or_else(|| RpcError::new(CODE_TASK_NOT_FOUND, format!("没有任务 `{raw}`")))?;
    // 查表一律用**规范化**后的 UUID（用户可能发大写），否则会出现
    // 「查得到但返回的 instance_id 是 null」这种莫名其妙的结果。
    let meta = state.task(&id.as_uuid().to_string());
    Ok(json!({ "task": render_task(&status, meta.as_ref()) }))
}

// ── download.list ─────────────────────────────────────────────────────────

fn list(state: &Arc<QueueState>) -> RpcResult<Value> {
    let ready = state.ready()?;

    // 先把记账快照出来：排序比较器里反复加锁既慢又没意义。
    let metas: HashMap<String, TaskMeta> = state
        .tasks
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clone();

    // gosh-dl 的 `list()` 是 HashMap 顺序（不保证稳定），我们固定成
    // 「最新提交在前」—— 前端能靠它做稳定的增量刷新。时间戳相同（同一毫秒提交）
    // 时再按 UUID 兜底，保证顺序是全序而不是「看起来随机」。
    let mut statuses = ready.engine.list();
    statuses.sort_by(|a, b| {
        let key = |s: &DownloadStatus| {
            metas
                .get(&s.id.as_uuid().to_string())
                .map(|m| m.created_at_ms)
        };
        key(b)
            .cmp(&key(a))
            .then_with(|| a.id.as_uuid().cmp(b.id.as_uuid()))
    });

    let tasks: Vec<Value> = statuses
        .iter()
        .map(|s| render_task(s, metas.get(&s.id.as_uuid().to_string())))
        .collect();

    let stats = ready.engine.global_stats();
    Ok(json!({
        "tasks": tasks,
        "count": tasks.len(),
        "stats": {
            "download_speed": stats.download_speed,
            "active": stats.num_active,
            "waiting": stats.num_waiting,
            "stopped": stats.num_stopped,
        },
    }))
}

/// 解析任务 ID。gosh-dl 的任务 ID 是 UUID，**只接受完整形式**：
/// `DownloadId::to_gid()` 那种 16 位 hex 是只取前 8 字节的有损投影，拿它反查
/// 会得到另一个 ID（`from_gid` 会把上位 8 字节填零）。
fn parse_task_id(raw: &str) -> RpcResult<DownloadId> {
    let trimmed = raw.trim();
    let uuid = Uuid::parse_str(trimmed).map_err(|_| {
        RpcError::new(
            CODE_TASK_NOT_FOUND,
            format!("任务 ID 应该是完整 UUID（36 字符），收到 `{raw}`"),
        )
    })?;
    Ok(DownloadId::from_uuid(uuid))
}

// ---------------------------------------------------------------------------
// sha1：自己算的那一路
// ---------------------------------------------------------------------------

/// 流式算一个文件的 sha1（**阻塞**，调用方丢 `spawn_blocking`）。
///
/// 服务端 jar 有几十 MB，整合包能上 GB —— 整个读进内存是不行的，所以按块喂。
fn sha1_of_file(path: &Path) -> std::result::Result<String, String> {
    use std::io::Read;

    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Sha1::new();
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf).map_err(|e| e.to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    // 自己拼十六进制：为一行编码引入 `hex` 依赖不划算（gosh-dl 也没 re-export）
    Ok(hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

/// 算完一个任务的 sha1，写回记账。
///
/// 对不上就**删掉这份文件**：留一个内容不对的 `server.jar` 比没有更糟 ——
/// 用户会以为下好了，然后对着一个启动不起来的服务端查半天。
async fn verify_task(state: Arc<QueueState>, id: String, expected: String, path: PathBuf) {
    let outcome = tokio::task::spawn_blocking({
        let path = path.clone();
        move || sha1_of_file(&path)
    })
    .await;

    let result = match outcome {
        Ok(Ok(actual)) if actual.eq_ignore_ascii_case(&expected) => Ok(()),
        Ok(Ok(actual)) => {
            let removed = tokio::fs::remove_file(&path).await;
            if let Err(e) = &removed {
                tracing::warn!(task = %id, path = %path.display(), error = %e, "校验失败的文件删不掉");
            }
            tracing::warn!(task = %id, expected = %expected, actual = %actual, "sha1 不匹配，已丢弃文件");
            Err(format!(
                "sha1 不匹配：期望 {expected}，实际 {actual}；这个文件已删除"
            ))
        }
        Ok(Err(e)) => Err(format!("读取文件算 sha1 失败：{e}")),
        Err(e) => Err(format!("校验任务没能跑起来：{e}")),
    };

    // 结果一写回，下一拍扫描就会把状态从 verifying 改成 completed / error
    // 并发 `download.state` —— 这里不用自己推事件。
    state.update(&id, |meta| {
        meta.verify = Some(Verify::Done { expected, result });
    });
}

// ---------------------------------------------------------------------------
// 事件推送
// ---------------------------------------------------------------------------

/// 进度 / 状态推送循环。
///
/// 每 `interval_ms` 扫一遍引擎的全部任务：
///
/// * 状态**变了** → 推一条 `download.state`；
/// * 排队中 / 进行中 → 推一条 `download.progress`。
///
/// 两条主题的数据都是**完整的任务对象**（和 `download.status` 返回的那个同形），
/// 前端一套模型就能同时吃快照与事件。
///
/// 为什么是「扫」而不是订阅 gosh-dl 的事件：它每读一块推一条，一个 60 MB 的 jar
/// 上千条。定时扫天然节流；而且慢消费者丢事件（broadcast 的 `Lagged`）也不怕 ——
/// 下一拍全会重新对齐，不需要补历史。
///
/// 这个循环**不推终态之外的历史**：新连上来的客户端先自己 `download.list` 拿快照。
async fn run_publish_loop(
    state: Arc<QueueState>,
    engine: Arc<DownloadEngine>,
    app: AppState,
    interval_ms: u64,
    cancel: CancellationToken,
) {
    let mut ticker = tokio::time::interval(Duration::from_millis(interval_ms));
    // 上一轮慢了就顺延，不追着补发一串。
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    // 上一拍每个任务的状态。用来判定「变了」——状态事件只在迁移时推，
    // 否则一个卡住的下载会每 500ms 刷一条没意义的 state。
    let mut last_states: HashMap<String, &'static str> = HashMap::new();

    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = ticker.tick() => {
                let metas: HashMap<String, TaskMeta> = state
                    .tasks
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone();

                for status in engine.list() {
                    let id = status.id.as_uuid().to_string();
                    let meta = metas.get(&id);

                    // 引擎说下完了、而我们还欠一次 sha1 → 认领并开工。
                    // `Pending → Running` 在锁里做，保证只开工一次。
                    if matches!(status.state, DownloadState::Completed)
                        && let Some((Verify::Pending(expected), target)) = meta
                            .and_then(|m| m.verify.as_ref().map(|v| (v, m.abs_target.clone())))
                    {
                        let mut claimed = false;
                        state.update(&id, |m| {
                            if let Some(Verify::Pending(expected)) = m.verify.take() {
                                m.verify = Some(Verify::Running(expected));
                                claimed = true;
                            }
                        });
                        if claimed {
                            tokio::spawn(verify_task(
                                state.clone(),
                                id.clone(),
                                expected.clone(),
                                target,
                            ));
                        }
                    }

                    let current = effective_state(&status, meta);
                    let payload = render_task(&status, meta);
                    let changed = last_states.get(&id) != Some(&current);

                    if changed {
                        app.bus.publish_from(Some("download"), TOPIC_STATE, payload.clone());
                        last_states.insert(id.clone(), current);
                    }
                    // 排队中与进行中都值得报进度（`verifying` 也算「还没结束」，
                    // 前端进度条要停在 100% 而不是跳回 0）
                    if is_in_flight(&status.state) || current == STATE_VERIFYING {
                        app.bus
                            .publish_from(Some("download"), TOPIC_PROGRESS, payload);
                    }
                }
            }
        }
    }
}

/// 还在路上（含排队）的状态 —— 这些才推进度；终态由 `download.state` 报一次就够。
fn is_in_flight(state: &DownloadState) -> bool {
    matches!(
        state,
        DownloadState::Queued
            | DownloadState::Connecting
            | DownloadState::Downloading
            | DownloadState::Seeding
            | DownloadState::Paused
    )
}

// ---------------------------------------------------------------------------
// 模块实现
// ---------------------------------------------------------------------------

/// 数据根 = instance 模块那一节解析出来的目录。
///
/// 读的是**配置节本身**而不是 instance 模块的运行时状态：这样即使 instance 被
/// `modules.disabled` 关掉，下载也照样能算对目录（配置节在禁用时只是被 instance
/// 模块忽略，内容仍在 `Config` 里）。
async fn build_engine(config: &DownloadConfig, data_dir: &Path) -> Result<Arc<DownloadEngine>> {
    // gosh-dl 要求 download_dir 必须已存在，会在 `validate()` 里直接报错。
    let queue_dir: &Path = &data_dir.join(DOWNLOAD_SUBDIR);
    tokio::fs::create_dir_all(queue_dir).await?;

    let engine_config = EngineConfig {
        download_dir: queue_dir.to_path_buf(),
        max_concurrent_downloads: config.clamped_max_concurrent(),
        max_connections_per_download: config.clamped_connections(),
        global_download_limit: config.effective_speed_limit(),
        user_agent: config.effective_user_agent(),
        // 队列不落盘：重启即清空。要持久化时这里给一个 `database_path`，
        // 并把 gosh-dl 的 `storage` feature 打开。
        database_path: None,
        http: HttpConfig {
            connect_timeout: config.clamped_connect_timeout(),
            read_timeout: config.clamped_read_timeout(),
            max_retries: config.max_retries,
            ..HttpConfig::default()
        },
        ..EngineConfig::default()
    };

    DownloadEngine::new(engine_config)
        .await
        .map_err(engine_error)
}

#[async_trait]
impl Module for DownloadModule {
    fn descriptor(&self) -> ModuleDescriptor {
        ModuleDescriptor::new("download", "下载队列", env!("CARGO_PKG_VERSION")).description(
            "全局 HTTP 下载队列：提交任务、按 ID 查状态、列全部任务。落盘以实例根目录为根。",
        )
    }

    fn register(&self, reg: &mut Registration) -> Result<()> {
        {
            let state = self.state.clone();
            reg.method(
                "download.add",
                "提交一个下载任务（url / instance_id / path? / filename? / md5? / sha256?）",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { add(&state, &ctx).await }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "download.status",
                "按任务 ID 查状态",
                move |ctx: CallCtx| {
                    let state = state.clone();
                    async move { status(&state, &ctx) }
                },
            );
        }
        {
            let state = self.state.clone();
            reg.method(
                "download.list",
                "全部下载任务（最新提交在前）",
                move |_ctx: CallCtx| {
                    let state = state.clone();
                    async move { list(&state) }
                },
            );
        }
        reg.topic(
            TOPIC_PROGRESS,
            "下载任务进度（排队中 / 进行中，间隔由 progress_interval_ms 决定）",
        );
        reg.topic(TOPIC_STATE, "下载任务状态变化（含终态与 sha1 校验失败）");
        Ok(())
    }

    async fn start(&self, env: ModuleEnv) -> Result<()> {
        let config: DownloadConfig = env.config()?;
        let data_dir = resolve_data_dir(env.app.config.modules.section("instance"));
        let engine = build_engine(&config, &data_dir).await?;

        tracing::info!(
            data_dir = %data_dir.display(),
            max_concurrent = config.clamped_max_concurrent(),
            connections = config.clamped_connections(),
            limit = ?config.effective_speed_limit(),
            progress_interval_ms = config.clamped_progress_interval(),
            "下载队列已就绪"
        );

        // 推送循环跟着模块的取消令牌走：模块停 → 循环停。
        let cancel = CancellationToken::new();
        let join = tokio::spawn(run_publish_loop(
            self.state.clone(),
            engine.clone(),
            env.app.clone(),
            config.clamped_progress_interval(),
            cancel.clone(),
        ));

        // 启动期只有这一个写入者，`set` 不会失败。
        let _ = self.state.ready.set(Ready {
            engine,
            data_dir,
            publish: Mutex::new(Some(PublishLoop { cancel, join })),
        });
        // 把句柄放进这次运行的跨模块槽里：`instance` / `runtime` 的工作流步骤
        // 走这条复用队列（见 [`queue_of`]）。
        //
        // 注意**必须在 `ready` 设好之后**才放行 —— `queue_of` 只保证拿到的
        // 是这次运行的队列，队列本身可用与否由 `Queue::submit` 里的 `ready()`
        // 兜底（拿不到会回 `download_engine_unavailable`）。
        let _ = env.app.services.insert(Arc::new(Queue(self.state.clone())));
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        let Some(ready) = self.state.ready.get() else {
            return Ok(());
        };
        // 先停推送循环，再关引擎：反过来的话（先 shutdown）循环还会扫到
        // 一堆被取消的任务，白发几条没意义的终态。
        let publish = ready
            .publish
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take();
        if let Some(PublishLoop { cancel, join }) = publish {
            cancel.cancel();
            if let Err(e) = join.await
                && e.is_panic()
            {
                tracing::error!(error = %e, "下载推送循环 panic");
            }
        }
        tracing::info!("正在关闭下载队列（进行中的任务会被中断）");
        ready.engine.shutdown().await.map_err(engine_error)
    }
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use crate::module::registry::ModuleRegistry;
    use crate::state::AppState;
    use tokio_util::sync::CancellationToken;

    // ── URL → 文件名 ──────────────────────────────────────────────────────

    #[test]
    fn url_basename_takes_the_last_segment() {
        assert_eq!(
            url_basename("https://example.com/a/b/server.jar").as_deref(),
            Some("server.jar")
        );
        assert_eq!(
            url_basename("http://example.com:8080/x.zip").as_deref(),
            Some("x.zip")
        );
        // 查询串与锚点不算文件名的一部分
        assert_eq!(
            url_basename("https://example.com/dl/pack.zip?token=abc#frag").as_deref(),
            Some("pack.zip")
        );
    }

    #[test]
    fn url_basename_is_none_when_there_is_no_name() {
        // 这三种都取不到名字 —— 必须报错，不能让 gosh-dl 落成叫 `download` 的无扩展名文件
        assert_eq!(url_basename("https://example.com"), None);
        assert_eq!(url_basename("https://example.com/"), None);
        assert_eq!(url_basename("https://example.com/dir/?a=1"), None);
        assert_eq!(url_basename("不是 URL"), None);
    }

    #[test]
    fn url_basename_does_not_percent_decode() {
        // 刻意的取舍：不解码就不会解出一个 `/` 或 `..` 来
        assert_eq!(
            url_basename("https://example.com/%E4%B8%AD%E6%96%87.jar").as_deref(),
            Some("%E4%B8%AD%E6%96%87.jar")
        );
    }

    #[test]
    fn check_url_rejects_non_http_schemes() {
        assert!(check_url("https://example.com/a.jar").is_ok());
        assert!(check_url("HTTP://example.com/a.jar").is_ok());
        for bad in [
            "",
            "ftp://example.com/a.jar",
            "file:///etc/passwd",
            "example.com/a.jar",
        ] {
            assert!(check_url(bad).is_err(), "`{bad}` 应该被拒绝");
        }
    }

    // ── 文件名 ────────────────────────────────────────────────────────────

    #[test]
    fn filename_must_be_a_single_component() {
        assert_eq!(validate_filename(" server.jar ").unwrap(), "server.jar");
        for bad in ["", "  ", ".", "..", "a/b", "a\\b", "../x", "..\\x"] {
            let err = validate_filename(bad).unwrap_err();
            assert_eq!(err.code, CODE_FILENAME_INVALID, "`{bad}` 应该被拒绝");
        }
    }

    #[test]
    fn filename_length_is_counted_in_bytes() {
        let ok = "中".repeat(FILENAME_MAX_BYTES / 3);
        assert!(validate_filename(&ok).is_ok());
        let too_long = format!("{ok}中");
        assert!(validate_filename(&too_long).is_err());
    }

    // ── 校验值 ────────────────────────────────────────────────────────────

    #[test]
    fn checksum_accepts_one_well_formed_value() {
        let md5 = parse_checksum(Some("ABCDEF0123456789ABCDEF0123456789".into()), None, None)
            .unwrap()
            .engine
            .expect("应当解析出 md5");
        assert_eq!(md5.algorithm, gosh_dl::protocol::ChecksumAlgorithm::Md5);
        // 值统一成小写（gosh-dl 的 `ExpectedChecksum::md5` 就是这么做的）
        assert_eq!(md5.value, "abcdef0123456789abcdef0123456789");

        let sha = parse_checksum(None, Some("a".repeat(64)), None)
            .unwrap()
            .engine
            .expect("应当解析出 sha256");
        assert_eq!(sha.algorithm, gosh_dl::protocol::ChecksumAlgorithm::Sha256);

        // sha1 不走引擎，记在我们自己这边
        let sha1 = parse_checksum(None, None, Some("B".repeat(40))).unwrap();
        assert!(sha1.engine.is_none(), "sha1 不该交给 gosh-dl");
        assert_eq!(sha1.sha1.as_deref(), Some("b".repeat(40).as_str()));

        // 空白串 = 没给
        let none = parse_checksum(Some("  ".into()), None, None).unwrap();
        assert!(none.engine.is_none() && none.sha1.is_none());
    }

    #[test]
    fn checksum_rejects_more_than_one_at_once() {
        // 三种组合都要拒：只校一个值才能让失败原因唯一
        for (md5, sha256, sha1) in [
            (Some("a".repeat(32)), Some("b".repeat(64)), None),
            (Some("a".repeat(32)), None, Some("c".repeat(40))),
            (None, Some("b".repeat(64)), Some("c".repeat(40))),
            (
                Some("a".repeat(32)),
                Some("b".repeat(64)),
                Some("c".repeat(40)),
            ),
        ] {
            let err = parse_checksum(md5, sha256, sha1).unwrap_err();
            assert_eq!(err.code, CODE_CHECKSUM_INVALID, "{err}");
        }
    }

    #[test]
    fn checksum_rejects_wrong_length_or_charset() {
        for bad in ["abc", &"a".repeat(31), &"a".repeat(33)] {
            let err = parse_checksum(Some(bad.to_string()), None, None).unwrap_err();
            assert_eq!(err.code, CODE_CHECKSUM_INVALID, "`{bad}` 应该被拒绝");
        }
        let err = parse_checksum(None, Some("z".repeat(64)), None).unwrap_err();
        assert_eq!(err.code, CODE_CHECKSUM_INVALID, "非十六进制字符应该被拒绝");

        // sha1 是 40 位，别拿 64 位当 sha1 收
        for bad in ["abc", &"a".repeat(39), &"a".repeat(64)] {
            let err = parse_checksum(None, None, Some(bad.to_string())).unwrap_err();
            assert_eq!(err.code, CODE_CHECKSUM_INVALID, "`{bad}` 应该被拒绝");
        }
    }

    // ── sha1：我们自己的那一路 ─────────────────────────────────────────────

    #[test]
    fn sha1_of_file_matches_the_known_digest_of_its_bytes() {
        let temp = TempData::new("sha1");

        // "abc" 的 sha1 是个到处都有的固定向量，用它钉住「我们算的确实是 sha1」
        let file = temp.0.join("abc.txt");
        std::fs::write(&file, b"abc").unwrap();
        assert_eq!(
            sha1_of_file(&file).unwrap(),
            "a9993e364706816aba3e25717850c26c9cd0d89d"
        );

        // 再拿一个比 64 KiB 缓冲区大的文件走一遍，确认分块读取不会算漏
        let big = temp.0.join("big.bin");
        let bytes: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
        std::fs::write(&big, &bytes).unwrap();
        assert_eq!(sha1_of_file(&big).unwrap(), sha1_hex_of(&bytes));
    }

    /// 参考实现：一次性喂字节，用来对照流式那版有没有算漏。
    fn sha1_hex_of(bytes: &[u8]) -> String {
        let mut hasher = Sha1::new();
        hasher.update(bytes);
        hasher
            .finalize()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }

    #[test]
    fn sha1_of_file_reports_a_missing_file() {
        let temp = TempData::new("sha1-missing");
        assert!(sha1_of_file(&temp.0.join("nope.bin")).is_err());
    }

    // ── 状态覆盖：verifying 与校验失败 ─────────────────────────────────────

    /// 拿一个「已完成」的引擎状态，用来喂 `effective_state` / `render_task`。
    fn completed_status() -> DownloadStatus {
        serde_json::from_value(json!({
            "id": "00000000-0000-0000-0000-000000000001",
            "kind": "http",
            "state": { "state": "completed" },
            "priority": "normal",
            "progress": {
                "total_size": 10,
                "completed_size": 10,
                "download_speed": 0,
                "upload_speed": 0,
                "connections": 0,
                "seeders": 0,
                "peers": 0
            },
            "metadata": {
                "name": "server.jar",
                "url": "https://example.com/server.jar",
                "save_dir": "/tmp",
                "filename": "server.jar",
                "headers": []
            },
            "created_at": "2026-01-01T00:00:00Z",
            "completed_at": "2026-01-01T00:00:01Z"
        }))
        .expect("应当能构造出一个已完成的状态")
    }

    fn meta_with_verify(verify: Verify) -> TaskMeta {
        TaskMeta {
            owner: Owner::Instance {
                instance_id: "abc123".into(),
                path: String::new(),
            },
            filename: "server.jar".into(),
            abs_target: PathBuf::from("/tmp/server.jar"),
            checksum: None,
            verify: Some(verify),
            created_at_ms: 0,
        }
    }

    #[test]
    fn sha1_pending_shows_as_verifying_then_resolves() {
        let status = completed_status();

        // 还没算 → verifying
        let pending = meta_with_verify(Verify::Pending("a".repeat(40)));
        assert_eq!(effective_state(&status, Some(&pending)), STATE_VERIFYING);
        let running = meta_with_verify(Verify::Running("a".repeat(40)));
        assert_eq!(effective_state(&status, Some(&running)), STATE_VERIFYING);

        // 算完对上了 → completed，且没有 error
        let ok = meta_with_verify(Verify::Done {
            expected: "a".repeat(40),
            result: Ok(()),
        });
        let rendered = render_task(&status, Some(&ok));
        assert_eq!(rendered["state"], json!("completed"));
        assert_eq!(rendered["error"], json!(null));
        assert_eq!(
            rendered["checksum"],
            json!({ "algorithm": "SHA1", "value": "a".repeat(40) })
        );

        // 算完对不上 → error，且原因是 checksum_mismatch
        let bad = meta_with_verify(Verify::Done {
            expected: "a".repeat(40),
            result: Err("sha1 不匹配".into()),
        });
        let rendered = render_task(&status, Some(&bad));
        assert_eq!(rendered["state"], json!("error"));
        assert_eq!(rendered["error"]["kind"], json!(KIND_CHECKSUM_MISMATCH));
        assert_eq!(rendered["error"]["retryable"], json!(false));
    }

    #[test]
    fn sha1_pending_does_not_mask_a_still_running_download() {
        // 引擎还在下的时候，不能因为我们「欠一次校验」就把状态说成 verifying
        let mut status = completed_status();
        status.state = DownloadState::Downloading;
        let pending = meta_with_verify(Verify::Pending("a".repeat(40)));
        assert_eq!(effective_state(&status, Some(&pending)), "downloading");
    }

    // ── 配置 ──────────────────────────────────────────────────────────────

    #[test]
    fn config_is_clamped_to_sane_values() {
        let config = DownloadConfig {
            max_concurrent: 0,
            connections_per_download: 0,
            connect_timeout_secs: 0,
            read_timeout_secs: 0,
            ..DownloadConfig::default()
        };
        assert_eq!(config.clamped_max_concurrent(), 1);
        assert_eq!(config.clamped_connections(), 1);
        assert_eq!(config.clamped_connect_timeout(), 1);
        assert_eq!(config.clamped_read_timeout(), 1);

        let config = DownloadConfig {
            max_concurrent: 9_999,
            connections_per_download: 9_999,
            ..DownloadConfig::default()
        };
        assert_eq!(config.clamped_max_concurrent(), 64);
        assert_eq!(config.clamped_connections(), 64);
    }

    #[test]
    fn zero_speed_limit_means_unlimited() {
        assert_eq!(DownloadConfig::default().effective_speed_limit(), None);
        let config = DownloadConfig {
            max_download_speed: 1024,
            ..DownloadConfig::default()
        };
        assert_eq!(config.effective_speed_limit(), Some(1024));
    }

    #[test]
    fn user_agent_defaults_to_our_own() {
        let ua = DownloadConfig::default().effective_user_agent();
        assert!(ua.starts_with("EdgeCube-daemon/"), "{ua}");
        let config = DownloadConfig {
            user_agent: "  custom/1.0 ".into(),
            ..DownloadConfig::default()
        };
        assert_eq!(config.effective_user_agent(), "custom/1.0");
    }

    /// 模板里那一节就是用户第一次跑会拿到的东西。
    ///
    /// `--check` 不过模块私有配置（那要等 `start()`），所以这一节的内容没人在
    /// 别处验过 —— 字段名写错、类型写错，都得在这里炸，而不是等用户启动时才看到
    /// 「配置解析失败」。`deny_unknown_fields` 让多写一个字段也会在这里暴露。
    #[test]
    fn the_default_template_section_parses() {
        let config: Config = toml::from_str(&Config::template()).expect("模板必须能解析");
        let section = config
            .modules
            .section("download")
            .expect("模板里应当有下载队列那一节");

        let parsed = DownloadConfig::deserialize(section.clone())
            .expect("模板里的下载队列配置必须能反序列化");
        let default = DownloadConfig::default();
        assert_eq!(parsed.max_concurrent, default.max_concurrent);
        assert_eq!(
            parsed.connections_per_download,
            default.connections_per_download
        );
        assert_eq!(parsed.max_retries, default.max_retries);
        assert!(parsed.user_agent.is_empty(), "模板里应当是留空 = 用内置 UA");
    }

    // ── 模块注册 ──────────────────────────────────────────────────────────

    #[test]
    fn module_registers_exactly_three_methods() {
        let module = DownloadModule::new();
        let mut reg = Registration::new("download");
        module.register(&mut reg).unwrap();

        let names: Vec<String> = reg.methods.iter().map(|m| m.name.clone()).collect();
        assert_eq!(
            names,
            vec!["download.add", "download.status", "download.list"],
            "本轮只有这三个方法，多出来的都是越界"
        );
        // 事件主题：进度 + 状态变化（前端靠第一条刷进度条、第二条收终态）
        let topics: Vec<&str> = reg.topics.iter().map(|t| t.topic.as_str()).collect();
        assert_eq!(topics, vec![TOPIC_PROGRESS, TOPIC_STATE]);
    }

    // ── 端到端：真的下一遍 ────────────────────────────────────────────────

    /// 一台只服务一个文件的极简 HTTP 服务，返回它的 base URL。
    ///
    /// 手搓而不是引测试框架：这里要验的是「任务真的落到了实例目录里」，
    /// 一个固定响应体就够了。
    async fn serve_file(body: &'static [u8]) -> String {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("应当能监听回环端口");
        let addr = listener.local_addr().unwrap();

        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let mut scratch = [0u8; 2048];
                    let _ = socket.read(&mut scratch).await;
                    let head = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n\
                         Content-Length: {}\r\nAccept-Ranges: none\r\nConnection: close\r\n\r\n",
                        body.len()
                    );
                    let _ = socket.write_all(head.as_bytes()).await;
                    let _ = socket.write_all(body).await;
                    let _ = socket.flush().await;
                });
            }
        });

        format!("http://{addr}/server.jar")
    }

    fn test_app() -> AppState {
        let config = Config::default();
        let registry = Arc::new(ModuleRegistry::build(vec![], &config).unwrap());
        AppState::new(config, None, registry, CancellationToken::new())
    }

    fn call_ctx(app: AppState, params: Value) -> CallCtx {
        CallCtx {
            app,
            module: "download".into(),
            method: "download.add".into(),
            params,
            conn_id: 1,
            peer: "127.0.0.1:12345".into(),
            is_local: true,
        }
    }

    /// 建一个「数据根 + 一个实例目录」的临时环境，析构时清盘。
    struct TempData(PathBuf);

    impl TempData {
        fn new(tag: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "edgecube-download-{tag}-{}-{}",
                std::process::id(),
                now_ms()
            ));
            std::fs::create_dir_all(&root).expect("应当能建临时目录");
            Self(root)
        }

        /// 只建目录不写元数据：`resolve_instance_root` 对缺元数据的实例会退回
        /// `<data_dir>/instances/<id>`，正是这里要覆盖的路径之一。
        fn add_instance(&self, id: &str) -> PathBuf {
            let dir = self.0.join("instances").join(id);
            std::fs::create_dir_all(&dir).expect("应当能建实例目录");
            dir
        }
    }

    impl Drop for TempData {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    /// 本机是否把回环也塞进了代理。
    ///
    /// `gosh-dl` 的 reqwest 客户端会读环境里的 `HTTP_PROXY`，我们改不了它
    /// （`HttpConfig` 只有 `proxy_url`，没有「显式不走代理」那一档）。所以机器上
    /// 真配了代理、又没在 `NO_PROXY` 里排除回环时，下面两条用例**没法**跑 ——
    /// 这种情况跳过并说明原因，好过让环境问题冒充成功能坏了。
    fn loopback_is_proxied() -> bool {
        let proxy = std::env::var("HTTP_PROXY")
            .or_else(|_| std::env::var("http_proxy"))
            .unwrap_or_default();
        if proxy.trim().is_empty() {
            return false;
        }
        let no_proxy = std::env::var("NO_PROXY")
            .or_else(|_| std::env::var("no_proxy"))
            .unwrap_or_default();
        !no_proxy
            .split(',')
            .any(|item| matches!(item.trim(), "127.0.0.1" | "localhost" | "::1" | "*"))
    }

    #[tokio::test]
    async fn add_downloads_into_the_instance_directory() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        const BODY: &[u8] = b"hello edgecube";
        let temp = TempData::new("e2e");
        let instance_dir = temp.add_instance("abc123");

        let url = serve_file(BODY).await;
        let engine = build_engine(&DownloadConfig::default(), &temp.0)
            .await
            .expect("引擎应当能起来");

        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine,
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        let ctx = call_ctx(
            test_app(),
            json!({ "url": url, "instance_id": "abc123", "path": "mods" }),
        );
        let task = add(&state, &ctx).await.expect("提交应当成功");
        let id = task["task"]["id"].as_str().unwrap().to_string();
        assert_eq!(task["task"]["target"], json!("mods/server.jar"));
        assert_eq!(task["task"]["instance_id"], json!("abc123"));

        // 等它下完（本地回环，几毫秒的事）
        let status = wait_for_finish(&state, &id).await;
        assert_eq!(status["state"], json!("completed"), "{status}");

        let written = instance_dir.join("mods").join("server.jar");
        assert_eq!(std::fs::read(&written).expect("文件应当存在"), BODY);
        assert_eq!(status["total_size"], json!(BODY.len() as u64));
    }

    #[tokio::test]
    async fn a_matching_sha1_lands_on_completed() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        const BODY: &[u8] = b"trustworthy bytes";
        let temp = TempData::new("sha1-ok");
        let instance_dir = temp.add_instance("abc123");
        let url = serve_file(BODY).await;

        let (state, pump_cancel, pump) = start_with_pump(&temp).await;
        let ctx = call_ctx(
            test_app(),
            json!({
                "url": url,
                "instance_id": "abc123",
                "filename": "server.jar",
                "sha1": sha1_hex_of(BODY),
            }),
        );
        let id = add(&state, &ctx).await.unwrap()["task"]["id"]
            .as_str()
            .unwrap()
            .to_string();

        let finished = wait_for_terminal(&state, &id).await;
        assert_eq!(finished["state"], json!("completed"), "{finished}");
        assert_eq!(finished["error"], json!(null));
        // 校验通过的完整路径：文件留着，校验值也回显出来
        assert_eq!(
            finished["checksum"],
            json!({ "algorithm": "SHA1", "value": sha1_hex_of(BODY) })
        );
        assert!(instance_dir.join("server.jar").exists());

        stop_pump(pump_cancel, pump).await;
    }

    #[tokio::test]
    async fn a_wrong_sha1_ends_as_error_and_removes_the_file() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        const BODY: &[u8] = b"tampered bytes";
        let temp = TempData::new("sha1-bad");
        let instance_dir = temp.add_instance("abc123");
        let url = serve_file(BODY).await;

        let (state, pump_cancel, pump) = start_with_pump(&temp).await;
        let ctx = call_ctx(
            test_app(),
            json!({
                "url": url,
                "instance_id": "abc123",
                "filename": "server.jar",
                "sha1": "a".repeat(40),
            }),
        );
        let id = add(&state, &ctx).await.unwrap()["task"]["id"]
            .as_str()
            .unwrap()
            .to_string();

        let finished = wait_for_terminal(&state, &id).await;
        assert_eq!(finished["state"], json!("error"), "{finished}");
        assert_eq!(finished["error"]["kind"], json!(KIND_CHECKSUM_MISMATCH));
        assert_eq!(finished["error"]["retryable"], json!(false));
        // **文件必须被删掉**：留一个内容不对的 server.jar 比没有更糟
        assert!(
            !instance_dir.join("server.jar").exists(),
            "校验失败的文件不该留在实例目录里"
        );

        stop_pump(pump_cancel, pump).await;
    }

    /// 起一个「引擎 + 推送循环」的完整环境（推送循环负责认领 sha1 校验）。
    async fn start_with_pump(
        temp: &TempData,
    ) -> (
        Arc<QueueState>,
        CancellationToken,
        tokio::task::JoinHandle<()>,
    ) {
        let engine = build_engine(&DownloadConfig::default(), &temp.0)
            .await
            .expect("引擎应当能起来");
        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: engine.clone(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        // 30ms 一拍，测试里不必等半秒
        let cancel = CancellationToken::new();
        let pump = tokio::spawn(run_publish_loop(
            state.clone(),
            engine,
            test_app(),
            30,
            cancel.clone(),
        ));
        (state, cancel, pump)
    }

    async fn stop_pump(cancel: CancellationToken, pump: tokio::task::JoinHandle<()>) {
        cancel.cancel();
        let _ = pump.await;
    }

    #[tokio::test]
    async fn add_rejects_a_path_that_escapes_the_instance() {
        let temp = TempData::new("escape");
        temp.add_instance("abc123");

        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: build_engine(&DownloadConfig::default(), &temp.0)
                .await
                .unwrap(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        for bad in ["../outside", "a/../../b", "/etc", "..\\outside"] {
            let ctx = call_ctx(
                test_app(),
                json!({ "url": "https://example.com/a.jar", "instance_id": "abc123", "path": bad }),
            );
            let err = add(&state, &ctx).await.unwrap_err();
            assert_eq!(err.code, CODE_PATH_INVALID, "`{bad}` 应该被拒绝: {err}");
        }
    }

    #[tokio::test]
    async fn add_rejects_unknown_instance_and_bad_input() {
        let temp = TempData::new("bad-input");
        temp.add_instance("abc123");

        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: build_engine(&DownloadConfig::default(), &temp.0)
                .await
                .unwrap(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        // 实例不存在
        let ctx = call_ctx(
            test_app(),
            json!({ "url": "https://example.com/a.jar", "instance_id": "nope" }),
        );
        assert_eq!(
            add(&state, &ctx).await.unwrap_err().code,
            CODE_INSTANCE_NOT_FOUND
        );

        // 非 http(s)
        let ctx = call_ctx(
            test_app(),
            json!({ "url": "ftp://example.com/a.jar", "instance_id": "abc123" }),
        );
        assert_eq!(add(&state, &ctx).await.unwrap_err().code, CODE_URL_INVALID);

        // URL 里没有文件名、又没给 filename
        let ctx = call_ctx(
            test_app(),
            json!({ "url": "https://example.com/", "instance_id": "abc123" }),
        );
        assert_eq!(
            add(&state, &ctx).await.unwrap_err().code,
            CODE_FILENAME_MISSING
        );

        // 缺参数
        let ctx = call_ctx(test_app(), json!({ "url": "https://example.com/a.jar" }));
        assert_eq!(add(&state, &ctx).await.unwrap_err().code, "invalid_params");
    }

    #[tokio::test]
    async fn add_refuses_to_overwrite_an_existing_file() {
        let temp = TempData::new("exists");
        let instance_dir = temp.add_instance("abc123");
        std::fs::create_dir_all(instance_dir.join("mods")).unwrap();
        std::fs::write(instance_dir.join("mods/server.jar"), b"already here").unwrap();

        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: build_engine(&DownloadConfig::default(), &temp.0)
                .await
                .unwrap(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        let ctx = call_ctx(
            test_app(),
            json!({ "url": "https://example.com/server.jar", "instance_id": "abc123", "path": "mods" }),
        );
        assert_eq!(
            add(&state, &ctx).await.unwrap_err().code,
            CODE_TARGET_EXISTS
        );
    }

    #[tokio::test]
    async fn status_and_list_report_what_we_submitted() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempData::new("query");
        temp.add_instance("abc123");

        let url = serve_file(b"payload").await;
        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: build_engine(&DownloadConfig::default(), &temp.0)
                .await
                .unwrap(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });

        let ctx = call_ctx(
            test_app(),
            json!({ "url": url, "instance_id": "abc123", "filename": "renamed.bin" }),
        );
        let id = add(&state, &ctx).await.unwrap()["task"]["id"]
            .as_str()
            .unwrap()
            .to_string();

        // 按完整 UUID 查得到
        let mut query = ctx.clone();
        query.params = json!({ "id": id });
        let task = status(&state, &query).expect("应当查得到");
        assert_eq!(task["task"]["filename"], json!("renamed.bin"));
        assert_eq!(task["task"]["path"], json!(""));

        // 16 位 GID 是**有损**投影，不接受
        let full = Uuid::parse_str(&id).unwrap();
        let gid = hex16(&full);
        query.params = json!({ "id": gid });
        assert_eq!(
            status(&state, &query).unwrap_err().code,
            CODE_TASK_NOT_FOUND
        );

        // 列表里有它
        let listed = list(&state).unwrap();
        assert_eq!(listed["count"], json!(1));
        assert_eq!(listed["tasks"][0]["id"], json!(id));

        wait_for_finish(&state, &id).await;
    }

    /// 把 UUID 的前 8 字节编成 gosh-dl 的 GID 形式，用来验证我们**不**接受它。
    fn hex16(uuid: &Uuid) -> String {
        uuid.as_bytes()[..8]
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }

    /// 等到任务出**终态**（`completed` / `error`）。
    ///
    /// 不能只看引擎状态：带 sha1 的任务在引擎眼里早就 `completed` 了，
    /// 而我们的状态还停在 `verifying` —— 那还没结束。
    async fn wait_for_terminal(state: &Arc<QueueState>, id: &str) -> Value {
        let ready = state.ready().unwrap();
        let parsed = parse_task_id(id).unwrap();
        for _ in 0..400 {
            let status = ready.engine.status(parsed).expect("任务应当还在");
            let rendered = render_task(&status, state.task(id).as_ref());
            let current = rendered["state"].as_str().unwrap_or_default();
            if current == "completed" || current == "error" {
                return rendered;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        panic!("等任务出终态超时");
    }

    /// 轮询到任务不再是「进行中」，返回最后那份任务对象。
    ///
    /// 测试里不去订阅事件（那要一个真实的 WS / 总线订阅者），直接轮询引擎状态更省事；
    /// 事件那条路在 `tests/framework.rs` 里走真协议验。
    async fn wait_for_finish(state: &Arc<QueueState>, id: &str) -> Value {
        let ready = state.ready().unwrap();
        let parsed = parse_task_id(id).unwrap();
        for _ in 0..200 {
            let status = ready.engine.status(parsed).expect("任务应当还在");
            let rendered = render_task(&status, state.task(id).as_ref());
            if !status.state.is_active() && !matches!(status.state, DownloadState::Queued) {
                return rendered;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        panic!("等下载完成超时");
    }

    /// 失败过的任务不该挡住「重试同一个文件」。
    ///
    /// 这是从前端反推出来的：下载页的「重试」就是拿同一个实例、同一个文件名
    /// 再提交一次。失败的任务会一直留在记账里（列表还要显示它），
    /// 如果拿它当「已存在的任务」，用户就被自己的历史顶回去了。
    #[tokio::test]
    async fn a_failed_task_does_not_block_retrying_the_same_file() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        const BODY: &[u8] = b"first attempt";
        let temp = TempData::new("retry");
        temp.add_instance("abc123");
        let url = serve_file(BODY).await;

        let (state, pump_cancel, pump) = start_with_pump(&temp).await;
        let params = |checksum: String| {
            json!({
                "url": url,
                "instance_id": "abc123",
                "filename": "server.jar",
                "sha1": checksum,
            })
        };

        // 第一次：故意给错的 sha1 → 变成 error，文件被删掉
        let ctx = call_ctx(test_app(), params("a".repeat(40)));
        let first = add(&state, &ctx).await.expect("第一次提交应当成功");
        let first_id = first["task"]["id"].as_str().unwrap().to_string();
        let failed = wait_for_terminal(&state, &first_id).await;
        assert_eq!(failed["state"], json!("error"), "{failed}");

        // 第二次：同一个文件、正确的 sha1 —— 不该被上一次的任务挡住
        let ctx = call_ctx(test_app(), params(sha1_hex_of(BODY)));
        let second = add(&state, &ctx).await.expect("重试应当被放行");
        let second_id = second["task"]["id"].as_str().unwrap().to_string();
        assert_ne!(second_id, first_id, "重试应当是一个新任务");

        let finished = wait_for_terminal(&state, &second_id).await;
        assert_eq!(finished["state"], json!("completed"), "{finished}");

        stop_pump(pump_cancel, pump).await;
    }

    // ── 进程内入口（别的模块复用队列走这条）────────────────────────────────

    /// 起一个「引擎 + 发布循环 + 队列句柄」的测试环境。
    ///
    /// 与 [`start_with_pump`] 的区别：**发布循环与等待方共用同一个 `AppState`** ——
    /// `wait` 是靠那个总线上的事件被叫醒的，两边各拿一个 app 的话事件发不到。
    async fn start_internal(
        temp: &TempData,
    ) -> (
        Queue,
        Arc<QueueState>,
        AppState,
        CancellationToken,
        tokio::task::JoinHandle<()>,
    ) {
        let engine = build_engine(&DownloadConfig::default(), &temp.0)
            .await
            .expect("引擎应当能起来");
        let state = Arc::new(QueueState::default());
        let _ = state.ready.set(Ready {
            engine: engine.clone(),
            data_dir: temp.0.clone(),
            publish: Mutex::new(None),
        });
        let app = test_app();
        let cancel = CancellationToken::new();
        let pump = tokio::spawn(run_publish_loop(
            state.clone(),
            engine,
            app.clone(),
            30,
            cancel.clone(),
        ));
        (Queue(state.clone()), state, app, cancel, pump)
    }

    #[tokio::test]
    async fn internal_queue_downloads_into_the_caller_given_directory() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        const BODY: &[u8] = b"this stands in for a jdk archive";
        let temp = TempData::new("internal");
        let url = serve_file(BODY).await;
        let (queue, state, app, cancel, pump) = start_internal(&temp).await;

        // 调用方（runtime 模块）给的是**自己算好的绝对路径**
        let staging = temp
            .0
            .join("runtimes")
            .join(".staging")
            .join("zulu-jdk-21-linux-x64");
        let id = queue
            .submit(InternalRequest {
                dir: staging.clone(),
                filename: "zulu21.tar.gz".into(),
                url,
                checksum: None,
                owner: Owner::Runtime {
                    runtime_id: "zulu-jdk-21-linux-x64".into(),
                },
            })
            .await
            .expect("提交应当成功");

        match queue.wait(&app, id).await {
            DownloadOutcome::Completed { path } => {
                assert_eq!(path, staging.join("zulu21.tar.gz"));
                assert_eq!(std::fs::read(&path).unwrap(), BODY);
            }
            other => panic!("应当下完，实际 {other:?}"),
        }

        // 任务对象要说清「这是给哪个环境下的」，同时不能假装成实例任务
        let status = state.ready().unwrap().engine.status(id).unwrap();
        let rendered = render_task(&status, state.task(&id.as_uuid().to_string()).as_ref());
        assert_eq!(rendered["runtime_id"], json!("zulu-jdk-21-linux-x64"));
        assert_eq!(rendered["instance_id"], json!(null));
        assert_eq!(
            rendered["target"],
            json!(null),
            "暂存路径对用户没意义，别报"
        );

        stop_pump(cancel, pump).await;
    }

    #[tokio::test]
    async fn internal_queue_reports_a_checksum_mismatch_as_failure() {
        if loopback_is_proxied() {
            eprintln!("跳过：需要 NO_PROXY=127.0.0.1,localhost,::1 才能直连回环");
            return;
        }

        let temp = TempData::new("internal-badsum");
        let url = serve_file(b"not what the checksum says").await;
        let (queue, _state, app, cancel, pump) = start_internal(&temp).await;

        let id = queue
            .submit(InternalRequest {
                dir: temp.0.join("staging"),
                filename: "x.bin".into(),
                url,
                checksum: Some(("sha256", "0".repeat(64))),
                owner: Owner::Runtime {
                    runtime_id: "zulu-jdk-21-linux-x64".into(),
                },
            })
            .await
            .expect("提交应当成功");

        match queue.wait(&app, id).await {
            DownloadOutcome::Failed { message } => {
                assert!(!message.trim().is_empty(), "失败得说清原因");
            }
            other => panic!("校验不过应当算失败，实际 {other:?}"),
        }

        stop_pump(cancel, pump).await;
    }

    #[tokio::test]
    async fn internal_queue_rejects_an_unknown_checksum_algorithm() {
        let temp = TempData::new("internal-algo");
        let (queue, _state, _app, cancel, pump) = start_internal(&temp).await;

        let err = queue
            .submit(InternalRequest {
                dir: temp.0.join("staging"),
                filename: "x.bin".into(),
                url: "https://example.com/x.bin".into(),
                checksum: Some(("sha512", "a".repeat(128))),
                owner: Owner::Runtime {
                    runtime_id: "zulu-jdk-21-linux-x64".into(),
                },
            })
            .await
            .expect_err("不认识的算法应当被拒");
        assert_eq!(err.code, CODE_CHECKSUM_INVALID, "{err:?}");

        // 文件名同样是单段才放行（这条校验两边共用）
        let err = queue
            .submit(InternalRequest {
                dir: temp.0.join("staging"),
                filename: "../escape.bin".into(),
                url: "https://example.com/x.bin".into(),
                checksum: None,
                owner: Owner::Runtime {
                    runtime_id: "zulu-jdk-21-linux-x64".into(),
                },
            })
            .await
            .expect_err("带路径分隔符的文件名应当被拒");
        assert_eq!(err.code, CODE_FILENAME_INVALID, "{err:?}");

        stop_pump(cancel, pump).await;
    }
}
