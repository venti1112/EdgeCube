import 'dart:convert';

import 'package:http/http.dart' as http;

import '../online/cloud_headers.dart';
import '../online/online_service.dart';
import '../server/runtime_update_service.dart';

class EcpkgCatalogPackage {
  const EcpkgCatalogPackage({
    required this.id,
    required this.type,
    required this.name,
    required this.version,
    required this.arch,
    this.description,
    this.author,
    this.homepage,
    this.repository,
    this.minAppVersion,
    this.updateUrl,
    this.publishedAt,
    this.releaseNotes,
    this.packageEntries = const {},
  });

  final String id;
  final String type;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final String? homepage;
  final String? repository;
  final int? minAppVersion;
  final String? updateUrl;
  final String? publishedAt;
  final String? releaseNotes;

  /// 该包所有下载条目支持的架构并集（去重排序）。
  final List<String> arch;

  /// key: `multi` / `arm64` / `arm` / `x86_64`，与 spec §4.7 一致。
  final Map<String, EcpkgDownloadEntry> packageEntries;

  factory EcpkgCatalogPackage.fromJson(Map<String, dynamic> json) {
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
    return EcpkgCatalogPackage(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      arch: archList,
      description: json['description'] as String?,
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      repository: json['repository'] as String?,
      minAppVersion: json['minAppVersion'] as int?,
      updateUrl: json['updateUrl'] as String?,
      publishedAt: json['publishedAt'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      packageEntries: entries,
    );
  }

  /// 转换为 [RuntimeUpdatePackage]，供下载流程复用。
  RuntimeUpdatePackage? toUpdatePackage(String arch) {
    final entry = packageEntries[arch] ??
        packageEntries['multi'] ??
        packageEntries.values.firstOrNull;
    if (entry == null) return null;
    return RuntimeUpdatePackage(
      key: arch,
      url: entry.urls.first.url,
      sha256: entry.sha256,
      size: entry.size,
      arch: entry.arch,
    );
  }

  /// 获取当前设备架构的最佳下载包。
  RuntimeUpdatePackage? pickPackage(String deviceArch) {
    final single = packageEntries[deviceArch];
    if (single != null) {
      return RuntimeUpdatePackage(
        key: deviceArch,
        url: single.urls.first.url,
        sha256: single.sha256,
        size: single.size,
        arch: single.arch,
      );
    }
    final multi = packageEntries['multi'];
    if (multi != null && multi.arch.contains(deviceArch)) {
      return RuntimeUpdatePackage(
        key: 'multi',
        url: multi.urls.first.url,
        sha256: multi.sha256,
        size: multi.size,
        arch: multi.arch,
      );
    }
    for (final entry in packageEntries.values) {
      if (entry.arch.contains(deviceArch)) {
        return RuntimeUpdatePackage(
          key: entry.key,
          url: entry.urls.first.url,
          sha256: entry.sha256,
          size: entry.size,
          arch: entry.arch,
        );
      }
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

  factory EcpkgCategory.fromJson(Map<String, dynamic> json) {
    final list = (json['packages'] as List? ?? []);
    return EcpkgCategory(
      type: json['type'] as String,
      nameKey: json['nameKey'] as String? ?? json['type'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      packages: list
          .map((e) => EcpkgCatalogPackage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class EcpkgCatalog {
  const EcpkgCatalog({
    required this.categories,
    this.total,
    this.updatedAt,
  });

  final List<EcpkgCategory> categories;
  final int? total;
  final String? updatedAt;

  factory EcpkgCatalog.fromJson(Map<String, dynamic> json) {
    final list = (json['categories'] as List? ?? []);
    return EcpkgCatalog(
      categories: list
          .map((e) => EcpkgCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  List<EcpkgCatalogPackage> get allPackages =>
      categories.expand((c) => c.packages).toList();
}

class EcpkgCatalogService {
  EcpkgCatalogService._();

  static Future<EcpkgCatalog> fetchCatalog() async {
    final urls = OnlineService.instance.ecpkgCatalogUrls;
    final headers = await CloudHeaders.base();

    return OnlineService.fetchFirstValid<EcpkgCatalog>(
      urls,
      (url) async {
        final uri = Uri.parse(url);
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final code = body['code'] as int?;
        if (code != null && code != 200) {
          throw Exception(body['message'] as String? ?? 'API error: $code');
        }
        final data = body['data'] as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('响应缺少 data 字段');
        }
        return EcpkgCatalog.fromJson(data);
      },
      (catalog) => catalog.categories.isNotEmpty,
    );
  }
}
