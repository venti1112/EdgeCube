//! 插件/模组元数据解析与缓存(对齐 V1 `mod_metadata.dart`)。
//!
//! 元数据检查放在后端:前端先经 `/fs/list` 获取文件列表展示,再提交
//! `POST /instances/{instanceId}/mods/analyze` 创建解析任务(TaskKind::Analyze),
//! 前端轮询 `GET /tasks/{jobId}` 状态;任务成功后经
//! `GET /instances/{instanceId}/mods/metadata` 拉取解析结果。
//!
//! 解析支持 .jar / .phar(.phar.disabled / .jar.disabled 同样识别):
//! fabric.mod.json → quilt.mod.json → META-INF/mods.toml → mcmod.info →
//! velocity-plugin.json → plugin.yml → bungee.yml;PMMP(.phar) 额外读
//! plugin.yml / pocketmine.yml 并标记 PocketMine 加载器。

use std::collections::HashMap;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::fs::{FsError, ensure_within, rel_path, resolve};
use crate::task::model::TaskFailure;
use crate::task::service::TaskHandle;

/// 插件/模组加载器类型(契约 ModLoader,lowercase 序列化)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ModLoader {
    Fabric,
    Forge,
    Quilt,
    NeoForge,
    Bukkit,
    BungeeCord,
    Velocity,
    PocketMine,
    Unknown,
}

impl ModLoader {
    pub fn label(self) -> &'static str {
        match self {
            ModLoader::Fabric => "Fabric",
            ModLoader::Forge => "Forge",
            ModLoader::Quilt => "Quilt",
            ModLoader::NeoForge => "NeoForge",
            ModLoader::Bukkit => "Plugin",
            ModLoader::BungeeCord => "BungeeCord",
            ModLoader::Velocity => "Velocity",
            ModLoader::PocketMine => "PocketMine",
            ModLoader::Unknown => "",
        }
    }
}

/// 从 .jar/.phar 解析出的插件/模组元数据(契约 ModMetadata)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModMetadata {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mod_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub authors: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    pub loader: ModLoader,
}

/// 单文件解析结果(契约 ModMetadataEntry;metadata 为 null = 未解析/未识别)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModMetadataEntry {
    pub path: String,
    pub name: String,
    pub size_bytes: u64,
    /// 文件 SHA1(小写 hex),供图标获取/更新检查(Modrinth version_files)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha1: Option<String>,
    /// 图标 URL(后端经 Modrinth 查询,尽力而为;失败/不可得为 null)。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub icon_url: Option<String>,
    pub metadata: Option<ModMetadata>,
}

/// 目录解析结果(契约 ModMetadataListResponse)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModMetadataListResponse {
    pub path: String,
    pub items: Vec<ModMetadataEntry>,
}

/// 单文件缓存条目:元数据(可空)+ SHA1 + 图标。
#[derive(Debug, Clone, Default)]
pub struct MetaCacheEntry {
    pub metadata: Option<ModMetadata>,
    pub sha1: Option<String>,
    pub icon_url: Option<String>,
}

/// 元数据缓存:instance_id → (相对路径 → 缓存条目)。
#[derive(Default)]
pub struct ModMetaManager {
    inner: RwLock<HashMap<Uuid, HashMap<String, MetaCacheEntry>>>,
}

