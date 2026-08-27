//! 账户与设备凭证:首次启动生成随机初始账户(openapi /auth/login:
//! "daemon 首次启动时生成随机凭证并打印到控制台");密码只存 argon2 哈希;
//! 登录 token 按设备持久化,可吊销。
//!
//! 另含本机免密登录(openapi /auth/local-login):凭据为数据目录 `local.key`,
//! 一次性 challenge + HMAC-SHA256 签名,持有该文件的进程(本机)才可通过,
//! 与来源 IP 无关(TCP 端口映射仅转发流量、读不到文件)。

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use chrono::Utc;
use hmac::{Hmac, Mac};
use rand::Rng;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use uuid::Uuid;

use crate::error::Result;

type HmacSha256 = Hmac<Sha256>;

/// 本机免密 challenge 有效期(秒)。
const LOCAL_CHALLENGE_TTL_SECS: i64 = 300;

/// 账户记录(仅存哈希,不存明文)。
#[derive(Debug, Serialize, Deserialize)]
pub struct Account {
    pub username: String,
    pub password_hash: String,
    pub created_at: String,
}

/// 已登录设备(openapi DeviceInfo 对应)。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub token: String,
    pub created_at: String,
    pub last_seen_at: Option<String>,
}

/// 首次创建初始账户时返回的明文凭证(仅用于控制台打印,不持久化)。
pub struct CreatedAccount {
    pub username: String,
    pub password: String,
}

/// 本机免密挑战(openapi LocalLoginChallenge)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalChallenge {
    pub challenge: String,
    pub expires_at: String,
}

/// 账户 + 设备凭证 + 本机免密状态,由数据目录下的 JSON 文件持久化。
pub struct AuthStore {
    account_path: PathBuf,
    devices_path: PathBuf,
    account: Option<Account>,
    devices: Vec<Device>,
    /// local.key 内容(本机免密秘密,仅存内存)。
    local_key: Vec<u8>,
    /// 一次性 challenge -> 过期时间戳(unix 秒),重启后清空。
    challenges: HashMap<String, i64>,
}

impl AuthStore {
    pub fn new(dir: &Path) -> Result<Self> {
        let local_key = load_or_create_local_key(&dir.join("local.key"))?;
        Ok(Self {
            account_path: dir.join("account.json"),
            devices_path: dir.join("devices.json"),
            account: None,
            devices: Vec::new(),
            local_key,
            challenges: HashMap::new(),
        })
    }

