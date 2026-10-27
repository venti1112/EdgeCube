/// 模组 / 插件的中立模型（与 daemon 的 `mods.*` 返回值一一对应）。
///
/// 这里**不做任何判断**：哪个平台、哪些加载器、装到哪个目录，全都是 daemon
/// 通过 `mods.sources` 给的。前端只负责把它们画出来 —— 加一个源、加一个加载器
/// 都不需要改 App（与 `mcserver/models.dart` 同一个套路）。
library;

/// 一个下载源（本轮只有 Modrinth）。
class ModSourceOption {
  const ModSourceOption({
    required this.id,
    required this.name,
    required this.url,
  });

  factory ModSourceOption.fromJson(Map<String, dynamic> json) =>
      ModSourceOption(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  final String id;
  final String name;

  /// 项目主页，用于「在浏览器打开」。
  final String url;
}

/// 一个项目类型（模组 / 插件）。
///
/// [dir] 是这个类型装到实例里的哪个子目录 —— **由 daemon 决定**，
/// 前端只显示。选错目录（插件丢进 `mods/`）服务端只会静默不加载。
class ModProjectType {
  const ModProjectType({
    required this.id,
    required this.name,
    required this.description,
    required this.dir,
    required this.loaders,
  });

  factory ModProjectType.fromJson(Map<String, dynamic> json) => ModProjectType(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    dir: json['dir'] as String? ?? '',
    loaders: _strings(json['loaders']),
  );

  final String id;
  final String name;
  final String description;

  /// 落地的子目录（`mods` / `plugins`）。
  final String dir;

  /// 这个类型下可筛的加载器 id。
  final List<String> loaders;
}

/// 一个加载器（id 直接用上游的说法）。
class ModLoader {
  const ModLoader({required this.id, required this.name});

  factory ModLoader.fromJson(Map<String, dynamic> json) => ModLoader(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  final String id;
  final String name;
}

/// 一种排序方式。
class ModSort {
  const ModSort({required this.id, required this.name});

  factory ModSort.fromJson(Map<String, dynamic> json) => ModSort(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  final String id;
  final String name;
}

/// `mods.sources` 的全部内容：**筛选器的唯一出处**。
class ModCatalog {
  const ModCatalog({
    required this.sources,
    required this.projectTypes,
    required this.loaders,
    required this.sorts,
    required this.fileExts,
    required this.disabledSuffix,
  });

  factory ModCatalog.fromJson(Map<String, dynamic> json) => ModCatalog(
    sources: _objects(json['sources'], ModSourceOption.fromJson),
    projectTypes: _objects(json['project_types'], ModProjectType.fromJson),
    loaders: _objects(json['loaders'], ModLoader.fromJson),
    sorts: _objects(json['sorts'], ModSort.fromJson),
    fileExts: _strings(json['file_exts']),
    disabledSuffix: json['disabled_suffix'] as String? ?? '.disabled',
  );

  final List<ModSourceOption> sources;
  final List<ModProjectType> projectTypes;
  final List<ModLoader> loaders;
  final List<ModSort> sorts;

  /// 认哪些后缀算模组（`jar` / `phar`）—— 由 daemon 给，前端不写死。
  final List<String> fileExts;

  final String disabledSuffix;

  static const empty = ModCatalog(
    sources: [],
    projectTypes: [],
    loaders: [],
    sorts: [],
    fileExts: ['jar'],
    disabledSuffix: '.disabled',
  );

  ModProjectType? projectType(String id) =>
      projectTypes.where((item) => item.id == id).firstOrNull;

  ModLoader? loader(String id) =>
      loaders.where((item) => item.id == id).firstOrNull;

  /// 加载器 id → 展示名；认不出就退回 id 本身。
  String loaderName(String id) => loader(id)?.name ?? id;
}

/// `mods.tags`：可选的游戏版本与**该类型可筛的加载器**。
class ModTags {
  const ModTags({
    required this.projectType,
    required this.gameVersions,
    required this.loaders,
    this.shapeMismatch = false,
  });

  factory ModTags.fromJson(Map<String, dynamic> json) {
    final gameVersions = _gameVersions(json['game_versions']);
    return ModTags(
      projectType: json['project_type'] as String? ?? '',
      gameVersions: gameVersions,
      loaders: _objects(json['loaders'], ModLoader.fromJson),
      // 给了东西却一项都没解析出来 = 两端的形状对不上（多半是 daemon 没跟着重新构建）
      shapeMismatch:
          json['game_versions'] is List &&
          (json['game_versions'] as List).isNotEmpty &&
          gameVersions.isEmpty,
    );
  }