impl ModMetaManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub async fn store(&self, instance_id: Uuid, path: String, meta: Option<ModMetadata>) {
        let mut inner = self.inner.write().await;
        inner
            .entry(instance_id)
            .or_default()
            .entry(path)
            .or_default()
            .metadata = meta;
    }

    pub async fn store_sha1(&self, instance_id: Uuid, path: String, sha1: Option<String>) {
        let mut inner = self.inner.write().await;
        inner
            .entry(instance_id)
            .or_default()
            .entry(path)
            .or_default()
            .sha1 = sha1;
    }

    pub async fn store_icon(&self, instance_id: Uuid, path: String, icon_url: Option<String>) {
        let mut inner = self.inner.write().await;
        inner
            .entry(instance_id)
            .or_default()
            .entry(path)
            .or_default()
            .icon_url = icon_url;
    }

    /// 读取单个缓存条目(外层 None = 尚未扫描过该路径)。
    pub async fn get_entry(&self, instance_id: Uuid, path: &str) -> Option<MetaCacheEntry> {
        let inner = self.inner.read().await;
        inner.get(&instance_id)?.get(path).cloned()
    }

    /// 读取解析结果(外层 None = 尚未扫描过该路径)。
    pub async fn get(&self, instance_id: Uuid, path: &str) -> Option<Option<ModMetadata>> {
        self.get_entry(instance_id, path).await.map(|e| e.metadata)
    }

    /// 实例删除时清理其缓存。
    pub async fn remove_instance(&self, instance_id: Uuid) {
        let mut inner = self.inner.write().await;
        inner.remove(&instance_id);
    }
}

/// 是否为可解析的插件/模组文件(.jar/.jar.disabled/.phar/.phar.disabled)。
pub fn is_mod_file(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.ends_with(".jar")
        || lower.ends_with(".jar.disabled")
        || lower.ends_with(".phar")
        || lower.ends_with(".phar.disabled")
}

// ────────────────────────── 解析任务 ──────────────────────────

/// 解析任务执行体:扫描目录内所有插件/模组文件并解析元数据,逐条写入缓存。
/// 供 `TaskKind::Analyze` 使用(instanceId 分组 FIFO 串行)。
pub async fn run_analyze_task(
    handle: TaskHandle,
    mgr: Arc<ModMetaManager>,
    instance_id: Uuid,
    cwd: PathBuf,
    rel_dir: String,
) -> Result<(), TaskFailure> {
    handle.set_phase("scanning").await;
    let dir = resolve(&cwd, &rel_dir).map_err(|e| TaskFailure::new("invalid_path", e.to_string()))?;
    ensure_within(&cwd, &dir).map_err(|e| TaskFailure::new("invalid_path", e.to_string()))?;

    // 收集待解析文件(相对路径 + 绝对路径)
    let mut files: Vec<(String, PathBuf)> = Vec::new();
    let entries =
        std::fs::read_dir(&dir).map_err(|e| TaskFailure::new("read_dir_failed", e.to_string()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() && is_mod_file(&entry.file_name().to_string_lossy()) {
            files.push((rel_path(&cwd, &path), path));
        }
    }

    let total = files.len();
    for (i, (rel, abs)) in files.iter().enumerate() {
        if handle.is_cancelled() {
            return Err(TaskFailure::new("cancelled", "analysis cancelled"));
        }
        handle.set_phase(format!("analyzing {}/{}", i + 1, total)).await;
        let path = abs.clone();
        let (meta, sha1) = tokio::task::spawn_blocking(move || analyze_file(&path))
            .await
            .map_err(|e| TaskFailure::new("analysis_failed", e.to_string()))?;
        mgr.store(instance_id, rel.clone(), meta).await;
        mgr.store_sha1(instance_id, rel.clone(), sha1).await;
    }
    Ok(())
}

/// 列出目录内所有插件/模组文件的解析结果(未解析/未识别为 null)。
pub async fn list_metadata(
    mgr: &ModMetaManager,
    instance_id: Uuid,
    cwd: &Path,
    rel_dir: &str,
) -> Result<ModMetadataListResponse, FsError> {
    let dir = resolve(cwd, rel_dir)?;
    ensure_within(cwd, &dir)?;
    if !dir.is_dir() {
        return Err(FsError::Invalid(format!("{rel_dir} is not a directory")));
    }

    let mut items = Vec::new();
    let entries = std::fs::read_dir(&dir)?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if !is_mod_file(&name) {
            continue;
        }
        let rel = rel_path(cwd, &path);
        let entry = mgr.get_entry(instance_id, &rel).await;
        let size_bytes = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        items.push(ModMetadataEntry {
            path: rel,
            name,
            size_bytes,
            sha1: entry.as_ref().and_then(|e| e.sha1.clone()),
            icon_url: entry.as_ref().and_then(|e| e.icon_url.clone()),
            metadata: entry.and_then(|e| e.metadata),
        });
    }
    // 按文件名不区分大小写排序
    items.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    Ok(ModMetadataListResponse {
        path: rel_dir.to_string(),
        items,
    })
}

