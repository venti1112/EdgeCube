//! 插件/模组市场代理(Modrinth / Poggit)。
//!
//! 网络调用全部收敛在后端:前端不直连第三方服务,统一经本模块代理。
//! - Modrinth:搜索、项目版本、批量项目信息(图标)、按 SHA1 查版本、游戏版本;
//! - Poggit:全量发布列表(带 12h 缓存,避免触发接口限流)与按名查询版本。
//!
//! 字段命名对齐 Modrinth/Poggit 原生响应(snake_case),openapi 契约据此定义,
//! 前端生成的 Dart 模型与 V1 直接解析第三方响应的字段一致。
//!
//! 接口均需鉴权(`require_auth`),由 server.rs 组装路由。

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

const MODRINTH_BASE: &str = "https://api.modrinth.com/v2";
const POGGIT_BASE: &str = "https://poggit.pmmp.io";
/// Poggit 全量列表缓存时长(V1 同款 12h)。
const POGGIT_CACHE_TTL: Duration = Duration::from_secs(12 * 3600);

/// 共享 HTTP 客户端(复用连接,统一 UA)。
#[derive(Clone)]
pub struct ModMarket {
    client: reqwest::Client,
    poggit_cache: Arc<RwLock<Option<(Instant, serde_json::Value)>>>,
}

