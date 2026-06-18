import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

/// 检查更新接口返回的数据。
class UpdateInfo {
  const UpdateInfo({required this.lastVersion, required this.downloadLink});

  final String lastVersion;
  final String downloadLink;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    lastVersion: json['lastVersion'] as String,
    downloadLink: json['downloadLink'] as String,
  );
}

/// 应用更新服务：检查版本、下载 APK、触发安装。
///
/// 检查更新接口为 `https://edgecube-api.ventichat.com/api/check_updates`，
/// 返回 `{lastVersion, downloadLink}`。版本比较采用简单字符串比对——
/// 与当前版本不一致即视为有更新。
class UpdateService {
  UpdateService._();

  static const _endpoint =
      'https://edgecube-api.ventichat.com/api/check_updates';
  static const _channel = MethodChannel('com.venti1112.edgecube/update');

  /// 检查更新。成功返回 [UpdateInfo]；网络/解析失败返回 null。
  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      final response = await http
          .get(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final lastVersion = json['lastVersion'] as String?;
      final downloadLink = json['downloadLink'] as String?;
      if (lastVersion == null || downloadLink == null) return null;
      return UpdateInfo(lastVersion: lastVersion, downloadLink: downloadLink);
    } catch (_) {
      return null;
    }
  }

  /// 判断 [info] 是否表示有更新（lastVersion 与当前版本字符串不同）。
  static Future<bool> hasUpdate(UpdateInfo info) async {
    final current = await _currentVersion();
    return info.lastVersion != current;
  }

  /// 下载 APK 到应用缓存目录并返回文件路径。
  /// [onProgress] 回调 (receivedBytes, totalBytes)，totalBytes 未知时为 null。
  static Future<String> downloadApk(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('下载失败：HTTP ${response.statusCode}');
    }

    final total = response.contentLength;
    final cacheDir = await getTemporaryDirectory();
    final fileName = _extractFileName(url);
    final filePath = p.join(cacheDir.path, fileName);
    final sink = File(filePath).openWrite();

    try {
      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return filePath;
  }

  /// 触发系统安装界面安装指定 APK。
  static Future<void> installApk(String apkPath) async {
    await _channel.invokeMethod<void>('installApk', {'apkPath': apkPath});
  }

  /// 获取当前应用完整版本号（version+buildNumber）。
  static Future<String> _currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  /// 从 URL 中提取文件名，失败回退为 `edgecube_update.apk`。
  static String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final name = uri.pathSegments.last;
      if (name.isNotEmpty && name.toLowerCase().endsWith('.apk')) return name;
    } catch (_) {
      // 忽略
    }
    return 'edgecube_update.apk';
  }
}
