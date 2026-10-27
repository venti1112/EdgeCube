//! Purpur（`api.purpurmc.org` v2）。
//!
//! 版本列表是**升序**的（实测 `1.14.1 → 26.3`），所以必须自己排。
//!
//! 下载不走 `/download` 那个「永远指向最新构建」的短链（短链没有校验），而是多问一次
//! 构建详情把 **md5** 带上（那个接口确实有 `md5` 字段，实测确认），于是下载
//! 就有完整性校验了 —— md5 弱，但比没有强，而且下载队列本来就支持 md5。

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError, is_prerelease, sort_versions_desc};

const BASE: &str = "https://api.purpurmc.org/v2/purpur";

/// 正式版列表，新版本在前。
pub async fn versions(http: &reqwest::Client) -> Result<Vec<String>, FetchError> {
    let value = super::get_value(http, BASE).await?;
    parse_versions(&value)
}

/// 滤掉 rc/pre 并降序排。
pub fn parse_versions(value: &Value) -> Result<Vec<String>, FetchError> {
    #[derive(Deserialize)]
    struct Response {
        versions: Vec<String>,
    }

    let response: Response = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("purpur 版本列表不是预期形状：{e}")))?;

    let mut versions: Vec<String> = response
        .versions
        .into_iter()
        .filter(|version| !is_prerelease(version))
        .collect();
    sort_versions_desc(&mut versions);
    Ok(versions)
}

/// 最新构建的下载地址与 md5。
pub async fn download(http: &reqwest::Client, version: &str) -> Result<Download, FetchError> {
    // 先问「最新构建号」，再用构建号拼**不可变**的下载地址与详情地址。
    // 直接用 `/download` 短链的话，下载途中上游出了新构建就会拿到另一个文件。
    let meta_url = format!("{BASE}/{version}");
    let meta = super::get_value(http, &meta_url).await?;
    let latest = parse_latest_build(&meta, version)?;

    let build_url = format!("{BASE}/{version}/{latest}");
    let build = super::get_value(http, &build_url).await?;
    let md5 = parse_build_md5(&build);

    Ok(Download {
        url: format!("{build_url}/download"),
        checksum: md5,
    })
}

/// 从版本信息里取「最新构建号」。
pub fn parse_latest_build(value: &Value, version: &str) -> Result<String, FetchError> {
    #[derive(Deserialize)]
    struct VersionInfo {
        builds: Builds,
    }
    #[derive(Deserialize)]
    struct Builds {
        latest: String,
    }

    let info: VersionInfo = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("purpur {version} 的版本信息不是预期形状：{e}")))?;
    Ok(info.builds.latest)
}

/// 从构建详情里取 md5（没有就是没有，不报错）。
pub fn parse_build_md5(value: &Value) -> Option<super::Checksum> {
    #[derive(Deserialize)]
    struct Build {
        md5: Option<String>,
    }

    serde_json::from_value::<Build>(value.clone())
        .ok()
        .and_then(|build| build.md5)
        .filter(|md5| !md5.trim().is_empty())
        .map(|md5| ("md5", md5.to_ascii_lowercase()))
}
