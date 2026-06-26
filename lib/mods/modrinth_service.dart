import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Modrinth 搜索结果项。
class ModrinthSearchHit {
  const ModrinthSearchHit({
    required this.projectId,
    required this.slug,
    required this.title,
    required this.description,
    this.iconUrl,
    required this.downloads,
    required this.categories,
    required this.follows,
  });

  final String projectId;
  final String slug;
  final String title;
  final String description;
  final String? iconUrl;
  final int downloads;
  final int follows;
  final List<String> categories;

  factory ModrinthSearchHit.fromJson(Map<String, dynamic> json) {
    return ModrinthSearchHit(
      projectId: json['project_id'] as String,
      slug: json['slug'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      downloads: json['downloads'] as int? ?? 0,
      follows: json['follows'] as int? ?? 0,
      categories: (json['categories'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// 搜索结果（含分页信息）。
class ModrinthSearchResult {
  const ModrinthSearchResult({
    required this.hits,
    required this.totalHits,
    required this.offset,
    required this.limit,
  });

  final List<ModrinthSearchHit> hits;
  final int totalHits;
  final int offset;
  final int limit;

  bool get hasMore => offset + hits.length < totalHits;
}

/// Modrinth 项目详情（用于批量获取图标）。
class ModrinthProject {
  const ModrinthProject({
    required this.id,
    required this.title,
    this.iconUrl,
  });

  final String id;
  final String title;
  final String? iconUrl;

  factory ModrinthProject.fromJson(Map<String, dynamic> json) {
    return ModrinthProject(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
    );
  }
}

/// Modrinth 版本文件。
class ModrinthFile {
  const ModrinthFile({
    required this.url,
    required this.filename,
    required this.size,
    this.sha1,
  });

  final String url;
  final String filename;
  final int size;
  final String? sha1;

  factory ModrinthFile.fromJson(Map<String, dynamic> json) {
    final hashes = json['hashes'] as Map<String, dynamic>?;
    return ModrinthFile(
      url: json['url'] as String,
      filename: json['filename'] as String,
      size: json['size'] as int? ?? 0,
      sha1: hashes?['sha1'] as String?,
    );
  }
}

/// Modrinth 版本依赖项。
class ModrinthDependency {
  const ModrinthDependency({
    required this.dependencyType,
    this.projectId,
    this.versionId,
    this.fileName,
    this.dependencyName,
  });

  /// required / optional / incompatible / embedded
  final String dependencyType;
  final String? projectId;
  final String? versionId;
  final String? fileName;
  /// 新版 API 直接返回的依赖名称（旧版可能为空，需通过 project_id 二次查询）
  final String? dependencyName;

  bool get isRequired => dependencyType == 'required';
  bool get isOptional => dependencyType == 'optional';
  bool get isIncompatible => dependencyType == 'incompatible';

  factory ModrinthDependency.fromJson(Map<String, dynamic> json) {
    return ModrinthDependency(
      dependencyType: json['dependency_type'] as String? ?? 'required',
      projectId: json['project_id'] as String?,
      versionId: json['version_id'] as String?,
      fileName: json['file_name'] as String?,
      dependencyName: json['dependency_name'] as String?,
    );
  }
}

/// Modrinth 版本信息。
class ModrinthVersion {
  const ModrinthVersion({
    required this.id,
    required this.name,
    required this.versionNumber,
    required this.files,
    required this.versionType,
    required this.gameVersions,
    required this.loaders,
    required this.datePublished,
    required this.projectId,
    required this.dependencies,
  });

  final String id;
  final String name;
  final String versionNumber;
  final List<ModrinthFile> files;
  final String versionType; // release, beta, alpha
  final List<String> gameVersions;
  final List<String> loaders;
  final DateTime datePublished;
  final String projectId;
  final List<ModrinthDependency> dependencies;

  bool get isRelease => versionType == 'release';

  /// 首个可下载文件（Modrinth 版本通常只有一个文件）。
  ModrinthFile? get primaryFile =>
      files.isNotEmpty ? files.first : null;

  factory ModrinthVersion.fromJson(Map<String, dynamic> json) {
    return ModrinthVersion(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      versionNumber: json['version_number'] as String? ?? '',
      files: ((json['files'] as List?) ?? [])
          .map((e) => ModrinthFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      versionType: json['version_type'] as String? ?? 'release',
      gameVersions: (json['game_versions'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
      loaders: (json['loaders'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
      datePublished:
          DateTime.tryParse(json['date_published'] as String? ?? '') ??
              DateTime.now(),
      projectId: json['project_id'] as String? ?? '',
      dependencies: ((json['dependencies'] as List?) ?? [])
          .map((e) => ModrinthDependency.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 游戏版本标签。
class ModrinthGameVersion {
  const ModrinthGameVersion({
    required this.version,
    required this.versionType,
    this.date,
  });

  final String version;
  final String versionType; // release, snapshot, beta, alpha
  final DateTime? date;

  factory ModrinthGameVersion.fromJson(Map<String, dynamic> json) {
    return ModrinthGameVersion(
      version: json['version'] as String,
      versionType: json['version_type'] as String? ?? 'release',
      date: DateTime.tryParse(json['date'] as String? ?? ''),
    );
  }
}

/// 搜索排序方式。
enum ModrinthSort {
  relevance, // 相关度
  downloads, // 下载量
  follows, // 关注数
  newest, // 最新创建
  updated, // 最近更新
}

/// Modrinth API 客户端。
///
/// 参考 PCL-CE 的 ModDownload.cs / ModComp.cs，封装搜索、版本获取、
/// 更新检查与文件下载。仅使用 Modrinth 官方 API（无需 API Key）。
class ModrinthService {
  ModrinthService._();

  static const _baseUrl = 'https://api.modrinth.com/v2';
  static const _userAgent = 'EdgeCube';

  /// 每页数量（与 PCL-CE 的 compPageSize 不同，移动端用较小值）。
  static const pageSize = 20;

  /// 搜索模组或插件。
  ///
  /// [query] 为空时返回按 [sort] 排序的浏览列表。
  /// [offset] 用于分页。[gameVersion] / [loader] 用于筛选。
  /// [projectType] 为 'mod' 或 'plugin'，决定按加载器 categories 过滤
  /// （Modrinth 的 project_type 字段不准确，跨平台项目大多标记为 mod）。
  static Future<ModrinthSearchResult> search(
    String query, {
    int offset = 0,
    int limit = pageSize,
    String? gameVersion,
    String? loader,
    ModrinthSort sort = ModrinthSort.relevance,
    String projectType = 'mod',
  }) async {
    // 按项目类型选择加载器 categories（OR 关系）
    final typeCategories = projectType == 'plugin'
        ? const ['paper', 'spigot', 'bukkit', 'bungeecord', 'velocity', 'waterfall', 'folia', 'purpur']
        : const ['fabric', 'forge', 'quilt', 'neoforge'];

    final facets = <List<String>>[
      typeCategories.map((c) => 'categories:$c').toList(),
    ];
    if (gameVersion != null && gameVersion.isNotEmpty) {
      facets.add(["versions:'$gameVersion'"]);
    }
    if (loader != null && loader.isNotEmpty) {
      facets.add(["categories:'$loader'"]);
    }

    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'facets': jsonEncode(facets),
      'index': _sortIndex(sort),
    };
    if (query.isNotEmpty) {
      params['query'] = query;
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final hits = (json['hits'] as List? ?? [])
        .map((e) => ModrinthSearchHit.fromJson(e as Map<String, dynamic>))
        .toList();
    final totalHits = json['total_hits'] as int? ?? hits.length;
    return ModrinthSearchResult(
      hits: hits,
      totalHits: totalHits,
      offset: offset,
      limit: limit,
    );
  }

  static String _sortIndex(ModrinthSort sort) => switch (sort) {
        ModrinthSort.relevance => 'relevance',
        ModrinthSort.downloads => 'downloads',
        ModrinthSort.follows => 'follows',
        ModrinthSort.newest => 'newest',
        ModrinthSort.updated => 'updated',
      };

  /// 获取项目的所有版本（按发布时间降序）。
  static Future<List<ModrinthVersion>> getVersions(String projectId) async {
    final uri = Uri.parse('$_baseUrl/project/$projectId/version');
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as List;
    final versions = json
        .map((e) => ModrinthVersion.fromJson(e as Map<String, dynamic>))
        .toList();
    versions.sort((a, b) => b.datePublished.compareTo(a.datePublished));
    return versions;
  }

  /// 批量获取项目信息（用于获取图标 URL）。
  static Future<List<ModrinthProject>> getProjects(
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/projects').replace(
      queryParameters: {'ids': jsonEncode(projectIds)},
    );
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as List? ?? [];
    return json
        .map((e) => ModrinthProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取游戏版本标签列表。
  static Future<List<ModrinthGameVersion>> getGameVersions() async {
    final uri = Uri.parse('$_baseUrl/tag/game_version');
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as List? ?? [];
    return json
        .map((e) => ModrinthGameVersion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 按文件 SHA1 哈希批量检查更新。
  ///
  /// 返回 {sha1: ModrinthVersion} 映射——仅包含有新版本的哈希。
  /// 调用方需对比返回版本的文件 SHA1 与本地哈希来判断是否真正需要更新。
  static Future<Map<String, ModrinthVersion>> checkUpdates(
    List<String> sha1Hashes,
  ) async {
    if (sha1Hashes.isEmpty) return {};
    final uri = Uri.parse('$_baseUrl/version_files/update');
    final body = jsonEncode({
      'hashes': sha1Hashes,
      'algorithm': 'sha1',
    });
    final response = await http
        .post(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = <String, ModrinthVersion>{};
    for (final entry in json.entries) {
      final versionData = entry.value as Map<String, dynamic>?;
      if (versionData != null) {
        result[entry.key] = ModrinthVersion.fromJson(versionData);
      }
    }
    return result;
  }

  /// 按文件 SHA1 哈希批量查询已安装版本信息。
  ///
  /// 返回 {sha1: ModrinthVersion} 映射——用于识别本地 jar 对应的 Modrinth 版本。
  static Future<Map<String, ModrinthVersion>> getVersionsByHashes(
    List<String> sha1Hashes,
  ) async {
    if (sha1Hashes.isEmpty) return {};
    final uri = Uri.parse('$_baseUrl/version_files');
    final body = jsonEncode({
      'hashes': sha1Hashes,
      'algorithm': 'sha1',
    });
    final response = await http
        .post(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = <String, ModrinthVersion>{};
    for (final entry in json.entries) {
      final versionData = entry.value as Map<String, dynamic>?;
      if (versionData != null) {
        result[entry.key] = ModrinthVersion.fromJson(versionData);
      }
    }
    return result;
  }

  /// 计算文件的 SHA1 哈希。
  static Future<String> computeSha1(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return sha1.convert(bytes).toString();
  }

  /// 下载文件到指定路径，[onProgress] 回调 (received, total)。
  ///
  /// [isCancelled] 返回 true 时中断下载并删除不完整的文件。
  static Future<void> downloadFile(
    String url,
    String destPath, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode != 200) {
      client.close();
      throw Exception('HTTP ${response.statusCode}');
    }
    final total = response.contentLength;
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
      await sink.close();
      client.close();
      if (cancelled) {
        try {
          await File(destPath).delete();
        } catch (_) {}
      }
    }
  }
}