    /// 载入或创建初始账户。
    /// 账户文件不存在时生成随机凭证并持久化,明文仅通过返回值交给调用方打印。
    pub fn ensure_account(&mut self) -> Result<Option<CreatedAccount>> {
        if self.account_path.exists() {
            let raw = fs::read_to_string(&self.account_path)?;
            self.account = Some(serde_json::from_str(&raw)?);
            tracing::info!("account loaded");
            return Ok(None);
        }

        let username = random_username();
        let password = random_password();
        let hash = hash_password(&password)?;
        let account = Account {
            username: username.clone(),
            password_hash: hash,
            created_at: Utc::now().to_rfc3339(),
        };
        fs::write(&self.account_path, serde_json::to_string_pretty(&account)?)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&self.account_path, fs::Permissions::from_mode(0o600));
        }

        self.account = Some(account);
        tracing::info!("no account found, initial account created");
        Ok(Some(CreatedAccount { username, password }))
    }

    /// 载入设备列表(不存在视为空)。
    pub fn load_devices(&mut self) {
        let raw = match fs::read_to_string(&self.devices_path) {
            Ok(raw) => raw,
            Err(_) => return,
        };
        match serde_json::from_str(&raw) {
            Ok(devices) => self.devices = devices,
            Err(e) => tracing::warn!(path = %self.devices_path.display(), "devices file corrupted, ignored: {e}"),
        }
    }

    /// 校验用户名密码。密码哈希校验较重,调用方应在阻塞线程执行。
    pub fn verify(&self, username: &str, password: &str) -> bool {
        let Some(account) = &self.account else {
            return false;
        };
        if account.username != username {
            return false;
        }
        let Ok(parsed) = PasswordHash::new(&account.password_hash) else {
            return false;
        };
        Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok()
    }

    /// 签发一次性本机免密 challenge(5 分钟有效,重启即失效)。
    pub fn issue_local_challenge(&mut self) -> LocalChallenge {
        let now = Utc::now();
        // 惰性清理过期项
        let now_ts = now.timestamp();
        self.challenges.retain(|_, exp| *exp > now_ts);

        let challenge = random_hex(16);
        self.challenges.insert(challenge.clone(), now_ts + LOCAL_CHALLENGE_TTL_SECS);
        let expires_at = chrono::DateTime::from_timestamp(now_ts + LOCAL_CHALLENGE_TTL_SECS as i64, 0)
            .expect("valid expiry timestamp")
            .to_rfc3339();
        tracing::debug!("local login challenge issued");
        LocalChallenge { challenge, expires_at }
    }

    /// 校验本机免密签名:challenge 存在且未过期则一次性作废。
    /// 通过即代表调用方持有 local.key(本机进程),与来源 IP 无关。
    pub fn verify_local_login(&mut self, challenge: &str, signature: &str) -> bool {
        let Some(expires_at) = self.challenges.remove(challenge) else {
            return false;
        };
        if Utc::now().timestamp() > expires_at {
            return false;
        }
        let Some(provided) = hex_decode(signature) else {
            return false;
        };
        let mut mac = HmacSha256::new_from_slice(&self.local_key).expect("HMAC accepts any key length");
        mac.update(challenge.as_bytes());
        mac.verify_slice(&provided).is_ok()
    }

    /// 为设备签发 token(持久化),返回设备信息。
    pub fn issue_token(&mut self, device_name: Option<&str>) -> Result<Device> {
        let device = Device {
            id: Uuid::new_v4().to_string(),
            name: device_name
                .filter(|n| !n.trim().is_empty())
                .map(|n| n.trim().to_string())
                .unwrap_or_else(|| "unknown".into()),
            token: random_token(),
            created_at: Utc::now().to_rfc3339(),
            last_seen_at: Some(Utc::now().to_rfc3339()),
        };
        self.devices.push(device.clone());
        self.persist_devices()?;
        Ok(device)
    }

    fn persist_devices(&self) -> Result<()> {
        fs::write(&self.devices_path, serde_json::to_string_pretty(&self.devices)?)?;
        Ok(())
    }
}

/// argon2 密码哈希。
fn hash_password(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    Ok(Argon2::default()
        .hash_password(password.as_bytes(), &salt)?
        .to_string())
}

/// 随机初始用户名(6 位小写字母数字,去除易混淆字符)。
fn random_username() -> String {
    const ALPHABET: &[u8] = b"abcdefghjkmnpqrstuvwxyz23456789";
    let mut rng = rand::rngs::OsRng;
    (0..6).map(|_| ALPHABET[rng.gen_range(0..ALPHABET.len())] as char).collect()
}

/// 随机初始密码(16 位,满足 LoginRequest.password minLength 8)。
fn random_password() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%^&*-_";
    let mut rng = rand::rngs::OsRng;
    (0..16).map(|_| ALPHABET[rng.gen_range(0..ALPHABET.len())] as char).collect()
}

/// 设备 token:32 字节随机数十六进制。
fn random_token() -> String {
    random_hex(32)
}

/// 生成 n 字节强随机数的十六进制小写字符串。
fn random_hex(bytes: usize) -> String {
    let mut rng = rand::rngs::OsRng;
    (0..bytes).map(|_| format!("{:02x}", rng.r#gen::<u8>())).collect()
}

fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    if hex.len() % 2 != 0 {
        return None;
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect()
}

/// 加载或创建本机免密秘密 `local.key`(32 字节随机数 hex,权限 0600)。
/// 免密凭据即此文件:仅持有它的进程(本机 App)可完成 local-login。
fn load_or_create_local_key(path: &Path) -> Result<Vec<u8>> {
    if path.exists() {
        let raw = fs::read_to_string(path)?;
        return Ok(raw.trim().as_bytes().to_vec());
    }
    let key = random_hex(32);
    fs::write(path, &key)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }

    tracing::info!(path = %path.display(), "local key created");
    Ok(key.into_bytes())
}