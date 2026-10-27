//! 已装模组 / 插件的扫描、元数据解析与启停（**同步 IO**，调用方负责丢进
//! `spawn_blocking`）。
//!
//! # 为什么元数据要在 daemon 里读
//!
//! 「装了什么」不能只看文件名：`sodium-fabric-0.7.3+mc1.21.8.jar` 这种名字里
//! 塞了三个信息，而 `Mod.jar` 什么都不说明。名字、版本、加载器这三样只能从
//! **jar 内部**的元数据文件读（`fabric.mod.json` / `plugin.yml` / …），
//! 而 jar 在服务端机器上 —— 前端既拿不到也读不动，所以这件事天然属于 daemon。
//!
//! # 「启用 / 禁用」怎么表达
//!
//! **改名**（`X.jar` ↔ `X.jar.disabled`），不搬家：服务端只认 `*.jar`，
//! 改个后缀就能让它不加载，而用户自己用文件管理器也看得懂、也能手工改回来。
//!
//! # 元数据缓存
//!
//! 读一次元数据要开一遍 zip。一个几十模组的服务端，进页面 / 切标签 / 下拉刷新
//! 都会重扫 —— 所以按「文件大小 + mtime」缓存解析结果，文件被替换自然失效，
//! **不需要任何显式失效逻辑**。缓存的是 `Option<Meta>`（含「这个 jar 没有
//! 可识别的元数据」这个结论），否则那些没有元数据的 jar 每次都要白开一遍。

use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use crate::error::{RpcError, RpcResult};
use crate::module::builtin::instance::files;
use crate::module::builtin::mods::model;

/// 扫描与解析的上限。
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    /// 每个目录最多列多少个文件。
    pub max_files: usize,
    /// 读元数据时单个 zip 条目最多读多少字节。
    ///
    /// `fabric.mod.json` / `plugin.yml` 都是几 KB 的量级；设上限是防「有人把
    /// 一个大文件伪装成元数据」把内存吃光。超限就当读不出来（不是错误）。
    pub max_entry_bytes: u64,
    /// `.phar` 的整文件上限。
    ///
    /// `.phar` 必须在内存里定位 `__HALT_COMPILER` 之后的那段 tar，没法像 zip
    /// 那样只读目录 —— 所以单独设一个上限，别让一个畸形的大文件把内存吃光。
    pub max_phar_bytes: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_files: 2_000,
            max_entry_bytes: 256 * 1024,
            max_phar_bytes: 64 * 1024 * 1024,
        }
    }
}

/// 一个目录的已装清单。
#[derive(Debug, Clone)]
pub struct DirListing {
    pub project_type: &'static str,
    pub dir: &'static str,
    /// 这个目录在实例里存在吗。
    ///
    /// **不替前端决定要不要隐藏标签**，但把事实给出去 ——
    /// 下载完第一个模组时目录才会被建出来。
    pub exists: bool,
    pub files: Vec<model::Installed>,
}

/// 扫描实例的 `mods/` 与 `plugins/`。
pub fn scan(root: &Path, limits: &Limits, cache: &MetaCache) -> Vec<DirListing> {
    model::PROJECT_TYPES
        .iter()
        .map(|entry| {
            let dir = root.join(entry.dir);
            let exists = dir.is_dir();
            let files = if exists {
                list_dir(&dir, limits, cache)
            } else {
                Vec::new()
            };
            DirListing {
                project_type: entry.id,
                dir: entry.dir,
                exists,
                files,
            }
        })
        .collect()
}

/// 列一个目录。
fn list_dir(dir: &Path, limits: &Limits, cache: &MetaCache) -> Vec<model::Installed> {
    let Ok(entries) = fs::read_dir(dir) else {
        // 目录存在但读不动（权限）—— 当作空目录。真实原因会在别处（用户
        // 装模组失败时）暴露出来，这里没必要把它变成整页报错。
        return Vec::new();
    };

    let mut out: Vec<model::Installed> = Vec::new();
    for entry in entries.flatten().take(limits.max_files) {
        let path = entry.path();
        let Some(file_name) = path.file_name().and_then(|name| name.to_str()) else {
            continue; // 非 UTF-8 文件名：列出来也没法在前端操作
        };

        let (base_name, enabled) = split_disabled(file_name);
        // 只认 `.jar` / `.phar`（含被禁用的 `.jar.disabled` 那种）：别的文件不是模组
        let lower = base_name.to_ascii_lowercase();
        if !model::FILE_EXTS
            .iter()
            .any(|ext| lower.ends_with(&format!(".{ext}")))
        {
            continue;
        }
        // 符号链接：`read_dir` 给的是链接本身，用 `metadata` 会跟随到目标 ——
        // 列表里显示的大小应当是被链接到的真实文件，这里用 `metadata` 是对的。
        let Ok(metadata) = fs::metadata(&path) else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }

        let size = metadata.len();
        let modified_ms = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .map(|delta| delta.as_millis() as i64)
            .unwrap_or(0);

        out.push(model::Installed {
            file_name: file_name.to_string(),
            base_name: base_name.to_string(),
            enabled,
            size,
            modified_ms,
            meta: cache.meta_of(&path, size, modified_ms, limits),
        });
    }

    // 按显示名忽略大小写排序 —— 与文件管理器同一条口径（`files::list` 也是这么排的）
    out.sort_by(|a, b| {
        a.base_name
            .to_lowercase()
            .cmp(&b.base_name.to_lowercase())
            .then_with(|| a.file_name.cmp(&b.file_name))
    });
    out
}

/// 把文件名拆成「基名 + 是否启用」。
///
/// 只有**末尾**那个 `.disabled` 算后缀，`a.disabled.jar` 是普通名字
/// （它确实是个启用的 jar）。
pub fn split_disabled(file_name: &str) -> (&str, bool) {
    match file_name.strip_suffix(model::DISABLED_SUFFIX) {
        Some(base) if !base.is_empty() => (base, false),
        _ => (file_name, true),
    }
}

// ---------------------------------------------------------------------------
// 启停 / 删除
// ---------------------------------------------------------------------------

/// 启用 / 禁用：改名。
///
/// 返回**改名后的文件名**（前端拿它更新列表，不必重扫一遍）。
pub fn set_enabled(
    root: &Path,
    project_type: &str,
    file_name: &str,
    enabled: bool,
) -> RpcResult<String> {
    let dir = dir_of(root, project_type)?;
    let current = safe_join(&dir, file_name)?;

    if !current.is_file() {
        return Err(not_found(file_name));
    }

    let (base, is_enabled) = split_disabled(file_name);
    if is_enabled == enabled {
        // 幂等：已经是要的状态就原样返回，不报错（前端重试 / 双点不该失败）
        return Ok(file_name.to_string());
    }

    let target_name = if enabled {
        base.to_string()
    } else {
        format!("{file_name}{}", model::DISABLED_SUFFIX)
    };
    let target = safe_join(&dir, &target_name)?;

    // **不覆盖**：目标名字已经被占了就报错让用户先处理，默默覆盖等于删了他一个文件
    if target.exists() {
        return Err(RpcError::new(
            "mods_target_exists",
            format!("`{target_name}` 已经存在，无法重命名"),
        ));
    }

    fs::rename(&current, &target)
        .map_err(|e| RpcError::new("mods_io_error", format!("重命名 `{file_name}` 失败：{e}")))?;
    Ok(target_name)
}

