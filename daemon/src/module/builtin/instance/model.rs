//! 实例的元数据模型。
//!
//! 模型只描述**磁盘上有什么**，不描述进程在干什么 —— 后者归进程管理模块，
//! 见 [`ServerPhase`]。
//!
//! # 两条启动配置路线
//!
//! 实例有两种配法，由 [`InstanceConfig::manual_command`] 选：
//!
//! * **表单模式**（默认）：存「运行环境 + 服务端 jar + 最大内存 +
//!   自定义 JVM 参数」，启动时由 daemon 现拼 `java … -jar <jar> nogui`；
//! * **手动模式**：用户自己写一整条命令，存进 [`InstanceConfig::startup_command`]，
//!   daemon 原样交给 shell 跑。
//!
//! 表单那四个字段的落盘 key 是 `runtimeEnvId` / `serverFile` / `maxMemory` /
//! `customJvmArgs`，老的 java 实例文件读进来就能接着用（其中的 `runtime: "java"`
//! 字段没有对应物，被忽略）。唯一保留的启动命令迁移口是 `prootStartupCommand`：
//! 它语义上就是「启动命令」，通过 `alias` 继续读得进来。
//!
//! 拼命令的那点推导刻意放在 daemon（见 [`compose_java_command`]）：命令最终由
//! daemon 交给 shell 跑，路径（环境装在哪、jar 叫什么）也只有它知道；前端只存
//! 字段、显示 daemon 回给它的「生效命令」（`launch_command`），不自己拼。

use std::path::Path;

use serde::{Deserialize, Serialize};

/// 命令尾换行符。
///
/// 这是「往服务端 stdin 写命令时补的换行」，与启动命令本身无关。
pub const LINE_ENDING_LF: &str = "\n";
pub const LINE_ENDING_CRLF: &str = "\r\n";

/// 启动命令的长度上限（字符数）。
///
/// 只是个防呆上限：启动命令会原样交给 shell，太长多半是贴错了东西。
pub const STARTUP_COMMAND_MAX_CHARS: usize = 4096;

/// 停止命令的长度上限（字符数）。
///
/// 比启动命令短得多：停止命令就是「一行控制台命令」或一个 caret 记号
/// （如 `stop` / `^C`），超过这个长度必然是贴错了东西。
pub const STOP_COMMAND_MAX_CHARS: usize = 512;

/// 没配停止命令时用的默认值。
///
/// 选 `stop` 是因为本项目主要伺候 Minecraft 服务端（原版 / Paper / Forge 都是
/// 这一条）。PocketMine 之类的要自己改，改不了的就用 `^C`。
pub const DEFAULT_STOP_COMMAND: &str = "stop";

/// 「最大内存」的上限（MB）。
///
/// 防呆：这个值会变成 `-Xmx<n>M`，填错了（比如把字节数当 MB 填）JVM 会直接
/// 起不来，而且报错离「设置页填错了」很远。1 TiB 够任何一台真机器用。
pub const MAX_MEMORY_MB_LIMIT: u32 = 1_048_576;

/// 「自定义 JVM 参数」的长度上限（字符数）。
///
/// 同 [`STARTUP_COMMAND_MAX_CHARS`] 的道理：这一串会被原样交给 shell，
/// 长得离谱基本就是贴错了东西。比启动命令短，因为正常的 JVM 参数是几行的事。
pub const CUSTOM_JVM_ARGS_MAX_CHARS: usize = 1024;

/// UPnP 端口映射的传输协议（线上与落盘都用这两个小写值）。
pub const UPNP_PROTOCOL_TCP: &str = "tcp";
pub const UPNP_PROTOCOL_UDP: &str = "udp";

/// 拼命令时用的「安全字符」：只含这些就不加引号。
fn is_shell_safe(text: &str) -> bool {
    !text.is_empty()
        && text.chars().all(|ch| {
            ch.is_ascii_alphanumeric()
                || matches!(ch, '-' | '_' | '.' | '/' | ':' | '=' | '+' | ',' | '@')
        })
}

/// 给 shell 的一个参数加引号（只在必要时加）。
///
/// 命令是**交给系统 shell 解析的一整行**（见 `process::shell_command`），所以
/// 拼进去的每一段都得自己保证不被拆词：jar 名字里带空格、JVM 参数里带引号都
/// 不稀奇。两边的引号规则不同，分开写：
///
/// * Unix：单引号最省事 —— 里面除了 `'` 全是字面量（用 `'\''` 收尾再开）。
/// * Windows：`cmd` 只认双引号；Win32 文件名里不允许 `"`，所以这里的输入
///   （java 路径、jar 名）不会有它，只剩自定义参数里可能有 —— 那种就照原样
///   交给 cmd，不做「转义成 `\"`」这种两边都不认的写法。
fn quote_arg(text: &str) -> String {
    if is_shell_safe(text) {
        return text.to_string();
    }
    #[cfg(windows)]
    {
        format!("\"{text}\"")
    }
    #[cfg(not(windows))]
    {
        format!("'{}'", text.replace('\'', "'\\''"))
    }
}

/// 按表单拼一条 java 启动命令。
///
/// 形状：
///
/// ```text
/// <java> [-Xmx<n>M] [自定义 JVM 参数…] -jar <jar> nogui
/// ```
///
/// `java` 是运行环境里那个可执行文件的**绝对路径**（`<环境目录>/<binary>`）：
/// 装好的 JDK 不在 PATH 上，写全路径才找得到。
///
/// 两处**有意为之**的取舍：
///
/// * 现代 Forge/NeoForge 的 `@argfile` 没有单独分支 —— V2 的服务端下载源里没有
///   Forge，等真有那条路再补；
/// * 最大内存为 `None` 时**不传** `-Xmx`（`mem > 0` 才传）。
pub fn compose_java_command(java: &Path, jar: &str, config: &InstanceConfig) -> String {
    let mut parts: Vec<String> = vec![quote_arg(&java.display().to_string())];
    if let Some(mb) = config.max_memory.filter(|mb| *mb > 0) {
        parts.push(format!("-Xmx{mb}M"));
    }
    // 自定义参数按空白拆开：一行一个、一行几个都行
    for arg in config
        .custom_jvm_args
        .as_deref()
        .unwrap_or_default()
        .split_whitespace()
    {
        parts.push(quote_arg(arg));
    }
    parts.push("-jar".to_string());
    parts.push(quote_arg(jar));
    parts.push("nogui".to_string());
    parts.join(" ")
}

