import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../net/mod_mirror.dart';
import 'mod_source.dart';

/// CurseForge 平台实现。
///
/// CurseForge 官方 API 取下载链接必须携带 `X-API-KEY`（编译期由
/// `--dart-define=CURSEFORGE_API_KEY` 注入），或经镜像源访问（镜像侧持 Key）。
/// 可用性由 [ModMirror.isCurseForgeAvailable] 判定：无 Key 且未开镜像时不可用，
/// UI 据此隐藏本平台。
///
/// 端点（gameId=432 为 Minecraft）：
/// - `GET /v1/mods/search`（classId=6 模组）
/// - `GET /v1/mods/{id}/files`
/// - `POST /v1/mods/files`（批量，整合包解析用）
///
/// downloadUrl 为空时（作者禁用 API 分发）用 CDN 回退：
/// `https://edge.forgecdn.net/files/{id~1000}/{id%1000}/{fileName}`。
class CurseForgeModSource extends ModSource {
  const CurseForgeModSource();

  static const _apiBase = 'https://api.curseforge.com';
  static const _userAgent = 'EdgeCube';
  static const _gameId = 432; // Minecraft
  static const _classIdMod = 6;

  @override
  ModSourceType get type => ModSourceType.curseforge;

  @override
  String get displayName => 'CurseForge';

  @override
  Future<bool> get isAvailable => ModMirror.isCurseForgeAvailable();

  @override
  bool supportsProjectType(String projectType) => projectType == 'mod';

  @override
  List<String> supportedLoaders(String projectType) =>
      const ['forge', 'fabric', 'quilt', 'neoforge'];

  /// CF 加载器筛选参数：Forge=1,Fabric=4,Quilt=5,NeoForge=6。
  static const _loaderTypeIds = {
    'forge': 1,
    'fabric': 4,
    'quilt': 5,
    'neoforge': 6,
  };

  /// CF 排序字段：Featured=1,Popularity=2,LastUpdated=3,Name=4,TotalDownloads=6。
  static int _sortField(ModSortType s) => switch (s) {
    ModSortType.relevance => 1,
    ModSortType.downloads => 6,
    ModSortType.follows => 2,
    ModSortType.newest => 11, // ReleaseDate
    ModSortType.updated => 3,
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
      'gameId': '$_gameId',
      'classId': '$_classIdMod',
      'index': '$offset',
      'pageSize': '$limit',
      'sortField': '${_sortField(sort)}',
      'sortOrder': 'desc',
    };
    if (query.isNotEmpty) params['searchFilter'] = query;
    if (gameVersion != null && gameVersion.isNotEmpty) {
      params['gameVersion'] = gameVersion;
    }
    final loaderId = loader != null ? _loaderTypeIds[loader] : null;
    if (loaderId != null) params['modLoaderType'] = '$loaderId';

    final uri = Uri.parse(
      '$_apiBase/v1/mods/search',
    ).replace(queryParameters: params);
    final json = await _getJson(uri) as Map<String, dynamic>;

    final data = (json['data'] as List? ?? []);
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final totalCount = (pagination['totalCount'] as int?) ?? data.length;
    // CF 的 totalCount 上限为 10000（API 限制），据此计算 hasMore。
    final effectiveTotal = totalCount > 10000 ? 10000 : totalCount;

