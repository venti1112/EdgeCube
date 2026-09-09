//! /fs/* 文件管理(沙箱文件系统)。
//!
//! 沙箱根 = 实例 `working_directory`(`files/{id}`);所有 path 均为相对该根的路径,
//! 拒绝绝对路径与 `..` 越界(路径穿越防线)。上传为三段式分片断点续传
//! (upload-init / upload-piece / upload-complete,对齐 MCSManager /upload-new 设计);
//! 压缩/解压为异步任务(202 + jobId,经任务队列查询进度/取消)。
//!
//! 安全要点:
//! - [`resolve`] 组件级校验:任何 `..` / `.` 之外的父引用 / 根 / 盘符前缀直接拒绝;
//! - 对已存在路径(list/download/delete/compress/extract/move 源)额外做
//!   canonicalize 包含性校验,防符号链接跳出沙箱;
//! - 解压 zip 逐条校验目标仍在沙箱内(zip-slip 防护);
//! - 禁止删除/压缩沙箱根,禁止把目录移动进自身内部。

use std::collections::HashMap;
use std::fs;
use std::io::{Seek, SeekFrom, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

use axum::body::Body;
use axum::extract::{Query, State};
use axum::http::{header, StatusCode};
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::server::{AppState, ErrorBody};
use crate::task::model::{TaskFailure, TaskKind};
use crate::task::service::{TaskError_, TaskHandle};

/// 上传会话存活期:超时(含 daemon 重启后残留会话)在下次 init 时清理。
const SESSION_TTL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);
/// 上传会话上限(防止内存被恶意 uploadId 撑爆)。
const MAX_SESSIONS: usize = 128;
/// 单分片体积上限(路由 BodyLimit 对齐,防御大块内存占用)。
pub const MAX_PIECE_BYTES: usize = 128 * 1024 * 1024;
/// 单次文本写入内容上限(内置编辑器保存场景;JSON body 上限对齐)。
pub const MAX_WRITE_BYTES: usize = 16 * 1024 * 1024;

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

/// 目录条目(契约 FileEntry)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub size_bytes: u64,
    pub modified_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub executable: Option<bool>,
}

/// 目录内容(契约 FileListResponse)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileListResponse {
    pub path: String,
    pub entries: Vec<FileEntry>,
}

/// 上传初始化(契约 UploadInitRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadInitRequest {
    pub instance_id: Uuid,
    /// 目标目录(相对实例 cwd)。
    pub path: String,
    pub file_name: String,
    pub size_bytes: u64,
    /// 可选;complete 时强校验(64 位 hex)。
    #[serde(default)]
    pub sha256: Option<String>,
    /// 完成自动解压(服务端整合包场景)。
    #[serde(default)]
    pub auto_extract: bool,
}

/// 上传会话(契约 UploadSession)。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadSession {
    pub upload_id: String,
    pub received_bytes: u64,
}

/// 分片进度(契约 UploadProgress)。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadProgress {
    pub upload_id: String,
    pub received_bytes: u64,
    pub total_bytes: u64,
}

/// 上传完成请求(契约 UploadCompleteRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadCompleteRequest {
    pub upload_id: String,
}

/// 上传完成响应(契约 UploadCompleteResponse)。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UploadCompleteResponse {
    pub path: String,
}

/// 单路径请求(契约 FsPathRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsPathRequest {
    pub instance_id: Uuid,
    pub path: String,
}

/// 移动/重命名请求(契约 FsMoveRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsMoveRequest {
    pub instance_id: Uuid,
    pub from: String,
    pub to: String,
}

/// 压缩请求(契约 FsCompressRequest)。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsCompressRequest {
    pub instance_id: Uuid,
    /// 待压缩目录/文件。
    pub path: String,
    /// 归档文件名(单段);缺省取源名 + ".zip"。
    #[serde(default)]
    pub dest_name: Option<String>,
}

/// 文本写入请求(契约 FsWriteRequest):内置编辑器保存场景,UTF-8 内容整体覆盖写入。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsWriteRequest {
    pub instance_id: Uuid,
    /// 目标文件路径(相对实例 cwd),父目录须已存在。
    pub path: String,
    /// UTF-8 文本内容(大小上限 [`MAX_WRITE_BYTES`],由路由 BodyLimit 与 handler 双重校验)。
    pub content: String,
}

/// 异步任务受理(契约 JobAccepted)。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobAccepted {
    pub job_id: Uuid,
}

// ────────────────────────── 管理错误 ──────────────────────────

/// 文件管理操作错误(handler 层映射 HTTP 状态码)。
#[derive(Debug)]
pub(crate) enum FsError {
    InstanceNotFound(Uuid),
    NotFound(String),
    Invalid(String),
    AlreadyExists(String),
    Conflict(String),
    Io(std::io::Error),
}

impl std::fmt::Display for FsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FsError::InstanceNotFound(id) => write!(f, "instance {id} not found"),
            FsError::NotFound(msg) => f.write_str(msg),
            FsError::Invalid(msg) => f.write_str(msg),
            FsError::AlreadyExists(msg) => f.write_str(msg),
            FsError::Conflict(msg) => f.write_str(msg),
            FsError::Io(e) => write!(f, "io error: {e}"),
        }
    }
}

impl From<std::io::Error> for FsError {
    fn from(e: std::io::Error) -> Self {
        FsError::Io(e)
    }
}

