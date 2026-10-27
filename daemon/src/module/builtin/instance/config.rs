//! 服务端配置文件的检测与读写（「服务器配置」功能的后端那一半）。
//!
//! # 为什么「认哪种配置」放在这里
//!
//! V2 的**入口文案通用**，进去之后由 daemon 回答「这个实例有哪种配置」。
//!
//! 这么切的两个理由：
//!
//! * 判断依据是**磁盘上的文件**，而磁盘归 daemon 管（前端连实例目录在哪都不该知道）；
//! * 前端少一份「优先级表」要维护 —— 加一种服务端配置只动这里。
//!
//! 字段表（每个字段叫什么、用什么控件、下拉有哪些选项）**留在前端**，所以这一层
//! 只做两件事：[`detect`] 认文件、[`load`] / [`save`] 读写文件。
//!
//! # 检测优先级
//!
//! ```text
//! pnx.yml  >  server-settings.yml  >  server.properties
//! ```
//!
//! 前一个在就轮不到后一个。三种都没有时 `kind = None` —— 上层给「先启动一次
//! 服务端生成配置文件」的文案。
//!
//! # Java 与 PocketMine 共用 `server.properties`
//!
//! 两者文件名一样、字段也大多重合，差别在**布尔值的写法**（Java `true`/`false`、
//! PocketMine `on`/`off`）与几个属性的取值集合。V2 的实例元数据里没有「实例
//! 是不是 PHP 运行环境」这个信息，所以**看文件本身**：先看有没有 PMMP 必写的
//! `pocketmine.yml`，再看 `server.properties` 里的布尔值长什么样。
//!
//! # 服务端图标（`server-icon.png`）
//!
//! 这是**另一个文件**（不在那三种配置里），只有 Java 系服务端认它，所以
//! [`Icon`] 的读写单独一对方法。Minecraft 硬性要求 64×64，所以写入前
//! **必须校验**（见 [`check_icon`]）—— 顺手也挡住前端把裁剪算错这种 bug：
//! 一幅尺寸不对的图标服务端会直接忽略，用户看到的现象是「改了没反应」，
//! 那比报错难查得多。

use std::io;
use std::path::Path;

use base64::Engine as _;
use serde_json::{Value, json};

/// 一次读入的上限。配置文件都是几 KB，1 MiB 足够，也挡住误传大文件。
const MAX_BYTES: u64 = 1024 * 1024;

/// 服务端图标。Minecraft 只认这个文件名与这个尺寸。
pub const ICON_FILE: &str = "server-icon.png";

/// Minecraft 要求的图标边长。
pub const ICON_SIDE: u32 = 64;

/// 图标文件的大小上限。
///
/// 64×64 的 PNG 撑死几十 KB，256 KiB 宽裕得很，同时挡住「拿这里当图床」。
const ICON_MAX_BYTES: usize = 256 * 1024;

/// PocketMine 一定会生成的主配置（用它确认「这是个 PMMP 服务端」）。
const PMMP_MARKER: &str = "pocketmine.yml";

/// 用来探布尔值写法的几个键。PMMP 的 `server.properties` 里它们一定在，
/// 且一定是 `on`/`off`；Java 版的同名键一定是 `true`/`false`。
const BOOL_SNIFF_KEYS: [&str; 3] = ["pvp", "enable-query", "white-list"];

/// 一种可编辑的服务端配置。
///
/// `Java` 与 `Pmmp` **共用一个文件**，是两个不同的字段表（前端按 `wire_name`
/// 选）。分开成一个枚举值而不是「kind + 一个变体字段」：前端只要认一个字符串。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigKind {
    /// `pnx.yml`（PowerNukkitX）。
    Pnx,
    /// `server-settings.yml`（Allay）。
    Allay,
    /// `server.properties`，Java 版（`true`/`false`）。
    Java,
    /// `server.properties`，PocketMine 版（`on`/`off`）。
    Pmmp,
}

