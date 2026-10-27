//! 运行环境的厂商表、目标平台、以及落盘 / 线上共用的那份模型。
//!
//! 「有哪些厂商、包类型叫什么、装到哪个平台」都是**编译期常量**：这些口径要跟着
//! 上游演进（Azul 改名、加包类型），做成配置只会让「配错了但没人知道」变成常态。
//! 与 `mcserver/model.rs` 是同一条取舍。

use serde::{Deserialize, Serialize};

/// 「解压完之后去哪儿找那个能跑的文件」。
///
/// 各家的包布局不一样，但形状就两种（实测确认）：
///
/// * **Zulu JDK** —— `…/bin/java`，压缩包里套一层版本目录，macOS 还多两层
///   （`zulu-21.jdk/Contents/Home`）。所以是「往下找 `bin/java`」。
/// * **frp** —— 压缩包顶层目录里直接躺着 `frpc`（还有 `frps`）。
///   没有 `bin/` 这一层，所以 `sub_dir` 是空串。
///
/// 放在厂商表里而不是写死在解压代码里：加厂商要填的列就该集中在一处。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Launcher {
    /// 相对「找到的那一层」的子目录；空串 = 就在那一层。
    pub sub_dir: &'static str,
    /// 候选文件名，按平台习惯排序（Windows 那份排前面）。
    pub names: &'static [&'static str],
}

/// 一个可下载的运行环境厂商。
///
/// 加第二个厂商（Temurin / Corretto / 别家的 frp 分发）要填的就是这几列 ——
/// 厂商特定的代码只有 [`api`](super::api) 下那个适配器，别的都走通用路径。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Provider {
    pub id: &'static str,
    pub name: &'static str,
    pub homepage: &'static str,
    /// 支持的包类型。**顺序即展示顺序**。
    pub package_types: &'static [&'static str],
    /// 解压后去哪儿找可执行文件。
    pub launcher: Launcher,
    /// 版本主行的显示前缀。
    ///
    /// Zulu 的版本号是 `21` 这种裸数字，主行要写成「Java 21」才认得出来；
    /// frp 的 `0.71.0` 本身就是完整的说法，前缀留空。
    /// 拼在前端最容易，但那样等于把「哪个厂商的版本号长什么样」写进 UI ——
    /// 所以放在这张表里，前端只负责显示 `label`。
    pub version_prefix: &'static str,
}

/// 包类型：JDK 还是 JRE。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct PackageType {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
}

pub const PROVIDERS: &[Provider] = &[
    Provider {
        id: "zulu",
        name: "Zulu",
        homepage: "https://www.azul.com/downloads/",
        // 只上 JDK：这是装服务端最常用的那一档，也是用户明确要的。
        // 加 `jre` 只需要在这里补一个字符串 —— 下游（查询参数、id、解压）都不区分。
        package_types: &["jdk"],
        launcher: Launcher {
            sub_dir: "bin",
            #[cfg(windows)]
            names: &["java.exe", "java"],
            #[cfg(not(windows))]
            names: &["java", "java.exe"],
        },
        version_prefix: "Java ",
    },
    Provider {
        id: "frp",
        name: "frp",
        homepage: "https://github.com/fatedier/frp",
        // 一个版本一个包，压缩包里 `frpc` 与 `frps` 都在（实测确认）。
        // 只列 `frpc` 是因为**用到的是它**：映射隧道跑的是客户端。
        // 将来真要做「自建 frps 服务端」再在这里补一个 `frps` —— 同一份包，
        // 只是挑的可执行文件不同。
        package_types: &["frpc"],
        launcher: Launcher {
            // frp 的包顶层就是那几个文件，没有 `bin/` 这一层
            sub_dir: "",
            #[cfg(windows)]
            names: &["frpc.exe", "frpc"],
            #[cfg(not(windows))]
            names: &["frpc", "frpc.exe"],
        },
        version_prefix: "",
    },
];

pub const PACKAGE_TYPES: &[PackageType] = &[
    PackageType {
        id: "jdk",
        name: "JDK",
        description: "开发工具包，含 javac 等工具；跑服务端用它",
    },
    PackageType {
        id: "jre",
        name: "JRE",
        description: "只含运行时，体积更小（本轮未开放下载）",
    },
    PackageType {
        id: "frpc",
        name: "frp 客户端",
        description: "内网穿透客户端；同一个包里也带 frps（自建服务端用）",
    },
];

pub fn find_provider(id: &str) -> Option<&'static Provider> {
    PROVIDERS.iter().find(|p| p.id == id)
}

pub fn find_package_type(id: &str) -> Option<&'static PackageType> {
    PACKAGE_TYPES.iter().find(|p| p.id == id)
}

/// 默认包类型（前端不传时用）。
pub const DEFAULT_PACKAGE_TYPE: &str = "jdk";

// ---------------------------------------------------------------------------
// 目标平台
// ---------------------------------------------------------------------------

/// 要装的环境跑在哪个平台上。
///
/// **只有「本机」这一种**：daemon 与它下的 JDK 在同一台机器上，实例也是在这儿跑的。
/// 做成可选只会给出一个当下没人用的功能，还多一条「装了别的平台的包」的出错路径。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Target {
    /// 进 id 的短名（`linux` / `windows` / `macos`）。
    pub os: &'static str,
    /// 上游查询用的 os —— Linux 要细分 libc，否则会同时回 glibc 与 musl 两份。
    pub query_os: &'static str,
    /// 进 id 的短名（`x64` / `aarch64`）。
    pub arch: &'static str,
    pub archive_type: &'static str,
    /// 期望的 libc（只有 Linux 有）。拿到包详情时会核对一次，见 `api::azul`。
    pub libc: Option<&'static str>,
}

