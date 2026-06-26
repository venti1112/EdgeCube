import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'runtime_service.dart';

/// `updateUrl` 响应中的单个下载包条目。
class RuntimeUpdatePackage {
  const RuntimeUpdatePackage({
    required this.key,
    required this.url,
    required this.sha256,
    this.size,
    required this.arch,
  });

  /// 在 `packages` 对象中的 key：`multi` / `arm64` / `arm` / `x86_64`。
  final String key;

  final String url;
  final String sha256;
  final int? size;

  /// 该包支持的架构列表。
  final List<String> arch;

  factory RuntimeUpdatePackage.fromJson(String key, Map<String, dynamic> json) {
    return RuntimeUpdatePackage(
      key: key,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
      size: json['size'] as int?,
      arch: (json['arch'] as List? ?? []).map((e) => e as String).toList(),
    );
  }
}

/// `updateUrl` 响应模型，对应 ecpkg-spec §4.7。
class RuntimeUpdateInfo {
  const RuntimeUpdateInfo({
    required this.formatVersion,
    required this.id,
    required this.latestVersion,
    this.minAppVersion,
    this.publishedAt,
    this.releaseNotes,
    this.packages = const {},
  });

  final int formatVersion;
  final String id;
  final String latestVersion;
  final int? minAppVersion;
  final String? publishedAt;
  final String? releaseNotes;
  final Map<String, RuntimeUpdatePackage> packages;

  factory RuntimeUpdateInfo.fromJson(Map<String, dynamic> json) {
    final packages = <String, RuntimeUpdatePackage>{};
    final packagesObj = json['packages'] as Map<String, dynamic>?;
    if (packagesObj != null) {
      for (final entry in packagesObj.entries) {
        packages[entry.key] = RuntimeUpdatePackage.fromJson(
          entry.key,
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return RuntimeUpdateInfo(
      formatVersion: json['formatVersion'] as int? ?? 1,
      id: json['id'] as String,
      latestVersion: json['latestVersion'] as String,
      minAppVersion: json['minAppVersion'] as int?,
      publishedAt: json['publishedAt'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      packages: packages,
    );
  }
}

/// 检查与下载运行时包更新的服务。
///
/// 流程遵循 ecpkg-spec §4.7：
/// 1. 请求 `updateUrl` 获取 [RuntimeUpdateInfo]
/// 2. 比较 `latestVersion` 与本地 `version`（字符串不等即视为有更新）
/// 3. 优先下载当前设备架构对应的单架构包，回退到 `multi` 包
/// 4. 下载后校验 SHA-256，校验通过则交由 [RuntimeService.importPackage] 安装
class RuntimeUpdateService {
  RuntimeUpdateService._();

  /// 请求 [runtime.updateUrl]，返回更新信息。
  ///
  /// - [runtime] 必须支持在线检查（`canCheckUpdate` 为 true）
  /// - 网络/解析失败抛出异常
  static Future<RuntimeUpdateInfo> checkForUpdates(
    RuntimeInfo runtime,
  ) async {
    if (!runtime.canCheckUpdate) {
      throw StateError('该运行时未声明 updateUrl，无法检查更新');
    }
    final response = await http
        .get(Uri.parse(runtime.updateUrl))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final info = RuntimeUpdateInfo.fromJson(json);
    if (info.id != runtime.id) {
      throw StateError('更新响应的 id（${info.id}）与已安装运行时 id（${runtime.id}）不一致');
    }
    return info;
  }

  /// 判断 [info] 相对于 [runtime] 是否表示有新版本。
  ///
  /// 不做语义化比较——`latestVersion` 与本地 `version` 字符串不等即视为可更新。
  static bool hasUpdate(RuntimeInfo runtime, RuntimeUpdateInfo info) {
    return info.latestVersion != runtime.version;
  }

  /// 根据设备架构从 [info.packages] 中选取最优下载包。
  ///
  /// 选择顺序（遵循 spec §4.7）：
  /// 1. `packages[deviceArch]`（单架构包，体积更小）
  /// 2. `packages.multi`（多架构包，需其 `arch` 含当前设备架构）
  /// 3. 任何其他 `arch` 含当前设备架构的包
  ///
  /// 找不到匹配包返回 null。
  static RuntimeUpdatePackage? pickPackage(
    RuntimeUpdateInfo info,
    String deviceArch,
  ) {
    // 1. 单架构包优先
    final single = info.packages[deviceArch];
    if (single != null) return single;

    // 2. multi 包（需声明支持当前架构）
    final multi = info.packages['multi'];
    if (multi != null && multi.arch.contains(deviceArch)) return multi;

    // 3. 任意其他含当前架构的包
    for (final pkg in info.packages.values) {
      if (pkg.arch.contains(deviceArch)) return pkg;
    }
    return null;
  }

  /// 下载指定包到临时目录并校验 SHA-256。
  ///
  /// - [onProgress] 回调 (receivedBytes, totalBytes)，totalBytes 未知时为 null
  /// - [isCancelled] 返回 true 时中断下载并清理不完整文件
  ///
  /// 校验失败抛出异常。成功返回下载文件路径。
  static Future<String> downloadPackage(
    RuntimeUpdatePackage pkg, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final fileName = _extractFileName(pkg.url, pkg.key);
    final destPath = p.join(cacheDir.path, fileName);

    final request = http.Request('GET', Uri.parse(pkg.url));
    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode != 200) {
      client.close();
      throw HttpException('HTTP ${response.statusCode}');
    }

    final total = pkg.size ?? response.contentLength;
    var received = 0;
    final sink = File(destPath).openWrite();
    var cancelled = false;
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
      client.close();
      if (cancelled) {
        try {
          await File(destPath).delete();
        } catch (_) {}
        throw const CancellationException();
      }
    }

    // SHA-256 校验
    final fileBytes = await File(destPath).readAsBytes();
    final actualHash = sha256.convert(fileBytes).toString();
    if (actualHash.toLowerCase() != pkg.sha256.toLowerCase()) {
      try {
        await File(destPath).delete();
      } catch (_) {}
      throw HashMismatchException(expected: pkg.sha256, actual: actualHash);
    }

    return destPath;
  }

  /// 从 URL 中提取文件名，失败回退为 `<key>.ecpkg`。
  static String _extractFileName(String url, String key) {
    try {
      final uri = Uri.parse(url);
      final name = uri.pathSegments.last;
      if (name.isNotEmpty && name.toLowerCase().endsWith('.ecpkg')) {
        return name;
      }
    } catch (_) {}
    return '$key.ecpkg';
  }
}

/// 下载被取消时抛出。
class CancellationException implements Exception {
  const CancellationException();
  @override
  String toString() => '下载已取消';
}

/// SHA-256 校验失败时抛出。
class HashMismatchException implements Exception {
  const HashMismatchException({required this.expected, required this.actual});
  final String expected;
  final String actual;
  @override
  String toString() => 'SHA-256 校验失败：期望 $expected，实际 $actual';
}
