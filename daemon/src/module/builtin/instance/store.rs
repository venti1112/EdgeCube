//! 实例元数据的存储层（同步 IO，调用方负责丢进 `spawn_blocking`）。
//!
//! # 目录布局（对齐 V1 的「索引 / 元数据 / 工作目录」三分离）
//!
//! ```text
//! <data_dir>/
//! ├── config/
//! │   ├── instances.json          # 索引：{ selected, instances: [{id,name,path?}] }
//! │   └── instances/
//! │       └── <id>.json           # 单个实例的完整元数据
//! └── instances/
//!     └── <id>/                   # 实例工作目录（服务端文件、世界存档……）
//! ```
//!
//! 为什么索引和元数据分开：实例列表只需要 `{id, name}`，不必把每个实例的
//! 启动配置都读进来；实例多了以后这是数量级差别。
//!
//! # 两条硬规则
//!
//! 1. **写文件必须原子**：先写 `<file>.tmp` 再 `rename`，中途崩溃不会留下半个
//!    JSON（否则下次启动整个实例列表都读不出来）。
//! 2. **id / path 来自客户端，必须校验**：id 会被直接拼进路径，
//!    `../` 之类必须挡在门口；删除时尤其致命。

use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::model::{DirStats, InstanceConfig, InstanceSummary};
use crate::error::{Error, Result};

/// 索引文件名（与 V1 一致）。
pub const INDEX_FILE_NAME: &str = "instances.json";
/// 元数据子目录名（与 V1 一致）。
pub const CONFIG_SUB_DIR: &str = "instances";
/// 工作目录子目录名（与 V1 一致）。
pub const DATA_SUB_DIR: &str = "instances";

/// id 的最大长度。id 是随机 hex 串，正常不会超过 16。
const MAX_ID_LEN: usize = 64;

/// 实例索引（`config/instances.json` 的内容）。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct InstanceIndex {
    /// 当前选中的实例 id；`None` = 没选。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected: Option<String>,
    #[serde(default)]
    pub instances: Vec<InstanceSummary>,
}

impl InstanceIndex {
    /// 找出指向某个 id 的下标。
    pub fn position(&self, id: &str) -> Option<usize> {
        self.instances.iter().position(|s| s.id == id)
    }

    pub fn contains(&self, id: &str) -> bool {
        self.position(id).is_some()
    }

    /// 名称是否已被占用（忽略首尾空白，与 V1 的 `_isNameTaken` 一致）。
    pub fn name_taken(&self, name: &str, except_id: Option<&str>) -> bool {
        let wanted = name.trim();
        self.instances
            .iter()
            .any(|s| s.name.trim() == wanted && Some(s.id.as_str()) != except_id)
    }
}

/// 实例元数据存储。克隆很便宜（只有一个 `PathBuf`）。
#[derive(Debug, Clone)]
pub struct InstanceStore {
    root: PathBuf,
}

