//! 实例迁移(导出打包 + 导入还原):导出归档存储在 daemon 数据目录 `exports/`。
//!
//! 导出结构:
//! - 顶层必须包含 `config.json` (原实例完整配置拷贝一份)
//! - `files/` 目录 = 原实例工作目录内容
//!
//! 导入:
//! - 归档解压到临时目录 → 读取 `config.json` → 生成新 uuid → 建新实例配置 →
//!   把 `files/` 内容移动到新实例工作目录 → 新实例出现在实例列表。
//! - 原导出归档仍然保留在上传时的位置(不删除),可重复导入。

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tokio::task::spawn_blocking;
use uuid::Uuid;

use crate::fs::extract_archive;
use crate::instance::{InstanceConfig, InstanceInput, InstanceManager};
use crate::task::model::{TaskFailure, TaskProgress};
use crate::task::service::TaskHandle;

/// 导出请求参数(对齐 openapi ExportRequest)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportRequest {
    #[serde(default = "default_format_zip")]
    pub format: ExportFormat,
    #[serde(default = "default_false")]
    pub include_logs: bool,
}

/// 导出归档格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ExportFormat {
    Zip,
    #[serde(rename = "tar.gz")]
    TarGz,
}

impl Default for ExportFormat {
    fn default() -> Self {
        ExportFormat::Zip
    }
}

fn default_format_zip() -> ExportFormat {
    ExportFormat::Zip
}
fn default_false() -> bool {
    false
}

/// 导入请求参数(对齐 openapi ImportRequest)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportRequest {
    /// 归档所在实例 id(先经 /fs/upload-* 上传到该实例 cwd)。
    pub source_instance_id: Uuid,
    /// 归档文件在该实例工作目录内的相对路径。
    pub archive_path: String,
}

/// 实例迁移管理器:导出归档存放于 daemon 数据目录 `exports/`,导入临时目录
/// 存放于 `imports/tmp/`。
///
/// - 每个导出任务产生一个文件: `exports/{export_task_id}.{ext}`
/// - 导入归档解压到 `imports/tmp/{uuid}`,校验完成后移动 files/ 到新实例,
///   临时目录随即清理。
#[derive(Clone)]
pub struct TransferManager {
    exports_dir: PathBuf,
    imports_tmp_dir: PathBuf,
}

impl TransferManager {
    /// 初始化:确保 exports/ 与 imports/tmp/ 目录存在。
    pub fn new(data_dir: &Path) -> io::Result<Self> {
        let exports_dir = data_dir.join("exports");
        let imports_tmp_dir = data_dir.join("imports").join("tmp");
        fs::create_dir_all(&exports_dir)?;
        fs::create_dir_all(&imports_tmp_dir)?;
        // 清理陈旧临时目录与过期导出文件(启动时一次性清理)
        Self::cleanup_stale(&imports_tmp_dir);
        let _ = Self::cleanup_expired(&exports_dir);
        Ok(TransferManager {
            exports_dir,
            imports_tmp_dir,
        })
    }

    /// 给导出任务生成归档路径。
    pub fn export_archive_path(&self, task_id: Uuid, format: ExportFormat) -> PathBuf {
        let ext = match format {
            ExportFormat::Zip => "zip",
            ExportFormat::TarGz => "tar.gz",
        };
        self.exports_dir.join(format!("{task_id}.{ext}"))
    }

    /// 根据任务 id 获取已导出归档路径(存在返回 Some,否则 None)。
    pub fn get_export_archive(&self, task_id: Uuid) -> Option<PathBuf> {
        // 试两种格式,找存在的那个
        let zip = self.export_archive_path(task_id, ExportFormat::Zip);
        if zip.exists() {
            return Some(zip);
        }
        let tgz = self.export_archive_path(task_id, ExportFormat::TarGz);
        if tgz.exists() {
            return Some(tgz);
        }
        None
    }

    /// 新建一个导入用临时解压目录(调用方负责在结束后清理)。
    pub fn new_import_tmp(&self) -> io::Result<PathBuf> {
        let dir = self.imports_tmp_dir.join(Uuid::new_v4().to_string());
        fs::create_dir_all(&dir)?;
        Ok(dir)
    }

