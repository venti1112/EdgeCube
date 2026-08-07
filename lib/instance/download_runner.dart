import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/network_store.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../net/download_engine.dart';
import '../net/download_exceptions.dart';
import '../net/msl_mirror.dart';
import '../server/server_service.dart';
import 'download_info.dart';
import 'download_info_service.dart';

/// 下载返回的非 200 状态码。
class DownloadHttpException implements Exception {
  const DownloadHttpException(this.statusCode);
  final int statusCode;
}

/// 下载文件哈希校验失败。
class HashMismatchException implements Exception {
  const HashMismatchException();
}

/// 「下载服务端」流程共享的网络与下载逻辑。
///
/// 从旧的单文件向导中抽出，供「下载进度」页与「整合包导入」流程共用，避免
/// 两处重复实现下载/校验/配置写入。所有方法均为纯 IO：成功返回，失败抛异常
/// （由调用方负责翻译并展示）。
class DownloadRunner {
  DownloadRunner._();

  // —— 版本列表 ——

  /// 获取官方端（Vanilla）发行版本列表，同时返回每个版本的详情页 URL 映射。
  static Future<({List<String> versions, Map<String, String> urls})>
  fetchVanillaVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://launchermeta.mojang.com/mc/game/version_manifest.json',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      final releases = versions.where((v) => v['type'] == 'release').toList();

