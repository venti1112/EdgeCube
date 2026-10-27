//! 玩家名单：在线玩家的输出解析 + 四份名单文件（白名单 / OP / 封禁 / IP 封禁）。
//!
//! # 为什么由 daemon 解析
//!
//! 服务端**没有**「现在谁在线」这种接口，只能从它的输出里认人。进程归 daemon 管，只有它拿得到**从头到尾、一条不漏**的
//! 输出流；控制台历史是有上限的一段，前端拿它解析必然在断线/错过一帧时漏事件。
//! 所以解析在输出线程里**边读边做**（[`OnlinePlayers`]），前端只读结果。
//!
//! # 解析规则
//!
//! 三条正则与判定顺序（加入 → 退出 → `list` 响应）见 [`OnlinePlayers`]；
//! 四份名单文件的读取与回退见 [`ListSpec`] / [`PlayerList`]。
//! 几处已知的怪癖也原样保留，见 [`OnlinePlayers`]。

use std::path::Path;
use std::sync::LazyLock;

use regex::Regex;
use serde_json::{Map, Value, json};

// ---------------------------------------------------------------------------
// 在线玩家
// ---------------------------------------------------------------------------

/// 加入：`Name[/ip] logged in`、`Name 加入了游戏`、`[/ip] 登入游戏`。
///
/// `(?-u:\w)` 是**故意的**：Dart 的 `\w` 只认 ASCII，Rust 的默认认 Unicode，
/// 不关掉的话中文名会被切出不一样的结果。
static RE_JOIN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"((?-u:\w){1,16})(?:\[/[\d.:]+\] logged in| 加入了游戏|[/\d.:]+\] 登入游戏)")
        .expect("在线玩家正则（加入）应当合法")
});

/// 退出：`Name left the game`、`Name 退出了游戏`、`[/ip] 登出游戏`。
static RE_LEAVE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"((?-u:\w){1,16})(?: left the game| 退出了游戏|[/\d.:]+\] 登出游戏)")
        .expect("在线玩家正则（退出）应当合法")
});

/// `list` 命令的响应（英文 `… players online: a, b` / 中文 `… 个玩家在线：a, b`）。
static RE_LIST: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?:online|在线)[：:]\s*(.*)").expect("在线玩家正则（list）应当合法")
});

/// 还没等到换行的尾巴最多留这么多字节。
///
/// 正常一行不会这么长；万一进程吐出一条没有换行的长输出（比如无限打进度条），
/// 也不能让这个缓冲无限涨下去 —— 只留尾部就够，匹配的都是行内短结构。
const MAX_PENDING_BYTES: usize = 8 * 1024;

/// 在线玩家集合：喂输出、认人。
///
/// 解析规则有两处已知的怪癖：
///
/// * 原版服务端的 `Steve joined the game` **认不出来** —— 只认
///   `[/ip] logged in`（Bukkit 系）和两句中文；
/// * `[/\d.:]+\] 登入游戏` 里的 `[` 是**没转义**的字符类，引擎会从 `[` 后面
///   才开始匹配这一支，于是前导的 `(\w{1,16})` 抓到的是 IP 的尾数
///   （`Steve[/10.0.0.5:1234] 登入游戏` → `10`）。线上就是这个结果，原样保留。
pub struct OnlinePlayers {
    /// 插入序的集合（Dart 的 `Set` 也是插入序）。
    names: Vec<String>,
    /// 按块到达的输出里还没凑满一行的尾巴。
    pending: Vec<u8>,
    /// 当前这一行因为太长被丢掉了，等到下一个换行才算新行。
    truncated: bool,
}

impl Default for OnlinePlayers {
    fn default() -> Self {
        Self::new()
    }
}

impl OnlinePlayers {
    pub fn new() -> Self {
        Self {
            names: Vec::new(),
            pending: Vec::new(),
            truncated: false,
        }
    }

    /// 当前名单（插入序）。
    pub fn names(&self) -> &[String] {
        &self.names
    }

    /// 清空（进程退出时用）。
    /// 返回之前是否有内容。
    pub fn clear(&mut self) -> bool {
        let had = !self.names.is_empty() || !self.pending.is_empty();
        self.names.clear();
        self.pending.clear();
        had
    }

