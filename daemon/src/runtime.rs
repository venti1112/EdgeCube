//! 运行时环境管理(契约 /runtimes/*)。
//!
//! 目录布局(均在 daemon 数据目录下):
//!   runtimes/{id}/runtime.json   运行时元数据(RuntimeInfo 的 JSON)
//!   runtimes/{id}/…              运行时本体(如 java 的 bin/ lib/ 顶层目录)
//!   runtimes/.tmp-{uuid}/        安装任务暂存区(下载 + 解压,终结即清理)
//!
//! 运行时 id 为 `{type}-{version}` 的文件系统安全形式(如 `java-21.0.5+11`);
//! 卸载即删除整个 `{id}` 目录。`default` 为派生字段:每类运行时中版本最新者
//! 标记为默认(不落盘)。
//!
//! 可安装版本清单经官方渠道代取(java: Adoptium API,按当前平台 OS/架构
//! 过滤 JRE 归档;php/frpc 渠道待接入,返回 unsupported)。

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use aria2_core::request::request_group::{DownloadStatus, DownloadStatusSnapshot};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::download::DownloadManager;
use crate::fs::extract_archive;
use crate::task::model::{TaskFailure, TaskProgress};
use crate::task::service::TaskHandle;

/// 运行时目录根名 / 元数据文件名(相对 daemon 数据目录)。
const RUNTIMES_DIR: &str = "runtimes";
const META_FILE: &str = "runtime.json";
/// 版本清单 TTL(Adoptium 是公开 API,5 分钟缓存足够 UI 使用)。
const CATALOG_TTL: Duration = Duration::from_secs(300);
/// 安装任务轮询下载进度的间隔(与 download 模块轮询口径一致)。
const INSTALL_POLL_INTERVAL: Duration = Duration::from_millis(300);
/// 引擎停机后轮询仍拿不到状态的兜底次数(约 6s),避免死循环。
const MAX_IDLE_POLLS: u32 = 20;

// ────────────────────────── 模型(对齐 openapi.yaml) ──────────────────────────

/// 运行时类型(契约 RuntimeType)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeType {
    Java,
    Php,
    Frpc,
}

impl RuntimeType {
    fn as_str(self) -> &'static str {
        match self {
            RuntimeType::Java => "java",
            RuntimeType::Php => "php",
            RuntimeType::Frpc => "frpc",
        }
    }
}

/// 已安装运行时(契约 RuntimeInfo;`default` 为 list 时派生,不落盘)。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeInfo {
    pub id: String,
    #[serde(rename = "type")]
    pub runtime_type: RuntimeType,
    pub version: String,
    #[serde(default)]
    pub arch: Option<String>,
    /// 运行时主目录绝对路径(如 java 指向含 bin/ 的目录)。
    pub path: String,
    #[serde(default)]
    pub size_bytes: Option<i64>,
    pub installed_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<bool>,
}

/// 可安装版本条目(契约 RuntimeCatalogEntry)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeCatalogEntry {
    pub version: String,
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size_bytes: Option<i64>,
}

/// 可安装版本清单(契约 RuntimeCatalog;新版本在前,首个为推荐版本)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeCatalog {
    #[serde(rename = "type")]
    pub runtime_type: RuntimeType,
    pub entries: Vec<RuntimeCatalogEntry>,
}

/// 安装请求(契约 RuntimeInstallRequest)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeInstallRequest {
    #[serde(rename = "type")]
    pub runtime_type: RuntimeType,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub arch: Option<String>,
    /// 覆盖官方源地址(开发者选项);提供后跳过清单,不做校验值校验。
    #[serde(default)]
    pub url: Option<String>,
}

/// 安装任务的实际执行计划(handler 解析请求后生成,交任务队列执行)。
#[derive(Debug, Clone)]
pub struct InstallPlan {
    pub id: String,
    pub runtime_type: RuntimeType,
    pub version: String,
    pub arch: Option<String>,
    pub url: String,
    /// "sha256:<hex>";自定义 url 时为 None(跳过校验)。
    pub checksum: Option<String>,
    /// 归档落盘文件名(由 URL 末段推导)。
    pub file_name: String,
}

// ────────────────────────── 错误(handler 层映射 HTTP 状态码) ──────────────────────────

#[derive(Debug)]
pub enum RuntimeError {
    /// 运行时不存在(404)。
    NotFound(String),
    /// 该类型/平台暂不支持在线安装(400)。
    Unsupported(String),
    /// 请求参数不合法(400)。
    BadRequest(String),
    /// 上游清单不可用(502)。
    Upstream(String),
    /// 上游没有可用结果(502)。
    NoResult(String),
    /// 本地 IO(500)。
    Io(std::io::Error),
}

// ────────────────────────── 管理器 ──────────────────────────

/// 运行时管理器:`{data}/runtimes` 扫描注册 + 版本清单代理 + 安装目录操作。
pub struct RuntimeManager {
    /// `{data}/runtimes`。
    root: PathBuf,
    /// 内存注册表:id -> 元数据(与 runtime.json 同步落盘)。
    runtimes: RwLock<HashMap<String, RuntimeInfo>>,
    client: reqwest::Client,
    /// 版本清单缓存:类型 -> (时间, 清单)。
    catalog_cache: Mutex<HashMap<(RuntimeType, bool), (Instant, RuntimeCatalog)>>,
}