      final urls = {
        for (final v in releases) v['id'] as String: v['url'] as String,
      };
      final ids = releases.map<String>((v) => v['id'] as String).toList();
      return (versions: ids, urls: urls);
    } finally {
      client.close();
    }
  }

  // —— 下载信息 ——

  /// 镜像开启且成功时返回 MSL 下载信息，否则返回 null（调用方回退官方源）。
  ///
  /// [forceOfficial] 为 true 时跳过镜像源，强制走官方源（用于更新模式）。
  static Future<DownloadInfo?> tryMirrorDownloadInfo(
    String serverType,
    String version, {
    bool forceOfficial = false,
  }) async {
    if (forceOfficial) return null;
    if (!await NetworkStore.loadUseMirror()) return null;
    final info = await MslMirror.fetchDownloadInfo(serverType, version);
    if (info == null) return null;
    return DownloadInfo(url: info.url, sha256: info.sha256);
  }

  /// 根据服务端类型获取指定版本的下载信息（Vanilla / 插件 / 代理 / 基岩端）。
  static Future<DownloadInfo> fetchDownloadInfo(
    String serverType,
    String version,
    Map<String, String> vanillaVersionUrls,
  ) async {
    switch (serverType) {
      case 'vanilla':
        return fetchVanillaDownloadInfo(version, vanillaVersionUrls);
      case 'velocity':
        return DownloadInfoService.fetchVelocityDownloadInfo(version);
      case 'spigot':
        return DownloadInfoService.fetchSpigotDownloadInfo(version);
      case 'craftbukkit':
        return DownloadInfoService.fetchCraftBukkitDownloadInfo(version);
      case 'purpur':
        return DownloadInfoService.fetchPurpurDownloadInfo(version);
      case 'leaf':
        return DownloadInfoService.fetchLeafDownloadInfo(version);
      case 'leaves':
        return DownloadInfoService.fetchLeavesDownloadInfo(version);
      case 'powernukkitx':
        return DownloadInfoService.fetchPowernukkitxDownloadInfo(version);
      case 'pocketmine':
        return DownloadInfoService.fetchPocketmineDownloadInfo(version);
      case 'allay':
        return DownloadInfoService.fetchAllayDownloadInfo(version);
      default:
        return DownloadInfoService.fetchPaperDownloadInfo(version);
    }
  }

  /// Fabric 下载信息：查询最新 Installer 版本并组装直接下载 URL。
  static Future<DownloadInfo> fetchFabricDownloadInfo(
    String mcVersion,
    String loaderVersion,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://meta.fabricmc.net/v2/versions/installer'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      final latestInstaller = json.first['version'] as String;

      return DownloadInfo(
        url:
            'https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loaderVersion/$latestInstaller/server/jar',
      );
    } finally {
      client.close();
    }
  }

  /// 从版本详情 JSON 获取官方端服务端的真实下载 URL 和 SHA-1。
  static Future<DownloadInfo> fetchVanillaDownloadInfo(
    String version,
    Map<String, String> vanillaVersionUrls,
  ) async {
    final detailUrl = vanillaVersionUrls[version];
    if (detailUrl == null) {
      throw Exception('version detail not found: $version');
    }
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(detailUrl));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final server = json['downloads']?['server'];
      if (server == null) {
        throw Exception('no server jar');
      }
      return DownloadInfo(
        url: server['url'] as String,
        sha1: server['sha1'] as String?,
      );
    } finally {
      client.close();
    }
  }

  // —— 下载与配置 ——

  /// 下载服务端文件（.jar / .phar）到实例目录并校验哈希，成功后按服务端类型
  /// 写入实例配置。
  ///
  /// 进度经 [onProgress] 回传（0..1）。HTTP 非 200 抛 [DownloadHttpException]，
  /// 哈希不匹配抛 [HashMismatchException]，其余 IO 错误原样抛出。
  ///
  /// [configure] 为 false 时仅下载文件不写配置（用于更新模式：替换服务端文件
  /// 但保留原有实例配置不变）。
  static Future<void> downloadAndConfigure({
    required InstanceController controller,
    required String instanceId,
    required DownloadInfo info,
    required String serverType,
    String serverFileName = 'server.jar',
    String? selectedVersion,
    String? selectedMcVersion,
    bool configure = true,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final dir = await controller.directoryForId(instanceId);
    final serverFilePath = p.join(dir.path, serverFileName);

    // 下载并由引擎校验哈希（优先 sha1，其次 sha256）；分片并行 + 断点续传。
    try {
      await DownloadEngine.instance.downloadToFile(
        info.url,
        serverFilePath,
        sha1: info.sha1,
        sha256: info.sha256,
        onProgress: onProgress,
      );
    } on DownloadHashMismatch {
      throw const HashMismatchException();
    } on DownloadHttpError catch (e) {
      throw DownloadHttpException(e.statusCode);
    }

    // 更新模式：仅替换服务端文件，不修改实例配置。
    if (!configure) return;

    // 按服务端类型写入运行环境与运行环境 id。
    if (serverType == 'pocketmine') {
      // PocketMine-MP 使用 PHP 运行环境，无需 JRE。
      await controller.updateConfig(
        instanceId,
        serverFile: serverFileName,
        runtime: kRuntimePhp,
      );
      return;
    }

    final String javaVer;
    if (serverType == 'powernukkitx') {
      javaVer = await resolveJavaVersion('1.20.5');
    } else if (serverType == 'allay') {
      // Allay 需要 Java 21 及以上。
      javaVer = await resolveJavaVersion('1.21');
    } else {
      final mcVersion = serverType == 'fabric'
          ? (selectedMcVersion ?? '')
          : (serverType == 'velocity' ? '1.21' : (selectedVersion ?? ''));
      javaVer = await resolveJavaVersion(mcVersion);
    }
    await controller.updateConfig(
      instanceId,
      serverFile: serverFileName,
      runtimeEnvId: javaVer,
    );
  }

  /// 根据 MC 版本号推断所需的 JRE id（已移除 jre8）。
  ///
  /// MC 26+（年份命名）          → jre25
  /// MC 1.20.5 - 1.21.11（含边界） → jre21
  /// MC ≤1.20.4                  → jre17
  static String jreIdForMc(String mcVersion) {
    final parts = mcVersion.split('.');
    if (parts.isEmpty) return 'jre17';
    final major = int.tryParse(parts[0]) ?? 1;
    // Mojang 新版本采用年份开头（如 26 = 2026 年），统一使用 jre25。
    if (major >= 26) return 'jre25';
    if (major == 1) {
      final minor = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final patch = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
      // 1.20.5 ≤ version ≤ 1.21.11 → jre21
      if (minor > 21) return 'jre21';
      if (minor == 21 && patch <= 11) return 'jre21';
      if (minor == 20 && patch >= 5) return 'jre21';
      return 'jre17';
    }
    return 'jre17';
  }

  /// 根据 MC 版本推断首选 JRE id；若该版本未安装，回退到首个已安装 JRE。
  static Future<String> resolveJavaVersion(String mcVersion) async {
    final preferred = jreIdForMc(mcVersion);
    final available = await ServerService().availableJreIds();
    if (available.contains(preferred)) return preferred;
    if (available.isEmpty) return preferred;
    return available.first;
  }
}