/// 删除一个已装文件。
///
/// 只删一个文件，**不追问、不备份** —— 模组是可以重新下回来的东西，
/// 而「删错了怎么办」的答案在用户那边（上游页面一键重下）。
pub fn remove(root: &Path, project_type: &str, file_name: &str) -> RpcResult<()> {
    let dir = dir_of(root, project_type)?;
    let path = safe_join(&dir, file_name)?;

    // `is_file()` 会跟随符号链接：一个指向别处的链接不该被当成「文件」删掉目标。
    // 所以先判链接本身，再判类型。
    let metadata = fs::symlink_metadata(&path).map_err(|_| not_found(file_name))?;
    if metadata.file_type().is_symlink() || metadata.is_file() {
        fs::remove_file(&path)
            .map_err(|e| RpcError::new("mods_io_error", format!("删除 `{file_name}` 失败：{e}")))?;
        return Ok(());
    }

    Err(RpcError::new(
        "mods_not_a_file",
        format!("`{file_name}` 不是一个文件"),
    ))
}

/// 项目类型 → 目录的**绝对路径**（目录不存在不报错，调用方按需要建）。
pub fn dir_of(root: &Path, project_type: &str) -> RpcResult<PathBuf> {
    let dir = model::dir_of(project_type).ok_or_else(|| {
        RpcError::new(
            "mods_type_not_found",
            format!(
                "不认识的项目类型 `{project_type}`；可选：{}",
                model::project_type_ids().join(", ")
            ),
        )
    })?;
    Ok(root.join(dir))
}

/// 把一个用户给的文件名并进目录，**只允许单段**。
///
/// 这里复用 `files::resolve` 那套「拒绝对路径 + 任意 `..`」的实现（安全边界
/// 只允许有一份），但我们额外要求**不含分隔符** —— 模组文件名就该是单段，
/// 放行 `mods/a.jar` 这种写法只会让「他到底在删哪个目录里的东西」变模糊。
fn safe_join(dir: &Path, file_name: &str) -> RpcResult<PathBuf> {
    let trimmed = file_name.trim();
    if trimmed.is_empty() {
        return Err(RpcError::invalid_params("文件名不能为空"));
    }
    if trimmed.contains(['/', '\\']) {
        return Err(RpcError::invalid_params(format!(
            "文件名不能包含路径分隔符：`{trimmed}`"
        )));
    }
    // 再过一遍公共入口：`..` / 绝对路径在这里被挡掉
    files::resolve(dir, trimmed)
}

fn not_found(file_name: &str) -> RpcError {
    RpcError::new("mods_not_found", format!("`{file_name}` 不在这个目录里"))
}

// ---------------------------------------------------------------------------
// 元数据缓存
// ---------------------------------------------------------------------------

/// 按「绝对路径 + 大小 + mtime」缓存解析结果。
#[derive(Default)]
pub struct MetaCache {
    entries: Mutex<HashMap<PathBuf, Entry>>,
}

struct Entry {
    size: u64,
    modified_ms: i64,
    /// `None` = 这个 jar 里没有可识别的元数据（这个结论也值得缓存）。
    meta: Option<model::Meta>,
}

/// 缓存条数上限。超了就整体清空 —— 一个实例不会有两千个模组，
/// 真到了这个量级说明调用模式不对，简单清空比实现 LRU 划算。
const CACHE_CAP: usize = 2_048;

impl MetaCache {
    /// 读一个文件的元数据（命中缓存就不开 zip）。
    fn meta_of(
        &self,
        path: &Path,
        size: u64,
        modified_ms: i64,
        limits: &Limits,
    ) -> Option<model::Meta> {
        if let Some(entry) = self
            .entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(path)
            && entry.size == size
            && entry.modified_ms == modified_ms
        {
            return entry.meta.clone();
        }

        let meta = read_meta(path, limits);

        let mut entries = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        if entries.len() >= CACHE_CAP {
            entries.clear();
        }
        entries.insert(
            path.to_path_buf(),
            Entry {
                size,
                modified_ms,
                meta: meta.clone(),
            },
        );
        meta
    }

    /// 主动丢掉一个路径的缓存（删文件后调用，省一条陈旧记录）。
    pub fn forget(&self, path: &Path) {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(path);
    }
}

// ---------------------------------------------------------------------------
// SHA1 缓存
// ---------------------------------------------------------------------------

/// 按「绝对路径 + 大小 + mtime」缓存算好的 SHA1。
///
/// 与元数据缓存同一个道理：算 SHA1 要**整读一遍文件**（几十 MB 的模组包不少见），
/// 而同一批哈希会被问好几次 —— 「配图标」（进页面一次）与「检查更新」（点按钮一次）
/// 用的是同一批文件 —— 算一次存起来复用。
/// 哈希缓存的表项：`(文件大小, mtime, 算出来的 sha1)`。
///
/// 大小 + mtime 就是「这个文件还是不是同一个文件」的判据，与元数据缓存同一套。
type HashEntry = (u64, i64, Option<String>);

#[derive(Default)]
pub struct HashCache {
    entries: Mutex<HashMap<PathBuf, HashEntry>>,
}

impl HashCache {
    /// 取一个文件的 SHA1（命中缓存就不重算）。读不动就是 `None`。
    pub fn sha1_of(&self, path: &Path) -> Option<String> {
        // 先 stat 再拿锁：临界区里只做查表/插表
        let metadata = fs::metadata(path).ok()?;
        let size = metadata.len();
        let modified_ms = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .map(|delta| delta.as_millis() as i64)
            .unwrap_or(0);

        if let Some((cached_size, cached_ms, hash)) = self
            .entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(path)
            && *cached_size == size
            && *cached_ms == modified_ms
        {
            return hash.clone();
        }

        let hash = sha1_file(path);
        let mut entries = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        if entries.len() >= CACHE_CAP {
            entries.clear();
        }
        entries.insert(path.to_path_buf(), (size, modified_ms, hash.clone()));
        hash
    }

    /// 主动丢掉一个路径（删文件后调用）。
    pub fn forget(&self, path: &Path) {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(path);
    }
}

/// 算一个文件的 SHA1（十六进制小写）。读不动就是 `None`。
///
/// 与 `download` 模块那份同一个写法（`sha1_of_file`）：按块读，**不整个进内存**
/// —— 模组包能到几十 MB；十六进制也自己拼（为一行编码引 `hex` 依赖不划算）。
pub fn sha1_file(path: &Path) -> Option<String> {
    use sha1::{Digest, Sha1};

    let mut file = fs::File::open(path).ok()?;
    let mut hasher = Sha1::new();
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer).ok()?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Some(
        hasher
            .finalize()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect(),
    )
}

// ---------------------------------------------------------------------------
// 元数据解析
// ---------------------------------------------------------------------------

