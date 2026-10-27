//! Modrinth v2 客户端与解析。
//!
//! # 用了哪几个接口（都实测过）
//!
//! | 用途 | 请求 |
//! | --- | --- |
//! | 搜索 / 浏览 | `GET /search?query&facets&index&offset&limit` |
//! | 项目详情 | `GET /project/{id\|slug}` |
//! | 项目的版本列表 | `GET /project/{id\|slug}/version?loaders&game_versions` |
//! | 按已装文件反查最新版 | `POST /version_files/update` |
//!
//! # 两个实测出来的坑
//!
//! 1. **关注数在两个接口里字段名不同**：搜索命中是 `follows`，项目详情是
//!    `followers`。照一个写会让另一个恒为 0。
//! 2. **`facets` 是「数组的数组」**：内层是 OR，外层是 AND。加载器没有单独的
//!    facet 名，它和普通分类一起放在 `categories` 下（`categories:fabric`），
//!    所以「筛选加载器」和「筛掉杂项分类」用的是同一个字段。
//!
//! # 限流
//!
//! 300 次/分钟（响应头 `x-ratelimit-limit`）。搜索是用户点一次打一次，够用；
//! 更新检查用**批量接口**（一次提交最多 100 个哈希），不是每个文件一次请求。

use std::collections::HashMap;

use serde_json::Value;

use super::{FetchError, get_value, post_value, validate_id};
use crate::module::builtin::mods::model;

/// 接口根。写死是刻意的：换域名是升级 daemon 的事，不是配置项。
pub const API_BASE: &str = "https://api.modrinth.com/v2";

/// 本文件对应的源 id（[`model::SOURCES`] 里的那个）。
pub const SOURCE: &str = "modrinth";

/// 一次 `version_files` 批量请求最多带多少个哈希。
///
/// 上游单次能接受 1000 个，这里压到 100：请求体更小、失败时重试代价更低，
/// 而 100 个模组已经远超一般服务端的规模（超了就分多次，见 `check_updates`）。
pub const HASH_BATCH: usize = 100;

/// 拼一个接口地址。`API_BASE` 是编译期常量，解析失败属于编程错误。
fn url(path: &str) -> reqwest::Url {
    reqwest::Url::parse(&format!("{API_BASE}{path}"))
        .expect("API_BASE 是编译期常量，拼接后必然可以解析")
}

// ---------------------------------------------------------------------------
// 搜索
// ---------------------------------------------------------------------------

/// 搜索（或只是浏览：`query` 为空时上游照样返回按 `index` 排序的列表）。
///
/// 参数直接进 URL 查询串，由 [`reqwest::Url`] 负责转义 —— 不要自己拼字符串，
/// `facets` 里全是 `[` `"` `:` 这些字符。
#[allow(clippy::too_many_arguments)]
pub async fn search(
    http: &reqwest::Client,
    source: &'static str,
    query: &str,
    project_type: &str,
    loader: Option<&str>,
    game_version: Option<&str>,
    index: &str,
    offset: u64,
    limit: u64,
) -> Result<model::Page, FetchError> {
    let mut target = url("/search");
    {
        let mut pairs = target.query_pairs_mut();
        pairs.append_pair("query", query);
        pairs.append_pair("facets", &facets(project_type, loader, game_version));
        pairs.append_pair("index", index);
        pairs.append_pair("offset", &offset.to_string());
        pairs.append_pair("limit", &limit.to_string());
    }

    let value = get_value(http, target.as_str()).await?;
    parse_search(&value, source)
}

/// `facets` 的构造。
///
/// 结构是 `[[A],[B],[C]]`：内层的多个取值之间是 **OR**，外层各组之间是 **AND**。
/// 我们每组只放一个取值，所以是「项目类型 且 加载器 且 游戏版本」。
pub fn facets(project_type: &str, loader: Option<&str>, game_version: Option<&str>) -> String {
    let mut groups: Vec<Value> = vec![Value::Array(vec![Value::String(format!(
        "project_type:{project_type}"
    ))])];
    if let Some(loader) = loader {
        groups.push(Value::Array(vec![Value::String(format!(
            "categories:{loader}"
        ))]));
    }
    if let Some(game_version) = game_version {
        groups.push(Value::Array(vec![Value::String(format!(
            "versions:{game_version}"
        ))]));
    }
    Value::Array(groups).to_string()
}