impl ModMarket {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .user_agent("EdgeCube-Daemon/1.0 (plugin-mod market proxy)")
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .build()
            .expect("build reqwest client");
        ModMarket {
            client,
            poggit_cache: Arc::new(RwLock::new(None)),
        }
    }

    // ── Modrinth ──────────────────────────────────────────────

    /// 搜索(参数对齐 V1 ModrinthService.search)。
    pub async fn modrinth_search(
        &self,
        query: &str,
        offset: u64,
        limit: u64,
        game_version: Option<&str>,
        loader: Option<&str>,
        sort: &str,
        project_type: &str,
    ) -> Result<ModrinthSearchResponse, String> {
        let mut facets: Vec<serde_json::Value> = Vec::new();
        // 插件(paper/spigot/velocity/bungeecord)与模组(fabric/forge/quilt/neoforge)
        let category_facet = if project_type == "plugin" {
            vec![
                "categories:paper",
                "categories:spigot",
                "categories:velocity",
                "categories:bungeecord",
            ]
        } else {
            vec![
                "categories:fabric",
                "categories:forge",
                "categories:quilt",
                "categories:neoforge",
            ]
        };
        facets.push(serde_json::json!(category_facet));
        if let Some(gv) = game_version.filter(|s| !s.is_empty()) {
            facets.push(serde_json::json!([format!("versions:{gv}")]));
        }
        if let Some(ld) = loader.filter(|s| !s.is_empty()) {
            facets.push(serde_json::json!([format!("categories:{ld}")]));
        }

        let resp = self
            .client
            .get(format!("{MODRINTH_BASE}/search"))
            .query(&[
                ("query", query.to_string()),
                ("offset", offset.to_string()),
                ("limit", limit.to_string()),
                ("index", sort.to_string()),
                ("facets", serde_json::json!(facets).to_string()),
            ])
            .send()
            .await
            .map_err(|e| format!("modrinth search: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("modrinth search: HTTP {}", resp.status()));
        }
        resp.json::<ModrinthSearchResponse>()
            .await
            .map_err(|e| format!("modrinth search decode: {e}"))
    }

    /// 项目版本列表(可选按游戏版本/加载器过滤)。
    pub async fn modrinth_versions(
        &self,
        project_id: &str,
        game_version: Option<&str>,
        loader: Option<&str>,
    ) -> Result<Vec<ModrinthVersion>, String> {
        let mut req = self
            .client
            .get(format!("{MODRINTH_BASE}/project/{project_id}/version"));
        let mut params: Vec<(&str, String)> = Vec::new();
        if let Some(gv) = game_version.filter(|s| !s.is_empty()) {
            params.push(("game_versions", format!("[\"{gv}\"]")));
        }
        if let Some(ld) = loader.filter(|s| !s.is_empty()) {
            params.push(("loaders", format!("[\"{ld}\"]")));
        }
        if !params.is_empty() {
            req = req.query(&params);
        }
        let resp = req
            .send()
            .await
            .map_err(|e| format!("modrinth versions: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("modrinth versions: HTTP {}", resp.status()));
        }
        resp.json::<Vec<ModrinthVersion>>()
            .await
            .map_err(|e| format!("modrinth versions decode: {e}"))
    }

    /// 批量项目信息(图标/标题),ids 为 Modrinth project id 列表。
    pub async fn modrinth_projects(
        &self,
        ids: &[String],
    ) -> Result<Vec<ModrinthProject>, String> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let resp = self
            .client
            .get(format!("{MODRINTH_BASE}/projects"))
            .query(&[("ids", serde_json::json!(ids).to_string())])
            .send()
            .await
            .map_err(|e| format!("modrinth projects: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("modrinth projects: HTTP {}", resp.status()));
        }
        resp.json::<Vec<ModrinthProject>>()
            .await
            .map_err(|e| format!("modrinth projects decode: {e}"))
    }

    /// 按 SHA1 查最新版本(Modrinth version_files/update)。
    /// 返回 map: sha1 -> Version(对齐 V1 ModrinthService.checkUpdates)。
    pub async fn modrinth_version_files(
        &self,
        hashes: &[String],
    ) -> Result<HashMap<String, ModrinthVersion>, String> {
        if hashes.is_empty() {
            return Ok(HashMap::new());
        }
        let resp = self
            .client
            .post(format!("{MODRINTH_BASE}/version_files/update"))
            .json(&serde_json::json!({ "hashes": hashes, "algorithm": "sha1" }))
            .send()
            .await
            .map_err(|e| format!("modrinth version_files: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("modrinth version_files: HTTP {}", resp.status()));
        }
        resp.json::<HashMap<String, ModrinthVersion>>()
            .await
            .map_err(|e| format!("modrinth version_files decode: {e}"))
    }

    /// 游戏版本列表(筛选下拉数据源)。
    pub async fn modrinth_game_versions(&self) -> Result<Vec<String>, String> {
        let resp = self
            .client
            .get(format!("{MODRINTH_BASE}/tag/game_version"))
            .send()
            .await
            .map_err(|e| format!("modrinth game_versions: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("modrinth game_versions: HTTP {}", resp.status()));
        }
        resp.json::<Vec<String>>()
            .await
            .map_err(|e| format!("modrinth game_versions decode: {e}"))
    }

    // ── Poggit ────────────────────────────────────────────────

    /// 全量发布列表(带 12h 缓存)。
    pub async fn poggit_plugins(&self) -> Result<serde_json::Value, String> {
        if let Some((at, cached)) = self.poggit_cache.read().await.as_ref() {
            if at.elapsed() < POGGIT_CACHE_TTL {
                return Ok(cached.clone());
            }
        }
        let resp = self
            .client
            .get(format!("{POGGIT_BASE}/releases.min.json"))
            .send()
            .await
            .map_err(|e| format!("poggit releases: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("poggit releases: HTTP {}", resp.status()));
        }
        let value = resp
            .json::<serde_json::Value>()
            .await
            .map_err(|e| format!("poggit releases decode: {e}"))?;
        *self.poggit_cache.write().await = Some((Instant::now(), value.clone()));
        Ok(value)
    }

    /// 按名查询发布版本(Poggit v2.1 API)。
    pub async fn poggit_versions(&self, name: &str) -> Result<serde_json::Value, String> {
        let resp = self
            .client
            .get(format!("{POGGIT_BASE}/v2.1/releases"))
            .query(&[("name", name.to_string())])
            .send()
            .await
            .map_err(|e| format!("poggit versions: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("poggit versions: HTTP {}", resp.status()));
        }
        resp.json::<serde_json::Value>()
            .await
            .map_err(|e| format!("poggit versions decode: {e}"))
    }
}

impl Default for ModMarket {
    fn default() -> Self {
        Self::new()
    }
}

// ── 服务端代理契约模型(对齐 openapi mods) ─────────────────────

/// Modrinth 搜索响应。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthSearchResponse {
    pub hits: Vec<ModrinthSearchHit>,
    pub offset: u64,
    pub limit: u64,
    pub total_hits: u64,
}

/// 搜索结果条目。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthSearchHit {
    pub slug: String,
    pub project_id: String,
    pub title: String,
    pub description: Option<String>,
    pub categories: Vec<String>,
    pub versions: Vec<String>,
    pub project_type: String,
    pub icon_url: Option<String>,
    pub author: Option<String>,
    pub downloads: u64,
    pub follows: u64,
    pub latest_version: Option<String>,
}

/// 项目版本(精简:文件 + 依赖 + 加载器/游戏版本)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthVersion {
    pub id: String,
    pub project_id: String,
    pub name: Option<String>,
    pub version_number: String,
    pub game_versions: Vec<String>,
    pub loaders: Vec<String>,
    pub files: Vec<ModrinthVersionFile>,
    pub dependencies: Vec<ModrinthDependency>,
}

/// 版本文件(SHA1 用于图标/更新检查)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthVersionFile {
    pub url: String,
    pub filename: String,
    pub primary: bool,
    pub size: u64,
    pub hashes: ModrinthFileHashes,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthFileHashes {
    pub sha1: Option<String>,
    pub sha512: Option<String>,
}

/// 依赖(供版本详情展示)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthDependency {
    pub project_id: Option<String>,
    pub version_id: Option<String>,
    pub dependency_type: String,
}

/// 项目信息(图标/标题,批量查询)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ModrinthProject {
    pub id: String,
    pub slug: String,
    pub title: String,
    pub description: Option<String>,
    pub icon_url: Option<String>,
    pub project_type: String,
}