/// 认哪些元数据文件，**顺序即优先级**（越靠前越优先）：
/// fabric → quilt → neoforge.mods.toml → mods.toml → mcmod.info →
/// velocity-plugin.json → paper-plugin.yml → plugin.yml → bungee.yml。
///
/// **两处都比常见实现只多不少**：
///
/// 1. `paper-plugin.yml` 也认，且排在 `plugin.yml` 前 —— Paper 插件两个文件
///    都有、前者信息更全。**显示口径不变**（同样是 `bukkit` 那一档）。
/// 2. 条目名匹配**忽略大小写** —— 只影响 `Plugin.yml` 这种写法不规范但
///    确实存在的包，不会再漏读。
const CANDIDATES: &[(&str, &str)] = &[
    ("fabric.mod.json", "fabric"),
    ("quilt.mod.json", "quilt"),
    ("META-INF/neoforge.mods.toml", "forge"),
    ("META-INF/mods.toml", "forge"),
    ("mcmod.info", "mcmod"),
    ("velocity-plugin.json", "velocity"),
    ("paper-plugin.yml", "bukkit"),
    ("plugin.yml", "bukkit"),
    ("bungee.yml", "bungeecord"),
];

/// 按文件后缀分派：`.jar` 走 zip，`.phar` 走 tar（带一段 PHP stub）。
fn read_meta(path: &Path, limits: &Limits) -> Option<model::Meta> {
    let lower = path.file_name()?.to_str()?.to_ascii_lowercase();
    if lower.ends_with(".phar") || lower.ends_with(".phar.disabled") {
        return read_phar_meta(path, limits);
    }
    read_jar_meta(path, limits)
}

/// 开一次 zip，按优先级找出**可识别的**元数据。
///
/// **一次遍历**（不是「候选挨个 `by_name`」）：省掉逐个查找，也顺手把大小写
/// 差异抹平（有的 jar 里写 `Plugin.yml`）。
///
/// 遍历时不提前收工，而是记下「优先级最高的那个成功结果」——
/// `paper-plugin.yml` 坏掉时应当退回 `plugin.yml` 拿到答案，而不是因为
/// 「更高优先级的候选存在过」就报告读不出来。
fn read_jar_meta(path: &Path, limits: &Limits) -> Option<model::Meta> {
    let file = fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;

    let mut best: Option<(usize, model::Meta)> = None;
    for index in 0..zip.len() {
        let Ok(mut item) = zip.by_index(index) else {
            continue;
        };
        if item.is_dir() {
            continue;
        }
        let name = item.name().to_ascii_lowercase();
        let Some(position) = CANDIDATES
            .iter()
            .position(|(candidate, _)| candidate.to_ascii_lowercase() == name)
        else {
            continue;
        };
        // 已经拿到一个优先级更高的结论就不必再读这个（省一次解压）
        if best.as_ref().is_some_and(|(best, _)| *best <= position) {
            continue;
        }

        let mut buffer = Vec::new();
        if item
            .by_ref()
            .take(limits.max_entry_bytes)
            .read_to_end(&mut buffer)
            .is_err()
        {
            continue;
        }

        let (display, loader) = CANDIDATES[position];
        if let Some(meta) = parse_candidate(display, loader, &buffer) {
            // 已经是最优先的候选，后面不可能更好，直接收工
            if position == 0 {
                return Some(meta);
            }
            best = Some((position, meta));
        }
    }
    best.map(|(_, meta)| meta)
}

/// 按来源解析元数据。返回 `None` 表示「这个文件在这儿，但读不出东西」。
fn parse_candidate(from: &str, loader: &'static str, bytes: &[u8]) -> Option<model::Meta> {
    match loader {
        "fabric" => parse_fabric(bytes),
        "quilt" => parse_quilt(bytes),
        "velocity" => parse_velocity(bytes, from),
        // forge 与 neoforge **共用**一个解析（loader 由内容判），所以这里只认 "forge"
        "forge" => parse_mods_toml(bytes, from),
        // `mcmod.info` 是 JSON，不是 TOML —— 别让它走前面那个分支
        "mcmod" => parse_mcmod_info(bytes),
        other => std::str::from_utf8(bytes)
            .ok()
            .and_then(|text| parse_plugin_yml(text, other, from)),
    }
}

/// 一份空元数据骨架 —— 每个解析器只填自己认得的字段。
fn meta(from: &str, loader: &'static str) -> model::Meta {
    model::Meta {
        id: None,
        name: None,
        version: None,
        description: None,
        authors: None,
        url: None,
        from: from.to_string(),
        loader,
        environment: "unknown",
    }
}

/// `fabric.mod.json`。
///
/// `name` 与 `id` **都缺**才算认不出来；`url` 取
/// `contact.homepage`；`authors` 是数组（元素可以是字符串或 `{name}` 对象），
/// 用 `, ` 拼起来；`environment` 见 [`model::Meta::environment`] 的说明。
pub fn parse_fabric(bytes: &[u8]) -> Option<model::Meta> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let id = clean(value.get("id").and_then(serde_json::Value::as_str));
    let name = clean(value.get("name").and_then(serde_json::Value::as_str));
    if id.is_none() && name.is_none() {
        return None;
    }

    let mut out = meta("fabric.mod.json", "fabric");
    out.id = id;
    out.name = name;
    out.version = clean_version(value.get("version").and_then(serde_json::Value::as_str));
    out.description = clean(value.get("description").and_then(serde_json::Value::as_str));
    out.url = clean(
        value
            .get("contact")
            .and_then(|contact| contact.get("homepage"))
            .and_then(serde_json::Value::as_str),
    );
    out.authors = json_names(value.get("authors"));
    out.environment = fabric_environment(value.get("environment"));
    Some(out)
}

/// Fabric 的 `environment`：`client` / `server` / 其余（含缺失与 `*`）都是 both。
///
/// 缺失当 both 是 Fabric 规范自己说的默认值（`*`）。
fn fabric_environment(value: Option<&serde_json::Value>) -> &'static str {
    match value.and_then(serde_json::Value::as_str) {
        Some("client") => "client",
        Some("server") => "server",
        // 非字符串（含缺失）也是 both
        _ => "both",
    }
}

/// `quilt.mod.json`：id 与 version 在 `quilt_loader` 里，
/// 展示名 / 描述 / 侧别在 `metadata` 里。
pub fn parse_quilt(bytes: &[u8]) -> Option<model::Meta> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let loader = value.get("quilt_loader")?;
    let id = clean(loader.get("id").and_then(serde_json::Value::as_str))?;
    let metadata = value.get("metadata");

    let mut out = meta("quilt.mod.json", "quilt");
    out.id = Some(id.clone());
    out.name = clean(
        metadata
            .and_then(|metadata| metadata.get("name"))
            .and_then(serde_json::Value::as_str),
    )
    // 展示名缺了就用 id
    .or(Some(id));
    out.version = clean_version(loader.get("version").and_then(serde_json::Value::as_str));
    out.description = clean(
        metadata
            .and_then(|metadata| metadata.get("description"))
            .and_then(serde_json::Value::as_str),
    );
    // Quilt 服务端的写法是 `dedicated_server`，**与 Fabric 的 `server` 不同**
    out.environment = match metadata
        .and_then(|metadata| metadata.get("environment"))
        .and_then(serde_json::Value::as_str)
    {
        Some("client") => "client",
        Some("dedicated_server") => "server",
        _ => "both",
    };
    Some(out)
}

