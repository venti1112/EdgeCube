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

  /// 请求存储权限。
  /// - API < 30：返回 true/false 表示授权结果。
  /// - API >= 30：跳转到系统设置页，返回 null（Dart 侧需等待应用恢复前台后重新查询）。
  static Future<bool?> request() async {
    if (!Platform.isAndroid) return true;
    return _channel.invokeMethod<bool>('request');
  }

  /// 外部存储根目录（如 /storage/emulated/0）；不可用时返回 null。
  static Future<String?> externalStorageRoot() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('externalStorageRoot');
  }

  /// 获取指定路径所在分区的总空间与可用空间（字节）。
  /// 非 Android 平台返回 null。
  static Future<({int totalBytes, int availableBytes})?> getStorageStats(
    String path,
  ) async {
    if (!Platform.isAndroid) return null;
    final result = await _channel.invokeMethod<Map>('getStorageStats', {
      'path': path,
    });
    if (result == null) return null;
    return (
      totalBytes: (result['totalBytes'] as num?)?.toInt() ?? 0,
      availableBytes: (result['availableBytes'] as num?)?.toInt() ?? 0,
    );
  }

  /// 获取程序本体大小（APK + native 库，字节）。非 Android 平台返回 null。
  static Future<({int apkSize, int nativeLibSize, int totalSize})?>
  getAppSize() async {
    if (!Platform.isAndroid) return null;
    final result = await _channel.invokeMethod<Map>('getAppSize');
    if (result == null) return null;
    return (
      apkSize: (result['apkSize'] as num?)?.toInt() ?? 0,
      nativeLibSize: (result['nativeLibSize'] as num?)?.toInt() ?? 0,
      totalSize: (result['totalSize'] as num?)?.toInt() ?? 0,
    );
  }
}
