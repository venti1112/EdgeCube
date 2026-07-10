import 'dart:convert';

import 'package:http/http.dart' as http;

import '../net/download_engine.dart';

/// Poggit 插件分类。
class PoggitCategory {
  const PoggitCategory({
    required this.major,
    required this.categoryName,
  });

  final bool major;
  final String categoryName;

  factory PoggitCategory.fromJson(Map<String, dynamic> json) {
    return PoggitCategory(
      major: json['major'] as bool? ?? false,
      categoryName: json['category_name'] as String? ?? '',
    );
  }
}

/// PocketMine API 版本范围（插件兼容的 API 版本）。
class PoggitApiRange {
  const PoggitApiRange({required this.from, required this.to});

  final String from;
  final String to;

  factory PoggitApiRange.fromJson(Map<String, dynamic> json) {
    return PoggitApiRange(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
    );
  }
}

/// Poggit 插件版本（每个 JSON 对象代表一个版本）。
///
/// 字段对应 Poggit `/plugins.min.json` 返回的结构。
class PoggitPlugin {
  const PoggitPlugin({
    required this.id,
    required this.name,
    required this.version,
    required this.projectName,
    required this.projectId,
    required this.tagline,
    required this.artifactUrl,
    required this.downloads,
    required this.htmlUrl,
    required this.license,
    required this.categories,
    required this.api,
    required this.keywords,
    required this.producers,
    required this.submissionDate,
    required this.stateName,
    this.iconUrl,
    this.descriptionUrl,
    this.changelogUrl,
    this.score,
    this.isPreRelease = false,
    this.isOutdated = false,
    this.isObsolete = false,
    this.isOfficial = false,
    this.isAbandoned = false,
  });

  /// 版本 ID（每个版本唯一）。
  final int id;

  /// 版本特定的名称。
  final String name;

  /// 版本号。
  final String version;

  /// 项目名称（同一插件的不同版本 projectName 相同）。
  final String projectName;

  /// 项目 ID（同一插件的所有版本 projectId 相同）。
  final int projectId;

  /// 简短描述。
  final String tagline;

  /// 下载地址（.phar 文件）。
  final String artifactUrl;

  /// 下载次数。
  final int downloads;

  /// Poggit 页面链接。
  final String htmlUrl;

  /// 许可证标识。
  final String license;

  /// 分类列表。
  final List<PoggitCategory> categories;

  /// 兼容的 PocketMine API 版本范围。
  final List<PoggitApiRange> api;

  /// 关键词。
  final List<String> keywords;

  /// 作者映射（角色 → 作者名列表）。
  final Map<String, List<String>> producers;

  /// 提交时间（Unix 时间戳，秒）。
  final int submissionDate;

  /// 状态名称（如 "Approved"）。
  final String stateName;

  final String? iconUrl;
  final String? descriptionUrl;
  final String? changelogUrl;
  final int? score;
  final bool isPreRelease;
  final bool isOutdated;
  final bool isObsolete;
  final bool isOfficial;
  final bool isAbandoned;

  /// 下载文件名（从 artifact_url 推导，附加 .phar 扩展名）。
  String get fileName {
    final safeName = projectName.isNotEmpty ? projectName : name;
    return '${safeName}_v$version.phar';
  }

  /// 主要分类名（major 为 true 的第一个）。
  String get mainCategory {
    final major = categories.where((c) => c.major).firstOrNull;
    return major?.categoryName ?? (categories.isNotEmpty ? categories.first.categoryName : '');
  }

  /// 作者列表（所有角色的作者合并）。
  List<String> get authors {
    return producers.values.expand((list) => list).toList();
  }