/// `META-INF/mods.toml` 与 `META-INF/neoforge.mods.toml`。
///
/// loader 由**内容**判定（含 `neoforge` 就是 NeoForge）——
/// 两个文件名都走这一个解析。
pub fn parse_mods_toml(bytes: &[u8], from: &str) -> Option<model::Meta> {
    let text = std::str::from_utf8(bytes).ok()?;
    let value: toml::Value = toml::from_str(text).ok()?;
    let entry = value.get("mods")?.as_array()?.first()?;

    let pick = |key: &str| {
        entry
            .get(key)
            .and_then(toml::Value::as_str)
            .and_then(|raw| clean(Some(raw)))
    };
    // 顶层（不在 `[[mods]]` 里）的那几个键
    let global = |key: &str| {
        value
            .get(key)
            .and_then(toml::Value::as_str)
            .and_then(|raw| clean(Some(raw)))
    };

    let id = pick("modId")?;
    let is_neoforge = text.contains("neoforge") || text.contains("NeoForge");

    let mut out = meta(from, if is_neoforge { "neoforge" } else { "forge" });
    out.id = Some(id.clone());
    out.name = pick("displayName").or(Some(id));
    out.version = clean_version(pick("version").as_deref());
    out.description = pick("description");
    out.authors = global("authors");
    out.url = global("displayURL");
    // **缺失 → unknown（不是 both）**：判不准就别动它，
    // 免得把服务端模组当成客户端模组删掉。
    //
    // 注意 `clientSideOnly` 在 TOML 里是**布尔**，不是字符串 —— 按字符串取会永远
    // 拿到 `None`，于是所有 Forge 模组都被判成 unknown（静默错，测试里才炸）。
    out.environment = match value.get("clientSideOnly") {
        None => "unknown",
        Some(toml::Value::Boolean(true)) => "client",
        Some(toml::Value::String(text)) if text.eq_ignore_ascii_case("true") => "client",
        Some(_) => "both",
    };
    Some(out)
}

/// `mcmod.info`（Forge 1.7.10 及更早）。
///
/// 顶层可以是数组，也可以是 `{ "modList": [...] }`；只取第一项。
pub fn parse_mcmod_info(bytes: &[u8]) -> Option<model::Meta> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let first = match &value {
        serde_json::Value::Array(items) => items.first()?,
        other => other.get("modList")?.as_array()?.first()?,
    };

    let name = clean(first.get("name").and_then(serde_json::Value::as_str))
        .or_else(|| clean(first.get("modid").and_then(serde_json::Value::as_str)))?;

    let mut out = meta("mcmod.info", "forge");
    out.name = Some(name);
    out.id = clean(first.get("modid").and_then(serde_json::Value::as_str));
    out.version = clean_version(first.get("version").and_then(serde_json::Value::as_str));
    out.description = clean(first.get("description").and_then(serde_json::Value::as_str));
    out.authors = json_names(first.get("authorList"));
    out.url = clean(first.get("url").and_then(serde_json::Value::as_str));
    Some(out)
}

/// `velocity-plugin.json`：**顶层是数组**，取第一个条目。
pub fn parse_velocity(bytes: &[u8], from: &str) -> Option<model::Meta> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let entry = value.as_array()?.first()?;
    let name = clean(entry.get("name").and_then(serde_json::Value::as_str))
        .or_else(|| clean(entry.get("id").and_then(serde_json::Value::as_str)))?;

    let mut out = meta(from, "velocity");
    out.name = Some(name);
    out.id = clean(entry.get("id").and_then(serde_json::Value::as_str));
    out.version = clean_version(entry.get("version").and_then(serde_json::Value::as_str));
    out.description = clean(entry.get("description").and_then(serde_json::Value::as_str));
    out.authors = json_names(entry.get("authors"));
    out.url = clean(entry.get("url").and_then(serde_json::Value::as_str));
    Some(out)
}

/// `plugin.yml` / `paper-plugin.yml` / `bungee.yml` 这类「扁平 YAML」。
///
/// **不引 YAML 依赖**：只要顶层几个标量（`name` / `version` / `description` /
/// `author` / `website` / `main`），行扫描就够，而引一个 YAML 库会顺带接受一大票
/// 我们并不支持的语法（锚点、多行标量），反而更容易给出错误的结论。
///
/// **这里刻意按缩进只认顶层键**：不看缩进的话，
///
/// ```yaml
/// name: MyPlugin
/// commands:
///   foo:
///     name: bar
/// ```
///
/// 里后出现的嵌套 `name` 会**覆盖**顶层那个，最终显示成 `bar`。按缩进只认
/// 顶层键（`foo` 与嵌套键都不进 map），拿到的名字才是对的。
pub fn parse_plugin_yml(text: &str, loader: &'static str, from: &str) -> Option<model::Meta> {
    let map = simple_yaml_map(text);
    let name = map.get("name").or_else(|| map.get("main")).cloned()?;

    let mut out = meta(from, loader);
    out.name = Some(name);
    out.id = map.get("main").cloned();
    out.version = clean_version(map.get("version").map(String::as_str));
    out.description = map.get("description").cloned();
    out.authors = map.get("author").or_else(|| map.get("authors")).cloned();
    out.url = map.get("website").cloned();
    // 插件系不声明侧别
    Some(out)
}

/// 「扁平 YAML」的顶层键值表。
///
/// 认三种写法：`key: value`、`key:` + 缩进的 `- a` 列表（用 `, ` 拼）、
/// `key: [a, b]`（内联列表）。**只收没有缩进的键**（见 [`parse_plugin_yml`] 的说明）。
fn simple_yaml_map(text: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let mut pending: Option<String> = None;
    let mut buffer: Vec<String> = Vec::new();

    for line in text.lines() {
        let trimmed = line.trim_end();
        if trimmed.trim().is_empty() || trimmed.trim_start().starts_with('#') {
            continue;
        }
        let indented = trimmed.starts_with([' ', '\t']);
        let content = trimmed.trim();

        // 列表项：挂在最近那个「值为空」的键下
        if let Some(item) = content.strip_prefix("- ") {
            if pending.is_some() {
                buffer.push(unquote(item.trim()));
            }
            continue;
        }
        // 缩进的**键**一律不当顶层键（不看缩进就会误收，见上面的说明）
        if indented {
            continue;
        }

        // 换到下一个顶层键了，把攒下的列表落表
        if let Some(key) = pending.take()
            && !buffer.is_empty()
        {
            out.insert(key, buffer.join(", "));
        }
        buffer.clear();

        let Some((key, value)) = content.split_once(':') else {
            continue;
        };
        let key = key.trim().to_string();
        let value = value.trim();

        if value.is_empty() {
            // 值在下面几行（列表）
            pending = Some(key);
            continue;
        }
        if let Some(inner) = value.strip_prefix('[').and_then(|v| v.strip_suffix(']')) {
            let joined = inner
                .split(',')
                .map(|item| unquote(item.trim()))
                .filter(|item| !item.is_empty())
                .collect::<Vec<_>>()
                .join(", ");
            if !joined.is_empty() {
                out.insert(key, joined);
            }
            continue;
        }
        // 带引号的取值：取到配对的那个引号为止（后面可能是行尾注释）
        let value = if value.starts_with(['"', '\'']) {
            let quote = value.chars().next().unwrap_or('"');
            let inner = &value[1..];
            inner.split(quote).next().unwrap_or(inner).to_string()
        } else {
            // 裸值：切掉行尾注释
            value.split(" #").next().unwrap_or(value).trim().to_string()
        };
        if let Some(value) = clean(Some(&value)) {
            out.insert(key, value);
        }
    }
    if let Some(key) = pending.take()
        && !buffer.is_empty()
    {
        out.insert(key, buffer.join(", "));
    }
    out
}