    /// 清理导入临时目录中残留的陈旧子目录(上次异常中断产生)。
    fn cleanup_stale(imports_tmp_dir: &Path) {
        let Ok(mut entries) = fs::read_dir(imports_tmp_dir) else {
            return;
        };
        while let Some(Ok(entry)) = entries.next() {
            if entry.metadata().map(|m| m.is_dir()).unwrap_or(false) {
                let _ = fs::remove_dir_all(entry.path());
            }
        }
    }

    /// 清理 24 小时前的导出文件(空间回收)。
    fn cleanup_expired(exports_dir: &Path) -> io::Result<()> {
        let Ok(mut entries) = fs::read_dir(exports_dir) else {
            return Ok(());
        };
        let twenty_four_hours_ago = std::time::SystemTime::now()
            .checked_sub(std::time::Duration::from_secs(86400))
            .unwrap();
        while let Some(Ok(entry)) = entries.next() {
            let Ok(meta) = entry.metadata() else {
                continue;
            };
            if !meta.is_file() {
                continue;
            }
            let Ok(modified) = meta.modified() else {
                continue;
            };
            if modified < twenty_four_hours_ago {
                let _ = fs::remove_file(entry.path());
            }
        }
        Ok(())
    }
}

/// 导出任务执行体:打包实例工作目录 + 嵌入 config.json。
///
/// 预条件:
/// - 实例必须已停止(调用方确保 409 检查)。
/// - 调用者已通过 TaskService 排队(同实例串行)。
pub async fn run_export_task(
    handle: TaskHandle,
    tm: TransferManager,
    im: Arc<InstanceManager>,
    instance_id: Uuid,
    req: ExportRequest,
) -> Result<(), TaskFailure> {
    handle.set_phase("preparing").await;

    // 1. 拿实例配置 + 工作目录
    let config = im
        .get_config(instance_id)
        .await
        .ok_or_else(|| TaskFailure::new("instance_not_found", "instance not found"))?;
    let working_dir = config.working_directory.clone();
    if !working_dir.exists() {
        return Err(TaskFailure::new(
            "working_dir_missing",
            "instance working directory not found",
        ));
    }

    // 2. 确定归档路径和格式
    let task_id = handle.id();
    let archive_path = tm.export_archive_path(task_id, req.format);

    // 3. 统计总文件大小(用于进度百分比)
    handle.set_phase("scanning").await;
    let include_logs = req.include_logs;
    let total_bytes = match spawn_blocking({
        let working_dir = working_dir.clone();
        move || count_total_bytes(&working_dir, include_logs)
    })
    .await
    {
        Ok(Ok(b)) => b,
        Ok(Err(e)) => {
            return Err(TaskFailure::new("scan_failed", format!("cannot scan: {e}")));
        }
        Err(e) => {
            return Err(TaskFailure::new("scan_panic", format!("task panic: {e}")));
        }
    };

    // 4. 打包到目标归档(spawn_blocking 避免阻塞异步事件循环)
    handle.set_phase("packing").await;
    tracing::info!(
        instance_id = %instance_id,
        archive = %archive_path.display(),
        "starting instance export"
    );

    // 闭包中使用的变量先克隆,保证 move 后外层仍可取用(archive_path 用于日志/清理)
    let archive_for_pack = archive_path.clone();
    let result = spawn_blocking(move || {
        match req.format {
            ExportFormat::Zip => create_zip_export(
                &working_dir,
                &config,
                include_logs,
                &archive_for_pack,
                &handle,
                total_bytes,
            ),
            ExportFormat::TarGz => create_targz_export(
                &working_dir,
                &config,
                include_logs,
                &archive_for_pack,
                &handle,
                total_bytes,
            ),
        }
    })
    .await;

    match result {
        Ok(Ok(())) => {
            tracing::info!(
                instance_id = %instance_id,
                archive = %archive_path.display(),
                "instance export completed"
            );
            Ok(())
        }
        Ok(Err(e)) => {
            let _ = fs::remove_file(&archive_path);
            Err(TaskFailure::new("export_failed", format!("pack failed: {e}")))
        }
        Err(e) => {
            let _ = fs::remove_file(&archive_path);
            Err(TaskFailure::new("export_panic", format!("task panic: {e}")))
        }
    }
}

