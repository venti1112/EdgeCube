//! 上游源客户端。
//!
//! 两家：Azul（JDK，[`azul`]）与 GitHub Releases（frp，[`github`]）。
//! 每个源的**解析**都拎成纯函数（`parse_*`），
//! 用真实抓下来的响应体钉在测试里 —— 上游改形状时先炸测试，而不是线上用户。
//!
//! 「怎么打上游」那层（客户端、GET、三类失败、标识符白名单）与 Minecraft 服务端
//! 那边共用，在 [`crate::util::fetch`]。

pub mod azul;
pub mod github;
