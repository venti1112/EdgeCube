//! EULA 同意机制。
//!
//! 启动 Minecraft 服务端前必须让用户同意 EULA —— 服务端自己会在启动时读
//! 实例目录下的 `eula.txt`，里面没有 `eula=true` 就直接退出。
//!
//! # 为什么在 daemon
//!
//! `eula.txt` 在**服务端机器上**，V2 的文件归 daemon 管，
//! 于是「判断 + 写入」都留在这边，前端只发两个 RPC（与 `instance.config.*`
//! 是同一条分工：**文件长什么样是后端的事**）。
//!
//! # 与前端约定的对应
//!
//! * `eula.txt` 的路径 —— [`FILE`]，相对实例工作目录。
//! * 「已同意」判定 —— [`is_agreed`]，忽略大小写地找 `eula` + 空白 + `=`
//!   + 空白 + `true`。
//! * 同意写入 —— [`accept`]，内容固定为 [`ACCEPTED_CONTENT`]（一行注释 +
//!   `eula=true` + 结尾换行）。
//! * 前端在 `instance.start` 之前调「读状态」与「同意」这两个方法。

use std::fs;
use std::path::Path;

use serde::Serialize;

/// 文件名。**不许改**：服务端自己认的就是这个名字。
pub const FILE: &str = "eula.txt";

/// 同意之后写进去的内容（一行注释 + `eula=true` + 结尾换行）。
pub const ACCEPTED_CONTENT: &str = "#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\neula=true\n";

/// `eula.txt` 的当前状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Status {
    /// 文件在不在这儿。
    ///
    /// 服务端**第一次启动之后**才会自己生成一份 `eula=false` 的，所以新实例上
    /// 通常不存在 —— 那正是要弹框的情形。
    pub exists: bool,
    /// 里面有没有 `eula=true`。
    pub agreed: bool,
}

/// 读一个实例的 EULA 状态。
///
/// 读不出来（不存在 / 权限 / 不是 UTF-8）一律当「没同意」—— 那本来就是
/// 「要弹框问用户」的情形，不该因为读不到文件就让启动流程报错。
pub fn status(root: &Path) -> Status {
    let path = root.join(FILE);
    let Ok(content) = fs::read_to_string(&path) else {
        return Status {
            exists: path.is_file(),
            agreed: false,
        };
    };
    Status {
        exists: true,
        agreed: is_agreed(&content),
    }
}

/// 同意：把固定内容写进 `eula.txt`（**没有就建**）。
///
/// 这里直接用 `fs::write`（**没有就建**），而 `instance.files.write` **不行** ——
/// 它只写已存在的文件（新实例上 `eula.txt` 还没被服务端生成过）。
/// 这也是为什么这件事没走「文件编辑」那条路。
pub fn accept(root: &Path) -> std::io::Result<()> {
    fs::write(root.join(FILE), ACCEPTED_CONTENT)
}

/// 这段内容算不算「已同意」。
///
/// 忽略大小写，找 `eula` + 任意空白 + `=` + 任意空白 + `true`。
///
/// **不写成 `contains("eula=true")`**：`\s*` 允许中间夹空格 / 制表 / 换行
/// （用户手改过、或不同服务端的排版不一样），`contains` 会漏掉 `eula = true`。
/// 反过来，这个判定**没有锚定在行首**，所以 `# eula=true` 这种注释行、
/// 甚至 `noteula=true` 都算「已同意」—— 这个宽松口径是刻意保留的，
/// 宁可多认几个也别把已经同意过的用户再拦一次。
///
/// 只在**字节层面**扫（不切 `&str`）：内容可能是任意 UTF-8，
/// 按字符边界切片会 panic，而这里全程只用 ASCII 判定。
pub fn is_agreed(content: &str) -> bool {
    // `to_ascii_lowercase` 只折 ASCII，长度不变，字节下标仍然对得上
    let bytes = content.to_ascii_lowercase().into_bytes();
    let mut at = 0;
    while at + 4 <= bytes.len() {
        if &bytes[at..at + 4] != b"eula" {
            at += 1;
            continue;
        }
        let mut cursor = at + 4;
        while cursor < bytes.len() && is_space(bytes[cursor]) {
            cursor += 1;
        }
        if cursor >= bytes.len() || bytes[cursor] != b'=' {
            at += 1;
            continue;
        }
        cursor += 1;
        while cursor < bytes.len() && is_space(bytes[cursor]) {
            cursor += 1;
        }
        if bytes[cursor..].starts_with(b"true") {
            return true;
        }
        at += 1;
    }
    false
}

