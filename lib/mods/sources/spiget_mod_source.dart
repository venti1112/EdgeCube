import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mod_source.dart';

/// SpigotMC 插件平台实现（经 Spiget API）。
///
/// 公开只读 API，无需 Key。仅提供插件。文档：https://spiget.org/documentation
///
/// 重要限制：Spiget 无文件哈希；部分资源为**外链**（`external: true`，
/// 作者把下载托管在站外），无法直连下载——这类文件标记为 [ModVersionFile.external]，
/// UI 应提示「前往官网下载」而非静默失败。
///
/// 端点：
/// - `GET /v2/search/resources/{query}?field=name&size=&page=&sort=`
/// - `GET /v2/resources/{id}/versions?size=&sort=-releaseDate`
/// 下载 URL：`/v2/resources/{id}/download`（内链资源）。
class SpigetModSource extends ModSource {
  const SpigetModSource();

  static const _base = 'https://api.spiget.org/v2';
  static const _userAgent = 'EdgeCube';

  @override
  ModSourceType get type => ModSourceType.spiget;

  @override
  String get displayName => 'SpigotMC';

  @override
  bool supportsProjectType(String projectType) => projectType == 'plugin';

  @override
  List<String> supportedLoaders(String projectType) => const [];

  @override
  bool get supportsGameVersionFilter => false;

  /// Spiget 排序字段：`-downloads` 降序。
  static String _sortParam(ModSortType s) => switch (s) {
    ModSortType.relevance => '-downloads',
    ModSortType.downloads => '-downloads',
    ModSortType.follows => '-rating.count',
    ModSortType.newest => '-releaseDate',
    ModSortType.updated => '-updateDate',
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
    // Spiget 用 page（从 1 开始）分页。
    final page = (offset ~/ limit) + 1;
    final params = <String, String>{
      'size': '$limit',
      'page': '$page',
      'sort': _sortParam(sort),
      'fields': 'id,name,tag,icon,downloads,rating,external,version,testedVersions,author',
    };

    final Uri uri;
    if (query.isNotEmpty) {
      params['field'] = 'name';
      uri = Uri.parse(
        '$_base/search/resources/${Uri.encodeComponent(query)}',
      ).replace(queryParameters: params);
    } else {
      uri = Uri.parse('$_base/resources').replace(queryParameters: params);
    }

    final json = await _getJson(uri);
    final list = (json as List? ?? []);
    final hits = list.whereType<Map<String, dynamic>>().map(_hitFromJson).toList();
    // Spiget 不返回总数；用「取满一页即可能有更多」估算。
    final total = list.length < limit
        ? offset + hits.length
        : offset + hits.length + 1;
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
    // 先取资源详情，判断是否外链。
    final detailUri = Uri.parse('$_base/resources/$projectId');
    final detail = await _getJson(detailUri) as Map<String, dynamic>;
    final external = detail['external'] == true;
    final resourceName = detail['name'] as String? ?? projectId;
    final fileInfo = detail['file'] as Map<String, dynamic>?;

    final uri = Uri.parse('$_base/resources/$projectId/versions').replace(
      queryParameters: {'size': '25', 'sort': '-releaseDate'},
    );
    final json = await _getJson(uri);
    final list = (json as List? ?? []);
    return list
        .whereType<Map<String, dynamic>>()
        .map((v) => _versionFromJson(v, projectId, resourceName, external, fileInfo))
        .toList();
  }

  // ── HTTP ────────────────────────────────────────────────────

  Future<Object?> _getJson(Uri uri) async {
    final res = await http
        .get(uri, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Spiget HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  // ── 映射 ────────────────────────────────────────────────────

  ModSearchHit _hitFromJson(Map<String, dynamic> j) {
    final icon = j['icon'] as Map<String, dynamic>?;
    final iconData = icon?['url'] as String?;
    final id = '${j['id']}';
    return ModSearchHit(
      sourceType: ModSourceType.spiget,
      projectId: id,
      slug: id,
      title: j['name'] as String? ?? '',
      description: j['tag'] as String? ?? '',
      iconUrl: iconData == null || iconData.isEmpty
          ? null
          : 'https://www.spigotmc.org/$iconData',
      downloads: (j['downloads'] as num?)?.toInt() ?? 0,
      pageUrl: 'https://www.spigotmc.org/resources/$id',
    );
  }

  ModVersionInfo _versionFromJson(
    Map<String, dynamic> j,
    String resourceId,
    String resourceName,
    bool external,
    Map<String, dynamic>? fileInfo,
  ) {
    final versionName = j['name'] as String? ?? '${j['id']}';
    final ext = (fileInfo?['type'] as String?)?.replaceFirst('.', '') ?? 'jar';
    final filename = '${_sanitize(resourceName)}-$versionName.$ext';
    final downloadUrl = '$_base/resources/$resourceId/download';
    return ModVersionInfo(
      sourceType: ModSourceType.spiget,
      id: '${j['id']}',
      name: versionName,
      versionNumber: versionName,
      files: [
        ModVersionFile(
          downloads: external ? const [] : [downloadUrl],
          filename: filename,
          size: (fileInfo?['size'] as num?)?.toInt() ?? 0,
          external: external,
        ),
      ],
      versionType: 'release',
      datePublished: j['releaseDate'] is int
          ? DateTime.fromMillisecondsSinceEpoch((j['releaseDate'] as int) * 1000)
          : DateTime.now(),
      projectId: resourceId,
    );
  }

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^\w.-]'), '_');
}