fn map_fs_error(e: FsError) -> (StatusCode, Json<ErrorBody>) {
    match e {
        FsError::InstanceNotFound(id) => err(
            StatusCode::NOT_FOUND,
            "not_found",
            format!("instance {id} not found"),
        ),
        FsError::NotFound(msg) => err(StatusCode::NOT_FOUND, "not_found", msg),
        FsError::Invalid(msg) => err(StatusCode::BAD_REQUEST, "invalid_path", msg),
        FsError::AlreadyExists(msg) => err(StatusCode::CONFLICT, "already_exists", msg),
        FsError::Conflict(msg) => err(StatusCode::CONFLICT, "conflict", msg),
        FsError::Io(e) => {
            tracing::error!(error = %e, "fs io error");
            err(
                StatusCode::INTERNAL_SERVER_ERROR,
                "internal_error",
                "internal server error",
            )
        }
    }
}

fn err(status: StatusCode, code: &'static str, message: impl Into<String>) -> (StatusCode, Json<ErrorBody>) {
    (status, Json(ErrorBody { code, message: message.into() }))
}

/// `?` 糖:handler 内 FsError 直接转换为 HTTP 错误响应。
impl From<FsError> for (StatusCode, Json<ErrorBody>) {
    fn from(e: FsError) -> Self {
        map_fs_error(e)
    }
}

/// 任务服务错误 → HTTP(409 task_conflict 等,对齐 server::map_task_error)。
fn map_task_error(e: TaskError_) -> (StatusCode, Json<ErrorBody>) {
    match e {
        TaskError_::NotFound(id) => err(
            StatusCode::NOT_FOUND,
            "task_not_found",
            format!("task {id} not found"),
        ),
        TaskError_::Conflict(..) => err(
            StatusCode::CONFLICT,
            "task_conflict",
            "task is already finished or still running the same kind",
        ),
    }
}

// ────────────────────────── 上传会话管理 ──────────────────────────

/// 上传会话(内存态;daemon 重启后残留会话随文件长度自然续传)。
#[derive(Debug)]
struct Session {
    target_abs: PathBuf,
    relative: String,
    size_bytes: u64,
    sha256: Option<String>,
    auto_extract: bool,
    created_at: Instant,
}

#[derive(Debug, Default)]
struct FsInner {
    sessions: HashMap<String, Session>,
}

impl FsInner {
    /// 清理超时/超量会话(在所有写入会话表的人口调用)。
    fn prune(&mut self) {
        let now = Instant::now();
        self.sessions.retain(|_, s| now.duration_since(s.created_at) < SESSION_TTL);
        while self.sessions.len() > MAX_SESSIONS {
            // 逐出最早创建的会话(接近 TTL 的优先淘汰)
            let oldest = self
                .sessions
                .iter()
                .min_by_key(|(_, s)| s.created_at)
                .map(|(k, _)| k.clone());
            if let Some(k) = oldest {
                self.sessions.remove(&k);
            } else {
                break;
            }
        }
    }
}

/// 文件管理服务:上传会话注册表(克隆 = 共享引用)。
#[derive(Debug, Clone, Default)]
pub struct FsManager {
    inner: Arc<Mutex<FsInner>>,
}

impl FsManager {
    /// 初始化上传会话:目标文件已部分落盘(中断续传)时以其当前长度作为已接收字节。
    pub async fn init_upload(&self, req: &UploadInitRequest, cwd: &Path) -> Result<UploadSession, FsError> {
        let dir = resolve(cwd, &req.path)?;
        let file_name = validate_file_name(&req.file_name)?;
        let target = dir.join(&file_name);
        let received = match fs::metadata(&target) {
            Ok(meta) if meta.is_file() => meta.len(),
            _ => 0,
        };
        let relative = rel_path(cwd, &target);

        let session = Session {
            target_abs: target,
            relative,
            size_bytes: req.size_bytes,
            sha256: req.sha256.clone(),
            auto_extract: req.auto_extract,
            created_at: Instant::now(),
        };
        let upload_id = Uuid::new_v4().to_string();
        {
            let mut inner = self.inner.lock().await;
            inner.prune();
            inner.sessions.insert(upload_id.clone(), session);
        }
        Ok(UploadSession {
            upload_id,
            received_bytes: received,
        })
    }

    /// 写入一片:按 offset 随机写(允许乱序),返回累计进度。
    pub async fn write_piece(
        &self,
        upload_id: &str,
        offset: u64,
        data: axum::body::Bytes,
    ) -> Result<UploadProgress, FsError> {
        let (target_abs, size_bytes) = {
            let inner = self.inner.lock().await;
            let s = inner
                .sessions
                .get(upload_id)
                .ok_or_else(|| FsError::NotFound(format!("unknown uploadId: {upload_id}")))?;
            (s.target_abs.clone(), s.size_bytes)
        };

        let write_len = data.len() as u64;
        let file = target_abs.clone();
        let bytes = data.to_vec();
        // 磁盘 IO 放入阻塞池,避免占用事件循环
        tokio::task::spawn_blocking(move || {
            let mut f = fs::OpenOptions::new()
                .create(true)
                .write(true)
                .open(&file)?;
            f.seek(SeekFrom::Start(offset))?;
            f.write_all(&bytes)?;
            Ok::<_, std::io::Error>(())
        })
        .await
        .map_err(|e| FsError::Io(std::io::Error::other(format!("piece task panic: {e}"))))?
        .map_err(FsError::Io)?;

        Ok(UploadProgress {
            upload_id: upload_id.to_string(),
            received_bytes: offset + write_len,
            total_bytes: size_bytes,
        })
    }