/// 递归统计待打包文件总字节数。
fn count_total_bytes(root: &Path, include_logs: bool) -> io::Result<u64> {
    let mut total = 0;
    if !root.exists() {
        return Ok(0);
    }

    let mut stack = vec![root.to_path_buf()];
    while let Some(path) = stack.pop() {
        let meta = fs::symlink_metadata(&path)?;
        if meta.is_symlink() {
            // 跳过符号链接,避免打包外部文件造成安全问题
            continue;
        }
        if meta.is_dir() {
            for entry in fs::read_dir(&path)?.flatten() {
                let entry_path = entry.path();
                // 排除 logs 目录(用户选择不包含时)
                if !include_logs
                    && entry.metadata().map(|m| m.is_dir()).unwrap_or(false)
                    && entry.file_name() == "logs"
                {
                    continue;
                }
                stack.push(entry_path);
            }
        } else if meta.is_file() {
            total += meta.len();
        }
    }
    Ok(total)
}

/// 创建 zip 格式导出归档。
/// - 顶层: config.json + files/
fn create_zip_export(
    working_dir: &Path,
    config: &InstanceConfig,
    include_logs: bool,
    target: &Path,
    handle: &TaskHandle,
    total_bytes: u64,
) -> io::Result<()> {
    use zip::ZipWriter;

    let file = fs::File::create(target)?;
    let mut zip = ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    // 1. 先写顶层 config.json
    let json = serde_json::to_string_pretty(config)?;
    zip.start_file("config.json", options)?;
    zip.write_all(json.as_bytes())?;

    // 2. 递归添加 working_dir 到 files/
    let mut processed_bytes = 0;
    add_dir_to_zip(
        &mut zip,
        working_dir,
        "files",
        include_logs,
        &mut processed_bytes,
        total_bytes,
        handle,
    )?;

    zip.finish()?;
    Ok(())
}

/// 递归添加目录到 zip,更新进度。
fn add_dir_to_zip(
    zip: &mut zip::ZipWriter<std::fs::File>,
    src_root: &Path,
    zip_prefix: &str,
    include_logs: bool,
    processed: &mut u64,
    total: u64,
    handle: &TaskHandle,
) -> io::Result<()> {
    for entry in fs::read_dir(src_root)? {
        if handle.is_cancelled() {
            return Err(io::Error::other("export cancelled"));
        }
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();

        // 跳过 logs 目录(excludeLogs 时,仅跳过名为 logs 的目录)
        let meta = entry.metadata()?;
        if !include_logs && meta.is_dir() && file_name == "logs" {
            continue;
        }

        // 跳过符号链接(避免打包外部文件)
        if meta.is_symlink() {
            continue;
        }

        let zip_path = format!("{zip_prefix}/{}", file_name.to_string_lossy());
        if meta.is_dir() {
            zip.add_directory(&zip_path, zip::write::SimpleFileOptions::default())?;
            add_dir_to_zip(
                zip,
                &path,
                &zip_path,
                include_logs,
                processed,
                total,
                handle,
            )?;
        } else if meta.is_file() {
            let mut f = fs::File::open(&path)?;
            zip.start_file(&zip_path, zip::write::SimpleFileOptions::default())?;
            let bytes_copied = std::io::copy(&mut f, zip)?;
            *processed += bytes_copied;
            emit_progress(*processed, total, handle);
        }
    }
    Ok(())
}

/// 创建 tar.gz 格式导出归档。
fn create_targz_export(
    working_dir: &Path,
    config: &InstanceConfig,
    include_logs: bool,
    target: &Path,
    handle: &TaskHandle,
    total_bytes: u64,
) -> io::Result<()> {
    use flate2::write::GzEncoder;
    use flate2::Compression;

    let file = fs::File::create(target)?;
    let gz = GzEncoder::new(file, Compression::default());
    let mut tar = tar::Builder::new(gz);

    // 1. 添加顶层 config.json
    let json = serde_json::to_string_pretty(config)?;
    let mut header = tar::Header::new_gnu();
    header.set_path("config.json")?;
    header.set_size(json.len() as u64);
    header.set_cksum();
    tar.append(&mut header, json.as_bytes())?;

    // 2. 递归添加 working_dir 到 files/
    let mut processed_bytes = 0;
    add_dir_to_tar(
        &mut tar,
        working_dir,
        "files",
        include_logs,
        &mut processed_bytes,
        total_bytes,
        handle,
    )?;

    tar.finish()?;
    Ok(())
}

