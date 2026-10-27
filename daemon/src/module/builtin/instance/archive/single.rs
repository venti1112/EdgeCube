//! 单文件压缩流（gz / xz / bz2 / zst / lz4）解压。
//!
//! 这类格式里没有条目名，输出名只能从归档文件名推（去掉后缀），
//! 所以由调用方把名字传进来。

use std::io::Read;
use std::path::Path;

use crate::error::{RpcError, RpcResult};

use super::super::files;

pub fn extract<R: Read>(mut input: R, target: &Path, out_name: &str) -> RpcResult<()> {
    let name = if out_name.trim().is_empty() {
        "解压文件".to_string()
    } else {
        files::validate_name(out_name)?
    };
    let out = target.join(&name);
    if let Some(parent) = out.parent() {
        std::fs::create_dir_all(parent).map_err(|e| files::io_error(parent, e))?;
    }
    let mut sink = std::fs::File::create(&out).map_err(|e| files::io_error(&out, e))?;
    // 单流格式没有条目头，坏数据只能在拷贝时暴露 —— 统一报 `file_archive`，
    // 别让「不是 gzip」看起来像磁盘错误
    std::io::copy(&mut input, &mut sink)
        .map_err(|e| RpcError::new("file_archive", format!("解压 {} 失败：{e}", out.display())))?;
    Ok(())
}