    /// 完成上传:校验大小与可选 sha256;autoExtract 时原地解压并删除归档。
    pub async fn complete_upload(
        &self,
        upload_id: &str,
    ) -> Result<UploadCompleteResponse, FsError> {
        let session = {
            let mut inner = self.inner.lock().await;
            inner
                .sessions
                .remove(upload_id)
                .ok_or_else(|| FsError::NotFound(format!("unknown uploadId: {upload_id}")))?
        };
        let target = session.target_abs.clone();

        // ── 1. 大小校验(未收完允许续传,不清会话数据) ─────────────
        let len = fs::metadata(&target)
            .map_err(|e| fs_err_io(&target, e))?
            .len();
        if len != session.size_bytes {
            return Err(FsError::Invalid(format!(
                "upload incomplete: expected {} bytes, got {len}",
                session.size_bytes
            )));
        }

        // ── 2. 可选 sha256 强校验 ────────────────────────────────
        if let Some(sha256) = &session.sha256 {
            let expected = sha256.trim().to_lowercase();
            let file = target.clone();
            let actual = tokio::task::spawn_blocking(move || hash_sha256(&file))
                .await
                .map_err(|e| FsError::Io(std::io::Error::other(format!("hash task panic: {e}"))))?
                .map_err(|e| fs_err_io(&target, e))?;
            if actual != expected {
                return Err(FsError::Conflict(format!(
                    "checksum mismatch: expected {expected}, actual {actual}"
                )));
            }
        }

        // ── 3. 自动解压:原地解压后删除归档(整合包场景) ──────────
        if session.auto_extract {
            let dir = target
                .parent()
                .ok_or_else(|| FsError::Invalid("upload target has no parent".into()))?
                .to_path_buf();
            let file = target.clone();
            tokio::task::spawn_blocking(move || extract_and_remove(&file, &dir))
                .await
                .map_err(|e| FsError::Io(std::io::Error::other(format!("extract task panic: {e}"))))?
                .map_err(|e| fs_err_io(&target, e))?;
        }

        Ok(UploadCompleteResponse {
            path: session.relative,
        })
    }
}

/// 带上下文的 io 错误(定位到具体文件)。
fn fs_err_io(path: &Path, e: std::io::Error) -> FsError {
    match e.kind() {
        std::io::ErrorKind::NotFound => {
            FsError::NotFound(format!("{} not found", path.display()))
        }
        _ => FsError::Io(e),
    }
}

// ────────────────────────── 沙箱路径解析 ──────────────────────────

/// 将相对路径解析到沙箱内绝对路径。
///
/// - 空串 / "." / "/" 视为沙箱根;
/// - 绝对路径(含 Windows 盘符前缀)与任何 `..` 段直接拒绝;
/// - 其余组件原样拼接(不触达文件系统,末段允许不存在,供 mkdir/上传目标使用)。
pub(crate) fn resolve(cwd: &Path, rel: &str) -> Result<PathBuf, FsError> {
    let rel = rel.trim();
    if rel.is_empty() || rel == "." || rel == "/" || rel == "\\" {
        return Ok(cwd.to_path_buf());
    }
    let p = Path::new(rel);
    let mut out = PathBuf::new();
    for comp in p.components() {
        match comp {
            Component::Normal(c) => out.push(c),
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(FsError::Invalid(
                    "path must not traverse outside the instance sandbox ('..' is not allowed)".into(),
                ));
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(FsError::Invalid("path must be relative to instance root".into()));
            }
        }
    }
    Ok(cwd.join(out))
}

/// 已存在路径的沙箱包含性校验(canonicalize 解引用符号链接,防链出沙箱)。
pub(crate) fn ensure_within(cwd: &Path, abs: &Path) -> Result<(), FsError> {
    let cwd_canon = fs::canonicalize(cwd).map_err(|e| fs_err_io(cwd, e))?;
    let abs_canon = fs::canonicalize(abs).map_err(|e| fs_err_io(abs, e))?;
    if abs_canon.starts_with(&cwd_canon) {
        Ok(())
    } else {
        Err(FsError::Invalid(
            "path resolves outside the instance sandbox".into(),
        ))
    }
}

/// 绝对路径相对 cwd 的规范化字符串("/" 分隔,供响应 path 字段)。
pub(crate) fn rel_path(cwd: &Path, abs: &Path) -> String {
    abs.strip_prefix(cwd)
        .unwrap_or(abs)
        .to_string_lossy()
        .replace('\\', "/")
}

/// 校验单段文件名(上传目标 / 压缩归档名):非空、非 "." / ".."、
/// 无路径分隔符与控制字符、无 Windows 非法字符(跨平台统一口径)。
fn validate_file_name(name: &str) -> Result<String, FsError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(FsError::Invalid("file name must not be empty".into()));
    }
    if name == "." || name == ".." {
        return Err(FsError::Invalid(format!("invalid file name: {name}")));
    }
    if name.contains(['/', '\\', '\0'])
        || name.chars().any(|c| c.is_control())
        || name.chars().any(|c| matches!(c, '<' | '>' | ':' | '"' | '|' | '?' | '*'))
    {
        return Err(FsError::Invalid(format!(
            "file name must be a single segment without special characters: {name}"
        )));
    }
    Ok(name.to_string())
}

/// 校验格式为 64 位小写/大写 hex(可选 sha256)。
fn validate_sha256(sha: &Option<String>) -> Result<(), FsError> {
    if let Some(s) = sha {
        let s = s.trim();
        if s.len() != 64 || !s.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(FsError::Invalid(
                "sha256 must be 64 hex digits".into(),
            ));
        }
    }
    Ok(())
}

// ────────────────────────── 处理器 ──────────────────────────