impl InstanceStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// 数据根目录。
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// `<root>/config/instances.json`
    pub fn index_path(&self) -> PathBuf {
        self.root.join("config").join(INDEX_FILE_NAME)
    }

    /// `<root>/config/instances/<id>.json`
    pub fn config_path(&self, id: &str) -> PathBuf {
        self.root
            .join("config")
            .join(CONFIG_SUB_DIR)
            .join(format!("{id}.json"))
    }

    /// 实例工作目录的默认位置 `<root>/instances/<id>`。
    pub fn default_dir(&self, id: &str) -> PathBuf {
        self.root.join(DATA_SUB_DIR).join(id)
    }

    /// 某个实例实际使用的目录：元数据里写了自定义 `path` 就用它。
    pub fn instance_dir(&self, config: &InstanceConfig) -> PathBuf {
        match config.path.as_deref().filter(|p| !p.trim().is_empty()) {
            Some(custom) => PathBuf::from(custom),
            None => self.default_dir(&config.id),
        }
    }

    /// 建好 `config/`、`config/instances/`、`instances/` 三个目录。
    pub fn ensure_dirs(&self) -> Result<()> {
        std::fs::create_dir_all(self.root.join("config").join(CONFIG_SUB_DIR))?;
        std::fs::create_dir_all(self.root.join(DATA_SUB_DIR))?;
        Ok(())
    }

    /// 原子写 JSON：先写临时文件再 `rename`（与 V1 的
    /// `ConfigStore.writeJsonFile` 同一套做法）。
    ///
    /// 中途崩溃只会留下一个 `.tmp`，不会把原文件写成半个 JSON。
    /// 用 pretty 输出：元数据是给人也能看的，出问题时肉眼可查。
    ///
    /// 临时文件名**必须唯一**（带 pid + 进程内序号）：如果两个写入者共用
    /// `<file>.tmp`，先完成的一方 rename 之后，另一方的 rename 会因为源文件
    /// 已经不在而报 `ENOENT` —— 明明是个正常并发却写成失败。
    fn write_json<T: Serialize>(&self, path: &Path, value: &T) -> Result<()> {
        use std::sync::atomic::{AtomicU64, Ordering};

        static SEQ: AtomicU64 = AtomicU64::new(0);

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let body = serde_json::to_string_pretty(value)?;
        let tmp = PathBuf::from(format!(
            "{}.{}.{}.tmp",
            path.display(),
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&tmp, body)?;
        match std::fs::rename(&tmp, path) {
            Ok(()) => Ok(()),
            Err(e) => {
                // 失败时别把临时文件留在原地
                let _ = std::fs::remove_file(&tmp);
                Err(e.into())
            }
        }
    }

    // ── 索引 ───────────────────────────────────────────────────────────────

    /// 读索引。文件缺失、损坏、或个别条目坏掉都不算错 —— 能用多少用多少，
    /// 读不出来的条目记一条日志跳过（V1 的 `readJsonFile` 同样是"读失败当空"）。
    pub fn read_index(&self) -> InstanceIndex {
        let path = self.index_path();
        let raw = match std::fs::read_to_string(&path) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return InstanceIndex::default();
            }
            Err(e) => {
                tracing::warn!(path = %path.display(), error = %e, "读取实例索引失败，按空索引处理");
                return InstanceIndex::default();
            }
        };

        if raw.trim().is_empty() {
            return InstanceIndex::default();
        }

        // 逐条解析：一条坏掉不该拖垮整个列表
        let value: serde_json::Value = match serde_json::from_str(&raw) {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!(path = %path.display(), error = %e, "实例索引不是合法 JSON，按空索引处理");
                return InstanceIndex::default();
            }
        };

        let selected = value
            .get("selected")
            .and_then(|v| v.as_str())
            .map(str::to_string);

        let mut instances = Vec::new();
        if let Some(items) = value.get("instances").and_then(|v| v.as_array()) {
            for item in items {
                match serde_json::from_value::<InstanceSummary>(item.clone()) {
                    Ok(summary) if !summary.id.trim().is_empty() => instances.push(summary),
                    Ok(_) => tracing::warn!("索引里有一条实例缺少 id，已跳过"),
                    Err(e) => tracing::warn!(error = %e, "索引里有条目格式不对，已跳过"),
                }
            }
        }

        InstanceIndex {
            selected,
            instances,
        }
    }

    /// 写索引（原子写）。
    pub fn write_index(&self, index: &InstanceIndex) -> Result<()> {
        self.write_json(&self.index_path(), index)
    }

    // ── 单实例元数据 ───────────────────────────────────────────────────────

    /// 读单个实例的元数据；文件不存在返回 `None`。
    pub fn read_config(&self, id: &str) -> Result<Option<InstanceConfig>> {
        validate_id(id).map_err(|msg| Error::module("instance", msg))?;
        let path = self.config_path(id);
        let raw = match std::fs::read_to_string(&path) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e.into()),
        };
        if raw.trim().is_empty() {
            return Ok(None);
        }
        let config: InstanceConfig = serde_json::from_str(&raw)
            .map_err(|e| Error::module("instance", format!("实例 {id} 的元数据损坏: {e}")))?;
        Ok(Some(config))
    }

    /// 写单个实例的元数据（原子写），并刷新 `updated_at_ms`。
    ///
    /// 写失败时**不要**静默：元数据丢了就等于实例丢了。
    pub fn write_config(&self, config: &InstanceConfig) -> Result<()> {
        validate_id(&config.id).map_err(|msg| Error::module("instance", msg))?;
        let mut value = config.clone();
        value.updated_at_ms = Some(crate::util::now_ms());
        self.write_json(&self.config_path(&config.id), &value)
    }

    /// 删除单个实例的元数据文件。返回是否真的删掉了。
    pub fn delete_config(&self, id: &str) -> Result<bool> {
        validate_id(id).map_err(|msg| Error::module("instance", msg))?;
        let path = self.config_path(id);
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(e.into()),
        }
    }

    // ── 工作目录 ───────────────────────────────────────────────────────────

    /// 创建目录（含父目录）。
    pub fn create_dir(&self, dir: &Path) -> Result<()> {
        std::fs::create_dir_all(dir)?;
        Ok(())
    }

    /// 递归删除目录。返回是否真的删掉了。
    ///
    /// 调用方必须先过 [`validate_instance_dir`]：这个函数只负责"删"。
    pub fn remove_dir(&self, dir: &Path) -> Result<bool> {
        match std::fs::metadata(dir) {
            Ok(meta) if meta.is_dir() => {
                std::fs::remove_dir_all(dir)?;
                Ok(true)
            }
            Ok(_) => Err(Error::module(
                "instance",
                format!("{} 不是目录，拒绝删除", dir.display()),
            )),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(e.into()),
        }
    }

    /// 列出 `instances/` 下已经存在的目录名（跳过隐藏目录）。
    ///
    /// 目录不存在时先尝试创建：创建成功说明父目录可写、实例确实被删光了；
    /// 创建失败（存储没挂载、权限不足）就返回 `None`，调用方应当**跳过**
    /// 「清理缺失实例」这一步，绝不能因为一次读失败就把索引清空。
    pub fn discover_dirs(&self) -> Option<BTreeSet<String>> {
        let root = self.root.join(DATA_SUB_DIR);
        if !root.is_dir() {
            match std::fs::create_dir_all(&root) {
                Ok(()) => return Some(BTreeSet::new()),
                Err(e) => {
                    tracing::warn!(
                        path = %root.display(),
                        error = %e,
                        "实例根目录不存在且无法创建，跳过目录扫描（避免误删索引）"
                    );
                    return None;
                }
            }
        }

        let entries = match std::fs::read_dir(&root) {
            Ok(entries) => entries,
            Err(e) => {
                tracing::warn!(path = %root.display(), error = %e, "遍历实例根目录失败，跳过扫描");
                return None;
            }
        };

        let mut names = BTreeSet::new();
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            // 用 symlink_metadata：不跟随符号链接（跟出去可能删错东西）
            match entry.metadata() {
                Ok(meta) if meta.is_dir() => {
                    names.insert(name);
                }
                _ => {}
            }
        }
        Some(names)
    }

    // ── 杂项 ───────────────────────────────────────────────────────────────

    /// 统计目录体积。显式栈遍历（不用递归）避免深目录爆栈，
    /// 并且带条目数/深度上限，免得扫到几十 GB 的世界存档卡住。
    pub fn dir_stats(&self, path: &Path, max_entries: u64, max_depth: usize) -> DirStats {
        let mut stats = DirStats {
            exists: path.is_dir(),
            ..Default::default()
        };
        if !stats.exists {
            return stats;
        }

        let mut stack: Vec<(PathBuf, usize)> = vec![(path.to_path_buf(), 0)];
        let mut visited: u64 = 0;

        while let Some((dir, depth)) = stack.pop() {
            let entries = match std::fs::read_dir(&dir) {
                Ok(entries) => entries,
                // 单个子目录读不动（权限）就跳过，不影响整体统计
                Err(_) => continue,
            };
            for entry in entries.flatten() {
                visited += 1;
                if visited > max_entries {
                    stats.truncated = true;
                    return stats;
                }
                let meta = match entry.metadata() {
                    Ok(meta) => meta,
                    Err(_) => continue,
                };
                if meta.is_dir() {
                    stats.dir_count += 1;
                    if depth + 1 < max_depth {
                        stack.push((entry.path(), depth + 1));
                    } else {
                        stats.truncated = true;
                    }
                } else {
                    stats.file_count += 1;
                    stats.size_bytes = stats.size_bytes.saturating_add(meta.len());
                }
            }
        }
        stats
    }
}

