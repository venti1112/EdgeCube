//! 服务端核心更新(Paper 系:Paper / Purpur / Spigot / CraftBukkit)。
//!
//! - `check`:代理 PaperMC 官方 API(`api.papermc.io/v2/projects/paper`),识别实例
//!   工作目录中的核心 jar 文件与版本,与最新稳定版本/构建对比,给出更新建议;
//! - `update`:按检查结果下载最新核心 jar,校验 sha256 后替换旧 jar(旧 jar 重命名
//!   为 `.disabled`),经任务队列 `TaskKind::CoreUpdate` 执行(实例必须 Stopped)。
//!
//! 识别规则:
//! - 仅 Java 实例(MinecraftJava)支持;其它类型返回 `supported: false`;
//! - 工作目录扫描:优先启动命令中出现的 jar,其次按文件名关键词匹配
//!   (paper/purpur/spigot/craftbukkit)取最具体的一个;
//! - 版本号从文件名解析(`paper-1.21.4-230.jar` → 1.21.4 / build 230),
//!   解析不到(`server.jar`)视为未知版本,更新可用性按最新版提示。
//!
//! 网络调用收敛在后端(与 mod_market 一致),前端不直连 PaperMC。

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::download::{DownloadManager, run_download_task};
use crate::instance::{InstanceConfig, InstanceManager, InstanceType};
use crate::task::model::TaskFailure;
use crate::task::service::TaskHandle;

const PAPERMC_BASE: &str = "https://api.papermc.io/v2/projects/paper";

/// 服务端核心更新管理器(PaperMC 源;网络调用集中在后端)。
#[derive(Clone)]
pub struct ServerCoreManager {
    client: reqwest::Client,
}

impl Default for ServerCoreManager {
    fn default() -> Self {
        Self::new()
    }
}

impl ServerCoreManager {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .user_agent("EdgeCube-Daemon/1.0 (server-core updater)")
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .build()
            .expect("build reqwest client");
        ServerCoreManager { client }
    }

    /// 对实例执行更新检查(仅 Java 实例、且可识别核心 jar 时 supported=true)。
    pub async fn check(
        &self,
        instance: &InstanceConfig,
    ) -> Result<ServerCoreUpdateCheck, String> {
        // 1. 仅 Java 实例支持 Paper 系更新
        if instance.instance_type != InstanceType::MinecraftJava {
            return Ok(ServerCoreUpdateCheck::unsupported());
        }

        // 2. 定位核心 jar(启动命令优先,其次目录关键词扫描)
        let Some(core) = find_core_jar(&instance.working_directory, &instance.start_command)
        else {
            return Ok(ServerCoreUpdateCheck::unsupported());
        };

        // 3. 从文件名解析当前版本/构建(可能为未知,如 server.jar)
        let current = parse_core_name(&core);

        // 4. 查询 PaperMC:全部版本 → 最新版本的最新构建
        let project: PaperProject = self
            .get_json(PAPERMC_BASE)
            .await
            .map_err(core_error)?;
        let Some(latest_version) = project.versions.last() else {
            return Err("papermc: no versions returned".into());
        };
        let builds_url = format!("{PAPERMC_BASE}/versions/{latest_version}/builds");
        let builds: PaperBuilds = self.get_json(&builds_url).await.map_err(core_error)?;
        let Some(latest_build) = builds.builds.last() else {
            return Err(format!("papermc: no builds for version {latest_version}"));
        };
        let Some(application) = &latest_build.downloads.application else {
            return Err(format!(
                "papermc: build {} has no application download",
                latest_build.build
            ));
        };

        // 5. 汇总对比:当前版本已识别时,版本或构建不一致即有更新;
        //    当前版本未知(server.jar)时提示最新版可用。
        let update_available = match &current {
            Some(c) => c.version != *latest_version || c.build != Some(latest_build.build),
            None => true,
        };

        Ok(ServerCoreUpdateCheck {
            supported: true,
            source: "paper".to_string(),
            current_version: current.as_ref().map(|c| c.version.clone()).unwrap_or_default(),
            current_build: current
                .as_ref()
                .and_then(|c| c.build)
                .map(|b| b.to_string()),
            latest_version: latest_version.clone(),
            latest_build: latest_build.build.to_string(),
            download_url: papermc_download_url(latest_version, latest_build.build, &application.name),
            sha256: application.sha256.clone().unwrap_or_default(),
            update_available,
        })
    }
}