/// 把一段文本解释成控制字符（标准 caret 记号）。
///
/// 认 `^@`–`^_`（`^C` 就是 0x03）与 `^?`（DEL），大小写都收。
/// **必须整个值就是一个记号**才算 —— 否则 `say ^C` 这种带 caret 的普通命令
/// 会被误当成控制字符，那种误判极难排查。
fn caret_byte(text: &str) -> Option<u8> {
    let mut chars = text.chars();
    if chars.next()? != '^' {
        return None;
    }
    let head = chars.next()?;
    if chars.next().is_some() {
        return None;
    }
    let head = head.to_ascii_uppercase();
    match head {
        // `@`(0x40)–`_`(0x5f) 与 `^@`–`^_` 正好差 0x40，清掉第 6 位即可
        '@'..='_' => Some((head as u8) & 0x1f),
        '?' => Some(0x7f),
        _ => None,
    }
}

/// 把「停止命令」翻译成要写进 PTY 的字节。
///
/// * 整个值是 caret 记号（如 `^C`）→ 只写那个控制字节。终端驱动会把 `^C`
///   变成发给前台进程组的 SIGINT —— 没有控制台命令的服务端（`python main.py`
///   之类）靠这个优雅退出。
/// * 其它 → 当成一条控制台命令，末尾补 `line_ending` 再写。
/// * 两者都拿不到（命令为空）→ `None`，此时只有「强制停止」可用。
pub fn stop_payload(stop_command: Option<&str>, line_ending: &str) -> Option<Vec<u8>> {
    let text = stop_command.map(str::trim).filter(|t| !t.is_empty())?;
    if let Some(byte) = caret_byte(text) {
        return Some(vec![byte]);
    }
    let mut payload = text.as_bytes().to_vec();
    payload.extend_from_slice(line_ending.as_bytes());
    Some(payload)
}

fn default_line_ending() -> String {
    LINE_ENDING_LF.to_string()
}

fn is_default_line_ending(value: &str) -> bool {
    value == LINE_ENDING_LF
}

fn is_false(value: &bool) -> bool {
    !*value
}

fn default_upnp_protocol() -> String {
    UPNP_PROTOCOL_TCP.to_string()
}

fn is_default_upnp_protocol(value: &str) -> bool {
    value == UPNP_PROTOCOL_TCP
}

/// 实例索引项：只含实例选择列表需要的字段。
///
/// 对应 `config/instances.json` 里 `instances` 数组的一项。列表只要读索引，
/// 不必把每个实例的完整元数据都读一遍。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstanceSummary {
    /// 实例 id，同时也是磁盘上的目录名（随机生成，创建后不可变）。
    pub id: String,
    /// 用户可编辑的名称。
    pub name: String,
    /// 实例目录的完整路径；`None` = 用默认路径 `<instances-root>/<id>`。
    /// 需要把文件放进 proot rootfs 的实例会设置它。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}

impl InstanceSummary {
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            path: None,
        }
    }
}