/// 取出实例沙箱根(实例不存在 → 404)。
async fn cwd_of(state: &AppState, id: Uuid) -> Result<PathBuf, (StatusCode, Json<ErrorBody>)> {
    let detail = state
        .instances
        .get_detail(id)
        .await
        .ok_or_else(|| map_fs_error(FsError::InstanceNotFound(id)))?;
    Ok(detail.config.working_directory)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ListQuery {
    instance_id: Uuid,
    #[serde(default)]
    path: Option<String>,
}

/// GET /api/v1/fs/list:列出目录(沙箱,以实例 cwd 为根)。
pub async fn list_files(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Query(query): Query<ListQuery>,
) -> Result<Json<FileListResponse>, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, query.instance_id).await?;
    let dir = resolve(&cwd, query.path.as_deref().unwrap_or(""))?;
    ensure_within(&cwd, &dir)?;

    let mut entries = Vec::new();
    if !dir.exists() {
        return Err(map_fs_error(FsError::NotFound(format!(
            "{} not found",
            rel_path(&cwd, &dir)
        ))));
    }
    for entry in fs::read_dir(&dir).map_err(|e| map_fs_error(FsError::from(e)))? {
        let entry = entry.map_err(|e| map_fs_error(FsError::from(e)))?;
        let path = entry.path();
        let meta = entry
            .metadata()
            .map_err(|e| map_fs_error(FsError::from(e)))?;
        let is_dir = meta.is_dir();
        entries.push(FileEntry {
            name: entry.file_name().to_string_lossy().into_owned(),
            path: rel_path(&cwd, &path),
            is_directory: is_dir,
            size_bytes: if is_dir { 0 } else { meta.len() },
            modified_at: sys_to_datetime(meta.modified().unwrap_or(std::time::UNIX_EPOCH)),
            executable: executable_bit(&meta),
        });
    }
    // 目录优先,再按文件名不区分大小写排序
    entries.sort_by(|a, b| {
        b.is_directory
            .cmp(&a.is_directory)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(Json(FileListResponse {
        path: query.path.unwrap_or_default().trim().to_string(),
        entries,
    }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DownloadQuery {
    instance_id: Uuid,
    path: String,
}

/// GET /api/v1/fs/download:下载文件(二进制流)。
pub async fn download_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Query(query): Query<DownloadQuery>,
) -> Result<Response, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, query.instance_id).await?;
    let file = resolve(&cwd, &query.path)?;
    ensure_within(&cwd, &file)?;
    let meta = fs::metadata(&file).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => map_fs_error(FsError::NotFound(format!(
            "{} not found",
            rel_path(&cwd, &file)
        ))),
        _ => map_fs_error(FsError::Io(e)),
    })?;
    if !meta.is_file() {
        return Err(map_fs_error(FsError::Invalid("target is not a file".into())));
    }
    let len = meta.len();
    let name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "download".into());

    let file_for_read = file.clone();
    let data = tokio::task::spawn_blocking(move || fs::read(&file_for_read))
        .await
        .map_err(|e| map_fs_error(FsError::Io(std::io::Error::other(format!("read task panic: {e}")))))?;
    let data = match data {
        Ok(d) => d,
        Err(e) => return Err(map_fs_error(fs_err_io(&file, e))),
    };

    let body = Body::from(data);
    let mut response = Response::new(body);
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, "application/octet-stream".parse().unwrap());
    headers.insert(header::CONTENT_LENGTH, len.to_string().parse().unwrap());
    headers.insert(
        header::CONTENT_DISPOSITION,
        format!("attachment; filename=\"{name}\"")
            .parse()
            .unwrap(),
    );
    Ok(response)
}

/// POST /api/v1/fs/upload-init:分片上传初始化(断点续传从已有文件长度续传)。
pub async fn init_file_upload(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<UploadInitRequest>,
) -> Result<Json<UploadSession>, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    validate_sha256(&req.sha256)?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let session = state
        .fs
        .init_upload(&req, &cwd)
        .await
        .map_err(map_fs_error)?;
    Ok(Json(session))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PieceQuery {
    upload_id: String,
    offset: u64,
}

/// POST /api/v1/fs/upload-piece:写入一片(按 offset 随机写)。
pub async fn upload_file_piece(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Query(query): Query<PieceQuery>,
    body: axum::body::Bytes,
) -> Result<Json<UploadProgress>, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let progress = state
        .fs
        .write_piece(&query.upload_id, query.offset, body)
        .await
        .map_err(map_fs_error)?;
    Ok(Json(progress))
}

/// POST /api/v1/fs/upload-complete:完成上传(大小 + 可选 sha256 校验,可选自动解压)。
pub async fn complete_file_upload(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<UploadCompleteRequest>,
) -> Result<Json<UploadCompleteResponse>, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let resp = state
        .fs
        .complete_upload(&req.upload_id)
        .await
        .map_err(map_fs_error)?;
    Ok(Json(resp))
}

/// POST /api/v1/fs/mkdir:创建目录(父目录须已存在)。
pub async fn create_directory(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsPathRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let dir = resolve(&cwd, &req.path)?;
    fs::create_dir(&dir).map_err(|e| match e.kind() {
        std::io::ErrorKind::AlreadyExists => {
            map_fs_error(FsError::AlreadyExists(format!("{} already exists", dir.display())))
        }
        std::io::ErrorKind::NotFound => map_fs_error(FsError::Invalid(format!(
            "parent directory of {} does not exist",
            rel_path(&cwd, &dir)
        ))),
        _ => map_fs_error(FsError::Io(e)),
    })?;
    Ok(StatusCode::CREATED)
}

