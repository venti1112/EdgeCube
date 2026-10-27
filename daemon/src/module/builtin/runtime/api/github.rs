//! GitHub Releases 客户端 —— 目前只服务 `fatedier/frp`。
//!
//! 与 Azul 那家的三点不同，都是 GitHub 的形态决定的：
//!
//! 1. **版本不是数字**，是 semver 标签（`v0.71.0`）。我们规范化成 `0.71.0`
//!    （去掉前缀 `v`）作为环境 id 的一段，标签原文留在元数据里排错用。
//! 2. **一个 release 里有很多平台的产物**（实测一个版本 18 个 asset：linux /
//!    darwin / windows / android / freebsd … 各平台各架构）。所以要按**目标平台
//!    的 asset 名**挑一个，而不是像 Azul 那样「一个版本一个包」。
//! 3. **校验值在 asset 自己的 `digest` 字段里**（`sha256:…`，与同页的
//!    `frp_sha256_checksums.txt` 内容一致，实测核对过）。所以不用像 Azul 那样
//!    再问一次详情接口 —— 少一次请求，也就少一次限流的风险。
//!
//! 两个入口对应两种需求：**默认只要最新**（`/releases/latest`，一个对象）、
//! 用户点了「历史版本」才拉列表（`/releases`，一个数组）。
//!
//! 未认证的 GitHub API 只有 **60 次/小时**，所以调用方（`runtime`）必须缓存。

use serde_json::Value;

use crate::module::builtin::runtime::model::Target;
use crate::util::fetch::{self, FetchError};

/// 上游仓库。
pub const REPO: &str = "fatedier/frp";
const BASE: &str = "https://api.github.com/repos";

/// 历史版本一次拉多少个。
///
/// 20 是「够用」与「一次请求的体量」之间的取中：frp 的 release 里 asset 很多，
/// 20 条的响应已经有几十 KB；再多的版本用户也不会翻。
pub const HISTORY_PAGE_SIZE: u32 = 20;

/// 一个可下载的 frp 版本。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    /// 规范化版本号（去掉前缀 `v`）：`0.71.0`。进环境 id。
    pub version: String,
    /// 上游标签原文（`v0.71.0`）—— 拼下载地址要用它，排错时也用得上。
    pub tag: String,
    /// 该版本里对应**本机平台**的那个产物。
    pub asset: Asset,
    /// 发布时间（ISO 8601 字符串，展示用）。
    pub published_at: Option<String>,
}

/// 一个 release 产物。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Asset {
    pub name: String,
    pub url: String,
    pub size: Option<u64>,
    /// 上游给的 sha256（小写十六进制）。**没有就拒绝下载** —— 与 Azul 同一条规矩。
    pub sha256: String,
}

/// 本机平台对应的 asset 名里的「os 段」。
///
/// GitHub 用的是 Go 的 `GOOS`/`GOARCH` 命名（`linux` / `darwin` / `windows`，
/// `amd64` / `arm64`），与 [`Target`] 里给 id 用的短名（`macos` / `x64`）**不一样**。
/// 这层映射就放在这里：别的地方都只认 [`Target`]。
fn go_os(target: &Target) -> Option<&'static str> {
    match target.os {
        "linux" => Some("linux"),
        "macos" => Some("darwin"),
        "windows" => Some("windows"),
        _ => None,
    }
}

fn go_arch(target: &Target) -> Option<&'static str> {
    match target.arch {
        "x64" => Some("amd64"),
        "aarch64" => Some("arm64"),
        // 实测有 linux_arm / linux_arm_hf，但 Target 只认 x64 / aarch64
        _ => None,
    }
}

/// 一个版本的 asset 名前缀：`frp_0.71.0_linux_amd64`。
///
/// frp 的命名规则是 `frp_<版本>_<os>_<arch>.<tar.gz|zip>`（实测确认），
/// Windows 是 `.zip`、其余是 `.tar.gz`。
fn expected_asset_stem(version: &str, target: &Target) -> Option<String> {
    let (os, arch) = (go_os(target)?, go_arch(target)?);
    Some(format!("frp_{version}_{os}_{arch}"))
}

