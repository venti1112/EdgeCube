//! Azul Metadata API —— Zulu 的 JDK / JRE 清单。
//!
//! 两跳：
//!
//! 1. **列表** `GET /zulu/packages/?…` → 每个 Java 大版本一条；
//! 2. **详情** `GET /zulu/packages/{uuid}` → 校验值（`sha256_hash` / `md5_hash`）、
//!    体积、libc 等。
//!
//! **列表里没有校验值**，所以「下什么」这一步必须再问一次详情 —— 这也是我们把
//! 详情与列表分成两个函数、而不是只留一个的原因。
//!
//! 查询参数是**实测**出来的（2026-09-26，Azul Metadata API 1.20.6）：
//!
//! * `os` 要收到 `linux-glibc`：写 `linux` 的话同一个大版本会**多回一份 musl 构建**，
//!   两者在列表里除了文件名以外没有区别字段可辨；
//! * `crac_supported=false` / `crs_supported=false` / `javafx_bundled=false`：
//!   滤掉带 CRaC 与带 JavaFX 的变体（它们也满足「GA + latest」）；
//! * `availability_types=CA`：只要社区免费构建。`SA` 是订阅版，没有凭证下不下来；
//! * `latest=true`：每个大版本只要最新的那个构建，省掉自己比构建号。

use serde::Deserialize;
use serde_json::Value;

use crate::module::builtin::runtime::model::Target;
use crate::util::fetch::{self, FetchError};

const BASE: &str = "https://api.azul.com/metadata/v1/zulu";

/// 一个 Java 大版本下可下载的那一项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    pub java_major: u32,
    /// 完整的 Java 版本号（`21.0.12.1`）。
    pub java_version: String,
    pub package_uuid: String,
}

/// 包详情里我们要的那部分。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Detail {
    pub package_uuid: String,
    pub file_name: String,
    pub java_major: u32,
    pub java_version: String,
    /// 厂商版本号（Zulu 的 `21.52.203`，来自上游的 `distro_version`）。
    pub vendor_version: String,
    pub download_url: String,
    /// **一定有** —— 没有就报错，不做无校验下载。见 [`parse_detail`]。
    pub sha256: String,
    pub md5: Option<String>,
    pub size: Option<u64>,
    pub support_term: Option<String>,
    pub build_date: Option<String>,
}

/// 列表接口的原始形状（`ZuluPkgList`；只留我们要的字段）。
#[derive(Debug, Deserialize)]
struct RawPackage {
    package_uuid: String,
    java_version: Vec<u32>,
}

/// 详情接口的原始形状（`ZuluPkgDetail`；只留我们要的字段）。
#[derive(Debug, Deserialize)]
struct RawDetail {
    package_uuid: String,
    name: String,
    java_version: Vec<u32>,
    #[serde(default)]
    distro_version: Vec<u32>,
    download_url: String,
    #[serde(default)]
    sha256_hash: Option<String>,
    #[serde(default)]
    md5_hash: Option<String>,
    #[serde(default)]
    size: Option<u64>,
    archive_type: String,
    #[serde(default)]
    lib_c_type: Option<String>,
    #[serde(default)]
    support_term: Option<String>,
    #[serde(default)]
    build_date: Option<String>,
}

/// 拼列表请求的 URL。
///
/// 单独一个函数是为了让「我们到底请求了什么」可读、可测 —— 参数写漏一个
/// （比如忘了 `crac_supported=false`）不会报错，只会静静多回几条候选。
pub fn list_url(target: &Target, package_type: &str) -> String {
    format!(
        "{BASE}/packages/?os={}&arch={}&archive_type={}&java_package_type={}\
         &release_status=ga&latest=true\
         &crac_supported=false&crs_supported=false&javafx_bundled=false\
         &availability_types=CA&page_size=100",
        target.query_os, target.arch, target.archive_type, package_type
    )
}

