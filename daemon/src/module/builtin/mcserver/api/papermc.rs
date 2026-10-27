//! PaperMC 的 v3 API —— `paper` 与 `velocity` 同一套接口，只有 project 名不同。
//!
//! 版本列表是**分组**的：`{"versions": {"26.3": ["26.3", "26.3-rc-3"], …}}` ——
//! 同一大版本下再列小版本，所以要摊平再滤掉预发布版。
//!
//! 下载走 `builds/latest` 的 `server:default`，带 sha256。

use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError, is_prerelease, sort_versions_desc};

const BASE: &str = "https://fill.papermc.io/v3/projects";

/// 取某个项目（paper / velocity）的正式版列表，新版本在前。
pub async fn versions(http: &reqwest::Client, project: &str) -> Result<Vec<String>, FetchError> {
    let value = super::get_value(http, &format!("{BASE}/{project}")).await?;
    parse_versions(&value)
}

/// 摊平分组、滤掉 rc/pre、降序排。
pub fn parse_versions(value: &Value) -> Result<Vec<String>, FetchError> {
    #[derive(Deserialize)]
    struct Response {
        versions: BTreeMap<String, Vec<String>>,
    }

    let response: Response = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("paper 版本列表不是预期形状：{e}")))?;

    let mut versions: Vec<String> = response
        .versions
        .into_values()
        .flatten()
        .filter(|version| !is_prerelease(version))
        .collect();
    sort_versions_desc(&mut versions);
    Ok(versions)
}

/// 取某个版本「最新构建」的下载地址与 sha256。
pub async fn download(
    http: &reqwest::Client,
    project: &str,
    version: &str,
) -> Result<Download, FetchError> {
    let url = format!("{BASE}/{project}/versions/{version}/builds/latest");
    let value = super::get_value(http, &url).await?;
    parse_download(&value, project, version)
}

/// 从构建详情里挑出 `server:default`。
pub fn parse_download(value: &Value, project: &str, version: &str) -> Result<Download, FetchError> {
    #[derive(Deserialize)]
    struct Build {
        downloads: BTreeMap<String, Artifact>,
    }
    #[derive(Deserialize)]
    struct Artifact {
        url: String,
        #[serde(default)]
        checksums: BTreeMap<String, String>,
    }

    let build: Build = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("{project} 构建详情不是预期形状：{e}")))?;

    let artifact = build.downloads.get("server:default").ok_or_else(|| {
        FetchError::NotFound(format!(
            "{project} {version} 的最新构建里没有 server:default"
        ))
    })?;

    Ok(Download {
        url: artifact.url.clone(),
        checksum: artifact
            .checksums
            .get("sha256")
            .map(|sha| ("sha256", sha.to_ascii_lowercase())),
    })
}
