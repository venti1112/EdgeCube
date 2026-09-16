//! 无依赖的小工具。

use std::time::{SystemTime, UNIX_EPOCH};

/// 当前 Unix 时间戳（毫秒）。
///
/// 协议里所有时间统一用毫秒整数，避免引入日期库，也省掉时区歧义。
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// 把 `Duration` 渲染成 `1h 02m 03s` 这种可读形式（用于 uptime）。
pub fn humanize_secs(total: u64) -> String {
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    if h > 0 {
        format!("{h}h {m:02}m {s:02}s")
    } else if m > 0 {
        format!("{m}m {s:02}s")
    } else {
        format!("{s}s")
    }
}

/// 遮蔽敏感串，日志里只留头尾。
pub fn redact(secret: &str) -> String {
    let chars: Vec<char> = secret.chars().collect();
    match chars.len() {
        0 => String::new(),
        1..=8 => "*".repeat(chars.len()),
        n => format!(
            "{}…{}",
            chars[..2].iter().collect::<String>(),
            chars[n - 2..].iter().collect::<String>()
        ),
    }
}

/// 把字节数渲染成 `1.5 MiB` 这种可读形式。
///
/// 用 1024 进制（KiB/MiB/GiB）—— 磁盘用量这样看更直观；
/// 想看成十进制 `MB` 的调用方请自己除。
pub fn humanize_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    format!("{value:.1} {}", UNITS[unit])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn humanize_works() {
        assert_eq!(humanize_secs(9), "9s");
        assert_eq!(humanize_secs(90), "1m 30s");
        assert_eq!(humanize_secs(3723), "1h 02m 03s");
    }

    #[test]
    fn humanize_bytes_works() {
        assert_eq!(humanize_bytes(0), "0 B");
        assert_eq!(humanize_bytes(512), "512 B");
        assert_eq!(humanize_bytes(1024), "1.0 KiB");
        assert_eq!(humanize_bytes(1536), "1.5 KiB");
        assert_eq!(humanize_bytes(1024 * 1024 * 3 / 2), "1.5 MiB");
        assert_eq!(humanize_bytes(5 * 1024 * 1024 * 1024), "5.0 GiB");
    }

    #[test]
    fn redact_hides_middle() {
        assert_eq!(redact(""), "");
        assert_eq!(redact("short"), "*****");
        assert_eq!(redact("abcdefghij"), "ab…ij");
    }
}
