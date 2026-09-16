//! 实例的元数据模型。
//!
//! JSON 的 key 与 V1（`EdgeCube/lib/instance/instance.dart`）**逐字对齐**，
//! 两边写出的实例配置可以互相读：V1 的 key 一个不改，daemon 新增的字段
//! 都是「多出来 V1 也会忽略」的可选键。
//!
//! 模型只描述**磁盘上有什么**，不描述进程在干什么 —— 后者归进程管理模块，
//! 见 [`ServerPhase`]。

use serde::{Deserialize, Serialize};

/// 运行环境标识（与 V1 的 `kRuntime*` 一致）。
pub const RUNTIME_JAVA: &str = "java";
pub const RUNTIME_PHP: &str = "php";
pub const RUNTIME_PROOT: &str = "proot";

/// 允许的运行环境。
pub const RUNTIMES: [&str; 3] = [RUNTIME_JAVA, RUNTIME_PHP, RUNTIME_PROOT];

/// 命令尾换行符（与 V1 的 `kLineEnding*` 一致）。
pub const LINE_ENDING_LF: &str = "\n";
pub const LINE_ENDING_CRLF: &str = "\r\n";

fn default_runtime() -> String {
    RUNTIME_JAVA.to_string()
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

/// 是否是可用的运行环境。
pub fn is_known_runtime(runtime: &str) -> bool {
    RUNTIMES.contains(&runtime)
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
/// `id` 与磁盘目录名一致；`runtime` 决定用 JVM / PHP / proot 启动，
/// 以及服务端入口文件取 `.jar` / `.phar` / 任意文件。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct InstanceConfig {
    pub id: String,
    pub name: String,
    pub runtime: String,

    /// 最大内存（MB），仅 Java 版使用。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_memory: Option<u32>,

    /// 运行环境标识：`runtime = java` 时为 JRE id（如 `jre21`）；
    /// `runtime = proot` 时为所选 rootfs id。V1 的历史 key 是 `javaVersion`。
    #[serde(alias = "javaVersion", skip_serializing_if = "Option::is_none")]
    pub runtime_env_id: Option<String>,

    /// 服务端入口文件名。V1 的历史 key 是 `selectedJar`。
    #[serde(alias = "selectedJar", skip_serializing_if = "Option::is_none")]
    pub server_file: Option<String>,

    /// 用户自定义 JVM 参数（原样追加在内置参数之后，仅 Java 版）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_jvm_args: Option<String>,

    /// 兼容模式：进程起来后跳过「启动中」阶段（适配不打印 Done 的服务端）。
    #[serde(skip_serializing_if = "is_false")]
    pub compat_mode: bool,

    /// 关服自动重启（正常退出时用相同参数重新拉起）。
    #[serde(skip_serializing_if = "is_false")]
    pub auto_restart_on_exit: bool,

    /// proot 纯容器（generic rootfs）的完整启动命令。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proot_startup_command: Option<String>,

    /// 自定义实例目录；`None` = 默认的 `<instances-root>/<id>`。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,

    /// 命令尾换行符，默认 `\n`。
    #[serde(
        default = "default_line_ending",
        skip_serializing_if = "is_default_line_ending"
    )]
    pub line_ending: String,

    // ── 以下是 daemon 侧补充的，V1 读到会忽略 ──────────────────────────
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
            runtime: default_runtime(),
            max_memory: None,
            runtime_env_id: None,
            server_file: None,
            custom_jvm_args: None,
            compat_mode: false,
            auto_restart_on_exit: false,
            proot_startup_command: None,
            path: None,
            line_ending: default_line_ending(),
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

    /// **线上**（WS / HTTP）的形态：统一 snake_case，和 daemon 其余响应一致
    /// （`uptime_ms`、`method_not_found`、`process_managed` …）。
    ///
    /// 落盘用的是 V1 的 camelCase（直接 `serde_json::to_string`），两者刻意分开：
    /// **文件格式对齐 V1，线上格式对齐 daemon 自己**。前端只需要知道一套命名。
    pub fn to_wire_value(&self) -> serde_json::Value {
        serde_json::json!({
            "id": self.id,
            "name": self.name,
            "runtime": self.runtime,
            "max_memory": self.max_memory,
            "runtime_env_id": self.runtime_env_id,
            "server_file": self.server_file,
            "custom_jvm_args": self.custom_jvm_args,
            "compat_mode": self.compat_mode,
            "auto_restart_on_exit": self.auto_restart_on_exit,
            "proot_startup_command": self.proot_startup_command,
            "path": self.path,
            "line_ending": self.line_ending,
            "created_at_ms": self.created_at_ms,
            "updated_at_ms": self.updated_at_ms,
        })
    }

    /// 是否为 PHP（PocketMine）运行环境。
    pub fn is_php(&self) -> bool {
        self.runtime == RUNTIME_PHP
    }

    /// 元数据自洽性检查的结果（不碰磁盘的部分）。
    pub fn lint(&self) -> Vec<String> {
        let mut warnings = Vec::new();
        if self.name.trim().is_empty() {
            warnings.push("实例名称为空".to_string());
        }
        if !is_known_runtime(&self.runtime) {
            warnings.push(format!(
                "未知运行环境 `{}`，可选：{}",
                self.runtime,
                RUNTIMES.join(" / ")
            ));
        }
        if self.runtime != RUNTIME_JAVA && self.max_memory.is_some() {
            warnings.push("非 Java 运行环境不使用 maxMemory，该字段会被忽略".to_string());
        }
        if self.line_ending != LINE_ENDING_LF && self.line_ending != LINE_ENDING_CRLF {
            warnings.push(format!("非常规换行符 {:?}", self.line_ending));
        }
        warnings
    }
}