/// 递归添加目录到 tar,更新进度。
fn add_dir_to_tar(
    tar: &mut tar::Builder<flate2::write::GzEncoder<std::fs::File>>,
    src_root: &Path,
    tar_prefix: &str,
    include_logs: bool,
    processed: &mut u64,
    total: u64,
    handle: &TaskHandle,
) -> io::Result<()> {
    for entry in fs::read_dir(src_root)? {
        if handle.is_cancelled() {
            return Err(io::Error::other("export cancelled"));
        }
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();

        // 跳过 logs 目录(excludeLogs 时)
        let meta = entry.metadata()?;
        if !include_logs && meta.is_dir() && file_name == "logs" {
            continue;
        }

        // 跳过符号链接
        if meta.is_symlink() {
            continue;
        }

        let tar_path = format!("{tar_prefix}/{}", file_name.to_string_lossy());
        if meta.is_dir() {
            add_dir_to_tar(
                tar,
                &path,
                &tar_path,
                include_logs,
                processed,
                total,
                handle,
            )?;
        } else if meta.is_file() {
            let mut f = fs::File::open(&path)?;
            let mut header = tar::Header::new_gnu();
            header.set_path(&tar_path)?;
            header.set_size(meta.len());
            header.set_cksum();
            tar.append(&mut header, &mut f)?;
            *processed += meta.len();
            emit_progress(*processed, total, handle);
        }
    }
    Ok(())
}

/// 同步进度上报(spawn_blocking 内调用;不持有 async runtime 时静默跳过)。
/// 通过当前 tokio runtime Handle block_on 更新任务进度,失败仅告警不致导出失败。
fn emit_progress(processed: u64, total: u64, handle: &TaskHandle) {
    if total == 0 {
        return;
    }
    let progress = TaskProgress {
        received_bytes: Some(processed),
        total_bytes: Some(total),
        percent: Some(processed as f32 / total as f32),
        ..Default::default()
    };
    if let Ok(rt) = tokio::runtime::Handle::try_current() {
        // 在 tokio runtime 上下文内(spawn_blocking 时可用)异步发送进度
        let progress = progress.clone();
        rt.block_on(async move {
            handle.set_progress(progress).await;
        });
    }
}