// ────────────────────────── 解析(同步,CPU 密集) ──────────────────────────

/// 解析文件元数据并计算 SHA1;无法识别或解析失败返回 (None, sha1)。
/// CPU 密集,应置于 spawn_blocking。
fn analyze_file(path: &Path) -> (Option<ModMetadata>, Option<String>) {
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(_) => return (None, None),
    };
    let sha1 = Some(hex_sha1(&bytes));
    let meta = parse_file(&bytes, &path.to_string_lossy());
    (meta, sha1)
}

/// 解析文件元数据;无法识别或解析失败返回 None。
fn parse_file(bytes: &[u8], name: &str) -> Option<ModMetadata> {
    let lower = name.to_ascii_lowercase();
    if lower.ends_with(".phar") || lower.ends_with(".phar.disabled") {
        parse_phar(bytes)
    } else {
        parse_jar(bytes)
    }
}

/// SHA1 十六进制(小写)。
fn hex_sha1(bytes: &[u8]) -> String {
    use sha1::Digest;
    let mut hasher = sha1::Sha1::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn parse_jar(bytes: &[u8]) -> Option<ModMetadata> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes)).ok()?;
    extract_metadata(&mut archive)
}

/// 从 zip 中按优先级提取元数据(顺序对齐 V1 `_extractMetadata`)。
fn extract_metadata(archive: &mut zip::ZipArchive<Cursor<&[u8]>>) -> Option<ModMetadata> {
    if let Some(bytes) = read_zip_entry(archive, "fabric.mod.json") {
        if let Some(meta) = parse_fabric_mod_json(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "quilt.mod.json") {
        if let Some(meta) = parse_quilt_mod_json(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "META-INF/mods.toml") {
        if let Some(meta) = parse_mods_toml(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "mcmod.info") {
        if let Some(meta) = parse_mcmod_info(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "velocity-plugin.json") {
        if let Some(meta) = parse_velocity_plugin_json(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "plugin.yml") {
        if let Some(meta) = parse_plugin_yml(&bytes) {
            return Some(meta);
        }
    }
    if let Some(bytes) = read_zip_entry(archive, "bungee.yml") {
        if let Some(meta) = parse_bungee_yml(&bytes) {
            return Some(meta);
        }
    }
    None
}

/// 读取 zip 条目(先精确匹配,再大小写不敏感回退),失败返回 None。
fn read_zip_entry(
    archive: &mut zip::ZipArchive<Cursor<&[u8]>>,
    name: &str,
) -> Option<Vec<u8>> {
    if let Ok(mut f) = archive.by_name(name) {
        let mut buf = Vec::new();
        if f.read_to_end(&mut buf).is_ok() {
            return Some(buf);
        }
    }
    for i in 0..archive.len() {
        let entry_name = {
            let entry = archive.by_index(i).ok()?;
            entry.name().to_string()
        };
        if entry_name.eq_ignore_ascii_case(name) {
            let mut f = archive.by_index(i).ok()?;
            let mut buf = Vec::new();
            if f.read_to_end(&mut buf).is_ok() {
                return Some(buf);
            }
        }
    }
    None
}

/// 解析 .phar(PocketMine-MP 插件):zip-based 直接走 zip;
/// tar-based 跳过 PHP stub(__HALT_COMPILER 之后)再按 tar 解析。
fn parse_phar(bytes: &[u8]) -> Option<ModMetadata> {
    let is_zip = bytes.len() >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if is_zip {
        let mut archive = zip::ZipArchive::new(Cursor::new(bytes)).ok()?;
        return parse_pmmp_zip(&mut archive);
    }
    // 跳过 stub;找不到标记时尝试整体按 tar 解析(裸 tar 场景)
    let start = skip_phar_stub(bytes).unwrap_or(0);
    parse_pmmp_tar(&bytes[start..])
}

/// 定位 __HALT_COMPILER 并跳过 stub(含 `();` 与 `?>` 及空白),返回数据起点。
fn skip_phar_stub(bytes: &[u8]) -> Option<usize> {
    let halt = b"__HALT_COMPILER";
    let idx = find_bytes(bytes, halt)?;
    let mut start = idx + halt.len();
    while start < bytes.len() && matches!(bytes[start], b'(' | b')' | b';') {
        start += 1;
    }
    while start < bytes.len() && matches!(bytes[start], b'?' | b'>' | b'\r' | b'\n' | b' ' | b'\t') {
        start += 1;
    }
    Some(start)
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn parse_pmmp_zip(archive: &mut zip::ZipArchive<Cursor<&[u8]>>) -> Option<ModMetadata> {
    for name in ["plugin.yml", "pocketmine.yml"] {
        if let Some(bytes) = read_zip_entry(archive, name) {
            if let Some(meta) = parse_pmmp_plugin_yml(&bytes) {
                return Some(meta);
            }
        }
    }
    None
}

fn parse_pmmp_tar(bytes: &[u8]) -> Option<ModMetadata> {
    let mut archive = tar::Archive::new(Cursor::new(bytes));
    let entries = archive.entries().ok()?;
    for entry in entries.flatten() {
        let mut entry = entry;
        let lower = entry.path().ok()?.to_string_lossy().to_ascii_lowercase();
        if lower == "plugin.yml" || lower == "pocketmine.yml" {
            let mut buf = Vec::new();
            entry.read_to_end(&mut buf).ok()?;
            if let Some(meta) = parse_pmmp_plugin_yml(&buf) {
                return Some(meta);
            }
        }
    }
    None
}

// ── fabric.mod.json ──────────────────────────────────────────
fn parse_fabric_mod_json(bytes: &[u8]) -> Option<ModMetadata> {
    let data: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let obj = data.as_object()?;
    let id = obj.get("id").and_then(|v| v.as_str());
    let name = obj
        .get("name")
        .and_then(|v| v.as_str())
        .or(id)?;
    let authors = obj.get("authors").and_then(|v| v.as_array()).map(|arr| {
        arr.iter()
            .filter_map(|a| {
                if let Some(s) = a.as_str() {
                    Some(s.to_string())
                } else {
                    a.as_object()
                        .and_then(|o| o.get("name").and_then(|n| n.as_str()))
                        .map(str::to_string)
                }
            })
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(", ")
    });
    let url = obj
        .get("contact")
        .and_then(|v| v.as_object())
        .and_then(|c| c.get("homepage"))
        .and_then(|v| v.as_str())
        .map(str::to_string);
    Some(ModMetadata {
        name: name.to_string(),
        version: obj.get("version").and_then(|v| v.as_str()).map(str::to_string),
        description: obj.get("description").and_then(|v| v.as_str()).map(str::to_string),
        mod_id: id.map(str::to_string),
        authors,
        url,
        loader: ModLoader::Fabric,
    })
}

// ── quilt.mod.json ───────────────────────────────────────────
fn parse_quilt_mod_json(bytes: &[u8]) -> Option<ModMetadata> {
    let data: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let quilt = data.get("quilt_loader")?.as_object()?;
    let id = quilt.get("id")?.as_str()?;
    let mut name = id.to_string();
    let mut description = None;
    if let Some(metadata) = data.get("metadata").and_then(|v| v.as_object()) {
        if let Some(n) = metadata.get("name").and_then(|v| v.as_str()) {
            name = n.to_string();
        }
        description = metadata.get("description").and_then(|v| v.as_str()).map(str::to_string);
    }
    Some(ModMetadata {
        name,
        version: quilt.get("version").and_then(|v| v.as_str()).map(str::to_string),
        description,
        mod_id: Some(id.to_string()),
        authors: None,
        url: None,
        loader: ModLoader::Quilt,
    })
}

// ── META-INF/mods.toml(Forge 1.13+/NeoForge) ─────────────────
fn parse_mods_toml(bytes: &[u8]) -> Option<ModMetadata> {
    let toml = String::from_utf8_lossy(bytes);
    let mut current_section: Option<String> = None;
    let mut mods: HashMap<String, String> = HashMap::new();
    let mut global: HashMap<String, String> = HashMap::new();
    let mut in_mods_array = false;

    for raw in toml.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(section) = toml_section_name(line) {
            current_section = Some(section.clone());
            in_mods_array = section == "mods";
            continue;
        }
        if let Some((key, value)) = toml_kv(line) {
            let value = unquote(&value);
            if in_mods_array {
                mods.insert(key, value);
            } else if current_section
                .as_deref()
                .map_or(true, |s| !s.starts_with("dependencies"))
            {
                global.insert(key, value);
            }
        }
    }

    let display_name = mods
        .get("displayName")
        .cloned()
        .or_else(|| mods.get("modId").cloned())?;
    let is_neoforge = toml.contains("neoforge") || toml.contains("NeoForge");
    Some(ModMetadata {
        name: display_name,
        version: mods.get("version").cloned(),
        description: mods.get("description").cloned(),
        mod_id: mods.get("modId").cloned(),
        authors: global.get("authors").cloned(),
        url: global.get("displayURL").cloned(),
        loader: if is_neoforge { ModLoader::NeoForge } else { ModLoader::Forge },
    })
}

/// 提取 TOML 节名(兼容 `[mods]` / `[[mods]]` 双中括号)。
fn toml_section_name(line: &str) -> Option<String> {
    if line.len() < 3 || !line.starts_with('[') || !line.ends_with(']') {
        return None;
    }
    let inner = line[1..line.len() - 1].trim();
    let inner = inner.trim_matches(|c| c == '[' || c == ']');
    let inner = inner.trim();
    if inner.is_empty() {
        None
    } else {
        Some(inner.to_string())
    }
}

fn toml_kv(line: &str) -> Option<(String, String)> {
    let idx = line.find('=')?;
    let key = line[..idx].trim();
    if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }
    Some((key.to_string(), line[idx + 1..].trim().to_string()))
}

// ── mcmod.info(Forge 1.7.10 及更早) ──────────────────────────
fn parse_mcmod_info(bytes: &[u8]) -> Option<ModMetadata> {
    let data: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let list = match data {
        serde_json::Value::Array(arr) => arr,
        serde_json::Value::Object(obj) => obj.get("modList")?.as_array()?.clone(),
        _ => return None,
    };
    let first = list.first()?.as_object()?;
    let name = first
        .get("name")
        .and_then(|v| v.as_str())
        .or_else(|| first.get("modid").and_then(|v| v.as_str()))?;
    let authors = first.get("authorList").and_then(|v| v.as_array()).map(|arr| {
        arr.iter()
            .filter_map(|a| a.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    });
    Some(ModMetadata {
        name: name.to_string(),
        version: first.get("version").and_then(|v| v.as_str()).map(str::to_string),
        description: first.get("description").and_then(|v| v.as_str()).map(str::to_string),
        mod_id: first.get("modid").and_then(|v| v.as_str()).map(str::to_string),
        authors,
        url: first.get("url").and_then(|v| v.as_str()).map(str::to_string),
        loader: ModLoader::Forge,
    })
}

// ── velocity-plugin.json(Velocity 插件) ──────────────────────
fn parse_velocity_plugin_json(bytes: &[u8]) -> Option<ModMetadata> {
    let obj: serde_json::Map<String, serde_json::Value> =
        serde_json::from_slice::<serde_json::Value>(bytes).ok()?.as_object()?.clone();
    let name = obj
        .get("name")
        .and_then(|v| v.as_str())
        .or_else(|| obj.get("id").and_then(|v| v.as_str()))?;
    let authors = obj.get("authors").and_then(|v| v.as_array()).map(|arr| {
        arr.iter()
            .filter_map(|a| {
                if let Some(s) = a.as_str() {
                    Some(s.to_string())
                } else {
                    a.as_object()
                        .and_then(|o| o.get("name").and_then(|n| n.as_str()))
                        .map(str::to_string)
                }
            })
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(", ")
    });
    Some(ModMetadata {
        name: name.to_string(),
        version: obj.get("version").and_then(|v| v.as_str()).map(str::to_string),
        description: obj.get("description").and_then(|v| v.as_str()).map(str::to_string),
        mod_id: obj.get("id").and_then(|v| v.as_str()).map(str::to_string),
        authors,
        url: obj.get("url").and_then(|v| v.as_str()).map(str::to_string),
        loader: ModLoader::Velocity,
    })
}

// ── plugin.yml(Bukkit/Spigot/Paper 插件) ─────────────────────
fn parse_plugin_yml(bytes: &[u8]) -> Option<ModMetadata> {
    let map = parse_simple_yaml(&String::from_utf8_lossy(bytes));
    let name = map.get("name").or_else(|| map.get("main"))?.clone();
    Some(ModMetadata {
        name,
        version: map.get("version").cloned(),
        description: map.get("description").cloned(),
        mod_id: map.get("main").cloned(),
        authors: map.get("author").cloned().or_else(|| map.get("authors").cloned()),
        url: map.get("website").cloned(),
        loader: ModLoader::Bukkit,
    })
}

// ── bungee.yml(BungeeCord/Waterfall 插件) ────────────────────
fn parse_bungee_yml(bytes: &[u8]) -> Option<ModMetadata> {
    let map = parse_simple_yaml(&String::from_utf8_lossy(bytes));
    let name = map.get("name").or_else(|| map.get("main"))?.clone();
    Some(ModMetadata {
        name,
        version: map.get("version").cloned(),
        description: map.get("description").cloned(),
        mod_id: map.get("main").cloned(),
        authors: map.get("author").cloned().or_else(|| map.get("authors").cloned()),
        url: map.get("website").cloned(),
        loader: ModLoader::BungeeCord,
    })
}

// ── PocketMine plugin.yml / pocketmine.yml ───────────────────
fn parse_pmmp_plugin_yml(bytes: &[u8]) -> Option<ModMetadata> {
    let map = parse_simple_yaml(&String::from_utf8_lossy(bytes));
    let name = map.get("name").cloned().or_else(|| map.get("main").cloned())?;
    Some(ModMetadata {
        name,
        version: map.get("version").cloned(),
        description: map.get("description").cloned(),
        mod_id: map.get("main").cloned(),
        authors: map.get("author").cloned().or_else(|| map.get("authors").cloned()),
        url: map.get("website").cloned(),
        loader: ModLoader::PocketMine,
    })
}

// ── 简易 YAML 解析器(顶层 key: value + 列表项,对齐 V1 `_parseSimpleYaml`) ──
fn parse_simple_yaml(yaml: &str) -> HashMap<String, String> {
    let mut result = HashMap::new();
    let mut pending_list_key: Option<String> = None;
    let mut list_buffer: Vec<String> = Vec::new();

    fn flush(result: &mut HashMap<String, String>, pending: &mut Option<String>, buffer: &mut Vec<String>) {
        if let Some(key) = pending.take() {
            if !buffer.is_empty() {
                result.insert(key, buffer.join(", "));
            }
            buffer.clear();
        }
    }

    for raw in yaml.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("- ") {
            if pending_list_key.is_some() {
                list_buffer.push(unquote(rest.trim()));
            }
            continue;
        }
        flush(&mut result, &mut pending_list_key, &mut list_buffer);
        let Some(idx) = line.find(':') else {
            continue;
        };
        let key = line[..idx].trim().to_string();
        let value = line[idx + 1..].trim().to_string();
        if value.is_empty() {
            pending_list_key = Some(key);
        } else if value.starts_with('[') && value.ends_with(']') {
            let inner = &value[1..value.len() - 1];
            result.insert(
                key,
                inner
                    .split(',')
                    .map(|s| unquote(s.trim()))
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(", "),
            );
        } else {
            result.insert(key, unquote(&value));
        }
    }
    flush(&mut result, &mut pending_list_key, &mut list_buffer);
    result
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    let stripped = if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        &s[1..s.len() - 1]
    } else {
        s
    };
    stripped.replace("\\\"", "\"")
}
