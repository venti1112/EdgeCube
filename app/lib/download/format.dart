/// 下载队列的展示格式化。
///
/// 输出格式如 `1.5 MB` / `5.3 MB/s` / `2m3s`。
///
/// `formatEta` 收的是**秒** ——
/// daemon 的任务对象里给的就是 `eta_seconds`。
library;

/// 人类可读的字节数，如 `1.5 MB`。
///
/// 用 1024 进制但用 `KB / MB / GB` 写法（不是 `KiB`）——
/// 与 daemon 日志里的 `humanize_bytes` 有意不同：那儿是给运维看的，这儿是用户界面。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MB';
  final gib = mib / 1024;
  return '${gib.toStringAsFixed(2)} GB';
}

/// 人类可读的下载速度，如 `5.3 MB/s`；速度为 0 时返回空串。
String formatSpeed(int bytesPerSec) {
  if (bytesPerSec <= 0) return '';
  return '${formatBytes(bytesPerSec)}/s';
}

/// 人类可读的剩余时间，如 `16s` / `2m3s` / `1h4m`；未知或非正时返回空串。
///
/// 这个值是 daemon 按**瞬时速度**估的，只当参考。
String formatEta(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  if (seconds < 60) return '${seconds}s';
  final mins = seconds ~/ 60;
  if (mins < 60) return '${mins}m${seconds % 60}s';
  final hours = mins ~/ 60;
  return '${hours}h${mins % 60}m';
}