impl RuntimeManager {
    /// 扫描 `{data}/runtimes` 加载已安装运行时。
    pub fn load(data_dir: &Path) -> std::io::Result<Self> {
        let root = data_dir.join(RUNTIMES_DIR);
        fs::create_dir_all(&root)?;

        let mut runtimes = HashMap::new();
        for entry in fs::read_dir(&root)?.flatten() {
            let dir = entry.path();
            if !dir.is_dir() {
                continue;
            }
            // 暂存区(.tmp-*)与无元数据目录不注册;id 以目录名为准
            let Some(id) = dir.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if id.starts_with('.') {
                continue;
            }
            match fs::read(dir.join(META_FILE)) {
                Ok(bytes) => match serde_json::from_slice::<RuntimeInfo>(&bytes) {
                    Ok(mut info) => {
                        info.path = dir.to_string_lossy().into_owned();
                        runtimes.insert(id.to_string(), info);
                    }
                    Err(e) => {
                        tracing::warn!(path = %dir.display(), "skipping unparsable runtime meta: {e}");
                    }
                },
                Err(_) => {
                    tracing::warn!(path = %dir.display(), "skipping dir without runtime.json");
                }
            }
        }

        tracing::info!(count = runtimes.len(), "runtimes loaded");
        Ok(RuntimeManager {
            root,
            runtimes: RwLock::new(runtimes),
            client: reqwest::Client::builder()
                .user_agent(concat!("EdgeCube/", env!("CARGO_PKG_VERSION")))
                .connect_timeout(Duration::from_secs(5))
                .timeout(Duration::from_secs(12))
                .build()
                .expect("build reqwest client"),
            catalog_cache: Mutex::new(HashMap::new()),
        })
    }

    /// 安装目录根(安装任务落盘用)。
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// 已安装运行时列表(同类型按版本号降序;每类最新者标记 default)。
    pub async fn list(&self) -> Vec<RuntimeInfo> {
        let runtimes = self.runtimes.read().await;
        let mut items: Vec<RuntimeInfo> = runtimes.values().cloned().collect();
        items.sort_by(|a, b| {
            a.runtime_type
                .as_str()
                .cmp(b.runtime_type.as_str())
                .then_with(|| version_cmp(&b.version, &a.version))
        });
        // 派生默认:每类第一个(版本最新)为默认
        let mut seen = std::collections::HashSet::new();
        for info in &mut items {
            let is_first = seen.insert(info.runtime_type);
            info.default = Some(is_first);
        }
        items
    }

    /// 按 id 查询已安装运行时信息(未安装/已卸载 → None)。
    pub async fn get(&self, id: &str) -> Option<RuntimeInfo> {
        self.runtimes.read().await.get(id).cloned()
    }

    /// frpc 可执行文件路径(取版本最新的 frpc 运行时);未安装 → None。
    ///
    /// 同步版本(供 frp 模块进程控制注入的解析器使用,blocking_read 只在
    /// 非 async 上下文中短暂持有读锁)。
    pub fn frpc_binary(&self) -> Option<PathBuf> {
        let runtimes = self.runtimes.blocking_read();
        let frpc = runtimes
            .values()
            .filter(|i| i.runtime_type == RuntimeType::Frpc)
            .max_by(|a, b| version_cmp(&a.version, &b.version))?;
        let exe = if cfg!(windows) { "frpc.exe" } else { "frpc" };
        Some(PathBuf::from(&frpc.path).join(exe))
    }

    /// 卸载运行时:删除目录与注册表项;不存在返回 404 语义错误。
    pub async fn delete(&self, id: &str) -> Result<(), RuntimeError> {
        let removed = {
            let mut runtimes = self.runtimes.write().await;
            runtimes.remove(id)
        };
        if removed.is_none() {
            return Err(RuntimeError::NotFound(id.to_string()));
        }
        let dir = self.root.join(sanitize_component(id));
        if dir.exists() {
            fs::remove_dir_all(&dir).map_err(RuntimeError::Io)?;
        }
        tracing::info!(runtime = id, "runtime uninstalled");
        Ok(())
    }

    /// 安装完成后登记(目录与 runtime.json 已由任务落盘)。
    pub async fn register(&self, info: RuntimeInfo) {
        self.runtimes.write().await.insert(info.id.clone(), info);
    }

    // ── 版本清单 ─────────────────────────────────────────────────

    /// 拉取可安装版本清单(带缓存;`include_all` 为 true 时拉全量版本,
    /// false 时 frpc 仅拉最新 release,避免无关旧版本请求)。
    /// 全程记录耗时日志,便于远端排查清单加载问题。
    /// 缓存按 (类型, include_all) 分别命中:展开旧版本/安装旧版本时
    /// 不会被“仅最新”的快照挡住。
    pub async fn catalog(
        &self,
        runtime_type: RuntimeType,
        include_all: bool,
    ) -> Result<RuntimeCatalog, RuntimeError> {
        let started = Instant::now();
        let key = (runtime_type, include_all);
        if let Some((at, catalog)) = self.catalog_cache.lock().unwrap().get(&key) {
            if at.elapsed() < CATALOG_TTL {
                return Ok(catalog.clone());
            }
        }
        let catalog = match runtime_type {
            RuntimeType::Java => self.java_catalog().await?,
            RuntimeType::Frpc => self.frpc_catalog(include_all).await?,
            other => {
                return Err(RuntimeError::Unsupported(format!(
                    "{} 在线安装渠道尚未接入",
                    other.as_str()
                )));
            }
        };
        self.catalog_cache
            .lock()
            .unwrap()
            .insert(key, (Instant::now(), catalog.clone()));
        tracing::info!(
            runtime_type = runtime_type.as_str(),
            include_all,
            entries = catalog.entries.len(),
            elapsed_ms = started.elapsed().as_millis() as u64,
            "runtime catalog served"
        );
        Ok(catalog)
    }