/// 单个实例的完整元数据（= `config/instances/<id>.json`）。
///
/// `id` 与磁盘目录名一致。启动相关的信息有两条路线（手动命令 / 表单），
/// 见模块文档「两条启动配置路线」与 [`manual_command`](Self::manual_command)。
///
/// # 两个拼法都收
///
/// 落盘是 camelCase，线上（`instance.create` 的参数）是 snake_case ——
/// 按 README 的「命名分两套」。`create` 是**直接把参数反序列化成本结构**的，
/// 所以多词字段额外挂一个 snake_case 的 `alias`，两种拼法都认。
/// （曾经只认 camelCase，前端发 `max_memory` 会被静默丢掉 —— 这种"发了没生效"
/// 最难查，宁可两种都收。）
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct InstanceConfig {
    pub id: String,
    pub name: String,

    /// 启动命令：怎么把服务端拉起来，由用户自己写全（含解释器与参数）。
    ///
    /// 例：`java -Xmx2G -jar server.jar nogui`、
    /// `/usr/bin/python3 /mnt/server/main.py`、`./box64 ./bedrock_server`。
    ///
    /// `None` / 空串 = 还没配 —— 进程管理模块接进来之后，这种实例起不来，
    /// 所以 [`InstanceConfig::lint`] 会就此给出提醒。
    ///
    /// `prootStartupCommand` 是为了不丢老数据：早期 daemon 用它承载同一件事，
    /// 继续读得进来；写出去一律是新的 `startupCommand`。
    #[serde(
        alias = "prootStartupCommand",
        alias = "startup_command",
        skip_serializing_if = "Option::is_none"
    )]
    pub startup_command: Option<String>,

    /// 停止命令：怎么让服务端**优雅退出**。
    ///
    /// * 普通文本（如 `stop`）= 往服务端 stdin 写这一行（末尾补
    ///   [`line_ending`](Self::line_ending)）；
    /// * caret 记号（如 `^C`）= 直接把那个控制字符写进 PTY（见 [`stop_payload`]）。
    ///
    /// `None` / 空串 = 没配，这时按 [`DEFAULT_STOP_COMMAND`] 走（`stop`）。
    /// 实在没有优雅退出手段的服务端填 `^C`。
    #[serde(alias = "stop_command", skip_serializing_if = "Option::is_none")]
    pub stop_command: Option<String>,

    /// 兼容模式：进程起来后跳过「启动中」阶段（适配不打印 Done 的服务端）。
    #[serde(alias = "compat_mode", skip_serializing_if = "is_false")]
    pub compat_mode: bool,

    /// 关服自动重启（正常退出时用相同的启动命令重新拉起）。
    #[serde(alias = "auto_restart_on_exit", skip_serializing_if = "is_false")]
    pub auto_restart_on_exit: bool,

    /// **连带启动的映射隧道**：起这个游戏实例时，顺便把那条 frp 实例也拉起来。
    ///
    /// 存的是隧道的 `local_id`（`config/frp/toml/<local_id>.toml`）。
    /// `None` = 不连带。
    ///
    /// 这里**只是一个引用**，不是「绑定」：
    ///
    /// * 「用哪个 frpc 可执行文件」不在这儿 —— 那是 FRP 侧自己的设置
    ///   （`config/frp/settings.json`），换 frpc 版本不该动到游戏实例；
    /// * **运行态也不在这儿** —— 一条隧道可以同时被好几个游戏实例连带启动
    ///   （每个游戏实例各写一个 id，指向同一条隧道），进程归 FRP 侧管
    ///   （`frp.run.*`，一个隧道配置同时只有一个进程）。运行态问 FRP 那边，
    ///   别在这里再存一份「它现在跑没跑」，否则就有两个来源了；
    /// * **停游戏实例不会停隧道**：隧道是独立实例，可能还被别的游戏实例用着，
    ///   跟着一起停会误伤。要停就去「网络映射 → 管理隧道」里停。
    #[serde(alias = "frp_tunnel_id", skip_serializing_if = "Option::is_none")]
    pub frp_tunnel_id: Option<String>,

    /// **路由器端口映射（UPnP）**：起这个实例时自动在网关上开一个映射，
    /// 进程退出时撤销（见 upnp 模块）。
    ///
    /// 与 [`frp_tunnel_id`](Self::frp_tunnel_id) 的取舍相反：UPnP 是**每实例
    /// 独立**的 —— 协议与外网端口都跟着实例走，几个服务端（Java 版 25565、
    /// 基岩版 19132……）各自映射各自的。
    #[serde(alias = "upnp_enabled", skip_serializing_if = "is_false")]
    pub upnp_enabled: bool,

    /// UPnP 映射的传输协议：`tcp`（默认）或 `udp`。
    ///
    /// 存字符串而不是枚举：老文件 / 手改的元数据里出现怪值时，整份实例配置
    /// 不该因此读不进来（同 [`line_ending`](Self::line_ending) 的取舍），
    /// 由 create / update 把住取值范围，读取侧见 [`upnp_protocol`](Self::upnp_protocol)。
    #[serde(
        default = "default_upnp_protocol",
        alias = "upnp_protocol",
        skip_serializing_if = "is_default_upnp_protocol"
    )]
    pub upnp_protocol: String,

    /// UPnP 映射的**外网端口**；`None` = 用服务端自己的端口（内外网同号）。
    ///
    /// 想错开端口（公网入口已被别的服务占用）时填它；V1 就是这个语义。
    #[serde(alias = "upnp_external_port", skip_serializing_if = "Option::is_none")]
    pub upnp_external_port: Option<u16>,

    /// **STUN 隧道**：起这个实例时自动打洞，进程退出时关隧道（见 stun 模块）。
    ///
    /// 与 UPnP 同一套取舍（每实例独立）：隧道为「这个实例的服务端端口」而建，
    /// 几个实例各打各的洞。
    #[serde(alias = "stun_enabled", skip_serializing_if = "is_false")]
    pub stun_enabled: bool,

    /// STUN 隧道是否发送 PROXY protocol v2 头（让服务端拿到玩家真实 IP）。
    ///
    /// 需服务端已开启对应支持，否则玩家将无法进入（V1 的原话警告）。
    #[serde(alias = "stun_proxy_protocol", skip_serializing_if = "is_false")]
    pub stun_proxy_protocol: bool,

    /// STUN 隧道的**转发目标端口**（隧道收下连接后转发到本机哪个端口）；
    /// `None` = 用实例服务端自己的端口（见 upnp 模块的 `port::read_port`）。
    ///
    /// V1 的「本地端口」配置就是这个语义 —— 留空跟随服务端端口。
    #[serde(alias = "stun_target_port", skip_serializing_if = "Option::is_none")]
    pub stun_target_port: Option<u16>,

    /// 自定义实例目录；`None` = 默认的 `<instances-root>/<id>`。
    ///
    /// 为了接管一个已经存在的服务端目录（文件在别处、或挂在别的盘上）才需要它。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,

    /// 命令尾换行符，默认 `\n`。
    #[serde(
        default = "default_line_ending",
        alias = "line_ending",
        skip_serializing_if = "is_default_line_ending"
    )]
    pub line_ending: String,

    // ── 启动配置（「实例设置」表单）────────────────
    /// 手动命令开关。
    ///
    /// * `Some(true)` —— 直接用 [`startup_command`](Self::startup_command)，
    ///   下面那四个字段只是留着备查；
    /// * `Some(false)` —— 表单模式：启动时按那四个字段现拼命令；
    /// * `None` —— 没显式选过（老实例、下载向导建的），按字段推断，见
    ///   [`manual_command`](Self::manual_command)。
    ///
    /// 用「存过的值优先」而不是纯推断：用户手动关掉表单之后，那四个字段可能还
    /// 留着（改回表单时不用重填），只有存下开关本身才分得清「还在用」与「留着」。
    #[serde(alias = "manual_command", skip_serializing_if = "Option::is_none")]
    pub manual_command: Option<bool>,

    /// 表单模式：用哪个运行环境（`zulu-jdk-21-linux-x64`）。
    ///
    /// 只存 id、不存绝对路径：数据根搬家之后 id 仍然指得对，路径每次现算
    /// （与 [`frp_tunnel_id`](Self::frp_tunnel_id) 同一套存法）。
    #[serde(alias = "runtime_env_id", skip_serializing_if = "Option::is_none")]
    pub runtime_env_id: Option<String>,

    /// 表单模式：服务端 jar 的**文件名**（相对实例目录，不带路径）。
    ///
    /// 会被拼进启动命令，所以 update/create 会挡掉带路径分隔符的写法。
    #[serde(alias = "server_file", skip_serializing_if = "Option::is_none")]
    pub server_file: Option<String>,

    /// 表单模式：最大内存（MB），拼成 `-Xmx<n>M`；`None` = 不传（JVM 默认）。
    #[serde(alias = "max_memory", skip_serializing_if = "Option::is_none")]
    pub max_memory: Option<u32>,

    /// 表单模式：自定义 JVM 参数，原样一段文本（每行或空格分隔一个参数）。
    #[serde(alias = "custom_jvm_args", skip_serializing_if = "Option::is_none")]
    pub custom_jvm_args: Option<String>,

    // ── 以下是 daemon 侧补充的 ──────────────────────────
    /// 创建时间（毫秒时间戳）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at_ms: Option<u64>,

    /// 元数据最后写入时间（毫秒时间戳）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at_ms: Option<u64>,
}

impl Default for InstanceConfig {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            startup_command: None,
            stop_command: None,
            compat_mode: false,
            auto_restart_on_exit: false,
            frp_tunnel_id: None,
            upnp_enabled: false,
            upnp_protocol: default_upnp_protocol(),
            upnp_external_port: None,
            stun_enabled: false,
            stun_proxy_protocol: false,
            stun_target_port: None,
            path: None,
            line_ending: default_line_ending(),
            manual_command: None,
            runtime_env_id: None,
            server_file: None,
            max_memory: None,
            custom_jvm_args: None,
            created_at_ms: None,
            updated_at_ms: None,
        }
    }
}