  final String projectType;

  /// 上游的游戏版本清单（**含快照 / beta**，顺序就是上游给的「新的在前」）。
  ///
  /// 选项菜单里把正式版挑到前面、其余排后面并带上类型副标题
  /// （见 `ModDownloadPage._showVersionPicker`），所以这里**不能只留正式版** ——
  /// 那样用户就选不了快照了。
  final List<ModGameVersion> gameVersions;

  /// **这个类型**可筛的加载器。插件那一栏不会出现 Fabric / Forge，
  /// 模组那一栏也不会出现 Paper（两张表在 daemon 的 `model.rs` 里分开定义）。
  final List<ModLoader> loaders;

  /// 上边给了游戏版本，却一条都没解析出来。
  ///
  /// 这种「形状对不上」以前会**静默降级**成「菜单里只有任意」，从界面上完全看不出
  /// 是两端版本不一致（真踩过：daemon 换了 `game_versions` 的元素形状，
  /// 旧 daemon 一跑，菜单就只剩「任意」）。所以标出来让界面能提示。
  final bool shapeMismatch;

  static const empty = ModTags(projectType: '', gameVersions: [], loaders: []);
}

/// 解析 `game_versions`：**新形状是对象**（`{version, version_type}`）。
///
/// 同时**容错旧形状**（纯字符串数组，没有类型）—— 那是这一轮改之前的返回。
/// 当一个正式版收下就够了：不兼容的话，daemon 稍旧一点就会让整个菜单只剩
/// 「任意」，而界面上看不出任何原因（真踩过）。
List<ModGameVersion> _gameVersions(Object? raw) {
  if (raw is! List) return const [];
  final out = <ModGameVersion>[];
  for (final item in raw) {
    if (item is Map) {
      // 没有 `version` 的条目直接丢掉 —— 收进来只会在菜单里显示成一行空白，
      // 而且会让「形状对不上」检测不出来（上面靠「非空但零条」判定）
      final parsed = ModGameVersion.fromJson(item.cast<String, dynamic>());
      if (parsed.version.isNotEmpty) out.add(parsed);
    } else if (item is String && item.isNotEmpty) {
      out.add(ModGameVersion(version: item, versionType: 'release'));
    }
  }
  return out;
}

/// 一个游戏版本（上游 `/tag/game_version` 的一项）。
class ModGameVersion {
  const ModGameVersion({required this.version, required this.versionType});

  factory ModGameVersion.fromJson(Map<String, dynamic> json) => ModGameVersion(
    version: json['version'] as String? ?? '',
    versionType: json['version_type'] as String? ?? 'release',
  );

  final String version;

  /// `release` / `snapshot` / `beta` / `alpha`。
  final String versionType;

  bool get isRelease => versionType == 'release';
}

/// 一条搜索结果。
class ModHit {
  const ModHit({
    required this.source,
    required this.projectId,
    required this.slug,
    required this.title,
    required this.description,
    required this.author,
    required this.iconUrl,
    required this.downloads,
    required this.follows,
    required this.categories,
    required this.projectType,
    required this.loaders,
    required this.latestVersion,
    required this.serverSide,
    required this.pageUrl,
  });

  factory ModHit.fromJson(Map<String, dynamic> json) => ModHit(
    source: json['source'] as String? ?? '',
    projectId: json['project_id'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    author: json['author'] as String?,
    iconUrl: json['icon_url'] as String?,
    downloads: _int(json['downloads']),
    follows: _int(json['follows']),
    categories: _strings(json['categories']),
    projectType: json['project_type'] as String? ?? '',
    loaders: _strings(json['loaders']),
    latestVersion: json['latest_version'] as String?,
    serverSide: json['server_side'] as String?,
    pageUrl: json['page_url'] as String? ?? '',
  );

  final String source;
  final String projectId;
  final String slug;
  final String title;
  final String description;
  final String? author;
  final String? iconUrl;
  final int downloads;
  final int follows;
  final List<String> categories;
  final String projectType;
  final List<String> loaders;
  final String? latestVersion;

  /// `required` / `optional` / `unsupported` / `unknown`。
  final String? serverSide;

  final String pageUrl;

  /// 客户端专属（装到服务端没有意义）。
  ///
  /// 上游直接给了这个字段，这里一定要用上：
  /// 把优化模组装进服务端是新手最常踩的坑之一。
  bool get isClientOnly => serverSide == 'unsupported';
}

/// 一页搜索结果。
class ModSearchPage {
  const ModSearchPage({
    required this.hits,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
    required this.projectType,
    required this.loader,
    required this.gameVersion,
    required this.sort,
  });