    /// 由请求解析安装计划:自定义 url 直通;否则查清单取指定版本或推荐版本。
    pub async fn plan_install(&self, req: RuntimeInstallRequest) -> Result<InstallPlan, RuntimeError> {
        let arch = Some(
            req.arch
                .clone()
                .unwrap_or_else(|| match req.runtime_type {
                    // frpc 的架构记法为 amd64/arm64/386/arm(与 Adoptium 的 x64 不同)
                    RuntimeType::Frpc => frp_platform()
                        .map(|(_, a)| a)
                        .unwrap_or_else(|_| current_arch()),
                    _ => current_arch(),
                }),
        )
        .filter(|s| !s.is_empty());

        if let Some(url) = req.url.clone().filter(|s| !s.is_empty()) {
            if !url.starts_with("http://") && !url.starts_with("https://") {
                return Err(RuntimeError::BadRequest("url must be an http(s) url".into()));
            }
            let file_name = filename_from_url(&url).to_string();
            let version = req
                .version
                .clone()
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| file_stem(&file_name));
            let id = format!("{}-{}", req.runtime_type.as_str(), sanitize_component(&version));
            return Ok(InstallPlan {
                id,
                runtime_type: req.runtime_type,
                version,
                arch,
                url,
                checksum: None,
                file_name,
            });
        }