/// 服务端生命周期阶段。
///
/// 取值与 V1 的 `ServerStatus`（`lib/server/server_controller.dart`）对齐，
/// 只多一个 [`ServerPhase::Crashed`] —— 进程异常退出要和「用户主动停止」区分开，
/// 否则前端只能把崩溃显示成"已停止"。
///
/// **当前 daemon 还没有进程管理模块**，所以 `instance.status` 一律返回
/// [`ServerPhase::Stopped`]，并用 `process_managed = false` 明说这件事。
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
    /// 异常退出（daemon 侧扩展，V1 没有）。
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

    /// 是否算「正在运行」（等价 V1 的 `isRunning`）。
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

/// 实例状态：**磁盘视角** + 预留的进程阶段。
#[derive(Debug, Clone, Serialize)]
pub struct InstanceStatus {
    pub id: String,
    pub name: String,
    /// 生命周期阶段（见 [`ServerPhase`]）。
    pub phase: ServerPhase,
    pub running: bool,
    /// 进程管理是否已接入。当前恒为 `false` —— `phase` 还不会动。
    pub process_managed: bool,
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

    #[test]
    fn json_keys_match_v1() {
        let cfg = InstanceConfig {
            id: "a1".into(),
            name: "生存服".into(),
            runtime: RUNTIME_JAVA.into(),
            max_memory: Some(2048),
            runtime_env_id: Some("jre21".into()),
            server_file: Some("server.jar".into()),
            custom_jvm_args: Some("-XX:+UseZGC".into()),
            compat_mode: true,
            auto_restart_on_exit: true,
            proot_startup_command: None,
            path: None,
            line_ending: LINE_ENDING_CRLF.into(),
            created_at_ms: Some(1),
            updated_at_ms: Some(2),
        };
        let value = serde_json::to_value(&cfg).expect("应能序列化");
        // V1 的 key 一个都不能变
        for key in [
            "id",
            "name",
            "runtime",
            "maxMemory",
            "runtimeEnvId",
            "serverFile",
            "customJvmArgs",
            "compatMode",
            "autoRestartOnExit",
            "lineEnding",
        ] {
            assert!(
                value.get(key).is_some(),
                "缺少 V1 兼容 key: {key}（{value}）"
            );
        }
        // 默认值不落盘
        let minimal = InstanceConfig::new("a1", "服");
        let value = serde_json::to_value(&minimal).expect("应能序列化");
        assert!(value.get("maxMemory").is_none());
        assert!(value.get("compatMode").is_none());
        assert!(value.get("lineEnding").is_none(), "默认换行符不该写出来");
        assert!(value.get("prootStartupCommand").is_none());
    }

    #[test]
    fn wire_shape_is_snake_case_while_file_stays_v1_camel_case() {
        let cfg = InstanceConfig {
            id: "a1".into(),
            name: "生存服".into(),
            runtime: RUNTIME_JAVA.into(),
            max_memory: Some(2048),
            runtime_env_id: Some("jre21".into()),
            server_file: Some("server.jar".into()),
            created_at_ms: Some(7),
            ..Default::default()
        };

        // 线上：snake_case，且缺省项也是显式 null（前端不用猜字段在不在）
        let wire = cfg.to_wire_value();
        assert_eq!(wire["max_memory"], json!(2048));
        assert_eq!(wire["runtime_env_id"], json!("jre21"));
        assert_eq!(wire["server_file"], json!("server.jar"));
        assert_eq!(wire["created_at_ms"], json!(7));
        assert_eq!(wire["compat_mode"], json!(false));
        assert!(wire["proot_startup_command"].is_null());
        assert!(wire.get("maxMemory").is_none(), "线上不该出现 camelCase");

        // 文件：V1 的 camelCase
        let file = serde_json::to_value(&cfg).unwrap();
        assert_eq!(file["maxMemory"], json!(2048));
        assert_eq!(file["runtimeEnvId"], json!("jre21"));
        assert_eq!(file["createdAtMs"], json!(7));
    }

    #[test]
    fn reads_v1_legacy_keys_and_ignores_unknown_ones() {
        // V1 老版本写的是 javaVersion / selectedJar
        let cfg: InstanceConfig = serde_json::from_value(json!({
            "id": "x",
            "name": "老实例",
            "javaVersion": "jre17",
            "selectedJar": "paper.jar",
            "someFutureKey": {"nested": true}
        }))
        .expect("应能读 V1 历史配置");
        assert_eq!(cfg.runtime, RUNTIME_JAVA, "缺省运行环境应为 java");
        assert_eq!(cfg.runtime_env_id.as_deref(), Some("jre17"));
        assert_eq!(cfg.server_file.as_deref(), Some("paper.jar"));
        assert_eq!(cfg.line_ending, LINE_ENDING_LF);
        assert_eq!(cfg.created_at_ms, None);
    }

    #[test]
    fn phase_matches_v1_and_serializes_snake_case() {
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
    fn lint_flags_suspicious_metadata() {
        let cfg = InstanceConfig {
            runtime: "native".into(),
            line_ending: "\r".into(),
            ..InstanceConfig::new("a", "服")
        };
        let warnings = cfg.lint();
        assert!(
            warnings.iter().any(|w| w.contains("未知运行环境")),
            "{warnings:?}"
        );
        assert!(
            warnings.iter().any(|w| w.contains("换行符")),
            "{warnings:?}"
        );

        let clean = InstanceConfig::new("a", "服");
        assert!(clean.lint().is_empty(), "正常配置不该有告警");
    }
}
