//! Leaf 与 Leaves —— 两个同源的 Paper 分支，接口形状像但**不完全一样**。
//!
//! * 版本列表：两边都是 `{"versions": [...]}`，但顺序都不可信（leaf 实测是乱的），
//!   一律自己降序排。
//! * 下载：
//!   * Leaf 要先取「构建号数组」自己挑最大，再取构建详情里的 `primary`；
//!   * Leaves 直接有 `builds/latest`，构建详情里的字段叫 `application`。
//!
//! 两者的构建详情都带 sha256。

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError, is_prerelease, sort_versions_desc};

/// Leaf 的接口前缀。
pub const LEAF_BASE: &str = "https://api.leafmc.one/v2/projects/leaf";
/// Leaves 的接口前缀。
pub const LEAVES_BASE: &str = "https://api.leavesmc.org/v2/projects/leaves";

/// 版本列表（正式版，新版本在前）。
pub async fn versions(http: &reqwest::Client, base: &str) -> Result<Vec<String>, FetchError> {
    let value = super::get_value(http, base).await?;
    parse_versions(&value)
}

/// 解析 `{"versions": [...]}`。顺带滤掉 rc/pre。
pub fn parse_versions(value: &Value) -> Result<Vec<String>, FetchError> {
    #[derive(Deserialize)]
    struct Response {
        versions: Vec<String>,
    }

    let response: Response = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("leaf 系版本列表不是预期形状：{e}")))?;

    let mut versions: Vec<String> = response
        .versions
        .into_iter()
        .filter(|version| !is_prerelease(version))
        .collect();
    sort_versions_desc(&mut versions);
    Ok(versions)
}

// ── Leaf ──────────────────────────────────────────────────────────────────

/// Leaf：构建号数组 → 挑最大 → 构建详情。
pub async fn leaf_download(http: &reqwest::Client, version: &str) -> Result<Download, FetchError> {
    let list_url = format!("{LEAF_BASE}/versions/{version}");
    let list = super::get_value(http, &list_url).await?;
    let build = parse_latest_build(&list, version)?;

    let detail_url = format!("{LEAF_BASE}/versions/{version}/builds/{build}");
    let detail = super::get_value(http, &detail_url).await?;
    parse_leaf_build_detail(&detail, version, &build)
}

/// 从 `{"builds": [3, 4, …]}` 里挑最大的构建号。
///
/// 数组顺序不可信（可能有缺口，如 `…, 16, 18, …`），所以取最大值而不是最后一个。
pub fn parse_latest_build(value: &Value, version: &str) -> Result<String, FetchError> {
    #[derive(Deserialize)]
    struct Response {
        builds: Vec<u64>,
    }

    let response: Response = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("leaf {version} 的构建列表不是预期形状：{e}")))?;
    response
        .builds
        .into_iter()
        .max()
        .map(|build| build.to_string())
        .ok_or_else(|| FetchError::NotFound(format!("leaf {version} 还没有任何构建")))
}

/// Leaf 的构建详情：下载地址在 `downloads.primary`，文件名单独给。
pub fn parse_leaf_build_detail(
    value: &Value,
    version: &str,
    build: &str,
) -> Result<Download, FetchError> {
    let (name, sha256) = parse_artifact(value, "primary", &format!("leaf {version} #{build}"))?;
    Ok(Download {
        url: format!("{LEAF_BASE}/versions/{version}/builds/{build}/downloads/{name}"),
        checksum: sha256,
    })
}

// ── Leaves ────────────────────────────────────────────────────────────────

/// Leaves：直接有 `builds/latest`。
pub async fn leaves_download(
    http: &reqwest::Client,
    version: &str,
) -> Result<Download, FetchError> {
    let url = format!("{LEAVES_BASE}/versions/{version}/builds/latest");
    let value = super::get_value(http, &url).await?;
    parse_leaves_latest(&value, version)
}

/// Leaves 的构建详情：`build` 是构建号，下载信息在 `downloads.application`。
pub fn parse_leaves_latest(value: &Value, version: &str) -> Result<Download, FetchError> {
    #[derive(Deserialize)]
    struct Response {
        build: u64,
    }

    let build = serde_json::from_value::<Response>(value.clone())
        .map_err(|e| FetchError::Parse(format!("leaves {version} 的构建详情不是预期形状：{e}")))?
        .build;
    let (name, sha256) =
        parse_artifact(value, "application", &format!("leaves {version} #{build}"))?;

    Ok(Download {
        url: format!("{LEAVES_BASE}/versions/{version}/builds/{build}/downloads/{name}"),
        checksum: sha256,
    })
}

/// 取 `downloads.<key>` 里的 `(文件名, sha256)`。两家的字段名不一样，其余相同。
fn parse_artifact(
    value: &Value,
    key: &str,
    what: &str,
) -> Result<(String, Option<super::Checksum>), FetchError> {
    #[derive(Deserialize)]
    struct Downloads {
        name: String,
        #[serde(default)]
        sha256: Option<String>,
    }
    #[derive(Deserialize)]
    struct Response {
        downloads: std::collections::BTreeMap<String, Downloads>,
    }

    let response: Response = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("{what} 的下载信息不是预期形状：{e}")))?;
    let artifact = response
        .downloads
        .get(key)
        .ok_or_else(|| FetchError::NotFound(format!("{what} 的下载信息里没有 `{key}`")))?;

    Ok((
        artifact.name.clone(),
        artifact
            .sha256
            .as_ref()
            .filter(|sha| !sha.trim().is_empty())
            .map(|sha| ("sha256", sha.to_ascii_lowercase())),
    ))
}