        let catalog = self.catalog(req.runtime_type, true).await?;
        let version = req.version.clone().filter(|s| !s.is_empty());
        let entry = match version {
            Some(v) => catalog
                .entries
                .iter()
                .find(|e| e.version == v)
                .ok_or_else(|| RuntimeError::NotFound(format!("{} {}", req.runtime_type.as_str(), v)))?,
            // 缺省取推荐版本(清单首个,新版本在前)
            None => catalog
                .entries
                .first()
                .ok_or_else(|| RuntimeError::NoResult(format!("{} catalog", req.runtime_type.as_str())))?,
        };
        let id = format!("{}-{}", req.runtime_type.as_str(), sanitize_component(&entry.version));
        Ok(InstallPlan {
            id,
            runtime_type: req.runtime_type,
            version: entry.version.clone(),
            arch,
            url: entry.url.clone(),
            checksum: entry.sha256.as_deref().map(|s| format!("sha256:{s}")),
            file_name: filename_from_url(&entry.url).to_string(),
        })
    }

    /// Adoptium(Temurin)JRE 清单:各 LTS 特性版本的 latest 归档,新版本在前。
    ///
    /// v3 资产端点路径为 `/assets/latest/{feature}/{project}`
    /// (project = hotspot/openj9;旧的 `/{feature}/ga?project=jdk` 已下线,
    /// 返回条目为 `binary` 单对象而非 `binaries` 数组)。
    async fn java_catalog(&self) -> Result<RuntimeCatalog, RuntimeError> {
        let os = match std::env::consts::OS {
            "windows" => "windows",
            "linux" => "linux",
            "macos" => "mac",
            other => {
                return Err(RuntimeError::Unsupported(format!(
                    "java 运行时清单暂不支持平台 {other}"
                )));
            }
        };
        let arch = current_arch();

        let releases: serde_json::Value = self
            .get_json("https://api.adoptium.net/v3/info/available_releases")
            .await?;
        let mut lts: Vec<u32> = releases
            .get("available_lts_releases")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|v| v.as_u64().map(|n| n as u32)).collect())
            .unwrap_or_default();
        if lts.is_empty() {
            return Err(RuntimeError::NoResult("adoptium lts releases".into()));
        }
        lts.sort_unstable_by(|a, b| b.cmp(a));

        let mut entries = Vec::new();
        // 全部特性版本都失败时透出底层原因(404 = 该平台无 JRE,属正常跳过)
        let mut last_error: Option<String> = None;
        for feature in lts {
            let url = format!(
                "https://api.adoptium.net/v3/assets/latest/{feature}/hotspot?os={os}&architecture={arch}&image_type=jre"
            );
            match self.get_json::<Vec<serde_json::Value>>(&url).await {
                Ok(assets) => {
                    if let Some(entry) = assets.first().and_then(adoptium_entry) {
                        entries.push(entry);
                    }
                }
                // 个别 LTS 在当前平台无 JRE(如 mac + 8):跳过该版本
                Err(e @ RuntimeError::NotFound(_)) => {
                    tracing::debug!(feature, "adoptium jre unavailable: {e:?}");
                }
                Err(e) => {
                    tracing::warn!(feature, error = ?e, "adoptium feature fetch failed");
                    last_error = Some(e.to_string());
                }
            }
        }
        if entries.is_empty() {
            return Err(match last_error {
                Some(detail) => RuntimeError::Upstream(format!("adoptium 资产查询失败:{detail}")),
                None => RuntimeError::NoResult("adoptium jre assets".into()),
            });
        }
        Ok(RuntimeCatalog {
            runtime_type: RuntimeType::Java,
            entries,
        })
    }

    async fn get_json<T: serde::de::DeserializeOwned>(&self, url: &str) -> Result<T, RuntimeError> {
        let resp = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|e| RuntimeError::Upstream(format!("request {url}: {e}")))?;
        let status = resp.status();
        if !status.is_success() {
            // 404 = 上游无该资源(如某 LTS 在当前平台无 JRE),调用方据此跳过
            if status == reqwest::StatusCode::NOT_FOUND {
                return Err(RuntimeError::NotFound(format!("{url} -> HTTP 404")));
            }
            return Err(RuntimeError::Upstream(format!("{url} -> HTTP {status}")));
        }
        resp.json::<T>()
            .await
            .map_err(|e| RuntimeError::Upstream(format!("parse {url}: {e}")))
    }

    /// 拉取纯文本资源(状态码映射与 [Self::get_json] 一致,用于 checksum 文件)。
    async fn get_text(&self, url: &str) -> Result<String, RuntimeError> {
        let resp = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|e| RuntimeError::Upstream(format!("request {url}: {e}")))?;
        let status = resp.status();
        if !status.is_success() {
            if status == reqwest::StatusCode::NOT_FOUND {
                return Err(RuntimeError::NotFound(format!("{url} -> HTTP 404")));
            }
            return Err(RuntimeError::Upstream(format!("{url} -> HTTP {status}")));
        }
        resp.text()
            .await
            .map_err(|e| RuntimeError::Upstream(format!("read {url}: {e}")))
    }

    /// GitHub Releases(fatedier/frp)清单:默认(`include_all=false`)走
    /// `/releases/latest` 仅取**最新 release** 一个对象(1 次请求 + 1 次
    /// checksum);点击展开旧版本(`include_all=true`)才走列表端点拉全量。
    /// 资产名形如 `frp_{version}_{os}_{arch}.{ext}`,版本去 v 前缀。
    /// 各 release 的 checksum 文件并行拉取(避免串行 10+ 次请求把清单加载
    /// 拖到数秒,连接层易被中断)。
    ///
    /// GitHub 未认证 API 限流 60/h,由 catalog_cache(5 分钟 TTL)兜底。
    async fn frpc_catalog(&self, include_all: bool) -> Result<RuntimeCatalog, RuntimeError> {
        let (os, arch) = frp_platform()?;
        let suffix = format!("_{os}_{arch}");
        // 默认只请求 latest;展开旧版本才请求列表
        let (url, releases): (String, Vec<serde_json::Value>) = if include_all {
            let url = "https://api.github.com/repos/fatedier/frp/releases?per_page=10".to_string();
            let list: Vec<serde_json::Value> = self.get_json(&url).await?;
            (url, list)
        } else {
            let url = "https://api.github.com/repos/fatedier/frp/releases/latest".to_string();
            tracing::info!(%url, "frpc catalog upstream request");
            let latest: serde_json::Value = self.get_json(&url).await?;
            (url, vec![latest])
        };
        tracing::info!(%url, include_all, fetched = releases.len(), "frpc releases fetched");
        // 候选:(版本, url, 大小, release 下标, 资产名)
        let mut cands: Vec<(String, String, Option<i64>, usize, String)> = Vec::new();
        for (idx, release) in releases.iter().enumerate() {
            // 跳过草稿与预发布
            if release.get("draft").and_then(|v| v.as_bool()).unwrap_or(false) {
                continue;
            }
            if release.get("prerelease").and_then(|v| v.as_bool()).unwrap_or(false) {
                continue;
            }
            let tag = release.get("tag_name").and_then(|v| v.as_str()).unwrap_or("");
            let version = tag.strip_prefix('v').unwrap_or(tag);
            if version.is_empty() {
                continue;
            }
            let Some(asset) = release.get("assets").and_then(|v| v.as_array()).and_then(|a| {
                a.iter().find(|a| {
                    let name = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
                    frpc_asset_match(name, version, &suffix)
                })
            }) else {
                continue;
            };
            let url = asset
                .get("browser_download_url")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            if url.is_empty() {
                continue;
            }
            let size = asset.get("size").and_then(|v| v.as_i64());
            let name = asset
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            cands.push((version.to_string(), url, size, idx, name));
        }
        // 并行拉各候选 release 的 checksum(单条失败仅降级为无校验,不阻塞清单)
        let checksums: Vec<_> = futures_util::future::join_all(
            cands
                .iter()
                .map(|(_, _, _, idx, name)| self.frpc_checksum(&releases[*idx], name)),
        )
        .await;
        let mut entries = Vec::with_capacity(cands.len());
        for ((version, url, size, _, _), checksum) in cands.into_iter().zip(checksums) {
            let sha256 = match checksum {
                Ok(v) => v,
                Err(e) => {
                    tracing::debug!(version, error = ?e, "frpc checksum fetch failed");
                    None
                }
            };
            entries.push(RuntimeCatalogEntry {
                version,
                url,
                sha256,
                size_bytes: size,
            });
        }
        entries.sort_by(|a, b| version_cmp(&b.version, &a.version));
        if entries.is_empty() {
            return Err(RuntimeError::NoResult(
                "fatedier/frp releases for current platform".into(),
            ));
        }
        tracing::info!(include_all, entries = entries.len(), "frpc catalog built");
        Ok(RuntimeCatalog {
            runtime_type: RuntimeType::Frpc,
            entries,
        })
    }

    /// 从 release 的 checksum 资产(名含 "sha256"/"checksum" 的 .txt,如
    /// `frp_sha256_checksums.txt` / `sha256sum.txt`)解析指定资产名的 sha256;
    /// 无 checksum 资产或文件内无该资产行 → None。
    async fn frpc_checksum(
        &self,
        release: &serde_json::Value,
        asset_name: &str,
    ) -> Result<Option<String>, RuntimeError> {
        let Some(ca) = release.get("assets").and_then(|v| v.as_array()).and_then(|a| {
            a.iter().find(|a| {
                let n = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
                (n.contains("sha256") || n.contains("checksum")) && n.ends_with(".txt")
            })
        }) else {
            return Ok(None);
        };
        let Some(url) = ca.get("browser_download_url").and_then(|v| v.as_str()) else {
            return Ok(None);
        };
        let text = self.get_text(url).await?;
        Ok(checksum_line(&text, asset_name))
    }
}

// ────────────────────────── 安装任务执行体 ──────────────────────────

