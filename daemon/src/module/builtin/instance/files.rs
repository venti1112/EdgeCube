//! 实例工作目录的文件管理（同步 IO，调用方负责丢进 `spawn_blocking`）。
//!
//! 语义：
//!
//! * 列目录：目录在前，各自按名称**忽略大小写**排序；
//! * 复制重名 → 自动追加 ` (n)`；移动重名 → 直接报错；
//! * 重命名只改名字不搬家，同目录内进行；
//! * 删除符号链接只删链接本身，**绝不**跟着删目标；
//! * 压缩/解压交给 [`archive`] 子模块（zip / tar 家族 / 7z / rar / 单流压缩）；
//! * 解压到「归档名去掉归档后缀」的新子目录里。
//!
//! 路径参数是**相对实例目录**的字符串（不是本机绝对路径）。
//! [`resolve`] 是唯一入口，把 `..`、绝对路径之类越界写法
//! 全部挡在门外 —— 这是安全边界，不是格式偏好。
//!
//! # 符号链接
//!
//! 跟随与否按操作区分：**读**（列目录、读文本、压缩）跟随，**改**（删除、
//! 重命名、移动）只作用于链接本身。能走到这里的调用方本来就
//! 持令牌、能改实例的启动命令、能开 PTY，所以「实例目录里预先存在的链接」
//! 不算提权面；真正要防的是 `path` 参数里的 `..`。

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::{Value, json};

use super::archive;
use crate::error::{RpcError, RpcResult};
use crate::util::now_ms;

/// 来自模块配置的几条上限。
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// 内置编辑器读写的单文件上限（字节）。
    pub text_max_bytes: u64,
    /// 搜索一次最多返回多少条。
    pub search_max: usize,
    /// 打包一个归档最多收多少条目。
    pub archive_max_entries: u64,
}

// ══════════════════════════════════════════════════════════════════════════
// 路径与条目
// ══════════════════════════════════════════════════════════════════════════

/// 相对路径 → 实例目录内的绝对路径。
///
/// 拒绝绝对路径与任何 `..` 段（`\` 也当分隔符，免得 Windows 客户端以为
/// 能借它绕过去）。空串与 `.` 都表示实例目录本身。
pub fn resolve(root: &Path, rel: &str) -> RpcResult<PathBuf> {
    let rel = rel.trim();
    if rel.starts_with('/') || rel.starts_with('\\') {
        return Err(RpcError::invalid_params(format!(
            "路径必须是相对实例目录的：`{rel}`"
        )));
    }
    let mut out = root.to_path_buf();
    for part in rel.split(['/', '\\']) {
        match part {
            "" | "." => continue,
            ".." => {
                return Err(RpcError::invalid_params(format!(
                    "路径不能包含 `..`：`{rel}`"
                )));
            }
            other => out.push(other),
        }
    }
    Ok(out)
}

/// 校验一个「名字」参数（新建/重命名用）：单段、非空、不是 `.` / `..`。
pub fn validate_name(name: &str) -> RpcResult<String> {
    let name = name.trim();
    if name.is_empty() {
        return Err(RpcError::invalid_params("名称不能为空"));
    }
    if name == "." || name == ".." {
        return Err(RpcError::invalid_params("名称不合法"));
    }
    if name.contains('/') || name.contains('\\') {
        return Err(RpcError::invalid_params("名称里不能有路径分隔符"));
    }
    Ok(name.to_string())
}

/// 绝对路径 → 相对实例目录的展示路径（`/` 分隔；实例目录本身为 `""`）。
pub fn display_path(root: &Path, path: &Path) -> String {
    let rel = path.strip_prefix(root).unwrap_or(path);
    let mut parts: Vec<String> = Vec::new();
    for component in rel.components() {
        let text = component.as_os_str().to_string_lossy().into_owned();
        if text.is_empty() {
            continue;
        }
        parts.push(text);
    }
    parts.join("/")
}

/// 目录里的一个条目（给前端的展示信息）。
#[derive(Debug, Clone, Serialize)]
pub struct Entry {
    pub name: String,
    /// 相对实例目录的路径。
    pub path: String,
    /// 是否目录。对符号链接而言，表示其**目标**是不是目录。
    pub is_dir: bool,
    pub is_link: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link_target: Option<String>,
    /// 文件字节数；目录为 0。
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified_ms: Option<u64>,
}

/// 把一个路径读成 [`Entry`]（跟随链接判定类型）。
fn entry_of(root: &Path, path: &Path) -> RpcResult<Entry> {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let meta = fs::symlink_metadata(path).map_err(|e| io_error(path, e))?;
    let is_link = meta.file_type().is_symlink();

    // 链接取目标的信息；断链退化为「0 字节的非目录」，不报错。
    let followed = if is_link {
        fs::metadata(path).ok()
    } else {
        Some(meta)
    };
    let is_dir = followed.as_ref().is_some_and(|m| m.is_dir());
    let size = match followed.as_ref() {
        Some(m) if !m.is_dir() => m.len(),
        _ => 0,
    };
    let modified_ms = followed.as_ref().and_then(modified_ms_of);
    let link_target = if is_link {
        fs::read_link(path)
            .ok()
            .map(|p| p.to_string_lossy().into_owned())
    } else {
        None
    };

    Ok(Entry {
        name,
        path: display_path(root, path),
        is_dir,
        is_link,
        link_target,
        size,
        modified_ms,
    })
}

fn modified_ms_of(meta: &fs::Metadata) -> Option<u64> {
    let modified = meta.modified().ok()?;
    let since = modified.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some(since.as_millis() as u64)
}

fn entry_value(root: &Path, path: &Path) -> RpcResult<Value> {
    Ok(json!({ "entry": entry_of(root, path)? }))
}

/// 把实例目录里的一个绝对路径描述成 `{"entry": {...}}`（上传落盘后回给前端）。
pub fn describe(root: &Path, path: &Path) -> RpcResult<Value> {
    entry_value(root, path)
}

/// 排序：目录在前，然后按名称忽略大小写。
fn sort_entries(entries: &mut [Entry]) {
    entries.sort_by(|a, b| {
        if a.is_dir != b.is_dir {
            return if a.is_dir {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Greater
            };
        }
        let by_name = a.name.to_lowercase().cmp(&b.name.to_lowercase());
        if by_name != std::cmp::Ordering::Equal {
            return by_name;
        }
        // 同名不同大小写的两条，再按原样比一次，保证顺序稳定
        a.name.cmp(&b.name)
    });
}

// ── 错误小工具 ─────────────────────────────────────────────────────────────

