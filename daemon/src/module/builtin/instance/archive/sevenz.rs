//! 7z 解压（纯 Rust，`sevenz-rust2`）。

use std::fs;
use std::path::Path;

use sevenz_rust2::{ArchiveReader, Password};

use crate::error::{RpcError, RpcResult};

use super::super::files::{self, Limits};
use super::{check_entries, entry_target};

fn sevenz_err(context: &str, error: impl std::fmt::Display) -> RpcError {
    RpcError::new("file_archive", format!("{context}：{error}"))
}

/// 解压 7z。逐条目回调里拿不到 `RpcResult`，所以用 `failure` 槽把错误带出来
/// （`for_each_entries` 只认自己的错误类型）。
pub fn extract(archive: &Path, target: &Path, limits: &Limits) -> RpcResult<()> {
    let mut reader = ArchiveReader::open(archive, Password::empty())
        .map_err(|e| sevenz_err("不是有效的 7z 归档", e))?;

    let mut count = 0u64;
    let mut failure: Option<RpcError> = None;

    let walked = reader.for_each_entries(|entry, data| {
        if failure.is_some() {
            return Ok(false);
        }

        count += 1;
        if let Err(e) = check_entries(count, limits) {
            failure = Some(e);
            return Ok(false);
        }

        let out = match entry_target(target, &entry.name) {
            Ok(path) => path,
            Err(e) => {
                failure = Some(e);
                return Ok(false);
            }
        };

        if entry.is_directory {
            if let Err(e) = fs::create_dir_all(&out).map_err(|e| files::io_error(&out, e)) {
                failure = Some(e);
                return Ok(false);
            }
            return Ok(true);
        }

        let written = (|| -> RpcResult<()> {
            if let Some(parent) = out.parent() {
                fs::create_dir_all(parent).map_err(|e| files::io_error(parent, e))?;
            }
            let mut sink = fs::File::create(&out).map_err(|e| files::io_error(&out, e))?;
            std::io::copy(data, &mut sink).map_err(|e| files::io_error(&out, e))?;
            Ok(())
        })();
        if let Err(e) = written {
            failure = Some(e);
            return Ok(false);
        }
        Ok(true)
    });

    if let Some(error) = failure {
        return Err(error);
    }
    walked.map_err(|e| sevenz_err("解压 7z 失败", e))?;
    Ok(())
}