/// 去一对包裹的引号。
fn unquote(text: &str) -> String {
    let text = text.trim();
    if text.len() >= 2
        && ((text.starts_with('"') && text.ends_with('"'))
            || (text.starts_with('\'') && text.ends_with('\'')))
    {
        return text[1..text.len() - 1].to_string();
    }
    text.to_string()
}

/// JSON 里那种「作者数组」：元素可以是字符串，也可以是 `{ "name": … }`。
///
/// 字符串数组、对象数组、混合都按同一套处理（fabric 与 velocity 共用这一个）。
fn json_names(value: Option<&serde_json::Value>) -> Option<String> {
    let items = value?.as_array()?;
    let names: Vec<String> = items
        .iter()
        .filter_map(|item| match item {
            serde_json::Value::String(text) => clean(Some(text)),
            other => clean(other.get("name").and_then(serde_json::Value::as_str)),
        })
        .collect();
    if names.is_empty() {
        None
    } else {
        Some(names.join(", "))
    }
}

/// 去空白；空串归一成 `None`。
fn clean(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
}

/// 版本号里的**构建占位符**（`${file.jarVersion}`）当作「没给」。
///
/// 不替换是有意的：那个值要在运行时由加载器填，jar 里就是占位符本身，
/// 显示成 `${file.jarVersion}` 比显示成空更让人困惑。
fn clean_version(value: Option<&str>) -> Option<String> {
    clean(value).filter(|text| !text.starts_with("${"))
}

// ---------------------------------------------------------------------------
// .phar（PocketMine-MP 插件）
// ---------------------------------------------------------------------------

/// 读 `.phar` 的元数据。
///
/// `.phar` 是「一段 PHP stub + 一个归档 + 可选签名」，归档可能是 zip（`Phar::ZIP`）
/// 也可能是 tar（PocketMine 插件基本都是 tar）。两种都试一遍。
///
/// 里面要找的是 **`plugin.yml`**（PocketMine 的插件清单），解析走同一份
/// 「扁平 YAML」实现，只是 loader 标成 `pocketmine`。
fn read_phar_meta(path: &Path, limits: &Limits) -> Option<model::Meta> {
    let metadata = fs::metadata(path).ok()?;
    if metadata.len() > limits.max_phar_bytes {
        return None;
    }
    let bytes = fs::read(path).ok()?;

    // 1) zip 形式的 phar
    if let Ok(mut zip) = zip::ZipArchive::new(std::io::Cursor::new(bytes.clone())) {
        for index in 0..zip.len() {
            let Ok(mut item) = zip.by_index(index) else {
                continue;
            };
            if item.is_dir() || !is_plugin_manifest(item.name()) {
                continue;
            }
            let mut buffer = Vec::new();
            if item
                .by_ref()
                .take(limits.max_entry_bytes)
                .read_to_end(&mut buffer)
                .is_err()
            {
                continue;
            }
            if let Some(meta) = parse_plugin_yml(
                &String::from_utf8_lossy(&buffer),
                "pocketmine",
                "plugin.yml",
            ) {
                return Some(meta);
            }
        }
    }

    // 2) tar 形式的 phar：跳过 PHP stub 之后才是归档
    let start = phar_data_start(&bytes)?;
    let mut archive = tar::Archive::new(&bytes[start..]);
    for entry in archive.entries().ok()? {
        let Ok(mut entry) = entry else {
            continue;
        };
        let name = entry
            .path()
            .ok()
            .and_then(|path| path.file_name().map(|name| name.to_owned()))
            .and_then(|name| name.to_str().map(str::to_string))
            .unwrap_or_default();
        if !is_plugin_manifest(&name) {
            continue;
        }
        let mut buffer = Vec::new();
        if entry
            .by_ref()
            .take(limits.max_entry_bytes)
            .read_to_end(&mut buffer)
            .is_err()
        {
            continue;
        }
        if let Some(meta) = parse_plugin_yml(
            &String::from_utf8_lossy(&buffer),
            "pocketmine",
            "plugin.yml",
        ) {
            return Some(meta);
        }
    }
    None
}

/// 是不是 PocketMine 的插件清单（`plugin.yml`，位置不限）。
fn is_plugin_manifest(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == "plugin.yml" || lower.ends_with("/plugin.yml")
}