/// POST /api/v1/fs/move:移动/重命名(目标父目录须已存在)。
pub async fn move_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsMoveRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let from = resolve(&cwd, &req.from)?;
    let to = resolve(&cwd, &req.to)?;

    if from == cwd {
        return Err(map_fs_error(FsError::Invalid(
            "cannot move the instance root".into(),
        )));
    }
    if to == cwd || to == from {
        return Err(map_fs_error(FsError::Invalid(
            "move target must differ from source and the instance root".into(),
        )));
    }
    if to.starts_with(&from) {
        return Err(map_fs_error(FsError::Invalid(
            "cannot move a directory into itself".into(),
        )));
    }
    ensure_within(&cwd, &from)?;
    // 目标父目录须已存在(避免"移动并创建目录"的隐性语义)
    let parent = to.parent().ok_or_else(|| {
        map_fs_error(FsError::Invalid("move target has no parent".into()))
    })?;
    if !parent.exists() {
        return Err(map_fs_error(FsError::Invalid(format!(
            "destination directory {} does not exist",
            rel_path(&cwd, parent)
        ))));
    }
    if to.exists() {
        return Err(map_fs_error(FsError::AlreadyExists(format!(
            "{} already exists",
            rel_path(&cwd, &to)
        ))));
    }

    fs::rename(&from, &to).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => {
            map_fs_error(FsError::NotFound(format!("{} not found", from.display())))
        }
        _ => map_fs_error(FsError::Io(e)),
    })?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/fs/delete:删除文件/目录(目录递归;拒绝删除沙箱根)。
pub async fn delete_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsPathRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let target = resolve(&cwd, &req.path)?;
    if target == cwd {
        return Err(map_fs_error(FsError::Invalid(
            "cannot delete the instance root".into(),
        )));
    }
    ensure_within(&cwd, &target)?;

    let meta = fs::symlink_metadata(&target).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => {
            map_fs_error(FsError::NotFound(format!("{} not found", target.display())))
        }
        _ => map_fs_error(FsError::Io(e)),
    })?;
    let result = if meta.is_dir() {
        fs::remove_dir_all(&target)
    } else {
        fs::remove_file(&target)
    };
    result.map_err(|e| map_fs_error(FsError::Io(e)))?;
    Ok(StatusCode::NO_CONTENT)
}

/// POST /api/v1/fs/write:以 UTF-8 文本整体覆盖写入文件(内置编辑器保存场景)。
///
/// 目标父目录须已存在;已存在的目标(含符号链接)先做沙箱包含性校验再原子替换
/// (同目录临时文件 + rename,避免部分写入;Windows 上 rename 无法覆盖时先移除旧文件)。
pub async fn write_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsWriteRequest>,
) -> Result<StatusCode, (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    if req.content.len() > MAX_WRITE_BYTES {
        return Err(map_fs_error(FsError::Invalid(format!(
            "content exceeds {} bytes limit",
            MAX_WRITE_BYTES
        ))));
    }
    let cwd = cwd_of(&state, req.instance_id).await?;
    let target = resolve(&cwd, &req.path)?;
    if target == cwd {
        return Err(map_fs_error(FsError::Invalid(
            "cannot write the instance root".into(),
        )));
    }
    let parent = target.parent().ok_or_else(|| {
        map_fs_error(FsError::Invalid("write target has no parent".into()))
    })?;
    if !parent.exists() {
        return Err(map_fs_error(FsError::Invalid(format!(
            "parent directory {} does not exist",
            rel_path(&cwd, parent)
        ))));
    }
    // 父目录已存在:canonicalize 防符号链接把写入重定向出沙箱。
    ensure_within(&cwd, parent)?;
    // 目标已存在(含符号链接):解引用后同样必须在沙箱内,且不能是目录。
    if let Ok(meta) = fs::symlink_metadata(&target) {
        ensure_within(&cwd, &target)?;
        if meta.is_dir() {
            return Err(map_fs_error(FsError::Invalid(format!(
                "{} is a directory, cannot write content to it",
                rel_path(&cwd, &target)
            ))));
        }
    }

    let file_name = target
        .file_name()
        .ok_or_else(|| map_fs_error(FsError::Invalid("write target has no file name".into())))?
        .to_string_lossy()
        .into_owned();
    let tmp = parent.join(format!(".{file_name}.{}.tmp", Uuid::new_v4()));
    let bytes = req.content.into_bytes();
    let target_for_task = target.clone();
    // 磁盘 IO 放入阻塞池:临时文件写入 + 原子替换(失败时清理临时文件)。
    tokio::task::spawn_blocking(move || write_text_atomic(&tmp, &target_for_task, &bytes))
        .await
        .map_err(|e| map_fs_error(FsError::Io(std::io::Error::other(format!("write task panic: {e}")))))?
        .map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => {
                map_fs_error(FsError::NotFound(format!("{} not found", target.display())))
            }
            _ => map_fs_error(FsError::Io(e)),
        })?;
    Ok(StatusCode::NO_CONTENT)
}

/// 原子写入:写入同目录临时文件后 rename 覆盖目标(Windows 上 rename 无法覆盖时先移除旧文件)。
fn write_text_atomic(tmp: &Path, target: &Path, bytes: &[u8]) -> std::io::Result<()> {
    fs::write(tmp, bytes)?;
    match fs::rename(tmp, target) {
        Ok(()) => Ok(()),
        // 目标为普通文件且 rename 失败(Windows 语义):先移除旧文件再重命名,
        // 失败时清理临时文件。目录/其它非常规目标不尝试覆盖,直接返回错误。
        Err(_) if target.is_file() => {
            fs::remove_file(target)?;
            fs::rename(tmp, target).map_err(|e| {
                let _ = fs::remove_file(tmp);
                e
            })
        }
        Err(e) => {
            let _ = fs::remove_file(tmp);
            Err(e)
        }
    }
}