    /// 喂一块原始输出（PTY 读多少喂多少），返回集合是否因此变了。
    ///
    /// **只按完整行解析**：没等到 `\n` 的尾巴留在缓冲里。一行分几块到达时，
    /// 切在半个多字节字符（中文名）上也不会解出乱码。
    pub fn feed(&mut self, chunk: &[u8]) -> bool {
        self.pending.extend_from_slice(chunk);

        let mut changed = false;
        while let Some(pos) = self.pending.iter().position(|b| *b == b'\n') {
            let mut line: Vec<u8> = self.pending.drain(..=pos).collect();
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            // 被丢掉的那半行到此为止，后面的内容不再拼进来解析
            if self.truncated {
                self.truncated = false;
                continue;
            }
            changed |= self.apply_line(&String::from_utf8_lossy(&line));
        }

        // 一行迟迟不换行：整段丢掉，别让缓冲无限涨。截断的半行本来就不是一行，
        // 攒不出名字 —— 连它后面拼上的内容一起skip，等下个换行再恢复。
        if self.pending.len() > MAX_PENDING_BYTES {
            self.pending.clear();
            self.truncated = true;
        }
        changed
    }

    /// 喂一行（不含换行），返回集合是否因此变了。
    ///
    /// 判定顺序：先看加入、再看退出、最后看 `list` 的响应。
    pub fn apply_line(&mut self, line: &str) -> bool {
        if let Some(caps) = RE_JOIN.captures(line) {
            let name = caps[1].to_string();
            if self.names.contains(&name) {
                return false;
            }
            self.names.push(name);
            return true;
        }
        if let Some(caps) = RE_LEAVE.captures(line) {
            let name = &caps[1];
            let before = self.names.len();
            self.names.retain(|n| n != name);
            return self.names.len() != before;
        }
        if let Some(caps) = RE_LIST.captures(line) {
            return self.replace(caps[1].trim());
        }
        false
    }

    /// `list` 的响应：整份替换（空响应 = 没人）。
    fn replace(&mut self, names: &str) -> bool {
        let next: Vec<String> = if names.is_empty() {
            Vec::new()
        } else {
            names
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .collect()
        };
        if same_names(&next, &self.names) {
            return false;
        }
        self.names = next;
        true
    }
}

/// 两份名单是不是同一批人（不看顺序）。
fn same_names(a: &[String], b: &[String]) -> bool {
    a.len() == b.len() && a.iter().all(|name| b.contains(name))
}

// ---------------------------------------------------------------------------
// 名单文件
// ---------------------------------------------------------------------------

/// 名单文件的读取规则。
///
/// 同一个文件按两套规则各读一遍，原样保留成 [`PlayerList`] 的两个视图，
/// **别合并**：合并了就必然有一边不符合另一套的口径。
pub struct ListSpec {
    /// Java 版写的 JSON 名单。
    pub json_file: &'static str,
    /// PNX / PMMP 写的纯文本名单。
    pub txt_file: &'static str,
    /// 条目字段：线上格式的字段名，以及它可能出现的旧名字（PNX 别名）。
    pub fields: &'static [FieldSpec],
    /// 打标签用的小写名字取自哪个字段；`None` = 这份名单不参与打标签。
    pub name_field: Option<&'static str>,
}

/// 一个字段在线上格式里的名字。
pub struct FieldSpec {
    pub name: &'static str,
    /// 旧名字（按顺序试）。
    pub aliases: &'static [&'static str],
}

const fn field(name: &'static str) -> FieldSpec {
    FieldSpec { name, aliases: &[] }
}

