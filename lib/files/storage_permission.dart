import 'dart:io';

import 'package:flutter/services.dart';

/// 「管理全部文件」权限的 Dart 封装，对接 MainActivity 中的 MethodChannel。
class StoragePermission {
  static const MethodChannel _channel = MethodChannel(
    'com.venti1112.edgecube/storage',
  );

  /// 是否已获得管理全部文件的权限。非 Android 平台恒为 true。
  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    final granted = await _channel.invokeMethod<bool>('isGranted');
    return granted ?? false;
  }

  /// 跳转到系统设置页，请求授予「所有文件访问权限」。
  static Future<void> request() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('request');
  }

  /// 外部存储根目录（如 /storage/emulated/0）；不可用时返回 null。
  static Future<String?> externalStorageRoot() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('externalStorageRoot');
  }
}