// ══════════════════════════════════════════════════════════════════════════
// 校验与安全
// ══════════════════════════════════════════════════════════════════════════

/// 校验实例 id：只允许 `[0-9A-Za-z_-]`，长度 1..=64。
///
/// id 会被直接拼进文件路径，所以这是**安全边界**而不是格式偏好：
/// 放行 `..`、`/`、`\`、`:` 任何一个都可能让一次 `instance.delete`
/// 删掉数据目录之外的东西。
pub fn validate_id(id: &str) -> std::result::Result<(), String> {
    let id = id.trim();
    if id.is_empty() {
        return Err("实例 id 不能为空".to_string());
    }
    if id.len() > MAX_ID_LEN {
        return Err(format!("实例 id 过长（上限 {MAX_ID_LEN} 字符）"));
    }
    if !id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(format!(
            "实例 id `{id}` 含非法字符，只允许字母、数字、下划线与短横线"
        ));
    }
    Ok(())
}

/// 校验"可以删的实例目录"。
///
/// 比 [`validate_id`] 更宽（实例允许把工作目录放在数据根之外，如 proot rootfs
/// 内的路径），但必须挡住那些一旦误删就无法挽回的位置：
///
/// * 相对路径 —— 跟着 daemon 的 CWD 走，语义不确定；
/// * 含 `..` 或 `.` 的路径 —— 规范化后可能跑到别处；
/// * 层级过浅 —— `/`、`/etc`、`/tmp`、`/home` 这类；
/// * 等于文件系统根。
pub fn validate_instance_dir(path: &Path) -> std::result::Result<(), String> {
    if !path.is_absolute() {
        return Err(format!("实例目录必须是绝对路径: {}", path.display()));
    }
    for component in path.components() {
        match component {
            Component::ParentDir | Component::CurDir => {
                return Err(format!("实例目录不能包含 `.` 或 `..`: {}", path.display()));
            }
            Component::RootDir | Component::Prefix(_) | Component::Normal(_) => {}
        }
    }
    // 至少三层，如 /srv/edgecube/instances/xxx —— 挡住 /etc、/tmp 这种
    let depth = path
        .components()
        .filter(|c| matches!(c, Component::Normal(_)))
        .count();
    if depth < 3 {
        return Err(format!(
            "实例目录 `{}` 层级过浅（至少 3 层），拒绝删除以免误伤系统目录",
            path.display()
        ));
    }
    Ok(())
}

