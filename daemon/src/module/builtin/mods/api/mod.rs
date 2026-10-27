//! 上游源客户端。
//!
//! 一个源一个文件，都提供三件事：**搜索**、**取项目的版本列表**、
//! **按已装文件的哈希反查最新版本**（更新检查）。
//!
//! 每个源都把**解析**单独拎成纯函数（`parse_*`）：上游改接口时炸的是那些函数，
//! 而它们能在没有网络的情况下用真实响应体钉住（见本文件底部的测试）。
//!
//! 「怎么打上游」（客户端、GET / POST、三类失败、标识符白名单）是**公共**的，
//! 在 [`crate::util::fetch`] 里，这里转出来给源模块用。
//!
//! 统一约定（与 `mcserver/api` 一致）：
//!
//! * 请求带 `EdgeCube/<版本>` 的 User-Agent。**Modrinth 强制要求**有 UA，
//!   没有会被拒；限流是 300 次/分钟（实测响应头 `x-ratelimit-limit: 300`）；
//! * **不重试** —— 失败就让用户点重试；
//! * 校验算法由**我们**指定，不采信上游返回的算法名（它要直接当 `download.add`
//!   的参数名用）。

pub mod modrinth;

pub use crate::util::fetch::{
    FetchError, build_client, get_json, get_value, post_json, post_value,
    validate_token as validate_id,
};

/// 上游给的 `(算法, 值)`。取值就是 `download.add` 的参数名。
pub type Checksum = (&'static str, String);
