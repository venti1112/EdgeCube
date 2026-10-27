//! 模组 / 插件的中立模型与编译期常量表。
//!
//! 「有哪些平台、哪些加载器、装到哪个目录」全是**编译期常量**，理由与
//! `mcserver/model.rs` 一致：这些口径要跟着上游演进，做成配置只会让
//! 「配错了但没人知道」变成常态。
//!
//! 本轮只有 Modrinth 一个源。**加源时这里只多一行 `SOURCES`，前端零改动** ——
//! 这正是 `mods.sources` 存在的意义（前端不硬编码平台名，与 `mcserver.types`
//! 同一个套路）。

use serde::Serialize;

/// 一个「项目类型」。Modrinth 的 `project_type` 取值很多，这里只暴露
/// 服务端场景用得上的两个。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct ProjectType {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    /// 落到实例目录的哪个子目录。**按项目类型自动定**，不让用户选：
    /// 选错了（把插件丢进 `mods/`）服务端只会静默不加载，是最难查的一类问题。
    pub dir: &'static str,
    /// 这种类型下可筛的加载器 id，顺序即展示顺序。
    pub loaders: &'static [&'static str],
}

/// 项目类型表。顺序即前端展示顺序。
///
/// **每个类型的 `loaders` 就是「筛选器里能选到什么」** —— 两张表必须分开：
/// 插件那一栏绝不能出现 Fabric / Forge，模组那一栏也不该出现 Paper。
pub const PROJECT_TYPES: &[ProjectType] = &[
    ProjectType {
        id: "mod",
        name: "模组",
        description: "装到 mods/，需要 Fabric / NeoForge 这类模组加载器",
        dir: "mods",
        loaders: &["fabric", "forge", "quilt", "neoforge"],
    },
    ProjectType {
        id: "plugin",
        name: "插件",
        description: "装到 plugins/，面向 Bukkit 系插件服务端与代理",
        dir: "plugins",
        loaders: &[
            "paper",
            "spigot",
            "bukkit",
            "bungeecord",
            "velocity",
            "waterfall",
            "folia",
            "purpur",
        ],
    },
];

/// 一个加载器。`id` 直接用 Modrinth 的说法（它在搜索里把加载器也放在
/// `categories` 这个 facet 下），我们不做二次映射。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Loader {
    pub id: &'static str,
    pub name: &'static str,
}

/// 加载器表。
pub const LOADERS: &[Loader] = &[
    Loader {
        id: "fabric",
        name: "Fabric",
    },
    Loader {
        id: "neoforge",
        name: "NeoForge",
    },
    Loader {
        id: "forge",
        name: "Forge",
    },
    Loader {
        id: "quilt",
        name: "Quilt",
    },
    Loader {
        id: "paper",
        name: "Paper",
    },
    Loader {
        id: "purpur",
        name: "Purpur",
    },
    Loader {
        id: "folia",
        name: "Folia",
    },
    Loader {
        id: "spigot",
        name: "Spigot",
    },
    Loader {
        id: "bukkit",
        name: "Bukkit",
    },
    Loader {
        id: "velocity",
        name: "Velocity",
    },
    Loader {
        id: "bungeecord",
        name: "BungeeCord",
    },
    Loader {
        id: "waterfall",
        name: "Waterfall",
    },
];

/// 一个游戏版本（上游 `/tag/game_version` 的一项）。
///
/// **带类型**：游戏版本菜单里正式版在前、其余（快照 / beta / alpha）在后，
/// 非正式版的副标题写的就是这个 `version_type`。所以这里不能只给正式版。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct GameVersion {
    pub version: String,
    /// `release` / `snapshot` / `beta` / `alpha`。
    pub version_type: String,
}

/// 排序方式。`id` 就是 Modrinth `search` 的 `index` 参数值。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct SortKind {
    pub id: &'static str,
    pub name: &'static str,
}