impl InstanceConfig {
    /// 新建一个实例（`id` 由调用方生成）。
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        let now = crate::util::now_ms();
        Self {
            id: id.into(),
            name: name.into(),
            created_at_ms: Some(now),
            ..Default::default()
        }
    }

    pub fn summary(&self) -> InstanceSummary {
        InstanceSummary {
            id: self.id.clone(),
            name: self.name.clone(),
            path: self.path.clone(),
        }
    }

    /// 启动命令的有效值：空白串等同于没配。
    pub fn startup_command(&self) -> Option<&str> {
        self.startup_command
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
    }

    /// 停止命令的有效值；没配时回落到 [`DEFAULT_STOP_COMMAND`]。
    pub fn stop_command(&self) -> &str {
        self.stop_command
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .unwrap_or(DEFAULT_STOP_COMMAND)
    }

    /// 是否「手动命令」模式（显式存过的优先，没存过按字段推断）。
    ///
    /// 推断规则只有一条：**只在 `startup_command` 上写了命令、表单字段一个都
    /// 没填 → 手动**。下载向导建出来的实例正是这样（命令是它写的，不能被表单
    /// 盖掉），而空实例（什么都没有）落在表单模式 —— 那正是设置页的默认形态。
    pub fn manual_command(&self) -> bool {
        self.manual_command.unwrap_or_else(|| {
            self.startup_command().is_some()
                && self.runtime_env_id.is_none()
                && self.server_file.is_none()
                && self.max_memory.is_none()
                && self.custom_jvm_args.is_none()
        })
    }

    /// 表单模式：这次启动要拼进去的 jar 名（空白串等同没选）。
    pub fn server_file(&self) -> Option<&str> {
        self.server_file
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
    }

    /// 表单模式：用哪个运行环境（空白串等同没选）。
    pub fn runtime_env_id(&self) -> Option<&str> {
        self.runtime_env_id
            .as_deref()
            .map(str::trim)
            .filter(|text| !text.is_empty())
    }

    /// UPnP 协议的有效值：只认 `tcp` / `udp`（大小写不敏感），
    /// 怪值一律按 `tcp` 走 —— 读取侧宽容，写入侧（create / update）把关。
    pub fn upnp_protocol(&self) -> &'static str {
        if self
            .upnp_protocol
            .trim()
            .eq_ignore_ascii_case(UPNP_PROTOCOL_UDP)
        {
            UPNP_PROTOCOL_UDP
        } else {
            UPNP_PROTOCOL_TCP
        }
    }

    /// **线上**（WS / HTTP）的形态：统一 snake_case，和 daemon 其余响应一致
    /// （`uptime_ms`、`method_not_found`、`process_managed` …）。
    ///
    /// 落盘用的是 camelCase（直接 `serde_json::to_string`），两者刻意分开：
    /// 文件格式与线上格式各自保持一致，前端只需要知道线上这一套。
    ///
    /// **注意这是第二份序列化**：落盘走 `serde`（camelCase），线上走这里
    /// —— 所以**加字段要同时改两处**（这一份 + 结构体上的 serde 属性），
    /// 漏了就会出现「存进去了、读回来没有」这种最费时间的错（踩过）。
    ///
    /// `launch_command` 由调用方算好传进来（拼命令要读运行环境，那是实例模块的
    /// 事）：`Some` = 现在就能跑起来的那条命令，`None` = 还没配全 / 环境不在了
    /// —— 前端据此决定显示什么。
    pub fn to_wire_value(&self, launch_command: Option<&str>) -> serde_json::Value {
        serde_json::json!({
            "id": self.id,
            "name": self.name,
            // 手动模式存的那条命令（表单模式下只是留档，不参与启动）
            "startup_command": self.startup_command,
            // 实际会跑的那条：表单模式是现拼的
            "launch_command": launch_command,
            "manual_command": self.manual_command(),
            "runtime_env_id": self.runtime_env_id,
            "server_file": self.server_file,
            "max_memory": self.max_memory,
            "custom_jvm_args": self.custom_jvm_args,
            // 没配时把生效的默认值一并告诉前端，界面上就不用再猜
            "stop_command": self.stop_command(),
            "compat_mode": self.compat_mode,
            "auto_restart_on_exit": self.auto_restart_on_exit,
            "frp_tunnel_id": self.frp_tunnel_id,
            // UPnP 三字段：协议给生效值（怪值回落到 tcp），前端不用再猜
            "upnp_enabled": self.upnp_enabled,
            "upnp_protocol": self.upnp_protocol(),
            "upnp_external_port": self.upnp_external_port,
            // STUN 三字段：目标端口留空 = 跟随服务端端口
            "stun_enabled": self.stun_enabled,
            "stun_proxy_protocol": self.stun_proxy_protocol,
            "stun_target_port": self.stun_target_port,
            "path": self.path,
            "line_ending": self.line_ending,
            "created_at_ms": self.created_at_ms,
            "updated_at_ms": self.updated_at_ms,
        })
    }

    /// 元数据自洽性检查的结果（不碰磁盘的部分）。
    ///
    /// 「运行环境还在不在」「jar 还在不在」要读盘，归 `status`（见实例模块）——
    /// 这里只说「配置形态」的问题。
    pub fn lint(&self) -> Vec<String> {
        let mut warnings = Vec::new();
        if self.name.trim().is_empty() {
            warnings.push("实例名称为空".to_string());
        }
        if self.manual_command() {
            if self.startup_command().is_none() {
                warnings.push("未配置启动命令，该实例无法被启动".to_string());
            }
        } else {
            if self.runtime_env_id().is_none() {
                warnings.push("还没选运行环境，该实例无法被启动".to_string());
            }
            if self.server_file().is_none() {
                warnings.push("还没选服务端 jar，该实例无法被启动".to_string());
            }
        }
        if self.line_ending != LINE_ENDING_LF && self.line_ending != LINE_ENDING_CRLF {
            warnings.push(format!("非常规换行符 {:?}", self.line_ending));
        }
        warnings
    }
}

/// 服务端生命周期阶段。
///
/// 线上取值是 `stopped` / `preparing` / `starting` / `running` / `stopping` /
/// `crashed` —— [`ServerPhase::Crashed`] 把进程异常退出和「用户主动停止」区分开，
/// 否则前端只能把崩溃显示成"已停止"。
///
/// 判定规则（见 `process.rs`）：
///
/// * 拉起进程 → `starting`（`compatMode` 为真则直接 `running`）；
/// * 输出里出现 `Done (` → `running`；
/// * 收到停止命令 → `stopping`；
/// * 退出时：是我们让它停的、或退出码为 0 → `stopped`；否则 `crashed`。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ServerPhase {
    /// 未运行。
    Stopped,
    /// 启动前的准备（校验文件、补依赖等）。
    Preparing,
    /// 进程已拉起，等待服务端就绪。
    Starting,
    /// 正常运行。
    Running,
    /// 正在停止。
    Stopping,
    /// 异常退出（daemon 侧扩展）。
    Crashed,
}

impl ServerPhase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Stopped => "stopped",
            Self::Preparing => "preparing",
            Self::Starting => "starting",
            Self::Running => "running",
            Self::Stopping => "stopping",
            Self::Crashed => "crashed",
        }
    }

    /// 是否算「正在运行」。
    pub fn is_running(self) -> bool {
        self == Self::Running
    }

    /// 是否处于过渡态（禁止并发启停）。
    pub fn is_busy(self) -> bool {
        matches!(self, Self::Preparing | Self::Starting | Self::Stopping)
    }
}

/// 实例目录的体积统计（有上限，见 `scan_max_entries` / `scan_max_depth`）。
#[derive(Debug, Clone, Default, Serialize)]
pub struct DirStats {
    pub exists: bool,
    pub size_bytes: u64,
    pub file_count: u64,
    pub dir_count: u64,
    /// 触到了扫描上限，体积/数量不完整。
    pub truncated: bool,
}

