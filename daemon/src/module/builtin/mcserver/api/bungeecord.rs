//! BungeeCord（md-5 官方 Jenkins）。
//!
//! **没有版本概念**：只有「最后一个成功的构建」。所以它的版本列表是一个假值
//! [`PSEUDO_VERSION`]，前端看 `mcserver.types` 里的 `needs_version = false`
//! 就知道该跳过版本页。
//!
//! 下载地址用**构建号**拼（不可变），而不是 `lastSuccessfulBuild` 那个短链 ——
//! 后者在下载途中上游出了新构建就会拿到另一个文件。

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError};

/// 没有版本可选时的占位版本号。
pub const PSEUDO_VERSION: &str = "latest";

const BASE: &str = "https://ci.md-5.net/job/BungeeCord";

/// 最后一个成功构建的下载地址。
pub async fn download(http: &reqwest::Client) -> Result<Download, FetchError> {
    let value = super::get_value(http, &format!("{BASE}/lastSuccessfulBuild/api/json")).await?;
    parse_download(&value)
}

/// 从构建信息里取构建号并拼出产物地址。
pub fn parse_download(value: &Value) -> Result<Download, FetchError> {
    #[derive(Deserialize)]
    struct Build {
        number: u64,
    }

    let build: Build = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("BungeeCord 构建信息不是预期形状：{e}")))?;

    Ok(Download {
        url: format!(
            "{BASE}/{}/artifact/bootstrap/target/BungeeCord.jar",
            build.number
        ),
        // Jenkins 不给校验值
        checksum: None,
    })
}