impl ServerCoreManager {
    /// GET JSON 工具。
    async fn get_json<T: for<'de> Deserialize<'de>>(&self, url: &str) -> Result<T, String> {
        let resp = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|e| format!("papermc request: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("papermc: HTTP {}", resp.status()));
        }
        resp.json::<T>()
            .await
            .map_err(|e| format!("papermc decode: {e}"))
    }
}

fn core_error(e: String) -> String {
    e
}

/// PaperMC 下载 URL(规范拼装)。
fn papermc_download_url(version: &str, build: u64, name: &str) -> String {
    format!("{PAPERMC_BASE}/versions/{version}/builds/{build}/downloads/{name}")
}

// ────────────────────────── PaperMC 响应模型 ──────────────────────────

/// GET /projects/paper
#[derive(Debug, Deserialize)]
struct PaperProject {
    versions: Vec<String>,
}

/// GET /projects/paper/versions/{version}/builds
#[derive(Debug, Deserialize)]
struct PaperBuilds {
    builds: Vec<PaperBuild>,
}

#[derive(Debug, Deserialize)]
struct PaperBuild {
    build: u64,
    downloads: PaperBuildDownloads,
}

#[derive(Debug, Deserialize)]
struct PaperBuildDownloads {
    application: Option<PaperApplication>,
}

#[derive(Debug, Deserialize)]
struct PaperApplication {
    name: String,
    sha256: Option<String>,
}

// ────────────────────────── 核心 jar 识别 ──────────────────────────

/// 从工作目录定位核心 jar:优先启动命令引用的文件名,其次关键词匹配
/// (paper/purpur/spigot/craftbukkit),取存在者中文件名最具体的一个。
fn find_core_jar(cwd: &Path, start_command: &str) -> Option<PathBuf> {
    // 1. 启动命令中出现的 .jar 文件名 → 精确命中
    if let Some(name) = jar_from_command(start_command) {
        let candidate = cwd.join(&name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }

    // 2. 目录扫描:关键词匹配,取最具体的(带构建号 > 带版本 > 裸关键词)。
    let keywords = ["paper", "purpur", "spigot", "craftbukkit"];
    let mut hits: Vec<(PathBuf, usize)> = Vec::new();
    let Ok(entries) = std::fs::read_dir(cwd) else {
        return None;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let lower = name.to_lowercase();
        if !lower.ends_with(".jar") || lower.contains("disabled") {
            continue;
        }
        if let Some(kw) = keywords.iter().find(|k| lower.contains(**k)) {
            let score = specificity(lower.trim_end_matches(".jar"), kw);
            hits.push((path, score));
        }
    }
    hits.sort_by(|a, b| b.1.cmp(&a.1));
    hits.first().map(|h| h.0.clone())
}

/// 命名具体度:含构建号(+2) > 含版本号(+1) > 仅关键词(+0)。
fn specificity(stem: &str, keyword: &str) -> usize {
    if stem.contains('-') && stem.rsplit_once('-').map(|(_, t)| t.chars().all(|c| c.is_ascii_digit())).unwrap_or(false)
    {
        2
    } else if stem.split_once(keyword).map(|(_, rest)| rest.matches('.').count() >= 2).unwrap_or(false) {
        1
    } else {
        0
    }
}

/// 从启动命令提取 jar 文件名(如 `java -jar server.jar nogui`)。
fn jar_from_command(command: &str) -> Option<String> {
    for tok in command.split_whitespace() {
        let tok = tok.trim_matches(['"', '\'']);
        if tok.ends_with(".jar") {
            return Some(tok.rsplit(['/', '\\']).next()?.to_string());
        }
    }
    None
}

/// 解析核心名 → (版本, 构建号)。形如:
/// - `paper-1.21.4-230.jar` → Some(1.21.4, 230)
/// - `paper-1.21.4.jar` / `craftbukkit-1.21.4.jar` → Some(1.21.4, None)
/// - `server.jar` → None(无法识别)
fn parse_core_name(path: &Path) -> Option<CoreIdentity> {
    let name = path.file_name()?.to_string_lossy();
    let stem = name.trim_end_matches(".jar");

    // 找 token 中的版本段(匹配 x.y.z 或 x.y)与紧随其后的构建号
    let tokens: Vec<&str> = stem.split('-').collect();
    let mut version: Option<String> = None;
    let mut build: Option<u64> = None;
    for (idx, tok) in tokens.iter().enumerate() {
        if version.is_none() {
            if let Some(v) = version_of_token(tok) {
                version = Some(v);
                // 紧邻下一个纯数字 token 视为构建号
                if let Some(next) = tokens.get(idx + 1) {
                    if !next.is_empty() && next.chars().all(|c| c.is_ascii_digit()) {
                        build = next.parse().ok();
                    }
                }
            }
        }
    }
    version.map(|v| CoreIdentity { version: v, build })
}

/// 从单个 token 提取版本(x.y.z / x.y)。
fn version_of_token(tok: &str) -> Option<String> {
    let v: String = tok
        .trim_start_matches(|c: char| c.is_ascii_alphabetic())
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let dots = v.matches('.').count();
    if dots == 2 || (dots == 1 && !v.starts_with('.')) {
        Some(v)
    } else {
        None
    }
}

/// 核心身份(文件名解析结果)。
struct CoreIdentity {
    version: String,
    build: Option<u64>,
}

// ────────────────────────── 契约响应模型 ──────────────────────────

/// 更新检查结果(openapi ServerCoreUpdateCheck)。
#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCoreUpdateCheck {
    pub supported: bool,
    pub source: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub current_version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_build: Option<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub latest_version: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub latest_build: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub download_url: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub sha256: String,
    pub update_available: bool,
}

