//! 与上游 HTTP 接口打交道的公共部分：客户端、GET / POST、以及三类失败。
//!
//! 抽出来是因为**不止一个模块要打上游**：`mcserver`（Mojang / PaperMC / …）、
//! `runtime`（Azul 的 JDK 清单）与 `mods`（Modrinth）用的是同一套「取 JSON、
//! 分三种失败」的口径。各家的**解析**仍然留在自己模块里（那是各自的业务知识），
//! 这里只放与业务无关的那层。
//!
//! # 为什么有 POST
//!
//! 绝大多数上游都是「一个 GET 换一份 JSON」，但**批量接口**例外：
//! Modrinth 的「按文件哈希反查最新版本」（`version_files/update`，模组更新检查
//! 就靠它）一次要带几十个哈希，只能用 POST 带 body。所以这里补一个 POST，
//! 而不是让 `mods` 自己再建一个客户端 —— 失败分类与错误文案是共用的。
//!
//! 统一约定：
//!
//! * 请求带 `EdgeCube/<版本>` 的 User-Agent（GitHub 那类接口没有 UA 会 403）；
//! * **不重试** —— 这些接口都是小 JSON，失败就让用户点重试，比偷偷等半分钟好。

use std::time::Duration;

use serde::de::DeserializeOwned;
use serde_json::Value;

/// 与上游打交道失败的原因。
///
/// 分这么细是为了让前端的报错能说人话：`NotFound` 是「你自己选错了版本」，
/// `Upstream` 是「网络/对面挂了（可以重试）」，`Parse` 是「我们该升级了」。
/// 各模块再把它翻成自己的错误码（`mcserver_*` / `runtime_*`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FetchError {
    /// 上游没有这个版本，或这个版本没有可下载的构建。
    NotFound(String),
    /// 网络失败 / 非 2xx。
    Upstream(String),
    /// 响应形状不是我们认识的样子（多半是上游改接口了）。
    Parse(String),
}

impl std::fmt::Display for FetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotFound(message) => write!(f, "{message}"),
            Self::Upstream(message) => write!(f, "{message}"),
            Self::Parse(message) => write!(f, "{message}"),
        }
    }
}

/// 建一个共用的 HTTP 客户端。
pub fn build_client(timeout_secs: u64) -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(timeout_secs.max(1)))
        .user_agent(format!("EdgeCube/{}", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| format!("建 HTTP 客户端失败: {e}"))
}

/// GET 一个 JSON 接口。非 2xx 一律算 `Upstream`（含 404 —— 对我们的使用方式来说
/// 「上游说没有」和「上游挂了」对用户是同一件事：这个版本拿不到）。
pub async fn get_json<T: DeserializeOwned>(
    http: &reqwest::Client,
    url: &str,
) -> Result<T, FetchError> {
    let value = get_value(http, url).await?;
    serde_json::from_value(value)
        .map_err(|e| FetchError::Parse(format!("{url} 的响应不是预期形状：{e}")))
}

/// GET 一个 JSON 接口，拿到未解析的 [`Value`]（给「先看两层再决定怎么解」的用）。
pub async fn get_value(http: &reqwest::Client, url: &str) -> Result<Value, FetchError> {
    let response = http
        .get(url)
        .send()
        .await
        .map_err(|e| FetchError::Upstream(format!("请求 {url} 失败：{e}")))?;

    let status = response.status();
    if !status.is_success() {
        return Err(FetchError::Upstream(format!(
            "{url} 返回 HTTP {}",
            status.as_u16()
        )));
    }

    let body = response
        .text()
        .await
        .map_err(|e| FetchError::Upstream(format!("读 {url} 的响应失败：{e}")))?;
    serde_json::from_str(&body)
        .map_err(|e| FetchError::Parse(format!("{url} 的响应不是合法 JSON：{e}")))
}

/// POST 一份 JSON 到接口，拿到未解析的 [`Value`]。
///
/// 失败分类与 [`get_value`] 完全一致 —— 对调用方来说「换了个动词」不该改变
/// 错误语义。**404 仍然算 `Upstream`**：对我们的用法（批量查询）来说，
/// 「这个哈希上游没有」是用**响应里缺了那个键**表达的，而不是 HTTP 404。
pub async fn post_value(
    http: &reqwest::Client,
    url: &str,
    body: &Value,
) -> Result<Value, FetchError> {
    let response = http
        .post(url)
        .json(body)
        .send()
        .await
        .map_err(|e| FetchError::Upstream(format!("请求 {url} 失败：{e}")))?;

    let status = response.status();
    if !status.is_success() {
        return Err(FetchError::Upstream(format!(
            "{url} 返回 HTTP {}",
            status.as_u16()
        )));
    }

    let text = response
        .text()
        .await
        .map_err(|e| FetchError::Upstream(format!("读 {url} 的响应失败：{e}")))?;
    serde_json::from_str(&text)
        .map_err(|e| FetchError::Parse(format!("{url} 的响应不是合法 JSON：{e}")))
}

/// POST 一份 JSON，并把响应解析成 `T`。
pub async fn post_json<T: DeserializeOwned>(
    http: &reqwest::Client,
    url: &str,
    body: &Value,
) -> Result<T, FetchError> {
    let value = post_value(http, url, body).await?;
    serde_json::from_value(value)
        .map_err(|e| FetchError::Parse(format!("{url} 的响应不是预期形状：{e}")))
}

/// 要拼进上游 URL 的那个标识符（版本号、构建号之类）的字符白名单。
///
/// **这是安全边界**：上游 URL 是把调用方给的值拼进去的，放行 `/`、`..`、`?`
/// 任何一个都可能让请求指到别处。调用方还会拿它去比对上游客回的列表
/// （那才是主校验），这里是第二层。
pub fn validate_token(token: &str, field: &str) -> Result<(), String> {
    if token.is_empty() {
        return Err(format!("`{field}` 不能为空"));
    }
    if token.len() > 64 {
        return Err(format!("`{field}` 过长（上限 64 字符）"));
    }
    if !token
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' || c == '+')
    {
        return Err(format!("`{field}` 含非法字符：`{token}`"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_token_rejects_path_characters() {
        for bad in ["", "../etc/passwd", "a/b", "a?b", "a b", "a\\b"] {
            assert!(validate_token(bad, "version").is_err(), "`{bad}` 应当被拒");
        }
        for good in ["1.21.8", "21.0.12.1", "0.16.14", "jre-21_x64"] {
            assert!(validate_token(good, "version").is_ok(), "`{good}` 应当放行");
        }
        assert!(validate_token(&"1".repeat(65), "version").is_err());
    }
}
