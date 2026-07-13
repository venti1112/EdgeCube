import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../i18n/i18n_service.dart';
import '../net/download_engine.dart';
import '../net/download_exceptions.dart';
import 'runtime_service.dart';

/// `updateUrl` 响应中的单个下载包条目。
///
/// 新格式下，metadata 的 `packages[key]` 含 `urls` 数组（多个下载源）。
/// 这里在解析时自动选取第一个 `direct` 类型 URL，对外只暴露单个 [url]，
/// 供 [RuntimeUpdateService.downloadPackage] 直接使用。
class RuntimeUpdatePackage {
  const RuntimeUpdatePackage({
    required this.key,
    required this.url,
    this.urls = const [],
    required this.sha256,
    this.size,
    required this.arch,
  });

  /// 在 `packages` 对象中的 key：`multi` / `aarch64` / `arm` / `x86_64`。
  final String key;

  /// 首选下载直链（即 [urls] 的第一个，向后兼容单源调用）。
  final String url;

  /// 所有可用的直链下载源，供多源顺序回退使用。
  final List<String> urls;

  final String sha256;
  final int? size;

  /// 该包支持的架构列表。
  final List<String> arch;

  factory RuntimeUpdatePackage.fromJson(String key, Map<String, dynamic> json) {
    // 收集所有非 web（direct）类型直链供多源回退；url 取第一个。
    final entries = (json['urls'] as List? ?? []).cast<Map<String, dynamic>>();
    final directUrls = entries
        .where((u) => u['type'] != 'web')
        .map((u) => u['url'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
    final fallback =
        entries.isNotEmpty ? (entries.first['url'] as String? ?? '') : '';
    final sources = directUrls.isNotEmpty
        ? directUrls
        : (fallback.isNotEmpty ? [fallback] : const <String>[]);
    return RuntimeUpdatePackage(
      key: key,
      url: sources.isNotEmpty ? sources.first : '',
      urls: sources,
      sha256: json['sha256'] as String,
      size: json['size'] as int?,
      arch: (json['arch'] as List? ?? []).map((e) => e as String).toList(),
    );
  }
}

/// `updateUrl` 响应模型。
///
/// 新格式下，`updateUrl` 指向与 ecpkg 下载中心 metadata 相同的 JSON：
/// 顶层对象含 `id` / `version`(int) / `versionName` / `packages` 等字段，
/// 无 `{code,data}` 外壳，无 `formatVersion` / `latestVersion`。
class RuntimeUpdateInfo {
  const RuntimeUpdateInfo({
    required this.id,
    required this.version,
    this.versionName,
    this.minAppVersion,
    this.publishedAt,
    this.releaseNotes,
    this.packages = const {},
  });

  final String id;

  /// 构建版本号（整数，越大越新）。
  final int version;

  /// 显示用版本号；为空时回退到 [version]。
  final String? versionName;

  final int? minAppVersion;
  final String? publishedAt;
  final String? releaseNotes;
  final Map<String, RuntimeUpdatePackage> packages;

  /// 用于展示的版本字符串。
  String get displayVersion =>
      versionName?.isNotEmpty == true ? versionName! : version.toString();

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
      id: json['id'] as String,
      version: json['version'] as int,
      versionName: json['versionName'] as String?,
      minAppVersion: json['minAppVersion'] as int?,
      publishedAt: json['publishedAt'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      packages: packages,
    );
  }
}

/// 检查与下载运行时包更新的服务。
///
/// 流程：
/// 1. 请求 `updateUrl` 获取 [RuntimeUpdateInfo]（新 metadata 格式）
/// 2. 比较 `version`（整数构建版本号）：远端 > 本地即视为有更新
/// 3. 优先下载当前设备架构对应的单架构包，回退到 `multi` 包
/// 4. 下载后校验 SHA-256，校验通过则交由 [RuntimeService.importPackage] 安装
class RuntimeUpdateService {
  RuntimeUpdateService._();

  /// 请求 [runtime.updateUrl]，返回更新信息。
  ///
  /// - [runtime] 必须支持在线检查（`canCheckUpdate` 为 true）
  /// - 网络/解析失败抛出异常
  static Future<RuntimeUpdateInfo> checkForUpdates(RuntimeInfo runtime) async {
    if (!runtime.canCheckUpdate) {
      throw StateError(tr('runtimeUpdate.noUpdateUrl'));
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
      throw StateError(tr('runtimeUpdate.idMismatch',
          {'infoId': info.id, 'runtimeId': runtime.id}));
    }
    return info;
  }

  /// 判断 [info] 相对于 [runtime] 是否表示有新版本。
  ///
  /// 比较整数构建版本号 [RuntimeUpdateInfo.version] 与 [RuntimeInfo.version]，
  /// 远端 > 本地即视为可更新。
  static bool hasUpdate(RuntimeInfo runtime, RuntimeUpdateInfo info) {
    return info.version > runtime.version;
  }

  /// 根据设备架构从 [info.packages] 中选取最优下载包。
  ///
  /// 选择顺序：
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
  /// - [onProgress] 回调携带 [DownloadProgress]（速度/剩余时间/已下载/总大小）
  /// - [isCancelled] 返回 true 时中断下载并清理不完整文件
  ///
  /// 校验失败抛出异常。成功返回下载文件路径。
  static Future<String> downloadPackage(
    RuntimeUpdatePackage pkg, {
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final fileName = _extractFileName(pkg.url, pkg.key);
    final destPath = p.join(cacheDir.path, fileName);

    // 多源顺序回退 + 引擎内 sha256 校验（分片并行 + 断点续传）。
    final sources = pkg.urls.isNotEmpty ? pkg.urls : [pkg.url];
    try {
      await DownloadEngine.instance.downloadToFileMultiSource(
        sources,
        destPath,
        sha256: pkg.sha256,
        expectedSize: pkg.size,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
    } on DownloadCancelled {
      throw const CancellationException();
    } on DownloadHashMismatch catch (e) {
      throw HashMismatchException(
        expected: e.expected ?? pkg.sha256,
        actual: e.actual,
      );
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
  String toString() => tr('runtimeUpdate.cancelled');
}

/// SHA-256 校验失败时抛出。
class HashMismatchException implements Exception {
  const HashMismatchException({required this.expected, required this.actual});
  final String expected;
  final String actual;
  @override
  String toString() =>
      tr('runtimeUpdate.hashMismatch', {'expected': expected, 'actual': actual});
}
