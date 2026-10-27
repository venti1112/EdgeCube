//! 归档读写。
//!
//! 解压认的格式与 V1 一致：zip、tar 家族（gz/xz/bz2/zst/lz4）、7z、rar，
//! 以及单文件压缩流（gz/xz/bz2/zst/lz4）。压缩出四种：zip / tar.gz / tar.xz / tar.zst。
//!
//! 各格式的实现都在子模块里，这里只做三件事：按文件名探格式、把解压结果落到
//! 一个新目录、按格式把源条目写出去。
//!
//! 条目路径一律过 [`entry_target`]：归档是**不可信输入**，`../` 或绝对路径
//! 就能把文件写到实例目录外面去。

mod rar;
mod sevenz;
mod single;
mod tar;
mod zip;

use std::fs;
use std::path::{Path, PathBuf};

use crate::error::{RpcError, RpcResult};

use super::files::{self, Limits};

/// 归档格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Zip,
    /// 裸 tar（不压缩）。
    Tar,
    TarGz,
    TarXz,
    TarBz2,
    TarZst,
    TarLz4,
    SevenZ,
    Rar,
    /// 以下是单文件压缩流，解出来只有一个文件。
    Gz,
    Xz,
    Bz2,
    Zst,
    Lz4,
}

impl Format {
    /// 拼接归档名用的后缀。
    pub fn suffix(self) -> &'static str {
        match self {
            Format::Zip => ".zip",
            Format::Tar => ".tar",
            Format::TarGz => ".tar.gz",
            Format::TarXz => ".tar.xz",
            Format::TarBz2 => ".tar.bz2",
            Format::TarZst => ".tar.zst",
            Format::TarLz4 => ".tar.lz4",
            Format::SevenZ => ".7z",
            Format::Rar => ".rar",
            Format::Gz => ".gz",
            Format::Xz => ".xz",
            Format::Bz2 => ".bz2",
            Format::Zst => ".zst",
            Format::Lz4 => ".lz4",
        }
    }

    /// 报错文案里的名字。
    pub fn label(self) -> &'static str {
        self.suffix().trim_start_matches('.')
    }
}

/// 全部认得的后缀，**按长度降序**（`.tar.gz` 必须先于 `.gz` 命中）。
const SUFFIXES: &[(&str, Format)] = &[
    (".tar.bz2", Format::TarBz2),
    (".tar.lz4", Format::TarLz4),
    (".tar.zst", Format::TarZst),
    (".tar.gz", Format::TarGz),
    (".tar.xz", Format::TarXz),
    (".tbz2", Format::TarBz2),
    (".tzst", Format::TarZst),
    (".tgz", Format::TarGz),
    (".txz", Format::TarXz),
    (".tar", Format::Tar),
    (".zip", Format::Zip),
    (".7z", Format::SevenZ),
    (".rar", Format::Rar),
    (".bz2", Format::Bz2),
    (".zst", Format::Zst),
    (".lz4", Format::Lz4),
    (".gz", Format::Gz),
    (".xz", Format::Xz),
];

/// 按文件名探格式；不认得的返回 `None`。
pub fn detect(name: &str) -> Option<Format> {
    let lower = name.to_ascii_lowercase();
    SUFFIXES
        .iter()
        .find(|(suffix, _)| lower.ends_with(suffix))
        .map(|(_, format)| *format)
}

/// 文件名**实际命中**的那个后缀（`.tgz` 就返回 `.tgz`，不是规范化的 `.tar.gz`）。
///
/// 剥后缀必须用它：短别名与规范后缀长度不同，按 `Format::suffix()` 切片会算错。
/// 这里**不 trim** —— 名字前后真有空格也是文件名的一部分，切片要按原串来。
pub fn matched_suffix(name: &str) -> Option<&'static str> {
    let lower = name.to_ascii_lowercase();
    SUFFIXES
        .iter()
        .find(|(suffix, _)| lower.ends_with(suffix))
        .map(|(suffix, _)| *suffix)
}

/// 压缩输出格式：只认这四种（裸 tar 只用于解压）。
///
/// 空串按 zip —— 老客户端不带这个参数时行为不变。
pub fn parse_compress_format(raw: &str) -> RpcResult<Format> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "" | "zip" => Ok(Format::Zip),
        "tar.gz" | "tgz" => Ok(Format::TarGz),
        "tar.xz" | "txz" => Ok(Format::TarXz),
        "tar.zst" | "tzst" => Ok(Format::TarZst),
        other => Err(RpcError::invalid_params(format!(
            "不支持的压缩格式 `{other}`，可选：zip / tar.gz / tar.xz / tar.zst"
        ))),
    }
}

