//! FRP 的落盘层（同步 IO，调用方负责丢进 `spawn_blocking`）。
//!
//! # 目录布局
//!
//! ```text
//! <data_dir>/
//! └── config/
//!     └── frp/
//!         ├── auth.json                 # 各平台登录令牌 + 账号缓存（0600）
//!         ├── settings.json             # FRP 侧自己的设置（用哪个 frpc 跑隧道）
//!         ├── config/<localId>.json     # 一条已保存隧道的元数据（camelCase）
//!         └── toml/<localId>.toml       # 由元数据生成的 frpc 配置
//!                                       #   ← **一个 toml 就是一个可独立运行的 FRP 实例**
//! ```
//!
//! daemon 这边没有加密存储（Android Keystore 那类）可用，
//! 退而求其次：单独一个文件、权限 `0600`、只在自己进程里读。
//!
//! # 两条硬规则（同实例存储）
//!
//! 1. **写文件必须原子**：先写 `<file>.tmp` 再 `rename`。
//! 2. **localId 来自客户端，必须校验**：它会被拼进路径，`../` 一律挡在门口。

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

// rand 0.10：`random_range` 在 `RngExt` 上（见 api/openfrp.rs 的说明）。
use rand::RngExt as _;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::model::{Account, Provider, SavedTunnel};
use crate::error::{Error, Result};
use crate::util::now_ms;

/// 令牌文件权限（仅 Unix 生效）。
const TOKEN_FILE_MODE: u32 = 0o600;
/// localId 的长度上限。它是随机 hex 串，正常恒为 16。
const MAX_ID_LEN: usize = 64;

/// 一个平台的登录令牌与账号缓存。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AuthEntry {
    /// 登录令牌。ChmlFrp 存的是 `{at, rt, exp}` 的 JSON 串。
    pub token: String,
    #[serde(default)]
    pub account: Account,
}

/// `auth.json` 的内容：平台 key → 令牌。
pub type AuthBook = BTreeMap<String, AuthEntry>;

/// FRP 侧自己的设置（`settings.json`）—— 与具体隧道无关的那几项。
///
/// 放这儿而不是放在某条隧道的元数据里：**跑隧道用哪个 frpc 是全局的一件事**，
/// 换 frpc 版本不该逐条隧道去改。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct FrpSettings {
    /// 跑隧道用哪个 frpc 运行环境（`frp-frpc-0.71.0-linux-x64`）。
    ///
    /// 存 id 不存路径：数据根搬家之后 id 仍指得对，可执行文件每次现算。
    /// `None` = 还没选过 —— 这时用第一个装好的 frpc 环境（`frp.runtimes` 的
    /// 第一项），省掉「装完还得先去选一次」这一步。
    pub frpc_runtime_id: Option<String>,
}

/// FRP 存储。克隆很便宜（只有一个 `PathBuf`）。
#[derive(Debug, Clone)]
pub struct FrpStore {
    root: PathBuf,
}

impl FrpStore {
    /// `root` 是 `<data_dir>/config/frp`。
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// 隧道元数据目录 `config/`。
    pub fn meta_dir(&self) -> PathBuf {
        self.root.join("config")
    }

    /// 隧道配置目录 `toml/`。
    pub fn toml_dir(&self) -> PathBuf {
        self.root.join("toml")
    }

    fn auth_path(&self) -> PathBuf {
        self.root.join("auth.json")
    }

    /// `<root>/settings.json`。
    pub fn settings_path(&self) -> PathBuf {
        self.root.join("settings.json")
    }

    /// 读 FRP 侧自己的设置。读不到 / 坏了都当「还没配过」——
    /// 这条设置丢了不会让谁的数据没了，最坏是回落到「用第一个装好的 frpc」。
    pub fn read_settings(&self) -> FrpSettings {
        let Ok(text) = std::fs::read_to_string(self.settings_path()) else {
            return FrpSettings::default();
        };
        serde_json::from_str(&text).unwrap_or_default()
    }

    /// 写 FRP 侧自己的设置（原子写）。
    pub fn write_settings(&self, settings: &FrpSettings) -> Result<()> {
        let body = serde_json::to_string_pretty(settings)?;
        self.write_atomic(&self.settings_path(), &body, None)
    }

    /// localId 合法性与路径注入防护。
    pub fn is_valid_local_id(id: &str) -> bool {
        !id.is_empty() && id.len() <= MAX_ID_LEN && id.chars().all(|c| c.is_ascii_hexdigit())
    }

    fn meta_path(&self, id: &str) -> Result<PathBuf> {
        if !Self::is_valid_local_id(id) {
            return Err(Error::other(format!("非法的隧道 id `{id}`")));
        }
        Ok(self.meta_dir().join(format!("{id}.json")))
    }