/// 解析一页搜索结果。
pub fn parse_search(value: &Value, source: &'static str) -> Result<model::Page, FetchError> {
    let hits = value
        .get("hits")
        .and_then(Value::as_array)
        .ok_or_else(|| FetchError::Parse("搜索结果里没有 `hits` 数组".to_string()))?;

    let mut parsed = Vec::with_capacity(hits.len());
    for hit in hits {
        parsed.push(parse_hit(hit, source)?);
    }

    Ok(model::Page {
        hits: parsed,
        total: number(value.get("total_hits")),
        offset: number(value.get("offset")),
        limit: number(value.get("limit")),
    })
}

/// 解析一条搜索命中。
///
/// `source` 要求 `&'static str` 而不是 `&str`：它直接进 [`model::Hit::source`]
/// 那个 `&'static str` 字段。**别为此写 `Box::leak`** —— 那是每条搜索结果泄漏
/// 一次；调用方的源 id 本来就来自 [`model::SOURCES`] 这张编译期常量表。
fn parse_hit(value: &Value, source: &'static str) -> Result<model::Hit, FetchError> {
    let categories = strings(value.get("categories"));
    let project_type = text(value.get("project_type"));
    let slug = text(value.get("slug"));
    if slug.is_empty() {
        return Err(FetchError::Parse("搜索命中缺少 `slug`".to_string()));
    }

    Ok(model::Hit {
        source,
        project_id: text(value.get("project_id")),
        page_url: format!(
            "{}/{}/{}",
            model::find_source(source).map_or("", |s| s.url),
            project_type,
            slug
        ),
        slug,
        title: text(value.get("title")),
        description: text(value.get("description")),
        author: optional_text(value.get("author")),
        icon_url: optional_text(value.get("icon_url")),
        downloads: number(value.get("downloads")),
        // 搜索命中是 `follows`，项目详情是 `followers` —— 实测，别改混
        follows: number(value.get("follows")),
        loaders: known_loaders(&categories),
        categories,
        project_type,
        latest_version: optional_text(value.get("latest_version")),
        server_side: optional_text(value.get("server_side")),
    })
}

/// 解析项目详情（点进某个项目时用，字段比搜索命中更全）。
pub fn parse_project(value: &Value, source: &'static str) -> Result<model::Hit, FetchError> {
    let slug = text(value.get("slug"));
    if slug.is_empty() {
        return Err(FetchError::Parse("项目详情缺少 `slug`".to_string()));
    }
    let project_type = text(value.get("project_type"));
    let categories = strings(value.get("categories"));
    // 项目详情里有独立的 `loaders` 字段，比 categories 干净；拿不到再退回 categories
    let loaders = {
        let explicit = strings(value.get("loaders"));
        if explicit.is_empty() {
            known_loaders(&categories)
        } else {
            explicit
        }
    };

    Ok(model::Hit {
        source,
        page_url: format!(
            "{}/{}/{}",
            model::find_source(source).map_or("", |s| s.url),
            project_type,
            slug
        ),
        slug,
        project_id: text(value.get("id")),
        title: text(value.get("title")),
        description: text(value.get("description")),
        // 项目详情里没有 author 字段（作者的展示名在 team 里），留空
        author: None,
        icon_url: optional_text(value.get("icon_url")),
        downloads: number(value.get("downloads")),
        // 这里是 `followers` —— 与搜索命中的 `follows` 不是一个词
        follows: number(value.get("followers")),
        loaders,
        categories,
        project_type,
        latest_version: None,
        server_side: optional_text(value.get("server_side")),
    })
}

// ---------------------------------------------------------------------------
// 版本列表
// ---------------------------------------------------------------------------