  factory ModSearchPage.fromJson(Map<String, dynamic> json) => ModSearchPage(
    hits: _objects(json['hits'], ModHit.fromJson),
    total: _int(json['total']),
    offset: _int(json['offset']),
    limit: _int(json['limit']),
    hasMore: json['has_more'] as bool? ?? false,
    projectType: json['project_type'] as String? ?? '',
    loader: json['loader'] as String?,
    gameVersion: json['game_version'] as String?,
    sort: json['sort'] as String? ?? '',
  );

  final List<ModHit> hits;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;
  final String projectType;
  final String? loader;
  final String? gameVersion;
  final String sort;

  static const empty = ModSearchPage(
    hits: [],
    total: 0,
    offset: 0,
    limit: 0,
    hasMore: false,
    projectType: '',
    loader: null,
    gameVersion: null,
    sort: '',
  );
}

/// 一个可下载的文件。
class ModFile {
  const ModFile({
    required this.url,
    required this.filename,
    required this.size,
    required this.sha1,
    required this.primary,
  });

  factory ModFile.fromJson(Map<String, dynamic> json) => ModFile(
    url: json['url'] as String? ?? '',
    filename: json['filename'] as String? ?? '',
    size: _int(json['size']),
    sha1: json['sha1'] as String?,
    primary: json['primary'] as bool? ?? false,
  );

  final String url;
  final String filename;
  final int size;
  final String? sha1;
  final bool primary;
}

/// 一条依赖。
class ModDependency {
  const ModDependency({
    required this.projectId,
    required this.fileName,
    required this.kind,
  });

  factory ModDependency.fromJson(Map<String, dynamic> json) => ModDependency(
    projectId: json['project_id'] as String?,
    fileName: json['file_name'] as String?,
    kind: json['dependency_type'] as String? ?? '',
  );

  final String? projectId;
  final String? fileName;

  /// `required` / `optional` / `incompatible` / `embedded`。
  final String kind;

  bool get isRequired => kind == 'required';
}

/// 上游的一个版本。
class ModVersion {
  const ModVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    required this.kind,
    required this.gameVersions,
    required this.loaders,
    required this.datePublished,
    required this.files,
    required this.dependencies,
  });

  factory ModVersion.fromJson(Map<String, dynamic> json) => ModVersion(
    id: json['id'] as String? ?? '',
    projectId: json['project_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    versionNumber: json['version_number'] as String? ?? '',
    kind: json['version_type'] as String? ?? 'release',
    gameVersions: _strings(json['game_versions']),
    loaders: _strings(json['loaders']),
    datePublished: json['date_published'] as String? ?? '',
    files: _objects(json['files'], ModFile.fromJson),
    dependencies: _objects(json['dependencies'], ModDependency.fromJson),
  );

  final String id;
  final String projectId;
  final String name;
  final String versionNumber;

  /// `release` / `beta` / `alpha`。
  final String kind;
  final List<String> gameVersions;
  final List<String> loaders;
  final String datePublished;
  final List<ModFile> files;
  final List<ModDependency> dependencies;

  bool get isRelease => kind == 'release';

  ModFile? get primaryFile {
    for (final file in files) {
      if (file.primary) return file;
    }
    return files.isEmpty ? null : files.first;
  }

  /// 「需要 Fabric API」这类必须先装的依赖（只挑 required）。
  List<ModDependency> get requiredDependencies =>
      dependencies.where((item) => item.isRequired).toList(growable: false);
}

/// jar 里读到的元数据。
class ModMeta {
  const ModMeta({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.authors,
    required this.url,
    required this.from,
    required this.loader,
    required this.environment,
  });

  factory ModMeta.fromJson(Map<String, dynamic> json) => ModMeta(
    id: json['id'] as String?,
    name: json['name'] as String?,
    version: json['version'] as String?,
    description: json['description'] as String?,
    authors: json['authors'] as String?,
    url: json['url'] as String?,
    from: json['from'] as String? ?? '',
    loader: json['loader'] as String? ?? 'unknown',
    environment: json['environment'] as String? ?? 'unknown',
  );

  final String? id;
  final String? name;
  final String? version;
  final String? description;
  final String? authors;
  final String? url;

  /// 从哪种元数据文件读出来的（`fabric.mod.json` / `plugin.yml` / …）。
  final String from;

  /// `fabric` / `forge` / `quilt` / `neoforge` / `bukkit` / `bungeecord` /
  /// `velocity` / `pocketmine` / `unknown`。
  final String loader;

  /// `client` / `server` / `both` / `unknown`。
  final String environment;

