/// 系统监控的线上模型。
///
/// 字段与 daemon 的 `monitor.snapshot` 一一对应（snake_case）：
/// 内存单位统一 MB，CPU 使用率是百分数。
///
/// [SystemSnapshot.fromJson] **不会抛异常**：字段缺失、类型不对（daemon 版本比 App
/// 新、或者手工塞了怪东西）一律退化成「不可用」。这是网络边界，
/// 把页面搞崩没有任何好处 —— 真正的契约漂移由 `test/daemon_e2e_test.dart`
/// 那条对着真 daemon 的用例负责发现。
library;

/// 一次系统状态快照。
class SystemSnapshot {
  const SystemSnapshot({
    this.supported = false,
    this.totalMemMb = 0,
    this.usedMemMb = 0,
    this.availableMemMb = 0,
    this.usedMemPercent = 0,
    this.cpuUsage,
    this.cpuCores = 0,
    this.serverMemMb,
    this.sampledAtMs = 0,
    this.intervalMs = 0,
  });

  /// daemon 所在平台是否支持采集。false 时后面的数字都没有意义。
  final bool supported;

  /// 设备总物理内存（MB）。
  final int totalMemMb;

  /// 设备已用内存（MB）。口径是 `total - available`。
  final int usedMemMb;

  /// 设备可用内存（MB）。
  final int availableMemMb;

  /// 已用内存占比（0–100）。
  final double usedMemPercent;

  /// 整机 CPU 使用率（%）。`null` = 还没有可信值或平台不支持。
  ///
  /// daemon 侧的使用率靠**两次采样的差值**算，所以守护进程刚起来的那一份快照里
  /// 它必然是 null；下一个采样间隔之后就有了。
  final double? cpuUsage;

  /// 逻辑核数。
  final int cpuCores;

  /// 服务端进程的内存占用（MB）。
  ///
  /// **目前恒为 null**：读它要服务端进程的 RSS，属于进程管理模块。
  final int? serverMemMb;

  /// 这份数据的采样时刻（Unix 毫秒）。
  final int sampledAtMs;

  /// daemon 的采样间隔，据此可知这份数据最旧能有多旧。
  final int intervalMs;

  bool get hasMemory => supported && totalMemMb > 0;
  bool get hasCpu => supported && cpuUsage != null;

  /// 「10253 MB / 31845 MB」；读不到时是「不可用」。
  String get memoryLabel =>
      hasMemory ? '$usedMemMb MB / $totalMemMb MB' : '不可用';

  /// 「11.0%」；读不到时是「不可用」。
  String get cpuLabel =>
      hasCpu ? '${cpuUsage!.toStringAsFixed(1)}%' : '不可用';

  /// 进度条用；读不到时是 0（条子空着，不假装有占用）。
  double get memoryPercent =>
      hasMemory ? usedMemPercent.clamp(0.0, 100.0) : 0.0;

  double get cpuPercent => hasCpu ? cpuUsage!.clamp(0.0, 100.0) : 0.0;

  factory SystemSnapshot.fromJson(Map<String, dynamic> json) => SystemSnapshot(
    supported: json['supported'] == true,
    totalMemMb: _asInt(json['total_mem_mb']),
    usedMemMb: _asInt(json['used_mem_mb']),
    availableMemMb: _asInt(json['available_mem_mb']),
    usedMemPercent: _asDouble(json['used_mem_percent']),
    cpuUsage: _asDoubleOrNull(json['cpu_usage']),
    cpuCores: _asInt(json['cpu_cores']),
    serverMemMb: _asIntOrNull(json['server_mem_mb']),
    sampledAtMs: _asInt(json['sampled_at_ms']),
    intervalMs: _asInt(json['interval_ms']),
  );
}

// 下面四个是「宽容解析」：类型不对就退化成默认值，不抛。

int _asInt(Object? value) => value is num ? value.toInt() : 0;

double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

int? _asIntOrNull(Object? value) => value is num ? value.toInt() : null;

double? _asDoubleOrNull(Object? value) =>
    value is num ? value.toDouble() : null;