impl ConfigKind {
    /// 线上名字。**前端按它选字段表**，所以是契约的一部分，改了要两边一起改。
    pub fn wire_name(self) -> &'static str {
        match self {
            ConfigKind::Pnx => "pnx",
            ConfigKind::Allay => "allay",
            ConfigKind::Java => "java",
            ConfigKind::Pmmp => "pmmp",
        }
    }

    /// 这条配置落在哪个文件（**相对实例目录**）。
    ///
    /// 保存时用**这里算出来的名字**，不接受前端给路径 —— 否则就是一个
    /// 「按 id 写任意文件」的洞。
    pub fn file_name(self) -> &'static str {
        match self {
            ConfigKind::Pnx => "pnx.yml",
            ConfigKind::Allay => "server-settings.yml",
            ConfigKind::Java | ConfigKind::Pmmp => "server.properties",
        }
    }

    /// 从线上名字解析回来（保存请求里带的那个）。
    pub fn parse(wire: &str) -> Option<Self> {
        match wire.trim() {
            "pnx" => Some(ConfigKind::Pnx),
            "allay" => Some(ConfigKind::Allay),
            "java" => Some(ConfigKind::Java),
            "pmmp" => Some(ConfigKind::Pmmp),
            _ => None,
        }
    }
}

/// 一次检测的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Detected {
    /// 认出来的配置类型；三种都没有时为 `None`。
    pub kind: Option<ConfigKind>,
    /// 文件内容（不存在时为空串）。
    pub content: String,
}

impl Detected {
    /// 线上形状（`instance.config.get` 的返回）。
    pub fn to_wire(&self) -> Value {
        json!({
            "kind": self.kind.map(ConfigKind::wire_name),
            // 文件不存在时也给个名字 —— 前端要拿它写「没有 server.properties」这句话
            "file": self.kind.map(ConfigKind::file_name).unwrap_or(DEFAULT_FILE),
            "exists": self.kind.is_some(),
            "content": self.content,
        })
    }
}

/// 三种都没有时对外报的文件名。取最常用的那个。
const DEFAULT_FILE: &str = "server.properties";

/// 认这个实例用的是哪种配置，并把内容读出来。
///
/// 文件存在但读不出来（权限、不是 UTF-8）会如实报错 —— 静默当成「没有配置」
/// 会把用户送进「请先启动一次服务器」那条路，而文件其实好好躺在那儿。
pub fn load(dir: &Path) -> io::Result<Detected> {
    let Some(kind) = detect_kind(dir) else {
        return Ok(Detected {
            kind: None,
            content: String::new(),
        });
    };

    let path = dir.join(kind.file_name());
    let meta = std::fs::metadata(&path)?;
    if meta.len() > MAX_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{} 太大（{} 字节）", kind.file_name(), meta.len()),
        ));
    }
    let content = std::fs::read_to_string(&path)?;
    Ok(Detected {
        kind: Some(kind),
        content,
    })
}

/// 只认类型不读内容（检测逻辑单独可测）。
pub fn detect_kind(dir: &Path) -> Option<ConfigKind> {
    if dir.join(ConfigKind::Pnx.file_name()).is_file() {
        return Some(ConfigKind::Pnx);
    }
    if dir.join(ConfigKind::Allay.file_name()).is_file() {
        return Some(ConfigKind::Allay);
    }
    if dir.join(ConfigKind::Java.file_name()).is_file() {
        return Some(properties_variant(dir));
    }
    None
}

/// `server.properties` 是 Java 版还是 PocketMine 版。
///
/// 两步：PMMP 必写的 `pocketmine.yml` 在 → 就是它；否则看内容里布尔值的写法
/// （`on`/`off` → PMMP）。都判断不出来时按 Java（最常见的那一种）。
///
/// 读不到内容（刚被删、没权限）也按 Java —— 这时候前端选哪张表都可能不对，
/// 而 Java 的概率最高，且用户可以自己看得懂。
fn properties_variant(dir: &Path) -> ConfigKind {
    if dir.join(PMMP_MARKER).is_file() {
        return ConfigKind::Pmmp;
    }
    let Ok(content) = std::fs::read_to_string(dir.join(ConfigKind::Java.file_name())) else {
        return ConfigKind::Java;
    };
    if looks_like_pmmp(&content) {
        ConfigKind::Pmmp
    } else {
        ConfigKind::Java
    }
}

