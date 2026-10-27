//! zip 读写。
//!
//! 写入沿用了原来 `files.rs` 里的一套：先写同目录的 `.part` 再 rename，
//! 中途失败不会留半个包；目录递归时**跟随符号链接**，但记住进过的真实目录
//! 并限深，免得自引用链接把磁盘写满。
//!
//! 解压用 zip crate 自己的 `enclosed_name()` 挡路径穿越。

use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

use crate::error::{RpcError, RpcResult};

use super::super::files::{self, Limits, temp_sibling};
use super::check_entries;

/// 目录递归的层数上限（防符号链接套娃）。
const MAX_DEPTH: usize = 32;

/// zip 里压缩方式固定用 deflate。
fn options() -> SimpleFileOptions {
    SimpleFileOptions::default().compression_method(CompressionMethod::Deflated)
}

fn zip_err(context: &str, error: impl std::fmt::Display) -> RpcError {
    RpcError::new("file_archive", format!("{context}：{error}"))
}

/// 解压 zip 到 [target]。
///
/// 挡住「压缩炸弹」式的路径穿越（`../` 与绝对路径条目）—— 用 zip 自己
/// 的 `enclosed_name()` 判定，它对不安全的名字返回 `None`。
/// 归档里的「符号链接条目」按普通文件写出（内容即链接目标字符串），
/// 免得解压动作凭空在磁盘上造出一堆指向别处的链接。
pub fn extract(archive: &Path, target: &Path, limits: &Limits) -> RpcResult<()> {
    let file = fs::File::open(archive).map_err(|e| files::io_error(archive, e))?;
    let mut zip = ZipArchive::new(file).map_err(|e| zip_err("不是有效的 zip 压缩包", e))?;

    check_entries(zip.len() as u64, limits)?;

    for index in 0..zip.len() {
        let mut item = zip
            .by_index(index)
            .map_err(|e| zip_err("读取压缩包条目失败", e))?;

        let Some(relative) = item.enclosed_name() else {
            return Err(RpcError::new(
                "file_archive",
                format!("压缩包含有非法路径的条目：{}", item.name()),
            ));
        };
        let out = target.join(&relative);

        if item.is_dir() {
            fs::create_dir_all(&out).map_err(|e| files::io_error(&out, e))?;
            continue;
        }
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent).map_err(|e| files::io_error(parent, e))?;
        }
        let mut sink = fs::File::create(&out).map_err(|e| files::io_error(&out, e))?;
        std::io::copy(&mut item, &mut sink).map_err(|e| files::io_error(&out, e))?;
    }
    Ok(())
}

/// 把 [sources] 打进 [target]。
pub fn write(sources: &[PathBuf], target: &Path, limits: &Limits) -> RpcResult<()> {
    let tmp = temp_sibling(target);
    let result = (|| -> RpcResult<()> {
        let file = fs::File::create(&tmp).map_err(|e| files::io_error(&tmp, e))?;
        let mut zip = ZipWriter::new(file);
        let mut budget = limits.archive_max_entries.max(1);

        for source in sources {
            let name = files::file_name_of(source)?;
            let mut visited = BTreeSet::new();
            add_to_zip(&mut zip, source, &name, &mut budget, &mut visited, 0)?;
        }
        zip.finish().map_err(|e| zip_err("写入压缩包失败", e))?;
        Ok(())
    })();

    match result {
        Ok(()) => {
            fs::rename(&tmp, target).map_err(|e| files::io_error(target, e))?;
            Ok(())
        }
        Err(e) => {
            let _ = fs::remove_file(&tmp);
            Err(e)
        }
    }
}

/// 递归收条目进 zip。
///
/// 目录里的符号链接**跟随**，但用 `visited` 记住已经进过的目录、并限深，
/// 避免自引用链接把磁盘写满。
fn add_to_zip<W: Write + std::io::Seek>(
    zip: &mut ZipWriter<W>,
    source: &Path,
    name: &str,
    budget: &mut u64,
    visited: &mut BTreeSet<PathBuf>,
    depth: usize,
) -> RpcResult<()> {
    if depth > MAX_DEPTH {
        return Err(RpcError::new(
            "file_archive",
            format!("目录层级过深，可能是符号链接成环：{name}"),
        ));
    }
    if *budget == 0 {
        return Err(RpcError::new("file_archive", "归档条目数超出上限，已中止"));
    }
    *budget -= 1;

    let meta = fs::metadata(source).map_err(|e| files::io_error(source, e))?;
    if meta.is_dir() {
        // 同一层目录只进一次（符号链接指回上层时靠它断路）
        let real = fs::canonicalize(source).unwrap_or_else(|_| source.to_path_buf());
        if !visited.insert(real) {
            return Ok(());
        }
        let dir_name = format!("{}/", name.trim_end_matches('/'));
        zip.add_directory(&dir_name, options())
            .map_err(|e| zip_err("写入目录条目失败", e))?;
        for item in fs::read_dir(source)
            .map_err(|e| files::io_error(source, e))?
            .flatten()
        {
            let child = item.path();
            let child_name = item.file_name().to_string_lossy().into_owned();
            add_to_zip(
                zip,
                &child,
                &format!("{dir_name}{child_name}"),
                budget,
                visited,
                depth + 1,
            )?;
        }
        return Ok(());
    }

    zip.start_file(name, options())
        .map_err(|e| zip_err("写入压缩包条目失败", e))?;
    let mut file = fs::File::open(source).map_err(|e| files::io_error(source, e))?;
    std::io::copy(&mut file, zip).map_err(|e| files::io_error(source, e))?;
    Ok(())
}