/// 404：目录里没有这个条目。
fn not_found(name: &str) -> RpcError {
    RpcError::new("file_not_found", format!("没有 `{name}` 这个条目"))
}

/// 409：目标位置已有同名条目。
fn conflict(name: &str) -> RpcError {
    RpcError::new("file_exists", format!("目标位置已存在同名文件：{name}"))
}

pub fn io_error(path: &Path, error: std::io::Error) -> RpcError {
    if error.kind() == std::io::ErrorKind::NotFound {
        return not_found(&path.display().to_string());
    }
    if error.kind() == std::io::ErrorKind::AlreadyExists {
        return conflict(&path.display().to_string());
    }
    RpcError::new("file_io", format!("{} 操作失败：{error}", path.display()))
}

// ══════════════════════════════════════════════════════════════════════════
// 读
// ══════════════════════════════════════════════════════════════════════════

/// 列出目录。目录不存在 → 空列表（不报错）。
pub fn list(root: &Path, rel: &str) -> RpcResult<Value> {
    let dir = resolve(root, rel)?;
    let mut entries: Vec<Entry> = Vec::new();

    match fs::read_dir(&dir) {
        Ok(iter) => {
            for item in iter.flatten() {
                if let Ok(entry) = entry_of(root, &item.path()) {
                    entries.push(entry);
                }
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotADirectory => {
            return Err(RpcError::invalid_params(format!(
                "{} 不是目录",
                display_path(root, &dir)
            )));
        }
        Err(e) => return Err(io_error(&dir, e)),
    }

    sort_entries(&mut entries);
    Ok(json!({
        "path": display_path(root, &dir),
        "entries": entries,
    }))
}

/// 按名称搜索（大小写不敏感的子串）。不跟随符号链接（`followLinks: false`），
/// 读不动的子目录静默跳过。
pub fn search(
    root: &Path,
    rel: &str,
    query: &str,
    recursive: bool,
    limits: &Limits,
) -> RpcResult<Value> {
    let dir = resolve(root, rel)?;
    let needle = query.trim().to_lowercase();
    let mut matches: Vec<Entry> = Vec::new();
    let mut truncated = false;

    if !needle.is_empty() {
        let mut stack = vec![dir.clone()];
        while let Some(current) = stack.pop() {
            let Ok(iter) = fs::read_dir(&current) else {
                continue; // 没权限或目录在枚举中消失：跳过这棵子树
            };
            for item in iter.flatten() {
                let path = item.path();
                let Ok(meta) = fs::symlink_metadata(&path) else {
                    continue;
                };
                let is_dir = meta.is_dir();
                let name = item.file_name().to_string_lossy().into_owned();
                if name.to_lowercase().contains(&needle)
                    && let Ok(entry) = entry_of(root, &path)
                {
                    matches.push(entry);
                    if matches.len() >= limits.search_max {
                        truncated = true;
                        break;
                    }
                }
                if recursive && is_dir {
                    stack.push(path);
                }
            }
            if truncated {
                break;
            }
        }
    }

    sort_entries(&mut matches);
    Ok(json!({
        "path": display_path(root, &dir),
        "query": query.trim(),
        "recursive": recursive,
        "truncated": truncated,
        "entries": matches,
    }))
}

/// 读文本。`raw = true` 时按 latin1 兜底（一个字节一个字符，永不失败），
/// 保存时仍按 UTF-8 写回。
pub fn read_text(root: &Path, rel: &str, raw: bool, limits: &Limits) -> RpcResult<Value> {
    let path = resolve(root, rel)?;
    let meta = fs::metadata(&path).map_err(|e| io_error(&path, e))?;
    if !meta.is_file() {
        return Err(RpcError::invalid_params(format!(
            "{} 不是普通文件",
            display_path(root, &path)
        )));
    }
    if meta.len() > limits.text_max_bytes {
        return Err(RpcError::new(
            "file_too_large",
            format!(
                "文件太大（{} 字节），超过编辑器上限 {} 字节",
                meta.len(),
                limits.text_max_bytes
            ),
        ));
    }

    let bytes = fs::read(&path).map_err(|e| io_error(&path, e))?;
    let (content, encoding) = if raw {
        (
            bytes.iter().map(|b| *b as char).collect::<String>(),
            "latin1",
        )
    } else {
        match String::from_utf8(bytes) {
            Ok(text) => (text, "utf-8"),
            Err(_) => {
                return Err(RpcError::new(
                    "file_not_utf8",
                    "这个文件不是 UTF-8 文本，可以强制按 latin1 打开",
                ));
            }
        }
    };

    Ok(json!({
        "path": display_path(root, &path),
        "name": path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        "content": content,
        "encoding": encoding,
        "size": meta.len(),
    }))
}

// ══════════════════════════════════════════════════════════════════════════
// 写
// ══════════════════════════════════════════════════════════════════════════

/// 新建子目录。重名报错。
pub fn create_dir(root: &Path, rel: &str, name: &str) -> RpcResult<Value> {
    let parent = resolve(root, rel)?;
    let name = validate_name(name)?;
    let target = parent.join(&name);
    if exists_no_follow(&target) {
        return Err(conflict(&name));
    }
    fs::create_dir(&target).map_err(|e| io_error(&target, e))?;
    entry_value(root, &target)
}

/// 新建空文件。已存在同名文件**或目录**都报错。
pub fn create_file(root: &Path, rel: &str, name: &str) -> RpcResult<Value> {
    let parent = resolve(root, rel)?;
    let name = validate_name(name)?;
    let target = parent.join(&name);
    if exists_no_follow(&target) {
        return Err(conflict(&name));
    }
    fs::File::create(&target).map_err(|e| io_error(&target, e))?;
    entry_value(root, &target)
}

/// 覆盖写入文本（直接写、写前 flush）。
pub fn write_text(root: &Path, rel: &str, content: &str, limits: &Limits) -> RpcResult<Value> {
    let path = resolve(root, rel)?;
    if content.len() as u64 > limits.text_max_bytes {
        return Err(RpcError::new(
            "file_too_large",
            format!(
                "内容太大（{} 字节），超过编辑器上限 {} 字节",
                content.len(),
                limits.text_max_bytes
            ),
        ));
    }
    let meta = fs::metadata(&path).map_err(|e| io_error(&path, e))?;
    if !meta.is_file() {
        return Err(RpcError::invalid_params(format!(
            "{} 不是普通文件",
            display_path(root, &path)
        )));
    }

    let mut file = fs::File::create(&path).map_err(|e| io_error(&path, e))?;
    file.write_all(content.as_bytes())
        .map_err(|e| io_error(&path, e))?;
    file.flush().map_err(|e| io_error(&path, e))?;
    Ok(json!({
        "path": display_path(root, &path),
        "size": content.len(),
    }))
}

/// 同目录内重命名。链接重命名的是链接本身。
pub fn rename(root: &Path, rel: &str, new_name: &str) -> RpcResult<Value> {
    let source = resolve(root, rel)?;
    if source == root {
        return Err(RpcError::invalid_params("不能重命名实例根目录"));
    }
    let new_name = validate_name(new_name)?;
    let parent = source
        .parent()
        .ok_or_else(|| RpcError::invalid_params("路径没有父目录"))?;
    let target = parent.join(&new_name);

    if target == source {
        return entry_value(root, &source);
    }
    if exists_no_follow(&target) {
        return Err(conflict(&new_name));
    }
    if !exists_no_follow(&source) {
        return Err(not_found(&display_path(root, &source)));
    }
    fs::rename(&source, &target).map_err(|e| io_error(&source, e))?;
    entry_value(root, &target)
}

/// 删除文件、目录或符号链接（目录递归）。
///
/// 符号链接只删链接本身；`rel` 为空（= 实例根目录）直接拒绝。
pub fn delete(root: &Path, rel: &str) -> RpcResult<Value> {
    let path = resolve(root, rel)?;
    if path == root {
        return Err(RpcError::invalid_params("不能删除实例根目录"));
    }
    let meta = match fs::symlink_metadata(&path) {
        Ok(meta) => meta,
        // 已经不在了：当成功，幂等
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Ok(json!({ "deleted": false, "path": display_path(root, &path) }));
        }
        Err(e) => return Err(io_error(&path, e)),
    };

    let result = if meta.file_type().is_symlink() || !meta.is_dir() {
        fs::remove_file(&path)
    } else {
        fs::remove_dir_all(&path)
    };
    result.map_err(|e| io_error(&path, e))?;
    Ok(json!({
        "deleted": true,
        "path": display_path(root, &path),
        "is_dir": meta.is_dir(),
    }))
}

/// 复制到 [dest_rel] 指向的目录，重名自动追加 ` (n)`。
pub fn copy(root: &Path, rel: &str, dest_rel: &str) -> RpcResult<Value> {
    let source = resolve(root, rel)?;
    let dest = resolve(root, dest_rel)?;
    ensure_dir(root, &dest)?;
    guard_not_into_self(&source, &dest)?;

    let name = file_name_of(&source)?;
    let target = unique_target(&dest, &name)?;
    copy_entity(&source, &target)?;
    entry_value(root, &target)
}

/// 移动到 [dest_rel] 指向的目录，重名报错。
pub fn move_entry(root: &Path, rel: &str, dest_rel: &str) -> RpcResult<Value> {
    let source = resolve(root, rel)?;
    let dest = resolve(root, dest_rel)?;
    ensure_dir(root, &dest)?;
    guard_not_into_self(&source, &dest)?;

    let name = file_name_of(&source)?;
    let target = dest.join(&name);
    if target == source {
        return entry_value(root, &source);
    }
    if exists_no_follow(&target) {
        return Err(conflict(&name));
    }
    if !exists_no_follow(&source) {
        return Err(not_found(&display_path(root, &source)));
    }

    match fs::rename(&source, &target) {
        Ok(()) => {}
        // 跨文件系统 rename 会失败（EXDEV）：退化成「复制后删除」，
        // 链接会被重建而不是跟随。
        Err(_) => {
            copy_entity(&source, &target)?;
            delete_path(&source)?;
        }
    }
    entry_value(root, &target)
}

// ══════════════════════════════════════════════════════════════════════════
// 归档
// ══════════════════════════════════════════════════════════════════════════

/// 把若干个条目压缩成一个归档，放进 [dest_rel] 目录，重名自动加后缀。
///
/// 输出格式由 [format] 定（zip / tar.gz / tar.xz / tar.zst）。输出名：给了
/// [name] 就用它（缺后缀会按格式补上、已有别的归档后缀会换掉）；否则单个源用
/// 「目录取全名、文件去扩展名」的规则，多个源用「压缩文件」。
pub fn compress(
    root: &Path,
    rels: &[String],
    dest_rel: &str,
    name: Option<&str>,
    format: archive::Format,
    limits: &Limits,
) -> RpcResult<Value> {
    if rels.is_empty() {
        return Err(RpcError::invalid_params("没有要压缩的条目"));
    }
    let dest = resolve(root, dest_rel)?;
    ensure_dir(root, &dest)?;

    let mut sources = Vec::with_capacity(rels.len());
    for rel in rels {
        sources.push(resolve(root, rel)?);
    }
    for source in &sources {
        if !exists_no_follow(source) {
            return Err(not_found(&display_path(root, source)));
        }
        // 压缩包落在被压缩的目录里会「自己包自己」，一路递归到爆
        guard_not_into_self(source, &dest)?;
    }

    let archive_name = archive::archive_name(&sources, name, format)?;
    let target = unique_target(&dest, &archive_name)?;
    archive::compress(&sources, &target, format, limits)?;
    entry_value(root, &target)
}

/// 解压任意支持的归档到 [dest_rel] 下以 [name] 命名的新子目录
/// （缺省用归档名去掉归档后缀）。
pub fn extract(
    root: &Path,
    rel: &str,
    dest_rel: &str,
    name: Option<&str>,
    limits: &Limits,
) -> RpcResult<Value> {
    let archive_path = resolve(root, rel)?;
    let dest = resolve(root, dest_rel)?;
    ensure_dir(root, &dest)?;

    let meta = fs::metadata(&archive_path).map_err(|e| io_error(&archive_path, e))?;
    if !meta.is_file() {
        return Err(RpcError::invalid_params(format!(
            "{} 不是文件",
            display_path(root, &archive_path)
        )));
    }

    let subfolder = match name.map(str::trim).filter(|n| !n.is_empty()) {
        Some(given) => given.to_string(),
        None => archive_base_name(&file_name_of(&archive_path)?),
    };
    let subfolder = validate_name(&subfolder)?;
    let target = unique_target(&dest, &subfolder)?;
    fs::create_dir_all(&target).map_err(|e| io_error(&target, e))?;

    let outcome = archive::extract(&archive_path, &target, limits);
    if let Err(e) = outcome {
        // 解到一半失败：把半成品收走，别留一堆看着像成功解压的文件
        let _ = fs::remove_dir_all(&target);
        return Err(e);
    }
    entry_value(root, &target)
}

// ══════════════════════════════════════════════════════════════════════════
// 下载（HTTP 层用）
// ══════════════════════════════════════════════════════════════════════════

/// 一次下载要发什么。
#[derive(Debug)]
pub enum Download {
    /// 单个文件，原样发。
    File {
        path: PathBuf,
        name: String,
        size: u64,
    },
    /// 目录，现打包成 zip 发（临时文件由 HTTP 层读完删掉）。
    Zip {
        archive: PathBuf,
        name: String,
        size: u64,
    },
}

/// 准备下载：文件直接给路径，目录先打一个临时 zip。
pub fn prepare_download(root: &Path, rel: &str, limits: &Limits) -> RpcResult<Download> {
    let path = resolve(root, rel)?;
    let meta = fs::metadata(&path).map_err(|e| io_error(&path, e))?;
    let name = if path == root {
        file_name_of(root).unwrap_or_else(|_| "instance".to_string())
    } else {
        file_name_of(&path)?
    };

    if meta.is_dir() {
        let archive = temp_download_path(&name);
        let sources = vec![path];
        archive::compress(&sources, &archive, archive::Format::Zip, limits)?;
        let download_name = if name.to_ascii_lowercase().ends_with(".zip") {
            name.clone()
        } else {
            format!("{name}.zip")
        };
        let size = fs::metadata(&archive).map(|m| m.len()).unwrap_or(0);
        return Ok(Download::Zip {
            archive,
            name: download_name,
            size,
        });
    }
    if !meta.is_file() {
        return Err(RpcError::invalid_params("只能下载文件或目录"));
    }
    Ok(Download::File {
        path,
        name,
        size: meta.len(),
    })
}

// ── 小工具 ─────────────────────────────────────────────────────────────────

/// 以 `followLinks: false` 判定「已存在」：**断链**也算存在，
/// 免得重名检测漏判、把链接覆盖掉。
fn exists_no_follow(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}

pub(super) fn file_name_of(path: &Path) -> RpcResult<String> {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .ok_or_else(|| RpcError::invalid_params(format!("{} 没有名字", path.display())))
}

/// [dest] 必须是已存在的目录。
fn ensure_dir(root: &Path, dest: &Path) -> RpcResult<()> {
    if dest.is_dir() {
        return Ok(());
    }
    Err(RpcError::invalid_params(format!(
        "{} 不是目录",
        display_path(root, dest)
    )))
}

/// 防止把目录移动/复制到它自身或其子目录里。
///
/// 符号链接不视为目录子树，可以自由移动（判定用 `followLinks: false` 的语义）。
fn guard_not_into_self(source: &Path, dest: &Path) -> RpcResult<()> {
    let meta = fs::symlink_metadata(source).map_err(|e| io_error(source, e))?;
    if !meta.is_dir() || meta.file_type().is_symlink() {
        return Ok(());
    }
    if dest == source || dest.starts_with(source) {
        return Err(RpcError::new(
            "file_invalid_destination",
            "不能把文件夹移动或复制到它自身内部。",
        ));
    }
    Ok(())
}

/// 在 [dir] 下为 [name] 找一个不冲突的名字，必要时追加 ` (n)`。
pub fn unique_target(dir: &Path, name: &str) -> RpcResult<PathBuf> {
    let candidate = dir.join(name);
    if !exists_no_follow(&candidate) {
        return Ok(candidate);
    }

    let (stem, ext) = split_name(name);
    for index in 1..10_000u32 {
        let candidate = dir.join(format!("{stem} ({index}){ext}"));
        if !exists_no_follow(&candidate) {
            return Ok(candidate);
        }
    }
    Err(RpcError::new(
        "file_exists",
        format!("`{name}` 的可用名字试了一万次都撞车，放弃"),
    ))
}

/// 拆 `名字` → `(主干, 扩展名含点)`，用于拼 ` (n)` 后缀。
fn split_name(name: &str) -> (String, String) {
    match name.rfind('.') {
        // 前导点（.env）不算扩展名
        Some(at) if at > 0 => (name[..at].to_string(), name[at..].to_string()),
        _ => (name.to_string(), String::new()),
    }
}

/// 去掉归档名的归档后缀（`.tar.gz` 这类复合后缀整体去掉），
/// 作为解压子目录的缺省名。名字只有一个后缀（`.zip`）时原样保留 ——
/// 去掉就成空串了，建不出目录。
fn archive_base_name(name: &str) -> String {
    match archive::matched_suffix(name) {
        Some(suffix) => {
            let stem = &name[..name.len() - suffix.len()];
            if stem.is_empty() {
                name.to_string()
            } else {
                stem.to_string()
            }
        }
        None => split_name(name).0,
    }
}

/// 删除链接/文件/目录（区分类型）。
fn delete_path(path: &Path) -> RpcResult<()> {
    let meta = fs::symlink_metadata(path).map_err(|e| io_error(path, e))?;
    let result = if meta.file_type().is_symlink() || !meta.is_dir() {
        fs::remove_file(path)
    } else {
        fs::remove_dir_all(path)
    };
    result.map_err(|e| io_error(path, e))
}

/// 递归复制：链接**重建**为指向同一目标的新链接，其余照抄。
fn copy_entity(source: &Path, target: &Path) -> RpcResult<()> {
    let meta = fs::symlink_metadata(source).map_err(|e| io_error(source, e))?;
    let file_type = meta.file_type();

    if file_type.is_symlink() {
        let link_target = fs::read_link(source).map_err(|e| io_error(source, e))?;
        return make_symlink(&link_target, target).map_err(|e| io_error(target, e));
    }
    if !file_type.is_dir() {
        fs::copy(source, target).map_err(|e| io_error(target, e))?;
        return Ok(());
    }

    fs::create_dir_all(target).map_err(|e| io_error(target, e))?;
    let mut stack = vec![(source.to_path_buf(), target.to_path_buf())];
    while let Some((from, to)) = stack.pop() {
        for item in fs::read_dir(&from)
            .map_err(|e| io_error(&from, e))?
            .flatten()
        {
            let child = item.path();
            let dest = to.join(item.file_name());
            let child_meta = fs::symlink_metadata(&child).map_err(|e| io_error(&child, e))?;
            let child_type = child_meta.file_type();
            if child_type.is_symlink() {
                let link_target = fs::read_link(&child).map_err(|e| io_error(&child, e))?;
                make_symlink(&link_target, &dest).map_err(|e| io_error(&dest, e))?;
            } else if child_type.is_dir() {
                fs::create_dir_all(&dest).map_err(|e| io_error(&dest, e))?;
                stack.push((child, dest));
            } else {
                fs::copy(&child, &dest).map_err(|e| io_error(&dest, e))?;
            }
        }
    }
    Ok(())
}

#[cfg(unix)]
fn make_symlink(target: &Path, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

#[cfg(windows)]
fn make_symlink(target: &Path, link: &Path) -> std::io::Result<()> {
    if target.is_dir() {
        std::os::windows::fs::symlink_dir(target, link)
    } else {
        std::os::windows::fs::symlink_file(target, link)
    }
}

/// 与 [target] 同目录的临时名（先写它再 rename，跨文件系统也不会失败）。
pub(crate) fn temp_sibling(target: &Path) -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let name = target
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "archive".to_string());
    let parent = target.parent().unwrap_or(Path::new("."));
    parent.join(format!(
        ".{name}.{}.{}.part",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ))
}