/// 本机平台；不支持的机器返回 `None`（调用方报 `runtime_unsupported_host`）。
pub fn host_target() -> Option<Target> {
    let (os, query_os, archive_type, libc) = match std::env::consts::OS {
        "linux" => ("linux", "linux-glibc", "tar.gz", Some("glibc")),
        "macos" => ("macos", "macos", "tar.gz", None),
        "windows" => ("windows", "windows", "zip", None),
        _ => return None,
    };
    let arch = match std::env::consts::ARCH {
        "x86_64" => "x64",
        "aarch64" => "aarch64",
        _ => return None,
    };
    Some(Target {
        os,
        query_os,
        arch,
        archive_type,
        libc,
    })
}

/// 环境的 id：`zulu-jdk-21-linux-x64`、`frp-frpc-0.71.0-linux-x64`。
///
/// **可读且稳定**，不用随机 id：一个「厂商 + 包类型 + 版本 + 平台」组合只该有一个
/// 环境，再装就是覆盖重装。随机 id 会让列表里出现两个「Zulu JDK 21」而用户分不清，
/// 而以组合为 id 时，同名即同物。
///
/// `version` 是**字符串**而不是数字：JDK 是 `21`，frp 是 `0.71.0`（semver）。
/// 两边都要能进 id，所以统一按上游的说法收下来。
pub fn env_id(vendor: &str, package_type: &str, version: &str, target: &Target) -> String {
    format!(
        "{vendor}-{package_type}-{version}-{}-{}",
        target.os, target.arch
    )
}

// ---------------------------------------------------------------------------
// 环境状态与落盘 / 线上共用的模型
// ---------------------------------------------------------------------------

/// 一个环境的生命周期。
///
/// `downloading` 与 `extracting` 是**进行中**的中间态 —— 它们会被记进元数据，
/// 所以 UI 关掉再打开仍然看得到「正在装」。daemon 重启时这两个状态会被判定为
/// `failed`（下载队列不持久化，重启后那个任务已经不存在了，见模块头注释）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnvState {
    Downloading,
    Extracting,
    Installed,
    Failed,
}

impl EnvState {
    /// 正在装（有后台任务在跑）。
    pub fn is_busy(self) -> bool {
        matches!(self, Self::Downloading | Self::Extracting)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Downloading => "downloading",
            Self::Extracting => "extracting",
            Self::Installed => "installed",
            Self::Failed => "failed",
        }
    }
}

/// 失败发生在哪一步。重试时据此决定要不要重新下载。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Stage {
    Download,
    Extract,
}

/// 一个运行环境。**落盘与线上是同一份形状**。
///
/// 实例那边落盘用 camelCase、线上用 snake_case，是为了兼容旧数据；
/// 运行环境是新东西，没有历史包袱，所以两边统一 snake_case，少一层心智负担。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Env {
    pub id: String,
    pub vendor: String,
    pub package_type: String,
    /// 装的是哪个版本：JDK 是 `21`（大版本），frp 是 `0.71.0`。
    /// **进 id、也是版本选择时用户看到的那一项**。
    pub version: String,
    /// 更完整的上游版本串（列表 / 详情的副标题）：
    /// JDK 的 `21.0.12.1`；frp 上游只有一个版本号，与 `version` 相同。
    pub version_name: String,
    /// 厂商自己的版本号（Zulu 的 `21.52.203`）。frp 没有这一层，空串。
    #[serde(default)]
    pub vendor_version: String,
    pub os: String,
    pub arch: String,
    pub archive_type: String,

    /// 上游的包 id、文件名、下载地址 —— 重装 / 排查时用得上。
    pub package_uuid: String,
    pub file_name: String,
    pub url: String,
    /// 上游给的校验值。**下载前就拿到**，所以能给队列当校验要求用。
    pub sha256: Option<String>,
    pub md5: Option<String>,
    pub size: Option<u64>,
    pub support_term: Option<String>,
    pub build_date: Option<String>,

    pub state: EnvState,
    /// 只在 `failed` 时有意义。
    #[serde(default)]
    pub stage: Option<Stage>,
    #[serde(default)]
    pub error: Option<String>,

    /// 下载任务 id。前端拿它去订阅 `download.progress` 看进度，
    /// 也让我们能把这条任务和这个环境对上。
    #[serde(default)]
    pub task_id: Option<String>,

    /// 解压出来的「家目录」与可执行文件（**相对环境目录**）。
    ///
    /// 相对而不是绝对：数据根搬家（改 `dir` 配置）之后仍然是对的。
    /// 具体是什么由厂商决定：JDK 是 `…/bin/java`（家目录即 `JAVA_HOME`），
    /// frp 是包里的 `frpc`（家目录就是它所在的那一层）。
    #[serde(default)]
    pub home: Option<String>,
    #[serde(default)]
    pub binary: Option<String>,

    pub created_at_ms: u64,
    #[serde(default)]
    pub installed_at_ms: Option<u64>,
    pub updated_at_ms: u64,
}

impl Env {
    /// 给人看的一句话（前端拼标题用；也是 daemon 日志里的说法）。
    pub fn label(&self) -> String {
        format!(
            "{} {}（{}）",
            self.vendor.to_uppercase(),
            self.package_type.to_uppercase(),
            self.version_name
        )
    }
}
