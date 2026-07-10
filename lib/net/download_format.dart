/// 下载进度展示用的格式化工具（人类可读的大小 / 速度 / 剩余时间）。
///
/// 供各处下载进度 UI 统一复用，返回纯数值文本，语言相关的前缀（如「剩余」）
/// 由调用方用 i18n 拼接。
library;

/// 人类可读的字节大小，如 `45.2 MB` / `1.20 GB`。
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
String formatSpeed(double bytesPerSec) {
  if (bytesPerSec <= 0) return '';
  return '${formatBytes(bytesPerSec.round())}/s';
}

/// 人类可读的剩余时间，如 `16s` / `2m3s` / `1h4m`；未知或非正时返回空串。
String formatEta(int? milliseconds) {
  if (milliseconds == null || milliseconds <= 0) return '';
  final totalSecs = (milliseconds / 1000).round();
  if (totalSecs < 60) return '${totalSecs}s';
  final mins = totalSecs ~/ 60;
  if (mins < 60) return '${mins}m${totalSecs % 60}s';
  final hours = mins ~/ 60;
  return '${hours}h${mins % 60}m';
}
