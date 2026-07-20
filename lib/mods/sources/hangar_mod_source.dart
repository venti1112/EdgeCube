import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mod_source.dart';

/// Hangar（PaperMC 官方插件仓库）平台实现。
///
/// 公开只读 API，无需 Key。仅提供插件（Paper/Waterfall/Velocity 平台）。
/// 文档：https://hangar.papermc.io/api-docs
///
/// 端点：
/// - `GET /api/v1/projects?query=&limit=&offset=&sort=`
/// - `GET /api/v1/projects/{slug}/versions?limit=&offset=`
/// 下载 URL：`/api/v1/projects/{slug}/versions/{name}/{platform}/download`。
class HangarModSource extends ModSource {
  const HangarModSource();

  static const _base = 'https://hangar.papermc.io/api/v1';
  static const _userAgent = 'EdgeCube';

  /// Hangar 平台名（大写），用于版本文件与筛选。
  static const _platforms = ['PAPER', 'WATERFALL', 'VELOCITY'];

  @override
  ModSourceType get type => ModSourceType.hangar;

  @override
  String get displayName => 'Hangar';

  @override
  bool supportsProjectType(String projectType) => projectType == 'plugin';

  @override
  List<String> supportedLoaders(String projectType) =>
      const ['paper', 'waterfall', 'velocity'];

  @override
  bool get supportsGameVersionFilter => false;

  /// Hangar 排序：`-downloads` 降序等，前缀 `-` 表示降序。
  static String _sortParam(ModSortType s) => switch (s) {
    ModSortType.relevance => '-downloads',
    ModSortType.downloads => '-downloads',
    ModSortType.follows => '-stars',
    ModSortType.newest => '-newest',
    ModSortType.updated => '-updated',
  };

  @override
  Future<ModSearchResult> search(
    String query, {
    int offset = 0,
    int limit = 20,
    String? gameVersion,
    String? loader,
    ModSortType sort = ModSortType.relevance,
    String projectType = 'mod',
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': _sortParam(sort),
    };
    if (query.isNotEmpty) params['query'] = query;
    if (loader != null && loader.isNotEmpty) {
      params['platform'] = loader.toUpperCase();
    }

    final uri = Uri.parse(
      '$_base/projects',
    ).replace(queryParameters: params);
    final json = await _getJson(uri) as Map<String, dynamic>;

    final result = (json['result'] as List? ?? []);
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final total = (pagination['count'] as int?) ?? result.length;
    final hits = result
        .whereType<Map<String, dynamic>>()
        .map(_hitFromJson)
        .toList();
    return ModSearchResult(
      hits: hits,
      totalHits: total,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<ModVersionInfo>> getVersions(
    String projectId, {
    String projectType = 'mod',
  }) async {
    // projectId 对 Hangar 即 slug。
    final uri = Uri.parse('$_base/projects/$projectId/versions').replace(
      queryParameters: {'limit': '25', 'offset': '0'},
    );
    final json = await _getJson(uri) as Map<String, dynamic>;
    final result = (json['result'] as List? ?? []);
    final versions = result
        .whereType<Map<String, dynamic>>()
        .map((v) => _versionFromJson(v, projectId))
        .toList();
    versions.sort((a, b) => b.datePublished.compareTo(a.datePublished));
    return versions;
  }

  // ── HTTP ────────────────────────────────────────────────────

  Future<Object?> _getJson(Uri uri) async {
    final res = await http
        .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Hangar HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  // ── 映射 ────────────────────────────────────────────────────

  ModSearchHit _hitFromJson(Map<String, dynamic> j) {
    final slug = j['name'] as String? ?? '';
    final namespace = j['namespace'] as Map<String, dynamic>?;
    final owner = namespace?['owner'] as String?;
    final ns = namespace?['slug'] as String? ?? slug;
    final stats = j['stats'] as Map<String, dynamic>?;
    final category = j['category'] as String?;
    return ModSearchHit(
      sourceType: ModSourceType.hangar,
      projectId: ns,
      slug: ns,
      title: slug,
      description: j['description'] as String? ?? '',
      iconUrl: j['avatarUrl'] as String?,
      downloads: (stats?['downloads'] as num?)?.toInt() ?? 0,
      follows: (stats?['stars'] as num?)?.toInt() ?? 0,
      categories: category == null ? const [] : [category],
      author: owner,
      pageUrl: owner == null
          ? null
          : 'https://hangar.papermc.io/$owner/$ns',
    );
  }

  ModVersionInfo _versionFromJson(Map<String, dynamic> j, String slug) {
    final name = j['name'] as String? ?? '';
    // downloads: {PAPER: {fileInfo, externalUrl, downloadUrl}, ...}
    final downloadsMap = j['downloads'] as Map<String, dynamic>? ?? {};
    final platformVersions = j['platformDependencies'] as Map<String, dynamic>? ?? {};

    final files = <ModVersionFile>[];
    final loaders = <String>[];
    final gameVersions = <String>{};
    for (final platform in _platforms) {
      final entry = downloadsMap[platform] as Map<String, dynamic>?;
      if (entry == null) continue;
      loaders.add(platform.toLowerCase());
      for (final gv in (platformVersions[platform] as List? ?? [])
          .whereType<String>()) {
        gameVersions.add(gv);
      }
      final fileInfo = entry['fileInfo'] as Map<String, dynamic>?;
      final external = entry['externalUrl'] as String?;
      if (external != null && external.isNotEmpty) {
        files.add(
          ModVersionFile(
            downloads: [external],
            filename: fileInfo?['name'] as String? ?? '$slug-$name.jar',
            size: (fileInfo?['sizeBytes'] as num?)?.toInt() ?? 0,
            sha1: fileInfo?['sha256Hash'] as String?,
            external: true,
          ),
        );
      } else {
        final url =
            '$_base/projects/$slug/versions/$name/$platform/download';
        files.add(
          ModVersionFile(
            downloads: [url],
            filename: fileInfo?['name'] as String? ?? '$slug-$name.jar',
            size: (fileInfo?['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    return ModVersionInfo(
      sourceType: ModSourceType.hangar,
      id: name,
      name: name,
      versionNumber: name,
      files: files,
      versionType: _channelType(j['channel'] as Map<String, dynamic>?),
      gameVersions: gameVersions.toList(),
      loaders: loaders,
      datePublished:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      projectId: slug,
    );
  }

  static String _channelType(Map<String, dynamic>? channel) {
    final name = (channel?['name'] as String? ?? 'Release').toLowerCase();
    if (name.contains('alpha')) return 'alpha';
    if (name.contains('beta') || name.contains('snapshot')) return 'beta';
    return 'release';
  }
}