/// 生成一个 16 位十六进制实例 id（与 V1 的 `_generateId` 格式一致）。
///
/// 熵来自 `RandomState`（由操作系统给随机种子）+ 时间戳 + 进程内自增序号，
/// 不需要为此引入 uuid / rand 依赖。
pub fn generate_id() -> String {
    use std::hash::{BuildHasher, Hash, Hasher};
    use std::sync::atomic::{AtomicU64, Ordering};

    static SEQ: AtomicU64 = AtomicU64::new(0);

    let mut hasher = std::collections::hash_map::RandomState::new().build_hasher();
    crate::util::now_ms().hash(&mut hasher);
    std::process::id().hash(&mut hasher);
    SEQ.fetch_add(1, Ordering::Relaxed).hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::builtin::instance::model::RUNTIME_JAVA;

    /// 建一个临时数据目录；测试结束自动清掉。
    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new(tag: &str) -> Self {
            let dir = std::env::temp_dir().join(format!(
                "edgecube-instance-test-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            std::fs::create_dir_all(&dir).expect("应能建临时目录");
            Self(dir)
        }
        fn store(&self) -> InstanceStore {
            InstanceStore::new(&self.0)
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn generated_id_is_16_hex_and_unique() {
        let ids: Vec<String> = (0..64).map(|_| generate_id()).collect();
        for id in &ids {
            assert_eq!(id.len(), 16, "id 应为 16 位: {id}");
            assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
            assert!(validate_id(id).is_ok());
        }
        let unique: BTreeSet<&String> = ids.iter().collect();
        assert_eq!(unique.len(), ids.len(), "id 不该重复");
    }

    #[test]
    fn validate_id_blocks_path_traversal() {
        for bad in [
            "", "  ", "../etc", "a/b", "a\\b", "C:evil", "a b", ".hidden",
        ] {
            assert!(validate_id(bad).is_err(), "`{bad}` 应当被拒绝");
        }
        for good in ["a1b2c3", "ABC-123", "_x", "0"] {
            assert!(validate_id(good).is_ok(), "`{good}` 应当放行");
        }
        assert!(validate_id(&"a".repeat(65)).is_err(), "超长 id 应被拒绝");
    }

    #[test]
    fn validate_instance_dir_blocks_dangerous_paths() {
        for bad in [
            "/",
            "/etc",
            "/tmp",
            "/home",
            "relative/dir",
            "/srv/../etc",
            "/srv/./x",
        ] {
            assert!(
                validate_instance_dir(Path::new(bad)).is_err(),
                "`{bad}` 应当被拒绝"
            );
        }
        for good in ["/srv/edgecube/instances/abc", "/opt/rootfs/opt/abc"] {
            assert!(
                validate_instance_dir(Path::new(good)).is_ok(),
                "`{good}` 应当放行"
            );
        }
    }

    #[test]
    fn index_round_trip_and_atomic_write() {
        let temp = TempRoot::new("index");
        let store = temp.store();
        store.ensure_dirs().expect("应能建目录");

        let index = InstanceIndex {
            selected: Some("abc".into()),
            instances: vec![InstanceSummary::new("abc", "生存服")],
        };
        store.write_index(&index).expect("应能写索引");
        // 写完不该留下临时文件
        let leftovers: Vec<_> = std::fs::read_dir(temp.0.join("config"))
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|name| name.contains(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "不该留下临时文件: {leftovers:?}");

        let loaded = store.read_index();
        assert_eq!(loaded.selected.as_deref(), Some("abc"));
        assert_eq!(loaded.instances.len(), 1);
        assert_eq!(loaded.instances[0].name, "生存服");
        assert!(loaded.contains("abc"));
        assert!(
            loaded.name_taken(" 生存服 ", None),
            "重名判断应忽略首尾空白"
        );
        assert!(
            !loaded.name_taken("生存服", Some("abc")),
            "排除自己就不算重名"
        );
    }

    /// 两个线程同时写同一个文件不该报错（临时文件名唯一）。
    #[test]
    fn concurrent_writes_to_same_file_do_not_fail() {
        let temp = TempRoot::new("concurrent");
        let store = temp.store();
        store.ensure_dirs().expect("应能建目录");

        let handles: Vec<_> = (0..8)
            .map(|i| {
                let store = store.clone();
                std::thread::spawn(move || {
                    for round in 0..16 {
                        let index = InstanceIndex {
                            selected: Some(format!("{i}-{round}")),
                            instances: vec![InstanceSummary::new(format!("{i}"), "同名")],
                        };
                        store.write_index(&index).expect("并发写不该失败");
                    }
                })
            })
            .collect();
        for handle in handles {
            handle.join().expect("线程不应 panic");
        }

        // 最后一定是一个完整的索引（哪个线程赢都行）
        let loaded = store.read_index();
        assert!(loaded.selected.is_some());
        assert_eq!(loaded.instances.len(), 1);
    }

    #[test]
    fn broken_index_degrades_gracefully() {
        let temp = TempRoot::new("broken-index");
        let store = temp.store();
        store.ensure_dirs().expect("应能建目录");

        std::fs::write(store.index_path(), "{ 这不是 json").unwrap();
        let index = store.read_index();
        assert!(index.instances.is_empty() && index.selected.is_none());

        // JSON 合法但个别条目坏掉 → 好的那条还在
        std::fs::write(
            store.index_path(),
            r#"{"selected":"a","instances":[{"id":"a","name":"甲"},{"name":"没有 id"},42]}"#,
        )
        .unwrap();
        let index = store.read_index();
        assert_eq!(index.instances.len(), 1);
        assert_eq!(index.instances[0].id, "a");
    }

    #[test]
    fn config_round_trip_and_delete() {
        let temp = TempRoot::new("config");
        let store = temp.store();
        store.ensure_dirs().expect("应能建目录");

        assert!(store.read_config("nope").unwrap().is_none());

        let mut config = InstanceConfig::new("a1", "生存服");
        config.runtime = RUNTIME_JAVA.into();
        config.max_memory = Some(4096);
        store.write_config(&config).expect("应能写元数据");

        let loaded = store.read_config("a1").unwrap().expect("应能读回");
        assert_eq!(loaded.name, "生存服");
        assert_eq!(loaded.max_memory, Some(4096));
        assert!(
            loaded.updated_at_ms.is_some(),
            "写元数据应刷新 updated_at_ms"
        );

        assert!(store.delete_config("a1").unwrap());
        assert!(!store.delete_config("a1").unwrap(), "重复删除应返回 false");
        assert!(store.read_config("a1").unwrap().is_none());
    }

    #[test]
    fn config_path_rejects_bad_id() {
        let temp = TempRoot::new("bad-id");
        let store = temp.store();
        assert!(store.read_config("../secret").is_err());
        assert!(store.delete_config("a/b").is_err());
    }

    #[test]
    fn instance_dir_honours_custom_path() {
        let temp = TempRoot::new("custom-path");
        let store = temp.store();
        let mut config = InstanceConfig::new("a1", "服");
        assert_eq!(store.instance_dir(&config), store.default_dir("a1"));

        config.path = Some("/opt/rootfs/opt/a1".into());
        assert_eq!(
            store.instance_dir(&config),
            PathBuf::from("/opt/rootfs/opt/a1")
        );

        // 空字符串等同于没写
        config.path = Some("   ".into());
        assert_eq!(store.instance_dir(&config), store.default_dir("a1"));
    }

    #[test]
    fn dir_stats_counts_and_truncates() {
        let temp = TempRoot::new("stats");
        let store = temp.store();
        let dir = temp.0.join("instances").join("a1");
        std::fs::create_dir_all(dir.join("world")).unwrap();
        std::fs::write(dir.join("server.jar"), vec![0u8; 1024]).unwrap();
        std::fs::write(dir.join("world").join("level.dat"), vec![0u8; 512]).unwrap();

        let stats = store.dir_stats(&dir, 10_000, 12);
        assert!(stats.exists);
        assert_eq!(stats.file_count, 2);
        assert_eq!(stats.dir_count, 1);
        assert_eq!(stats.size_bytes, 1536);
        assert!(!stats.truncated);

        // 上限压到 1 → 触顶且数值只是下界
        let capped = store.dir_stats(&dir, 1, 12);
        assert!(capped.truncated);

        // 深度上限
        let shallow = store.dir_stats(&dir, 10_000, 1);
        assert!(shallow.truncated, "深度不够时应当标记不完整");

        // 不存在的目录
        let missing = store.dir_stats(&temp.0.join("nope"), 10, 3);
        assert!(!missing.exists && missing.size_bytes == 0);
    }

    #[test]
    fn discover_dirs_skips_hidden_and_files() {
        let temp = TempRoot::new("discover");
        let store = temp.store();
        store.ensure_dirs().expect("应能建目录");

        let root = temp.0.join(DATA_SUB_DIR);
        std::fs::create_dir_all(root.join("aaa")).unwrap();
        std::fs::create_dir_all(root.join(".hidden")).unwrap();
        std::fs::write(root.join("note.txt"), b"x").unwrap();

        let found = store.discover_dirs().expect("应能扫描");
        assert_eq!(found.len(), 1);
        assert!(found.contains("aaa"));
    }

    #[test]
    fn discover_dirs_gives_up_when_root_unusable() {
        // 根目录位置被一个**文件**占住 → 建不出目录 → 必须返回 None，
        // 让调用方跳过"清理缺失实例"，而不是把索引当空的清掉。
        let temp = TempRoot::new("unusable");
        let store = temp.store();
        std::fs::write(temp.0.join(DATA_SUB_DIR), b"not a dir").unwrap();
        assert!(store.discover_dirs().is_none());
    }
}