/// 排序表。`relevance` 在有搜索词时才有意义（上游对空 `query` 也能接受，
/// 此时它退化成「综合」），所以前端在空搜索词时可以默认选 `downloads`。
pub const SORTS: &[SortKind] = &[
    SortKind {
        id: "relevance",
        name: "相关度",
    },
    SortKind {
        id: "downloads",
        name: "下载量",
    },
    SortKind {
        id: "follows",
        name: "关注数",
    },
    SortKind {
        id: "newest",
        // 排序名的措辞是「最新创建」，不是「最新发布」
        name: "最新创建",
    },
    SortKind {
        id: "updated",
        name: "最近更新",
    },
];

/// 一个下载源。前端拿它渲染「来自哪个平台」，不做硬编码。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Source {
    pub id: &'static str,
    pub name: &'static str,
    /// 项目主页（前端「在浏览器打开」用）。
    pub url: &'static str,
    /// 支持的搜索排序 id（各源不一定支持同一批）。
    pub sorts: &'static [&'static str],
}

/// 源表。本轮只有 Modrinth。
///
/// **取 `pub const` 而不是写进配置文件**：源的接口地址与查询语法是代码的一部分，
/// 用户可配的只有「缓存多久、超时多少」这类调度参数。
pub const SOURCES: &[Source] = &[Source {
    id: "modrinth",
    name: "Modrinth",
    url: "https://modrinth.com",
    sorts: &["relevance", "downloads", "follows", "newest", "updated"],
}];

/// 认哪些文件是「模组 / 插件」。
///
/// `.jar`（Java 系）与 `.phar`（PocketMine-MP）—— 按实例是不是 PHP 分派
/// （PHP 实例认 `.phar`，否则认 `.jar`）。
/// **目录是分开的**（插件在 `plugins/`），所以两类文件不会混在同一个目录里被误认。
pub const FILE_EXTS: &[&str] = &["jar", "phar"];

/// 「禁用」怎么表达：在文件名后面接这个后缀。
///
/// **用改名而不是搬家**：与服务端的加载行为一致（它只认 `*.jar`），
/// 且用户自己用文件管理器也能看懂、也能手工改回来。
pub const DISABLED_SUFFIX: &str = ".disabled";

/// 按 id 找一个项目类型。
pub fn find_project_type(id: &str) -> Option<&'static ProjectType> {
    PROJECT_TYPES.iter().find(|entry| entry.id == id)
}

/// 项目类型 id 列表（报错时提示「可选的有哪些」）。
pub fn project_type_ids() -> Vec<&'static str> {
    PROJECT_TYPES.iter().map(|entry| entry.id).collect()
}

/// 项目类型 → 实例内的子目录。
pub fn dir_of(project_type: &str) -> Option<&'static str> {
    find_project_type(project_type).map(|entry| entry.dir)
}

/// 这个加载器是否属于这个项目类型（用于拦「给插件选 fabric」这种组合）。
pub fn loader_supported(project_type: &str, loader: &str) -> bool {
    find_project_type(project_type)
        .map(|entry| entry.loaders.contains(&loader))
        .unwrap_or(false)
}

/// 按 id 找一个加载器。
pub fn find_loader(id: &str) -> Option<&'static Loader> {
    LOADERS.iter().find(|entry| entry.id == id)
}

/// 按 id 找一个排序方式。
pub fn find_sort(id: &str) -> Option<&'static SortKind> {
    SORTS.iter().find(|entry| entry.id == id)
}

/// 按 id 找一个源。
pub fn find_source(id: &str) -> Option<&'static Source> {
    SOURCES.iter().find(|entry| entry.id == id)
}

/// 源 id 列表（报错时提示）。
pub fn source_ids() -> Vec<&'static str> {
    SOURCES.iter().map(|entry| entry.id).collect()
}

// ---------------------------------------------------------------------------
// 上游数据的中立模型
// ---------------------------------------------------------------------------
//
// 每个源把自己的响应映射成下面这几个结构，前端与工作流只依赖它们 ——
// **加第二个源时不用动这里的任何字段**，谁的字段给不出来就留 `None`。

