//! Fabric（`meta.fabricmc.net`）。
//!
//! Fabric 的「服务端」不是一个 jar 而是**加载器 + 原版二合一**的产物，
//! 但官方提供了一个直接产出的接口：
//! `/v2/versions/loader/{mc}/{loader}/{installer}/server/jar`
//! —— 有了它就不用像 Forge 那样先下安装器再跑一遍（那正是用户说先不做的那类步骤）。
//!
//! 代价是那个接口不给校验值，所以 Fabric 的下载没有哈希校验。

use serde::Deserialize;
use serde_json::Value;

use super::{Download, FetchError, sort_versions_desc};

const BASE: &str = "https://meta.fabricmc.net/v2/versions";

/// Minecraft 版本（只要 Fabric 标记为 stable 的），新版本在前。
pub async fn game_versions(http: &reqwest::Client) -> Result<Vec<String>, FetchError> {
    let value = super::get_value(http, &format!("{BASE}/game")).await?;
    parse_game_versions(&value)
}

/// 解析游戏版本列表：只留 `stable == true`。
pub fn parse_game_versions(value: &Value) -> Result<Vec<String>, FetchError> {
    #[derive(Deserialize)]
    struct Entry {
        version: String,
        stable: bool,
    }

    let entries: Vec<Entry> = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("Fabric 游戏版本列表不是预期形状：{e}")))?;

    let mut versions: Vec<String> = entries
        .into_iter()
        .filter(|entry| entry.stable)
        .map(|entry| entry.version)
        .collect();
    sort_versions_desc(&mut versions);
    Ok(versions)
}

/// 某个 Minecraft 版本可用的加载器版本，新版本在前。
pub async fn loader_versions(
    http: &reqwest::Client,
    mc_version: &str,
) -> Result<Vec<String>, FetchError> {
    let value = super::get_value(http, &format!("{BASE}/loader/{mc_version}")).await?;
    parse_loader_versions(&value)
}

/// 解析加载器列表：`[{"loader": {"version": "0.16.14", …}}, …]`。
pub fn parse_loader_versions(value: &Value) -> Result<Vec<String>, FetchError> {
    #[derive(Deserialize)]
    struct Entry {
        loader: Loader,
    }
    #[derive(Deserialize)]
    struct Loader {
        version: String,
    }

    let entries: Vec<Entry> = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("Fabric 加载器列表不是预期形状：{e}")))?;

    let mut versions: Vec<String> = entries
        .into_iter()
        .map(|entry| entry.loader.version)
        .collect();
    sort_versions_desc(&mut versions);
    Ok(versions)
}

/// 合并 jar 的下载地址：先问最新 installer 版本，再拼出那条直链。
pub async fn server_jar(
    http: &reqwest::Client,
    mc_version: &str,
    loader_version: &str,
) -> Result<Download, FetchError> {
    let value = super::get_value(http, &format!("{BASE}/installer")).await?;
    let installer = parse_installer_version(&value)?;
    Ok(Download {
        url: format!("{BASE}/loader/{mc_version}/{loader_version}/{installer}/server/jar"),
        // 这个接口没有校验值可比
        checksum: None,
    })
}

/// 取最新 installer 版本（列表是新的在前，取第一个）。
pub fn parse_installer_version(value: &Value) -> Result<String, FetchError> {
    #[derive(Deserialize)]
    struct Entry {
        version: String,
    }

    let entries: Vec<Entry> = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("Fabric installer 列表不是预期形状：{e}")))?;
    entries
        .into_iter()
        .next()
        .map(|entry| entry.version)
        .ok_or_else(|| FetchError::NotFound("Fabric 没有可用的 installer 版本".into()))
}