  /// 列表主行显示什么：有名字用名字，没有的让调用方退回文件名。
  String? get displayName => name ?? id;

  /// 加载器展示名（注意 `bukkit` 显示成「Plugin」而不是「Bukkit」）。
  String get loaderLabel => switch (loader) {
    'fabric' => 'Fabric',
    'forge' => 'Forge',
    'quilt' => 'Quilt',
    'neoforge' => 'NeoForge',
    'bukkit' => 'Plugin',
    'bungeecord' => 'BungeeCord',
    'velocity' => 'Velocity',
    'pocketmine' => 'PocketMine',
    _ => '',
  };

  /// 客户端专属（不能在服务端跑）——「客户端模组清理」的依据。
  bool get isClientOnly => environment == 'client';
}

/// 一个已装的模组 / 插件文件。
class InstalledMod {
  const InstalledMod({
    required this.fileName,
    required this.baseName,
    required this.enabled,
    required this.size,
    required this.modifiedMs,
    required this.meta,
  });

  factory InstalledMod.fromJson(Map<String, dynamic> json) => InstalledMod(
    fileName: json['file_name'] as String? ?? '',
    baseName: json['base_name'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    size: _int(json['size']),
    modifiedMs: _int(json['modified_ms']),
    meta: json['meta'] is Map
        ? ModMeta.fromJson((json['meta'] as Map).cast<String, dynamic>())
        : null,
  );

  /// 实际文件名（禁用过的带 `.disabled`）。**当主键用** —— 同一目录里不会重名。
  final String fileName;

  /// 显示用名字（去掉了 `.disabled`）。
  final String baseName;

  final bool enabled;
  final int size;
  final int modifiedMs;
  final ModMeta? meta;

  /// 列表主行的标题：元数据里的名字 → 否则去掉 `.disabled` 的文件名。
  String get displayName {
    final name = meta?.displayName;
    if (name != null && name.isNotEmpty) return name;
    return baseName;
  }

  /// 列表副行：
  ///
  /// * 有元数据：`版本号 · 加载器标签`，有描述再换一行接上；
  /// * 没有元数据：文件大小（`1.5 MB` 这种）。
  String? get subtitle {
    final meta = this.meta;
    if (meta != null) {
      final parts = <String>[
        if (meta.version != null && meta.version!.isNotEmpty) meta.version!,
        if (meta.loaderLabel.isNotEmpty) meta.loaderLabel,
      ];
      final description = meta.description;
      if (parts.isNotEmpty) {
        return parts.join(' · ') +
            (description != null && description.isNotEmpty
                ? '\n$description'
                : '');
      }
      if (description != null && description.isNotEmpty) return description;
      return null;
    }
    return formatModSize(size);
  }
}

/// 列表副行的口径：`512 B` / `1.5 KB` / `12.3 MB`。
///
/// 与 `lib/download/format.dart` 的 `formatBytes` **刻意分开** —— 那个给下载进度
/// 用（会带单位与更多档位），这个只用于列表副行。
String formatModSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 一个目录（`mods/` 或 `plugins/`）的已装清单。
class ModDir {
  const ModDir({
    required this.projectType,
    required this.dir,
    required this.exists,
    required this.count,
    required this.files,
  });

  factory ModDir.fromJson(Map<String, dynamic> json) => ModDir(
    projectType: json['project_type'] as String? ?? '',
    dir: json['dir'] as String? ?? '',
    exists: json['exists'] as bool? ?? false,
    count: _int(json['count']),
    files: _objects(json['files'], InstalledMod.fromJson),
  );

  final String projectType;
  final String dir;

  /// 目录在实例里存在吗。**不存在时不显示这个标签**，
  /// 下载完第一个模组时目录才会被建出来。
  final bool exists;

  final int count;
  final List<InstalledMod> files;
}

/// `mods.installed` 的结果。
class InstalledMods {
  const InstalledMods({
    required this.instanceId,
    required this.pmmp,
    required this.dirs,
  });

  factory InstalledMods.fromJson(Map<String, dynamic> json) => InstalledMods(
    instanceId: json['instance_id'] as String? ?? '',
    pmmp: json['pmmp'] as bool? ?? false,
    dirs: _objects(json['dirs'], ModDir.fromJson),
  );

  final String instanceId;

  /// 这个实例是不是 PocketMine 系（`.phar` 服务端）。
  ///
  /// **判断在 daemon**。界面据此决定插件那一栏认 `.jar` 还是 `.phar`、
  /// 以及「插件下载」那个标签是不是换成「Poggit 插件」。
  final bool pmmp;

  final List<ModDir> dirs;

  static const empty = InstalledMods(instanceId: '', pmmp: false, dirs: []);

