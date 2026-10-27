//! 环境的落盘布局与读写。
//!
//! ```text
//! <data_dir>/
//! ├── config/
//! │   └── runtimes/<id>.json     每个环境的元数据（含「正在装」「装失败」）
//! └── runtimes/
//!     ├── <id>/                 解压出来的 JDK
//!     └── .staging/<id>/        下载中的压缩包（装完就删）
//! ```
//!
//! 与实例同一套数据根（`[modules.config.instance] dir`，见
//! [`instance::resolve_data_dir`](crate::module::builtin::instance::resolve_data_dir)），
//! 所以「EdgeCube 的东西放哪」只有一个答案。
//!
//! **没有索引文件**（实例那边有 `instances.json`）：环境数量是个位数，扫一遍
//! `config/runtimes/` 就够了。少一份需要与元数据对齐的状态，就少一类
//! 「索引说有、文件却不在」的问题 —— 而这里的元数据本来就写得很少。

use std::fs;
use std::path::{Path, PathBuf};

use super::model::Env;
use crate::util::fetch::validate_token;

/// 元数据子目录：`<data_dir>/config/runtimes/`。
pub const CONFIG_SUB_DIR: &str = "runtimes";
/// 环境目录：`<data_dir>/runtimes/`。
pub const DATA_SUB_DIR: &str = "runtimes";
/// 下载暂存的子目录名（在环境目录下）。
pub const STAGING_SUB_DIR: &str = ".staging";

/// 环境 id 的合法性。
///
/// 这个 id **同时是文件名和目录名**，所以是安全边界：白名单字符集之外还额外禁掉
/// 以 `.` 开头 —— `.staging` 是我们的保留名，而 `..` 这种也能被一并挡住。
pub fn validate_id(id: &str) -> Result<(), String> {
    validate_token(id, "id")?;
    if id.starts_with('.') {
        return Err(format!("`id` 不能以 `.` 开头：`{id}`"));
    }
    Ok(())
}

/// `<data_dir>/config/runtimes`。
pub fn meta_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("config").join(CONFIG_SUB_DIR)
}

/// `<data_dir>/runtimes/<id>`。
pub fn env_dir(data_dir: &Path, id: &str) -> PathBuf {
    data_dir.join(DATA_SUB_DIR).join(id)
}

/// `<data_dir>/runtimes/.staging/<id>` —— 下载中的压缩包放这儿。
///
/// 与环境目录分开是有意的：环境目录里只该有「干净的、装好的一份」，
/// 装到一半的 200 MB 包混在里面，`find_java` 会把它当成解压结果的一部分。
pub fn staging_dir(data_dir: &Path, id: &str) -> PathBuf {
    data_dir.join(DATA_SUB_DIR).join(STAGING_SUB_DIR).join(id)
}

/// 建好 `config/runtimes/`、`runtimes/`、`runtimes/.staging/`。
pub fn ensure_dirs(data_dir: &Path) -> std::io::Result<()> {
    fs::create_dir_all(meta_dir(data_dir))?;
    fs::create_dir_all(data_dir.join(DATA_SUB_DIR).join(STAGING_SUB_DIR))
}

fn meta_path(data_dir: &Path, id: &str) -> Result<PathBuf, String> {
    validate_id(id)?;
    Ok(meta_dir(data_dir).join(format!("{id}.json")))
}

/// 读一个环境；没有 / 坏了 / id 不合法都给 `None`。
pub fn load(data_dir: &Path, id: &str) -> Option<Env> {
    let path = meta_path(data_dir, id).ok()?;
    let text = fs::read_to_string(&path).ok()?;
    match serde_json::from_str::<Env>(&text) {
        Ok(env) => Some(env),
        Err(e) => {
            tracing::warn!(path = %path.display(), error = %e, "环境元数据解析失败，按不存在处理");
            None
        }
    }
}

/// 全部环境，按创建时间倒序（新的在前；同一毫秒按 id 兜底，保证顺序稳定）。
pub fn load_all(data_dir: &Path) -> Vec<Env> {
    let Ok(entries) = fs::read_dir(meta_dir(data_dir)) else {
        return Vec::new();
    };
    let mut envs: Vec<Env> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .filter_map(|path| {
            let text = fs::read_to_string(&path).ok()?;
            match serde_json::from_str::<Env>(&text) {
                Ok(env) => Some(env),
                Err(e) => {
                    tracing::warn!(path = %path.display(), error = %e, "跳过读不懂的环境元数据");
                    None
                }
            }
        })
        .collect();

    envs.sort_by(|a, b| {
        b.created_at_ms
            .cmp(&a.created_at_ms)
            .then_with(|| a.id.cmp(&b.id))
    });
    envs
}

/// 写一个环境（原子写：先写 `.tmp` 再改名）。
pub fn save(data_dir: &Path, env: &Env) -> Result<(), String> {
    let path = meta_path(data_dir, &env.id)?;
    let body = serde_json::to_string_pretty(env).map_err(|e| format!("序列化失败：{e}"))?;

    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, body.as_bytes()).map_err(|e| format!("写 `{}` 失败：{e}", tmp.display()))?;
    fs::rename(&tmp, &path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("落盘 `{}` 失败：{e}", path.display())
    })
}

