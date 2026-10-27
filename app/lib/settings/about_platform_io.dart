import 'dart:io';

/// 前端设备的 CPU 逻辑核心数。
int? localCpuCores() =>
    Platform.numberOfProcessors > 0 ? Platform.numberOfProcessors : null;

/// 前端设备的主机名。Linux 的 `device_info_plus` 不提供，用它补。
String? localHostname() {
  final name = Platform.localHostname.trim();
  return name.isEmpty ? null : name;
}

/// 前端设备的总内存（MB）。
///
/// `device_info_plus` 的 Linux 实现不读内存，这里从 `/proc/meminfo` 取；
/// 其它平台交给插件，返回 null 表示「这一层拿不到」。
int? localMemoryMb() {
  if (!Platform.isLinux) return null;
  try {
    final line = File(
      '/proc/meminfo',
    ).readAsLinesSync().firstWhere((line) => line.startsWith('MemTotal:'));
    final parts = line.split(RegExp(r'\s+'));
    final kb = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return kb == null || kb <= 0 ? null : kb ~/ 1024;
  } on FileSystemException {
    return null;
  } on StateError {
    return null;
  }
}
