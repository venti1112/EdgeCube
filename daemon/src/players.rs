//! 玩家管理(契约 players):四类名单(白名单/OP/封禁/IP 封禁)读取 + 在线玩家
//! 事件解析。纯函数/数据模型库,无全局管理器;在线玩家集合挂在
//! `proc::ProcManager.online_players`,由 stdout 泵逐行调用 [record_player_event]
//! 维护,进程结束时清空。
//!
//! 名单文件格式(对齐 V1 `players_page.dart`):
//! - Java:  whitelist.json / ops.json / banned-players.json / banned-ips.json
//! - PNX:   white-list.txt / ops.txt / banned-players.json(字段 expireDate/creationDate)
//! - PMMP:  white-list.txt / ops.txt / banned-players.txt / banned-ips.txt

use std::collections::HashSet;
use std::path::Path;
use std::sync::OnceLock;

use regex::Regex;
use serde::Serialize;

use crate::instance::InstanceStatus;
use crate::instance::InstanceType;

/// ANSI 转义序列(pty 已把 Minecraft § 色码转 ANSI;解析玩家事件前必须先剥离,
/// 否则玩家名前的色码会破坏 join/leave/list 匹配)。
fn ansi_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\x1b\[[0-9;?]*[A-Za-z]").expect("valid ansi regex"))
}

fn join_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(\w{1,16})(?:\[/[\d.:]+\] logged in| 加入了游戏|\[/[\d.:]+\] 登入游戏)")
            .expect("valid join regex")
    })
}

fn leave_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(\w{1,16})(?: left the game| 退出了游戏|\[/[\d.:]+\] 登出游戏)")
            .expect("valid leave regex")
    })
}

fn list_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?:online|在线)[：:]\s*(.*)").expect("valid list regex"))
}

/// stdout 泵快速预过滤:仅当行可能含玩家事件(join/leave/list)才进
/// [record_player_event] 加锁解析,避免海量日志行的无谓开销。
pub fn line_may_contain_player_event(line: &str) -> bool {
    line.contains("logged in")
        || line.contains("left the game")
        || line.contains("加入")
        || line.contains("退出")
        || line.contains("登入")
        || line.contains("登出")
        || line.contains("online")
        || line.contains("在线")
}

/// 剥离一行中的 ANSI 转义序列。
pub fn strip_ansi(line: &str) -> String {
    ansi_re().replace_all(line, "").to_string()
}

/// 解析一行控制台输出,更新在线玩家集合(join/leave/list 三事件,正则逐字
/// 移植 V1 `server_controller.dart::_parsePlayerEvent`)。
pub fn record_player_event(online: &mut HashSet<String>, raw_line: &str) {
    let line = strip_ansi(raw_line);

    // 玩家加入:Steve[/127.0.0.1:12345] logged in / 加入游戏 / 登入游戏
    if let Some(caps) = join_re().captures(&line) {
        if let Some(name) = caps.get(1) {
            online.insert(name.as_str().to_string());
        }
        return;
    }

    // 玩家离开:left the game / 退出了游戏 / 登出游戏
    if let Some(caps) = leave_re().captures(&line) {
        if let Some(name) = caps.get(1) {
            online.remove(name.as_str());
        }
        return;
    }

    // list 命令响应:There are X of Y players online: a, b, c / 目前有 X/Y 个玩家在线:a, b, c
    if let Some(caps) = list_re().captures(&line) {
        let names = caps.get(1).map_or("", |m| m.as_str()).trim();
        online.clear();
        if !names.is_empty() {
            for name in names.split(',').map(|s| s.trim()) {
                if !name.is_empty() {
                    online.insert(name.to_string());
                }
            }
        }
    }
}

// ────────────────────────── 模型(契约 players) ──────────────────────────

/// 名单条目(白名单/OP;文本名单无 uuid)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerNamedEntry {
    pub name: String,
    #[serde(default)]
    pub uuid: String,
}

/// 封禁条目(Java banned-players.json 全字段;PNX 兼容 expireDate/creationDate;
/// PMMP banned-players.txt 仅名字)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerBanEntry {
    pub name: String,
    #[serde(default)]
    pub uuid: String,
    #[serde(default)]
    pub reason: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub expires: String,
    #[serde(default)]
    pub created: String,
}

/// IP 封禁条目(Java banned-ips.json 全字段;banned-ips.txt 仅 IP)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerIpBanEntry {
    pub ip: String,
    #[serde(default)]
    pub reason: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub expires: String,
    #[serde(default)]
    pub created: String,
}

/// 玩家管理聚合快照(契约 PlayerSnapshot)。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerSnapshot {
    pub instance_status: InstanceStatus,
    #[serde(default)]
    pub online: Vec<String>,
    #[serde(default)]
    pub whitelist: Vec<PlayerNamedEntry>,
    #[serde(default)]
    pub ops: Vec<PlayerNamedEntry>,
    #[serde(default)]
    pub bans: Vec<PlayerBanEntry>,
    #[serde(default)]
    pub ban_ips: Vec<PlayerIpBanEntry>,
}

/// 四类名单读取结果。
pub struct PlayerFiles {
    pub whitelist: Vec<PlayerNamedEntry>,
    pub ops: Vec<PlayerNamedEntry>,
    pub bans: Vec<PlayerBanEntry>,
    pub ban_ips: Vec<PlayerIpBanEntry>,
}

// ────────────────────────── 名单文件读取 ──────────────────────────