/// 删掉一个环境的元数据文件。返回「原来在不在」。
pub fn remove(data_dir: &Path, id: &str) -> Result<bool, String> {
    let path = meta_path(data_dir, id)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(format!("删 `{}` 失败：{e}", path.display())),
    }
}

/// 删掉一个目录树（不存在也算成功）。
pub fn remove_dir(path: &Path) -> Result<(), String> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("删 `{}` 失败：{e}", path.display())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::builtin::runtime::model::{Env, EnvState};

    /// 一个用完就删的临时目录。
    struct TempDir(PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "edgecube-runtime-store-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn env(id: &str, created_at_ms: u64) -> Env {
        Env {
            id: id.into(),
            vendor: "zulu".into(),
            package_type: "jdk".into(),
            version: "21".into(),
            version_name: "21.0.12.1".into(),
            vendor_version: "21.52.203".into(),
            os: "linux".into(),
            arch: "x64".into(),
            archive_type: "tar.gz".into(),
            package_uuid: "uuid".into(),
            file_name: "zulu.tar.gz".into(),
            url: "https://cdn.azul.com/zulu/bin/zulu.tar.gz".into(),
            sha256: Some("a".repeat(64)),
            md5: None,
            size: Some(1),
            support_term: Some("lts".into()),
            build_date: None,
            state: EnvState::Installed,
            stage: None,
            error: None,
            task_id: None,
            home: Some("zulu-21".into()),
            binary: Some("zulu-21/bin/java".into()),
            created_at_ms,
            installed_at_ms: Some(created_at_ms + 1),
            updated_at_ms: created_at_ms + 1,
        }
    }

    #[test]
    fn save_load_roundtrip() {
        let temp = TempDir::new("roundtrip");
        ensure_dirs(&temp.0).unwrap();
        let one = env("zulu-jdk-21-linux-x64", 1_700_000_000_000);
        save(&temp.0, &one).unwrap();

        let back = load(&temp.0, "zulu-jdk-21-linux-x64").expect("应当读得回来");
        assert_eq!(back.id, one.id);
        assert_eq!(back.version_name, "21.0.12.1");
        assert_eq!(back.state, EnvState::Installed);
        assert_eq!(back.binary.as_deref(), Some("zulu-21/bin/java"));

        // 写的时候别留 `.tmp` 残渣
        assert!(
            !meta_dir(&temp.0)
                .join("zulu-jdk-21-linux-x64.json.tmp")
                .exists()
        );
    }

    #[test]
    fn load_all_sorts_newest_first_and_skips_garbage() {
        let temp = TempDir::new("list");
        ensure_dirs(&temp.0).unwrap();
        save(&temp.0, &env("zulu-jdk-17-linux-x64", 1_000)).unwrap();
        save(&temp.0, &env("zulu-jdk-21-linux-x64", 2_000)).unwrap();
        // 坏文件不该把整份列表拖下水
        fs::write(meta_dir(&temp.0).join("broken.json"), b"{ not json").unwrap();
        fs::write(meta_dir(&temp.0).join("README.txt"), b"ignore me").unwrap();

        let ids: Vec<String> = load_all(&temp.0).into_iter().map(|e| e.id).collect();
        assert_eq!(ids, vec!["zulu-jdk-21-linux-x64", "zulu-jdk-17-linux-x64"]);
    }

    #[test]
    fn load_all_on_a_missing_directory_is_empty() {
        let temp = TempDir::new("missing");
        assert!(load_all(&temp.0.join("nope")).is_empty());
    }

    #[test]
    fn id_must_be_a_single_safe_segment() {
        assert!(validate_id("zulu-jdk-21-linux-x64").is_ok());
        for bad in ["", "../escape", "a/b", "a\\b", ".staging", ".", "..", "a b"] {
            assert!(validate_id(bad).is_err(), "`{bad}` 应当被拒");
        }
    }

    #[test]
    fn reading_a_traversal_id_is_refused() {
        let temp = TempDir::new("traversal");
        ensure_dirs(&temp.0).unwrap();
        // 就算外面真有一个同名文件，也不该被读到
        fs::write(temp.0.join("secret.json"), b"{}").unwrap();
        assert!(load(&temp.0, "../secret").is_none());
        assert!(save(&temp.0, &env("../secret", 1)).is_err());
        assert!(remove(&temp.0, "../secret").is_err());
    }

    #[test]
    fn remove_reports_whether_the_file_was_there() {
        let temp = TempDir::new("remove");
        ensure_dirs(&temp.0).unwrap();
        save(&temp.0, &env("zulu-jdk-21-linux-x64", 1)).unwrap();
        assert!(remove(&temp.0, "zulu-jdk-21-linux-x64").unwrap());
        assert!(!remove(&temp.0, "zulu-jdk-21-linux-x64").unwrap());
    }

    #[test]
    fn remove_dir_is_idempotent() {
        let temp = TempDir::new("rmdir");
        let dir = env_dir(&temp.0, "zulu-jdk-21-linux-x64");
        fs::create_dir_all(dir.join("bin")).unwrap();
        remove_dir(&dir).unwrap();
        assert!(!dir.exists());
        remove_dir(&dir).unwrap();
    }
}