    /// `<root>/toml/<id>.toml`。
    pub fn toml_path(&self, id: &str) -> Result<PathBuf> {
        if !Self::is_valid_local_id(id) {
            return Err(Error::other(format!("非法的隧道 id `{id}`")));
        }
        Ok(self.toml_dir().join(format!("{id}.toml")))
    }

    /// 原子写文本：先写同目录的临时文件再 `rename`。
    ///
    /// 临时文件名带 pid + 进程内序号（理由同实例存储：共用 `.<name>.tmp`
    /// 会让并发写的第二个写者 rename 失败）。
    fn write_atomic(&self, path: &Path, body: &str, mode: Option<u32>) -> Result<()> {
        use std::io::Write as _;
        use std::sync::atomic::{AtomicU64, Ordering};

        static SEQ: AtomicU64 = AtomicU64::new(0);

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let tmp = PathBuf::from(format!(
            "{}.{}.{}.tmp",
            path.display(),
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));

        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        if let Some(mode) = mode {
            use std::os::unix::fs::OpenOptionsExt as _;
            options.mode(mode);
        }
        #[cfg(not(unix))]
        let _ = mode;

        let write_result = (|| -> std::io::Result<()> {
            let mut file = options.open(&tmp)?;
            file.write_all(body.as_bytes())?;
            file.flush()
        })();
        if let Err(e) = write_result {
            let _ = std::fs::remove_file(&tmp);
            return Err(e.into());
        }

        match std::fs::rename(&tmp, path) {
            Ok(()) => Ok(()),
            Err(e) => {
                let _ = std::fs::remove_file(&tmp);
                Err(e.into())
            }
        }
    }

    // ── 令牌与账号 ────────────────────────────────────────────────────────

    /// 读整本 `auth.json`。文件缺失 / 坏掉都当空本子（令牌丢了让用户重登，
    /// 不该因此让整个模块不可用）。
    pub fn read_auth(&self) -> AuthBook {
        let path = self.auth_path();
        let Ok(text) = std::fs::read_to_string(&path) else {
            return AuthBook::new();
        };
        match serde_json::from_str::<AuthBook>(&text) {
            Ok(book) => book,
            Err(e) => {
                tracing::warn!(error = %e, path = %path.display(), "auth.json 解析失败，按未登录处理");
                AuthBook::new()
            }
        }
    }

    fn write_auth(&self, book: &AuthBook) -> Result<()> {
        let body = serde_json::to_string_pretty(book)?;
        self.write_atomic(&self.auth_path(), &body, Some(TOKEN_FILE_MODE))
    }

    /// 登录令牌；没登录过返回 `None`。
    pub fn token(&self, provider: Provider) -> Option<String> {
        self.read_auth()
            .get(provider.key())
            .map(|entry| entry.token.clone())
            .filter(|t| !t.is_empty())
    }

    /// 缓存的账号信息；没登录过返回 `None`。
    pub fn account(&self, provider: Provider) -> Option<Account> {
        self.read_auth()
            .get(provider.key())
            .map(|entry| entry.account.clone())
            .filter(|a| !a.username.is_empty())
    }

    /// 保存令牌 + 账号（登录成功后调用）。
    pub fn save_token(&self, provider: Provider, token: &str, account: &Account) -> Result<()> {
        let mut book = self.read_auth();
        book.insert(
            provider.key().to_string(),
            AuthEntry {
                token: token.to_string(),
                account: account.clone(),
            },
        );
        self.write_auth(&book)
    }

    /// 只换令牌（ChmlFrp 刷新后回写），账号缓存保持原样。
    pub fn update_token(&self, provider: Provider, token: &str) -> Result<()> {
        let mut book = self.read_auth();
        let entry = book.entry(provider.key().to_string()).or_default();
        entry.token = token.to_string();
        self.write_auth(&book)
    }

    /// 退出登录（令牌与账号缓存一起清）。
    pub fn clear_token(&self, provider: Provider) -> Result<()> {
        let mut book = self.read_auth();
        if book.remove(provider.key()).is_some() {
            self.write_auth(&book)?;
        }
        Ok(())
    }

    // ── 隧道注册表 ────────────────────────────────────────────────────────

