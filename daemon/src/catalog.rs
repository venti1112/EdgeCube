//! 服务端版本目录(契约 /catalog/*):「下载服务端」向导的数据源。
//!
//! 对齐 V1 的 version_fetch_service / download_info_service / download_runner:
//! 版本列表与下载直链/校验值的组装逻辑从 Flutter 端回收至 daemon,daemon 代理
//! 第三方官方源(papermc / mojang / getbukkit / fabricmc / github 等),前端一律
//! 经本模块端点取数,不直连互联网。
//!
//! 类别:
//! - [server_types] 静态定义(编译期),随 daemon 发布演进;
//! - [Catalog::versions] 版本列表,带 TTL 缓存(5 分钟,减少对上游的冲击);
//! - [Catalog::loaders] Fabric 加载器版本列表(meta.fabricmc.net);
//! - [Catalog::download_info] 按选择的组合构建下载信息(URL / 校验值 / 落盘文件名)。

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;

/// 版本列表 TTL(上游是公开 API,频繁刷新会加重负担;5 分钟足够 UI 使用)。
const VERSION_TTL: Duration = Duration::from_secs(300);

/// 版本列表缓存条目。
struct CacheEntry {
    at: Instant,
    versions: Vec<ServerVersion>,
}

impl CacheEntry {
    fn fresh(&self) -> bool {
        self.at.elapsed() < VERSION_TTL
    }
}

/// 目录服务(所有操作为只读网络 IO,handler 层负责鉴权)。
pub struct Catalog {
    client: reqwest::Client,
    cache: Mutex<HashMap<String, CacheEntry>>,
}

impl Default for Catalog {
    fn default() -> Self {
        Self::new()
    }
}