/// 内容里有没有 PMMP 那种 `on`/`off` 布尔写法。
///
/// 只看那几个**两个版本都有、且都当布尔**的键：随便挑一个键会被注释里的示例
/// 或别的服务端插件配置带偏。
fn looks_like_pmmp(content: &str) -> bool {
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if !BOOL_SNIFF_KEYS.contains(&key) {
            continue;
        }
        let value = value.trim().to_ascii_lowercase();
        // 命中一个已知布尔键就下结论：on/off 是 PMMP，true/false 是 Java。
        // 两个都不是（比如被改成了别的东西）就继续看下一个。
        if value == "on" || value == "off" {
            return true;
        }
        if value == "true" || value == "false" {
            return false;
        }
    }
    false
}

/// 把前端编辑好的整份内容写回去。
///
/// * `kind` 决定写哪个文件（白名单，见 [`ConfigKind::file_name`]）；
/// * **文件必须已经存在** —— 这一层不做「新建配置文件」。新建是服务端自己启动时
///   的事（它才知道该生成哪些字段），凭空写一个半成品只会让服务端起不来；
/// * 原子写：先写 `.tmp` 再 `rename`，中途崩溃不会留下半个配置。
pub fn save(dir: &Path, kind: ConfigKind, content: &str) -> Result<(), String> {
    if content.len() as u64 > MAX_BYTES {
        return Err(format!(
            "内容太大（{} 字节），超过上限 {} 字节",
            content.len(),
            MAX_BYTES
        ));
    }

    let path = dir.join(kind.file_name());
    if !path.is_file() {
        return Err(format!(
            "{} 不存在 —— 先启动一次服务端让它生成",
            kind.file_name()
        ));
    }

    write_atomic(&path, content.as_bytes())
        .map_err(|e| format!("写入 {} 失败：{e}", kind.file_name()))
}

/// 一次图标读取的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Icon {
    /// 还没有图标。
    Missing,
    /// 有，这是原样字节。
    Present(Vec<u8>),
}

impl Icon {
    /// 线上形状。`data` 是 base64（图标只有几 KB，走 WS 完全够用 ——
    /// 几十 MB 的存档 / jar 那种才必须走 HTTP，见 `files::transfer`）。
    pub fn to_wire(&self) -> Value {
        match self {
            Icon::Missing => json!({
                "file": ICON_FILE,
                "exists": false,
                "data": Value::Null,
            }),
            Icon::Present(bytes) => json!({
                "file": ICON_FILE,
                "exists": true,
                "data": base64::engine::general_purpose::STANDARD.encode(bytes),
            }),
        }
    }
}

/// 读服务端图标。
///
/// 读不出来（权限、文件被占）会如实报错 —— 与 [`load`] 同一个取舍：静默当成
/// 「没有图标」会让用户以为图标丢了。
pub fn load_icon(dir: &Path) -> io::Result<Icon> {
    let path = dir.join(ICON_FILE);
    match std::fs::read(&path) {
        Ok(bytes) => Ok(Icon::Present(bytes)),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Icon::Missing),
        Err(e) => Err(e),
    }
}

/// 写服务端图标（先校验再原子写）。
pub fn save_icon(dir: &Path, bytes: &[u8]) -> Result<(), String> {
    check_icon(bytes)?;
    write_atomic(&dir.join(ICON_FILE), bytes).map_err(|e| format!("写入 {ICON_FILE} 失败：{e}"))
}

/// 把线上传来的 base64 解成字节。
///
/// 单独一个函数是为了把「这不是合法 base64」与「这不是合格 PNG」分成两种错误码：
/// 前者是调用方发错了（`invalid_params`），后者是内容不对（`instance_icon_invalid`）。
pub fn decode_icon(data_base64: &str) -> Result<Vec<u8>, String> {
    base64::engine::general_purpose::STANDARD
        .decode(data_base64.trim())
        .map_err(|e| format!("图标数据不是合法的 base64：{e}"))
}