    /// 读全部已保存隧道，按创建时间排序。
    ///
    /// 单个文件坏掉只跳过它 —— 一条坏元数据不该让整个列表消失。
    pub fn load_tunnels(&self) -> Vec<SavedTunnel> {
        let dir = self.meta_dir();
        let Ok(entries) = std::fs::read_dir(&dir) else {
            return Vec::new();
        };

        let mut rows: Vec<(u64, SavedTunnel)> = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&path) else {
                continue;
            };
            let Ok(raw) = serde_json::from_str::<serde_json::Value>(&text) else {
                tracing::warn!(path = %path.display(), "隧道元数据不是合法 JSON，已跳过");
                continue;
            };
            let created_at = raw.get("createdAt").and_then(|v| v.as_u64()).unwrap_or(0);
            match serde_json::from_value::<SavedTunnel>(raw) {
                Ok(tunnel) if !tunnel.local_id.is_empty() => rows.push((created_at, tunnel)),
                Ok(_) => tracing::warn!(path = %path.display(), "隧道元数据没有 localId，已跳过"),
                Err(e) => {
                    tracing::warn!(error = %e, path = %path.display(), "隧道元数据解析失败，已跳过")
                }
            }
        }
        rows.sort_by_key(|(created_at, _)| *created_at);
        rows.into_iter().map(|(_, tunnel)| tunnel).collect()
    }

    /// 新增或更新一条隧道（按 localId 定位文件）。保留首次写入的创建时间，
    /// 保证列表顺序稳定。
    pub fn upsert_tunnel(&self, tunnel: &SavedTunnel) -> Result<()> {
        let path = self.meta_path(&tunnel.local_id)?;

        let created_at = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
            .and_then(|value| value.get("createdAt").and_then(|v| v.as_u64()))
            .unwrap_or_else(now_ms);

        let mut value = serde_json::to_value(tunnel)?;
        if let Some(object) = value.as_object_mut() {
            object.insert("createdAt".to_string(), json!(created_at));
        }
        let body = serde_json::to_string_pretty(&value)?;
        self.write_atomic(&path, &body, None)
    }

    /// 删除一条隧道（元数据 + 配置文件）。
    pub fn remove_tunnel(&self, id: &str) -> Result<()> {
        let meta = self.meta_path(id)?;
        if meta.exists() {
            std::fs::remove_file(&meta)?;
        }
        let toml = self.toml_path(id)?;
        if toml.exists() {
            std::fs::remove_file(&toml)?;
        }
        Ok(())
    }

    /// 取某条隧道的元数据；不存在返回 `None`。
    pub fn tunnel(&self, id: &str) -> Option<SavedTunnel> {
        self.load_tunnels()
            .into_iter()
            .find(|tunnel| tunnel.local_id == id)
    }

    // ── frpc 配置 ─────────────────────────────────────────────────────────

    /// 写入 frpc 配置，返回文件路径（将来直接把这个路径交给 frpc）。
    pub fn write_toml(&self, id: &str, content: &str) -> Result<PathBuf> {
        let path = self.toml_path(id)?;
        self.write_atomic(&path, content, None)?;
        Ok(path)
    }

    /// 读已保存的 frpc 配置；文件不存在返回 `None`。
    pub fn read_toml(&self, id: &str) -> Option<String> {
        let path = self.toml_path(id).ok()?;
        std::fs::read_to_string(&path).ok()
    }

    pub fn toml_exists(&self, id: &str) -> bool {
        self.toml_path(id).map(|p| p.exists()).unwrap_or(false)
    }

    /// 生成不与现有条目冲突的随机 16 位十六进制 localId（与实例 ID 同策略）。
    pub fn new_local_id(&self) -> String {
        let mut rng = rand::rng();
        loop {
            let id: String = (0..16)
                .map(|_| char::from_digit(rng.random_range(0..16), 16).unwrap_or('0'))
                .collect();
            if let Ok(path) = self.meta_path(&id)
                && !path.exists()
            {
                return id;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store() -> (tempdir::TempDir, FrpStore) {
        let dir = tempdir::TempDir::new("edgecube-frp-store");
        let store = FrpStore::new(dir.path().join("frp"));
        (dir, store)
    }

    /// 一个只够测试用的临时目录实现（不引第三方 crate）。
    mod tempdir {
        use std::path::{Path, PathBuf};
        use std::sync::atomic::{AtomicU64, Ordering};

        pub struct TempDir(PathBuf);

        impl TempDir {
            pub fn new(tag: &str) -> Self {
                static SEQ: AtomicU64 = AtomicU64::new(0);
                let path = std::env::temp_dir().join(format!(
                    "{tag}-{}-{}",
                    std::process::id(),
                    SEQ.fetch_add(1, Ordering::Relaxed)
                ));
                std::fs::create_dir_all(&path).expect("建临时目录");
                Self(path)
            }

            pub fn path(&self) -> &Path {
                &self.0
            }
        }

        impl Drop for TempDir {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
    }

    fn sample_tunnel(id: &str, name: &str) -> SavedTunnel {
        SavedTunnel {
            local_id: id.to_string(),
            provider: Provider::OpenFrp,
            name: name.to_string(),
            node_id: "42".into(),
            local_port: 25565,
            remote_port: Some(30000),
            ..Default::default()
        }
    }

    #[test]
    fn tunnels_round_trip_and_sort_by_creation() {
        let (_dir, store) = temp_store();
        let first = store.new_local_id();
        store
            .upsert_tunnel(&sample_tunnel(&first, "第一条"))
            .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(5));
        let second = store.new_local_id();
        store
            .upsert_tunnel(&sample_tunnel(&second, "第二条"))
            .unwrap();

        let tunnels = store.load_tunnels();
        assert_eq!(tunnels.len(), 2);
        assert_eq!(tunnels[0].name, "第一条");
        assert_eq!(tunnels[1].name, "第二条");

        // 更新不改变创建顺序
        let mut updated = sample_tunnel(&first, "改过名");
        updated.remote_port = Some(30001);
        store.upsert_tunnel(&updated).unwrap();
        let tunnels = store.load_tunnels();
        assert_eq!(tunnels[0].name, "改过名");
        assert_eq!(tunnels[0].remote_port, Some(30001));

        store.remove_tunnel(&first).unwrap();
        assert_eq!(store.load_tunnels().len(), 1);
    }

    #[test]
    fn token_book_round_trip_and_clear() {
        let (_dir, store) = temp_store();
        assert!(store.token(Provider::SakuraFrp).is_none());

        let account = Account {
            username: "steve".into(),
            group: "VIP".into(),
            frp_token: Some("frp-secret".into()),
            ..Default::default()
        };
        store
            .save_token(Provider::SakuraFrp, "token-1", &account)
            .unwrap();
        assert_eq!(store.token(Provider::SakuraFrp).as_deref(), Some("token-1"));
        assert_eq!(
            store
                .account(Provider::SakuraFrp)
                .unwrap()
                .frp_token
                .as_deref(),
            Some("frp-secret")
        );

        // 只换令牌，账号缓存不动
        store.update_token(Provider::SakuraFrp, "token-2").unwrap();
        assert_eq!(store.token(Provider::SakuraFrp).as_deref(), Some("token-2"));
        assert_eq!(
            store.account(Provider::SakuraFrp).unwrap().username,
            "steve"
        );

        store.clear_token(Provider::SakuraFrp).unwrap();
        assert!(store.token(Provider::SakuraFrp).is_none());
        assert!(store.account(Provider::SakuraFrp).is_none());
    }

    #[cfg(unix)]
    #[test]
    fn token_file_is_private() {
        use std::os::unix::fs::PermissionsExt as _;

        let (_dir, store) = temp_store();
        store
            .save_token(Provider::MeFrp, "token", &Account::default())
            .unwrap();
        let mode = std::fs::metadata(store.root().join("auth.json"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, TOKEN_FILE_MODE, "auth.json 必须是 0600");
    }

    #[test]
    fn bad_ids_cannot_escape_the_directory() {
        let (_dir, store) = temp_store();
        assert!(store.toml_path("../evil").is_err());
        assert!(store.toml_path("").is_err());
        assert!(store.toml_path("a/b").is_err());
        assert!(store.remove_tunnel("..").is_err());
        assert!(FrpStore::is_valid_local_id("0123456789abcdef"));
        assert!(!FrpStore::is_valid_local_id("0123456789ABCDEFG"));
    }

    #[test]
    fn toml_round_trip() {
        let (_dir, store) = temp_store();
        let id = store.new_local_id();
        assert!(!store.toml_exists(&id));
        store.write_toml(&id, "serverAddr = \"x\"\n").unwrap();
        assert!(store.toml_exists(&id));
        assert_eq!(store.read_toml(&id).unwrap(), "serverAddr = \"x\"\n");
        store.remove_tunnel(&id).unwrap();
        assert!(!store.toml_exists(&id));
    }

    #[test]
    fn broken_metadata_is_skipped_not_fatal() {
        let (_dir, store) = temp_store();
        let id = store.new_local_id();
        store.upsert_tunnel(&sample_tunnel(&id, "好的")).unwrap();
        std::fs::write(store.meta_dir().join("broken.json"), "{ 不是 JSON").unwrap();
        std::fs::write(store.meta_dir().join("notes.txt"), "无关文件").unwrap();

        let tunnels = store.load_tunnels();
        assert_eq!(tunnels.len(), 1);
        assert_eq!(tunnels[0].name, "好的");
    }
}