/// 运行时安装任务(task 队列 runner,全局任务):
/// 下载归档到暂存区 → sha256 校验 → 解压 → 展平单层根目录 → 写 runtime.json → 登记。
/// 任何失败/取消均清理暂存区,不留半成品。
pub async fn run_runtime_install_task(
    handle: TaskHandle,
    dm: DownloadManager,
    manager: Arc<RuntimeManager>,
    plan: InstallPlan,
) -> Result<(), TaskFailure> {
    let temp = manager.root().join(format!(".tmp-{}", Uuid::new_v4()));
    fs::create_dir_all(&temp)
        .map_err(|e| TaskFailure::new("install_failed", format!("cannot create temp dir: {e}")))?;

    // 统一收尾:成功路径之外一律清理暂存区
    let result = install_inner(&handle, &dm, &manager, &plan, &temp).await;
    if result.is_err() || handle.is_cancelled() {
        let _ = fs::remove_dir_all(&temp);
    }
    result
}

async fn install_inner(
    handle: &TaskHandle,
    dm: &DownloadManager,
    manager: &Arc<RuntimeManager>,
    plan: &InstallPlan,
    temp: &Path,
) -> Result<(), TaskFailure> {
    // ── 下载(复用下载引擎,轮询进度与取消) ──────────────────────
    handle.set_phase("downloading").await;
    let gid = dm
        .add(&plan.url, temp, Some(&plan.file_name), false)
        .map_err(|e| TaskFailure::new("install_failed", format!("add download: {e}")))?;
    tracing::info!(runtime = %plan.id, url = %plan.url, "runtime download started");

    let mut idle_polls: u32 = 0;
    loop {
        if handle.is_cancelled() {
            dm.cancel(gid);
            return Err(TaskFailure::new("cancelled", "cancelled"));
        }
        match dm.snapshot(gid) {
            Some(snapshot) => {
                idle_polls = 0;
                set_download_progress(handle, &snapshot).await;
                match snapshot.status {
                    DownloadStatus::Complete => break,
                    DownloadStatus::Error(_) => {
                        return Err(TaskFailure::new("install_failed", "download failed"));
                    }
                    DownloadStatus::Removed => {
                        return Err(TaskFailure::new("install_failed", "download removed"));
                    }
                    _ => tokio::time::sleep(INSTALL_POLL_INTERVAL).await,
                }
            }
            // group 已终结(demote):查结果确认成败;未就绪则继续等
            None => {
                if let Some(result) = dm.stopped_result(gid) {
                    if result.status.is_completed() {
                        break;
                    }
                    return Err(TaskFailure::new("install_failed", result.message));
                }
                idle_polls += 1;
                if idle_polls > MAX_IDLE_POLLS {
                    return Err(TaskFailure::new(
                        "install_failed",
                        "download engine stopped while waiting",
                    ));
                }
                tokio::time::sleep(INSTALL_POLL_INTERVAL).await;
            }
        }
    }

    // ── sha256 校验 ──────────────────────────────────────────────
    let archive = temp.join(&plan.file_name);
    if let Some(checksum) = &plan.checksum {
        handle.set_phase("verifying").await;
        if handle.is_cancelled() {
            return Err(TaskFailure::new("cancelled", "cancelled"));
        }
        let expected = checksum.split_once(':').map(|(_, hex)| hex).unwrap_or(checksum);
        let actual = sha256_hex(&archive)
            .map_err(|e| TaskFailure::new("install_failed", format!("cannot read archive: {e}")))?;
        if !expected.eq_ignore_ascii_case(&actual) {
            return Err(TaskFailure::new(
                "install_failed",
                format!("checksum mismatch: expected {expected}, actual {actual}"),
            ));
        }
    }

    // ── 解压 + 展平 ──────────────────────────────────────────────
    handle.set_phase("extracting").await;
    if handle.is_cancelled() {
        return Err(TaskFailure::new("cancelled", "cancelled"));
    }
    let staging = temp.join("staging");
    fs::create_dir_all(&staging)
        .map_err(|e| TaskFailure::new("install_failed", format!("cannot create staging dir: {e}")))?;
    extract_archive(&archive, &staging)
        .map_err(|e| TaskFailure::new("install_failed", format!("extract: {e}")))?;

    // 归档常带单层根目录(如 jdk-21.0.5+11/):展平,使运行时目录直接含 bin/
    let source = single_root(&staging).unwrap_or(staging);

    // 目标已存在(重复安装):先摘除注册表项与旧目录,再改名进入位置
    let target = manager.root().join(&plan.id);
    manager.runtimes.write().await.remove(&plan.id);
    if target.exists() {
        fs::remove_dir_all(&target)
            .map_err(|e| TaskFailure::new("install_failed", format!("remove old: {e}")))?;
    }
    fs::rename(&source, &target)
        .map_err(|e| TaskFailure::new("install_failed", format!("finalize: {e}")))?;

    // ── 元数据落盘 + 登记 ─────────────────────────────────────────
    let size = dir_size(&target) as i64;
    let info = RuntimeInfo {
        id: plan.id.clone(),
        runtime_type: plan.runtime_type,
        version: plan.version.clone(),
        arch: plan.arch.clone(),
        path: target.to_string_lossy().into_owned(),
        size_bytes: Some(size),
        installed_at: Utc::now(),
        default: None,
    };
    match serde_json::to_string_pretty(&info) {
        Ok(meta) => {
            if let Err(e) = fs::write(target.join(META_FILE), meta) {
                tracing::warn!(runtime = %plan.id, error = %e, "persist runtime.json failed");
            }
        }
        Err(e) => tracing::warn!(runtime = %plan.id, error = %e, "serialize runtime.json failed"),
    }
    manager.register(info).await;

    tracing::info!(runtime = %plan.id, dir = %target.display(), size, "runtime installed");
    Ok(())
}