const fn field_with(name: &'static str, aliases: &'static [&'static str]) -> FieldSpec {
    FieldSpec { name, aliases }
}

/// 白名单：`whitelist.json` → `white-list.txt`。
pub const WHITELIST: ListSpec = ListSpec {
    json_file: "whitelist.json",
    txt_file: "white-list.txt",
    fields: &[field("name"), field("uuid")],
    name_field: Some("name"),
};

/// OP 名单：`ops.json` → `ops.txt`。
pub const OPS: ListSpec = ListSpec {
    json_file: "ops.json",
    txt_file: "ops.txt",
    fields: &[field("name"), field("uuid")],
    name_field: Some("name"),
};

/// 封禁名单：`banned-players.json` → `banned-players.txt`。
pub const BANS: ListSpec = ListSpec {
    json_file: "banned-players.json",
    txt_file: "banned-players.txt",
    fields: &[
        field("name"),
        field("uuid"),
        field("reason"),
        field("source"),
        // PNX 用 expireDate，Java 用 expires
        field_with("expires", &["expireDate"]),
        // PNX 用 creationDate，Java 用 created
        field_with("created", &["creationDate"]),
    ],
    name_field: Some("name"),
};

/// IP 封禁名单：`banned-ips.json` → `banned-ips.txt`。
pub const IP_BANS: ListSpec = ListSpec {
    json_file: "banned-ips.json",
    txt_file: "banned-ips.txt",
    fields: &[
        field("ip"),
        field("reason"),
        field("source"),
        field_with("expires", &["expireDate"]),
        field_with("created", &["creationDate"]),
    ],
    // 在线页没有「这个 IP 被封了」这种标签
    name_field: None,
};

/// 一份名单的两个视图。
pub struct PlayerList {
    /// 标签页显示的那份：JSON 存在且能解析就用它（**空数组也算数**），
    /// 否则回退纯文本。
    pub entries: Vec<Value>,
    /// 在线页打标签用的小写名字：JSON 名单**非空**才算数，否则回退纯文本。
    /// 不参与打标签的名单是空数组。
    pub names: Vec<String>,
}

/// 读一份名单。目录不存在、文件读不出来都算「这份名单没有」，不报错 ——
/// 名单文件本来就是可有可无的，读不出来就当这份名单没有。
pub fn read_list(dir: &Path, spec: &ListSpec) -> PlayerList {
    let json_entries = read_json(dir, spec);
    let txt_lines = read_txt(dir, spec.txt_file);

    let json_names: Vec<String> = match (&json_entries, spec.name_field) {
        (Some(entries), Some(field)) => entries
            .iter()
            .filter_map(|entry| entry.get(field)?.as_str())
            .map(str::to_lowercase)
            .collect(),
        _ => Vec::new(),
    };

    PlayerList {
        entries: json_entries
            .unwrap_or_else(|| txt_lines.iter().map(|line| txt_entry(spec, line)).collect()),
        names: if json_names.is_empty() {
            match spec.name_field {
                Some(_) => txt_lines.iter().map(|l| l.to_lowercase()).collect(),
                None => Vec::new(),
            }
        } else {
            json_names
        },
    }
}

/// 纯文本名单的一行 → 一条记录：第一个字段填行内容，其余补空串。
fn txt_entry(spec: &ListSpec, line: &str) -> Value {
    let mut object = Map::new();
    for (index, field) in spec.fields.iter().enumerate() {
        let value = if index == 0 { line } else { "" };
        object.insert(field.name.to_string(), json!(value));
    }
    Value::Object(object)
}

/// 读 JSON 名单。`None` = 这份文件不算数（不存在 / 不是 UTF-8 / 不是合法 JSON /
/// 顶层不是数组 / 有条目不是对象），调用方接着试纯文本。
///
/// 条目里缺的字段补空串、非字符串当空串 —— 非字符串**不**导致整份回退纯文本，
/// 只当空值，理由同文件模块的「不拿畸形数据为难用户」。
fn read_json(dir: &Path, spec: &ListSpec) -> Option<Vec<Value>> {
    let text = std::fs::read_to_string(dir.join(spec.json_file)).ok()?;
    let decoded: Value = serde_json::from_str(&text).ok()?;
    let items = decoded.as_array()?;

    let mut entries = Vec::with_capacity(items.len());
    for item in items {
        let object = item.as_object()?;
        let mut entry = Map::new();
        for field in spec.fields {
            let raw = std::iter::once(&field.name)
                .chain(field.aliases.iter())
                .find_map(|key| object.get(*key))
                .and_then(Value::as_str)
                .unwrap_or("");
            entry.insert(field.name.to_string(), json!(raw));
        }
        entries.push(Value::Object(entry));
    }
    Some(entries)
}

/// 读纯文本名单：每行一个名字，空行忽略。
fn read_txt(dir: &Path, file: &str) -> Vec<String> {
    let Ok(text) = std::fs::read_to_string(dir.join(file)) else {
        return Vec::new();
    };
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed_all(tracker: &mut OnlinePlayers, text: &str) -> bool {
        tracker.feed(text.as_bytes())
    }

    #[test]
    fn join_and_leave_in_english_and_chinese() {
        let mut players = OnlinePlayers::new();
        assert!(feed_all(
            &mut players,
            "Steve[/127.0.0.1:5000] logged in with entity id 1\n"
        ));
        assert_eq!(players.names(), ["Steve"]);
        assert!(feed_all(&mut players, "Alex 加入了游戏\n"));
        assert_eq!(players.names(), ["Steve", "Alex"]);

        // 重复加入不算变化
        assert!(!feed_all(
            &mut players,
            "Steve[/127.0.0.1:5001] logged in with entity id 2\n"
        ));

        assert!(feed_all(&mut players, "Steve left the game\n"));
        assert_eq!(players.names(), ["Alex"]);
        // 退一个不在名单里的人也不算变化
        assert!(!feed_all(&mut players, "Herobrine left the game\n"));
        assert!(feed_all(&mut players, "Alex 退出了游戏\n"));
        assert!(players.names().is_empty());
    }

    #[test]
    fn chinese_login_branch_keeps_quirk() {
        // `[/\d.:]+\] 登入游戏` 里 `[` 没转义，引擎从 `[` 后面才开始匹配，
        // 前导的 `\w{1,16}` 抓到的其实是 IP 的尾数。线上就是这个结果 —— 原样保留。
        let mut players = OnlinePlayers::new();
        assert!(feed_all(&mut players, "Steve[/10.0.0.5:1234] 登入游戏\n"));
        assert_eq!(players.names(), ["10"]);
    }

    #[test]
    fn vanilla_joined_line_is_not_recognized() {
        // 只认 `[/ip] logged in`，原版那句 `joined the game` 认不出来。
        let mut players = OnlinePlayers::new();
        assert!(!feed_all(&mut players, "Steve joined the game\n"));
        assert!(players.names().is_empty());
    }

    #[test]
    fn list_response_replaces_whole_set() {
        let mut players = OnlinePlayers::new();
        players.apply_line("Steve[/127.0.0.1:5000] logged in with entity id 1");

        assert!(players.apply_line("There are 2 of a max of 20 players online: Alex, Steve"));
        assert_eq!(players.names(), ["Alex", "Steve"]);

        // 同一批人（顺序不同）不算变化
        assert!(!players.apply_line("There are 2 of a max of 20 players online: Steve, Alex"));

        // 空响应 = 没人
        assert!(players.apply_line("There are 0 of a max of 20 players online: "));
        assert!(players.names().is_empty());

        // 中文格式
        assert!(players.apply_line("当前有 1 个玩家在线：Alex"));
        assert_eq!(players.names(), ["Alex"]);
    }

    #[test]
    fn join_wins_over_list_response_on_one_line() {
        let mut players = OnlinePlayers::new();
        // 判定顺序：加入 → 退出 → list。一行里两样都有时按加入走。
        players.apply_line("Steve[/127.0.0.1:5000] logged in, players online: Alex");
        assert_eq!(players.names(), ["Steve"]);
    }

    #[test]
    fn lines_split_across_chunks_are_reassembled() {
        let mut players = OnlinePlayers::new();
        let line = "Steve[/127.0.0.1:5000] logged in with entity id 1\n";
        let bytes = line.as_bytes();
        let cut = bytes.len() / 2;
        assert!(!players.feed(&bytes[..cut]));
        assert!(!players.feed(&bytes[cut..cut + 1]));
        assert!(players.feed(&bytes[cut + 1..]));
        assert_eq!(players.names(), ["Steve"]);
    }

    #[test]
    fn chinese_name_split_inside_a_character_is_safe() {
        let mut players = OnlinePlayers::new();
        let line = "Alex 加入了游戏\n".as_bytes().to_vec();
        // 「加」是 3 字节，切在它中间喂
        for chunk in line.chunks(4) {
            players.feed(chunk);
        }
        assert_eq!(players.names(), ["Alex"]);
    }

    #[test]
    fn crlf_and_blank_lines_are_fine() {
        let mut players = OnlinePlayers::new();
        players.feed(b"Steve[/127.0.0.1:5000] logged in\r\n\r\n");
        assert_eq!(players.names(), ["Steve"]);
    }

    #[test]
    fn clear_reports_whether_there_was_anything() {
        let mut players = OnlinePlayers::new();
        assert!(!players.clear());
        players.apply_line("Steve[/127.0.0.1:5000] logged in");
        // 半个行留在缓冲里也算「有内容」，重启后必须一起丢掉
        players.feed(b"Alex[/127.0.0.1:5001] logged in with enti");
        assert!(players.clear());
        assert!(players.names().is_empty());
        assert!(!players.clear());
    }

    #[test]
    fn oversized_line_is_dropped_whole() {
        let mut players = OnlinePlayers::new();
        players.feed(&vec![b'x'; MAX_PENDING_BYTES + 1000]);
        assert!(players.pending.is_empty());

        // 已经废掉的半行：后面拼上来的内容不解析（它们本来就是同一行）
        players.feed(b"Steve[/127.0.0.1:5000] logged in\n");
        assert!(players.names().is_empty());

        // 下一个换行之后恢复正常
        players.feed(b"Alex[/127.0.0.1:5001] logged in\n");
        assert_eq!(players.names(), ["Alex"]);
    }

    // ── 名单文件 ──

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-players-{tag}-{}-{}",
            std::process::id(),
            crate::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn whitelist_prefers_json_and_falls_back_to_txt() {
        let dir = temp_dir("wl-json");
        std::fs::write(
            dir.join("whitelist.json"),
            r#"[{"name":"Steve","uuid":"uuid-steve"}]"#,
        )
        .unwrap();
        std::fs::write(dir.join("white-list.txt"), "TxtOnly\n").unwrap();

        let list = read_list(&dir, &WHITELIST);
        assert_eq!(list.entries.len(), 1);
        assert_eq!(list.entries[0]["name"], "Steve");
        assert_eq!(list.entries[0]["uuid"], "uuid-steve");
        assert_eq!(list.names, ["steve"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn empty_json_wins_for_entries_but_loses_for_names() {
        let dir = temp_dir("wl-empty");
        std::fs::write(dir.join("whitelist.json"), "[]").unwrap();
        std::fs::write(dir.join("white-list.txt"), "TxtOnly\n").unwrap();

        let list = read_list(&dir, &WHITELIST);
        // 标签页：JSON 在，名单就是空的
        assert!(list.entries.is_empty());
        // 打标签：JSON 空 → 回退纯文本
        assert_eq!(list.names, ["txtonly"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn broken_json_falls_back_to_txt() {
        let dir = temp_dir("wl-broken");
        std::fs::write(dir.join("whitelist.json"), "{not json").unwrap();
        std::fs::write(dir.join("white-list.txt"), "TxtOnly\n").unwrap();

        let list = read_list(&dir, &WHITELIST);
        assert_eq!(list.entries[0]["name"], "TxtOnly");
        assert_eq!(list.entries[0]["uuid"], "");
        assert_eq!(list.names, ["txtonly"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn non_utf8_list_file_is_treated_as_absent() {
        let dir = temp_dir("wl-binary");
        std::fs::write(dir.join("whitelist.json"), [0xff, 0xfe, 0x00]).unwrap();
        std::fs::write(dir.join("white-list.txt"), [0xff, 0xfe]).unwrap();

        let list = read_list(&dir, &WHITELIST);
        assert!(list.entries.is_empty());
        assert!(list.names.is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn bans_accept_pnx_aliases_and_fill_missing_fields() {
        let dir = temp_dir("bans-pnx");
        std::fs::write(
            dir.join("banned-players.json"),
            r#"[{"name":"Cheater","expireDate":"forever","creationDate":"2026-01-01"}]"#,
        )
        .unwrap();

        let list = read_list(&dir, &BANS);
        assert_eq!(list.entries[0]["expires"], "forever");
        assert_eq!(list.entries[0]["created"], "2026-01-01");
        assert_eq!(list.entries[0]["reason"], "");
        assert_eq!(list.names, ["cheater"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn bans_txt_fallback_has_name_only() {
        let dir = temp_dir("bans-txt");
        std::fs::write(dir.join("banned-players.txt"), "Cheater\n\nGriefer\n").unwrap();

        let list = read_list(&dir, &BANS);
        assert_eq!(list.entries.len(), 2);
        assert_eq!(list.entries[0]["name"], "Cheater");
        assert_eq!(list.entries[1]["uuid"], "");
        assert_eq!(list.names, ["cheater", "griefer"]);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ip_bans_have_no_name_set() {
        let dir = temp_dir("ip-bans");
        std::fs::write(
            dir.join("banned-ips.json"),
            r#"[{"ip":"10.0.0.9","reason":"Banned by an operator."}]"#,
        )
        .unwrap();

        let list = read_list(&dir, &IP_BANS);
        assert_eq!(list.entries[0]["ip"], "10.0.0.9");
        assert_eq!(list.entries[0]["source"], "");
        assert!(list.names.is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn missing_directory_reads_as_empty_lists() {
        let dir = std::env::temp_dir().join("edgecube-players-does-not-exist");
        for spec in [&WHITELIST, &OPS, &BANS, &IP_BANS] {
            let list = read_list(&dir, spec);
            assert!(list.entries.is_empty());
        }
    }
}