/// 实例状态：**磁盘视角** + 进程视角。
#[derive(Debug, Clone, Serialize)]
pub struct InstanceStatus {
    pub id: String,
    pub name: String,
    /// 生命周期阶段（见 [`ServerPhase`]）。
    pub phase: ServerPhase,
    pub running: bool,
    /// 进程管理是否已接入。**现在是 `true`** —— 阶段真的会动了。
    pub process_managed: bool,
    /// 进程 id（在运行时才有）。
    pub pid: Option<u32>,
    /// 上一次退出的退出码。
    pub exit_code: Option<i32>,
    /// 本轮启动时刻（Unix 毫秒）。
    pub started_at_ms: Option<u64>,
    /// 实例目录的绝对路径。
    pub dir: String,
    pub dir_exists: bool,
    pub size_bytes: u64,
    pub size_human: String,
    pub file_count: u64,
    pub dir_count: u64,
    /// 体积统计触顶，数值只是下界。
    pub size_truncated: bool,
    pub created_at_ms: Option<u64>,
    pub updated_at_ms: Option<u64>,
    /// 值得提醒用户的问题（目录丢失、入口文件不在、元数据不合法……）。
    pub warnings: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// `frp_tunnel_id`：落盘是 camelCase，默认值不写出去
    /// （老实例的元数据里不会有它们）。
    #[test]
    fn frp_tunnel_id_uses_camel_case_and_is_omitted_at_default() {
        let mut cfg = InstanceConfig::default();
        let value = serde_json::to_value(&cfg).expect("应能序列化");
        assert!(
            value.get("frpTunnelId").is_none(),
            "默认值不该写出去：{value}"
        );

        cfg.frp_tunnel_id = Some("abc123".into());
        let value = serde_json::to_value(&cfg).expect("应能序列化");
        assert_eq!(value["frpTunnelId"], json!("abc123"));

        // 读回来：老数据（没有这几个字段）也要能读
        let legacy = json!({ "id": "a1", "name": "服" });
        let back: InstanceConfig = serde_json::from_value(legacy).expect("老数据应当读得进来");
        assert!(back.frp_tunnel_id.is_none());
    }

    /// UPnP 三字段：默认不落盘、读写两套命名都认、协议读取侧宽容。
    #[test]
    fn upnp_fields_round_trip_and_defaults_are_omitted() {
        let bare = InstanceConfig::new("a1", "服");
        let value = serde_json::to_value(&bare).expect("应能序列化");
        assert!(value.get("upnpEnabled").is_none(), "默认不落盘：{value}");
        assert!(
            value.get("upnpProtocol").is_none(),
            "默认 tcp 不落盘：{value}"
        );
        assert!(
            value.get("upnpExternalPort").is_none(),
            "没填不落盘：{value}"
        );

        // 线上：三件都显式给，协议给生效值
        let wire = bare.to_wire_value(None);
        assert_eq!(wire["upnp_enabled"], json!(false));
        assert_eq!(wire["upnp_protocol"], json!(UPNP_PROTOCOL_TCP));
        assert!(wire["upnp_external_port"].is_null());

        // 存进去读回来（落盘 camelCase）
        let cfg: InstanceConfig = serde_json::from_value(json!({
            "id": "a1", "name": "服",
            "upnpEnabled": true, "upnpProtocol": "udp", "upnpExternalPort": 25570
        }))
        .unwrap();
        assert!(cfg.upnp_enabled);
        assert_eq!(cfg.upnp_protocol(), UPNP_PROTOCOL_UDP);
        assert_eq!(cfg.upnp_external_port, Some(25570));
        let value = serde_json::to_value(&cfg).unwrap();
        assert_eq!(value["upnpEnabled"], json!(true));
        assert_eq!(value["upnpProtocol"], json!("udp"));
        assert_eq!(value["upnpExternalPort"], json!(25570));

        // 线上（snake_case 入参，instance.create 用）也认；
        // 大写 UDP 规范化后按 udp 算
        let from_wire: InstanceConfig = serde_json::from_value(json!({
            "name": "x",
            "upnp_enabled": true,
            "upnp_protocol": "UDP",
            "upnp_external_port": 19133
        }))
        .unwrap();
        assert!(from_wire.upnp_enabled);
        assert_eq!(from_wire.upnp_protocol(), UPNP_PROTOCOL_UDP);
        assert_eq!(from_wire.upnp_external_port, Some(19133));

        // 老文件里没有这三个 key → 默认关闭、tcp、端口留空
        let legacy: InstanceConfig =
            serde_json::from_value(json!({ "id": "a", "name": "服" })).expect("老数据应当读得进来");
        assert!(!legacy.upnp_enabled);
        assert_eq!(legacy.upnp_protocol(), UPNP_PROTOCOL_TCP);
        assert!(legacy.upnp_external_port.is_none());

        // 怪协议：不 panic、回落 tcp（读取侧宽容）
        let weird = InstanceConfig {
            upnp_protocol: "sctp".into(),
            ..InstanceConfig::new("a", "服")
        };
        assert_eq!(weird.upnp_protocol(), UPNP_PROTOCOL_TCP);
        assert_eq!(weird.to_wire_value(None)["upnp_protocol"], json!("tcp"));
    }

    /// STUN 三字段：默认不落盘、读写两套命名都认、老数据读得进来。
    #[test]
    fn stun_fields_round_trip_and_defaults_are_omitted() {
        let bare = InstanceConfig::new("a1", "服");
        let value = serde_json::to_value(&bare).expect("应能序列化");
        for gone in ["stunEnabled", "stunProxyProtocol", "stunTargetPort"] {
            assert!(value.get(gone).is_none(), "默认不落盘：{gone}（{value}）");
        }

        // 线上：三件都显式给
        let wire = bare.to_wire_value(None);
        assert_eq!(wire["stun_enabled"], json!(false));
        assert_eq!(wire["stun_proxy_protocol"], json!(false));
        assert!(wire["stun_target_port"].is_null());

        // 存进去读回来（落盘 camelCase）
        let cfg: InstanceConfig = serde_json::from_value(json!({
            "id": "a1", "name": "服",
            "stunEnabled": true, "stunProxyProtocol": true, "stunTargetPort": 25570
        }))
        .unwrap();
        assert!(cfg.stun_enabled);
        assert!(cfg.stun_proxy_protocol);
        assert_eq!(cfg.stun_target_port, Some(25570));
        let value = serde_json::to_value(&cfg).unwrap();
        assert_eq!(value["stunEnabled"], json!(true));
        assert_eq!(value["stunProxyProtocol"], json!(true));
        assert_eq!(value["stunTargetPort"], json!(25570));

        // 线上（snake_case 入参，instance.create 用）也认
        let from_wire: InstanceConfig = serde_json::from_value(json!({
            "name": "x",
            "stun_enabled": true,
            "stun_proxy_protocol": true,
            "stun_target_port": 25565
        }))
        .unwrap();
        assert!(from_wire.stun_enabled);
        assert!(from_wire.stun_proxy_protocol);
        assert_eq!(from_wire.stun_target_port, Some(25565));

        // 老文件里没有这三个 key → 默认关闭、无覆盖端口
        let legacy: InstanceConfig =
            serde_json::from_value(json!({ "id": "a", "name": "服" })).expect("老数据应当读得进来");
        assert!(!legacy.stun_enabled);
        assert!(!legacy.stun_proxy_protocol);
        assert!(legacy.stun_target_port.is_none());
    }