// ────────────────────────── 内部工具 ──────────────────────────

impl std::fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RuntimeError::NotFound(m) | RuntimeError::Unsupported(m)
            | RuntimeError::BadRequest(m) | RuntimeError::Upstream(m)
            | RuntimeError::NoResult(m) => f.write_str(m),
            RuntimeError::Io(e) => write!(f, "io error: {e}"),
        }
    }
}

/// Windows 保留字符 → '_'(id 同时用于目录名)。
fn sanitize_component(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => '_',
            _ => c,
        })
        .collect()
}

/// 当前平台架构(Adoptium 记法:x64;其余沿用 rust 常量,如 aarch64)。
fn current_arch() -> String {
    match std::env::consts::ARCH {
        "x86_64" => "x64".into(),
        other => other.into(),
    }
}

/// 当前平台 → (frp os, frp arch);不支持的平台返回 Unsupported。
///
/// frp 的 os 记法:windows/linux/darwin;arch 记法:amd64/arm64/386/arm
/// (与 Adoptium 的 "x64" 记法不同)。
fn frp_platform() -> Result<(String, String), RuntimeError> {
    let os = match std::env::consts::OS {
        "windows" => "windows",
        "linux" => "linux",
        "macos" => "darwin",
        other => {
            return Err(RuntimeError::Unsupported(format!(
                "frpc 运行时清单暂不支持平台 {other}"
            )));
        }
    };
    let arch = match std::env::consts::ARCH {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        "x86" => "386",
        "arm" => "arm",
        other => {
            return Err(RuntimeError::Unsupported(format!(
                "frpc 运行时清单暂不支持架构 {other}"
            )));
        }
    };
    Ok((os.into(), arch.into()))
}

/// 资产名匹配:`frp_{version}{suffix}.tar.gz|.zip`。带 `.` 边界,
/// 防 `_linux_arm` 误匹配 `_linux_arm64`(后者前缀不含 `_linux_arm.`)。
fn frpc_asset_match(name: &str, version: &str, suffix: &str) -> bool {
    let prefix = format!("frp_{version}{suffix}.");
    name.starts_with(&prefix) && (name.ends_with(".tar.gz") || name.ends_with(".zip"))
}

/// 从 sha256sum 文本中查找指定资产名的 hex(标准格式 `<hex>  <name>`;
/// 兼容 `<name>: <hex>` 变体)。找不到返回 None。
fn checksum_line(text: &str, asset_name: &str) -> Option<String> {
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        // 标准 sha256sum: "<hex>  <name>"
        let mut it = line.split_whitespace();
        if let (Some(first), Some(second)) = (it.next(), it.next()) {
            if second == asset_name && is_hex(first) {
                return Some(first.to_string());
            }
        }
        // 变体: "<name>: <hex>"
        if let Some(rest) = line.strip_prefix(asset_name) {
            let rest = rest.trim_start_matches(':').trim();
            if is_hex(rest) {
                return Some(rest.to_string());
            }
        }
    }
    None
}

/// 字符串是否全部为十六进制字符(非空)。
fn is_hex(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_hexdigit())
}

/// 由 URL 末段推导文件名(与 download 模块同名逻辑;此处供清单/自定义 url 用)。
fn filename_from_url(url: &str) -> &str {
    let clean = url.split(['?', '#']).next().unwrap_or(url);
    if clean.ends_with('/') {
        return "download";
    }
    let without_scheme = clean.split_once("://").map(|(_, rest)| rest).unwrap_or(clean);
    match without_scheme.rsplit_once('/') {
        Some((_, last)) if !last.is_empty() => last,
        _ => "download",
    }
}

/// 文件名去扩展名(自定义 url 且未指定版本时的版本号兜底)。
fn file_stem(file_name: &str) -> String {
    Path::new(file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_name)
        .to_string()
}

/// 从 Adoptium assets 条目提取清单项(兼容新旧两种结构:
/// 新版 `binary` 单对象;旧版 `binaries` 数组)。
fn adoptium_entry(asset: &serde_json::Value) -> Option<RuntimeCatalogEntry> {
    let release_name = asset.get("release_name")?.as_str()?;
    let version = release_name
        .strip_prefix("jdk-")
        .or_else(|| release_name.strip_prefix("openjdk-"))
        .unwrap_or(release_name);
    let package = match asset.get("binary").filter(|b| b.is_object()) {
        Some(binary) => binary.get("package")?,
        None => asset.get("binaries")?.as_array()?.first()?.get("package")?,
    };
    let url = package.get("link")?.as_str()?.to_string();
    let sha256 = package.get("checksum").and_then(|s| s.as_str()).map(ToString::to_string);
    let size_bytes = package.get("size").and_then(|s| s.as_i64());
    Some(RuntimeCatalogEntry {
        version: version.to_string(),
        url,
        sha256,
        size_bytes,
    })
}

/// 目录若只含一个子目录(无其他条目)则返回该子目录(归档单层根目录展平)。
fn single_root(dir: &Path) -> Option<PathBuf> {
    let mut entries = fs::read_dir(dir).ok()?.flatten();
    let first = entries.next()?;
    if entries.next().is_some() {
        return None;
    }
    let path = first.path();
    path.is_dir().then_some(path)
}

