/// 模组 / 插件下载平台的中立抽象层。
///
/// 借鉴 HMCL 的 `RemoteAddonRepository` + 中立域模型设计：每个平台
/// （Modrinth / CurseForge / Hangar / Spiget）实现 [ModSource] 接口，把各自
/// 的原始响应映射为这里定义的中立模型，UI 只依赖中立模型而与具体平台解耦。
library;

/// 支持的下载平台类型。
enum ModSourceType { modrinth, curseforge, hangar, spiget }

/// 依赖项目的展示信息（名称 / 图标），用于版本详情页解析依赖。
class ModProjectInfo {
  const ModProjectInfo({required this.id, required this.title, this.iconUrl});

  final String id;
  final String title;
  final String? iconUrl;
}

/// 搜索排序方式（中立）。各平台在自身实现中映射到对应参数。
enum ModSortType { relevance, downloads, follows, newest, updated }

/// 依赖关系类型（中立）。
enum ModDependencyType { required, optional, incompatible, embedded }

/// 中立搜索结果项。
class ModSearchHit {
  const ModSearchHit({
    required this.sourceType,
    required this.projectId,
    required this.slug,
    required this.title,
    required this.description,
    this.iconUrl,
    this.downloads = 0,
    this.follows = 0,
    this.categories = const [],
    this.author,
    this.pageUrl,
  });

  final ModSourceType sourceType;
  final String projectId;
  final String slug;
  final String title;
  final String description;
  final String? iconUrl;
  final int downloads;
  final int follows;
  final List<String> categories;
  final String? author;
  final String? pageUrl;
}

/// 中立搜索结果（含分页信息）。
class ModSearchResult {
  const ModSearchResult({
    required this.hits,
    required this.totalHits,
    required this.offset,
    required this.limit,
  });

  final List<ModSearchHit> hits;
  final int totalHits;
  final int offset;
  final int limit;

  bool get hasMore => offset + hits.length < totalHits;

  static const empty = ModSearchResult(
    hits: [],
    totalHits: 0,
    offset: 0,
    limit: 0,
  );
}

/// 中立版本文件。[downloads] 为有序候选 URL 列表（镜像在前、官方兜底），
/// 供下载队列多源回退；[url] 便捷取首个。
class ModVersionFile {
  const ModVersionFile({
    required this.downloads,
    required this.filename,
    this.size = 0,
    this.sha1,
    this.external = false,
  });

  final List<String> downloads;
  final String filename;
  final int size;
  final String? sha1;

  /// 外链文件（如 Spiget 部分资源），无法直连下载，仅能跳转官网。
  final bool external;

  String? get url => downloads.isEmpty ? null : downloads.first;
  bool get downloadable => !external && downloads.isNotEmpty;
}

/// 中立版本依赖项。
class ModVersionDependency {
  const ModVersionDependency({
    required this.dependencyType,
    this.projectId,
    this.dependencyName,
  });

  final ModDependencyType dependencyType;
  final String? projectId;
  final String? dependencyName;

  bool get isRequired => dependencyType == ModDependencyType.required;
  bool get isOptional => dependencyType == ModDependencyType.optional;
  bool get isIncompatible => dependencyType == ModDependencyType.incompatible;
}

/// 中立版本信息。
class ModVersionInfo {
  const ModVersionInfo({
    required this.sourceType,
    required this.id,
    required this.name,
    required this.versionNumber,
    required this.files,
    this.versionType = 'release',
    this.gameVersions = const [],
    this.loaders = const [],
    required this.datePublished,
    this.projectId = '',
    this.dependencies = const [],
  });

  final ModSourceType sourceType;
  final String id;
  final String name;
  final String versionNumber;
  final List<ModVersionFile> files;
  final String versionType; // release / beta / alpha
  final List<String> gameVersions;
  final List<String> loaders;
  final DateTime datePublished;
  final String projectId;
  final List<ModVersionDependency> dependencies;

  bool get isRelease => versionType == 'release';

  /// 首个可下载文件（多数平台单版本仅一个文件）。
  ModVersionFile? get primaryFile => files.isEmpty ? null : files.first;
}

/// 下载平台抽象接口。每个平台实现此接口，把原始 API 响应映射为中立模型。
///
/// 实现应是无状态的（可 const 或单例），网络失败以抛异常或返回空结果表达，
/// 由 UI 统一处理。
abstract class ModSource {
  const ModSource();

  /// 平台类型。
  ModSourceType get type;

  /// 平台展示名（如 "Modrinth" / "CurseForge"）。
  String get displayName;

  /// 平台是否当前可用。多数平台恒为 true；CurseForge 依赖编译期 Key
  /// 或镜像开关，故为异步判断。
  Future<bool> get isAvailable async => true;

  /// 是否支持某项目类型（'mod' / 'plugin'）。
  bool supportsProjectType(String projectType);

  /// 该项目类型下可筛选的加载器列表（用于 UI 筛选器）。空表示不提供加载器筛选。
  List<String> supportedLoaders(String projectType);

  /// 是否支持按游戏版本筛选（Spiget 等不支持）。
  bool get supportsGameVersionFilter => true;

  /// 搜索模组 / 插件。
  ///
  /// [query] 为空时返回按 [sort] 排序的浏览列表；[offset] 分页；
  /// [gameVersion] / [loader] 筛选（平台不支持时忽略）；[projectType]
  /// 为 'mod' 或 'plugin'。
  Future<ModSearchResult> search(
    String query, {
    int offset = 0,
    int limit = 20,
    String? gameVersion,
    String? loader,
    ModSortType sort = ModSortType.relevance,
    String projectType = 'mod',
  });

  /// 获取项目的版本列表（按发布时间降序）。
  Future<List<ModVersionInfo>> getVersions(
    String projectId, {
    String projectType = 'mod',
  });

  /// 批量获取依赖项目的展示信息（名称/图标），用于版本详情页解析依赖。
  /// 不支持或无依赖概念的平台返回空列表（依赖 UI 自然隐藏）。
  Future<List<ModProjectInfo>> getProjects(List<String> projectIds) async =>
      const [];
}