impl Catalog {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .user_agent(concat!("EdgeCube/", env!("CARGO_PKG_VERSION")))
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .build()
            .expect("build reqwest client");
        Catalog {
            client,
            cache: Mutex::new(HashMap::new()),
        }
    }

    // ── 版本列表(带缓存) ──────────────────────────────────────────

    /// 某服务端类型的可选版本(降序,最新在前);bungeecord 无版本概念返回空。
    pub async fn versions(&self, type_id: &str) -> Result<Vec<ServerVersion>, CatalogError> {
        if type_id == "bungeecord" {
            return Ok(Vec::new());
        }
        if let Some(entry) = self.cache.lock().unwrap().get(type_id) {
            if entry.fresh() {
                return Ok(entry.versions.clone());
            }
        }
        let versions = self.fetch_versions(type_id).await?;
        self.cache
            .lock()
            .unwrap()
            .insert(type_id.to_string(), CacheEntry { at: Instant::now(), versions: versions.clone() });
        Ok(versions)
    }

    /// Fabric 加载器版本(meta.fabricmc.net,不缓存——同一 MC 版本选择依赖实时列表)。
    pub async fn loaders(&self, mc_version: &str) -> Result<Vec<String>, CatalogError> {
        let body = self.get_text(&format!(
            "https://meta.fabricmc.net/v2/versions/loader/{mc_version}"
        )).await?;
        let json: Vec<serde_json::Value> =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("fabricmc meta parse: {e}")))?;
        let mut loaders = Vec::new();
        for item in json {
            if let Some(version) = item.get("loader").and_then(|l| l.get("version")).and_then(|v| v.as_str()) {
                loaders.push(version.to_string());
            }
        }
        if loaders.is_empty() {
            return Err(CatalogError::NoResult(format!(
                "fabric loaders for mc {mc_version}"
            )));
        }
        Ok(loaders)
    }

    // ── 下载信息 ──────────────────────────────────────────────────

    /// 构建下载信息:URL + 可选校验值("sha1:<hex>" / "sha256:<hex>") + 建议落盘文件名。
    pub async fn download_info(
        &self,
        type_id: &str,
        version: Option<&str>,
        mc_version: Option<&str>,
        loader_version: Option<&str>,
    ) -> Result<ServerDownloadInfo, CatalogError> {
        match type_id {
            "vanilla" => self.vanilla_download_info(version).await,
            "paper" => self.papermc_download_info("paper", version, "server.jar").await,
            "velocity" => self.papermc_download_info("velocity", version, "server.jar").await,
            "spigot" => Ok(ServerDownloadInfo::no_checksum(
                format!("https://cdn.getbukkit.org/spigot/spigot-{v}.jar", v = version_required(version, "spigot")?),
                "server.jar",
            )),
            "craftbukkit" => Ok(ServerDownloadInfo::no_checksum(
                format!("https://cdn.getbukkit.org/craftbukkit/craftbukkit-{v}.jar", v = version_required(version, "craftbukkit")?),
                "server.jar",
            )),
            "purpur" => self.purpur_download_info(version).await,
            "leaf" => self.leaf_download_info(version).await,
            "leaves" => self.leaves_download_info(version).await,
            "bungeecord" => self.bungeecord_download_info().await,
            "fabric" => self.fabric_download_info(mc_version, loader_version).await,
            "pocketmine" => self.pocketmine_download_info(version).await,
            "powernukkitx" => self.github_release_jar("PowerNukkitX/PowerNukkitX", version, "powernukkitx.jar").await,
            "allay" => self.allay_download_info(version).await,
            _ => Err(CatalogError::UnsupportedType(type_id.to_string())),
        }
    }

    // ── 各源版本列表 ──────────────────────────────────────────────

    async fn fetch_versions(&self, type_id: &str) -> Result<Vec<ServerVersion>, CatalogError> {
        match type_id {
            "vanilla" => self.vanilla_versions().await,
            "paper" => self.papermc_versions("paper").await,
            "velocity" => self.papermc_versions("velocity").await,
            "spigot" => self.getbukkit_versions("spigot").await,
            "craftbukkit" => self.getbukkit_versions("craftbukkit").await,
            "purpur" => self.purpur_versions().await,
            "leaf" => self.leaf_versions().await,
            "leaves" => self.leaves_versions().await,
            "fabric" => self.fabric_mc_versions().await,
            "pocketmine" => self.pocketmine_versions().await,
            "powernukkitx" => self.powernukkitx_versions().await,
            "allay" => self.allay_versions().await,
            other => Err(CatalogError::UnsupportedType(other.to_string())),
        }
    }

    /// 原版(Vanilla):launchermeta 发行版列表(仅 release)。
    async fn vanilla_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        // 兼容 V1 使用的镜像域名;官方为 launchermeta.mojang.com
        let body = self.get_text("https://launchermeta.mojang.com/mc/game/version_manifest.json").await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("mojang manifest parse: {e}")))?;
        let mut versions = Vec::new();
        if let Some(list) = json.get("versions").and_then(|v| v.as_array()) {
            for item in list {
                if item.get("type").and_then(|t| t.as_str()) == Some("release") {
                    if let Some(id) = item.get("id").and_then(|i| i.as_str()) {
                        versions.push(ServerVersion { version: id.to_string(), meta: None });
                    }
                }
            }
        }
        if versions.is_empty() {
            return Err(CatalogError::NoResult("vanilla versions".into()));
        }
        versions.reverse(); // 降序:最新在前
        Ok(versions)
    }

    /// PaperMC 系(paper / velocity):fill API 的 versions 按 group 分组,过滤 rc/pre,展平。
    async fn papermc_versions(&self, project: &str) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text(&format!("https://fill.papermc.io/v3/projects/{project}")).await?;
        let json: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| CatalogError::Upstream(format!("papermc {project} parse: {e}")))?;
        let mut versions = Vec::new();
        if let Some(groups) = json.get("versions").and_then(|v| v.as_object()) {
            for group in groups.values() {
                if let Some(list) = group.as_array() {
                    for v in list {
                        if let Some(v) = v.as_str() {
                            let lower = v.to_lowercase();
                            if !lower.contains("rc") && !lower.contains("pre") {
                                versions.push(ServerVersion { version: v.to_string(), meta: None });
                            }
                        }
                    }
                }
            }
        }
        if versions.is_empty() {
            return Err(CatalogError::NoResult(format!("{project} versions")));
        }
        versions.reverse();
        Ok(versions)
    }

    /// Spigot / CraftBukkit:getbukkit.org 页面正则解析。
    async fn getbukkit_versions(&self, project: &str) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text(&format!("https://getbukkit.org/download/{project}")).await?;
        let re = regex_version()?;
        let mut versions: Vec<String> = re
            .captures_iter(&body)
            .filter_map(|c| c.get(1).map(|m| m.as_str().to_string()))
            .collect();
        versions.sort_by(|a, b| version_cmp(a, b));
        Ok(versions.into_iter().map(|v| ServerVersion { version: v, meta: None }).collect())
    }

    /// Purpur:api.purpurmc.org 版本列表,过滤 rc/pre 后倒序。
    async fn purpur_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.purpurmc.org/v2/purpur").await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("purpur parse: {e}")))?;
        let mut versions = Vec::new();
        if let Some(list) = json.get("versions").and_then(|v| v.as_array()) {
            for v in list {
                if let Some(v) = v.as_str() {
                    let lower = v.to_lowercase();
                    if !lower.contains("rc") && !lower.contains("pre") {
                        versions.push(ServerVersion { version: v.to_string(), meta: None });
                    }
                }
            }
        }
        versions.sort_by(|a, b| version_cmp(&b.version, &a.version));
        Ok(versions)
    }

    /// Leaf:api.leafmc.one 版本列表。
    async fn leaf_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.leafmc.one/v2/projects/leaf").await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("leaf parse: {e}")))?;
        let mut versions = Vec::new();
        if let Some(list) = json.get("versions").and_then(|v| v.as_array()) {
            for v in list {
                if let Some(v) = v.as_str() {
                    versions.push(ServerVersion { version: v.to_string(), meta: None });
                }
            }
        }
        versions.sort_by(|a, b| version_cmp(&b.version, &a.version));
        Ok(versions)
    }

    /// Leaves:api.leavesmc.org 版本列表,过滤 rc/pre 后倒序。
    async fn leaves_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.leavesmc.org/v2/projects/leaves").await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("leaves parse: {e}")))?;
        let mut versions = Vec::new();
        if let Some(list) = json.get("versions").and_then(|v| v.as_array()) {
            for v in list {
                if let Some(v) = v.as_str() {
                    let lower = v.to_lowercase();
                    if !lower.contains("rc") && !lower.contains("pre") {
                        versions.push(ServerVersion { version: v.to_string(), meta: None });
                    }
                }
            }
        }
        versions.sort_by(|a, b| version_cmp(&b.version, &a.version));
        Ok(versions)
    }

    /// Fabric:Minecraft 稳定版列表(meta.fabricmc.net/v2/versions/game)。
    async fn fabric_mc_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://meta.fabricmc.net/v2/versions/game").await?;
        let json: Vec<serde_json::Value> =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("fabricmc game parse: {e}")))?;
        let mut versions = Vec::new();
        for item in json {
            if item.get("stable").and_then(|s| s.as_bool()) == Some(true) {
                if let Some(v) = item.get("version").and_then(|v| v.as_str()) {
                    versions.push(ServerVersion { version: v.to_string(), meta: None });
                }
            }
        }
        if versions.is_empty() {
            return Err(CatalogError::NoResult("fabric mc versions".into()));
        }
        Ok(versions)
    }

    /// PocketMine-MP:5.x 稳定频道列表 + 各频道 mcpe_version(meta)。
    /// 数据源:update.pmmp.io 的 channels 目录 + 每个 channel 的 json。
    async fn pocketmine_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.github.com/repos/pmmp/update.pmmp.io/contents/channels").await?;
        let json: Vec<serde_json::Value> =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("pmmp channels parse: {e}")))?;
        let version_pattern = regex_version_5()?;
        let mut versions: Vec<String> = json
            .iter()
            .filter_map(|item| item.get("name").and_then(|n| n.as_str()))
            .filter_map(|name| {
                name.strip_suffix(".json").and_then(|base| {
                    if version_pattern.is_match(base) {
                        Some(base.to_string())
                    } else {
                        None
                    }
                })
            })
            .collect();
        versions.sort_by(|a, b| version_cmp(b, a));

        // 并发获取每个版本的 mcpe_version
        let mut result = Vec::with_capacity(versions.len());
        for v in &versions {
            let meta = self
                .pocketmine_mcpe_version(v)
                .await
                .map(|mcpe| {
                    let mut m = serde_json::Map::new();
                    m.insert("mcpeVersion".into(), serde_json::Value::String(mcpe));
                    m
                })
                .unwrap_or_default();
            result.push(ServerVersion { version: v.clone(), meta: (!meta.is_empty()).then_some(serde_json::Value::Object(meta)) });
        }
        Ok(result)
    }

    async fn pocketmine_mcpe_version(&self, version: &str) -> Option<String> {
        let url = format!("https://raw.githubusercontent.com/pmmp/update.pmmp.io/master/channels/{version}.json");
        let body = self.get_text(&url).await.ok()?;
        let json: serde_json::Value = serde_json::from_str(&body).ok()?;
        json.get("mcpe_version").and_then(|v| v.as_str()).map(ToString::to_string)
    }

    /// PowerNukkitX:GitHub Releases(tag_name 列表,降序)。
    async fn powernukkitx_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.github.com/repos/PowerNukkitX/PowerNukkitX/releases?per_page=100").await?;
        let json: Vec<serde_json::Value> =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("pnx releases parse: {e}")))?;
        let mut versions = Vec::new();
        for release in json {
            if let Some(tag) = release.get("tag_name").and_then(|t| t.as_str()) {
                versions.push(ServerVersion { version: tag.to_string(), meta: None });
            }
        }
        if versions.is_empty() {
            return Err(CatalogError::NoResult("powernukkitx versions".into()));
        }
        Ok(versions)
    }

    /// Allay:GitHub Releases(夜间版优先 + 全部 tag,降序)。
    async fn allay_versions(&self) -> Result<Vec<ServerVersion>, CatalogError> {
        let body = self.get_text("https://api.github.com/repos/AllayMC/Allay/releases?per_page=100").await?;
        let json: Vec<serde_json::Value> =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("allay releases parse: {e}")))?;
        let mut versions = Vec::new();
        for release in json {
            if let Some(tag) = release.get("tag_name").and_then(|t| t.as_str()) {
                versions.push(ServerVersion { version: tag.to_string(), meta: None });
            }
        }
        if versions.is_empty() {
            return Err(CatalogError::NoResult("allay versions".into()));
        }
        Ok(versions)
    }

    // ── 各源下载信息 ──────────────────────────────────────────────

    /// 原版:从版本详情 JSON 取 server jar 直链 + sha1。
    async fn vanilla_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "vanilla")?;
        let body = self.get_text("https://launchermeta.mojang.com/mc/game/version_manifest.json").await?;
        let manifest: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| CatalogError::Upstream(format!("mojang manifest parse: {e}")))?;
        // 查找该版本的详情 URL
        let mut detail_url = None;
        if let Some(list) = manifest.get("versions").and_then(|v| v.as_array()) {
            for item in list {
                if item.get("id").and_then(|i| i.as_str()) == Some(version) {
                    detail_url = item.get("url").and_then(|u| u.as_str()).map(ToString::to_string);
                    break;
                }
            }
        }
        let detail_url = detail_url.ok_or_else(|| CatalogError::NotFound(format!("vanilla version {version}")))?;
        let body = self.get_text(&detail_url).await?;
        let detail: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("vanilla {version} parse: {e}")))?;
        let server = detail
            .get("downloads")
            .and_then(|d| d.get("server"))
            .ok_or_else(|| CatalogError::NoResult(format!("vanilla {version} server jar")))?;
        let url = server
            .get("url")
            .and_then(|u| u.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("vanilla {version} download url")))?
            .to_string();
        let sha1 = server.get("sha1").and_then(|s| s.as_str()).map(ToString::to_string);
        Ok(ServerDownloadInfo {
            url,
            file_name: "server.jar".to_string(),
            checksum: sha1.map(|s| format!("sha1:{s}")),
            size_bytes: None,
        })
    }

    /// PaperMC 系(paper / velocity):builds/latest 的 server:default 直链 + sha256。
    async fn papermc_download_info(
        &self,
        project: &str,
        version: Option<&str>,
        file_name: &str,
    ) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, project)?;
        let url = format!("https://fill.papermc.io/v3/projects/{project}/versions/{version}/builds/latest");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("papermc {project} builds parse: {e}")))?;
        let server = json
            .get("downloads")
            .and_then(|d| d.get("server:default"))
            .ok_or_else(|| CatalogError::NoResult(format!("{project} {version} server:default")))?;
        let download_url = server
            .get("url")
            .and_then(|u| u.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("{project} {version} download url")))?
            .to_string();
        let sha256 = server
            .get("checksums")
            .and_then(|c| c.get("sha256"))
            .and_then(|s| s.as_str())
            .map(ToString::to_string);
        Ok(ServerDownloadInfo {
            url: download_url,
            file_name: file_name.to_string(),
            checksum: sha256.map(|s| format!("sha256:{s}")),
            size_bytes: None,
        })
    }

    /// Purpur:version 详情取 latest 构建号,组装下载直链。
    async fn purpur_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "purpur")?;
        let url = format!("https://api.purpurmc.org/v2/purpur/{version}");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("purpur {version} parse: {e}")))?;
        let latest = json
            .get("builds")
            .and_then(|b| b.get("latest"))
            .and_then(|l| l.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("purpur {version} latest build")))?;
        Ok(ServerDownloadInfo::no_checksum(
            format!("https://api.purpurmc.org/v2/purpur/{version}/{latest}/download"),
            "server.jar",
        ))
    }

    /// Leaf:versions/{version} 的 builds 取最大构建,primary 下载直链 + sha256。
    async fn leaf_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "leaf")?;
        let url = format!("https://api.leafmc.one/v2/projects/leaf/versions/{version}");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("leaf {version} parse: {e}")))?;
        let mut builds: Vec<i64> = json
            .get("builds")
            .and_then(|b| b.as_array())
            .map(|arr| arr.iter().filter_map(|b| b.as_i64()).collect())
            .unwrap_or_default();
        builds.sort_unstable();
        let latest = builds.last().ok_or_else(|| CatalogError::NoResult(format!("leaf {version} builds")))?;

        let url = format!("https://api.leafmc.one/v2/projects/leaf/versions/{version}/builds/{latest}");
        let body = self.get_text(&url).await?;
        let build: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("leaf {version}/{latest} parse: {e}")))?;
        let primary = build
            .get("downloads")
            .and_then(|d| d.get("primary"))
            .ok_or_else(|| CatalogError::NoResult(format!("leaf {version} primary download")))?;
        let name = primary
            .get("name")
            .and_then(|n| n.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("leaf {version} download name")))?
            .to_string();
        let sha256 = primary.get("sha256").and_then(|s| s.as_str()).map(ToString::to_string);
        Ok(ServerDownloadInfo {
            url: format!("https://api.leafmc.one/v2/projects/leaf/versions/{version}/builds/{latest}/downloads/{name}"),
            file_name: "server.jar".to_string(),
            checksum: sha256.map(|s| format!("sha256:{s}")),
            size_bytes: None,
        })
    }

    /// Leaves:builds/latest 的 application 下载直链 + sha256。
    async fn leaves_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "leaves")?;
        let url = format!("https://api.leavesmc.org/v2/projects/leaves/versions/{version}/builds/latest");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("leaves {version} parse: {e}")))?;
        let build = json.get("build").and_then(|b| b.as_i64()).unwrap_or(0);
        let app = json
            .get("downloads")
            .and_then(|d| d.get("application"))
            .ok_or_else(|| CatalogError::NoResult(format!("leaves {version} application")))?;
        let name = app
            .get("name")
            .and_then(|n| n.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("leaves {version} download name")))?
            .to_string();
        let sha256 = app.get("sha256").and_then(|s| s.as_str()).map(ToString::to_string);
        Ok(ServerDownloadInfo {
            url: format!("https://api.leavesmc.org/v2/projects/leaves/versions/{version}/builds/{build}/downloads/{name}"),
            file_name: "server.jar".to_string(),
            checksum: sha256.map(|s| format!("sha256:{s}")),
            size_bytes: None,
        })
    }

    /// BungeeCord:ci.md-5.net 最新构建,组装 BungeeCord.jar 直链。无版本选择。
    async fn bungeecord_download_info(&self) -> Result<ServerDownloadInfo, CatalogError> {
        let body = self.get_text("https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/api/json").await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("bungeecord build parse: {e}")))?;
        let build = json
            .get("number")
            .and_then(|n| n.as_i64())
            .ok_or_else(|| CatalogError::NoResult("bungeecord build number".into()))?;
        Ok(ServerDownloadInfo::no_checksum(
            format!("https://ci.md-5.net/job/BungeeCord/{build}/artifact/bootstrap/target/BungeeCord.jar"),
            "bungeecord.jar",
        ))
    }

    /// Fabric:组装 meta.fabricmc.net 的 server/jar 直链(需 MC 版本 + 加载器版本)。
    async fn fabric_download_info(
        &self,
        mc_version: Option<&str>,
        loader_version: Option<&str>,
    ) -> Result<ServerDownloadInfo, CatalogError> {
        let mc = mc_version.filter(|s| !s.is_empty()).ok_or_else(|| {
            CatalogError::BadRequest("fabric 需提供 mcVersion".into())
        })?;
        let loader = loader_version.filter(|s| !s.is_empty()).ok_or_else(|| {
            CatalogError::BadRequest("fabric 需提供 loaderVersion".into())
        })?;
        // 查询最新 installer 版本
        let body = self.get_text("https://meta.fabricmc.net/v2/versions/installer").await?;
        let installers: Vec<serde_json::Value> = serde_json::from_str(&body)
            .map_err(|e| CatalogError::Upstream(format!("fabricmc installer parse: {e}")))?;
        let installer = installers
            .first()
            .and_then(|i| i.get("version"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| CatalogError::NoResult("fabricmc installer version".into()))?;
        Ok(ServerDownloadInfo::no_checksum(
            format!("https://meta.fabricmc.net/v2/versions/loader/{mc}/{loader}/{installer}/server/jar"),
            "server.jar",
        ))
    }

    /// PocketMine-MP:channel 详情 json 的 download_url。
    async fn pocketmine_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "pocketmine")?;
        let url = format!("https://raw.githubusercontent.com/pmmp/update.pmmp.io/master/channels/{version}.json");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("pmmp {version} parse: {e}")))?;
        let download_url = json
            .get("download_url")
            .and_then(|u| u.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("pmmp {version} download_url")))?
            .to_string();
        Ok(ServerDownloadInfo::no_checksum(download_url, "PocketMine-MP.phar"))
    }

    /// PowerNukkitX / 通用 GitHub release jar:取 .jar 资产,优先 shaded。
    async fn github_release_jar(
        &self,
        repo: &str,
        version: Option<&str>,
        file_name: &str,
    ) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, repo)?;
        let url = format!("https://api.github.com/repos/{repo}/releases/tags/{version}");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| CatalogError::Upstream(format!("github {repo} {version} parse: {e}")))?;
        let assets = json.get("assets").and_then(|a| a.as_array()).cloned().unwrap_or_default();
        let mut fallback: Option<String> = None;
        let mut shaded: Option<String> = None;
        for asset in &assets {
            let name = asset.get("name").and_then(|n| n.as_str()).unwrap_or("");
            if name.ends_with(".jar") {
                let download_url = asset.get("browser_download_url").and_then(|u| u.as_str());
                if fallback.is_none() {
                    fallback = download_url.map(ToString::to_string);
                }
                if name.to_lowercase().contains("shaded") {
                    shaded = download_url.map(ToString::to_string);
                    break;
                }
            }
        }
        let download_url = shaded.or(fallback)
            .ok_or_else(|| CatalogError::NoResult(format!("{repo} {version} jar asset")))?;
        Ok(ServerDownloadInfo::no_checksum(download_url, file_name))
    }

    /// Allay:release tags/{version} 的 allay 前缀资产 + sha256(digest)。
    async fn allay_download_info(&self, version: Option<&str>) -> Result<ServerDownloadInfo, CatalogError> {
        let version = version_required(version, "allay")?;
        let url = format!("https://api.github.com/repos/AllayMC/Allay/releases/tags/{version}");
        let body = self.get_text(&url).await?;
        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| CatalogError::Upstream(format!("allay {version} parse: {e}")))?;
        let assets = json.get("assets").and_then(|a| a.as_array()).cloned().unwrap_or_default();
        if assets.is_empty() {
            return Err(CatalogError::NoResult(format!("allay {version} assets")));
        }
        let mut asset: Option<&serde_json::Value> = None;
        for a in &assets {
            let name = a.get("name").and_then(|n| n.as_str()).unwrap_or("");
            if name.starts_with("allay") {
                asset = Some(a);
                break;
            }
        }
        let asset = asset.or_else(|| assets.first()).ok_or_else(|| CatalogError::NoResult(format!("allay {version} asset")))?;
        let download_url = asset
            .get("browser_download_url")
            .and_then(|u| u.as_str())
            .ok_or_else(|| CatalogError::NoResult(format!("allay {version} download url")))?
            .to_string();
        let sha256 = asset
            .get("digest")
            .and_then(|d| d.as_str())
            .and_then(|d| d.strip_prefix("sha256:"))
            .map(ToString::to_string);
        Ok(ServerDownloadInfo {
            url: download_url,
            file_name: "allay-server.jar".to_string(),
            checksum: sha256.map(|s| format!("sha256:{s}")),
            size_bytes: None,
        })
    }

    // ── HTTP 工具 ──────────────────────────────────────────────────

    async fn get_text(&self, url: &str) -> Result<String, CatalogError> {
        let resp = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|e| CatalogError::Upstream(format!("request {url}: {e}")))?;
        let status = resp.status();
        if !status.is_success() {
            if status == reqwest::StatusCode::NOT_FOUND {
                return Err(CatalogError::NotFound(url.to_string()));
            }
            return Err(CatalogError::Upstream(format!("{url} -> HTTP {status}")));
        }
        resp.text().await.map_err(|e| CatalogError::Upstream(format!("read {url}: {e}")))
    }
}