/// 解压 [archive] 到 [target]（`target` 由调用方建好，是个空目录）。
pub fn extract(archive: &Path, target: &Path, limits: &Limits) -> RpcResult<()> {
    let name = archive
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let Some(format) = detect(&name) else {
        return Err(RpcError::new(
            "file_archive",
            format!("不支持的归档格式：{name}"),
        ));
    };

    match format {
        Format::Zip => zip::extract(archive, target, limits),
        Format::Tar => {
            let file = open(archive)?;
            tar::extract(file, target, limits)
        }
        Format::TarGz => {
            let file = open(archive)?;
            tar::extract(flate2::read::GzDecoder::new(file), target, limits)
        }
        Format::TarXz => {
            let file = open(archive)?;
            tar::extract(xz2::read::XzDecoder::new(file), target, limits)
        }
        Format::TarBz2 => {
            let file = open(archive)?;
            tar::extract(bzip2::read::BzDecoder::new(file), target, limits)
        }
        Format::TarZst => {
            let file = open(archive)?;
            let decoder =
                zstd::stream::read::Decoder::new(file).map_err(|e| files::io_error(archive, e))?;
            tar::extract(decoder, target, limits)
        }
        Format::TarLz4 => {
            let file = open(archive)?;
            tar::extract(lz4_flex::frame::FrameDecoder::new(file), target, limits)
        }
        Format::SevenZ => sevenz::extract(archive, target, limits),
        Format::Rar => rar::extract(archive, target, limits),
        Format::Gz => {
            let file = open(archive)?;
            single::extract(
                flate2::read::GzDecoder::new(file),
                target,
                &strip_suffix(&name, ".gz"),
            )
        }
        Format::Xz => {
            let file = open(archive)?;
            single::extract(
                xz2::read::XzDecoder::new(file),
                target,
                &strip_suffix(&name, ".xz"),
            )
        }
        Format::Bz2 => {
            let file = open(archive)?;
            single::extract(
                bzip2::read::BzDecoder::new(file),
                target,
                &strip_suffix(&name, ".bz2"),
            )
        }
        Format::Zst => {
            let file = open(archive)?;
            let decoder =
                zstd::stream::read::Decoder::new(file).map_err(|e| files::io_error(archive, e))?;
            single::extract(decoder, target, &strip_suffix(&name, ".zst"))
        }
        Format::Lz4 => {
            let file = open(archive)?;
            single::extract(
                lz4_flex::frame::FrameDecoder::new(file),
                target,
                &strip_suffix(&name, ".lz4"),
            )
        }
    }
}

/// 把 [sources] 按 [format] 打进 [target]（调用方保证 `target` 不存在）。
pub fn compress(
    sources: &[PathBuf],
    target: &Path,
    format: Format,
    limits: &Limits,
) -> RpcResult<()> {
    let outcome = match format {
        Format::Zip => zip::write(sources, target, limits),
        Format::TarGz => tar::write(sources, target, tar::Encoder::Gz, limits),
        Format::TarXz => tar::write(sources, target, tar::Encoder::Xz, limits),
        Format::TarZst => tar::write(sources, target, tar::Encoder::Zstd, limits),
        other => Err(RpcError::invalid_params(format!(
            "`{}` 只能解压，不能作为压缩输出格式",
            other.label()
        ))),
    };
    if outcome.is_err() {
        // 半成品不能留：它看起来像个正常压缩包
        let _ = fs::remove_file(target);
    }
    outcome
}

/// 生成压缩包的名字：用户给了就用它（缺后缀补上、已有别的归档后缀则换掉），
/// 没给就按源条目推。
pub fn archive_name(sources: &[PathBuf], given: Option<&str>, format: Format) -> RpcResult<String> {
    let base = match given.map(str::trim).filter(|name| !name.is_empty()) {
        Some(name) => strip_known_suffix(name),
        None if sources.len() == 1 => default_base_name(&sources[0])?,
        None => "压缩文件".to_string(),
    };
    files::validate_name(&format!("{base}{}", format.suffix()))
}

/// 去掉名字末尾任何认得的归档后缀（用户可能在输入框里手打了 `.zip`）。
fn strip_known_suffix(name: &str) -> String {
    let lower = name.to_ascii_lowercase();
    for (suffix, _) in SUFFIXES {
        if lower.ends_with(suffix) {
            return name[..name.len() - suffix.len()].to_string();
        }
    }
    name.to_string()
}

