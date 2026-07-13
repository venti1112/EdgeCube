import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/network_store.dart';
import '../i18n/i18n_service.dart';
import '../online/cloud_headers.dart';
import '../online/online_service.dart';

/// 目录中的一个包：元数据 + 已随 metadata 一起加载的下载详情。
///
/// 新格式下，list.json 中每个分类的 `packages` 是一组 metadata JSON 的 URL；
/// 拉取这些 URL 即得到含全部字段（id/name/version/packages 等）的对象，
/// 因此 [EcpkgCatalogPackage] 同时持有摘要信息与 [detail]。
class EcpkgCatalogPackage {
  const EcpkgCatalogPackage({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.author,
    this.homepage,
    this.repository,
    this.minAppVersion,
    required this.detailUrl,
    required this.detail,
  });

  final String id;
  final String type;
  final String name;
  final String? description;
  final String? author;
  final String? homepage;
  final String? repository;
  final int? minAppVersion;

  /// 该包 metadata JSON 的来源 URL。
  final String detailUrl;

  /// 已随 metadata 一起加载的下载详情。
  final EcpkgPackageDetail detail;

  factory EcpkgCatalogPackage.fromDetailJson(
    String detailUrl,
    Map<String, dynamic> json,
  ) {
    return EcpkgCatalogPackage(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      repository: json['repository'] as String?,
      minAppVersion: json['minAppVersion'] as int?,
      detailUrl: detailUrl,
      detail: EcpkgPackageDetail.fromJson(json),
    );
  }
}

/// 包的下载详情：显示版本、架构并集、各架构下载条目。
class EcpkgPackageDetail {
  const EcpkgPackageDetail({
    required this.version,
    required this.buildVersion,
    required this.arch,
    required this.packageEntries,
    this.publishedAt,
    this.releaseNotes,
  });

  /// 显示用版本号（取自 metadata 中的 `versionName`）。
  final String version;

  /// 构建版本号（取自 metadata 中的 `version`，整数）。
  final int buildVersion;

  /// 该包所有下载条目支持的架构并集（去重排序）。
  final List<String> arch;

  /// key: `multi` / `aarch64` / `arm` / `x86_64`。
  final Map<String, EcpkgDownloadEntry> packageEntries;

  final String? publishedAt;
  final String? releaseNotes;