/// 导入任务执行体:从归档还原为新实例。
///
/// - 归档位于 source_instance_id 对应的实例 cwd 内(先经 /fs/upload-* 上传)。
/// - 新实例 id 重新生成,所有路径重新分配。
pub async fn run_import_task(
    handle: TaskHandle,
    tm: TransferManager,
    im: Arc<InstanceManager>,
    req: ImportRequest,
) -> Result<(), TaskFailure> {
    handle.set_phase("validating").await;

    // 1. 定位源实例 cwd,并做路径沙箱校验(防穿越)
    let source_cwd = im
        .get_config(req.source_instance_id)
        .await
        .ok_or_else(|| TaskFailure::new("instance_not_found", "source instance not found"))?
        .working_directory;
    let archive_path = crate::fs::resolve(&source_cwd, &req.archive_path)
        .map_err(|e| TaskFailure::new("invalid_archive_path", e.to_string()))?;
    if !archive_path.exists() {
        return Err(TaskFailure::new(
            "archive_not_found",
            format!("archive not found at {}", archive_path.display()),
        ));
    }

    // 2. 创建临时解压目录(在 daemon 数据目录 imports/tmp 下)
    let temp_dir = tm
        .new_import_tmp()
        .map_err(|e| TaskFailure::new("create_temp_failed", format!("cannot create temp: {e}")))?;

    // 3. 解压到临时目录(spawn_blocking)
    handle.set_phase("extracting").await;
    tracing::info!(archive = %archive_path.display(), temp = %temp_dir.display(), "starting instance import");

    let tmp_for_extract = temp_dir.clone();
    let archive_for_extract = archive_path.clone();
    let unpack_result = spawn_blocking(move || extract_archive(&archive_for_extract, &tmp_for_extract)).await;

    match unpack_result {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(TaskFailure::new(
                "extract_failed",
                format!("cannot extract archive: {e}"),
            ));
        }
        Err(e) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(TaskFailure::new("extract_panic", format!("task panic: {e}")));
        }
    }

    // 4. 读取顶层 config.json
    handle.set_phase("parsing_config").await;
    let config_json = temp_dir.join("config.json");
    if !config_json.exists() {
        let _ = fs::remove_dir_all(&temp_dir);
        return Err(TaskFailure::new(
            "invalid_archive",
            "archive missing top-level config.json, not a valid EdgeCube export",
        ));
    }

    let raw_config = match fs::read_to_string(&config_json) {
        Ok(r) => r,
        Err(e) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(TaskFailure::new(
                "read_config_failed",
                format!("cannot read config.json: {e}"),
            ));
        }
    };

    let mut original_config: InstanceConfig = match serde_json::from_str(&raw_config) {
        Ok(c) => c,
        Err(e) => {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(TaskFailure::new(
                "parse_config_failed",
                format!("cannot parse config.json: {e}"),
            ));
        }
    };

    // 5. 创建新实例输入(大部分字段从原配置拷贝,重新生成 id 和路径)
    let base_name = original_config.name.clone();
    let mut name = base_name.clone();
    let mut suffix = 2;
    let new_config = loop {
        let input = InstanceInput {
            name: name.clone(),
            start_command: original_config.start_command.clone(),
            stop_command: original_config.stop_command.clone(),
            stop_timeout_seconds: original_config.stop_timeout_seconds,
            working_directory: None, // 让 manager 分配新路径 {data}/files/{new_id}
            environment: original_config.environment.clone(),
            input_encoding: original_config.input_encoding,
            output_encoding: original_config.output_encoding,
            auto_restart: original_config.auto_restart,
            auto_restart_max_times: original_config.auto_restart_max_times,
            auto_start_on_boot: original_config.auto_start_on_boot,
            terminal: original_config.terminal.clone(),
            instance_type: original_config.instance_type,
            runtime_id: original_config.runtime_id.clone(),
            download_url: None, // 导入不需要下载
            file_name: None,
            checksum: None,
        };

        // 6. 创建新实例(名字冲突时自动追加 -2/-3 后缀重试)
        handle.set_phase("creating_instance").await;
        match im.create(input).await {
            Ok(c) => break c,
            Err(crate::instance::ManagerError::DuplicateName(_)) => {
                name = format!("{base_name}-{suffix}");
                suffix += 1;
            }
            Err(e) => {
                let _ = fs::remove_dir_all(&temp_dir);
                return Err(TaskFailure::new(
                    "create_instance_failed",
                    format!("cannot create new instance: {e}"),
                ));
            }
        }
    };

    // 7. 把 temp/files/ 内容移动到新实例工作目录
    handle.set_phase("moving_files").await;
    let temp_files = temp_dir.join("files");
    if temp_files.exists() {
        let new_cwd = new_config.working_directory.clone();
        let tmp_for_move = temp_dir.clone();
        let move_result = spawn_blocking(move || move_dir_contents(&tmp_for_move.join("files"), &new_cwd)).await;
        if let Err(e) = match move_result {
            Ok(r) => r,
            Err(e) => Err(io::Error::other(format!("move task panic: {e}"))),
        } {
            // 创建了实例但文件移动失败 → 删除半成品实例
            let _ = im.delete(new_config.id).await;
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(TaskFailure::new(
                "move_files_failed",
                format!("cannot move files to new instance: {e}"),
            ));
        }
    }

    // 8. 清理临时目录
    let _ = fs::remove_dir_all(&temp_dir);

    tracing::info!(
        new_instance_id = %new_config.id,
        new_name = %new_config.name,
        "instance import completed"
    );
    Ok(())
}

/// 移动源目录下所有内容到目标目录(目标已创建)。
/// 源是临时解压目录,移动后源删除。
///
/// 纯同步实现(内部递归),由调用方经 spawn_blocking 执行,避免 async 递归装箱。
fn move_dir_contents(src: &Path, dst: &Path) -> io::Result<()> {
    if !src.is_dir() {
        return Ok(());
    }

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());

        if entry.metadata()?.is_dir() {
            fs::create_dir_all(&dst_path)?;
            move_dir_contents(&src_path, &dst_path)?;
            fs::remove_dir(src_path)?;
        } else {
            // 如果目标已存在则覆盖
            if dst_path.exists() {
                fs::remove_file(&dst_path)?;
            }
            fs::rename(&src_path, &dst_path)?;
        }
    }
    Ok(())
}