/// 取一个项目的版本列表（新版本在前）。
///
/// `loader` / `game_version` 是可选的**上游侧筛选** —— 传了就只有匹配的版本，
/// 比拿全量再在本地过滤可靠（上游的版本兼容信息比我们能推断的准）。
pub async fn versions(
    http: &reqwest::Client,
    project_id: &str,
    loader: Option<&str>,
    game_version: Option<&str>,
) -> Result<Vec<model::VersionEntry>, FetchError> {
    let mut target = url(&format!("/project/{project_id}/version"));
    {
        let mut pairs = target.query_pairs_mut();
        if let Some(loader) = loader {
            pairs.append_pair("loaders", &Value::Array(vec![loader.into()]).to_string());
        }
        if let Some(game_version) = game_version {
            pairs.append_pair(
                "game_versions",
                &Value::Array(vec![game_version.into()]).to_string(),
            );
        }
    }

    let value = get_value(http, target.as_str()).await?;
    parse_versions(&value)
}

/// 解析版本列表。
pub fn parse_versions(value: &Value) -> Result<Vec<model::VersionEntry>, FetchError> {
    let items = value
        .as_array()
        .ok_or_else(|| FetchError::Parse("版本列表不是数组".to_string()))?;
    items.iter().map(parse_version).collect()
}

/// 解析一个版本对象。
pub fn parse_version(value: &Value) -> Result<model::VersionEntry, FetchError> {
    let id = text(value.get("id"));
    if id.is_empty() {
        return Err(FetchError::Parse("版本对象缺少 `id`".to_string()));
    }

    // 文件列表：只保留有 url 和文件名的（上游偶尔给个半截条目）
    let files = value
        .get("files")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let url = text(item.get("url"));
                    let filename = text(item.get("filename"));
                    if url.is_empty() || filename.is_empty() {
                        return None;
                    }
                    Some(model::FileEntry {
                        url,
                        filename,
                        size: number(item.get("size")),
                        // 上游的哈希是嵌套的：files[].hashes.sha1
                        sha1: item
                            .get("hashes")
                            .and_then(|hashes| hashes.get("sha1"))
                            .and_then(Value::as_str)
                            .map(|raw| raw.to_ascii_lowercase()),
                        primary: item
                            .get("primary")
                            .and_then(Value::as_bool)
                            .unwrap_or(false),
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let dependencies = value
        .get("dependencies")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .map(|item| model::Dependency {
                    project_id: optional_text(item.get("project_id")),
                    version_id: optional_text(item.get("version_id")),
                    file_name: optional_text(item.get("file_name")),
                    kind: text(item.get("dependency_type")),
                })
                .collect()
        })
        .unwrap_or_default();

    Ok(model::VersionEntry {
        project_id: text(value.get("project_id")),
        name: {
            let name = text(value.get("name"));
            if name.is_empty() {
                text(value.get("version_number"))
            } else {
                name
            }
        },
        version_number: text(value.get("version_number")),
        kind: {
            let kind = text(value.get("version_type"));
            if kind.is_empty() {
                "release".to_string()
            } else {
                kind
            }
        },
        game_versions: strings(value.get("game_versions")),
        loaders: strings(value.get("loaders")),
        date_published: text(value.get("date_published")),
        files,
        dependencies,
        id,
    })
}

// ---------------------------------------------------------------------------
// 更新检查
// ---------------------------------------------------------------------------