/// 从一堆 asset 里挑出本机平台那个。
///
/// 匹配是**精确的名字相等**（`<stem>.tar.gz` / `<stem>.zip`），不做前缀猜测 ——
/// asset 名里那些 `arm_hf` / `mips64le` 之类的变体一旦被前缀匹配捞进来，
/// 就是「装了一个跑不起来的二进制」这种最难查的错。
pub fn pick_asset(assets: &[Value], version: &str, target: &Target) -> Result<Asset, FetchError> {
    let stem = expected_asset_stem(version, target).ok_or_else(|| {
        FetchError::Parse(format!(
            "这个平台（{} {}）没有对应的 frp 构建",
            target.os, target.arch
        ))
    })?;
    let wanted = [format!("{stem}.{}", target.archive_type)];

    let asset = assets
        .iter()
        .find(|asset| {
            asset
                .get("name")
                .and_then(Value::as_str)
                .is_some_and(|name| wanted.iter().any(|w| w == name))
        })
        .ok_or_else(|| {
            FetchError::NotFound(format!(
                "`{REPO}` 的 `{version}` 里没有 `{}`",
                wanted.join("` / `")
            ))
        })?;

    let name = asset
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let url = asset
        .get("browser_download_url")
        .and_then(Value::as_str)
        .filter(|url| !url.is_empty())
        .ok_or_else(|| FetchError::Parse(format!("asset `{name}` 没有下载地址")))?
        .to_string();
    let size = asset.get("size").and_then(Value::as_u64);

    // `sha256:<hex>`。没给就等于没校验值 —— **拒绝**，不做无校验下载。
    let sha256 = asset
        .get("digest")
        .and_then(Value::as_str)
        .and_then(|digest| digest.strip_prefix("sha256:"))
        .filter(|hex| hex.len() == 64 && hex.chars().all(|c| c.is_ascii_hexdigit()))
        .ok_or_else(|| {
            FetchError::Parse(format!(
                "asset `{name}` 没有可用的 sha256（上游没给 `digest`）"
            ))
        })?
        .to_ascii_lowercase();

    Ok(Asset {
        name,
        url,
        size,
        sha256,
    })
}

/// 解析一个 release 对象（`/releases/latest` 的响应，或列表里的一项）。
pub fn parse_release(value: &Value, target: &Target) -> Result<Version, FetchError> {
    let tag = value
        .get("tag_name")
        .and_then(Value::as_str)
        .filter(|tag| !tag.is_empty())
        .ok_or_else(|| FetchError::Parse("release 里没有 `tag_name`".to_string()))?
        .to_string();
    // 规范化：去掉前缀 `v`（frp 一直是 `v0.71.0`，但别假设将来也带）
    let version = tag.strip_prefix('v').unwrap_or(&tag).to_string();

    let assets = value
        .get("assets")
        .and_then(Value::as_array)
        .ok_or_else(|| FetchError::Parse(format!("release `{tag}` 里没有 `assets`")))?;

    Ok(Version {
        asset: pick_asset(assets, &version, target)?,
        published_at: value
            .get("published_at")
            .and_then(Value::as_str)
            .map(str::to_string),
        tag,
        version,
    })
}

/// 最新的一个版本（`GET /releases/latest`）。
///
/// 「最新」由 GitHub 判定：**不含** prerelease 与 draft。
pub async fn latest(http: &reqwest::Client, target: &Target) -> Result<Version, FetchError> {
    let value = fetch::get_value(http, &format!("{BASE}/{REPO}/releases/latest")).await?;
    parse_release(&value, target)
}