impl ServerCoreUpdateCheck {
    fn unsupported() -> Self {
        ServerCoreUpdateCheck {
            supported: false,
            source: "unknown".to_string(),
            ..Default::default()
        }
    }
}

/// 更新请求(openapi ServerCoreUpdateRequest)。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCoreUpdateRequest {
    pub download_url: String,
    pub sha256: Option<String>,
    pub file_name: Option<String>,
}

// ────────────────────────── 更新任务执行体 ──────────────────────────

/// 服务端核心更新任务执行体。
///
/// 流程:
/// 1. 解析实例 → 定位旧核心 jar(或按请求 fileName 指定目标名);
/// 2. 旧 jar 重命名为 `.disabled`(存在才改);
/// 3. 下载新 jar 到实例 cwd(落盘为目标核心名,校验 sha256);
///
/// 调用方需保证实例 Stopped(409 检查在 handler)。
pub async fn run_core_update_task(
    handle: TaskHandle,
    dm: DownloadManager,
    im: Arc<InstanceManager>,
    instance_id: Uuid,
    req: ServerCoreUpdateRequest,
) -> Result<(), TaskFailure> {
    handle.set_phase("locating").await;
    let instance = im
        .get_config(instance_id)
        .await
        .ok_or_else(|| TaskFailure::new("instance_not_found", "instance not found"))?;
    let cwd = instance.working_directory.clone();

    // 1. 目标核心名:请求指定优先,否则从工作目录检测
    let target_name = match req.file_name {
        Some(name) => name,
        None => match find_core_jar(&cwd, &instance.start_command)
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        {
            Some(name) => name,
            None => {
                return Err(TaskFailure::new(
                    "core_jar_not_found",
                    "cannot locate server core jar in instance working directory",
                ));
            }
        },
    };

    // 2. 旧 jar 重命名 .disabled(存在才执行)
    handle.set_phase("backing_up").await;
    let old_jar = cwd.join(&target_name);
    if old_jar.is_file() {
        let disabled = PathBuf::from(format!("{}.disabled", old_jar.to_string_lossy()));
        std::fs::rename(&old_jar, &disabled).map_err(|e| {
            TaskFailure::new(
                "backup_failed",
                format!(
                    "cannot rename {} to {}: {e}",
                    old_jar.display(),
                    disabled.display()
                ),
            )
        })?;
        tracing::info!(
            old = %old_jar.display(),
            disabled = %disabled.display(),
            "old core jar backed up"
        );
    }

    // 3. 下载新 jar 落盘为目标名,校验 sha256
    let checksum = req.sha256.clone().map(|h| format!("sha256:{h}"));
    run_download_task(
        handle,
        dm,
        req.download_url,
        cwd,
        Some(target_name),
        checksum,
        None, // 旧 jar 已改名,无需 replace
        true, // 允许覆盖(幂等重跑)
    )
    .await
}