    #[test]
    fn file_keys_are_camel_case_and_defaults_are_omitted() {
        let cfg = InstanceConfig {
            id: "a1".into(),
            name: "生存服".into(),
            startup_command: Some("java -Xmx2G -jar server.jar nogui".into()),
            stop_command: Some("^C".into()),
            compat_mode: true,
            auto_restart_on_exit: true,
            frp_tunnel_id: None,
            upnp_enabled: false,
            upnp_protocol: UPNP_PROTOCOL_TCP.into(),
            upnp_external_port: None,
            stun_enabled: false,
            stun_proxy_protocol: false,
            stun_target_port: None,
            path: None,
            line_ending: LINE_ENDING_CRLF.into(),
            manual_command: None,
            runtime_env_id: None,
            server_file: None,
            max_memory: None,
            custom_jvm_args: None,
            created_at_ms: Some(1),
            updated_at_ms: Some(2),
        };
        let value = serde_json::to_value(&cfg).expect("应能序列化");
        for key in [
            "id",
            "name",
            "startupCommand",
            "stopCommand",
            "compatMode",
            "autoRestartOnExit",
            "lineEnding",
        ] {
            assert!(value.get(key).is_some(), "缺少 key: {key}（{value}）");
        }
        // 彻底消失的是这两样已经没有对应物的：`runtime`（服务端类型）
        // 与 proot 时代的 key（语义已由 `startupCommand` 承载）
        for gone in ["runtime", "prootStartupCommand"] {
            assert!(value.get(gone).is_none(), "`{gone}` 应当已经删掉: {value}");
        }

        // 默认值不落盘
        let minimal = InstanceConfig::new("a1", "服");
        let value = serde_json::to_value(&minimal).expect("应能序列化");
        assert!(value.get("startupCommand").is_none());
        assert!(value.get("compatMode").is_none());
        assert!(value.get("lineEnding").is_none(), "默认换行符不该写出来");
        for key in [
            "manualCommand",
            "runtimeEnvId",
            "serverFile",
            "maxMemory",
            "customJvmArgs",
        ] {
            assert!(value.get(key).is_none(), "没填就不该落盘：{key}（{value}）");
        }
    }

    /// 表单那四个字段 + 开关：落盘 key 是 `runtimeEnvId` / `serverFile` /
    /// `maxMemory` / `customJvmArgs`，实例文件读进来就能用。
    #[test]
    fn launch_form_fields_round_trip() {
        let stored_file = json!({
            "id": "a1",
            "name": "生存服",
            "runtime": "java",
            "runtimeEnvId": "zulu-jdk-21-linux-x64",
            "serverFile": "paper-1.21.jar",
            "maxMemory": 4096,
            "customJvmArgs": "-XX:+UseG1GC -XX:MaxGCPauseMillis=100"
        });
        let cfg: InstanceConfig =
            serde_json::from_value(stored_file).expect("这份实例文件应当读得进来");
        assert_eq!(cfg.runtime_env_id(), Some("zulu-jdk-21-linux-x64"));
        assert_eq!(cfg.server_file(), Some("paper-1.21.jar"));
        assert_eq!(cfg.max_memory, Some(4096));
        assert_eq!(
            cfg.custom_jvm_args.as_deref(),
            Some("-XX:+UseG1GC -XX:MaxGCPauseMillis=100")
        );
        assert!(!cfg.manual_command(), "填了表单字段就该是表单模式");

        // 写回去还是那几个 key
        let value = serde_json::to_value(&cfg).unwrap();
        assert_eq!(value["runtimeEnvId"], json!("zulu-jdk-21-linux-x64"));
        assert_eq!(value["serverFile"], json!("paper-1.21.jar"));
        assert_eq!(value["maxMemory"], json!(4096));
        assert_eq!(
            value["customJvmArgs"],
            json!("-XX:+UseG1GC -XX:MaxGCPauseMillis=100")
        );

        // 线上（snake_case）：四个字段 + 生效的 launch_command 一起给
        let wire = cfg.to_wire_value(Some("java -jar paper-1.21.jar nogui"));
        assert_eq!(wire["runtime_env_id"], json!("zulu-jdk-21-linux-x64"));
        assert_eq!(wire["server_file"], json!("paper-1.21.jar"));
        assert_eq!(wire["max_memory"], json!(4096));
        assert_eq!(
            wire["custom_jvm_args"],
            json!("-XX:+UseG1GC -XX:MaxGCPauseMillis=100")
        );
        assert_eq!(wire["manual_command"], json!(false));
        assert_eq!(
            wire["launch_command"],
            json!("java -jar paper-1.21.jar nogui")
        );

        // 线下（snake_case 入参）也收
        let from_wire: InstanceConfig = serde_json::from_value(json!({
            "name": "x",
            "manual_command": false,
            "runtime_env_id": "zulu-jdk-21-linux-x64",
            "server_file": "server.jar",
            "max_memory": 2048,
            "custom_jvm_args": "-Dfile.encoding=UTF-8"
        }))
        .unwrap();
        assert_eq!(from_wire.runtime_env_id(), Some("zulu-jdk-21-linux-x64"));
        assert_eq!(from_wire.server_file(), Some("server.jar"));
        assert_eq!(from_wire.max_memory, Some(2048));
        assert_eq!(from_wire.manual_command, Some(false));
    }