/// POST /api/v1/fs/compress:异步压缩为 zip(归档置于源同目录,202 + jobId)。
pub async fn compress_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsCompressRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let source = resolve(&cwd, &req.path)?;
    if source == cwd {
        return Err(map_fs_error(FsError::Invalid(
            "cannot compress the instance root".into(),
        )));
    }
    ensure_within(&cwd, &source)?;
    if !source.exists() {
        return Err(map_fs_error(FsError::NotFound(format!(
            "{} not found",
            rel_path(&cwd, &source)
        ))));
    }

    let default = format!(
        "{}.zip",
        source
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "archive".into())
    );
    let dest_name = validate_file_name(req.dest_name.as_deref().unwrap_or(&default))?;
    let target = source
        .parent()
        .ok_or_else(|| map_fs_error(FsError::Invalid("source has no parent".into())))?
        .join(dest_name);
    if target.exists() {
        return Err(map_fs_error(FsError::AlreadyExists(format!(
            "{} already exists",
            rel_path(&cwd, &target)
        ))));
    }

    let task = state
        .tasks
        .submit(TaskKind::Compress, Some(req.instance_id), move |handle| {
            compress_runner(handle, source, target)
        })
        .await
        .map_err(map_task_error)?;
    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

/// POST /api/v1/fs/extract:异步解压归档(zip/tar/tar.gz,解到源同目录,202 + jobId)。
pub async fn extract_file(
    State(state): State<AppState>,
    auth: axum::http::HeaderMap,
    Json(req): Json<FsPathRequest>,
) -> Result<(StatusCode, Json<JobAccepted>), (StatusCode, Json<ErrorBody>)> {
    crate::server::require_auth(&state, &auth).await?;
    let cwd = cwd_of(&state, req.instance_id).await?;
    let archive = resolve(&cwd, &req.path)?;
    ensure_within(&cwd, &archive)?;
    let meta = fs::metadata(&archive).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => {
            map_fs_error(FsError::NotFound(format!("{} not found", archive.display())))
        }
        _ => map_fs_error(FsError::Io(e)),
    })?;
    if !meta.is_file() {
        return Err(map_fs_error(FsError::Invalid("target is not an archive file".into())));
    }
    let dest = archive
        .parent()
        .ok_or_else(|| map_fs_error(FsError::Invalid("archive has no parent".into())))?
        .to_path_buf();

    let task = state
        .tasks
        .submit(TaskKind::Extract, Some(req.instance_id), move |handle| {
            extract_runner(handle, archive, dest)
        })
        .await
        .map_err(map_task_error)?;
    Ok((StatusCode::ACCEPTED, Json(JobAccepted { job_id: task.id })))
}

// ────────────────────────── 异步任务执行体 ──────────────────────────

/// 压缩执行体:spawn_blocking 走 zip 写入(压缩本身不可中断,开始前/收尾校验取消标志)。
async fn compress_runner(
    handle: TaskHandle,
    source: PathBuf,
    target: PathBuf,
) -> Result<(), TaskFailure> {
    if handle.is_cancelled() {
        return Err(TaskFailure::new("cancelled", "cancelled"));
    }
    handle.set_phase("compressing").await;
    let src = source.clone();
    let dst = target.clone();
    let result = tokio::task::spawn_blocking(move || create_zip(&src, &dst))
        .await
        .map_err(|e| TaskFailure::new("compress_failed", format!("compress task panic: {e}")))?;
    if let Err(e) = result {
        // 失败时清理半成品归档
        let _ = fs::remove_file(&target);
        return Err(TaskFailure::new(
            "compress_failed",
            format!("compress {}: {e}", source.display()),
        ));
    }
    if handle.is_cancelled() {
        let _ = fs::remove_file(&target);
        return Err(TaskFailure::new("cancelled", "cancelled"));
    }
    tracing::info!(source = %source.display(), target = %target.display(), "archive created");
    Ok(())
}

/// 解压执行体:spawn_blocking 走 zip/tar/tar.gz 解压(zip-slip 防护见 [`extract_zip`])。
async fn extract_runner(
    handle: TaskHandle,
    archive: PathBuf,
    dest: PathBuf,
) -> Result<(), TaskFailure> {
    if handle.is_cancelled() {
        return Err(TaskFailure::new("cancelled", "cancelled"));
    }
    handle.set_phase("extracting").await;
    let src = archive.clone();
    let dir = dest.clone();
    let result = tokio::task::spawn_blocking(move || extract_archive(&src, &dir))
        .await
        .map_err(|e| TaskFailure::new("extract_failed", format!("extract task panic: {e}")))?;
    if let Err(e) = result {
        return Err(TaskFailure::new(
            "extract_failed",
            format!("extract {}: {e}", archive.display()),
        ));
    }
    tracing::info!(archive = %archive.display(), dest = %dest.display(), "archive extracted");
    Ok(())
}

// ────────────────────────── 归档工具 ──────────────────────────

/// 将文件/目录递归压缩为 zip(目录结构以源自身为根)。
fn create_zip(source: &Path, target: &Path) -> std::io::Result<()> {
    let file = fs::File::create(target)?;
    let mut zip = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    add_to_zip(&mut zip, source, source, &options)?;
    zip.finish()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))
        .map(|_| ())
}

fn add_to_zip(
    zip: &mut zip::ZipWriter<fs::File>,
    base: &Path,
    path: &Path,
    options: &zip::write::SimpleFileOptions,
) -> std::io::Result<()> {
    let name = path
        .strip_prefix(base)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let meta = fs::metadata(path)?;
    if meta.is_dir() {
        if !name.is_empty() {
            zip.add_directory(name, *options)?;
        }
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            add_to_zip(zip, base, &entry.path(), options)?;
        }
    } else {
        zip.start_file(name, *options)?;
        let mut f = fs::File::open(path)?;
        std::io::copy(&mut f, zip)?;
    }
    Ok(())
}