/// 批量反查「这些已装文件在当前筛选条件下的最新版本」。
///
/// `hashes` 是已装文件的 sha1（小写十六进制）。返回的 map 只包含**上游认得的**
/// 那些哈希 —— 缺了的说明这个文件不是从 Modrinth 装的（或者项目被删了），
/// 调用方据此在结果里标「未知来源」。
///
/// `loader` / `game_version` 都不传时上游返回「项目的最新版本」，
/// **不筛游戏版本** —— 实例元数据里没记 MC 版本，这是刻意的取舍（见模块文档）。
pub async fn latest_for_hashes(
    http: &reqwest::Client,
    hashes: &[String],
    loader: Option<&str>,
    game_version: Option<&str>,
) -> Result<HashMap<String, model::VersionEntry>, FetchError> {
    if hashes.is_empty() {
        return Ok(HashMap::new());
    }

    let mut body = serde_json::Map::new();
    body.insert("hashes".into(), Value::from(hashes.to_vec()));
    body.insert("algorithm".into(), Value::String("sha1".into()));
    if let Some(loader) = loader {
        body.insert("loaders".into(), Value::Array(vec![loader.into()]));
    }
    if let Some(game_version) = game_version {
        body.insert(
            "game_versions".into(),
            Value::Array(vec![game_version.into()]),
        );
    }

    let value = post_value(
        http,
        url("/version_files/update").as_str(),
        &Value::Object(body),
    )
    .await?;
    parse_updates(&value, hashes)
}

/// 解析批量反查的结果。
///
/// 响应是 `{ "<sha1>": {版本对象}, … }`。`hashes` 传进来是为了**补全上游没回的
/// 哈希**（上游对不认识的哈希是直接不给键，不是给个 null），这样调用方不必自己
/// 去对账「哪几个没回来」。
pub fn parse_updates(
    value: &Value,
    hashes: &[String],
) -> Result<HashMap<String, model::VersionEntry>, FetchError> {
    let object = value
        .as_object()
        .ok_or_else(|| FetchError::Parse("版本反查结果不是对象".to_string()))?;

    let mut out = HashMap::new();
    for hash in hashes {
        // 上游对大小写不敏感，但回键时用的是请求里的原文 —— 两种都试一下
        let hit = object
            .get(hash)
            .or_else(|| object.get(&hash.to_ascii_uppercase()));
        let Some(hit) = hit else {
            continue;
        };
        out.insert(hash.clone(), parse_version(hit)?);
    }
    Ok(out)
}

/// 校验一个要拼进 URL 的 id（项目 id / slug / 版本 id / 哈希）。
///
/// 复用公共层那份白名单：`/`、`..`、`?` 一旦放行就能把请求指到别处。
pub fn check_id(id: &str, field: &str) -> Result<(), String> {
    validate_id(id, field)
}

// ---------------------------------------------------------------------------
// 按哈希反查项目（配图标用）
// ---------------------------------------------------------------------------

/// 批量反查「这些文件哈希各属于哪个版本」。
///
/// 与 [`latest_for_hashes`] 的分工：那个会**按筛选条件找最新版**（「检查更新」
/// 用），这个只回答「这个哈希是哪个项目的哪个版本」（**给已装文件配图标**用）。
/// 两个接口分着用，别合并 —— 配图标要的是准，找更新要的是新。
pub async fn versions_for_hashes(
    http: &reqwest::Client,
    hashes: &[String],
) -> Result<HashMap<String, model::VersionEntry>, FetchError> {
    if hashes.is_empty() {
        return Ok(HashMap::new());
    }

    let body = serde_json::json!({
        "hashes": hashes,
        "algorithm": "sha1",
    });
    let value = post_value(http, url("/version_files").as_str(), &body).await?;
    // 与 `version_files/update` 的响应形状完全一样，复用同一个解析
    parse_updates(&value, hashes)
}

/// 批量取项目摘要（`GET /projects?ids=[…]`）。
///
/// 一次拿一批，**不是**每个文件一次 —— Modrinth 限流 300 次/分钟，
/// 一个几十模组的目录逐个查会直接把额度打满。
pub async fn projects(
    http: &reqwest::Client,
    ids: &[String],
) -> Result<HashMap<String, model::ProjectRef>, FetchError> {
    if ids.is_empty() {
        return Ok(HashMap::new());
    }

    let mut target = url("/projects");
    target.query_pairs_mut().append_pair(
        "ids",
        &Value::Array(ids.iter().cloned().map(Value::String).collect::<Vec<_>>()).to_string(),
    );
    let value = get_value(http, target.as_str()).await?;
    parse_projects(&value)
}

