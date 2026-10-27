//! rar 解压。
//!
//! `unrar` 是 UnRAR 源码的绑定（随包编 C++），只能解压、不能打包 ——
//! 压缩输出里没有 rar，这是库本身的限制，不是没做。

use std::fs;
use std::path::Path;

use crate::error::{RpcError, RpcResult};

use super::super::files::{self, Limits};
use super::{check_entries, entry_target};

fn rar_err(context: &str, error: impl std::fmt::Display) -> RpcError {
    RpcError::new("file_archive", format!("{context}：{error}"))
}

pub fn extract(archive: &Path, target: &Path, limits: &Limits) -> RpcResult<()> {
    let mut handle = unrar::Archive::new(archive)
        .open_for_processing()
        .map_err(|e| rar_err("不是有效的 rar 归档", e))?;

    let mut count = 0u64;
    loop {
        let Some(header) = handle
            .read_header()
            .map_err(|e| rar_err("读取 rar 条目失败", e))?
        else {
            break;
        };

        count += 1;
        check_entries(count, limits)?;

        let name = header.entry().filename.to_string_lossy().into_owned();
        let is_dir = header.entry().is_directory();

        if is_dir {
            let out = entry_target(target, &name)?;
            fs::create_dir_all(&out).map_err(|e| files::io_error(&out, e))?;
            handle = header
                .skip()
                .map_err(|e| rar_err("跳过 rar 目录条目失败", e))?;
            continue;
        }

        // 链接类条目不落地：unrar 解链接条目会自行建链，等于绕开路径校验
        if header.entry().is_file() {
            let out = entry_target(target, &name)?;
            if let Some(parent) = out.parent() {
                fs::create_dir_all(parent).map_err(|e| files::io_error(parent, e))?;
            }
            handle = header
                .extract_to(&out)
                .map_err(|e| rar_err("解压 rar 条目失败", e))?;
            continue;
        }

        handle = header.skip().map_err(|e| rar_err("跳过 rar 条目失败", e))?;
    }
    Ok(())
}
