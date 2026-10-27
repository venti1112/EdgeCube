//! 从实例目录读「服务端实际监听的端口」。
//!
//! 优先级与 V1（`server_controller.dart` 的 `readServerPort`）逐条一致：
//!
//! 1. `server.properties`（Java）—— `server-port`，缺省 25565；
//! 2. `pnx.yml`（PowerNukkitX）—— `settings.port`，缺省 19132；
//! 3. `server-settings.yml`（Allay）—— `network-settings.port`，缺省 19132；
//! 4. 都没有 —— 25565。
//!
//! 两个注意点：
//!
//! * **认文件不认服务端**：先看 `server.properties` 在不在，在就不再往后看
//!   （哪怕里面没写 `server-port`，也是用它的缺省 25565）—— V1 就是这么做的；
//! * 读取或解析出任何差错都退回 25565（V1 的 `catch (_) { return 25565; }`），
//!   这里体现为 [`read_port`] 永远返回一个端口，没有 `Option`。
//!
//! YAML 只支持这两种配置实际用到的子集（同 V1 的手写解析器）：`key: value`、
//! 缩进嵌套、`#` 注释、单/双引号。不支持列表、多行字符串、流式语法。

use std::path::Path;

/// 没有配置文件时的默认端口（Minecraft Java 的默认值）。
pub const DEFAULT_PORT: u16 = 25565;

/// 读实例工作目录里的服务端端口。总有值：读不出来就是 [`DEFAULT_PORT`]。
pub fn read_port(dir: &Path) -> u16 {
    read_port_inner(dir).unwrap_or(DEFAULT_PORT)
}

fn read_port_inner(dir: &Path) -> Option<u16> {
    let props = dir.join("server.properties");
    if props.is_file() {
        // 文件在就不往后看了：解析失败也是它的缺省，不是下一种配置的
        let text = std::fs::read_to_string(&props).ok()?;
        return Some(server_properties_port(&text).unwrap_or(DEFAULT_PORT));
    }
    let pnx = dir.join("pnx.yml");
    if pnx.is_file() {
        let text = std::fs::read_to_string(&pnx).ok()?;
        return Some(yaml_int(&text, "settings.port").unwrap_or(19132));
    }
    let allay = dir.join("server-settings.yml");
    if allay.is_file() {
        let text = std::fs::read_to_string(&allay).ok()?;
        return Some(yaml_int(&text, "network-settings.port").unwrap_or(19132));
    }
    None
}

/// `server.properties` 里的 `server-port`（第一个匹配行说了算）。
fn server_properties_port(text: &str) -> Option<u16> {
    for raw in text.lines() {
        let trimmed = raw.trim_start();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let Some(eq) = raw.find('=') else { continue };
        if eq == 0 {
            continue;
        }
        if raw[..eq].trim() != "server-port" {
            continue;
        }
        // Dart 的 int.tryParse 容忍首尾空白；超范围（> 65535）按解析失败算
        return raw[eq + 1..].trim().parse::<u16>().ok();
    }
    None
}

/// 按 `a.b.c` 路径取 YAML 子集里的整数。
///
/// 缩进栈的实现同 V1 的 `AllayProperties`（pnx.yml 的两级结构是它的子集，
/// 一个实现就够）。
fn yaml_int(text: &str, path: &str) -> Option<u16> {
    yaml_value(text, path)?.parse().ok()
}

fn yaml_value(text: &str, path: &str) -> Option<String> {
    let mut stack: Vec<(usize, String)> = Vec::new();
    for raw in text.lines() {
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = raw.len() - raw.trim_start().len();
        // 回到外层：弹掉缩进 >= 当前行的层（mapping 起始行与父级兄弟同级，
        // 所以用 >= —— 同 V1）。
        while stack.last().is_some_and(|(level, _)| *level >= indent) {
            stack.pop();
        }
        let Some(colon) = trimmed.find(':') else {
            continue;
        };
        let key = trimmed[..colon].trim();
        if key.is_empty() {
            continue;
        }
        let rest = trimmed[colon + 1..].trim();
        let full = match stack.last() {
            Some((_, parent)) => format!("{parent}.{key}"),
            None => key.to_string(),
        };
        if rest.is_empty() {
            stack.push((indent, full));
        } else if full == path {
            return parse_yaml_value(rest);
        }
    }
    None
}

