import 'dart:io';

import 'package:flutter/services.dart';

/// 电池优化白名单的 Dart 封装，对接 [MainActivity] 的 power 通道。
///
/// 把本应用加入白名单（忽略电池优化）能显著降低锁屏/后台时服务端进程被系统
/// 回收的概率，是前台 Service 之外提升保活成功率的关键一环。
class PowerService {
  static const MethodChannel _channel =
      MethodChannel('com.venti1112.edgecube/power');

  /// 本应用是否已被忽略电池优化。非 Android 平台恒为 true。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    final v =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return v ?? false;
  }

  /// 弹出系统对话框，请求将本应用加入电池优化白名单。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }
}