/// 目录总大小(字节;符号链接不计)。
fn dir_size(path: &Path) -> u64 {
    let mut total = 0;
    let Ok(entries) = fs::read_dir(path) else {
        return 0;
    };
    for entry in entries.flatten() {
        let Ok(meta) = entry.metadata() else {
            continue;
        };
        if meta.is_symlink() {
            continue;
        }
        if meta.is_dir() {
            total += dir_size(&entry.path());
        } else {
            total += meta.len();
        }
    }
    total
}

/// 文件 sha256,hex 小写。
fn sha256_hex(path: &Path) -> std::io::Result<String> {
    use sha2::{Digest, Sha256};

    let bytes = fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    Ok(format!("{:x}", hasher.finalize()))
}

/// 数字分段版本比较(a>b 时 Greater;降序排序用 sort_by(|a,b| version_cmp(b, a)))。
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

/// 将引擎快照映射为契约 TaskProgress(percent 为 0..1 比率)。
async fn set_download_progress(handle: &TaskHandle, snapshot: &DownloadStatusSnapshot) {
    let total = snapshot.total_length;
    let received = if total > 0 {
        snapshot.completed_length.min(total)
    } else {
        snapshot.completed_length
    };
    let speed = (snapshot.download_speed > 0).then_some(snapshot.download_speed);
    let eta_seconds = match (total, received, speed) {
        (t, r, Some(s)) if t > r && s > 0 => Some((t - r) / s),
        _ => None,
    };
    handle
        .set_progress(TaskProgress {
            received_bytes: Some(received),
            total_bytes: (total > 0).then_some(total),
            speed_bytes_per_sec: speed,
            eta_seconds,
            percent: if total > 0 {
                Some((received as f32 / total as f32).min(1.0))
            } else {
                None
            },
        })
        .await;
}

