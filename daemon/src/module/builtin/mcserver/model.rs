//! 服务端类型表与对外模型。
//!
//! 这一层全是**编译期常量**：有哪些服务端、文件叫什么、启动命令写什么、
//! 上游能给哪种校验 —— 都写死在代码里。上游地址变了就得改代码，这是故意的：
//! 这些源的口径（文件名、启动参数）要跟着版本演进，做成配置只会让「配错了
//! 但没人知道」变成常态。

use serde::Serialize;

/// 一个服务端分类（前端第一层要选的东西）。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Category {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    /// 这个分类下的类型 id，**顺序即展示顺序**。
    pub types: &'static [&'static str],
}

/// 一个可下载的服务端类型。
#[derive(Debug, Clone, Copy, Serialize)]
pub struct ServerType {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    /// 所属分类 id。
    pub category: &'static str,
    /// 落盘文件名。**别随手改**：用户可能已经按这个名字写了启动命令。
    pub file_name: &'static str,
    /// 建议的启动命令。V2 的实例只有一条 `startupCommand`，所以这里直接给一条
    /// 能跑的；用户之后可以在「实例设置」里改。
    pub startup_command: &'static str,
    /// 这个源能提供哪种校验：`sha256` / `md5` / `sha1` / `none`。
    /// **取值直接就是 `download.add` 的参数名**，前端拿到 `plan` 的 checksum
    /// 可以原样透传，不用做映射表。
    pub checksum: &'static str,
    /// 版本页要不要先选一个版本（BungeeCord 没有版本概念，只有 latest）。
    pub needs_version: bool,
    /// 还要不要再选一个「加载器版本」（本轮只有 Fabric）。
    pub needs_loader: bool,
}

/// 分类表。顺序即前端展示顺序。
pub const CATEGORIES: &[Category] = &[
    Category {
        id: "vanilla",
        name: "原版",
        description: "Mojang 官方服务端，没有插件与模组支持",
        types: &["vanilla"],
    },
    Category {
        id: "plugin",
        name: "插件服务端",
        description: "支持 Bukkit 系插件",
        // 顺序：PaperMC 官方的两个（paper / folia）在前，第三方分支在后
        types: &["paper", "folia", "purpur", "leaf", "leaves"],
    },
    Category {
        id: "mod",
        name: "模组服务端",
        description: "支持模组（本轮只有 Fabric）",
        types: &["fabric"],
    },
    Category {
        id: "proxy",
        name: "代理服务端",
        description: "群组服转发，不承载世界",
        types: &["velocity", "bungeecord"],
    },
];

/// 类型表。
///
/// `checksum` 一列是**实测**出来的：`none` 表示上游确实不给
/// 校验值，`md5` 只有 purpur 那个构建详情接口有。
pub const TYPES: &[ServerType] = &[
    ServerType {
        id: "vanilla",
        name: "原版（Vanilla）",
        description: "Mojang 官方服务端 jar",
        category: "vanilla",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        // 上游只有 sha1（`downloads.server` 的字段就是 sha1/size/url），
        // 由 daemon 下载完成后自己算 —— 见 download 模块的说明。
        checksum: "sha1",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "paper",
        name: "Paper",
        description: "最常用的高性能插件服务端",
        category: "plugin",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        checksum: "sha256",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "folia",
        name: "Folia",
        description: "Paper 的分区多线程分支，插件兼容性受限",
        category: "plugin",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        // 与 paper 同一个接口的同一套产物，也带 sha256
        checksum: "sha256",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "purpur",
        name: "Purpur",
        description: "基于 Paper，附带大量可配置特性",
        category: "plugin",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        checksum: "md5",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "leaf",
        name: "Leaf",
        description: "基于 Paper 的优化分支",
        category: "plugin",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        checksum: "sha256",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "leaves",
        name: "Leaves",
        description: "偏原版行为的 Paper 分支（生电向）",
        category: "plugin",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        checksum: "sha256",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "fabric",
        name: "Fabric",
        description: "轻量模组加载器，安装器直接产出可跑的 server jar",
        category: "mod",
        file_name: "server.jar",
        startup_command: "java -jar server.jar nogui",
        // Fabric 的合并 jar 接口不提供校验值。
        checksum: "none",
        needs_version: true,
        needs_loader: true,
    },
    ServerType {
        id: "velocity",
        name: "Velocity",
        description: "现代代理服务端（PaperMC 出品）",
        category: "proxy",
        file_name: "velocity.jar",
        // 代理没有 GUI，也就没有 `nogui` 这个参数 —— 传了可能被当成非法参数。
        startup_command: "java -jar velocity.jar",
        checksum: "sha256",
        needs_version: true,
        needs_loader: false,
    },
    ServerType {
        id: "bungeecord",
        name: "BungeeCord",
        description: "老牌代理服务端，只有「最后一个成功的构建」",
        category: "proxy",
        file_name: "bungeecord.jar",
        startup_command: "java -jar bungeecord.jar",
        checksum: "none",
        needs_version: false,
        needs_loader: false,
    },
];

/// 按 id 找一个类型。
pub fn find(id: &str) -> Option<&'static ServerType> {
    TYPES.iter().find(|t| t.id == id)
}

/// 类型 id 是否合法（用于报错时提示「可选的有哪些」）。
pub fn known_ids() -> Vec<&'static str> {
    TYPES.iter().map(|t| t.id).collect()
}

/// 不带版本的占位版本号：BungeeCord 这类「只有 latest」的类型用它。
pub const LATEST_VERSION: &str = "latest";
