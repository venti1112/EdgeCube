import '../modrinth_service.dart';
import 'mod_source.dart';

/// Modrinth 平台实现：包装现有 [ModrinthService]，把其结果映射为中立模型。
///
/// [ModrinthService] 本体保留不动（本地更新检查 checkUpdates /
/// getVersionsByHashes 仍直接使用它），本类只负责搜索/版本浏览的中立化。
class ModrinthModSource extends ModSource {
  const ModrinthModSource();

  static const _modLoaders = ['fabric', 'forge', 'quilt', 'neoforge'];
  static const _pluginLoaders = [
    'paper',
    'spigot',
    'bukkit',
    'bungeecord',
    'velocity',
    'waterfall',
    'folia',
    'purpur',
  ];

  @override
  ModSourceType get type => ModSourceType.modrinth;

  @override
  String get displayName => 'Modrinth';

  @override
  bool supportsProjectType(String projectType) => true;

  @override
  List<String> supportedLoaders(String projectType) =>
      projectType == 'plugin' ? _pluginLoaders : _modLoaders;

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
    final result = await ModrinthService.search(
      query,
      offset: offset,
      limit: limit,
      gameVersion: gameVersion,
      loader: loader,
      sort: _toModrinthSort(sort),
      projectType: projectType,
    );
    return ModSearchResult(
      hits: result.hits.map(_hitToNeutral).toList(),
      totalHits: result.totalHits,
      offset: result.offset,
      limit: result.limit,
    );
  }

  @override
  Future<List<ModVersionInfo>> getVersions(
    String projectId, {
    String projectType = 'mod',
  }) async {
    final versions = await ModrinthService.getVersions(projectId);
    // 按项目类型过滤（只保留含对应加载器的版本），与原下载页 _applyFilters 一致。
    final typeLoaders = projectType == 'plugin' ? _pluginLoaders : _modLoaders;
    return versions
        .where((v) => v.loaders.any(typeLoaders.contains))
        .map(_versionToNeutral)
        .toList();
  }

  @override
  Future<List<ModProjectInfo>> getProjects(List<String> projectIds) async {
    final projects = await ModrinthService.getProjects(projectIds);
    return projects
        .map((p) => ModProjectInfo(id: p.id, title: p.title, iconUrl: p.iconUrl))
        .toList();
  }

  // ── 映射 ────────────────────────────────────────────────────

  ModSearchHit _hitToNeutral(ModrinthSearchHit h) => ModSearchHit(
    sourceType: ModSourceType.modrinth,
    projectId: h.projectId,
    slug: h.slug,
    title: h.title,
    description: h.description,
    iconUrl: h.iconUrl,
    downloads: h.downloads,
    follows: h.follows,
    categories: h.categories,
    pageUrl: 'https://modrinth.com/project/${h.slug}',
  );

  ModVersionInfo _versionToNeutral(ModrinthVersion v) => ModVersionInfo(
    sourceType: ModSourceType.modrinth,
    id: v.id,
    name: v.name,
    versionNumber: v.versionNumber,
    files: v.files.map(_fileToNeutral).toList(),
    versionType: v.versionType,
    gameVersions: v.gameVersions,
    loaders: v.loaders,
    datePublished: v.datePublished,
    projectId: v.projectId,
    dependencies: v.dependencies.map(_depToNeutral).toList(),
  );

  ModVersionFile _fileToNeutral(ModrinthFile f) => ModVersionFile(
    downloads: [f.url],
    filename: f.filename,
    size: f.size,
    sha1: f.sha1,
  );

  ModVersionDependency _depToNeutral(ModrinthDependency d) =>
      ModVersionDependency(
        dependencyType: _depType(d.dependencyType),
        projectId: d.projectId,
        dependencyName: d.dependencyName,
      );

  static ModDependencyType _depType(String raw) => switch (raw) {
    'optional' => ModDependencyType.optional,
    'incompatible' => ModDependencyType.incompatible,
    'embedded' => ModDependencyType.embedded,
    _ => ModDependencyType.required,
  };

  static ModrinthSort _toModrinthSort(ModSortType s) => switch (s) {
    ModSortType.relevance => ModrinthSort.relevance,
    ModSortType.downloads => ModrinthSort.downloads,
    ModSortType.follows => ModrinthSort.follows,
    ModSortType.newest => ModrinthSort.newest,
    ModSortType.updated => ModrinthSort.updated,
  };
}
