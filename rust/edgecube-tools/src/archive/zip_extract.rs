//! zip 解压与 ecpkg 专用读取/提取。

use std::fs::File;
use std::io::Read;
use std::path::Path;
use zip::result::ZipError;

use super::safe::{canonicalize_joined, canonicalize_like_java, is_safe_rel, resolve_safe};
use super::{ArchError, Progress};

/// zip 条目解压到 `dest`；返回解压出的文件数（目录与被拒条目不计）。
pub fn extract_zip(archive: &Path, dest: &Path, progress: Progress) -> Result<i32, ArchError> {
    let base = canonicalize_like_java(dest);
    let file = File::open(archive).map_err(ArchError::io)?;
    let mut zip = zip::ZipArchive::new(file).map_err(ArchError::io)?;
    let mut count = 0i32;
    let mut current = 0i32;
    for index in 0..zip.len() {
        let mut entry = zip.by_index(index).map_err(ArchError::io)?;
        let name = entry.name().map_err(ArchError::io)?.into_owned();
        if entry.is_dir() {
            if let Some(target) = resolve_safe(&base, &name) {
                let _ = std::fs::create_dir_all(&target);
            }
            current += 1;
            progress(current, -1);
            continue;
        }
        let Some(target) = resolve_safe(&base, &name) else {
            continue;
        };
        if let Some(parent) = target.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let mut out = File::create(&target).map_err(ArchError::io)?;
        std::io::copy(&mut entry, &mut out).map_err(ArchError::io)?;
        count += 1;
        current += 1;
        progress(current, -1);
    }
    Ok(count)
}

/// 读取 zip 单条目为 UTF-8 文本；条目缺失抛
/// `IllegalArgumentException("ZIP 中缺少 <name>")`。非法序列按
/// 替换符处理（等价 Kotlin `readBytes().toString(UTF_8)`）。
pub fn read_entry(archive: &Path, entry_name: &str) -> Result<String, ArchError> {
    let file = File::open(archive).map_err(ArchError::io)?;
    let mut zip = zip::ZipArchive::new(file).map_err(ArchError::io)?;
    let mut entry = zip.by_name(entry_name).map_err(|error| match error {
        ZipError::FileNotFound => ArchError::Arg(format!("ZIP 中缺少 {entry_name}")),
        other => ArchError::io(other),
    })?;
    let mut buf = Vec::new();
    entry.read_to_end(&mut buf).map_err(ArchError::io)?;
    Ok(String::from_utf8_lossy(&buf).into_owned())
}

/// ZIP 中是否存在以 `dir/` 为前缀的任意条目（目录存在性检查）。
pub fn has_dir_prefix(archive: &Path, dir: &str) -> Result<bool, ArchError> {
    let file = File::open(archive).map_err(ArchError::io)?;
    let zip = zip::ZipArchive::new(file).map_err(ArchError::io)?;
    let prefix = format!("{dir}/");
    for index in 0..zip.len() {
        if let Some(Ok(name)) = zip.name_for_index(index)
            && name.starts_with(&prefix)
        {
            return Ok(true);
        }
    }
    Ok(false)
}

/// ecpkg 双前缀提取：先 `universalDir` 后 `archDir`（后者覆盖同名文件），
/// 前缀剥离后写入 `dest`。返回 `(processed, total)`；条目逃逸抛
/// `SecurityException`（消息与原实现逐字一致）。
pub fn extract_prefixes(
    archive: &Path,
    dest: &Path,
    universal_dir: Option<&str>,
    arch_dir: &str,
) -> Result<(i32, i32), ArchError> {
    let file = File::open(archive).map_err(ArchError::io)?;
    let mut zip = zip::ZipArchive::new(file).map_err(ArchError::io)?;
    let names: Vec<String> = (0..zip.len())
        .filter_map(|index| zip.name_for_index(index)?.ok().map(|n| n.into_owned()))
        .collect();
    let dest_canon = canonicalize_like_java(dest);
    let total = names.len() as i32;
    let mut processed = 0i32;

    if let Some(universal_dir) = universal_dir {
        let prefix = format!("{universal_dir}/");
        for name in &names {
            if !name.starts_with(&prefix) {
                continue;
            }
            extract_entry(&mut zip, name, &prefix, dest, &dest_canon)?;
            processed += 1;
        }
    }
    let prefix = format!("{arch_dir}/");
    for name in &names {
        if !name.starts_with(&prefix) {
            continue;
        }
        extract_entry(&mut zip, name, &prefix, dest, &dest_canon)?;
        processed += 1;
    }
    Ok((processed, total))
}

/// 提取单个 zip 条目到目标目录（剥离 `prefix`），对齐原
/// `RuntimeInstaller.extractEntry`：空相对路径跳过、路径逃逸抛
/// `SecurityException`、UNIX 符号链接按内容创建并校验目标不逃逸。
fn extract_entry(
    zip: &mut zip::ZipArchive<File>,
    name: &str,
    prefix: &str,
    dest: &Path,
    dest_canon: &Path,
) -> Result<(), ArchError> {
    let rel = name.strip_prefix(prefix).unwrap_or(name);
    if rel.is_empty() {
        return Ok(());
    }
    if !is_safe_rel(rel) {
        return Err(ArchError::Security(format!("非法路径：{name}")));
    }
    let target = dest.join(rel);
    let mut entry = zip.by_name(name).map_err(ArchError::io)?;

    if entry.is_symlink() {
        if let Some(parent) = target.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::remove_file(&target);
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf).map_err(ArchError::io)?;
        let link_target = String::from_utf8_lossy(&buf).into_owned();
        let parent = target.parent().unwrap_or(dest);
        let resolved = canonicalize_joined(parent, &link_target);
        let dest_prefix = dest_canon.to_string_lossy();
        if !resolved.to_string_lossy().starts_with(&*dest_prefix) {
            return Err(ArchError::Security(format!(
                "符号链接目标逃逸：{name} -> {link_target}"
            )));
        }
        let _ = std::os::unix::fs::symlink(&link_target, &target);
        return Ok(());
    }

    if entry.is_dir() {
        let _ = std::fs::create_dir_all(&target);
        return Ok(());
    }
    if let Some(parent) = target.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let mut out = File::create(&target).map_err(ArchError::io)?;
    std::io::copy(&mut entry, &mut out).map_err(ArchError::io)?;
    Ok(())
}