    final hits = data
        .whereType<Map<String, dynamic>>()
        .map(_hitFromJson)
        .toList();
    return ModSearchResult(
      hits: hits,
      totalHits: effectiveTotal,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<ModVersionInfo>> getVersions(
    String projectId, {
    String projectType = 'mod',
  }) async {
    final uri = Uri.parse('$_apiBase/v1/mods/$projectId/files').replace(
      queryParameters: {'pageSize': '10000'},
    );
    final json = await _getJson(uri) as Map<String, dynamic>;
    final data = (json['data'] as List? ?? []);
    final versions = data
        .whereType<Map<String, dynamic>>()
        .map((f) => _versionFromFile(f, projectId))
        .toList();
    versions.sort((a, b) => b.datePublished.compareTo(a.datePublished));
    return versions;
  }

  @override
  Future<List<ModProjectInfo>> getProjects(List<String> projectIds) async {
    if (projectIds.isEmpty) return const [];
    final ids = projectIds
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return const [];
    final uri = Uri.parse('$_apiBase/v1/mods');
    final json = await _postJson(uri, {'modIds': ids});
    final data = ((json as Map<String, dynamic>)['data'] as List? ?? []);
    return data.whereType<Map<String, dynamic>>().map((m) {
      final logo = m['logo'] as Map<String, dynamic>?;
      return ModProjectInfo(
        id: '${m['id']}',
        title: m['name'] as String? ?? '',
        iconUrl: logo?['thumbnailUrl'] as String? ?? logo?['url'] as String?,
      );
    }).toList();
  }

  /// 批量解析文件下载信息（整合包用）：`POST /v1/mods/files`。
  /// 返回 {fileId: ModVersionFile}。
  Future<Map<int, ModVersionFile>> resolveFiles(List<int> fileIds) async {
    if (fileIds.isEmpty) return {};
    final uri = Uri.parse('$_apiBase/v1/mods/files');
    final json = await _postJson(uri, {'fileIds': fileIds});
    final data = ((json as Map<String, dynamic>)['data'] as List? ?? []);
    final result = <int, ModVersionFile>{};
    for (final item in data.whereType<Map<String, dynamic>>()) {
      final id = item['id'] as int?;
      if (id == null) continue;
      result[id] = _fileFromJson(item);
    }
    return result;
  }

  // ── HTTP ────────────────────────────────────────────────────

  Future<Object?> _getJson(Uri uri) async {
    final target = await ModMirror.rewriteApi(uri);
    final headers = {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
      ...await ModMirror.curseForgeHeaders(),
    };
    final res = await http
        .get(target, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('CurseForge HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  Future<Object?> _postJson(Uri uri, Map<String, dynamic> body) async {
    final target = await ModMirror.rewriteApi(uri);
    final headers = {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...await ModMirror.curseForgeHeaders(),
    };
    final res = await http
        .post(target, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('CurseForge HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body);
  }

  // ── 映射 ────────────────────────────────────────────────────

  ModSearchHit _hitFromJson(Map<String, dynamic> j) {
    final logo = j['logo'] as Map<String, dynamic>?;
    final links = j['links'] as Map<String, dynamic>?;
    final authors = (j['authors'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((a) => a['name'] as String?)
        .whereType<String>()
        .toList();
    final categories = (j['categories'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((c) => c['name'] as String?)
        .whereType<String>()
        .toList();
    return ModSearchHit(
      sourceType: ModSourceType.curseforge,
      projectId: '${j['id']}',
      slug: j['slug'] as String? ?? '${j['id']}',
      title: j['name'] as String? ?? '',
      description: j['summary'] as String? ?? '',
      iconUrl: logo?['thumbnailUrl'] as String? ?? logo?['url'] as String?,
      downloads: (j['downloadCount'] as num?)?.toInt() ?? 0,
      categories: categories,
      author: authors.isEmpty ? null : authors.first,
      pageUrl: links?['websiteUrl'] as String?,
    );
  }

  /// 由 CF 文件对象构造中立版本（每个 file 即一个版本）。
  ModVersionInfo _versionFromFile(Map<String, dynamic> f, String projectId) {
    final gameVersions = <String>[];
    final loaders = <String>[];
    for (final v in (f['gameVersions'] as List? ?? []).whereType<String>()) {
      // CF 把 MC 版本与加载器名混在 gameVersions 里，按已知加载器名分流。
      final lower = v.toLowerCase();
      if (const ['forge', 'fabric', 'quilt', 'neoforge'].contains(lower)) {
        loaders.add(lower);
      } else {
        gameVersions.add(v);
      }
    }
    return ModVersionInfo(
      sourceType: ModSourceType.curseforge,
      id: '${f['id']}',
      name: f['displayName'] as String? ?? f['fileName'] as String? ?? '',
      versionNumber: f['fileName'] as String? ?? '',
      files: [_fileFromJson(f)],
      versionType: _releaseType(f['releaseType'] as int?),
      gameVersions: gameVersions,
      loaders: loaders,
      datePublished:
          DateTime.tryParse(f['fileDate'] as String? ?? '') ?? DateTime.now(),
      projectId: projectId,
      dependencies: (f['dependencies'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(_depFromJson)
          .toList(),
    );
  }

  ModVersionFile _fileFromJson(Map<String, dynamic> f) {
    final fileName = f['fileName'] as String? ?? '';
    var downloadUrl = f['downloadUrl'] as String?;
    // 作者禁用 API 分发时 downloadUrl 为 null，用 CDN 规则回退。
    if (downloadUrl == null || downloadUrl.isEmpty) {
      final id = f['id'] as int?;
      if (id != null && fileName.isNotEmpty) {
        downloadUrl =
            'https://edge.forgecdn.net/files/${id ~/ 1000}/${id % 1000}/$fileName';
      }
    }
    String? sha1;
    for (final h in (f['hashes'] as List? ?? [])
        .whereType<Map<String, dynamic>>()) {
      // algo 1 = SHA1, 2 = MD5。
      if (h['algo'] == 1) sha1 = h['value'] as String?;
    }
    return ModVersionFile(
      downloads: downloadUrl == null ? const [] : [downloadUrl],
      filename: fileName,
      size: (f['fileLength'] as num?)?.toInt() ?? 0,
      sha1: sha1,
    );
  }

  ModVersionDependency _depFromJson(Map<String, dynamic> d) {
    return ModVersionDependency(
      dependencyType: _depType(d['relationType'] as int?),
      projectId: d['modId'] == null ? null : '${d['modId']}',
    );
  }

  static ModDependencyType _depType(int? relationType) => switch (relationType) {
    1 => ModDependencyType.embedded,
    2 => ModDependencyType.optional,
    5 => ModDependencyType.incompatible,
    _ => ModDependencyType.required, // 3 = requiredDependency
  };

  static String _releaseType(int? t) => switch (t) {
    2 => 'beta',
    3 => 'alpha',
    _ => 'release', // 1 = release
  };
}