  factory EcpkgPackageDetail.fromJson(Map<String, dynamic> json) {
    final packagesObj = json['packages'] as Map<String, dynamic>?;
    final entries = <String, EcpkgDownloadEntry>{};
    if (packagesObj != null) {
      for (final entry in packagesObj.entries) {
        entries[entry.key] = EcpkgDownloadEntry.fromJson(
          entry.key,
          entry.value as Map<String, dynamic>,
        );
      }
    }
    final archSet = <String>{};
    for (final e in entries.values) {
      archSet.addAll(e.arch);
    }
    final archList = archSet.toList()..sort();
    return EcpkgPackageDetail(
      version: json['versionName'] as String? ?? '',
      buildVersion: json['version'] as int? ?? 0,
      arch: archList,
      packageEntries: entries,
      publishedAt: json['publishedAt'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }

  /// 优先单架构包，其次 multi 包，最后任意含当前架构的包。
  EcpkgDownloadEntry? pickEntry(String deviceArch) {
    final single = packageEntries[deviceArch];
    if (single != null) return single;
    final multi = packageEntries['multi'];
    if (multi != null && multi.arch.contains(deviceArch)) return multi;
    for (final entry in packageEntries.values) {
      if (entry.arch.contains(deviceArch)) return entry;
    }
    return null;
  }
}

class EcpkgDownloadUrl {
  const EcpkgDownloadUrl({
    required this.name,
    required this.url,
    this.type = 'direct',
    this.extra = '',
  });

  final String name;
  final String url;

  /// 类型：`direct`（直接下载）或 `web`（跳转网页）。
  final String type;

  /// 额外描述信息（如版本号、更新说明）。
  final String extra;

  bool get isDirect => type == 'direct';

  bool get isWebPage => type == 'web';

  factory EcpkgDownloadUrl.fromJson(Map<String, dynamic> json) {
    return EcpkgDownloadUrl(
      name: json['name'] as String? ?? '',
      url: json['url'] as String,
      type: json['type'] as String? ?? 'direct',
      extra: json['extra'] as String? ?? '',
    );
  }
}

class EcpkgDownloadEntry {
  const EcpkgDownloadEntry({
    required this.key,
    required this.sha256,
    this.size,
    required this.arch,
    required this.urls,
  });

  final String key;
  final String sha256;
  final int? size;
  final List<String> arch;

  /// 下载源列表，与更新对话框一致。
  final List<EcpkgDownloadUrl> urls;

  factory EcpkgDownloadEntry.fromJson(String key, Map<String, dynamic> json) {
    final urlsList = (json['urls'] as List?) ?? [];
    return EcpkgDownloadEntry(
      key: key,
      sha256: json['sha256'] as String,
      size: json['size'] as int?,
      arch: (json['arch'] as List? ?? []).map((e) => e as String).toList(),
      urls: urlsList
          .map((e) => EcpkgDownloadUrl.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class EcpkgCategory {
  const EcpkgCategory({
    required this.type,
    required this.nameKey,
    this.icon,
    this.description,
    required this.packages,
  });

  final String type;
  final String nameKey;
  final String? icon;
  final String? description;
  final List<EcpkgCatalogPackage> packages;
}

class EcpkgCatalog {
  const EcpkgCatalog({required this.categories});

  final List<EcpkgCategory> categories;

  List<EcpkgCatalogPackage> get allPackages =>
      categories.expand((c) => c.packages).toList();
}

class EcpkgCatalogService {
  EcpkgCatalogService._();

  /// 拉取目录列表并并行加载每个包的 metadata，组装成 [EcpkgCatalog]。
  ///
  /// list.json 为顶层数组，每项形如：
  /// ```json
  /// { "type": "java", "nameKey": "Java", "icon": "coffee",
  ///   "packages": ["https://.../jre17.json", ...] }
  /// ```
  /// 每个 packages URL 指向的 metadata JSON 为顶层对象（无 `{code,data}` 包裹），
  /// 同时包含元数据与 `packages` 下载条目映射。
  static Future<EcpkgCatalog> fetchCatalog() async {
    final urls = await NetworkStore.getEcpkgCatalogUrls();
    final headers = await CloudHeaders.base();

    // 1. 拉取 list.json（顶层数组），取第一个有效响应。
    final rawList = await OnlineService.fetchFirstValid<List<dynamic>>(
      urls,
      (url) async {
        final uri = Uri.parse(url);
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final body = jsonDecode(response.body);
        if (body is! List) {
          throw Exception(tr('ecpkg.expectTopLevelArray'));
        }
        return body;
      },
      (list) => list.isNotEmpty,
    );

    // 2. 解析分类壳 + 包 metadata URL 列表。
    final shells = <_CategoryShell>[];
    for (final item in rawList) {
      final obj = item as Map<String, dynamic>;
      final pkgUrls = (obj['packages'] as List? ?? [])
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList();
      shells.add(_CategoryShell(
        type: obj['type'] as String? ?? '',
        nameKey: obj['nameKey'] as String? ?? obj['type'] as String? ?? '',
        icon: obj['icon'] as String?,
        description: obj['description'] as String?,
        packageUrls: pkgUrls,
      ));
    }

    // 3. 并行拉取每个包的 metadata，组装 catalog。
    final categories = <EcpkgCategory>[];
    for (final shell in shells) {
      final pkgs = await _fetchPackages(shell.packageUrls, headers);
      categories.add(EcpkgCategory(
        type: shell.type,
        nameKey: shell.nameKey,
        icon: shell.icon,
        description: shell.description,
        packages: pkgs,
      ));
    }

    return EcpkgCatalog(categories: categories);
  }

  /// 并行拉取一组 metadata URL，单个失败则跳过。
  static Future<List<EcpkgCatalogPackage>> _fetchPackages(
    List<String> urls,
    Map<String, String> headers,
  ) async {
    final results = await Future.wait(
      urls.map((u) => _fetchOne(u, headers)),
    );
    return results.whereType<EcpkgCatalogPackage>().toList();
  }

  static Future<EcpkgCatalogPackage?> _fetchOne(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final uri = Uri.parse(url);
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return EcpkgCatalogPackage.fromDetailJson(url, body);
    } catch (_) {
      return null;
    }
  }
}

class _CategoryShell {
  const _CategoryShell({
    required this.type,
    required this.nameKey,
    this.icon,
    this.description,
    required this.packageUrls,
  });

  final String type;
  final String nameKey;
  final String? icon;
  final String? description;
  final List<String> packageUrls;
}