/// 解析一批项目摘要。
pub fn parse_projects(value: &Value) -> Result<HashMap<String, model::ProjectRef>, FetchError> {
    let items = value
        .as_array()
        .ok_or_else(|| FetchError::Parse("项目列表不是数组".to_string()))?;

    let site = model::find_source(SOURCE).map_or("", |source| source.url);
    let mut out = HashMap::new();
    for item in items {
        let project_id = text(item.get("id"));
        if project_id.is_empty() {
            continue;
        }
        let slug = text(item.get("slug"));
        let project_type = text(item.get("project_type"));
        out.insert(
            project_id.clone(),
            model::ProjectRef {
                page_url: format!("{site}/{project_type}/{slug}"),
                project_id,
                slug,
                title: text(item.get("title")),
                icon_url: optional_text(item.get("icon_url")),
                project_type,
            },
        );
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/// 把 JSON 值当字符串取；`null` / 缺字段 / 非字符串都是空串。
fn text(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

/// 同上，但空串归一成 `None`。
fn optional_text(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
}

/// 取一个非负整数；缺字段 / 类型不对都是 0（上游的计数类字段缺了不该报错）。
fn number(value: Option<&Value>) -> u64 {
    value.and_then(Value::as_u64).unwrap_or(0)
}

/// 取字符串数组；缺字段给空表。
fn strings(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

/// 从 `categories` 里挑出我们认识的加载器。
///
/// Modrinth 把加载器和普通分类混在同一个字段里（`["fabric","optimization"]`），
/// 所以「是不是加载器」只能拿我们自己的表去比。
pub fn known_loaders(categories: &[String]) -> Vec<String> {
    model::LOADERS
        .iter()
        .filter(|loader| categories.iter().any(|item| item == loader.id))
        .map(|loader| loader.id.to_string())
        .collect()
}

// ---------------------------------------------------------------------------
// 测试
// ---------------------------------------------------------------------------
//
// 下面的 JSON 都是**从真实上游抓下来的**（裁掉无关字段，形状照抄，
// 抓取脚本见模块文档里的接口表）。上游改接口时先炸的是这里。

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// 实测抓下来的 `GET /search?query=sodium`（2026-10-01）。
    fn real_search() -> Value {
        json!({
            "hits": [
                {
                    "project_id": "AANobbMI",
                    "project_type": "mod",
                    "slug": "sodium",
                    "author": "jellysquid3",
                    "title": "Sodium",
                    "description": "A high-performance rendering engine replacement.",
                    "categories": ["fabric", "neoforge", "optimization", "quilt"],
                    "downloads": 233640873,
                    "follows": 41248,
                    "icon_url": "https://cdn.modrinth.com/data/AANobbMI/x_96.webp",
                    "latest_version": "NM9w06Kr",
                    "client_side": "required",
                    "server_side": "unsupported"
                },
                {
                    "project_id": "PtjYWJkn",
                    "project_type": "mod",
                    "slug": "sodium-extra",
                    "author": "FlashyReese",
                    "title": "Sodium Extra",
                    "description": "A Sodium addon.",
                    "categories": ["fabric", "utility"],
                    "downloads": 100,
                    "follows": 5,
                    "icon_url": null,
                    "latest_version": null,
                    "server_side": "optional"
                }
            ],
            "offset": 0,
            "limit": 20,
            "total_hits": 106
        })
    }

    #[test]
    fn search_maps_hits_and_reads_the_follows_field() {
        let page = parse_search(&real_search(), "modrinth").expect("搜索结果应当能解析");

        assert_eq!(page.total, 106);
        assert_eq!(page.offset, 0);
        assert_eq!(page.hits.len(), 2);
        assert!(page.has_more(), "106 条里只拿了 2 条，应当还有");

        let first = &page.hits[0];
        assert_eq!(first.title, "Sodium");
        assert_eq!(first.project_id, "AANobbMI");
        // 搜索命中的关注数字段叫 `follows`（**不是** `followers`，那是详情接口）
        assert_eq!(first.follows, 41248);
        assert_eq!(first.downloads, 233640873);
        assert_eq!(first.page_url, "https://modrinth.com/mod/sodium");
        assert_eq!(first.server_side.as_deref(), Some("unsupported"));
        assert!(first.is_client_only(), "Sodium 是客户端专属的");
    }

    #[test]
    fn search_picks_loaders_out_of_the_categories_bag() {
        let page = parse_search(&real_search(), "modrinth").unwrap();
        // categories 里混着加载器和普通分类，只挑得出我们认识的加载器
        assert_eq!(page.hits[0].loaders, vec!["fabric", "neoforge", "quilt"]);
        assert!(
            !page.hits[0].loaders.contains(&"optimization".to_string()),
            "`optimization` 是分类不是加载器"
        );
        assert_eq!(page.hits[1].loaders, vec!["fabric"]);
    }

    #[test]
    fn search_tolerates_missing_optional_fields() {
        // 第二个命中没有 icon_url / latest_version，不该因此报错
        let page = parse_search(&real_search(), "modrinth").unwrap();
        assert!(page.hits[1].icon_url.is_none());
        assert!(page.hits[1].latest_version.is_none());
    }

    #[test]
    fn search_without_hits_is_a_parse_error_not_a_panic() {
        // 上游改了形状（比如把 hits 挪走了）→ 必须报 Parse，让前端提示「该升级了」
        let err = parse_search(&json!({ "items": [] }), "modrinth").unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
    }

    /// 实测抓下来的 `GET /project/AANobbMI`（2026-10-01）。
    #[test]
    fn project_detail_reads_followers_not_follows() {
        let project = json!({
            "id": "AANobbMI",
            "slug": "sodium",
            "title": "Sodium",
            "description": "A high-performance rendering engine replacement.",
            "project_type": "mod",
            "icon_url": "https://cdn.modrinth.com/data/AANobbMI/x_96.webp",
            "downloads": 233640873,
            "followers": 41248,
            "client_side": "required",
            "server_side": "unsupported",
            "loaders": ["fabric", "neoforge", "quilt"],
            "game_versions": ["1.21.8"],
            "categories": ["optimization"]
        });

        let hit = parse_project(&project, "modrinth").expect("项目详情应当能解析");
        // 详情接口是 `followers`；这里读不到就是恒为 0
        assert_eq!(hit.follows, 41248);
        assert_eq!(hit.loaders, vec!["fabric", "neoforge", "quilt"]);
        assert_eq!(hit.page_url, "https://modrinth.com/mod/sodium");
        // 详情接口没有 latest_version / author
        assert!(hit.latest_version.is_none());
        assert!(hit.author.is_none());
    }

    /// 实测抓下来的 `GET /project/AANobbMI/version?loaders=["fabric"]&game_versions=["1.21.8"]`。
    fn real_versions() -> Value {
        json!([
            {
                "id": "7pwil2dy",
                "project_id": "AANobbMI",
                "name": "Sodium 0.7.3 for Fabric 1.21.8",
                "version_number": "mc1.21.8-0.7.3-fabric",
                "version_type": "release",
                "game_versions": ["1.21.6", "1.21.7", "1.21.8"],
                "loaders": ["fabric"],
                "date_published": "2025-11-10T18:49:39.796580Z",
                "files": [
                    {
                        "id": "PgQNi5QF",
                        "hashes": {
                            "sha512": "2c7fe9…",
                            "sha1": "c9ed2b00385ea191e81ea4da51c008755fe90a26"
                        },
                        "url": "https://cdn.modrinth.com/data/AANobbMI/versions/7pwil2dy/sodium-fabric-0.7.3%2Bmc1.21.8.jar",
                        "filename": "sodium-fabric-0.7.3+mc1.21.8.jar",
                        "primary": true,
                        "size": 1621285
                    }
                ],
                "dependencies": []
            },
            {
                "id": "aaaaaaaa",
                "project_id": "AANobbMI",
                "name": "旧版",
                "version_number": "mc1.21.7-0.7.2-fabric",
                "version_type": "beta",
                "game_versions": ["1.21.7"],
                "loaders": ["fabric"],
                "date_published": "2025-10-01T00:00:00Z",
                "files": [
                    {
                        "hashes": { "sha1": "AAAABBBB" },
                        "url": "https://cdn.modrinth.com/x.jar",
                        "filename": "x.jar",
                        "primary": true,
                        "size": 1
                    }
                ],
                "dependencies": [
                    {
                        "version_id": null,
                        "project_id": "P7dR8mSH",
                        "file_name": "fabric-api-0.1.jar",
                        "dependency_type": "required"
                    }
                ]
            }
        ])
    }

    #[test]
    fn versions_keep_upstream_order_and_lowercase_the_sha1() {
        let versions = parse_versions(&real_versions()).expect("版本列表应当能解析");
        assert_eq!(versions.len(), 2);
        assert_eq!(versions[0].version_number, "mc1.21.8-0.7.3-fabric");
        assert!(versions[0].is_release());
        assert!(!versions[1].is_release());

        let file = versions[0].primary_file().expect("应当有主文件");
        // URL 里的 `%2B` 原样保留 —— 不要自作主张解码，上游要的就是它
        assert!(file.url.contains("%2Bmc1.21.8.jar"));
        assert_eq!(file.filename, "sodium-fabric-0.7.3+mc1.21.8.jar");
        assert_eq!(file.size, 1621285);
        // sha1 统一成小写，方便和本地算出来的比
        assert_eq!(
            file.sha1.as_deref(),
            Some("c9ed2b00385ea191e81ea4da51c008755fe90a26")
        );
    }

    #[test]
    fn versions_read_dependencies() {
        let versions = parse_versions(&real_versions()).unwrap();
        let dependency = &versions[1].dependencies[0];
        assert_eq!(dependency.kind, "required");
        assert_eq!(dependency.file_name.as_deref(), Some("fabric-api-0.1.jar"));
        assert_eq!(dependency.project_id.as_deref(), Some("P7dR8mSH"));
        assert!(dependency.version_id.is_none());
    }

    #[test]
    fn version_without_id_is_rejected() {
        let err = parse_versions(&json!([{ "name": "x" }])).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
    }

    #[test]
    fn primary_file_falls_back_to_the_first_one() {
        let versions = parse_versions(&json!([{
            "id": "v1",
            "files": [
                { "url": "https://x/a.jar", "filename": "a.jar", "primary": false },
                { "url": "https://x/b.jar", "filename": "b.jar", "primary": false }
            ]
        }]))
        .unwrap();
        assert_eq!(
            versions[0]
                .primary_file()
                .map(|file| file.filename.as_str()),
            Some("a.jar"),
            "没有 primary 标记时应当退回第一个"
        );
    }

    #[test]
    fn versions_with_garbage_entries_are_skipped_not_fatal() {
        // 上游偶发的半截条目（没有 url / filename）不该让整页解析失败
        let versions = parse_versions(&json!([{
            "id": "v1",
            "files": [
                { "url": "", "filename": "empty-url.jar" },
                { "url": "https://x/ok.jar" },
                { "url": "https://x/ok.jar", "filename": "ok.jar", "primary": true }
            ]
        }]))
        .unwrap();
        assert_eq!(versions[0].files.len(), 1);
        assert_eq!(versions[0].files[0].filename, "ok.jar");
    }

    /// 实测抓下来的 `POST /version_files/update`（2026-10-01）。
    #[test]
    fn update_lookup_is_keyed_by_the_hash_we_sent() {
        let hash = "c9ed2b00385ea191e81ea4da51c008755fe90a26";
        let response = json!({
            hash: {
                "id": "7pwil2dy",
                "project_id": "AANobbMI",
                "version_number": "mc1.21.8-0.7.3-fabric",
                "version_type": "release",
                "loaders": ["fabric"],
                "files": [
                    {
                        "hashes": { "sha1": hash },
                        "url": "https://cdn.modrinth.com/x.jar",
                        "filename": "x.jar",
                        "primary": true
                    }
                ]
            }
        });

        let found = parse_updates(&response, &[hash.to_string()]).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[hash].version_number, "mc1.21.8-0.7.3-fabric");
    }

    #[test]
    fn update_lookup_leaves_unknown_hashes_out() {
        // 上游对不认识的哈希是**直接不给键**，不是给个 null
        let response = json!({
            "aaaaaaaa": { "id": "v1", "files": [] }
        });
        let hashes = vec!["aaaaaaaa".to_string(), "bbbbbbbb".to_string()];
        let found = parse_updates(&response, &hashes).unwrap();
        assert_eq!(found.len(), 1, "`bbbbbbbb` 上游不认得，就该不在结果里");
        assert!(found.contains_key("aaaaaaaa"));
    }

    #[test]
    fn update_lookup_of_nothing_makes_no_request_shapes() {
        // 空哈希表直接返回空（调用方会走这条分支，不该白打一次上游）
        let found = parse_updates(&json!({}), &[]).unwrap();
        assert!(found.is_empty());
    }

    #[test]
    fn facets_nest_or_groups_inside_and_groups() {
        // 内层数组是 OR，外层各组是 AND
        assert_eq!(
            facets("mod", Some("fabric"), Some("1.21.8")),
            r#"[["project_type:mod"],["categories:fabric"],["versions:1.21.8"]]"#
        );
        // 不筛加载器 / 游戏版本时就只有一组
        assert_eq!(facets("plugin", None, None), r#"[["project_type:plugin"]]"#);
    }

    #[test]
    fn ids_are_checked_before_being_spliced_into_a_url() {
        for bad in ["", "../x", "a/b", "a?b", "a b"] {
            assert!(check_id(bad, "project_id").is_err(), "`{bad}` 应当被拒");
        }
        for good in ["AANobbMI", "sodium-extra", "7pwil2dy"] {
            assert!(check_id(good, "project_id").is_ok(), "`{good}` 应当放行");
        }
    }

    #[test]
    fn api_base_is_a_constant_we_can_parse() {
        // `url()` 里 unwrap 的前提
        assert!(
            url("/search")
                .as_str()
                .starts_with("https://api.modrinth.com/v2/")
        );
    }

    /// 实测抓下来的 `GET /projects?ids=[…]`（2026-10-01）。
    #[test]
    fn batch_projects_are_keyed_by_id_and_carry_the_icon() {
        let response = json!([
            {
                "id": "PtjYWJkn",
                "slug": "sodium-extra",
                "title": "Sodium Extra",
                "icon_url": "https://cdn.modrinth.com/data/PtjYWJkn/x_96.webp",
                "project_type": "mod"
            },
            {
                // 没有图标的项目：`icon_url` 会是 null，不该因此整批失败
                "id": "AANobbMI",
                "slug": "sodium",
                "title": "Sodium",
                "icon_url": null,
                "project_type": "mod"
            }
        ]);

        let projects = parse_projects(&response).expect("项目列表应当能解析");
        assert_eq!(projects.len(), 2);

        let extra = &projects["PtjYWJkn"];
        assert_eq!(extra.title, "Sodium Extra");
        assert_eq!(
            extra.icon_url.as_deref(),
            Some("https://cdn.modrinth.com/data/PtjYWJkn/x_96.webp")
        );
        assert_eq!(extra.page_url, "https://modrinth.com/mod/sodium-extra");
        assert!(projects["AANobbMI"].icon_url.is_none());
    }

    #[test]
    fn batch_projects_skips_entries_without_an_id() {
        let response = json!([{ "slug": "x" }, { "id": "ok", "slug": "y" }]);
        let projects = parse_projects(&response).unwrap();
        assert_eq!(projects.len(), 1);
        assert!(projects.contains_key("ok"));
    }

    #[test]
    fn batch_projects_rejects_a_non_array() {
        let err = parse_projects(&json!({ "projects": [] })).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
    }
}
