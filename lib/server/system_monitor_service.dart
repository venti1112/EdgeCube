import 'package:flutter/services.dart';

/// 与原生 `com.venti1112.edgecube/system_monitor` MethodChannel 对接，
/// 获取设备总内存、已用内存、CPU 使用率以及服务端进程内存。
class SystemMonitorService {
  static const MethodChannel _channel =
      MethodChannel('com.venti1112.edgecube/system_monitor');

  /// 获取一次系统状态快照。
  Future<SystemInfo> getSystemInfo() async {
    final raw = await _channel.invokeMethod<Map>('getSystemInfo');
    if (raw == null) {
      return const SystemInfo(
        totalMemMb: 0,
        usedMemMb: 0,
        availMemMb: 0,
        cpuUsage: -1,
        serverMemMb: null,
      );
    }
    final map = Map<String, dynamic>.from(raw);
    return SystemInfo(
      totalMemMb: (map['totalMemMb'] as num?)?.toInt() ?? 0,
      usedMemMb: (map['usedMemMb'] as num?)?.toInt() ?? 0,
      availMemMb: (map['availMemMb'] as num?)?.toInt() ?? 0,
      cpuUsage: (map['cpuUsage'] as num?)?.toDouble() ?? -1.0,
      serverMemMb: (map['serverMemMb'] as num?)?.toInt(),
    );
  }

  /// 获取设备硬件信息（SoC、架构、制造商、型号）。
  Future<DeviceInfo> getDeviceInfo() async {
    final raw = await _channel.invokeMethod<Map>('getDeviceInfo');
    if (raw == null) {
      return const DeviceInfo(
        socModel: 'unknown',
        architecture: 'unknown',
        manufacturer: 'unknown',
        model: 'unknown',
        androidVersion: 'unknown',
        securityPatch: 'unknown',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    return DeviceInfo(
      socModel: (map['socModel'] as String?) ?? 'unknown',
      architecture: (map['architecture'] as String?) ?? 'unknown',
      manufacturer: (map['manufacturer'] as String?) ?? 'unknown',
      model: (map['model'] as String?) ?? 'unknown',
      androidVersion: (map['androidVersion'] as String?) ?? 'unknown',
      securityPatch: (map['securityPatch'] as String?) ?? 'unknown',
    );
  }
}

/// 一次系统状态快照。
class SystemInfo {
  const SystemInfo({
    required this.totalMemMb,
    required this.usedMemMb,
    required this.availMemMb,
    required this.cpuUsage,
    required this.serverMemMb,
  });

  /// 设备总物理内存（MB）。
  final int totalMemMb;

  /// 设备已用内存（MB）。
  final int usedMemMb;

  /// 设备可用内存（MB）。
  final int availMemMb;

  /// 整体 CPU 使用率（0–100）；首次采样时为 -1。
  final double cpuUsage;

  /// 服务端子进程 VmRSS（MB）；未运行时为 null。
  final int? serverMemMb;

  /// 已用内存占总量百分比。
  double get usedMemPercent =>
      totalMemMb > 0 ? (usedMemMb / totalMemMb) * 100.0 : 0.0;
}

/// 设备硬件信息，用于崩溃报告。
class DeviceInfo {
  const DeviceInfo({
    required this.socModel,
    required this.architecture,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.securityPatch,
  });

  /// SoC 型号（如 Snapdragon 8 Gen 2）。
  final String socModel;

  /// 设备架构（如 arm64-v8a）。
  final String architecture;

  /// 设备制造商（如 Xiaomi）。
  final String manufacturer;

  /// 设备型号（如 2210132C）。
  final String model;

  /// 安卓系统版本（如 14）。
  final String androidVersion;

  /// 安全补丁日期（如 2024-01-01）。
  final String securityPatch;
}