/// 单个源条目的缺省包名：目录取全名，文件去扩展名。
fn default_base_name(source: &Path) -> RpcResult<String> {
    let name = source
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .ok_or_else(|| RpcError::new("file_archive", "无法从路径推出压缩包名"))?;
    if source.is_dir() {
        return Ok(name);
    }
    let (stem, _) = split_last_extension(&name);
    Ok(stem)
}

fn split_last_extension(name: &str) -> (String, String) {
    match name.rfind('.') {
        Some(index) if index > 0 => (name[..index].to_string(), name[index..].to_string()),
        _ => (name.to_string(), String::new()),
    }
}

fn strip_suffix(name: &str, suffix: &str) -> String {
    if name.to_ascii_lowercase().ends_with(suffix) {
        name[..name.len() - suffix.len()].to_string()
    } else {
        name.to_string()
    }
}

fn open(path: &Path) -> RpcResult<fs::File> {
    fs::File::open(path).map_err(|e| files::io_error(path, e))
}

/// 归档条目名 → 目标绝对路径。
///
/// 判据：绝对路径直接拒绝；`..` 逐段弹栈，弹空说明想跑出 `base`，拒绝。
/// `foo/../bar` 这种「绕一圈又回原地」的写法允许（等价于 `bar`），
/// 与 zip 的 `enclosed_name()` 一致。
pub(super) fn entry_target(base: &Path, name: &str) -> RpcResult<PathBuf> {
    let normalized = name.replace('\\', "/");
    if normalized.starts_with('/') {
        return Err(bad_entry(name));
    }

    let mut parts: Vec<&str> = Vec::new();
    for part in normalized.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if parts.pop().is_none() {
                    return Err(bad_entry(name));
                }
            }
            other => parts.push(other),
        }
    }

    let Some(first) = parts.first() else {
        return Err(bad_entry(name));
    };
    // Windows 的盘符（`C:`）会被 `Path::join` 当成前缀，必须在入口挡掉
    if first.as_bytes().get(1) == Some(&b':') {
        return Err(bad_entry(name));
    }

    let mut out = base.to_path_buf();
    for part in parts {
        out.push(part);
    }
    Ok(out)
}

fn bad_entry(name: &str) -> RpcError {
    RpcError::new("file_archive", format!("压缩包含有非法路径的条目：{name}"))
}

/// 条目数上限检查（各格式共用）。
pub(super) fn check_entries(count: u64, limits: &Limits) -> RpcResult<()> {
    if count > limits.archive_max_entries.max(1) {
        return Err(RpcError::new(
            "file_archive",
            format!("压缩包条目数超出上限（{}）", limits.archive_max_entries),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_prefers_compound_suffixes() {
        assert_eq!(detect("a.tar.gz"), Some(Format::TarGz));
        assert_eq!(detect("a.TAR.GZ"), Some(Format::TarGz));
        assert_eq!(detect("a.tgz"), Some(Format::TarGz));
        assert_eq!(detect("a.tar.xz"), Some(Format::TarXz));
        assert_eq!(detect("a.tar.bz2"), Some(Format::TarBz2));
        assert_eq!(detect("a.tar.zst"), Some(Format::TarZst));
        assert_eq!(detect("a.tar.lz4"), Some(Format::TarLz4));
        assert_eq!(detect("a.tar"), Some(Format::Tar));
        assert_eq!(detect("a.gz"), Some(Format::Gz));
        assert_eq!(detect("a.7z"), Some(Format::SevenZ));
        assert_eq!(detect("a.rar"), Some(Format::Rar));
        assert_eq!(detect("a.txt"), None);
    }

    #[test]
    fn entry_target_rejects_escapes() {
        let base = Path::new("/tmp/base");
        assert!(entry_target(base, "../evil").is_err());
        assert!(entry_target(base, "/etc/passwd").is_err());
        assert!(entry_target(base, "a/../../evil").is_err());
        assert!(entry_target(base, "C:/windows").is_err());
        assert!(entry_target(base, "").is_err());
        assert_eq!(
            entry_target(base, "a/../b.txt").unwrap(),
            base.join("b.txt")
        );
        assert_eq!(
            entry_target(base, "./a\\b.txt").unwrap(),
            base.join("a/b.txt")
        );
    }

    #[test]
    fn archive_name_swaps_known_suffix() {
        let format = Format::TarGz;
        assert_eq!(
            archive_name(&[], Some("备份.zip"), format).unwrap(),
            "备份.tar.gz"
        );
        assert_eq!(
            archive_name(&[], Some("备份"), format).unwrap(),
            "备份.tar.gz"
        );
    }
}