/// 按扩展名分派解压:zip/jar → tar → gz/tgz(tar.gz)。
pub(crate) fn extract_archive(archive: &Path, dest: &Path) -> std::io::Result<()> {
    let ext = archive
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "zip" | "jar" => extract_zip(archive, dest),
        "tar" => {
            let f = fs::File::open(archive)?;
            let mut tar = tar::Archive::new(f);
            tar.unpack(dest)
        }
        "gz" | "tgz" => {
            let f = fs::File::open(archive)?;
            let gz = flate2::read::GzDecoder::new(f);
            let mut tar = tar::Archive::new(gz);
            tar.unpack(dest)
        }
        _ => Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("unsupported archive type: .{ext}"),
        )),
    }
}

/// 解压 zip:逐条使用 [`zip::ZipFile::enclosed_name`] 校验,拒绝任何越界条目
/// (zip-slip 防护);常规 `tar` 由 crate 默认拦截 `..` / 绝对路径。
fn extract_zip(archive: &Path, dest: &Path) -> std::io::Result<()> {
    let file = fs::File::open(archive)?;
    let mut zip = zip::ZipArchive::new(file)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    for i in 0..zip.len() {
        let mut entry = zip
            .by_index(i)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        let Some(name) = entry.enclosed_name() else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("zip entry {} escapes the target directory", entry.name()),
            ));
        };
        let out = dest.join(name);
        if !out.starts_with(dest) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "zip entry escapes the target directory",
            ));
        }
        if entry.is_dir() {
            fs::create_dir_all(&out)?;
        } else {
            if let Some(parent) = out.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut f = fs::File::create(&out)?;
            std::io::copy(&mut entry, &mut f)?;
        }
    }
    Ok(())
}

/// 解压成功后删除归档(autoExtract 整合包场景:解压即落地,归档不再保留)。
fn extract_and_remove(archive: &Path, dest: &Path) -> std::io::Result<()> {
    extract_archive(archive, dest)?;
    fs::remove_file(archive)
}

// ────────────────────────── 内部工具 ──────────────────────────

/// SystemTime → DateTime<Utc>(文件系统时间转换;非 UNIX 纪元前时间按纪元起点兜底)。
fn sys_to_datetime(t: std::time::SystemTime) -> DateTime<Utc> {
    let secs = t
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    DateTime::<Utc>::from_timestamp(secs, 0).unwrap_or(DateTime::<Utc>::from_timestamp(0, 0).unwrap())
}

/// 平台相关可执行位(仅 unix 有意义;windows 一律 None)。
fn executable_bit(meta: &fs::Metadata) -> Option<bool> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        Some(meta.permissions().mode() & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        let _ = meta;
        None
    }
}