/// 下载目录时用的临时 zip 路径（放系统临时目录，读完就删）。
fn temp_download_path(name: &str) -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let (stem, _) = split_name(name);
    std::env::temp_dir().join(format!(
        "edgecube-dl-{}-{}-{}.zip",
        sanitize(&stem),
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ))
}

/// 把名字里不适合进文件名的字符换成 `_`（临时文件而已，不追求可读）。
fn sanitize(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "instance".to_string()
    } else {
        cleaned
    }
}

/// 上传落盘用的临时名（同目录，成功后再 rename 到最终名）。
pub fn upload_temp_name(dir: &Path) -> PathBuf {
    temp_sibling(&dir.join(format!("upload-{}", now_ms())))
}

// ══════════════════════════════════════════════════════════════════════════
// 测试：直接打同步层（不走 WS / HTTP，跑得快）
// ══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    use zip::write::SimpleFileOptions;
    use zip::{ZipArchive, ZipWriter};

    /// 一个临时实例目录；析构时清盘。
    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new(tag: &str) -> Self {
            use std::sync::atomic::{AtomicU64, Ordering};
            static SEQ: AtomicU64 = AtomicU64::new(0);
            let dir = std::env::temp_dir().join(format!(
                "edgecube-files-{tag}-{}-{}",
                std::process::id(),
                SEQ.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::create_dir_all(&dir).expect("应能建临时目录");
            Self(dir)
        }

        fn path(&self, rel: &str) -> PathBuf {
            self.0.join(rel)
        }

        fn write(&self, rel: &str, body: &str) {
            let path = self.path(rel);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(path, body).unwrap();
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn limits() -> Limits {
        Limits {
            text_max_bytes: 1024 * 1024,
            search_max: 100,
            archive_max_entries: 10_000,
        }
    }

    fn names_of(value: &Value) -> Vec<String> {
        value["entries"]
            .as_array()
            .expect("应有 entries")
            .iter()
            .map(|e| e["name"].as_str().unwrap().to_string())
            .collect()
    }

    fn paths_of(value: &Value) -> Vec<String> {
        value["entries"]
            .as_array()
            .expect("应有 entries")
            .iter()
            .map(|e| e["path"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn resolve_blocks_escape_and_normalizes() {
        let root = Path::new("/data/instances/abc");
        assert_eq!(resolve(root, "").unwrap(), root);
        assert_eq!(resolve(root, ".").unwrap(), root);
        assert_eq!(resolve(root, "a").unwrap(), root.join("a"));
        assert_eq!(resolve(root, "a//b/").unwrap(), root.join("a").join("b"));
        assert_eq!(resolve(root, "a\\b").unwrap(), root.join("a").join("b"));

        for bad in [
            "..",
            "../etc",
            "a/../../b",
            "a/..",
            "..\\x",
            "/../x",
            "/a",
            "\\a",
        ] {
            assert!(resolve(root, bad).is_err(), "`{bad}` 应当被拒绝");
        }
    }

    #[test]
    fn validate_name_rejects_separators() {
        assert_eq!(validate_name(" 笔记.txt ").unwrap(), "笔记.txt");
        for bad in ["", "   ", ".", "..", "a/b", "a\\b"] {
            assert!(validate_name(bad).is_err(), "`{bad}` 应当被拒绝");
        }
    }

    #[test]
    fn list_sorts_dirs_first_case_insensitive() {
        let temp = TempRoot::new("list");
        std::fs::create_dir_all(temp.path("zeta")).unwrap();
        std::fs::create_dir_all(temp.path("Alpha")).unwrap();
        temp.write("beta.txt", "b");
        temp.write("Yankee.txt", "y");

        let value = list(&temp.0, "").unwrap();
        assert_eq!(value["path"], "");
        assert_eq!(
            names_of(&value),
            vec!["Alpha", "zeta", "beta.txt", "Yankee.txt"]
        );
        assert_eq!(paths_of(&value)[2], "beta.txt");

        // 空目录 / 不存在的目录都是空列表，不报错
        assert!(names_of(&list(&temp.0, "Alpha").unwrap()).is_empty());
        assert!(names_of(&list(&temp.0, "nope").unwrap()).is_empty());
        // 但拿文件当目录查得出错
        assert!(list(&temp.0, "beta.txt").is_err());
    }

    #[test]
    fn list_reports_sizes_and_keeps_broken_links() {
        let temp = TempRoot::new("sizes");
        temp.write("a.bin", "0123456789");
        let value = list(&temp.0, "").unwrap();
        let entry = &value["entries"][0];
        assert_eq!(entry["size"], 10);
        assert_eq!(entry["is_dir"], false);
        assert_eq!(entry["is_link"], false);
        assert!(entry["modified_ms"].as_u64().is_some());
    }

    #[cfg(unix)]
    #[test]
    fn list_and_delete_treat_symlinks_specially() {
        let temp = TempRoot::new("links");
        std::fs::create_dir_all(temp.path("real")).unwrap();
        temp.write("real/inside.txt", "x");
        std::os::unix::fs::symlink("real", temp.path("link-dir")).unwrap();
        std::os::unix::fs::symlink("nowhere", temp.path("broken")).unwrap();

        let value = list(&temp.0, "").unwrap();
        let entries = value["entries"].as_array().unwrap();
        let link_dir = entries
            .iter()
            .find(|e| e["name"] == "link-dir")
            .expect("应有 link-dir");
        assert_eq!(link_dir["is_link"], true);
        assert_eq!(link_dir["is_dir"], true, "指向目录的链接可进入");
        assert_eq!(link_dir["link_target"], "real");

        let broken = entries
            .iter()
            .find(|e| e["name"] == "broken")
            .expect("应有 broken");
        assert_eq!(broken["is_dir"], false);
        assert_eq!(broken["size"], 0);
        assert_eq!(broken["link_target"], "nowhere");

        // 能进入链接指向的目录
        assert_eq!(
            names_of(&list(&temp.0, "link-dir").unwrap()),
            vec!["inside.txt"]
        );

        // 删链接只删链接，不碰目标
        delete(&temp.0, "link-dir").unwrap();
        assert!(temp.path("real").is_dir(), "目标目录必须还在");
        assert!(!exists_no_follow(&temp.path("link-dir")));

        // 断链也算「存在」，重名判定不能漏
        assert!(create_dir(&temp.0, "", "broken").is_err());
    }

    #[test]
    fn search_scope_follows_recursive_flag() {
        let temp = TempRoot::new("search");
        temp.write("mods/jei.jar", "");
        temp.write("mods/config/JEI.toml", "");
        temp.write("server.jar", "");

        // 非递归：只看当前目录的直接子项（所以从根找 mods 里的东西要先进去）
        assert!(names_of(&search(&temp.0, "", "jei", false, &limits()).unwrap()).is_empty());
        let flat = search(&temp.0, "mods", "jei", false, &limits()).unwrap();
        assert_eq!(names_of(&flat), vec!["jei.jar"]);
        assert_eq!(paths_of(&flat), vec!["mods/jei.jar"]);

        let deep = search(&temp.0, "", "jei", true, &limits()).unwrap();
        assert_eq!(names_of(&deep), vec!["jei.jar", "JEI.toml"]);
        assert_eq!(
            paths_of(&deep),
            vec!["mods/jei.jar", "mods/config/JEI.toml"]
        );

        // 空查询 = 空结果；搜目录名也能命中
        assert!(names_of(&search(&temp.0, "", "   ", true, &limits()).unwrap()).is_empty());
        assert_eq!(
            names_of(&search(&temp.0, "", "mods", false, &limits()).unwrap()),
            vec!["mods"]
        );
    }

    #[test]
    fn create_dir_and_file_conflict() {
        let temp = TempRoot::new("create");
        let dir = create_dir(&temp.0, "", "world").unwrap();
        assert_eq!(dir["entry"]["name"], "world");
        assert_eq!(dir["entry"]["is_dir"], true);
        let error = create_dir(&temp.0, "", "world").unwrap_err();
        assert_eq!(error.code, "file_exists");

        let file = create_file(&temp.0, "", "server.properties").unwrap();
        assert_eq!(file["entry"]["size"], 0);
        assert!(create_file(&temp.0, "", "server.properties").is_err());
        // 名字与已有目录撞车也要拦
        assert!(create_file(&temp.0, "", "world").is_err());
        // 建在不存在的父目录下 → 报错（不是悄悄建出一串目录）
        assert!(create_file(&temp.0, "nope", "x.txt").is_err());
    }

    #[test]
    fn rename_is_same_dir_and_checks_conflict() {
        let temp = TempRoot::new("rename");
        temp.write("old.txt", "hi");
        let value = rename(&temp.0, "old.txt", "new.txt").unwrap();
        assert_eq!(value["entry"]["name"], "new.txt");
        assert!(temp.path("new.txt").is_file());
        assert!(!temp.path("old.txt").exists());

        // 改成自己 → 无操作也算成功
        assert!(rename(&temp.0, "new.txt", "new.txt").is_ok());
        // 撞已有名字 → 报错
        temp.write("other.txt", "x");
        assert_eq!(
            rename(&temp.0, "new.txt", "other.txt").unwrap_err().code,
            "file_exists"
        );
        assert!(rename(&temp.0, "new.txt", "../escape").is_err());
        assert_eq!(
            rename(&temp.0, "missing.txt", "x.txt").unwrap_err().code,
            "file_not_found"
        );
    }

    #[test]
    fn copy_appends_number_suffix() {
        let temp = TempRoot::new("copy");
        std::fs::create_dir_all(temp.path("world/region")).unwrap();
        temp.write("world/level.dat", "data");
        temp.write("world (1).txt", "occupied"); // 只影响同名条目

        let first = copy(&temp.0, "world", "").unwrap();
        assert_eq!(first["entry"]["name"], "world (1)");
        assert!(temp.path("world (1)/level.dat").is_file());

        let second = copy(&temp.0, "world", "").unwrap();
        assert_eq!(second["entry"]["name"], "world (2)");

        temp.write("a.txt", "x");
        let copied = copy(&temp.0, "a.txt", "").unwrap();
        assert_eq!(copied["entry"]["name"], "a (1).txt");
    }

    #[cfg(unix)]
    #[test]
    fn copy_rebuilds_symlinks_instead_of_following() {
        let temp = TempRoot::new("copy-link");
        std::fs::create_dir_all(temp.path("real")).unwrap();
        temp.write("real/inside.txt", "x");
        std::os::unix::fs::symlink("real", temp.path("alias")).unwrap();

        std::fs::create_dir_all(temp.path("backup")).unwrap();
        copy(&temp.0, "alias", "backup").unwrap();
        let recreated = temp.path("backup/alias");
        assert!(
            std::fs::symlink_metadata(&recreated)
                .unwrap()
                .file_type()
                .is_symlink(),
            "链接应被重建"
        );
        assert_eq!(std::fs::read_link(&recreated).unwrap(), Path::new("real"));
    }

    #[test]
    fn copy_and_move_refuse_into_self() {
        let temp = TempRoot::new("self");
        std::fs::create_dir_all(temp.path("world/sub")).unwrap();
        temp.write("world/level.dat", "x");

        assert_eq!(
            copy(&temp.0, "world", "world").unwrap_err().code,
            "file_invalid_destination"
        );
        assert_eq!(
            copy(&temp.0, "world", "world/sub").unwrap_err().code,
            "file_invalid_destination"
        );
        assert_eq!(
            move_entry(&temp.0, "world", "world/sub").unwrap_err().code,
            "file_invalid_destination"
        );
        // 文件不受这条限制（只挡目录）
        temp.write("note.txt", "x");
        assert!(copy(&temp.0, "note.txt", "world").is_ok());
    }

    #[test]
    fn move_checks_conflict_and_works_across_dirs() {
        let temp = TempRoot::new("move");
        std::fs::create_dir_all(temp.path("backup")).unwrap();
        temp.write("world/level.dat", "x");

        let moved = move_entry(&temp.0, "world", "backup").unwrap();
        assert_eq!(moved["entry"]["path"], "backup/world");
        assert!(temp.path("backup/world/level.dat").is_file());
        assert!(!temp.path("world").exists());

        // 目标已有同名 → 报错，且源还在
        temp.write("keep.txt", "x");
        temp.write("backup/keep.txt", "y");
        assert_eq!(
            move_entry(&temp.0, "keep.txt", "backup").unwrap_err().code,
            "file_exists"
        );
        assert!(temp.path("keep.txt").is_file());
    }

    #[test]
    fn delete_recurses_but_never_the_instance_root() {
        let temp = TempRoot::new("delete");
        std::fs::create_dir_all(temp.path("world/region")).unwrap();
        temp.write("world/region/r.0.0.mca", "x");

        assert_eq!(delete(&temp.0, "world").unwrap()["deleted"], true);
        assert!(!temp.path("world").exists());
        // 删不存在的条目：幂等成功
        assert_eq!(delete(&temp.0, "world").unwrap()["deleted"], false);
        // 实例根目录拒绝
        assert!(delete(&temp.0, "").is_err());
        assert!(delete(&temp.0, ".").is_err());
    }

    #[test]
    fn read_and_write_text_round_trip() {
        let temp = TempRoot::new("text");
        temp.write("server.properties", "motd=你好\n");

        let read = read_text(&temp.0, "server.properties", false, &limits()).unwrap();
        assert_eq!(read["content"], "motd=你好\n");
        assert_eq!(read["encoding"], "utf-8");

        write_text(&temp.0, "server.properties", "motd=hello", &limits()).unwrap();
        assert_eq!(
            std::fs::read_to_string(temp.path("server.properties")).unwrap(),
            "motd=hello"
        );

        // 非 UTF-8：普通读报错，强制读按 latin1 兜底（一个字节一个字符）
        std::fs::write(temp.path("blob.dat"), [0xff, 0xfe, 0x41]).unwrap();
        let error = read_text(&temp.0, "blob.dat", false, &limits()).unwrap_err();
        assert_eq!(error.code, "file_not_utf8");
        let raw = read_text(&temp.0, "blob.dat", true, &limits()).unwrap();
        assert_eq!(raw["encoding"], "latin1");
        assert_eq!(raw["content"].as_str().unwrap().chars().count(), 3);

        // 目录不能当文本读/写
        std::fs::create_dir_all(temp.path("world")).unwrap();
        assert!(read_text(&temp.0, "world", false, &limits()).is_err());
        assert!(write_text(&temp.0, "world", "x", &limits()).is_err());
        // 不存在的文件不能凭空写出来（新建走 create）
        assert!(write_text(&temp.0, "new.txt", "x", &limits()).is_err());
    }

    #[test]
    fn text_limits_are_enforced() {
        let temp = TempRoot::new("text-limit");
        temp.write("big.txt", &"a".repeat(2048));
        let small = Limits {
            text_max_bytes: 1024,
            ..limits()
        };
        assert_eq!(
            read_text(&temp.0, "big.txt", false, &small)
                .unwrap_err()
                .code,
            "file_too_large"
        );
        assert_eq!(
            write_text(&temp.0, "big.txt", &"b".repeat(2048), &small)
                .unwrap_err()
                .code,
            "file_too_large"
        );
    }

    #[test]
    fn compress_single_file_strips_extension() {
        let temp = TempRoot::new("zip-file");
        temp.write("server.jar", "jar-bytes");

        // 压缩输出名规则：文件取 basenameWithoutExtension，所以是 server.zip
        let value = compress(
            &temp.0,
            &["server.jar".into()],
            "",
            None,
            archive::Format::Zip,
            &limits(),
        )
        .unwrap();
        assert_eq!(value["entry"]["name"], "server.zip");

        // 再压一次自动加序号
        let again = compress(
            &temp.0,
            &["server.jar".into()],
            "",
            None,
            archive::Format::Zip,
            &limits(),
        )
        .unwrap();
        assert_eq!(again["entry"]["name"], "server (1).zip");

        // 包里的名字是原文件名
        let file = std::fs::File::open(temp.path("server.zip")).unwrap();
        let mut zip = ZipArchive::new(file).unwrap();
        assert_eq!(zip.len(), 1);
        assert_eq!(zip.by_index(0).unwrap().name(), "server.jar");
    }

    #[test]
    fn compress_directory_keeps_name_and_extracts_back() {
        let temp = TempRoot::new("zip-dir");
        temp.write("world/level.dat", "level");
        temp.write("world/region/r.0.0.mca", "region");

        let value = compress(
            &temp.0,
            &["world".into()],
            "",
            None,
            archive::Format::Zip,
            &limits(),
        )
        .unwrap();
        assert_eq!(value["entry"]["name"], "world.zip");

        std::fs::remove_dir_all(temp.path("world")).unwrap();
        let extracted = extract(&temp.0, "world.zip", "", None, &limits()).unwrap();
        assert_eq!(extracted["entry"]["name"], "world");
        // 压缩时带了 `world/` 这个根条目，解压按条目名原样落盘，所以会再套一层
        // —— 这是刻意保留的行为，不在这里"修好"。
        assert_eq!(
            std::fs::read_to_string(temp.path("world/world/level.dat")).unwrap(),
            "level"
        );
        assert_eq!(
            std::fs::read_to_string(temp.path("world/world/region/r.0.0.mca")).unwrap(),
            "region"
        );
    }

    #[test]
    fn compress_many_uses_given_name_and_extract_honours_it() {
        let temp = TempRoot::new("zip-many");
        temp.write("a.txt", "a");
        temp.write("b.txt", "b");

        let value = compress(
            &temp.0,
            &["a.txt".into(), "b.txt".into()],
            "",
            Some("压缩文件"),
            archive::Format::Zip,
            &limits(),
        )
        .unwrap();
        assert_eq!(value["entry"]["name"], "压缩文件.zip");

        let extracted = extract(&temp.0, "压缩文件.zip", "", Some("解压结果"), &limits()).unwrap();
        assert_eq!(extracted["entry"]["name"], "解压结果");
        assert!(temp.path("解压结果/a.txt").is_file());
        assert!(temp.path("解压结果/b.txt").is_file());

        // 默认子目录名：复合扩展名整体去掉
        assert_eq!(archive_base_name("world.tar.gz"), "world");
        assert_eq!(archive_base_name("world.zip"), "world");
        assert_eq!(archive_base_name(".zip"), ".zip");
        // 短别名不能按规范后缀长度切（`.tgz` 是 4 个字、`.tar.gz` 是 7 个）
        assert_eq!(archive_base_name("world.tgz"), "world");
        assert_eq!(archive_base_name("world.txz"), "world");
        assert_eq!(archive_base_name("world.tbz2"), "world");
        assert_eq!(archive_base_name("world.tzst"), "world");
    }

    #[test]
    fn extract_blocks_zip_slip_and_reports_bad_archives() {
        let temp = TempRoot::new("zip-slip");
        // 手搓一个带 `..` 条目的压缩包
        let evil = temp.path("evil.zip");
        let file = std::fs::File::create(&evil).unwrap();
        let mut zip = ZipWriter::new(file);
        zip.start_file("../escape.txt", SimpleFileOptions::default())
            .unwrap();
        zip.write_all(b"gotcha").unwrap();
        zip.finish().unwrap();

        let error = extract(&temp.0, "evil.zip", "", None, &limits()).unwrap_err();
        assert_eq!(error.code, "file_archive");
        assert!(!temp.path("escape.txt").exists());
        assert!(!temp.0.join("../escape.txt").exists());
        // 半成品目录不该留下
        assert!(!temp.path("evil").exists());

        temp.write("not-a-zip.zip", "definitely not a zip");
        assert_eq!(
            extract(&temp.0, "not-a-zip.zip", "", None, &limits())
                .unwrap_err()
                .code,
            "file_archive"
        );
    }

    #[test]
    fn compress_round_trips_every_output_format() {
        for (format, suffix) in [
            (archive::Format::TarGz, "tar.gz"),
            (archive::Format::TarXz, "tar.xz"),
            (archive::Format::TarZst, "tar.zst"),
        ] {
            let temp = TempRoot::new(&format!("fmt-{suffix}"));
            temp.write("world/level.dat", "level");
            temp.write("world/region/r.0.0.mca", "region");

            let value = compress(&temp.0, &["world".into()], "", None, format, &limits()).unwrap();
            let name = format!("world.{suffix}");
            assert_eq!(value["entry"]["name"], name);

            std::fs::remove_dir_all(temp.path("world")).unwrap();
            extract(&temp.0, &name, "", None, &limits()).unwrap();
            assert_eq!(
                std::fs::read_to_string(temp.path("world/world/level.dat")).unwrap(),
                "level"
            );
            assert_eq!(
                std::fs::read_to_string(temp.path("world/world/region/r.0.0.mca")).unwrap(),
                "region"
            );
        }
    }

    #[test]
    fn compress_name_swaps_archive_suffix() {
        let temp = TempRoot::new("fmt-name");
        temp.write("a.txt", "a");

        // 用户手打了 `.zip`、又选了 tar.gz：后缀要换掉，而不是叠成 `.zip.tar.gz`
        let value = compress(
            &temp.0,
            &["a.txt".into()],
            "",
            Some("备份.zip"),
            archive::Format::TarGz,
            &limits(),
        )
        .unwrap();
        assert_eq!(value["entry"]["name"], "备份.tar.gz");
    }

    #[test]
    fn extract_handles_single_stream_formats() {
        let temp = TempRoot::new("single-stream");

        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all(b"hello").unwrap();
        std::fs::write(temp.path("note.txt.gz"), gz.finish().unwrap()).unwrap();

        let value = extract(&temp.0, "note.txt.gz", "", None, &limits()).unwrap();
        // 子目录名是归档名去掉 `.gz`，解出来的文件名同上去掉后缀后的名字
        assert_eq!(value["entry"]["name"], "note.txt");
        assert_eq!(
            std::fs::read_to_string(temp.path("note.txt/note.txt")).unwrap(),
            "hello"
        );
    }

    #[test]
    fn extract_blocks_tar_slip() {
        let temp = TempRoot::new("tar-slip");
        let file = std::fs::File::create(temp.path("evil.tar")).unwrap();
        let mut builder = tar::Builder::new(file);
        let mut header = tar::Header::new_gnu();
        header.set_size(6);
        header.set_mode(0o644);
        header.set_entry_type(tar::EntryType::Regular);
        // `set_path` 自己会拒绝 `..`，所以直接改 header 的 name 字段
        let name = b"../escape.txt";
        header.as_old_mut().name[..name.len()].copy_from_slice(name);
        header.set_cksum();
        builder.append(&header, &b"gotcha"[..]).unwrap();
        builder.into_inner().unwrap();

        let error = extract(&temp.0, "evil.tar", "", None, &limits()).unwrap_err();
        assert_eq!(error.code, "file_archive");
        assert!(!temp.0.join("../escape.txt").exists());
        assert!(!temp.path("evil").exists(), "半成品目录不该留下");
    }

    #[test]
    fn extract_reports_broken_archives_with_stable_code() {
        let temp = TempRoot::new("broken");

        for (file, suffix) in [
            ("bad.7z", "7z"),
            ("bad.rar", "rar"),
            ("bad.tar.gz", "tar.gz"),
            ("bad.zst", "zst"),
        ] {
            temp.write(file, "definitely not an archive");
            let error = extract(&temp.0, file, "", None, &limits()).unwrap_err();
            assert_eq!(error.code, "file_archive", "{suffix} 的错误码");
            assert!(
                !temp.path(&file[..file.len() - suffix.len() - 1]).exists(),
                "{suffix} 失败后不该留下半成品目录"
            );
        }
    }

    #[test]
    fn unique_target_handles_dotfiles_and_directories() {
        let temp = TempRoot::new("unique");
        temp.write(".env", "x");
        let target = unique_target(&temp.0, ".env").unwrap();
        assert_eq!(target.file_name().unwrap(), ".env (1)");

        // 空格目录：目标目录不存在 → 报错
        assert!(copy(&temp.0, ".env", "nope").is_err());
    }

    #[test]
    fn prepare_download_handles_file_and_directory() {
        let temp = TempRoot::new("download");
        temp.write("server.jar", "jar");
        match prepare_download(&temp.0, "server.jar", &limits()).unwrap() {
            Download::File { name, size, .. } => {
                assert_eq!(name, "server.jar");
                assert_eq!(size, 3);
            }
            other => panic!("应是文件下载，实际是 {other:?}"),
        }

        std::fs::create_dir_all(temp.path("world")).unwrap();
        temp.write("world/level.dat", "x");
        match prepare_download(&temp.0, "world", &limits()).unwrap() {
            Download::Zip {
                archive,
                name,
                size,
            } => {
                assert_eq!(name, "world.zip");
                assert!(size > 0);
                // 临时 zip 里应能读出那个文件
                let file = std::fs::File::open(&archive).unwrap();
                let mut zip = ZipArchive::new(file).unwrap();
                assert!(zip.by_name("world/level.dat").is_ok());
                let _ = std::fs::remove_file(&archive);
            }
            other => panic!("应是打包下载，实际是 {other:?}"),
        }

        assert!(prepare_download(&temp.0, "missing", &limits()).is_err());
    }
}