/// 一行 `key: value` 的 value 部分（同 V1 的 `_parseValue`）：
/// 去掉行尾注释（引号包住的不去）、剥掉成对的引号，空值算没有。
fn parse_yaml_value(rest: &str) -> Option<String> {
    let mut value = rest;
    if !value.starts_with('"')
        && !value.starts_with('\'')
        && let Some(hash) = value.find(" #")
    {
        value = value[..hash].trim();
    }
    if value.len() >= 2 {
        let bytes = value.as_bytes();
        let quote = bytes[0];
        if (quote == b'"' || quote == b'\'') && bytes[value.len() - 1] == quote {
            value = &value[1..value.len() - 1];
        }
    }
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "edgecube-upnp-port-{tag}-{}-{}",
            std::process::id(),
            crate::util::now_ms()
        ));
        std::fs::create_dir_all(&dir).expect("应能建临时目录");
        dir
    }

    #[test]
    fn server_properties_wins_over_others() {
        let dir = temp_dir("java");
        std::fs::write(dir.join("server.properties"), "server-port=25570\n").unwrap();
        std::fs::write(dir.join("pnx.yml"), "settings:\n  port: 19133\n").unwrap();
        assert_eq!(read_port(&dir), 25570);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn server_properties_without_key_uses_its_default() {
        // V1 语义：文件在就用它，没写 server-port 也是 25565，不往后看
        let dir = temp_dir("props-default");
        std::fs::write(dir.join("server.properties"), "motd=hello\n").unwrap();
        std::fs::write(dir.join("pnx.yml"), "settings:\n  port: 19133\n").unwrap();
        assert_eq!(read_port(&dir), 25565);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn pnx_yml_is_read_when_no_properties() {
        let dir = temp_dir("pnx");
        std::fs::write(
            dir.join("pnx.yml"),
            "# PowerNukkitX\nsettings:\n  port: 19133 # 注释\n",
        )
        .unwrap();
        assert_eq!(read_port(&dir), 19133);

        // 有文件但没那个 key → 19132
        std::fs::write(dir.join("pnx.yml"), "settings:\n  language: chs\n").unwrap();
        assert_eq!(read_port(&dir), 19132);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn allay_yml_nested_path_is_read() {
        let dir = temp_dir("allay");
        std::fs::write(
            dir.join("server-settings.yml"),
            "network-settings:\n  port: 20000\n  xbox-auth: true\nentity-settings:\n  motion-threshold: 0.003\n",
        )
        .unwrap();
        assert_eq!(read_port(&dir), 20000);

        // 其它节的 port 不该被误读
        std::fs::write(
            dir.join("server-settings.yml"),
            "entity-settings:\n  port: 1234\n",
        )
        .unwrap();
        assert_eq!(read_port(&dir), 19132);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_files_fall_back_to_java_default() {
        let dir = temp_dir("none");
        assert_eq!(read_port(&dir), DEFAULT_PORT);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn quoted_and_commented_values() {
        assert_eq!(parse_yaml_value("19133 # 注释"), Some("19133".into()));
        assert_eq!(parse_yaml_value("\"19133\""), Some("19133".into()));
        assert_eq!(parse_yaml_value("'19133' # x"), Some("'19133' # x".into()));
        assert_eq!(parse_yaml_value(""), None);
        assert_eq!(server_properties_port("server-port = 25566\n"), Some(25566));
        assert_eq!(server_properties_port("server-port=70000"), None);
        assert_eq!(server_properties_port("# server-port=1"), None);
    }

    #[test]
    fn duplicate_key_uses_first_match() {
        // V1 的 operator[] 返回第一个匹配行
        assert_eq!(
            server_properties_port("server-port=25566\nserver-port=25567\n"),
            Some(25566)
        );
    }
}