/// 校验这是不是一份能用的服务端图标。
///
/// Minecraft 只认 **64×64 的 PNG**，尺寸不对它**静默忽略**（服务器照跑、图标不换）。
/// 那种「改了没反应」最难查，所以宁可在入口就拒掉。
///
/// 只读 PNG 的头两段就够，不必引图片库：
///
/// ```text
/// 0..8   签名 \x89PNG\r\n\x1a\n
/// 8..12  IHDR 段长度（恒为 13）
/// 12..16 段名 "IHDR"
/// 16..20 宽（大端 u32）
/// 20..24 高（大端 u32）
/// ```
///
/// 这是 PNG 规范的硬约束，所以自己读是安全的（不是「手写图片解析」那种活）。
pub fn check_icon(bytes: &[u8]) -> Result<(), String> {
    if bytes.is_empty() {
        return Err("图标是空的".to_string());
    }
    if bytes.len() > ICON_MAX_BYTES {
        return Err(format!(
            "图标太大（{} 字节），超过上限 {} 字节",
            bytes.len(),
            ICON_MAX_BYTES
        ));
    }
    const SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    if bytes.len() < 24 || bytes[..8] != SIGNATURE {
        return Err("图标必须是 PNG".to_string());
    }
    if &bytes[12..16] != b"IHDR" {
        return Err("PNG 的头一段不是 IHDR —— 这个文件不完整或不是 PNG".to_string());
    }
    let width = u32::from_be_bytes(bytes[16..20].try_into().expect("切片长度已检查"));
    let height = u32::from_be_bytes(bytes[20..24].try_into().expect("切片长度已检查"));
    if width != ICON_SIDE || height != ICON_SIDE {
        return Err(format!(
            "图标必须是 {ICON_SIDE}×{ICON_SIDE}，这份是 {width}×{height}"
        ));
    }
    Ok(())
}