/// 服务器类型静态定义(契约 ServerTypeInfo)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerTypeInfo {
    #[serde(rename = "type")]
    pub type_id: String,
    pub category: &'static str,
    #[serde(default)]
    pub has_loader: bool,
    pub file_name: String,
}

/// 可选服务端类型全集(分类结构与 V1 一致;模组端本期仅 fabric)。
pub fn server_types() -> Vec<ServerTypeInfo> {
    let mut list = vec![
        ServerTypeInfo { type_id: "vanilla".into(), category: "vanilla", has_loader: false, file_name: "server.jar".into() },
        // 插件
        ServerTypeInfo { type_id: "paper".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "spigot".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "craftbukkit".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "purpur".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "leaf".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "leaves".into(), category: "plugin", has_loader: false, file_name: "server.jar".into() },
        // 模组
        ServerTypeInfo { type_id: "fabric".into(), category: "mod", has_loader: true, file_name: "server.jar".into() },
        // 代理
        ServerTypeInfo { type_id: "velocity".into(), category: "proxy", has_loader: false, file_name: "server.jar".into() },
        ServerTypeInfo { type_id: "bungeecord".into(), category: "proxy", has_loader: false, file_name: "bungeecord.jar".into() },
        // 基岩
        ServerTypeInfo { type_id: "pocketmine".into(), category: "bedrock", has_loader: false, file_name: "PocketMine-MP.phar".into() },
        ServerTypeInfo { type_id: "powernukkitx".into(), category: "bedrock", has_loader: false, file_name: "powernukkitx.jar".into() },
        ServerTypeInfo { type_id: "allay".into(), category: "bedrock", has_loader: false, file_name: "allay-server.jar".into() },
    ];
    list.sort_by(|a, b| a.type_id.cmp(&b.type_id));
    list
}