/// 取「每个大版本最新一个构建」的清单，大版本降序。
pub async fn versions(
    http: &reqwest::Client,
    target: &Target,
    package_type: &str,
) -> Result<Vec<Version>, FetchError> {
    let value = fetch::get_value(http, &list_url(target, package_type)).await?;
    parse_versions(&value)
}

/// 解析列表响应。
///
/// 同一个大版本可能回多条（上游的 `latest` 是按「构建」而不是按「大版本」算的），
/// 这里按 **Java 版本号最大** 的那条收敛成一条 —— 不靠响应顺序，也不靠文件名。
pub fn parse_versions(value: &Value) -> Result<Vec<Version>, FetchError> {
    let packages: Vec<RawPackage> = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("azul 包列表不是预期形状：{e}")))?;

    let mut best: Vec<Version> = Vec::new();
    for package in packages {
        let Some(&java_major) = package.java_version.first() else {
            // 没给大版本的条目对我们没用，跳过而不是整体报错
            continue;
        };
        let candidate = Version {
            java_major,
            java_version: dotted(&package.java_version),
            package_uuid: package.package_uuid,
        };
        match best.iter_mut().find(|v| v.java_major == java_major) {
            // `java_version` 是数值分段，逐段比较即「谁更新」
            Some(existing) if newer(&candidate.java_version, &existing.java_version) => {
                *existing = candidate;
            }
            Some(_) => {}
            None => best.push(candidate),
        }
    }

    // 大版本降序（新的在前）—— 上游的顺序不可信，一律自己排
    best.sort_by_key(|version| std::cmp::Reverse(version.java_major));
    Ok(best)
}

/// 取某个包的详情（校验值、体积、目标平台核对）。
pub async fn detail(
    http: &reqwest::Client,
    target: &Target,
    package_uuid: &str,
) -> Result<Detail, FetchError> {
    let value = fetch::get_value(http, &format!("{BASE}/packages/{package_uuid}")).await?;
    parse_detail(&value, target)
}

/// 解析包详情。
///
/// 这里做三件**防御性**的事，都是「宁可在装之前失败」的那类：
///
/// * 上游回的 `archive_type` / `lib_c_type` 必须与我们请求的目标平台一致 ——
///   查询参数写错时上游不会报错，只会给一份别的平台的包（Linux 上尤其容易拿到
///   musl 或 Windows 的包），那种包解开也跑不起来；
/// * **必须有 `sha256_hash`**：没有校验值的 200 MB 下载我们不做 ——
///   上面那两条本可以由校验值兜底，这里反过来，用「必须有校验值」兜住一切。
pub fn parse_detail(value: &Value, target: &Target) -> Result<Detail, FetchError> {
    let raw: RawDetail = serde_json::from_value(value.clone())
        .map_err(|e| FetchError::Parse(format!("azul 包详情不是预期形状：{e}")))?;

    if raw.archive_type != target.archive_type {
        return Err(FetchError::Parse(format!(
            "上游给的包是 `{}`，我们要的是 `{}`（查询参数与目标平台不一致）",
            raw.archive_type, target.archive_type
        )));
    }
    if let (Some(expected), Some(got)) = (target.libc, raw.lib_c_type.as_deref())
        && expected != got
    {
        return Err(FetchError::Parse(format!(
            "上游给的包是 {got} 构建，我们要的是 {expected}"
        )));
    }
    let Some(sha256) = raw.sha256_hash.filter(|s| !s.trim().is_empty()) else {
        return Err(FetchError::Parse(format!(
            "上游没给 `{}` 的 sha256，拒绝无校验下载",
            raw.name
        )));
    };

    let java_major = raw.java_version.first().copied().unwrap_or(0);
    Ok(Detail {
        package_uuid: raw.package_uuid,
        file_name: raw.name,
        java_major,
        java_version: dotted(&raw.java_version),
        vendor_version: trimmed_dotted(&raw.distro_version),
        download_url: raw.download_url,
        sha256: sha256.to_ascii_lowercase(),
        md5: raw.md5_hash.map(|s| s.to_ascii_lowercase()),
        size: raw.size,
        support_term: raw.support_term,
        build_date: raw.build_date,
    })
}