/// 原子写字节：先写唯一命名的临时文件，再 `rename`。
///
/// 临时文件名带 pid + 进程内序号（照 `store::write_json` 那套）：两个写入者共用
/// `<file>.tmp` 时，先完成的一方 rename 之后，另一方的 rename 会因为源文件没了
/// 而报 `ENOENT` —— 明明是个正常并发却写成失败。
fn write_atomic(path: &Path, content: &[u8]) -> io::Result<()> {
    use std::sync::atomic::{AtomicU64, Ordering};

    static SEQ: AtomicU64 = AtomicU64::new(0);

    let tmp = std::path::PathBuf::from(format!(
        "{}.{}.{}.tmp",
        path.display(),
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&tmp, content)?;
    match std::fs::rename(&tmp, path) {
        Ok(()) => Ok(()),
        Err(e) => {
            // 失败时别把临时文件留在实例目录里
            let _ = std::fs::remove_file(&tmp);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 每个用例一个独立临时目录（daemon 的测试不受 /tmp 大小限制）。
    struct TempDir(std::path::PathBuf);

    impl TempDir {
        fn new(tag: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "ec-config-{tag}-{}-{}",
                std::process::id(),
                crate::util::now_ms()
            ));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).expect("应当能建临时目录");
            Self(path)
        }

        fn write(&self, name: &str, content: &str) {
            std::fs::write(self.0.join(name), content).expect("应当能写文件");
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn detects_nothing_in_an_empty_dir() {
        let temp = TempDir::new("empty");
        assert_eq!(detect_kind(&temp.0), None);
        let loaded = load(&temp.0).unwrap();
        assert_eq!(loaded.kind, None);
        // 线上形状：kind 是 null、exists 是 false，但文件名照给
        assert_eq!(loaded.to_wire()["kind"], json!(null));
        assert_eq!(loaded.to_wire()["exists"], json!(false));
        assert_eq!(loaded.to_wire()["file"], json!("server.properties"));
        assert_eq!(loaded.to_wire()["content"], json!(""));
    }

    /// 优先级：pnx.yml 压过另外两个。
    #[test]
    fn pnx_wins_over_the_other_two() {
        let temp = TempDir::new("priority");
        temp.write("server.properties", "motd=hi\n");
        temp.write("server-settings.yml", "settings:\n");
        temp.write("pnx.yml", "settings:\n  motd: hi\n");

        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Pnx));
        let loaded = load(&temp.0).unwrap();
        assert_eq!(loaded.to_wire()["file"], json!("pnx.yml"));
        assert!(loaded.content.contains("motd"));
    }

    /// allay 压过 server.properties。
    #[test]
    fn allay_wins_over_properties() {
        let temp = TempDir::new("allay");
        temp.write("server.properties", "motd=hi\n");
        temp.write("server-settings.yml", "settings:\n");

        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Allay));
    }

    #[test]
    fn plain_properties_is_the_java_variant() {
        let temp = TempDir::new("java");
        temp.write("server.properties", "pvp=true\nmotd=hi\n");
        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Java));
    }

    /// PMMP：靠 `pocketmine.yml` 认出来，哪怕 `server.properties` 里没留下线索。
    #[test]
    fn pocketmine_marker_makes_it_the_pmmp_variant() {
        let temp = TempDir::new("pmmp-marker");
        temp.write("pocketmine.yml", "settings:\n");
        temp.write("server.properties", "pvp=on\n");
        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Pmmp));
    }

    /// 没有 `pocketmine.yml` 时，看布尔值写法也能认出来。
    #[test]
    fn on_off_booleans_also_mean_pmmp() {
        let temp = TempDir::new("pmmp-sniff");
        temp.write("server.properties", "# a comment\npvp=on\nmotd=hi\n");
        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Pmmp));
    }

    /// 注释里的示例不该把判断带偏（先看真键）。
    #[test]
    fn commented_lines_do_not_affect_the_variant() {
        let temp = TempDir::new("pmmp-comment");
        temp.write(
            "server.properties",
            "# pvp=on 是 PocketMine 的写法\npvp=true\n",
        );
        assert_eq!(detect_kind(&temp.0), Some(ConfigKind::Java));
    }

    #[test]
    fn wire_names_round_trip() {
        for kind in [
            ConfigKind::Pnx,
            ConfigKind::Allay,
            ConfigKind::Java,
            ConfigKind::Pmmp,
        ] {
            assert_eq!(ConfigKind::parse(kind.wire_name()), Some(kind));
        }
        assert_eq!(ConfigKind::parse("nope"), None);
        assert_eq!(ConfigKind::parse("  java  "), Some(ConfigKind::Java));
    }

    #[test]
    fn save_writes_the_file_the_kind_points_at() {
        let temp = TempDir::new("save");
        temp.write("server.properties", "motd=old\n");

        save(&temp.0, ConfigKind::Java, "motd=new\n").expect("应当能保存");
        assert_eq!(
            std::fs::read_to_string(temp.0.join("server.properties")).unwrap(),
            "motd=new\n"
        );
        // 原子写的临时文件不该留下
        let leftovers: Vec<_> = std::fs::read_dir(&temp.0)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|name| name.ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "不该留下临时文件：{leftovers:?}");
    }

    /// 保存只能写「这条 kind 对应的那个文件」。
    #[test]
    fn save_refuses_when_the_file_is_not_there() {
        let temp = TempDir::new("save-missing");
        let err = save(&temp.0, ConfigKind::Pnx, "settings:\n").unwrap_err();
        assert!(err.contains("pnx.yml"), "{err}");
        assert!(!temp.0.join("pnx.yml").exists(), "不该凭空建文件");
    }

    #[test]
    fn save_rejects_oversized_content() {
        let temp = TempDir::new("save-big");
        temp.write("server.properties", "motd=hi\n");
        let huge = "x".repeat((MAX_BYTES + 1) as usize);
        let err = save(&temp.0, ConfigKind::Java, &huge).unwrap_err();
        assert!(err.contains("太大"), "{err}");
    }

    /// Java 与 PMMP 共用 `server.properties`，但线上名字不同 —— 前端靠它选表。
    #[test]
    fn java_and_pmmp_share_a_file_but_not_a_name() {
        assert_eq!(ConfigKind::Java.file_name(), ConfigKind::Pmmp.file_name());
        assert_ne!(ConfigKind::Java.wire_name(), ConfigKind::Pmmp.wire_name());
    }

    // ── 服务端图标 ────────────────────────────────────────────────────────

    /// 一份**只有头部**的 PNG。
    ///
    /// [`check_icon`] 只读签名与 IHDR（宽高在那儿），所以校验用例不需要真的图像
    /// 数据。真正「能解码的 PNG」由 Dart 那边的用例与 e2e 覆盖 —— 它们用
    /// `dart:ui` 的编码器现生成一份。
    fn png_header(width: u32, height: u32) -> Vec<u8> {
        let mut out = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
        out.extend_from_slice(&13u32.to_be_bytes()); // IHDR 长度
        out.extend_from_slice(b"IHDR");
        out.extend_from_slice(&width.to_be_bytes());
        out.extend_from_slice(&height.to_be_bytes());
        out.extend_from_slice(&[8, 6, 0, 0, 0]); // 8 位 RGBA
        out.extend_from_slice(&[0, 0, 0, 0]); // CRC 占位（本模块不校验它）
        out
    }

    #[test]
    fn icon_accepts_a_64x64_png() {
        assert!(check_icon(&png_header(64, 64)).is_ok());
    }

    #[test]
    fn icon_rejects_wrong_dimensions() {
        // 尺寸不对时 Minecraft 会**静默忽略**（服务器照跑、图标不换），
        // 所以宁可在入口拒掉 —— 那是最难查的一类现象。
        for (w, h) in [(32, 32), (128, 128), (64, 128), (128, 64), (63, 63)] {
            let err = check_icon(&png_header(w, h)).unwrap_err();
            assert!(err.contains(&format!("{w}×{h}")), "{err}");
        }
    }

    #[test]
    fn icon_rejects_non_png() {
        assert!(check_icon(b"").unwrap_err().contains("空"));
        // JPEG 的头
        assert!(check_icon(&[0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]).is_err());
        // 签名对但截断在 IHDR 之前
        let mut short = png_header(64, 64);
        short.truncate(20);
        assert!(check_icon(&short).is_err());
    }

    #[test]
    fn icon_rejects_oversized_payloads() {
        let mut huge = png_header(64, 64);
        huge.resize(ICON_MAX_BYTES + 1, 0);
        assert!(check_icon(&huge).unwrap_err().contains("太大"));
    }

    #[test]
    fn icon_round_trips_and_reports_missing() {
        let temp = TempDir::new("icon");
        assert_eq!(load_icon(&temp.0).unwrap(), Icon::Missing);
        assert_eq!(
            load_icon(&temp.0).unwrap().to_wire()["exists"],
            json!(false)
        );

        let png = png_header(64, 64);
        save_icon(&temp.0, &png).expect("64×64 的 PNG 应当能存");
        assert_eq!(load_icon(&temp.0).unwrap(), Icon::Present(png.clone()));
        // 落盘的是原样字节（没有二次编码）
        assert_eq!(std::fs::read(temp.0.join(ICON_FILE)).unwrap(), png);

        let wire = load_icon(&temp.0).unwrap().to_wire();
        assert_eq!(wire["file"], json!(ICON_FILE));
        assert_eq!(wire["exists"], json!(true));
        // 线上是 base64
        assert_eq!(
            wire["data"],
            json!(base64::engine::general_purpose::STANDARD.encode(&png))
        );

        // 原子写不该留下临时文件
        let leftovers: Vec<_> = std::fs::read_dir(&temp.0)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|name| name.ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "不该留下临时文件：{leftovers:?}");
    }

    /// 校验不过就**别写文件** —— 覆盖掉一份好图标比报错糟得多。
    #[test]
    fn bad_icon_does_not_touch_the_existing_file() {
        let temp = TempDir::new("icon-bad");
        let good = png_header(64, 64);
        save_icon(&temp.0, &good).unwrap();

        let err = save_icon(&temp.0, &png_header(32, 32)).unwrap_err();
        assert!(err.contains("32×32"), "{err}");
        assert_eq!(
            std::fs::read(temp.0.join(ICON_FILE)).unwrap(),
            good,
            "旧图标应当原样还在"
        );
    }

    /// base64 解不开是**调用方发错了**（`invalid_params`），与「内容不是合格 PNG」
    /// （`instance_icon_invalid`）是两回事，所以分开报。
    #[test]
    fn icon_data_must_be_valid_base64() {
        let png = png_header(64, 64);
        let encoded = base64::engine::general_purpose::STANDARD.encode(&png);
        assert_eq!(decode_icon(&encoded).unwrap(), png);
        // 前后空白容错（HTTP 那一侧有时会带换行）
        assert_eq!(decode_icon(&format!("  {encoded}\n")).unwrap(), png);
        assert!(decode_icon("这不是 base64！！").is_err());
    }
}
