//! 上游源客户端。
//!
//! 一个源一个文件，都是「取版本列表」+「取某个版本的下载地址」两件事。
//! 每个文件都把**解析**单独拎成纯函数（`parse_*`）：上游改接口时炸的是那些
//! 函数，而它们能在没有网络的情况下用真实响应体钉住。
//!
//! 「怎么打上游」（客户端、GET、三类失败、标识符白名单）是**公共**的，
//! 在 [`crate::util::fetch`] 里，这里转出来给源模块用；本文件只留与
//! Minecraft 服务端有关的那些（版本号比较之类）。
//!
//! 统一约定：
//!
//! * 请求带 `EdgeCube-daemon/<版本>` 的 User-Agent（GitHub 那类接口没有 UA 会 403）；
//! * **不重试** —— 这些接口都是小 JSON，失败就让用户点重试，比偷偷等半分钟好；
//! * 校验算法由**我们**指定（见 [`Download::checksum`]），不采信上游返回的算法名，
//!   因为它要直接当 `download.add` 的参数名用。

pub mod bungeecord;
pub mod fabric;
pub mod leafmc;
pub mod mojang;
pub mod papermc;
pub mod purpur;

pub use crate::util::fetch::{
    FetchError, build_client, get_json, get_value, validate_token as validate_version_token,
};

/// `(算法, 值)`。算法是我们这边定的（不采信上游返回的算法名），
/// 取值就是 `download.add` 的参数名。
pub type Checksum = (&'static str, String);

/// 一个源的下载信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Download {
    pub url: String,
    pub checksum: Option<Checksum>,
}

// ---------------------------------------------------------------------------
// 版本号处理
// ---------------------------------------------------------------------------

/// 是不是预发布版（RC / pre）。
pub fn is_prerelease(version: &str) -> bool {
    let lower = version.to_ascii_lowercase();
    lower.contains("rc") || lower.contains("pre")
}

/// 版本号降序（新版本在前）。
///
/// **一定要自己排**：上游给的顺序不可信 —— purpur / leaves 是升序，leaf 干脆是乱的
/// （实测：`1.21.11, 1.21.4, 1.21.5, 1.21.6 …`）。
///
/// 按 `.` 分段做数值比较，非数字段退化成字符串比较。正式版里不会出现
/// `-pre1` 这类后缀（取列表时就滤掉了），所以不用管它们。
pub fn sort_versions_desc(versions: &mut [String]) {
    versions.sort_by(|a, b| compare_versions(b, a));
}

/// 版本号比较（同 [`sort_versions_desc`] 的规则）。
pub fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    let mut left = a.split('.');
    let mut right = b.split('.');
    loop {
        match (left.next(), right.next()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) => {
                let order = match (x.parse::<u64>(), y.parse::<u64>()) {
                    (Ok(nx), Ok(ny)) => nx.cmp(&ny),
                    _ => x.cmp(y),
                };
                if order != Ordering::Equal {
                    return order;
                }
            }
        }
    }
}