    /// 「手动 / 表单」怎么判：显式存过的开关优先，没存过才按字段推断。
    #[test]
    fn manual_command_is_stored_first_then_inferred() {
        // 下载向导建出来的实例：只有一条命令，推断成手动（不能被表单盖掉）
        let wizard = InstanceConfig {
            startup_command: Some("./start.sh".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(wizard.manual_command(), "只写了命令 → 手动模式");

        // 空实例：设置页的默认形态是表单
        let empty = InstanceConfig::new("a", "服");
        assert!(!empty.manual_command(), "什么都没有 → 表单模式（默认）");

        // 填了表单字段就是表单，哪怕 startup_command 里还留着旧命令
        let migrated = InstanceConfig {
            startup_command: Some("java -jar old.jar".into()),
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(!migrated.manual_command());

        // 显式开关优先于推断：关了表单之后四个字段只是留档，不参与启动
        let kept = InstanceConfig {
            startup_command: Some("./start.sh".into()),
            manual_command: Some(true),
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            server_file: Some("server.jar".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(kept.manual_command(), "显式 `true` 压过「有表单字段」");

        let forced_form = InstanceConfig {
            manual_command: Some(false),
            ..InstanceConfig::new("a", "服")
        };
        assert!(!forced_form.manual_command(), "显式 `false` 压过「有命令」");
    }

    /// 空白串等同没填（同 `startup_command` 的处理）。
    #[test]
    fn blank_form_fields_count_as_missing() {
        let cfg: InstanceConfig = serde_json::from_value(json!({
            "name": "x",
            "runtimeEnvId": "  ",
            "serverFile": " ",
            "customJvmArgs": ""
        }))
        .unwrap();
        assert!(cfg.runtime_env_id().is_none());
        assert!(cfg.server_file().is_none());
        // 自定义参数是「原样一段文本」，空的就等于没配（拼命令时自然跳过）
        assert_eq!(cfg.custom_jvm_args.as_deref(), Some(""));
    }

    /// 拼命令：该加引号的加、该省的省。
    #[test]
    fn compose_java_command_shape() {
        let base = InstanceConfig {
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            server_file: Some("server.jar".into()),
            ..InstanceConfig::new("a", "服")
        };

        // 全填：java 走绝对路径、-Xmx 紧跟着、自定义参数按空白拆
        let full = InstanceConfig {
            max_memory: Some(4096),
            custom_jvm_args: Some("-XX:+UseG1GC   -Dfile.encoding=UTF-8".into()),
            ..base.clone()
        };
        let command = compose_java_command(
            Path::new("/data/runtimes/zulu-jdk-21-linux-x64/bin/java"),
            "paper-1.21.jar",
            &full,
        );
        assert_eq!(
            command,
            "/data/runtimes/zulu-jdk-21-linux-x64/bin/java -Xmx4096M -XX:+UseG1GC -Dfile.encoding=UTF-8 -jar paper-1.21.jar nogui"
        );

        // 不填内存 / 参数：直接 -jar（`mem > 0` 才加 `-Xmx`）
        let bare = compose_java_command(Path::new("/opt/jdk/bin/java"), "server.jar", &base);
        assert_eq!(bare, "/opt/jdk/bin/java -jar server.jar nogui");

        // 0 也当没填
        let zero = InstanceConfig {
            max_memory: Some(0),
            ..base.clone()
        };
        assert_eq!(
            compose_java_command(Path::new("/opt/jdk/bin/java"), "server.jar", &zero),
            "/opt/jdk/bin/java -jar server.jar nogui"
        );

        // 需要引号的片段（空格、通配符）：交给 shell 也不能被拆词 / 展开
        let spaced = InstanceConfig {
            max_memory: Some(1024),
            custom_jvm_args: Some("-Dpattern=*.jar -Xss4M".into()),
            ..base.clone()
        };
        let command =
            compose_java_command(Path::new("/data/my jdk/bin/java"), "my server.jar", &spaced);
        #[cfg(not(windows))]
        assert_eq!(
            command,
            "'/data/my jdk/bin/java' -Xmx1024M '-Dpattern=*.jar' -Xss4M -jar 'my server.jar' nogui"
        );
        #[cfg(windows)]
        assert_eq!(
            command,
            "\"/data/my jdk/bin/java\" -Xmx1024M \"-Dpattern=*.jar\" -Xss4M -jar \"my server.jar\" nogui"
        );

        // 参数里的单引号：Unix 上要能原样传进去（`'\''` 收尾再开）
        #[cfg(not(windows))]
        {
            let tricky = InstanceConfig {
                custom_jvm_args: Some("-XX:OnError=touch /tmp/it's-here".into()),
                ..base.clone()
            };
            assert_eq!(
                compose_java_command(Path::new("java"), "server.jar", &tricky),
                "java -XX:OnError=touch '/tmp/it'\\''s-here' -jar server.jar nogui"
            );
        }
    }

    /// 自定义参数里的空白是分隔符，
    /// 而且一律**不**注入引号以外的解释。
    #[test]
    fn compose_java_command_splits_custom_args_on_whitespace() {
        let cfg = InstanceConfig {
            runtime_env_id: Some("jdk".into()),
            server_file: Some("server.jar".into()),
            custom_jvm_args: Some("\n  -Xss4M\t-XX:+AlwaysPreTouch  \n\n-Dfoo=bar\n".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert_eq!(
            compose_java_command(Path::new("java"), "server.jar", &cfg),
            "java -Xss4M -XX:+AlwaysPreTouch -Dfoo=bar -jar server.jar nogui"
        );
    }

    #[test]
    fn wire_shape_is_snake_case_while_file_is_camel_case() {
        let cfg = InstanceConfig {
            id: "a1".into(),
            name: "生存服".into(),
            startup_command: Some("./run.sh".into()),
            created_at_ms: Some(7),
            ..Default::default()
        };

        // 线上：snake_case，且缺省项也是显式 null（前端不用猜字段在不在）
        let wire = cfg.to_wire_value(Some("./run.sh"));
        assert_eq!(wire["startup_command"], json!("./run.sh"));
        assert_eq!(wire["launch_command"], json!("./run.sh"));
        assert_eq!(wire["created_at_ms"], json!(7));
        assert_eq!(wire["compat_mode"], json!(false));
        assert!(wire["path"].is_null());
        assert!(
            wire.get("startupCommand").is_none(),
            "线上不该出现 camelCase"
        );
        assert!(wire.get("runtime").is_none(), "线上不该再有服务端类型");
        assert_eq!(wire["manual_command"], json!(true), "只写了命令 → 手动模式");
        assert!(wire["runtime_env_id"].is_null());
        assert!(wire["server_file"].is_null());
        assert!(wire["max_memory"].is_null());
        // 没配停止命令时，线上直接给生效的默认值（不让前端猜）
        assert_eq!(wire["stop_command"], json!(DEFAULT_STOP_COMMAND));

        // 表单模式且没配全时：`launch_command` 给 `null`（前端显示「未配置」）
        let form = InstanceConfig {
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            ..Default::default()
        };
        let wire = form.to_wire_value(None);
        assert!(wire["launch_command"].is_null());
        assert_eq!(wire["manual_command"], json!(false));
        assert_eq!(wire["runtime_env_id"], json!("zulu-jdk-21-linux-x64"));

        // 文件：camelCase
        let file = serde_json::to_value(&cfg).unwrap();
        assert_eq!(file["startupCommand"], json!("./run.sh"));
        assert_eq!(file["createdAtMs"], json!(7));
        assert!(file.get("stopCommand").is_none(), "没配就不落盘");
        assert!(
            file.get("launchCommand").is_none(),
            "`launchCommand` 是算出来的，不落盘"
        );
    }

    #[test]
    fn stop_command_defaults_to_stop_and_accepts_both_spellings() {
        let bare = InstanceConfig::new("a", "服");
        assert_eq!(bare.stop_command(), "stop");
        assert!(bare.stop_command.is_none(), "默认值不该写进文件");

        let custom = InstanceConfig {
            stop_command: Some("  end  ".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert_eq!(custom.stop_command(), "end", "首尾空白要去掉");

        // snake_case 与 camelCase 都收
        let from_wire: InstanceConfig =
            serde_json::from_value(json!({ "name": "x", "stop_command": "^C" })).unwrap();
        assert_eq!(from_wire.stop_command(), "^C");
        let from_file: InstanceConfig =
            serde_json::from_value(json!({ "name": "x", "stopCommand": "stop" })).unwrap();
        assert_eq!(from_file.stop_command(), "stop");
    }

    #[test]
    fn stop_payload_handles_caret_notation_and_plain_commands() {
        // 普通命令：补上配置的换行符
        assert_eq!(
            stop_payload(Some("stop"), LINE_ENDING_LF).unwrap(),
            b"stop\n".to_vec()
        );
        assert_eq!(
            stop_payload(Some("  end  "), LINE_ENDING_CRLF).unwrap(),
            b"end\r\n".to_vec()
        );

        // caret 记号：只发那一个控制字节，不补换行
        assert_eq!(
            stop_payload(Some("^C"), LINE_ENDING_LF).unwrap(),
            vec![0x03]
        );
        assert_eq!(
            stop_payload(Some("^c"), LINE_ENDING_LF).unwrap(),
            vec![0x03]
        );
        assert_eq!(
            stop_payload(Some("^D"), LINE_ENDING_LF).unwrap(),
            vec![0x04]
        );
        assert_eq!(
            stop_payload(Some("^["), LINE_ENDING_LF).unwrap(),
            vec![0x1b]
        );
        assert_eq!(
            stop_payload(Some("^?"), LINE_ENDING_LF).unwrap(),
            vec![0x7f]
        );

        // 带 caret 的普通命令不能被误当成控制字符
        assert_eq!(
            stop_payload(Some("say ^C"), LINE_ENDING_LF).unwrap(),
            b"say ^C\n".to_vec()
        );
        // 不认识的记号也按普通命令处理
        assert_eq!(
            stop_payload(Some("^1"), LINE_ENDING_LF).unwrap(),
            b"^1\n".to_vec()
        );

        // 没配 / 空白 → None（只能强制停止）
        assert!(stop_payload(None, LINE_ENDING_LF).is_none());
        assert!(stop_payload(Some("   "), LINE_ENDING_LF).is_none());
    }

    #[test]
    fn reads_legacy_proot_startup_command_and_keeps_form_fields() {
        // 老实例文件里写的是 prootStartupCommand，还有一堆已经删掉的字段；
        // 表单字段则是**要接着用**的（key 相同）
        let cfg: InstanceConfig = serde_json::from_value(json!({
            "id": "x",
            "name": "老实例",
            "prootStartupCommand": "/usr/bin/python3 /mnt/server/main.py",
            "runtime": "proot",
            "runtimeEnvId": "rootfs-1",
            "maxMemory": 4096,
            "serverFile": "paper.jar",
            "customJvmArgs": "-Xmx1G",
            "someFutureKey": {"nested": true}
        }))
        .expect("应能读老配置");

        assert_eq!(
            cfg.startup_command(),
            Some("/usr/bin/python3 /mnt/server/main.py"),
            "老的 prootStartupCommand 语义上就是启动命令，不能丢"
        );
        assert_eq!(cfg.line_ending, LINE_ENDING_LF);
        assert_eq!(cfg.created_at_ms, None);
        // `runtime: "proot"` 没有对应物（被忽略），表单字段留下来
        assert_eq!(cfg.runtime_env_id(), Some("rootfs-1"));
        assert_eq!(cfg.server_file(), Some("paper.jar"));
        assert_eq!(cfg.max_memory, Some(4096));
        assert_eq!(cfg.custom_jvm_args.as_deref(), Some("-Xmx1G"));

        // 写回去时用的是新 key
        let value = serde_json::to_value(&cfg).unwrap();
        assert!(value.get("prootStartupCommand").is_none());
        assert!(value.get("runtime").is_none(), "服务端类型没有对应物");
        assert_eq!(
            value["startupCommand"],
            json!("/usr/bin/python3 /mnt/server/main.py")
        );
        assert_eq!(value["runtimeEnvId"], json!("rootfs-1"));
    }

    /// 空白串等同没配：老文件里可能有 `"prootStartupCommand": ""`。
    #[test]
    fn blank_startup_command_counts_as_missing() {
        let cfg = InstanceConfig {
            startup_command: Some("   ".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(cfg.startup_command().is_none());
    }

    #[test]
    fn phase_serializes_snake_case() {
        for (phase, text) in [
            (ServerPhase::Stopped, "stopped"),
            (ServerPhase::Preparing, "preparing"),
            (ServerPhase::Starting, "starting"),
            (ServerPhase::Running, "running"),
            (ServerPhase::Stopping, "stopping"),
            (ServerPhase::Crashed, "crashed"),
        ] {
            assert_eq!(phase.as_str(), text);
            assert_eq!(serde_json::to_value(phase).unwrap(), json!(text));
        }
        assert!(ServerPhase::Running.is_running());
        assert!(!ServerPhase::Stopped.is_running());
        assert!(ServerPhase::Starting.is_busy());
        assert!(!ServerPhase::Running.is_busy());
    }

    #[test]
    fn lint_is_mode_aware_and_flags_bad_line_ending() {
        // 手动模式：命令没写 → 起不来
        let manual = InstanceConfig {
            manual_command: Some(true),
            line_ending: "\r".into(),
            ..InstanceConfig::new("a", "服")
        };
        let warnings = manual.lint();
        assert!(
            warnings.iter().any(|w| w.contains("未配置启动命令")),
            "{warnings:?}"
        );
        assert!(
            warnings.iter().any(|w| w.contains("换行符")),
            "{warnings:?}"
        );

        // 表单模式（默认）：命令不是重点，环境与 jar 没选才起不来
        let form = InstanceConfig::new("a", "服");
        let warnings = form.lint();
        assert!(
            warnings.iter().any(|w| w.contains("运行环境")),
            "{warnings:?}"
        );
        assert!(
            warnings.iter().any(|w| w.contains("服务端 jar")),
            "{warnings:?}"
        );
        assert!(
            !warnings.iter().any(|w| w.contains("未配置启动命令")),
            "表单模式不该提启动命令：{warnings:?}"
        );

        // 表单填全 → 没告警（内存与自定义参数都是可选的）
        let clean = InstanceConfig {
            runtime_env_id: Some("zulu-jdk-21-linux-x64".into()),
            server_file: Some("server.jar".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(clean.lint().is_empty(), "{:?}", clean.lint());

        // 手动模式写好了命令 → 没告警
        let manual_ok = InstanceConfig {
            manual_command: Some(true),
            startup_command: Some("java -jar server.jar".into()),
            ..InstanceConfig::new("a", "服")
        };
        assert!(manual_ok.lint().is_empty());
    }
}
