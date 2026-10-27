//! tar 及 tar.* 的读写。
//!
//! 解压端只认目录与普通文件：符号链接、硬链接、设备文件一律跳过 ——
//! 归档是外部输入，先造一条指向 `/etc` 的链接、再往里写文件，等于绕开
//! 路径校验；「跳过」比「按普通文件写出」更干净。
//!
//! 压缩端跟随符号链接（与 zip 那边一致），并用 `visited` + 限深防环。

use std::collections::BTreeSet;
use std::fs;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::error::{RpcError, RpcResult};

use super::super::files::{self, Limits, temp_sibling};
use super::{check_entries, entry_target};

/// 目录递归的层数上限（防符号链接套娃）。
const MAX_DEPTH: usize = 32;

/// 压缩时套在 tar 外面的编码器。
#[derive(Debug, Clone, Copy)]
pub enum Encoder {
    Gz,
    Xz,
    Zstd,
}

fn tar_err(context: &str, error: impl std::fmt::Display) -> RpcError {
    RpcError::new("file_archive", format!("{context}：{error}"))
}

/// 顺序读 tar（`reader` 可为裸 tar 或任一压缩流解码器）。
pub fn extract<R: std::io::Read>(reader: R, target: &Path, limits: &Limits) -> RpcResult<()> {
    let mut archive = tar::Archive::new(reader);
    let mut count = 0u64;

    for entry in archive
        .entries()
        .map_err(|e| tar_err("不是有效的 tar 归档", e))?
    {
        let mut entry = entry.map_err(|e| tar_err("读取 tar 条目失败", e))?;
        count += 1;
        check_entries(count, limits)?;

        let name = String::from_utf8_lossy(&entry.path_bytes()).into_owned();
        let out = entry_target(target, &name)?;
        let kind = entry.header().entry_type();

        if kind.is_dir() {
            fs::create_dir_all(&out).map_err(|e| files::io_error(&out, e))?;
            continue;
        }
        if !kind.is_file() {
            // 链接类条目直接跳过，见模块注释
            continue;
        }
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent).map_err(|e| files::io_error(parent, e))?;
        }
        let mut sink = fs::File::create(&out).map_err(|e| files::io_error(&out, e))?;
        std::io::copy(&mut entry, &mut sink).map_err(|e| files::io_error(&out, e))?;
    }
    Ok(())
}

/// 把 [sources] 打成 tar（外面按 [encoder] 压）。
pub fn write(
    sources: &[PathBuf],
    target: &Path,
    encoder: Encoder,
    limits: &Limits,
) -> RpcResult<()> {
    let tmp = temp_sibling(target);
    let result = (|| -> RpcResult<()> {
        let file = fs::File::create(&tmp).map_err(|e| files::io_error(&tmp, e))?;
        let writer = BufWriter::new(file);

        match encoder {
            Encoder::Gz => {
                let wrapped = flate2::write::GzEncoder::new(writer, flate2::Compression::default());
                let mut out = write_tar(sources, wrapped, limits)?
                    .finish()
                    .map_err(|e| tar_err("写入 tar.gz 失败", e))?;
                out.flush().map_err(|e| files::io_error(&tmp, e))?;
            }
            Encoder::Xz => {
                let wrapped = xz2::write::XzEncoder::new(writer, 6);
                let mut out = write_tar(sources, wrapped, limits)?
                    .finish()
                    .map_err(|e| tar_err("写入 tar.xz 失败", e))?;
                out.flush().map_err(|e| files::io_error(&tmp, e))?;
            }
            Encoder::Zstd => {
                let wrapped = zstd::stream::write::Encoder::new(writer, 3)
                    .map_err(|e| tar_err("初始化 zstd 编码器失败", e))?;
                let mut out = write_tar(sources, wrapped, limits)?
                    .finish()
                    .map_err(|e| tar_err("写入 tar.zst 失败", e))?;
                out.flush().map_err(|e| files::io_error(&tmp, e))?;
            }
        }
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

/// 写 tar 本体，返回底层 writer（交给调用方 finish 编码器）。
fn write_tar<W: Write>(sources: &[PathBuf], writer: W, limits: &Limits) -> RpcResult<W> {
    let mut builder = tar::Builder::new(writer);
    let mut budget = limits.archive_max_entries.max(1);
    let mut visited = BTreeSet::new();

    for source in sources {
        let name = files::file_name_of(source)?;
        add_path(&mut builder, source, &name, &mut budget, &mut visited, 0)?;
    }

    builder
        .into_inner()
        .map_err(|e| tar_err("写入 tar 失败", e))
}

fn add_path<W: Write>(
    builder: &mut tar::Builder<W>,
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

    // `metadata` 跟随符号链接：与 zip 那边「链接到目录也当目录打包」一致
    let meta = fs::metadata(source).map_err(|e| files::io_error(source, e))?;
    if meta.is_dir() {
        let real = fs::canonicalize(source).unwrap_or_else(|_| source.to_path_buf());
        if !visited.insert(real) {
            return Ok(());
        }
        // tar 用 header 的 entry_type 标记目录，名字不用带尾斜杠
        builder
            .append_dir(name, source)
            .map_err(|e| tar_err("写入目录条目失败", e))?;
        for item in fs::read_dir(source)
            .map_err(|e| files::io_error(source, e))?
            .flatten()
        {
            let child = item.path();
            let child_name = item.file_name().to_string_lossy().into_owned();
            add_path(
                builder,
                &child,
                &format!("{name}/{child_name}"),
                budget,
                visited,
                depth + 1,
            )?;
        }
        return Ok(());
    }

    builder
        .append_path_with_name(source, name)
        .map_err(|e| tar_err("写入文件条目失败", e))?;
    Ok(())
}