  factory PoggitPlugin.fromJson(Map<String, dynamic> json) {
    return PoggitPlugin(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      projectName: json['project_name'] as String? ?? json['name'] as String? ?? '',
      projectId: json['project_id'] as int? ?? 0,
      tagline: json['tagline'] as String? ?? '',
      artifactUrl: json['artifact_url'] as String? ?? '',
      downloads: json['downloads'] as int? ?? 0,
      htmlUrl: json['html_url'] as String? ?? '',
      license: json['license'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      descriptionUrl: json['description_url'] as String?,
      changelogUrl: json['changelog_url'] as String?,
      score: json['score'] as int?,
      isPreRelease: json['is_pre_release'] as bool? ?? false,
      isOutdated: json['is_outdated'] as bool? ?? false,
      isObsolete: json['is_obsolete'] as bool? ?? false,
      isOfficial: json['is_official'] as bool? ?? false,
      isAbandoned: json['is_abandoned'] as bool? ?? false,
      submissionDate: json['submission_date'] as int? ?? 0,
      stateName: json['state_name'] as String? ?? '',
      categories: (json['categories'] as List?)
              ?.map((e) => PoggitCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      api: (json['api'] as List?)
              ?.map((e) => PoggitApiRange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      keywords: (json['keywords'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      producers: (json['producers'] as Map<String, dynamic>?)?.map(
              (role, list) => MapEntry(
                  role, (list as List).map((e) => e as String).toList())) ??
          const {},
    );
  }
}

/// Poggit API 客户端。
///
/// Poggit 是 PocketMine-MP 的官方插件仓库，API 文档：
/// https://github.com/poggit/support/blob/master/api.md
///
/// 注意：Poggit 的 `name` 查询参数是精确匹配（非模糊搜索），
/// 因此搜索需要先拉取全量列表再在客户端过滤。
class PoggitService {
  PoggitService._();

  static const _baseUrl = 'https://poggit.pmmp.io';
  static const _userAgent = 'EdgeCube';

  /// 内存缓存（仅最新版本列表），有效期 12 小时。
  static List<PoggitPlugin>? _cache;
  static DateTime? _cacheTime;

  /// 拉取全部插件列表（仅最新版本），带内存缓存。
  ///
  /// [forceRefresh] 为 true 时强制重新拉取。
  static Future<List<PoggitPlugin>> fetchPlugins({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < const Duration(hours: 12)) {
      return _cache!;
    }

    final url = '$_baseUrl/plugins.min.json?latest-only=true';
    final response = await http
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as List;
    final plugins = json
        .map((e) => PoggitPlugin.fromJson(e as Map<String, dynamic>))
        .toList();

    _cache = plugins;
    _cacheTime = DateTime.now();
    return plugins;
  }

  /// 按插件名精确查询所有版本（Poggit 的 name 参数为精确匹配）。
  static Future<List<PoggitPlugin>> getPluginVersions(String name) async {
    final url = '$_baseUrl/plugins.min.json?name=${Uri.encodeComponent(name)}';
    final response = await http
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as List;
    return json
        .map((e) => PoggitPlugin.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 客户端模糊搜索：在插件名、项目名、描述、分类、关键词中匹配。
  static List<PoggitPlugin> search(
    List<PoggitPlugin> plugins,
    String query,
  ) {
    if (query.isEmpty) return plugins;
    final q = query.toLowerCase();
    return plugins.where((p) {
      if (p.name.toLowerCase().contains(q)) return true;
      if (p.projectName.toLowerCase().contains(q)) return true;
      if (p.tagline.toLowerCase().contains(q)) return true;
      if (p.categories.any((c) => c.categoryName.toLowerCase().contains(q))) {
        return true;
      }
      if (p.keywords.any((k) => k.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  /// 获取资源链接的内容（如插件描述、更新日志）。
  ///
  /// Poggit 的 description_url / changelog_url 指向 /r/{id} 资源，
  /// 返回的是 HTML 格式。追加 `.md` 可获取原始 Markdown。
  static Future<String> fetchResourceMarkdown(String? resourceUrl) async {
    if (resourceUrl == null || resourceUrl.isEmpty) return '';
    // 将 /r/{id} 转换为 /r/{id}.md 获取 Markdown 原文
    final mdUrl = resourceUrl.endsWith('.md')
        ? resourceUrl
        : '$resourceUrl.md';
    final response = await http
        .get(Uri.parse(mdUrl), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return '';
    return response.body;
  }

  /// 下载插件 .phar 文件到指定路径。
  ///
  /// 下载 Poggit 插件文件到指定路径。
  ///
  /// 底层委托全局 [DownloadEngine]（downloadx 分片并行下载，UA 由引擎全局注入）。
  static Future<void> downloadFile(
    String url,
    String destPath, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    await DownloadEngine.instance.downloadToFile(
      url,
      destPath,
      isCancelled: isCancelled,
      onProgress: onProgress == null
          ? null
          : (p) => onProgress(p.receivedBytes, p.totalBytes),
    );
  }
}