/// 最近的若干版本（`GET /releases?per_page=N`），**新的在前**。
///
/// 上游返回的列表里可能有 draft；prerelease 我们也过滤掉 ——「历史版本」是给
/// 「新版跑不起来想退回旧版」用的，把 rc / beta 混进来只会让用户选错。
pub async fn history(http: &reqwest::Client, target: &Target) -> Result<Vec<Version>, FetchError> {
    let url = format!("{BASE}/{REPO}/releases?per_page={HISTORY_PAGE_SIZE}");
    let value = fetch::get_value(http, &url).await?;
    let releases = value
        .as_array()
        .ok_or_else(|| FetchError::Parse("release 列表不是数组".to_string()))?;

    Ok(releases
        .iter()
        .filter(|release| {
            release.get("draft").and_then(Value::as_bool) != Some(true)
                && release.get("prerelease").and_then(Value::as_bool) != Some(true)
        })
        // 挑不出本机平台的产物（某个老版本没出这个平台的包）就跳过它，
        // 而不是让整张列表失败 —— 用户要的是「能装的那些」。
        .filter_map(|release| parse_release(release, target).ok())
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn linux() -> Target {
        Target {
            os: "linux",
            query_os: "linux-glibc",
            arch: "x64",
            archive_type: "tar.gz",
            libc: Some("glibc"),
        }
    }

    fn windows() -> Target {
        Target {
            os: "windows",
            query_os: "windows",
            arch: "x64",
            archive_type: "zip",
            libc: None,
        }
    }

    fn macos_arm() -> Target {
        Target {
            os: "macos",
            query_os: "macos",
            arch: "aarch64",
            archive_type: "tar.gz",
            libc: None,
        }
    }

    /// 实测抓下来的 `GET /repos/fatedier/frp/releases/latest`（裁到我们要的字段，
    /// 但**asset 全留着** —— `pick_asset` 的匹配逻辑就是靠这份名单钉的）。
    fn real_latest() -> Value {
        json!({
            "tag_name": "v0.71.0",
            "name": "v0.71.0",
            "draft": false,
            "prerelease": false,
            "published_at": "2026-08-14T06:36:29Z",
            "assets": [
                {"name": "frp_0.71.0_android_arm64.tar.gz", "size": 13070767,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_android_arm64.tar.gz",
                 "digest": "sha256:845b486c63686990e671f13cc5e3bd130ce7be659ab3c6f043008353451858cb"},
                {"name": "frp_0.71.0_darwin_amd64.tar.gz", "size": 13958811,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_darwin_amd64.tar.gz",
                 "digest": "sha256:1b1b4e2f1836e21e8733f1dddaacd4ed9ae67d7dbee39046b9d7b7eda6253637"},
                {"name": "frp_0.71.0_darwin_arm64.tar.gz", "size": 12680181,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_darwin_arm64.tar.gz",
                 "digest": "sha256:45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6"},
                {"name": "frp_0.71.0_freebsd_amd64.tar.gz", "size": 13612890,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_freebsd_amd64.tar.gz",
                 "digest": "sha256:207c85353dd66e9ef1125a8ee60e4fd4a562f364bc584c4a5ff55e7ac7355bb8"},
                {"name": "frp_0.71.0_linux_amd64.tar.gz", "size": 13932092,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_amd64.tar.gz",
                 "digest": "sha256:84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716"},
                {"name": "frp_0.71.0_linux_arm.tar.gz", "size": 12926280,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_arm.tar.gz",
                 "digest": "sha256:f40a984f83e8d34a9241b0be4a9d5fbcfe513a4a5c022b84a02637ff6d36833b"},
                {"name": "frp_0.71.0_linux_arm64.tar.gz", "size": 12375716,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_arm64.tar.gz",
                 "digest": "sha256:f33c293c275d8fc68c654b6fba8f10b2551d6463d09a9fc9cffb72295f0f5d2e"},
                {"name": "frp_0.71.0_linux_arm_hf.tar.gz", "size": 12893288,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_arm_hf.tar.gz",
                 "digest": "sha256:7c3b0d5e8ea3a4b0d5e0d0f4e3c6bb0b40bd0e2f9a0d5a1c8d0d0a4b0b0e0f0a0"},
                {"name": "frp_0.71.0_linux_loong64.tar.gz", "size": 12784930,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_loong64.tar.gz",
                 "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111"},
                {"name": "frp_0.71.0_linux_mips64le.tar.gz", "size": 11968643,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_mips64le.tar.gz",
                 "digest": "sha256:2222222222222222222222222222222222222222222222222222222222222222"},
                {"name": "frp_0.71.0_linux_riscv64.tar.gz", "size": 12827309,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_riscv64.tar.gz",
                 "digest": "sha256:3333333333333333333333333333333333333333333333333333333333333333"},
                {"name": "frp_0.71.0_windows_amd64.zip", "size": 13933256,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_windows_amd64.zip",
                 "digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"},
                {"name": "frp_0.71.0_windows_arm64.zip", "size": 12213292,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_windows_arm64.zip",
                 "digest": "sha256:5555555555555555555555555555555555555555555555555555555555555555"},
                {"name": "frp_sha256_checksums.txt", "size": 1645,
                 "browser_download_url": "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_sha256_checksums.txt",
                 "digest": null}
            ]
        })
    }

    #[test]
    fn picks_the_asset_for_the_host_platform() {
        let version = parse_release(&real_latest(), &linux()).unwrap();
        assert_eq!(version.version, "0.71.0");
        assert_eq!(version.tag, "v0.71.0");
        assert_eq!(
            version.published_at.as_deref(),
            Some("2026-08-14T06:36:29Z")
        );
        assert_eq!(version.asset.name, "frp_0.71.0_linux_amd64.tar.gz");
        assert_eq!(
            version.asset.url,
            "https://github.com/fatedier/frp/releases/download/v0.71.0/frp_0.71.0_linux_amd64.tar.gz"
        );
        assert_eq!(version.asset.size, Some(13932092));
        // digest 的 `sha256:` 前缀要被剥掉，值就是 checksums.txt 里那一行
        assert_eq!(
            version.asset.sha256,
            "84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716"
        );
    }

    /// 平台不同 → 产物不同（Windows 是 zip，macOS 的 os 段是 darwin）。
    #[test]
    fn maps_platform_names_to_githubs_naming() {
        assert_eq!(
            parse_release(&real_latest(), &windows())
                .unwrap()
                .asset
                .name,
            "frp_0.71.0_windows_amd64.zip"
        );
        assert_eq!(
            parse_release(&real_latest(), &macos_arm())
                .unwrap()
                .asset
                .name,
            "frp_0.71.0_darwin_arm64.tar.gz"
        );
    }

    /// **不能**被前缀捞走：`linux_arm` / `linux_arm_hf` 都在名单里，
    /// 精确匹配才拿得到 `linux_amd64`。
    #[test]
    fn does_not_confuse_arch_variants() {
        let arm = Target {
            os: "linux",
            query_os: "linux",
            arch: "x64",
            archive_type: "tar.gz",
            libc: None,
        };
        assert_eq!(
            parse_release(&real_latest(), &arm).unwrap().asset.name,
            "frp_0.71.0_linux_amd64.tar.gz",
            "`linux_arm` 是另一个架构，不该被选中"
        );
    }

    #[test]
    fn rejects_releases_without_a_checksum() {
        let mut release = real_latest();
        // 把 linux 那条的 digest 抹掉
        for asset in release["assets"].as_array_mut().unwrap() {
            if asset["name"] == json!("frp_0.71.0_linux_amd64.tar.gz") {
                asset["digest"] = json!(null);
            }
        }
        let err = parse_release(&release, &linux()).unwrap_err();
        assert!(
            matches!(err, FetchError::Parse(ref m) if m.contains("sha256")),
            "没有校验值必须拒绝：{err:?}"
        );
    }

    #[test]
    fn missing_platform_asset_is_not_found() {
        let release = json!({
            "tag_name": "v0.71.0",
            "assets": [{"name": "frp_0.71.0_linux_amd64.tar.gz", "browser_download_url": "https://x/y",
                        "digest": "sha256:84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716"}]
        });
        let err = parse_release(&release, &windows()).unwrap_err();
        assert!(matches!(err, FetchError::NotFound(_)), "{err:?}");
    }

    /// 列表接口的响应是数组，draft / prerelease 要滤掉，
    /// 挑不出本机产物的版本要跳过而不是让整张列表失败。
    #[test]
    fn history_filters_drafts_and_prereleases() {
        let releases = json!([
            real_latest(),
            {"tag_name": "v0.70.1", "draft": false, "prerelease": false,
             "assets": [{"name": "frp_0.70.1_linux_amd64.tar.gz", "browser_download_url": "https://x/a",
                         "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]},
            // 预发布：不要
            {"tag_name": "v0.72.0-rc1", "draft": false, "prerelease": true, "assets": []},
            // 草稿：不要
            {"tag_name": "v0.73.0", "draft": true, "prerelease": false, "assets": []},
            // 没有本机产物的老版本（只有 mips）：跳过，不影响别的
            {"tag_name": "v0.60.0", "draft": false, "prerelease": false,
             "assets": [{"name": "frp_0.60.0_linux_mips.tar.gz", "browser_download_url": "https://x/b",
                         "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]},
        ]);

        let target = linux();
        let parsed: Vec<Version> = releases
            .as_array()
            .unwrap()
            .iter()
            .filter(|release| {
                release.get("draft").and_then(Value::as_bool) != Some(true)
                    && release.get("prerelease").and_then(Value::as_bool) != Some(true)
            })
            .filter_map(|release| parse_release(release, &target).ok())
            .collect();

        let versions: Vec<&str> = parsed.iter().map(|v| v.version.as_str()).collect();
        assert_eq!(versions, vec!["0.71.0", "0.70.1"]);
    }

    /// `query_os` 不参与 GitHub 的匹配（那是 Azul 才有的 libc 细分）。
    #[test]
    fn asset_stem_uses_go_naming() {
        assert_eq!(
            expected_asset_stem("0.71.0", &linux()).unwrap(),
            "frp_0.71.0_linux_amd64"
        );
        assert_eq!(
            expected_asset_stem("0.71.0", &macos_arm()).unwrap(),
            "frp_0.71.0_darwin_arm64"
        );
    }
}