/// 文件 sha256,hex 小写(上传 complete 的强校验)。
fn hash_sha256(path: &Path) -> std::io::Result<String> {
    let bytes = fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    Ok(format!("{:x}", hasher.finalize()))
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp() -> PathBuf {
        std::env::temp_dir().join(format!("edgecube-fs-test-{}", Uuid::new_v4()))
    }

    #[test]
    fn resolve_rejects_traversal_and_absolute() {
        let cwd = Path::new("/srv/files/abc");
        assert_eq!(resolve(cwd, "").unwrap(), cwd);
        assert_eq!(resolve(cwd, ".").unwrap(), cwd);
        assert_eq!(resolve(cwd, "/").unwrap(), cwd);
        assert_eq!(resolve(cwd, "sub/dir").unwrap(), cwd.join("sub/dir"));
        assert!(resolve(cwd, "../escape").is_err());
        assert!(resolve(cwd, "a/../../escape").is_err());
        assert!(resolve(cwd, "/etc/passwd").is_err());
        assert!(resolve(cwd, "C:/windows").is_err());
        assert!(resolve(cwd, "..\\escape").is_err());
    }

    #[test]
    fn validate_file_name_rejects_bad_names() {
        assert_eq!(validate_file_name("server.jar").unwrap(), "server.jar");
        assert_eq!(validate_file_name("  a b.txt ").unwrap(), "a b.txt");
        assert!(validate_file_name("").is_err());
        assert!(validate_file_name("..").is_err());
        assert!(validate_file_name("a/b").is_err());
        assert!(validate_file_name("a\\b").is_err());
        assert!(validate_file_name("a:b").is_err());
        assert!(validate_file_name("a\u{0}b").is_err());
    }

    #[tokio::test]
    async fn upload_flow_with_checksum() {
        use sha2::Digest;
        let dir = tmp();
        fs::create_dir_all(&dir.join("target")).unwrap();
        let man = FsManager::default();
        let payload = b"hello edgecube upload".to_vec();
        let digest: String = format!("{:x}", Sha256::digest(&payload));

        let init = man
            .init_upload(
                &UploadInitRequest {
                    instance_id: Uuid::new_v4(),
                    path: "target".into(),
                    file_name: "data.bin".into(),
                    size_bytes: payload.len() as u64,
                    sha256: Some(digest),
                    auto_extract: false,
                },
                &dir,
            )
            .await
            .unwrap();
        assert_eq!(init.received_bytes, 0);

        let mid = payload.len() as u64 / 2;
        let p1 = man
            .write_piece(
                &init.upload_id,
                0,
                axum::body::Bytes::from(payload[..mid as usize].to_vec()),
            )
            .await
            .unwrap();
        assert_eq!(p1.received_bytes, mid);
        // 断点续传:同路径再次 init,receivedBytes = 已有文件长度
        let again = man
            .init_upload(
                &UploadInitRequest {
                    instance_id: Uuid::new_v4(),
                    path: "target".into(),
                    file_name: "data.bin".into(),
                    size_bytes: payload.len() as u64,
                    sha256: None,
                    auto_extract: false,
                },
                &dir,
            )
            .await
            .unwrap();
        assert_eq!(again.received_bytes, mid);

        let p2 = man
            .write_piece(
                &init.upload_id,
                mid,
                axum::body::Bytes::from(payload[mid as usize..].to_vec()),
            )
            .await
            .unwrap();
        assert_eq!(p2.received_bytes, payload.len() as u64);

        let done = man.complete_upload(&init.upload_id).await.unwrap();
        assert_eq!(done.path, "target/data.bin");
        assert_eq!(fs::read(dir.join("target/data.bin")).unwrap(), payload);
        fs::remove_dir_all(dir).unwrap();
    }

    #[tokio::test]
    async fn upload_incomplete_fails() {
        let dir = tmp();
        fs::create_dir_all(&dir).unwrap();
        let man = FsManager::default();
        let init = man
            .init_upload(
                &UploadInitRequest {
                    instance_id: Uuid::new_v4(),
                    path: "".into(),
                    file_name: "a.bin".into(),
                    size_bytes: 10,
                    sha256: None,
                    auto_extract: false,
                },
                &dir,
            )
            .await
            .unwrap();
        man.write_piece(&init.upload_id, 0, axum::body::Bytes::from(vec![0u8; 3]))
            .await
            .unwrap();
        assert!(matches!(
            man.complete_upload(&init.upload_id).await,
            Err(FsError::Invalid(_))
        ));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn zip_roundtrip_and_extract() {
        let dir = tmp();
        fs::create_dir_all(dir.join("src/sub")).unwrap();
        fs::write(dir.join("src/a.txt"), b"aaa").unwrap();
        fs::write(dir.join("src/sub/b.txt"), b"bbb").unwrap();

        let archive = dir.join("out.zip");
        create_zip(&dir.join("src"), &archive).unwrap();
        let out = dir.join("out");
        fs::create_dir_all(&out).unwrap();
        extract_zip(&archive, &out).unwrap();
        assert_eq!(fs::read_to_string(out.join("a.txt")).unwrap(), "aaa");
        assert_eq!(fs::read_to_string(out.join("sub/b.txt")).unwrap(), "bbb");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn extract_rejects_zip_slip() {
        let dir = tmp();
        fs::create_dir_all(&dir).unwrap();
        // 手工构造一个含 "../evil" 条目的恶意 zip
        let archive_path = dir.join("evil.zip");
        {
            let f = fs::File::create(&archive_path).unwrap();
            let mut zip = zip::ZipWriter::new(f);
            let options = zip::write::SimpleFileOptions::default();
            zip.start_file("../evil.txt", options).unwrap();
            zip.write_all(b"pwn").unwrap();
            zip.finish().unwrap();
        }
        let out = dir.join("out");
        let result = extract_zip(&archive_path, &out);
        assert!(result.is_err(), "zip-slip entry must be rejected");
        assert!(!out.join("evil.txt").exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn tar_gz_roundtrip() {
        let dir = tmp();
        fs::create_dir_all(&dir).unwrap();
        let archive_path = dir.join("pkg.tar.gz");
        {
            let f = fs::File::create(&archive_path).unwrap();
            let enc = flate2::write::GzEncoder::new(f, flate2::Compression::default());
            let mut tar = tar::Builder::new(enc);
            let mut header = tar::Header::new_gnu();
            header.set_size(5);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, "hello.txt", std::io::Cursor::new("world")).unwrap();
            tar.finish().unwrap();
        }
        let out = dir.join("out");
        fs::create_dir_all(&out).unwrap();
        extract_archive(&archive_path, &out).unwrap();
        assert_eq!(fs::read_to_string(out.join("hello.txt")).unwrap(), "world");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn write_text_atomic_overwrites_and_cleans_tmp() {
        let dir = tmp();
        fs::create_dir_all(&dir).unwrap();
        let target = dir.join("a.txt");
        fs::write(&target, b"old").unwrap();

        let tmp = dir.join(".a.txt.uuid.tmp");
        write_text_atomic(&tmp, &target, b"new content").unwrap();
        assert_eq!(fs::read_to_string(&target).unwrap(), "new content");
        assert!(!tmp.exists(), "临时文件应在成功后清理");

        // 目标不存在(新建)同样走原子写入
        let target2 = dir.join("b.txt");
        write_text_atomic(&tmp, &target2, b"hello").unwrap();
        assert_eq!(fs::read_to_string(&target2).unwrap(), "hello");
        assert!(!tmp.exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn write_text_atomic_removes_orphan_tmp_on_failure() {
        let dir = tmp();
        fs::create_dir_all(&dir).unwrap();
        let target = dir.join("c.txt");
        fs::write(&target, b"keep").unwrap();

        // 目标为目录:rename 覆盖必然失败,旧文件保留、临时文件被清理
        let as_dir = dir.join("d");
        fs::create_dir_all(&as_dir).unwrap();
        let tmp = dir.join(".d.uuid.tmp");
        write_text_atomic(&tmp, &as_dir, b"won't write into a dir").unwrap_err();
        assert!(as_dir.is_dir());
        assert!(!tmp.exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn resolve_and_write_path_validation() {
        let cwd = Path::new("/srv/files/x");
        // 与 handler 相同的沙箱约束:根不可写、`..` 拒绝、绝对路径拒绝
        assert!(resolve(cwd, "../etc/passwd").is_err());
        assert!(resolve(cwd, "/etc/passwd").is_err());
        assert!(resolve(cwd, "a/b.txt").unwrap() == cwd.join("a/b.txt"));
    }
}