// ---------------------------------------------------------------------------
// 小工具（都是纯函数）
// ---------------------------------------------------------------------------

/// `[21, 0, 12, 1]` → `21.0.12.1`。
pub fn dotted(parts: &[u32]) -> String {
    parts
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(".")
}

/// 把末尾的 0 去掉：`[21, 52, 203, 0]` → `21.52.203`。
///
/// Zulu 的 `distro_version` 最后一位是补位的构建号（实测 `21.52.203.0`，
/// 但对外叫法是 `21.52.203`）。全 0 的退化情况保一位，别变成空串。
pub fn trimmed_dotted(parts: &[u32]) -> String {
    let mut end = parts.len();
    while end > 1 && parts[end - 1] == 0 {
        end -= 1;
    }
    dotted(&parts[..end])
}

/// `a` 是不是比 `b` 新（按 `.` 分段做数值比较）。
fn newer(a: &str, b: &str) -> bool {
    let keys = |s: &str| -> Vec<u32> {
        s.split('.')
            .map(|part| part.parse::<u32>().unwrap_or(0))
            .collect()
    };
    keys(a) > keys(b)
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

    /// 实测抓下来的 `GET /zulu/packages/?os=linux-glibc&…&java_version=21`（截断）。
    fn real_list() -> Value {
        json!([
            {
                "availability_type": "CA",
                "distro_version": [21, 52, 203, 0],
                "download_url": "https://cdn.azul.com/zulu/bin/zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz",
                "java_version": [21, 0, 12, 1],
                "latest": true,
                "name": "zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz",
                "openjdk_build_number": 1,
                "package_uuid": "bb912db2-5f50-4baa-818c-65f7f55d1b0e",
                "product": "zulu"
            },
            {
                "java_version": [17, 0, 16, 0],
                "latest": true,
                "name": "zulu17.66.19-ca-jdk17.0.16-linux_x64.tar.gz",
                "package_uuid": "11111111-2222-3333-4444-555555555555",
                "product": "zulu"
            }
        ])
    }

    /// 实测抓下来的 `GET /zulu/packages/{uuid}`（只留我们读的字段，值都是真的）。
    fn real_detail() -> Value {
        json!({
            "abi": "any",
            "arch": "x86",
            "archive_type": "tar.gz",
            "availability_type": "CA",
            "build_date": "2026-08-03T21:40:48",
            "crac_supported": false,
            "distro_version": [21, 52, 203, 0],
            "download_url": "https://cdn.azul.com/zulu/bin/zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz",
            "hw_bitness": 64,
            "java_package_type": "jdk",
            "java_version": [21, 0, 12, 1],
            "javafx_bundled": false,
            "lib_c_type": "glibc",
            "md5_hash": "6a26af74ea317e6ded71317fe507f13f",
            "name": "zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz",
            "os": "linux",
            "package_uuid": "bb912db2-5f50-4baa-818c-65f7f55d1b0e",
            "product": "zulu",
            "sha256_hash": "DB0C11E13B545E64D520B4821F4CA38EA9BC1C515924EB1E7F48435DF101F183",
            "size": 213089000,
            "support_term": "lts"
        })
    }

    #[test]
    fn list_url_pins_every_param_that_keeps_candidates_unique() {
        let url = list_url(&linux(), "jdk");
        // 这五个参数少一个就会多回候选：os 不收到 glibc 会多一份 musl；
        // 三个 false 会放过 CRaC / JavaFX 变体；availability_types 会把订阅版也带回来
        for expected in [
            "os=linux-glibc",
            "arch=x64",
            "archive_type=tar.gz",
            "java_package_type=jdk",
            "release_status=ga",
            "latest=true",
            "crac_supported=false",
            "crs_supported=false",
            "javafx_bundled=false",
            "availability_types=CA",
        ] {
            assert!(url.contains(expected), "URL 里少了 `{expected}`：{url}");
        }
    }

    #[test]
    fn versions_are_grouped_by_major_and_sorted_descending() {
        let versions = parse_versions(&real_list()).expect("应当能解析");
        assert_eq!(
            versions.iter().map(|v| v.java_major).collect::<Vec<_>>(),
            vec![21, 17],
            "大版本降序"
        );
        assert_eq!(versions[0].java_version, "21.0.12.1");
        assert_eq!(
            versions[0].package_uuid,
            "bb912db2-5f50-4baa-818c-65f7f55d1b0e"
        );
    }

    #[test]
    fn versions_keep_the_newest_build_of_a_major() {
        // 同一个大版本回多条时，收敛到 java 版本号最大的那条（不靠响应顺序）
        let value = json!([
            { "package_uuid": "old", "java_version": [21, 0, 11] },
            { "package_uuid": "new", "java_version": [21, 0, 12, 1] },
            { "package_uuid": "mid", "java_version": [21, 0, 12] },
        ]);
        let versions = parse_versions(&value).expect("应当能解析");
        assert_eq!(versions.len(), 1);
        assert_eq!(versions[0].package_uuid, "new");
        assert_eq!(versions[0].java_version, "21.0.12.1");
    }

    #[test]
    fn versions_skip_entries_without_a_major() {
        let value = json!([{ "package_uuid": "x", "java_version": [] }]);
        assert!(parse_versions(&value).unwrap().is_empty());
    }

    #[test]
    fn detail_reads_checksums_and_normalizes_case() {
        let detail = parse_detail(&real_detail(), &linux()).expect("应当能解析");
        assert_eq!(detail.java_major, 21);
        assert_eq!(detail.java_version, "21.0.12.1");
        assert_eq!(detail.vendor_version, "21.52.203", "Zulu 的对外版本号");
        assert_eq!(
            detail.file_name,
            "zulu21.52.203-ca-jdk21.0.12.1-linux_x64.tar.gz"
        );
        assert_eq!(detail.size, Some(213089000));
        assert_eq!(detail.support_term.as_deref(), Some("lts"));
        // 统一小写：`download.add` 那边就是这么比的
        assert_eq!(
            detail.sha256,
            "db0c11e13b545e64d520b4821f4ca38ea9bc1c515924eb1e7f48435df101f183"
        );
        assert_eq!(
            detail.md5.as_deref(),
            Some("6a26af74ea317e6ded71317fe507f13f")
        );
    }

    #[test]
    fn detail_refuses_a_package_for_another_platform() {
        // 查询参数写错时上游不报错，只会给别的平台的包 —— 必须在这里拦住
        let mut musl = real_detail();
        musl["lib_c_type"] = json!("musl");
        let err = parse_detail(&musl, &linux()).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");

        let mut zip = real_detail();
        zip["archive_type"] = json!("zip");
        let err = parse_detail(&zip, &linux()).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
    }

    #[test]
    fn detail_refuses_a_package_without_a_checksum() {
        let mut no_hash = real_detail();
        no_hash["sha256_hash"] = json!(null);
        let err = parse_detail(&no_hash, &linux()).unwrap_err();
        assert!(matches!(err, FetchError::Parse(_)), "{err:?}");
        assert!(format!("{err}").contains("sha256"), "{err}");
    }

    #[test]
    fn dotted_renders_versions() {
        assert_eq!(dotted(&[21, 0, 12, 1]), "21.0.12.1");
        assert_eq!(dotted(&[8]), "8");
        assert_eq!(trimmed_dotted(&[21, 52, 203, 0]), "21.52.203");
        assert_eq!(trimmed_dotted(&[8, 0, 0]), "8");
        // 退化情况别给出空串
        assert_eq!(trimmed_dotted(&[0, 0]), "0");
        assert_eq!(trimmed_dotted(&[]), "");
    }
}