/// 版本条目(契约 ServerVersion)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerVersion {
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meta: Option<serde_json::Value>,
}

/// 下载信息(契约 ServerDownloadInfo)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerDownloadInfo {
    pub url: String,
    pub file_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checksum: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<i64>,
}

impl ServerDownloadInfo {
    fn no_checksum(url: String, file_name: &str) -> Self {
        ServerDownloadInfo { url, file_name: file_name.to_string(), checksum: None, size_bytes: None }
    }
}

/// 目录错误(handler 层映射 HTTP 状态码)。
#[derive(Debug)]
pub enum CatalogError {
    /// 未知服务端类型(400)。
    UnsupportedType(String),
    /// 必填参数缺失/非法(400)。
    BadRequest(String),
    /// 上游返回结构不符合预期(502)。
    Upstream(String),
    /// 指定版本/构建不存在(404)。
    NotFound(String),
    /// 上游没有可用结果(502)。
    NoResult(String),
}

// ── 工具函数 ──────────────────────────────────────────────────────

fn version_required<'a>(version: Option<&'a str>, type_id: &str) -> Result<&'a str, CatalogError> {
    version
        .filter(|s| !s.is_empty())
        .ok_or_else(|| CatalogError::BadRequest(format!("{type_id} 需提供 version")))
}

fn regex_version() -> Result<regex::Regex, CatalogError> {
    regex::Regex::new(r"<h4>Version</h4>\s*<h2>([\d.]+)</h2>")
        .map_err(|e| CatalogError::Upstream(format!("compile version regex: {e}")))
}

fn regex_version_5() -> Result<regex::Regex, CatalogError> {
    regex::Regex::new(r"^5(\.\d+)*$")
        .map_err(|e| CatalogError::Upstream(format!("compile pocketmine version regex: {e}")))
}

/// 数字分段比较(a、b 为版本号;sort_by(cmp) 直接用于升序)。
fn version_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let pa: Vec<i64> = a.split('.').filter_map(|s| s.parse().ok()).collect();
    let pb: Vec<i64> = b.split('.').filter_map(|s| s.parse().ok()).collect();
    for i in 0..pa.len().max(pb.len()) {
        let va = if i < pa.len() { pa[i] } else { 0 };
        let vb = if i < pb.len() { pb[i] } else { 0 };
        if va != vb {
            return va.cmp(&vb);
        }
    }
    std::cmp::Ordering::Equal
}