/// 一条搜索结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Hit {
    /// 来自哪个源（[`SOURCES`] 的 id）。
    pub source: &'static str,
    pub project_id: String,
    pub slug: String,
    pub title: String,
    pub description: String,
    pub author: Option<String>,
    pub icon_url: Option<String>,
    pub downloads: u64,
    /// 关注数。**注意上游两个接口的字段名不同**：搜索命中叫 `follows`，
    /// 项目详情叫 `followers`（实测，见 `api/modrinth.rs` 的测试）。
    pub follows: u64,
    /// 上游给的全部分类（含加载器）。
    pub categories: Vec<String>,
    /// 项目类型（`mod` / `plugin` / …）。
    pub project_type: String,
    /// 从 `categories` 里挑出来的、我们认识的加载器。
    pub loaders: Vec<String>,
    /// 项目最新的版本 id（点击进版本页时用来定位，不必额外打一次上游）。
    pub latest_version: Option<String>,
    /// 这个项目在**服务端**能不能跑：`required` / `optional` / `unsupported` /
    /// `unknown`。
    ///
    /// 这是装模组时最容易踩的坑（客户端专属的优化模组装到服务端只是白占地方，
    /// 装错了还可能让服务端起不来），所以上游既然给了就一定带上 ——
    /// 有现成的字段，不必再扫 jar 元数据去猜。
    pub server_side: Option<String>,
    /// 项目主页，供「在浏览器打开」。
    pub page_url: String,
}

impl Hit {
    /// 是不是客户端专属（装到服务端没有意义）。
    pub fn is_client_only(&self) -> bool {
        self.server_side.as_deref() == Some("unsupported")
    }
}

/// 一页搜索结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Page {
    pub hits: Vec<Hit>,
    pub total: u64,
    pub offset: u64,
    pub limit: u64,
}

impl Page {
    /// 后面还有没有（前端据此决定要不要继续翻页）。
    pub fn has_more(&self) -> bool {
        self.offset + (self.hits.len() as u64) < self.total
    }
}

/// 一个可下载的文件。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FileEntry {
    pub url: String,
    pub filename: String,
    pub size: u64,
    /// 上游给的 sha1（Modrinth 一定给，所以我们一定校验）。
    pub sha1: Option<String>,
    /// 上游标记的「主文件」。一个版本通常只有一个文件。
    pub primary: bool,
}

/// 一条依赖。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Dependency {
    pub project_id: Option<String>,
    pub version_id: Option<String>,
    /// 依赖项目的文件名（上游会直接给，省一次查询）。
    pub file_name: Option<String>,
    /// `required` / `optional` / `incompatible` / `embedded`。
    pub kind: String,
}

/// 上游的一个版本。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct VersionEntry {
    pub id: String,
    pub project_id: String,
    /// 展示名（如「Sodium 0.7.3 for Fabric 1.21.8」）。
    pub name: String,
    /// 版本号。
    pub version_number: String,
    /// `release` / `beta` / `alpha`。
    pub kind: String,
    pub game_versions: Vec<String>,
    pub loaders: Vec<String>,
    /// ISO 8601 原文，前端自己格式化（daemon 不做本地化）。
    pub date_published: String,
    pub files: Vec<FileEntry>,
    pub dependencies: Vec<Dependency>,
}

impl VersionEntry {
    /// 该下哪个文件：优先上游标了 `primary` 的那个，否则取第一个。
    pub fn primary_file(&self) -> Option<&FileEntry> {
        self.files
            .iter()
            .find(|file| file.primary)
            .or_else(|| self.files.first())
    }

    pub fn is_release(&self) -> bool {
        self.kind == "release"
    }
}

/// 一次更新检查的结果（一个已装文件对应一条）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct UpdateCheck {
    /// 已装文件的基名（前端拿它和已装列表对齐）。
    pub file_name: String,
    /// 这个文件的 sha1。
    pub sha1: Option<String>,
    /// 上游认不认识这个文件。
    pub known: bool,
    /// 有没有更新。`known` 为 `false` 时恒为 `false`。
    pub has_update: bool,
    /// 上游给出的「当前筛选条件下的最新版本」。没查到就是 `None`。
    pub latest: Option<VersionEntry>,
}

