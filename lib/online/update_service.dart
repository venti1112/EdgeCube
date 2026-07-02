import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../config/network_store.dart';
import '../i18n/i18n_service.dart';
import 'cloud_headers.dart';

class DownloadLink {
  const DownloadLink({
    required this.name,
    required this.url,
    required this.type,
    required this.extra,
  });

  final String name;
  final String url;
  final String type;
  final String extra;

  bool get isDirect => type == 'direct';

  bool get isWebPage => type == 'web';

  factory DownloadLink.fromJson(Map<String, dynamic> json) => DownloadLink(
    name: json['name'] as String,
    url: json['url'] as String,
    type: json['type'] as String,
    extra: json['extra'] as String? ?? '',
  );
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.sha256,
    required this.releaseNotes,
    required this.downloadLinks,
  });

  final String version;
  final int build;
  final String sha256;
  final String releaseNotes;
  final List<DownloadLink> downloadLinks;

  List<DownloadLink> get directLinks =>
      downloadLinks.where((l) => l.isDirect).toList();

  DownloadLink? get firstDirectLink => directLinks.isEmpty ? null : directLinks.first;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
    version: json['version'] as String,
    build: json['build'] as int,
    sha256: json['sha256'] as String,
    releaseNotes: json['releaseNotes'] as String,
    downloadLinks: (json['download_links'] as List<dynamic>)
        .map((e) => DownloadLink.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.stable,
    this.beta,
  });

  final AppUpdateInfo stable;
  final AppUpdateInfo? beta;

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) =>
      UpdateCheckResult(
        stable: AppUpdateInfo.fromJson(json['stable'] as Map<String, dynamic>),
        beta: json['beta'] != null
            ? AppUpdateInfo.fromJson(json['beta'] as Map<String, dynamic>)
            : null,
      );
}

class UpdateService {
  UpdateService._();

  static const _channel = MethodChannel('com.venti1112.edgecube/update');

  static Future<UpdateCheckResult?> checkForUpdates() async {
    try {
      final baseUrl = await NetworkStore.loadBackendApiBaseUrl();
      final endpoint = '$baseUrl/api/check_updates';
      final info = await PackageInfo.fromPlatform();
      final headers = await CloudHeaders.base();
      headers['X-App-Version'] = info.version;
      headers['X-App-Build'] = info.buildNumber;
      final response = await http
          .get(Uri.parse(endpoint), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return UpdateCheckResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<int> getCurrentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  static bool hasUpdate(AppUpdateInfo channelInfo, int currentBuild) {
    return channelInfo.build > currentBuild;
  }

  /// 根据「获取测试版」设置和构建号选取最佳的更新通道。
  /// 返回 null 表示无需更新。
  static Future<AppUpdateInfo?> pickBestUpdate(UpdateCheckResult result) async {
    final currentBuild = await getCurrentBuild();
    final enableBeta = await NetworkStore.loadBetaUpdates();

    AppUpdateInfo? best;
    if (hasUpdate(result.stable, currentBuild)) {
      best = result.stable;
    }
    if (enableBeta && result.beta != null && hasUpdate(result.beta!, currentBuild)) {
      if (best == null || result.beta!.build > best.build) {
        best = result.beta;
      }
    }
    return best;
  }

  static Future<String> downloadApk(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception(
        tr('updateService.downloadFailedHttp', {
          'status': '${response.statusCode}',
        }),
      );
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

  static Future<bool> verifySha256(String filePath, String expectedSha256) async {
    try {
      if (expectedSha256.isEmpty) return true;
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString().toLowerCase() == expectedSha256.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verifyApkSignature(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'verifySignature',
        {'apkPath': apkPath},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> installApk(String apkPath) async {
    await _channel.invokeMethod<void>('installApk', {'apkPath': apkPath});
  }

  static String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final name = uri.pathSegments.last;
      if (name.isNotEmpty && name.toLowerCase().endsWith('.apk')) return name;
    } catch (_) {
    }
    return 'edgecube_update.apk';
  }
}