/// 归档数据的起点：跳过 PHAR 的 PHP stub。
///
/// stub 以 `__HALT_COMPILER();` 结束，后面可能还有 `?>` 与空白。这几个字符
/// 得按顺序逐个跳过 —— 少跳一个字节 tar 头就解析不出来。
fn phar_data_start(bytes: &[u8]) -> Option<usize> {
    const MARKER: &[u8] = b"__HALT_COMPILER";
    let index = bytes
        .windows(MARKER.len())
        .position(|window| window == MARKER)?;

    let mut at = index + MARKER.len();
    // 跳过 `();`
    while at < bytes.len() && matches!(bytes[at], b'(' | b')' | b';') {
        at += 1;
    }
    // 跳过 `?>` 与空白
    while at < bytes.len() && matches!(bytes[at], b'?' | b'>' | b'\r' | b'\n' | b' ' | b'\t') {
        at += 1;
    }
    // 后面必须还有东西（tar 至少要一个 512 字节的块头）
    (at < bytes.len()).then_some(at)
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // ── 「禁用」的表示 ────────────────────────────────────────────────────

    #[test]
    fn disabled_suffix_only_counts_at_the_end() {
        assert_eq!(split_disabled("sodium.jar"), ("sodium.jar", true));
        assert_eq!(split_disabled("sodium.jar.disabled"), ("sodium.jar", false));
        // 中间那个不算后缀
        assert_eq!(split_disabled("a.disabled.jar"), ("a.disabled.jar", true));
        // 光是后缀本身不算文件名
        assert_eq!(split_disabled(".disabled"), (".disabled", true));
    }

    #[test]
    fn filenames_with_separators_are_rejected() {
        let root = Path::new("/tmp/edgecube-mods-test");
        for bad in ["../x.jar", "a/b.jar", "a\\b.jar", ""] {
            assert!(
                safe_join(root, bad).is_err(),
                "`{bad}` 不该被当成合法文件名"
            );
        }
        assert!(safe_join(root, "ok.jar").is_ok());
    }

    // ── fabric.mod.json ──────────────────────────────────────────────────

    #[test]
    fn fabric_reads_every_field() {
        let raw = br#"{
            "id": "sodium",
            "name": "Sodium",
            "version": "0.7.3",
            "description": "A rendering engine replacement.",
            "contact": { "homepage": "https://caffeinemc.net", "sources": "x" },
            "authors": ["jellysquid3", { "name": "CaffeineMC" }]
        }"#;
        let meta = parse_fabric(raw).expect("fabric 元数据应当能解析");

        assert_eq!(meta.id.as_deref(), Some("sodium"));
        assert_eq!(meta.name.as_deref(), Some("Sodium"));
        assert_eq!(meta.version.as_deref(), Some("0.7.3"));
        assert_eq!(
            meta.description.as_deref(),
            Some("A rendering engine replacement.")
        );
        // url 只认 contact.homepage（不是 sources）
        assert_eq!(meta.url.as_deref(), Some("https://caffeinemc.net"));
        // 作者数组里字符串与 `{name}` 对象混着也要拼对
        assert_eq!(meta.authors.as_deref(), Some("jellysquid3, CaffeineMC"));
        assert_eq!(meta.loader, "fabric");
        assert_eq!(meta.from, "fabric.mod.json");
    }

    #[test]
    fn fabric_needs_a_name_or_an_id() {
        // 两者都缺才算认不出来
        assert!(parse_fabric(br#"{ "version": "1.0" }"#).is_none());
        // 只有 id 也认
        let only_id = parse_fabric(br#"{ "id": "x" }"#).unwrap();
        assert_eq!(only_id.name, None);
        assert_eq!(only_id.id.as_deref(), Some("x"));
    }

    #[test]
    fn fabric_environment_defaults_to_both() {
        // 缺失 = Fabric 规范里的 `*`（两端），不是 unknown
        assert_eq!(parse_fabric(br#"{"id":"a"}"#).unwrap().environment, "both");
        assert_eq!(
            parse_fabric(br#"{"id":"a","environment":"*"}"#)
                .unwrap()
                .environment,
            "both"
        );
        assert_eq!(
            parse_fabric(br#"{"id":"a","environment":"client,server"}"#)
                .unwrap()
                .environment,
            "both"
        );
        assert_eq!(
            parse_fabric(br#"{"id":"a","environment":"client"}"#)
                .unwrap()
                .environment,
            "client"
        );
        assert_eq!(
            parse_fabric(br#"{"id":"a","environment":"server"}"#)
                .unwrap()
                .environment,
            "server"
        );
        // 非字符串也按 both
        assert_eq!(
            parse_fabric(br#"{"id":"a","environment":1}"#)
                .unwrap()
                .environment,
            "both"
        );
    }

    #[test]
    fn fabric_client_only_is_detected() {
        let meta = parse_fabric(br#"{"id":"sodium","environment":"client"}"#).unwrap();
        assert!(meta.is_client_only(), "「客户端专属清理」就靠这个判断");
        assert!(
            !parse_fabric(br#"{"id":"a","environment":"server"}"#)
                .unwrap()
                .is_client_only()
        );
    }

    #[test]
    fn placeholder_versions_are_treated_as_missing() {
        // Fabric 模板里常见 `${file.jarVersion}`，它的值要运行时才填
        let meta = parse_fabric(br#"{ "id": "x", "version": "${file.jarVersion}" }"#).unwrap();
        assert!(meta.version.is_none());
        assert_eq!(meta.id.as_deref(), Some("x"));
    }

    // ── quilt.mod.json ──────────────────────────────────────────────────

    #[test]
    fn quilt_reads_the_nested_loader_object() {
        let raw = br#"{
            "quilt_loader": { "id": "my_mod", "version": "1.2.3" },
            "metadata": { "name": "My Mod", "description": "hi" }
        }"#;
        let meta = parse_quilt(raw).expect("quilt 元数据应当能解析");
        assert_eq!(meta.id.as_deref(), Some("my_mod"));
        assert_eq!(meta.name.as_deref(), Some("My Mod"));
        assert_eq!(meta.version.as_deref(), Some("1.2.3"));
        assert_eq!(meta.description.as_deref(), Some("hi"));
        assert_eq!(meta.loader, "quilt");
    }

    #[test]
    fn quilt_falls_back_to_the_id_as_name() {
        let raw = br#"{ "quilt_loader": { "id": "standalone" } }"#;
        assert_eq!(
            parse_quilt(raw).unwrap().name.as_deref(),
            Some("standalone")
        );
    }

    #[test]
    fn quilt_uses_dedicated_server_not_server() {
        // Quilt 的写法与 Fabric 不同，写错就会把服务端模组判成 both
        let raw = |env: &str| {
            format!(
                r#"{{ "quilt_loader": {{ "id": "x" }}, "metadata": {{ "environment": "{env}" }} }}"#
            )
        };
        assert_eq!(
            parse_quilt(raw("client").as_bytes()).unwrap().environment,
            "client"
        );
        assert_eq!(
            parse_quilt(raw("dedicated_server").as_bytes())
                .unwrap()
                .environment,
            "server"
        );
        // Fabric 的 `server` 在 Quilt 里不是合法值，按 both 处理
        assert_eq!(
            parse_quilt(raw("server").as_bytes()).unwrap().environment,
            "both"
        );
        assert_eq!(
            parse_quilt(raw("*").as_bytes()).unwrap().environment,
            "both"
        );
    }

    // ── META-INF/mods.toml（Forge / NeoForge）───────────────────────────

    const FORGE_TOML: &str = r#"
modLoader="javafml"
loaderVersion="[47,)"
license="MIT"
authors="Someone"
displayURL="https://example.com/jei"
clientSideOnly=true

[[mods]]
modId="jei"
version="15.2.0"
displayName="Just Enough Items"
description="看配方用的"

[[dependencies.jei]]
modId="minecraft"
side="BOTH"
"#;

    #[test]
    fn mods_toml_reads_the_first_mod_block_and_the_globals() {
        let meta = parse_mods_toml(FORGE_TOML.as_bytes(), "META-INF/mods.toml")
            .expect("mods.toml 应当能解析");
        assert_eq!(meta.id.as_deref(), Some("jei"));
        assert_eq!(meta.name.as_deref(), Some("Just Enough Items"));
        assert_eq!(meta.version.as_deref(), Some("15.2.0"));
        assert_eq!(meta.description.as_deref(), Some("看配方用的"));
        assert_eq!(meta.authors.as_deref(), Some("Someone"));
        assert_eq!(meta.url.as_deref(), Some("https://example.com/jei"));
        assert_eq!(meta.loader, "forge");
    }

    #[test]
    fn mods_toml_side_comes_from_client_side_only_only() {
        // `clientSideOnly = true` → 仅客户端
        assert_eq!(
            parse_mods_toml(FORGE_TOML.as_bytes(), "META-INF/mods.toml")
                .unwrap()
                .environment,
            "client"
        );
        // 明确写 false → both（注意这个键必须写在 `[[mods]]` **之前**：
        // 写在它后面就属于 mods 那张表，不再是顶层键了）
        let false_case = "clientSideOnly=false\n[[mods]]\nmodId=\"a\"\n";
        assert_eq!(
            parse_mods_toml(false_case.as_bytes(), "META-INF/mods.toml")
                .unwrap()
                .environment,
            "both"
        );
        // **缺失 → unknown**：判不准就别动它，免得把服务端模组当客户端模组删掉
        let missing = "[[mods]]\nmodId=\"a\"\n";
        assert_eq!(
            parse_mods_toml(missing.as_bytes(), "META-INF/mods.toml")
                .unwrap()
                .environment,
            "unknown"
        );
    }

    #[test]
    fn dependencies_side_does_not_decide_the_mod_side() {
        // `[[dependencies.x]]` 里的 `side` 说的是**依赖项**的要求，不是模组自己
        let raw = "[[mods]]\nmodId=\"a\"\n\n[[dependencies.a]]\nmodId=\"b\"\nside=\"CLIENT\"\n";
        let meta = parse_mods_toml(raw.as_bytes(), "META-INF/mods.toml").unwrap();
        assert_eq!(meta.environment, "unknown", "不能靠依赖的 side 判自己");
    }

    #[test]
    fn mods_toml_name_falls_back_to_the_mod_id() {
        let raw = "[[mods]]\nmodId=\"only_id\"\n";
        assert_eq!(
            parse_mods_toml(raw.as_bytes(), "META-INF/mods.toml")
                .unwrap()
                .name
                .as_deref(),
            Some("only_id")
        );
    }

    #[test]
    fn neoforge_is_detected_from_the_content_or_the_file_name() {
        // loader 按**内容**判（文本里含 `neoforge`），不是按文件名
        let neoforge = "# built for neoforge\n[[mods]]\nmodId=\"a\"\n";
        assert_eq!(
            parse_mods_toml(neoforge.as_bytes(), "META-INF/neoforge.mods.toml")
                .unwrap()
                .loader,
            "neoforge"
        );
        // 文件名也带上（前端用它显示「NeoForge」）
        assert_eq!(
            parse_mods_toml(neoforge.as_bytes(), "META-INF/neoforge.mods.toml")
                .unwrap()
                .from,
            "META-INF/neoforge.mods.toml"
        );
        // 普通 Forge 那个不喊 neoforge
        assert_eq!(
            parse_mods_toml(b"[[mods]]\nmodId=\"a\"\n", "META-INF/mods.toml")
                .unwrap()
                .loader,
            "forge"
        );
    }

    // ── mcmod.info ──────────────────────────────────────────────────────

    #[test]
    fn mcmod_info_accepts_both_the_array_and_the_mod_list_shape() {
        let array = br#"[{ "modid": "old", "name": "Old Mod", "version": "1.0",
                          "description": "d", "url": "https://x",
                          "authorList": ["a", "b"] }]"#;
        let meta = parse_mcmod_info(array).expect("数组形状应当能解析");
        assert_eq!(meta.id.as_deref(), Some("old"));
        assert_eq!(meta.name.as_deref(), Some("Old Mod"));
        assert_eq!(meta.authors.as_deref(), Some("a, b"));
        assert_eq!(meta.url.as_deref(), Some("https://x"));
        assert_eq!(meta.loader, "forge");

        let wrapped = br#"{ "modListVersion": 2, "modList": [{ "modid": "wrapped" }] }"#;
        assert_eq!(
            parse_mcmod_info(wrapped).unwrap().id.as_deref(),
            Some("wrapped")
        );
    }

    #[test]
    fn mcmod_info_without_a_name_is_not_recognised() {
        assert!(parse_mcmod_info(b"[]").is_none());
        assert!(parse_mcmod_info(br#"[{ "version": "1" }]"#).is_none());
    }

    // ── velocity-plugin.json ────────────────────────────────────────────

    #[test]
    fn velocity_reads_the_first_array_entry() {
        let raw = br#"[{ "id": "luckperms", "name": "LuckPerms", "version": "5.4",
                        "description": "perms", "url": "https://luckperms.net",
                        "authors": ["Luck", {"name": "Others"}] }]"#;
        let meta = parse_velocity(raw, "velocity-plugin.json").expect("velocity 应当能解析");
        assert_eq!(meta.id.as_deref(), Some("luckperms"));
        assert_eq!(meta.name.as_deref(), Some("LuckPerms"));
        assert_eq!(meta.authors.as_deref(), Some("Luck, Others"));
        assert_eq!(meta.loader, "velocity");
        // 插件系不声明侧别
        assert_eq!(meta.environment, "unknown");
    }

    #[test]
    fn velocity_falls_back_to_the_id_for_the_name() {
        let raw = br#"[{ "id": "only_id" }]"#;
        assert_eq!(
            parse_velocity(raw, "velocity-plugin.json")
                .unwrap()
                .name
                .as_deref(),
            Some("only_id")
        );
    }

    // ── plugin.yml / paper-plugin.yml / bungee.yml ──────────────────────

    #[test]
    fn plugin_yml_reads_the_documented_fields() {
        let raw = "name: LuckPerms\nversion: 5.4.102\nmain: me.lucko.LPBukkitPlugin\ndescription: 权限管理\nauthor: Luck\nwebsite: https://luckperms.net\napi-version: '1.21'\n";
        let meta = parse_plugin_yml(raw, "bukkit", "plugin.yml").expect("plugin.yml 应当能解析");
        assert_eq!(meta.name.as_deref(), Some("LuckPerms"));
        assert_eq!(meta.version.as_deref(), Some("5.4.102"));
        assert_eq!(meta.description.as_deref(), Some("权限管理"));
        assert_eq!(meta.authors.as_deref(), Some("Luck"));
        assert_eq!(meta.url.as_deref(), Some("https://luckperms.net"));
        // `main` 进 id
        assert_eq!(meta.id.as_deref(), Some("me.lucko.LPBukkitPlugin"));
        assert_eq!(meta.loader, "bukkit");
        assert_eq!(meta.from, "plugin.yml");
    }

    #[test]
    fn plugin_yml_falls_back_to_main_for_the_name() {
        let raw = "main: a.B\n";
        assert_eq!(
            parse_plugin_yml(raw, "bukkit", "plugin.yml")
                .unwrap()
                .name
                .as_deref(),
            Some("a.B")
        );
    }

    #[test]
    fn paper_and_bukkit_share_the_loader_but_not_the_file_name() {
        let raw = "name: X\n";
        let paper = parse_plugin_yml(raw, "bukkit", "paper-plugin.yml").unwrap();
        let legacy = parse_plugin_yml(raw, "bukkit", "plugin.yml").unwrap();
        // 展示口径一样（都是 bukkit 那一档，前端显示成「Plugin」）
        assert_eq!(paper.loader, legacy.loader);
        // 但 `from` 要说实话，用户排查问题时看得见读的是哪个文件
        assert_ne!(paper.from, legacy.from);
    }

    #[test]
    fn bungee_yml_is_its_own_loader() {
        let meta = parse_plugin_yml("name: B\n", "bungeecord", "bungee.yml").unwrap();
        assert_eq!(meta.loader, "bungeecord");
    }

    #[test]
    fn plugin_yml_handles_the_author_list_forms() {
        // 缩进列表
        let list = "name: X\nauthors:\n  - a\n  - b\n";
        assert_eq!(
            parse_plugin_yml(list, "bukkit", "plugin.yml")
                .unwrap()
                .authors
                .as_deref(),
            Some("a, b")
        );
        // 内联列表
        let inline = "name: X\nauthors: [a, b]\n";
        assert_eq!(
            parse_plugin_yml(inline, "bukkit", "plugin.yml")
                .unwrap()
                .authors
                .as_deref(),
            Some("a, b")
        );
    }

    #[test]
    fn plugin_yml_ignores_indented_keys() {
        // 行扫描按缩进只认顶层键：不看缩进的话，嵌套的 `name` 会**覆盖**顶层
        // 那个（最终显示成 `bar`）。
        let raw = "name: MyPlugin\ncommands:\n  foo:\n    name: bar\n";
        assert_eq!(
            parse_plugin_yml(raw, "bukkit", "plugin.yml")
                .unwrap()
                .name
                .as_deref(),
            Some("MyPlugin"),
            "嵌套的 name 不该顶掉顶层的"
        );
    }

    #[test]
    fn plugin_yml_strips_quotes_but_keeps_hashes_inside_them() {
        assert_eq!(
            parse_plugin_yml("name: \"My Plugin\" # 注释\n", "bukkit", "plugin.yml")
                .unwrap()
                .name
                .as_deref(),
            Some("My Plugin")
        );
        // 引号里的 `#` 是名字的一部分
        assert_eq!(
            parse_plugin_yml("name: \"a # b\"\n", "bukkit", "plugin.yml")
                .unwrap()
                .name
                .as_deref(),
            Some("a # b")
        );
    }

    #[test]
    fn plugin_yml_does_not_confuse_namespace_with_name() {
        assert_eq!(
            parse_plugin_yml("namespace: foo\nname: bar\n", "bukkit", "plugin.yml")
                .unwrap()
                .name
                .as_deref(),
            Some("bar")
        );
    }

    // ── 坏输入 ──────────────────────────────────────────────────────────

    #[test]
    fn a_corrupt_metadata_file_does_not_panic() {
        // 上游给什么字节都可能，解析器只该说「读不出来」
        assert!(parse_fabric(b"not json at all").is_none());
        assert!(parse_quilt(b"{}").is_none());
        assert!(parse_mods_toml(b"[[mods]", "META-INF/mods.toml").is_none());
        assert!(parse_mcmod_info(b"{").is_none());
        assert!(parse_velocity(b"{}", "velocity-plugin.json").is_none());
        assert!(parse_plugin_yml("", "bukkit", "plugin.yml").is_none());
        assert!(parse_plugin_yml("不是 yaml", "bukkit", "plugin.yml").is_none());
    }

    // ── .phar（PocketMine）────────────────────────────────────────────

    /// 造一个 tar 形式的 phar：PHP stub + 标准 tar。
    fn build_phar(entries: &[(&str, &str)]) -> Vec<u8> {
        let mut tar_bytes = Vec::new();
        {
            let mut builder = tar::Builder::new(&mut tar_bytes);
            for (name, body) in entries {
                let mut header = tar::Header::new_gnu();
                header.set_size(body.len() as u64);
                header.set_mode(0o644);
                header.set_cksum();
                builder
                    .append_data(&mut header, name, body.as_bytes())
                    .expect("应当能写入 tar 条目");
            }
            builder.finish().expect("应当能收尾");
        }

        let mut out = b"<?php\n__HALT_COMPILER(); ?>\n".to_vec();
        out.extend_from_slice(&tar_bytes);
        out
    }

    #[test]
    fn phar_finds_the_stub_then_parses_plugin_yml() {
        let phar = build_phar(&[(
            "plugin.yml",
            "name: EconomyAPI\nversion: 5.0.0\nauthor: onebone\ndescription: 经济系统\nmain: onebone\\economyapi\\EconomyAPI\n",
        )]);
        // 起点必须在 stub 之后（跳过 `();` 与 `?>` 与换行）
        let start = phar_data_start(&phar).expect("应当能定位归档起点");
        assert!(start > b"<?php\n__HALT_COMPILER(); ?>".len());

        let dir = std::env::temp_dir().join("edgecube-mods-phar-test");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("EconomyAPI.phar");
        fs::write(&path, &phar).unwrap();

        let meta = read_meta(&path, &Limits::default()).expect("phar 元数据应当能解析");
        assert_eq!(meta.name.as_deref(), Some("EconomyAPI"));
        assert_eq!(meta.version.as_deref(), Some("5.0.0"));
        assert_eq!(meta.authors.as_deref(), Some("onebone"));
        assert_eq!(meta.description.as_deref(), Some("经济系统"));
        assert_eq!(meta.loader, "pocketmine");
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn phar_without_the_halt_marker_is_not_recognised() {
        assert!(phar_data_start(b"<?php echo 1; ?>").is_none());
        // 标记在结尾、后面没有归档
        assert!(phar_data_start(b"__HALT_COMPILER();").is_none());
    }

    #[test]
    fn scan_accepts_both_jar_and_phar() {
        let root = std::env::temp_dir().join("edgecube-mods-scan-ext-test");
        let plugins = root.join("plugins");
        fs::create_dir_all(&plugins).unwrap();
        fs::write(plugins.join("EconomyAPI.phar"), b"not a phar").unwrap();
        fs::write(plugins.join("Legacy.jar"), b"not a jar").unwrap();
        fs::write(plugins.join("notes.txt"), b"nope").unwrap();
        fs::write(plugins.join("Old.phar.disabled"), b"nope").unwrap();

        let cache = MetaCache::default();
        let listings = scan(&root, &Limits::default(), &cache);
        let plugins = listings
            .iter()
            .find(|listing| listing.dir == "plugins")
            .expect("应当有 plugins 那一项");

        let names: Vec<&str> = plugins
            .files
            .iter()
            .map(|file| file.file_name.as_str())
            .collect();
        assert_eq!(
            names,
            vec!["EconomyAPI.phar", "Legacy.jar", "Old.phar.disabled"],
            "`.jar` 与 `.phar` 都认，`.txt` 不认"
        );
        // 禁用过的那个仍要标出来
        assert!(!plugins.files[2].enabled);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn hash_cache_reuses_the_result_and_notices_a_change() {
        let dir = std::env::temp_dir().join("edgecube-mods-hash-cache-test");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("a.bin");
        fs::write(&path, b"abc").unwrap();

        let cache = HashCache::default();
        let first = cache.sha1_of(&path).expect("应当能算出来");
        assert_eq!(first, "a9993e364706816aba3e25717850c26c9cd0d89d");
        // 第二次是查表（值一样）
        assert_eq!(cache.sha1_of(&path).as_deref(), Some(first.as_str()));

        // 内容变了（mtime 也会变）→ 必须重算
        fs::write(&path, b"abcd").unwrap();
        assert_ne!(cache.sha1_of(&path).as_deref(), Some(first.as_str()));

        // 手动忘掉之后还能算回来
        cache.forget(&path);
        assert!(cache.sha1_of(&path).is_some());
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn candidate_table_is_ordered_by_priority() {
        let names: Vec<&str> = CANDIDATES.iter().map(|(name, _)| *name).collect();
        assert_eq!(
            names,
            vec![
                "fabric.mod.json",
                "quilt.mod.json",
                "META-INF/neoforge.mods.toml",
                "META-INF/mods.toml",
                "mcmod.info",
                "velocity-plugin.json",
                "paper-plugin.yml",
                "plugin.yml",
                "bungee.yml",
            ],
            "顺序即优先级，越靠前越优先"
        );
    }
}
