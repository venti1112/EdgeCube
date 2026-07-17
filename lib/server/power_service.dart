import 'dart:io';

import 'package:flutter/services.dart';

/// 悬浮窗状态点的颜色绑定来源。
enum OverlayDotSource {
  /// 固定表示运行状态（绿色）。
  status('status'),

  /// CPU 使用率（绿/橙/红分档）。
  cpu('cpu'),

  /// 设备内存占用率。
  mem('mem'),

  /// 服务端内存占设备总内存比例。
  serverMem('serverMem');

  const OverlayDotSource(this.key);

  /// 与原生层约定的稳定标识。
  final String key;

  static OverlayDotSource fromKey(String? key) => values.firstWhere(
        (s) => s.key == key,
        orElse: () => OverlayDotSource.status,
      );
}

/// 状态悬浮窗的展示与交互设置（原生 SharedPreferences 持久化）。
class OverlayOptions {
  const OverlayOptions({
    this.showCpu = false,
    this.showMem = false,
    this.showServerMem = false,
    this.dotOnly = false,
    this.dotColorSource = OverlayDotSource.status,
    this.clickThrough = false,
  });

  /// 文本区显示 CPU 使用率。
  final bool showCpu;

  /// 文本区显示设备内存占用率。
  final bool showMem;

  /// 文本区显示服务端内存占用。
  final bool showServerMem;

  /// 仅显示一个状态点（隐藏文本区）。
  final bool dotOnly;

  /// 状态点颜色绑定来源。
  final OverlayDotSource dotColorSource;

  /// 穿透模式：悬浮窗不响应任何触摸（点击/拖拽直接落到下层应用）。
  final bool clickThrough;

  OverlayOptions copyWith({
    bool? showCpu,
    bool? showMem,
    bool? showServerMem,
    bool? dotOnly,
    OverlayDotSource? dotColorSource,
    bool? clickThrough,
  }) => OverlayOptions(
    showCpu: showCpu ?? this.showCpu,
    showMem: showMem ?? this.showMem,
    showServerMem: showServerMem ?? this.showServerMem,
    dotOnly: dotOnly ?? this.dotOnly,
    dotColorSource: dotColorSource ?? this.dotColorSource,
    clickThrough: clickThrough ?? this.clickThrough,
  );

  Map<String, dynamic> toMap() => {
    'showCpu': showCpu,
    'showMem': showMem,
    'showServerMem': showServerMem,
    'dotOnly': dotOnly,
    'dotColorSource': dotColorSource.key,
    'clickThrough': clickThrough,
  };

  factory OverlayOptions.fromMap(Map<dynamic, dynamic> map) => OverlayOptions(
    showCpu: map['showCpu'] as bool? ?? false,
    showMem: map['showMem'] as bool? ?? false,
    showServerMem: map['showServerMem'] as bool? ?? false,
    dotOnly: map['dotOnly'] as bool? ?? false,
    dotColorSource: OverlayDotSource.fromKey(map['dotColorSource'] as String?),
    clickThrough: map['clickThrough'] as bool? ?? false,
  );
}

/// 保活相关能力的 Dart 封装，对接 [MainActivity] 的 power 通道。
///
/// 覆盖三层保活手段（均为前台 Service 之外的增强）：
/// - 电池优化白名单：降低锁屏/后台时服务端进程被系统回收的概率；
/// - WakeLock + WifiLock（锁屏保活开关）：阻止锁屏后 CPU 深度休眠与
///   Wi-Fi 省电断连，随服务端启停自动获取/释放；
/// - 状态悬浮窗：随时展示运行状态，并让部分 ROM 视本应用为「用户可感知」。
class PowerService {
  static const MethodChannel _channel = MethodChannel(
    'com.venti1112.edgecube/power',
  );

  /// 本应用是否已被忽略电池优化。非 Android 平台恒为 true。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    final v = await _channel.invokeMethod<bool>(
      'isIgnoringBatteryOptimizations',
    );
    return v ?? false;
  }

  /// 弹出系统对话框，请求将本应用加入电池优化白名单。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  // —— 锁屏保活（WakeLock + WifiLock）——

  /// 锁屏保活开关是否启用（默认启用）。非 Android 平台恒为 false。
  static Future<bool> isWakeLockEnabled() async {
    if (!Platform.isAndroid) return false;
    final v = await _channel.invokeMethod<bool>('isWakeLockEnabled');
    return v ?? true;
  }

  /// 设置锁屏保活开关；服务端运行中立即生效（获取/释放锁）。
  static Future<void> setWakeLockEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setWakeLockEnabled', {'enabled': enabled});
  }

  // —— 状态悬浮窗 ——

  /// 状态悬浮窗开关是否启用（默认关闭）。非 Android 平台恒为 false。
  static Future<bool> isOverlayEnabled() async {
    if (!Platform.isAndroid) return false;
    final v = await _channel.invokeMethod<bool>('isOverlayEnabled');
    return v ?? false;
  }

  /// 设置状态悬浮窗开关；服务端运行中立即生效（挂载/移除悬浮窗）。
  static Future<void> setOverlayEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setOverlayEnabled', {'enabled': enabled});
  }

  /// 是否已授予悬浮窗（SYSTEM_ALERT_WINDOW）权限。
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    final v = await _channel.invokeMethod<bool>('canDrawOverlays');
    return v ?? false;
  }

  /// 跳转到本应用的悬浮窗权限设置页（该权限只能由用户手动授予）。
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestOverlayPermission');
  }

  /// 读取悬浮窗展示与交互设置。
  static Future<OverlayOptions> getOverlayOptions() async {
    if (!Platform.isAndroid) return const OverlayOptions();
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getOverlayOptions',
    );
    if (map == null) return const OverlayOptions();
    return OverlayOptions.fromMap(map);
  }

  /// 保存悬浮窗设置；悬浮窗正在显示时立即重建生效。
  static Future<void> setOverlayOptions(OverlayOptions options) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setOverlayOptions', options.toMap());
  }

  // —— 返回键退出策略 ——

  /// 把任务移到后台（等效 Home 键）：Activity 与 Flutter 引擎保持存活，
  /// 回前台后页面状态（UPnP/DDNS 映射信息等）不丢失。服务端运行中退出用。
  static Future<void> moveTaskToBack() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('moveTaskToBack');
  }

  /// 结束任务并彻底杀死应用进程，不留后台残留。服务端未运行时退出用。
  static Future<void> exitApp() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('exitApp');
  }
}
