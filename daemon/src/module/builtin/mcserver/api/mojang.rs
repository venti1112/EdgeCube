//! 原版（Mojang 官方）。
//!
//! 两步：版本清单拿到「版本 → 详情地址」，详情里才有服务端 jar 的真实地址。
//!
//! **Mojang 只提供 sha1** —— 实测 `downloads.server` 就只有 `sha1` / `size` / `url`
//! 三个字段。gosh-dl 的校验只支持 md5/sha256，所以这一路是 daemon 下载完自己算的
//! （见 `download` 模块）。

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError};

const MANIFEST_URL: &str = "https://launchermeta.mojang.com/mc/game/version_manifest.json";

/// 清单里的一条：版本号 + 详情的地址。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VersionEntry {
    pub id: String,
    pub detail_url: String,
}

/// 取「正式版 → 详情地址」。
///
/// 清单本身就是新版本在前，所以**不排序**，跟着官方走。
pub async fn version_index(http: &reqwest::Client) -> Result<Vec<VersionEntry>, FetchError> {
    let value = super::get_value(http, MANIFEST_URL).await?;
    parse_manifest(&value)
}

/// 解析版本清单。只留 `type == "release"`（快照与预发布版不进列表）。
pub fn parse_manifest(value: &Value) -> Result<Vec<VersionEntry>, FetchError> {
    #[derive(Deserialize)]
    struct Manifest {
        versions: Vec<Entry>,
    }
    #[derive(Deserialize)]
    struct Entry {
        id: String,
        #[serde(rename = "type")]
        kind: String,
        url: String,
    }

    let manifest: Manifest = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("版本清单不是预期形状：{e}")))?;

    Ok(manifest
        .versions
        .into_iter()
        .filter(|entry| entry.kind == "release")
        .map(|entry| VersionEntry {
            id: entry.id,
            detail_url: entry.url,
        })
        .collect())
}

/// 取某个版本的服务端 jar 地址与 sha1。
pub async fn server_download(
    http: &reqwest::Client,
    detail_url: &str,
) -> Result<Download, FetchError> {
    let value = super::get_value(http, detail_url).await?;
    parse_server_download(&value, detail_url)
}

/// 从版本详情里挑出服务端 jar。
///
/// 老版本（1.2.5 以前）没有 `downloads.server`，那时确实没服务端可下 ——
/// 报「没有」而不是崩掉。
pub fn parse_server_download(value: &Value, detail_url: &str) -> Result<Download, FetchError> {
    #[derive(Deserialize)]
    struct Detail {
        downloads: Downloads,
    }
    #[derive(Deserialize)]
    struct Downloads {
        server: Option<Server>,
    }
    #[derive(Deserialize)]
    struct Server {
        url: String,
        sha1: String,
    }

    let detail: Detail = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("{detail_url} 不是预期形状：{e}")))?;

    let server = detail.downloads.server.ok_or_else(|| {
        FetchError::NotFound(format!("这个版本没有官方服务端 jar（{detail_url}）"))
    })?;

    Ok(Download {
        url: server.url,
        checksum: Some(("sha1", server.sha1.to_ascii_lowercase())),
    })
}