  ModDir? dir(String projectType) =>
      dirs.where((item) => item.projectType == projectType).firstOrNull;

  /// 两个目录加起来一共装了多少个。
  int get total => dirs.fold(0, (sum, dir) => sum + dir.count);
}

/// 一个已装文件的更新检查结果。
class ModUpdate {
  const ModUpdate({
    required this.fileName,
    required this.known,
    required this.hasUpdate,
    required this.latest,
  });

  factory ModUpdate.fromJson(Map<String, dynamic> json) => ModUpdate(
    fileName: json['file_name'] as String? ?? '',
    known: json['known'] as bool? ?? false,
    hasUpdate: json['has_update'] as bool? ?? false,
    latest: json['latest'] is Map
        ? ModVersion.fromJson((json['latest'] as Map).cast<String, dynamic>())
        : null,
  );

  final String fileName;

  /// 上游认不认识这个文件。`false` = 不是从上游装的（手放的、或项目被删了）。
  final bool known;

  final bool hasUpdate;
  final ModVersion? latest;
}

/// `mods.check_updates` 的结果。
class ModUpdateReport {
  const ModUpdateReport({
    required this.checked,
    required this.truncated,
    required this.updates,
  });

  factory ModUpdateReport.fromJson(Map<String, dynamic> json) =>
      ModUpdateReport(
        checked: _int(json['checked']),
        truncated: json['truncated'] as bool? ?? false,
        updates: _objects(json['updates'], ModUpdate.fromJson),
      );

  final int checked;

  /// 文件太多，只查了前面一部分 —— 界面要如实说。
  final bool truncated;

  final List<ModUpdate> updates;

  int get updateCount => updates.where((item) => item.hasUpdate).length;

  /// 按文件名索引，供列表逐行取「有没有更新」。
  Map<String, ModUpdate> get byFileName => {
    for (final update in updates) update.fileName: update,
  };

  static const empty = ModUpdateReport(
    checked: 0,
    truncated: false,
    updates: [],
  );
}

// ---------------------------------------------------------------------------
// 解析小工具
// ---------------------------------------------------------------------------

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (item is String) item,
];

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

List<T> _objects<T>(Object? raw, T Function(Map<String, dynamic>) parse) => [
  if (raw is List)
    for (final item in raw)
      if (item is Map) parse(item.cast<String, dynamic>()),
];

// ---------------------------------------------------------------------------
// 按 SHA1 对回上游项目（配图标用）
// ---------------------------------------------------------------------------

/// 上游项目的一句摘要。
class ModProjectRef {
  const ModProjectRef({
    required this.projectId,
    required this.slug,
    required this.title,
    required this.iconUrl,
    required this.projectType,
    required this.pageUrl,
  });

  factory ModProjectRef.fromJson(Map<String, dynamic> json) => ModProjectRef(
    projectId: json['project_id'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
    title: json['title'] as String? ?? '',
    iconUrl: json['icon_url'] as String?,
    projectType: json['project_type'] as String? ?? '',
    pageUrl: json['page_url'] as String? ?? '',
  );

  final String projectId;
  final String slug;
  final String title;
  final String? iconUrl;
  final String projectType;
  final String pageUrl;
}

/// 一个已装文件对回了哪个上游项目。
class ModMatch {
  const ModMatch({
    required this.fileName,
    required this.known,
    required this.project,
  });

  factory ModMatch.fromJson(Map<String, dynamic> json) => ModMatch(
    fileName: json['file_name'] as String? ?? '',
    known: json['known'] as bool? ?? false,
    project: json['project'] is Map
        ? ModProjectRef.fromJson(
            (json['project'] as Map).cast<String, dynamic>(),
          )
        : null,
  );

  /// 已装文件名（与 `mods.installed` 的键一致）。
  final String fileName;

  /// 上游认不认识这个文件。
  final bool known;

  final ModProjectRef? project;

  /// 列表左侧那个 40×40 的图标 URL（拿不到就退回按加载器上色的方块）。
  String? get iconUrl => project?.iconUrl;
}

/// `mods.match_projects` 的结果。
class ModMatchReport {
  const ModMatchReport({required this.matches});

  factory ModMatchReport.fromJson(Map<String, dynamic> json) =>
      ModMatchReport(matches: _objects(json['matches'], ModMatch.fromJson));

  final List<ModMatch> matches;

  /// 按文件名索引 —— 列表逐行取图标就靠它。
  Map<String, ModMatch> get byFileName => {
    for (final match in matches) match.fileName: match,
  };

  static const empty = ModMatchReport(matches: []);
}