/// 上游项目的一句摘要。
///
/// 现在的用途只有一个：**给已装文件配图标** —— 算 SHA1 → 反查项目 →
/// 拿 `icon_url`，图标是列表左侧那个 40×40 的方块（拿不到就退回按加载器上色）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProjectRef {
    pub project_id: String,
    pub slug: String,
    pub title: String,
    pub icon_url: Option<String>,
    pub project_type: String,
    pub page_url: String,
}

/// `mods.match_projects` 的一条：一个已装文件对回了哪个上游项目。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Match {
    /// 已装文件名（**前端拿它当主键**，与 `mods.installed` 的键一致）。
    pub file_name: String,
    pub sha1: Option<String>,
    /// 上游认不认识这个文件。`false` = 不是从上游装的（手放的、或项目被删了）。
    pub known: bool,
    pub project: Option<ProjectRef>,
}

// ---------------------------------------------------------------------------
// 已装文件
// ---------------------------------------------------------------------------
/// 一个已装的模组 / 插件文件。
///
/// 字段名走**线上那套 snake_case**（`to_wire_value` 风格）—— 这个结构只经 WS
/// 出去，不落盘，所以没有「两套序列化」的问题。
#[derive(Debug, Clone, Serialize)]
pub struct Installed {
    /// 文件名。禁用过的带 `.disabled` 后缀 —— 前端要拿它当**主键**用
    /// （同一目录里不会有重名），不能只用「基名」。
    pub file_name: String,
    /// 显示用名字（去掉了 `.disabled`）。
    pub base_name: String,
    pub enabled: bool,
    pub size: u64,
    /// 文件修改时间（毫秒时间戳）。
    pub modified_ms: i64,
    /// 从 jar 里读到的元数据。读不出来时为 `null`（不是错误：很多老插件
    /// 就是没有可识别的元数据文件）。
    pub meta: Option<Meta>,
}

/// jar 里读到的元数据。
///
/// 页面上的主行/副行/加载器标签/「客户端专属」都从这几个字段来，
/// 少一个就得让前端去猜。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Meta {
    /// 加载器视角的 mod / plugin id。
    pub id: Option<String>,
    /// 展示名。
    pub name: Option<String>,
    /// 版本号。
    pub version: Option<String>,
    /// 描述（列表副行的第二行）。
    pub description: Option<String>,
    /// 作者（`a, b` 拼好的）。
    pub authors: Option<String>,
    /// 主页 / 源码地址。
    pub url: Option<String>,
    /// 从哪种元数据文件读出来的（`fabric.mod.json` / `plugin.yml` / …）。
    ///
    /// 前端可以据此提示「这个 jar 看起来是 Fabric 的，但你装的是 NeoForge」。
    pub from: String,
    /// 加载器：`fabric` / `forge` / `quilt` / `neoforge` / `bukkit` /
    /// `bungeecord` / `velocity` / `pocketmine` / `unknown`。
    ///
    /// 由**读到哪个元数据文件**决定（不是猜内容）。
    /// 展示名（含把 `bukkit` 显示成「Plugin」）留在前端 —— 那是文案。
    pub loader: &'static str,
    /// 运行环境：`client` / `server` / `both` / `unknown`。
    ///
    /// 「客户端专属模组清理」的依据就是这个字段。**归一化规则如下**
    /// （每一条都是踩过的坑，见 `installed.rs` 的测试）：
    ///
    /// * Fabric 的 `environment`：`client` → client、`server` → server、
    ///   **其余（含缺失、`*`、`client,server`）→ both**；
    /// * Quilt 的 `environment`：`client` → client、`dedicated_server` → server、
    ///   其余 → both（注意它服务端的写法与 Fabric 不同）；
    /// * Forge / NeoForge 的顶层 `clientSideOnly`：缺失 → **unknown**（不是 both！）、
    ///   `true` → client、其余 → both。缺失判 unknown 是为了**不误删**服务端模组；
    /// * 插件系（plugin.yml / bungee.yml / velocity）不声明侧别 → unknown。
    pub environment: &'static str,
}

impl Meta {
    /// 是不是客户端专属（不能在服务端跑）。
    pub fn is_client_only(&self) -> bool {
        self.environment == "client"
    }
}