/// 读取实例 cwd 下的四类名单(JSON 优先,txt 回退),文件缺失/解析失败一律
/// 返回空列表(对齐 V1 的宽容行为)。
pub async fn snapshot_files(cwd: &Path, instance_type: InstanceType) -> PlayerFiles {
    let pocketmine = instance_type == InstanceType::Pocketmine;
    PlayerFiles {
        whitelist: load_named(cwd, "whitelist.json", "white-list.txt").await,
        ops: load_named(cwd, "ops.json", "ops.txt").await,
        bans: load_bans(cwd, pocketmine).await,
        ban_ips: load_ban_ips(cwd).await,
    }
}

/// 名称条目名单:JSON `[{uuid,name,...}]` 优先,txt 逐行回退。
async fn load_named(cwd: &Path, json_file: &str, txt_file: &str) -> Vec<PlayerNamedEntry> {
    let json_path = cwd.join(json_file);
    if let Some(text) = read_if_exists(&json_path).await {
        if let Ok(list) = serde_json::from_str::<serde_json::Value>(&text) {
            if let Some(items) = list.as_array() {
                let entries: Vec<PlayerNamedEntry> = items
                    .iter()
                    .map(|e| PlayerNamedEntry {
                        name: str_field(e, "name"),
                        uuid: str_field(e, "uuid"),
                    })
                    .collect();
                if !entries.is_empty() {
                    return entries;
                }
            }
        }
    }
    load_txt(cwd, txt_file)
        .await
        .into_iter()
        .map(|name| PlayerNamedEntry {
            name,
            uuid: String::new(),
        })
        .collect()
}

/// 封禁名单:PMMP 的 banned-players.txt 每行一个名字(无元数据)。
async fn load_bans(cwd: &Path, pocketmine: bool) -> Vec<PlayerBanEntry> {
    let json_path = cwd.join("banned-players.json");
    if let Some(text) = read_if_exists(&json_path).await {
        if let Ok(list) = serde_json::from_str::<serde_json::Value>(&text) {
            if let Some(items) = list.as_array() {
                let entries: Vec<PlayerBanEntry> = items.iter().map(map_ban_entry).collect();
                if !entries.is_empty() {
                    return entries;
                }
            }
        }
    }
    if pocketmine {
        // PMMP banned-players.txt:每行 `name|reason|source|expires|created`
        load_banned_txt(cwd, "banned-players.txt")
            .await
            .into_iter()
            .map(|fields| PlayerBanEntry {
                name: fields.get(0).cloned().unwrap_or_default(),
                uuid: String::new(),
                reason: fields.get(1).cloned().unwrap_or_default(),
                source: fields.get(2).cloned().unwrap_or_default(),
                expires: fields.get(3).cloned().unwrap_or_default(),
                created: fields.get(4).cloned().unwrap_or_default(),
            })
            .collect()
    } else {
        Vec::new()
    }
}

/// IP 封禁名单:banned-ips.json 优先,banned-ips.txt 逐行回退。
async fn load_ban_ips(cwd: &Path) -> Vec<PlayerIpBanEntry> {
    let json_path = cwd.join("banned-ips.json");
    if let Some(text) = read_if_exists(&json_path).await {
        if let Ok(list) = serde_json::from_str::<serde_json::Value>(&text) {
            if let Some(items) = list.as_array() {
                let entries: Vec<PlayerIpBanEntry> = items
                    .iter()
                    .map(|e| PlayerIpBanEntry {
                        ip: str_field(e, "ip"),
                        reason: str_field(e, "reason"),
                        source: str_field(e, "source"),
                        // Java 用 expires,PNX 用 expireDate
                        expires: field_or(e, "expires", "expireDate"),
                        // Java 用 created,PNX 用 creationDate
                        created: field_or(e, "created", "creationDate"),
                    })
                    .collect();
                if !entries.is_empty() {
                    return entries;
                }
            }
        }
    }
    load_txt(cwd, "banned-ips.txt")
        .await
        .into_iter()
        .map(|ip| PlayerIpBanEntry {
            ip,
            reason: String::new(),
            source: String::new(),
            expires: String::new(),
            created: String::new(),
        })
        .collect()
}

fn map_ban_entry(e: &serde_json::Value) -> PlayerBanEntry {
    PlayerBanEntry {
        name: str_field(e, "name"),
        uuid: str_field(e, "uuid"),
        reason: str_field(e, "reason"),
        source: str_field(e, "source"),
        // Java 用 expires,PNX 用 expireDate
        expires: field_or(e, "expires", "expireDate"),
        // Java 用 created,PNX 用 creationDate
        created: field_or(e, "created", "creationDate"),
    }
}

fn str_field(e: &serde_json::Value, key: &str) -> String {
    e.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string()
}

fn field_or(e: &serde_json::Value, key: &str, fallback: &str) -> String {
    let v = str_field(e, key);
    if v.is_empty() { str_field(e, fallback) } else { v }
}

/// 逐行读文本名单(去空行/trim),失败返回空列表。
async fn load_txt(cwd: &Path, file_name: &str) -> Vec<String> {
    let Some(text) = read_if_exists(&cwd.join(file_name)).await else {
        return Vec::new();
    };
    text.lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

/// PMMP banned-players.txt:按 `|` 拆字段。
async fn load_banned_txt(cwd: &Path, file_name: &str) -> Vec<Vec<String>> {
    let Some(text) = read_if_exists(&cwd.join(file_name)).await else {
        return Vec::new();
    };
    text.lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .map(|l| l.split('|').map(|f| f.trim().to_string()).collect())
        .collect()
}

/// 文件存在且读取成功时返回内容(不存在/读失败 → None,调用方回退)。
async fn read_if_exists(path: &Path) -> Option<String> {
    if !path.exists() {
        return None;
    }
    tokio::fs::read_to_string(path).await.ok()
}