// ────────────────────────── 测试 ──────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_replaces_windows_reserved() {
        assert_eq!(sanitize_component("21.0.5+11"), "21.0.5+11");
        assert_eq!(sanitize_component("a/b\\c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j");
        assert_eq!(sanitize_component("a b"), "a b"); // 空格合法,保留
    }

    #[test]
    fn filename_from_url_extracts_last_segment() {
        assert_eq!(
            filename_from_url("https://github.com/adoptium/a/OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip"),
            "OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip"
        );
        assert_eq!(filename_from_url("https://example.com/a/"), "download");
    }

    #[test]
    fn file_stem_drops_extension() {
        assert_eq!(
            file_stem("OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip"),
            "OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11"
        );
        assert_eq!(file_stem("jdk.tar.gz"), "jdk.tar");
    }

    #[test]
    fn adoptium_entry_parses_release_name_and_package() {
        // 新版 v3 资产端点:binary 单对象
        let asset = serde_json::json!({
            "release_name": "jdk-21.0.5+11",
            "binary": {
                "package": {
                    "link": "https://example.com/jre.zip",
                    "checksum": "abc",
                    "size": 1234
                }
            }
        });
        let entry = adoptium_entry(&asset).unwrap();
        assert_eq!(entry.version, "21.0.5+11");
        assert_eq!(entry.url, "https://example.com/jre.zip");
        assert_eq!(entry.sha256.as_deref(), Some("abc"));
        assert_eq!(entry.size_bytes, Some(1234));

        // 旧版端点:binaries 数组
        let legacy = serde_json::json!({
            "release_name": "jdk-17.0.1+12",
            "binaries": [{
                "package": {
                    "link": "https://example.com/old.zip",
                    "checksum": "def",
                    "size": 42
                }
            }]
        });
        let entry = adoptium_entry(&legacy).unwrap();
        assert_eq!(entry.version, "17.0.1+12");
        assert_eq!(entry.url, "https://example.com/old.zip");
        assert_eq!(entry.size_bytes, Some(42));
    }

    #[test]
    fn single_root_flattens_single_dir_only() {
        let dir = std::env::temp_dir().join(format!("edgecube-rt-{}", Uuid::new_v4()));
        let inner = dir.join("jdk-21");
        fs::create_dir_all(&inner).unwrap();
        assert_eq!(single_root(&dir).as_deref(), Some(inner.as_path()));

        fs::write(dir.join("README"), b"x").unwrap();
        assert_eq!(single_root(&dir), None);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn version_cmp_orders_numerically() {
        assert_eq!(version_cmp("21.0.5", "21.0.2"), std::cmp::Ordering::Greater);
        assert_eq!(version_cmp("17", "21"), std::cmp::Ordering::Less);
        assert_eq!(version_cmp("8", "8.0"), std::cmp::Ordering::Equal);
    }

    #[test]
    fn frpc_asset_match_matches_current_platform_only() {
        let suffix = "_linux_amd64";
        assert!(frpc_asset_match("frp_0.61.1_linux_amd64.tar.gz", "0.61.1", suffix));
        assert!(frpc_asset_match("frp_0.61.1_linux_amd64.zip", "0.61.1", suffix));
        // 其它平台不匹配
        assert!(!frpc_asset_match("frp_0.61.1_windows_amd64.zip", "0.61.1", suffix));
        assert!(!frpc_asset_match("frp_0.61.1_linux_arm64.tar.gz", "0.61.1", suffix));
        // _linux_arm 不误匹配 _linux_arm64(带 '.' 边界)
        assert!(frpc_asset_match("frp_0.61.1_linux_arm.tar.gz", "0.61.1", "_linux_arm"));
        assert!(!frpc_asset_match("frp_0.61.1_linux_arm64.tar.gz", "0.61.1", "_linux_arm"));
        // 版本不同不匹配
        assert!(!frpc_asset_match("frp_0.60.0_linux_amd64.tar.gz", "0.61.1", suffix));
    }

    #[test]
    fn checksum_line_parses_standard_and_variant() {
        let text = concat!(
            "aabbcc  frp_0.61.1_linux_amd64.tar.gz\n",
            "ddeeff  frp_0.61.1_linux_arm64.tar.gz\n",
        );
        assert_eq!(
            checksum_line(text, "frp_0.61.1_linux_amd64.tar.gz").as_deref(),
            Some("aabbcc")
        );
        assert_eq!(
            checksum_line(text, "frp_0.61.1_linux_arm64.tar.gz").as_deref(),
            Some("ddeeff")
        );
        assert_eq!(checksum_line(text, "frp_0.61.1_windows_amd64.zip"), None);
        // 变体 "<name>: <hex>"
        let variant = "frp_0.61.1_linux_amd64.tar.gz: 00112233\n";
        assert_eq!(
            checksum_line(variant, "frp_0.61.1_linux_amd64.tar.gz").as_deref(),
            Some("00112233")
        );
        // 空文本 / 非法 hex
        assert_eq!(checksum_line("", "x"), None);
        assert_eq!(checksum_line("zz  name\n", "name"), None);
    }

    #[test]
    fn frp_platform_maps_known_archs() {
        // 当前编译平台必然命中一个已知分支;验证记法后缀(amd64/arm64/386/arm)
        let (os, arch) = frp_platform().expect("host platform must be supported");
        assert!(matches!(os.as_str(), "windows" | "linux" | "darwin"));
        assert!(matches!(arch.as_str(), "amd64" | "arm64" | "386" | "arm"));
    }

    #[tokio::test]
    async fn manager_scans_and_deletes() {
        let data = std::env::temp_dir().join(format!("edgecube-rt-mgr-{}", Uuid::new_v4()));
        let mgr = RuntimeManager::load(&data).unwrap();

        // 空:无运行时,删除 404
        assert!(mgr.list().await.is_empty());
        assert!(matches!(mgr.delete("java-21").await, Err(RuntimeError::NotFound(_))));

        // 手工放一个运行时目录 + 元数据:扫描可见并标记默认;暂存目录不注册
        let dir = mgr.root().join("java-21.0.5+11");
        fs::create_dir_all(&dir).unwrap();
        fs::create_dir_all(mgr.root().join(".tmp-xyz")).unwrap();
        let info = RuntimeInfo {
            id: "java-21.0.5+11".into(),
            runtime_type: RuntimeType::Java,
            version: "21.0.5+11".into(),
            arch: Some("x64".into()),
            path: dir.to_string_lossy().into_owned(),
            size_bytes: Some(1),
            installed_at: Utc::now(),
            default: None,
        };
        fs::write(dir.join(META_FILE), serde_json::to_string(&info).unwrap()).unwrap();

        let list = RuntimeManager::load(&data).unwrap().list().await;
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "java-21.0.5+11");
        assert_eq!(list[0].default, Some(true));

        // 卸载:目录与注册表同步清除
        RuntimeManager::load(&data)
            .unwrap()
            .delete("java-21.0.5+11")
            .await
            .unwrap();
        assert!(!dir.exists());
        fs::remove_dir_all(&data).unwrap();
    }

    #[tokio::test]
    async fn install_task_downloads_extracts_and_registers() {
        use crate::task::service::TaskService;

        // 本地 HTTP 源:zip 内含单层根目录 jdk-test/bin/java
        let data = std::env::temp_dir().join(format!("edgecube-rt-inst-{}", Uuid::new_v4()));
        let mgr = Arc::new(RuntimeManager::load(&data).unwrap());

        let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        zip.add_directory("jdk-test/bin/", zip::write::SimpleFileOptions::default())
            .unwrap();
        zip.start_file("jdk-test/bin/java", zip::write::SimpleFileOptions::default())
            .unwrap();
        std::io::Write::write_all(&mut zip, b"fake java").unwrap();
        let archive_bytes = zip.finish().unwrap().into_inner();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            // 极小 HTTP 服务:读请求头后回固定 200 响应(仅本测试使用)
            let (mut sock, _) = listener.accept().await.unwrap();
            let mut buf = [0u8; 4096];
            let _ = tokio::io::AsyncReadExt::read(&mut sock, &mut buf).await;
            let head = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                archive_bytes.len()
            );
            use tokio::io::AsyncWriteExt;
            let mut resp = head.into_bytes();
            resp.extend_from_slice(&archive_bytes);
            let _ = sock.write_all(&resp).await;
        });

        // 经完整任务链路安装:下载 → 解压 → 展平 → 登记
        let plan = InstallPlan {
            id: "java-test".into(),
            runtime_type: RuntimeType::Java,
            version: "test".into(),
            arch: Some(current_arch()),
            url: format!("http://{addr}/jdk.zip"),
            checksum: None,
            file_name: "jdk.zip".into(),
        };
        let tasks = TaskService::new();
        let mgr_for_task = mgr.clone();
        let task = tasks
            .submit(crate::task::model::TaskKind::Download, None, move |h| {
                run_runtime_install_task(h, DownloadManager::new(), mgr_for_task, plan.clone())
            })
            .await
            .unwrap();
        for _ in 0..100 {
            let t = tasks.get(task.id).await.unwrap();
            if t.status.is_terminal() {
                assert_eq!(t.status, crate::task::model::TaskStatus::Succeeded, "task error: {:?}", t.error);
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        let _ = server.await;

        let target = mgr.root().join("java-test");
        assert!(target.join("bin").is_dir());
        assert!(target.join(META_FILE).is_file());
        let list = mgr.list().await;
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, "java-test");
        assert!(list[0].size_bytes.unwrap_or(0) > 0);

        fs::remove_dir_all(&data).unwrap();
    }
}