/// Dart 正则里 `\s` 认的那几个 ASCII 空白。
///
/// 特意把 `\v`（0x0B）也算上 —— Dart 的 `\s` 含它，而
/// `u8::is_ascii_whitespace` **不含**（它只认空格 / `\t` / `\n` / `\f` / `\r`）。
/// 非 ASCII 的 Unicode 空白（如 U+00A0）不认，这一档差异可以忽略。
fn is_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── 判定 ──────────────────────────────────────────────────────────────

    #[test]
    fn accepts_the_shapes_a_real_eula_txt_has() {
        // 服务端自己生成的那一行
        assert!(is_agreed("eula=true\n"));
        // 我们写进去的整份内容
        assert!(is_agreed(ACCEPTED_CONTENT));
        // 带空格的（用户手改过）
        assert!(is_agreed("eula = true"));
        assert!(is_agreed("eula\t=\ttrue"));
        // `\s*` 能跨行 —— 这是正则原样，别「顺手收紧」
        assert!(is_agreed("eula=\ntrue"));
        // 大小写不敏感
        assert!(is_agreed("EULA=TRUE"));
        assert!(is_agreed("Eula=True"));
    }

    #[test]
    fn rejects_when_it_is_not_agreed() {
        assert!(!is_agreed(""));
        assert!(!is_agreed("eula=false\n"));
        assert!(!is_agreed("eula = false"));
        // 缺了 `=`（只有 "eula true" 不算）
        assert!(!is_agreed("eula true"));
        // 写成别的值
        assert!(!is_agreed("eula=1"));
        // 只写了半个
        assert!(!is_agreed("eula="));
        assert!(!is_agreed("eul"));
    }

    /// 判定没有锚定行首，所以注释行与「粘在别的词后面」的写法**都算同意**。
    /// 这是刻意保留的宽松口径 —— 宁可多认，也别把已经同意过的用户再拦一次。
    #[test]
    fn agreed_regex_is_unanchored_and_loose() {
        assert!(is_agreed("# eula=true 我同意了\n"));
        assert!(is_agreed("noteula=true"));
    }

    #[test]
    fn does_not_panic_on_multibyte_content() {
        // 内容里有非 ASCII，扫字节时不能按字符切
        assert!(!is_agreed("中文注释eul中ä文"));
        assert!(is_agreed("中文注释：eula=true\n"));
        // 结尾正好卡在多字节字符中间的情形
        assert!(!is_agreed("eul中"));
        assert!(!is_agreed("eula中"));
        assert!(!is_agreed("eula=中"));
    }

    // ── 读写 ──────────────────────────────────────────────────────────────

    #[test]
    fn status_and_accept_round_trip_on_a_temp_dir() {
        let root = std::env::temp_dir().join("edgecube-eula-test");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        // 新实例：文件还没有 → 没同意
        let fresh = status(&root);
        assert!(!fresh.exists, "新实例上服务端还没生成 eula.txt");
        assert!(!fresh.agreed);

        // 同意 → 建文件 + 写固定内容
        accept(&root).unwrap();
        let content = fs::read_to_string(root.join(FILE)).unwrap();
        assert_eq!(content, ACCEPTED_CONTENT, "内容要符合约定");
        assert!(content.ends_with('\n'), "结尾带换行");

        let after = status(&root);
        assert!(after.exists);
        assert!(after.agreed);

        // 服务端把它改回 false（或者用户手改）→ 又要重新同意
        fs::write(root.join(FILE), "eula=false\n").unwrap();
        assert!(!status(&root).agreed);
        assert!(status(&root).exists, "文件在，只是没同意");

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn status_treats_unreadable_content_as_not_agreed() {
        let root = std::env::temp_dir().join("edgecube-eula-binary-test");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        // 不是合法 UTF-8：读不出来就当没同意（不该让启动流程报错）
        fs::write(root.join(FILE), [0xff, 0xfe, 0x00]).unwrap();
        let status = status(&root);
        assert!(status.exists);
        assert!(!status.agreed);
        let _ = fs::remove_dir_all(&root);
    }
}
