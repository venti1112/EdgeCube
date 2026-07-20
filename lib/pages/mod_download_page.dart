import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../mods/download_queue.dart';
import '../mods/icon_cache.dart';
import '../mods/modrinth_service.dart';
import '../mods/sources/mod_source.dart';
import '../mods/sources/mod_source_registry.dart';
import '../net/download_format.dart';
import '../net/mod_mirror.dart';

/// 模组/插件下载页：跨平台搜索并下载到指定目录。
///
/// 支持多平台切换（Modrinth / CurseForge / Hangar / SpigotMC，经 [ModSourceRegistry]）、
/// 搜索、浏览、筛选（游戏版本 / 加载器）和排序，分页加载（offset + limit）。
/// UI 只依赖中立模型（[ModSearchHit] / [ModVersionInfo]），与具体平台解耦。
class ModDownloadPage extends StatefulWidget {
  const ModDownloadPage({
    super.key,
    required this.modsFolder,
    this.embedded = false,
    this.projectType = 'mod',
    this.titleKey = 'modsPlugins.downloadMod',
  });

  final Directory modsFolder;
  final bool embedded;

  /// 'mod' 或 'plugin'，决定可用平台列表与可选加载器列表。
  final String projectType;

  /// AppBar 标题的 i18n 键。
  final String titleKey;

  @override
  State<ModDownloadPage> createState() => _ModDownloadPageState();
}

class _ModDownloadPageState extends State<ModDownloadPage> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  // 平台
  List<ModSource> _sources = [];
  ModSource? _source;
  bool _initializingSources = true;

  /// 是否有平台因不可用（如 CF 无 Key 且未开镜像）被过滤掉，用于提示引导。
  bool _hasHiddenSource = false;

  List<ModSearchHit> _results = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _totalHits = 0;

  // 筛选
  List<ModrinthGameVersion> _gameVersions = [];
  String? _selectedGameVersion;
  String? _selectedLoader;
  ModSortType _sort = ModSortType.relevance;

  /// 当前平台可选加载器列表（随平台变化）。
  List<String> get _loaders =>
      _source?.supportedLoaders(widget.projectType) ?? const [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _initSources();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 初始化可用平台列表（按 isAvailable 过滤，如 CF 无 Key 且未开镜像则剔除）。
  Future<void> _initSources() async {
    final all = ModSourceRegistry.sourcesFor(widget.projectType);
    final sources = await ModSourceRegistry.availableSources(widget.projectType);
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _source = sources.isEmpty ? null : sources.first;
      _hasHiddenSource = sources.length < all.length;
      _initializingSources = false;
    });
    if (_source != null) {
      _loadGameVersions();
      _search();
    }
  }

  /// 切换平台：重置筛选与结果并重新搜索。
  void _switchSource(ModSource source) {
    if (source.type == _source?.type) return;
    setState(() {
      _source = source;
      // 加载器随平台变化，清掉不适用的选择。
      if (_selectedLoader != null &&
          !source.supportedLoaders(widget.projectType).contains(_selectedLoader)) {
        _selectedLoader = null;
      }
      if (!source.supportsGameVersionFilter) _selectedGameVersion = null;
    });
    _search();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadGameVersions() async {
    if (_gameVersions.isNotEmpty) return;
    try {
      final versions = await ModrinthService.getGameVersions();
      if (!mounted) return;
      setState(() => _gameVersions = versions);
    } catch (_) {
      // 忽略，筛选器不可用不影响搜索
    }
  }

  Future<void> _search() async {
    final source = _source;
    if (source == null) return;
    final query = _controller.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _totalHits = 0;
    });
    try {
      final result = await source.search(
        query,
        offset: 0,
        gameVersion: _selectedGameVersion,
        loader: _selectedLoader,
        sort: query.isEmpty ? ModSortType.downloads : _sort,
        projectType: widget.projectType,
      );
      if (!mounted || source.type != _source?.type) return;
      setState(() {
        _results = result.hits;
        _totalHits = result.totalHits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || source.type != _source?.type) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final source = _source;
    if (source == null) return;
    if (_loadingMore || _loading || _error != null) return;
    if (_results.length >= _totalHits) return;
    setState(() => _loadingMore = true);
    try {
      final query = _controller.text.trim();
      final result = await source.search(
        query,
        offset: _results.length,
        gameVersion: _selectedGameVersion,
        loader: _selectedLoader,
        sort: query.isEmpty ? ModSortType.downloads : _sort,
        projectType: widget.projectType,
      );
      if (!mounted || source.type != _source?.type) return;
      setState(() {
        _results.addAll(result.hits);
        _totalHits = result.totalHits;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openVersions(ModSearchHit hit) {
    _showVersionSheet(
      projectId: hit.projectId,
      title: hit.title,
      iconUrl: hit.iconUrl,
    );
  }

  void _showVersionSheet({
    required String projectId,
    required String title,
    String? iconUrl,
  }) {
    final source = _source;
    if (source == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _VersionSheet(
        source: source,
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
        modsFolder: widget.modsFolder,
        projectType: widget.projectType,
        filterGameVersion: _selectedGameVersion,
        filterLoader: _selectedLoader,
        onDownloaded: () {
          Navigator.of(context).pop(true);
        },
      ),
    ).then((downloaded) {
      // sheet 关闭后，用父页面稳定的 context 显示 SnackBar，
      // 避免 sheet 的 context 失效导致 SnackBar 永不消失或"查看队列"按钮无效。
      if (downloaded == true && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr('modsPlugins.downloadQueued')),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: context.tr('modsPlugins.viewQueue'),
                onPressed: () => showDownloadQueueSheet(context),
              ),
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(context.tr(widget.titleKey))),
      body: Column(
        children: [
          if (_sources.length > 1) _buildSourceBar(theme),
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          const DownloadQueueBanner(),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  /// 平台切换条（仅当可用平台 > 1 时显示）。
  Widget _buildSourceBar(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        children: [
          for (final s in _sources)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(s.displayName),
                selected: s.type == _source?.type,
                onSelected: (_) => _switchSource(s),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: context.tr('modsPlugins.searchHint'),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _search();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _loading ? null : _search,
            child: Text(context.tr('modsPlugins.search')),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _filterChip(
            theme,
            label: context.tr('modsPlugins.sortLabel'),
            value: context.tr('modsPlugins.sort.${_sort.name}'),
            icon: Icons.sort,
            onTap: () => _showSortPicker(theme),
          ),
          if (_loaders.isNotEmpty)
            _filterChip(
              theme,
              label: context.tr('modsPlugins.loader'),
              value: _selectedLoader ?? context.tr('modsPlugins.any'),
              icon: Icons.extension_outlined,
              onTap: () => _showLoaderPicker(theme),
            ),
          if (_source?.supportsGameVersionFilter ?? true)
            _filterChip(
              theme,
              label: context.tr('modsPlugins.gameVersion'),
              value: _selectedGameVersion ?? context.tr('modsPlugins.any'),
              icon: Icons.verified_outlined,
              onTap: () => _showVersionPicker(theme),
            ),
          if (_selectedLoader != null || _selectedGameVersion != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: ActionChip(
                label: Text(context.tr('modsPlugins.clearFilter')),
                avatar: const Icon(Icons.clear_all, size: 16),
                onPressed: () {
                  setState(() {
                    _selectedLoader = null;
                    _selectedGameVersion = null;
                  });
                  _search();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text('$label: $value'),
        onPressed: onTap,
      ),
    );
  }

  void _showSortPicker(ThemeData theme) {
    final options = ModSortType.values;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('modsPlugins.sortLabel')),
        children: options
            .map(
              (s) => SimpleDialogOption(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _sort = s);
                  _search();
                },
                child: Row(
                  children: [
                    if (_sort == s)
                      Icon(Icons.check, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 8),
                    Text(context.tr('modsPlugins.sort.${s.name}')),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showLoaderPicker(ThemeData theme) {
    final items = <String?>[null, ..._loaders];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('modsPlugins.loader')),
        children: items
            .map(
              (l) => SimpleDialogOption(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedLoader = l);
                  _search();
                },
                child: Row(
                  children: [
                    if (_selectedLoader == l)
                      Icon(Icons.check, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 8),
                    Text(
                      l == null
                          ? context.tr('modsPlugins.any')
                          : _capitalize(l),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showVersionPicker(ThemeData theme) {
    final releases = _gameVersions
        .where((v) => v.versionType == 'release')
        .toList();
    final others = _gameVersions
        .where((v) => v.versionType != 'release')
        .toList();
    final items = <ModrinthGameVersion?>[null, ...releases, ...others];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('modsPlugins.gameVersion')),
        children: items
            .map(
              (v) => SimpleDialogOption(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedGameVersion = v?.version);
                  _search();
                },
                child: Row(
                  children: [
                    if (_selectedGameVersion == v?.version)
                      Icon(Icons.check, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 8),
                    Text(v == null ? context.tr('modsPlugins.any') : v.version),
                    if (v != null && v.versionType != 'release')
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          v.versionType,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _buildBody(ThemeData theme) {
    if (_initializingSources) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_source == null) {
      // 没有任何可用平台（如仅登记 CF 但无 Key 且未开镜像）。
      return _centerMessage(
        theme,
        Icons.cloud_off_outlined,
        context.tr('modsPlugins.noAvailableSource'),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centerMessage(
        theme,
        Icons.error_outline,
        context.tr('modsPlugins.searchFailed', {'error': _error!}),
      );
    }
    if (_results.isEmpty) {
      return _centerMessage(
        theme,
        Icons.inbox_outlined,
        _hasHiddenSource
            ? context.tr('modsPlugins.noResultsSourceHidden')
            : context.tr('modsPlugins.noResults'),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _results.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _results.length) {
          // 底部加载指示器
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (_results.length >= _totalHits) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  context.tr('modsPlugins.noMore', {'count': '$_totalHits'}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return const SizedBox(height: 16);
        }
        final hit = _results[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: _ModIcon(url: hit.iconUrl),
            title: Text(
              hit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              hit.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.download_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatDownloads(hit.downloads),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                if (hit.categories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hit.categories.take(2).join(', '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _openVersions(hit),
          ),
        );
      },
    );
  }
}

/// 版本选择底部弹层。
class _VersionSheet extends StatefulWidget {
  const _VersionSheet({
    required this.source,
    required this.projectId,
    required this.title,
    required this.iconUrl,
    required this.modsFolder,
    required this.onDownloaded,
    this.projectType = 'mod',
    this.filterGameVersion,
    this.filterLoader,
  });

  final ModSource source;
  final String projectId;
  final String title;
  final String? iconUrl;
  final Directory modsFolder;
  final VoidCallback onDownloaded;
  final String projectType;
  final String? filterGameVersion;
  final String? filterLoader;

  @override
  State<_VersionSheet> createState() => _VersionSheetState();
}

class _VersionSheetState extends State<_VersionSheet> {
  List<ModVersionInfo> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    try {
      final versions = await widget.source.getVersions(
        widget.projectId,
        projectType: widget.projectType,
      );
      if (!mounted) return;
      setState(() {
        _versions = _applyFilters(versions);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 按当前筛选条件过滤版本（版本类型已由各平台源在 getVersions 内处理）。
  List<ModVersionInfo> _applyFilters(List<ModVersionInfo> versions) {
    var filtered = versions;
    if (widget.filterGameVersion != null) {
      filtered = filtered
          .where((v) => v.gameVersions.contains(widget.filterGameVersion))
          .toList();
    }
    if (widget.filterLoader != null) {
      filtered = filtered
          .where((v) => v.loaders.contains(widget.filterLoader))
          .toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = LocaleScope.of(context).translations;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        tr.get('modsPlugins.searchFailed', {'error': _error!}),
                      ),
                    )
                  : _versions.isEmpty
                  ? Center(child: Text(tr.get('modsPlugins.noResults')))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _versions.length,
                      itemBuilder: (ctx, i) {
                        final v = _versions[i];
                        final depCount = v.dependencies
                            .where((d) => d.projectId != null)
                            .length;
                        return ListTile(
                          title: Text(
                            v.name.isEmpty ? v.versionNumber : v.name,
                          ),
                          subtitle: Wrap(
                            spacing: 6,
                            children: [
                              if (v.gameVersions.isNotEmpty)
                                _chip(theme, v.gameVersions.take(3).join(', ')),
                              if (v.loaders.isNotEmpty)
                                _chip(theme, v.loaders.join(', ')),
                              _chip(
                                theme,
                                tr.get(
                                  'modsPlugins.releaseType.'
                                  '${v.versionType}',
                                ),
                              ),
                              if (v.primaryFile != null)
                                _chip(theme, _formatSize(v.primaryFile!.size)),
                              if (depCount > 0)
                                _chip(
                                  theme,
                                  tr.get('modsPlugins.dependencyCount', {
                                    'count': '$depCount',
                                  }),
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showVersionDetail(v),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showVersionDetail(ModVersionInfo version) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VersionDetailPage(
          source: widget.source,
          projectId: widget.projectId,
          title: widget.title,
          iconUrl: widget.iconUrl,
          version: version,
          modsFolder: widget.modsFolder,
          projectType: widget.projectType,
          onDownloaded: () => Navigator.of(context).pop(true),
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

/// 版本详情页：显示版本完整信息和依赖关系。
class _VersionDetailPage extends StatefulWidget {
  const _VersionDetailPage({
    required this.source,
    required this.projectId,
    required this.title,
    required this.iconUrl,
    required this.version,
    required this.modsFolder,
    required this.onDownloaded,
    this.projectType = 'mod',
  });

  final ModSource source;
  final String projectId;
  final String title;
  final String? iconUrl;
  final ModVersionInfo version;
  final Directory modsFolder;
  final VoidCallback onDownloaded;
  final String projectType;

  @override
  State<_VersionDetailPage> createState() => _VersionDetailPageState();
}

class _VersionDetailPageState extends State<_VersionDetailPage> {
  // 依赖项目 ID → 项目信息
  final Map<String, ModProjectInfo> _depProjects = {};
  bool _loadingDeps = true;

  @override
  void initState() {
    super.initState();
    _loadDependencies();
  }

  Future<void> _loadDependencies() async {
    final depIds = widget.version.dependencies
        .where((d) => d.projectId != null && d.projectId!.isNotEmpty)
        .map((d) => d.projectId!)
        .toSet()
        .toList();
    if (depIds.isEmpty) {
      setState(() => _loadingDeps = false);
      return;
    }
    try {
      final projects = await widget.source.getProjects(depIds);
      if (!mounted) return;
      setState(() {
        for (final p in projects) {
          _depProjects[p.id] = p;
        }
        _loadingDeps = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDeps = false);
    }
  }

  /// 加入下载队列。退出页面后下载仍会继续。
  ///
  /// 外链文件（如 SpigotMC 部分资源）无法直连下载，改为提示前往官网。
  /// 镜像开启时用镜像 URL（[ModMirror.downloadCandidates] 首选项）加速。
  Future<void> _enqueueDownload() async {
    final file = widget.version.primaryFile;
    if (file == null) return;

    if (!file.downloadable) {
      // 外链资源：提示前往官网下载。
      if (!mounted) return;
      await _showExternalDialog();
      return;
    }

    final url = file.url!;
    final candidates = await ModMirror.downloadCandidates(url);
    final destPath = p.join(widget.modsFolder.path, file.filename);
    DownloadQueue.instance.enqueue(
      url: candidates.first,
      destPath: destPath,
      filename: file.filename,
      projectTitle: widget.title,
      versionName: widget.version.name.isEmpty
          ? widget.version.versionNumber
          : widget.version.name,
      iconUrl: widget.iconUrl,
    );
    // 不在此处显示 SnackBar：此处 context 是 sheet 的 BuildContext，
    // sheet 关闭后会失效，导致 SnackBar 永不消失且"查看队列"按钮点击无效。
    // 改由父页面在 sheet 关闭后的 .then() 回调中用稳定的 context 显示。
    widget.onDownloaded();
  }

  Future<void> _showExternalDialog() async {
    final pageUrl = widget.version.primaryFile?.url;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('modsPlugins.externalTitle')),
        content: Text(
          ctx.tr('modsPlugins.externalMessage', {'url': pageUrl ?? '-'}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
  }

  String _dependencyLabel(ModVersionDependency dep) {
    if (dep.dependencyName != null && dep.dependencyName!.isNotEmpty) {
      return dep.dependencyName!;
    }
    final project = dep.projectId != null ? _depProjects[dep.projectId] : null;
    if (project != null) return project.title;
    return context.tr('modsPlugins.dependencyUnknown');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = LocaleScope.of(context).translations;
    final v = widget.version;
    final file = v.primaryFile;

    final requiredDeps = v.dependencies.where((d) => d.isRequired).toList();
    final optionalDeps = v.dependencies.where((d) => d.isOptional).toList();
    final incompatibleDeps = v.dependencies
        .where((d) => d.isIncompatible)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr.get('modsPlugins.versionDetail'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 模组标题
          Row(
            children: [
              _ModIcon(url: widget.iconUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      v.name.isEmpty ? v.versionNumber : v.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 基本信息卡
          _sectionCard(
            theme,
            tr.get('modsPlugins.versionName'),
            v.name.isEmpty ? v.versionNumber : v.name,
          ),
          _sectionCard(
            theme,
            tr.get('modsPlugins.versionNumber'),
            v.versionNumber,
          ),
          _sectionCard(
            theme,
            tr.get('modsPlugins.publishedAt'),
            tr.get('modsPlugins.publishedAt', {
              'date': _formatDate(v.datePublished),
            }),
          ),
          _sectionCard(
            theme,
            tr.get('modsPlugins.releaseType.${v.versionType}'),
            null,
            isChip: true,
          ),

          // 游戏版本
          if (v.gameVersions.isNotEmpty) ...[
            _sectionTitle(theme, tr.get('modsPlugins.gameVersions')),
            _chipWrap(theme, v.gameVersions),
            const SizedBox(height: 12),
          ],

          // 加载器
          if (v.loaders.isNotEmpty) ...[
            _sectionTitle(theme, tr.get('modsPlugins.loaders')),
            _chipWrap(theme, v.loaders),
            const SizedBox(height: 12),
          ],

          // 文件信息
          if (file != null) ...[
            _sectionTitle(theme, tr.get('modsPlugins.fileInfo')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(
                      theme,
                      tr.get('modsPlugins.fileName'),
                      file.filename,
                    ),
                    const SizedBox(height: 6),
                    _infoRow(
                      theme,
                      tr.get('modsPlugins.fileSize'),
                      _formatSize(file.size),
                    ),
                    if (file.sha1 != null) ...[
                      const SizedBox(height: 6),
                      _infoRow(
                        theme,
                        tr.get('modsPlugins.sha1'),
                        file.sha1!,
                        mono: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 依赖
          if (_loadingDeps)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (requiredDeps.isNotEmpty) ...[
              _sectionTitle(theme, tr.get('modsPlugins.dependencies')),
              Card(
                child: Column(
                  children: requiredDeps
                      .map((d) => _depTile(theme, d, required: true))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (optionalDeps.isNotEmpty) ...[
              _sectionTitle(theme, tr.get('modsPlugins.optionalDependencies')),
              Card(
                child: Column(
                  children: optionalDeps
                      .map((d) => _depTile(theme, d, required: false))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (incompatibleDeps.isNotEmpty) ...[
              _sectionTitle(theme, tr.get('modsPlugins.incompatible')),
              Card(
                child: Column(
                  children: incompatibleDeps
                      .map(
                        (d) => _depTile(
                          theme,
                          d,
                          required: false,
                          incompatible: true,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (requiredDeps.isEmpty &&
                optionalDeps.isEmpty &&
                incompatibleDeps.isEmpty)
              _sectionCard(
                theme,
                tr.get('modsPlugins.dependencies'),
                tr.get('modsPlugins.noDependencies'),
              ),
          ],

          const SizedBox(height: 24),

          // 下载按钮
          FilledButton.icon(
            onPressed: _enqueueDownload,
            icon: const Icon(Icons.download),
            label: Text(tr.get('modsPlugins.downloadVersion')),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme,
    String label,
    String? value, {
    bool isChip = false,
  }) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text(label, style: theme.textTheme.bodySmall),
        trailing: isChip
            ? Chip(
                label: Text(value ?? ''),
                visualDensity: VisualDensity.compact,
              )
            : value == null
            ? null
            : Text(value, style: theme.textTheme.bodyMedium),
      ),
    );
  }

  Widget _chipWrap(ThemeData theme, List<String> items) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(item, style: theme.textTheme.labelMedium),
            ),
          )
          .toList(),
    );
  }

  Widget _infoRow(
    ThemeData theme,
    String label,
    String value, {
    bool mono = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  )
                : theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _depTile(
    ThemeData theme,
    ModVersionDependency dep, {
    required bool required,
    bool incompatible = false,
  }) {
    final label = _dependencyLabel(dep);
    final canNavigate = dep.projectId != null && dep.projectId!.isNotEmpty;
    final project = canNavigate ? _depProjects[dep.projectId] : null;
    return ListTile(
      dense: true,
      leading: Icon(
        incompatible
            ? Icons.block
            : required
            ? Icons.priority_high
            : Icons.low_priority,
        size: 20,
        color: incompatible
            ? theme.colorScheme.error
            : required
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: dep.projectId != null
          ? Text(
              dep.projectId!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: canNavigate
          ? Icon(
              Icons.chevron_right,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : null,
      onTap: canNavigate
          ? () => _openDependency(
              projectId: dep.projectId!,
              title: label,
              iconUrl: project?.iconUrl,
            )
          : null,
    );
  }

  /// 打开依赖项目的版本选择弹层。
  void _openDependency({
    required String projectId,
    required String title,
    String? iconUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _VersionSheet(
        source: widget.source,
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
        modsFolder: widget.modsFolder,
        projectType: widget.projectType,
        onDownloaded: () {
          Navigator.of(context).pop(true);
        },
      ),
    ).then((downloaded) {
      // sheet 关闭后，用父页面稳定的 context 显示 SnackBar，
      // 避免 sheet 的 context 失效导致 SnackBar 永不消失或"查看队列"按钮无效。
      if (downloaded == true && mounted) {
        final tr = LocaleScope.of(context).translations;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(tr.get('modsPlugins.downloadQueued')),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: tr.get('modsPlugins.viewQueue'),
                onPressed: () => showDownloadQueueSheet(context),
              ),
            ),
          );
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

// ── 辅助组件 ──────────────────────────────────────────────────

class _ModIcon extends StatelessWidget {
  const _ModIcon({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return CachedModIcon(url: url, size: 40);
  }
}

Widget _chip(ThemeData theme, String label) {
  return Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: theme.textTheme.labelSmall),
  );
}

Widget _centerMessage(ThemeData theme, IconData icon, String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDownloads(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '${(count / 1000000).toStringAsFixed(1)}M';
}

/// 正在下载任务的「速度 · ~剩余时间」文本，如 `5.3 MB/s · ~16s`。
/// 剩余时间未知时仅显示速度。调用方需保证速度 > 0（否则速度段为空）。
String _formatRateEta(DownloadTask task) {
  final speed = formatSpeed(task.speedBytesPerSec);
  final eta = formatEta(task.etaMs);
  return eta.isEmpty ? speed : '$speed · $eta';
}

// ── 下载队列横幅 ──────────────────────────────────────────────

/// 下载队列状态横幅。监听全局 [DownloadQueue]，有任务时显示。
class DownloadQueueBanner extends StatefulWidget {
  const DownloadQueueBanner({super.key});

  @override
  State<DownloadQueueBanner> createState() => _DownloadQueueBannerState();
}

class _DownloadQueueBannerState extends State<DownloadQueueBanner> {
  @override
  void initState() {
    super.initState();
    DownloadQueue.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    DownloadQueue.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final queue = DownloadQueue.instance;
    // 没有任何任务时不显示
    if (queue.tasks.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final current = queue.current;
    final pending = queue.pendingCount;
    final completed = queue.completedCount;
    final failed = queue.failedCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => showDownloadQueueSheet(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (current != null)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: current.progress >= 0
                        ? TweenAnimationBuilder<double>(
                            tween: Tween(begin: current.progress, end: current.progress),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.linear,
                            builder: (context, value, _) =>
                                CircularProgressIndicator(value: value, strokeWidth: 2),
                          )
                        : const CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.download_done,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (current != null)
                        Text(
                          '${current.projectTitle} · '
                          '${current.progress >= 0 ? '${(current.progress * 100).toInt()}%' : '...'}'
                          '${current.speedBytesPerSec > 0 ? ' · ${formatSpeed(current.speedBytesPerSec)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Text(
                          context.tr('modsPlugins.queueEmpty'),
                          maxLines: 1,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (pending > 0 || completed > 0 || failed > 0)
                        Text(
                          [
                            if (pending > 0)
                              context.tr('modsPlugins.queuePending', {
                                'count': '$pending',
                              }),
                            if (completed > 0)
                              context.tr('modsPlugins.queueCompleted', {
                                'count': '$completed',
                              }),
                            if (failed > 0)
                              context.tr('modsPlugins.queueFailed', {
                                'count': '$failed',
                              }),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showDownloadQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => const _QueueSheet(),
  );
}

/// 下载队列详情弹层。
class _QueueSheet extends StatefulWidget {
  const _QueueSheet();

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  @override
  void initState() {
    super.initState();
    DownloadQueue.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    DownloadQueue.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = LocaleScope.of(context).translations;
    final queue = DownloadQueue.instance;
    final tasks = queue.tasks.reversed.toList(); // 最新的在上

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr.get('modsPlugins.downloadQueue'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (queue.hasActiveTasks)
                    TextButton(
                      onPressed: () => DownloadQueue.instance.cancelAll(),
                      child: Text(tr.get('modsPlugins.cancelAll')),
                    ),
                  if (queue.tasks.any(
                    (t) =>
                        t.status == DownloadTaskStatus.completed ||
                        t.status == DownloadTaskStatus.failed ||
                        t.status == DownloadTaskStatus.cancelled,
                  ))
                    TextButton(
                      onPressed: () => DownloadQueue.instance.removeFinished(),
                      child: Text(tr.get('modsPlugins.clearFinished')),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tasks.isEmpty
                  ? Center(child: Text(tr.get('modsPlugins.queueEmpty')))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: tasks.length,
                      itemBuilder: (ctx, i) {
                        final task = tasks[i];
                        return _QueueTile(task: task);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = LocaleScope.of(context).translations;

    IconData statusIcon;
    Color? statusColor;
    switch (task.status) {
      case DownloadTaskStatus.downloading:
        statusIcon = Icons.downloading;
        statusColor = theme.colorScheme.primary;
        break;
      case DownloadTaskStatus.pending:
        statusIcon = Icons.schedule;
        statusColor = theme.colorScheme.onSurfaceVariant;
        break;
      case DownloadTaskStatus.completed:
        statusIcon = Icons.check_circle;
        statusColor = theme.colorScheme.primary;
        break;
      case DownloadTaskStatus.failed:
        statusIcon = Icons.error_outline;
        statusColor = theme.colorScheme.error;
        break;
      case DownloadTaskStatus.cancelled:
        statusIcon = Icons.cancel;
        statusColor = theme.colorScheme.onSurfaceVariant;
        break;
    }

    return ListTile(
      leading: _ModIcon(url: task.iconUrl),
      title: Text(
        task.projectTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.versionName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (task.status == DownloadTaskStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: task.progress >= 0
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: task.progress, end: task.progress),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.linear,
                      builder: (context, value, _) =>
                          LinearProgressIndicator(value: value),
                    )
                  : const LinearProgressIndicator(),
            )
          else if (task.status == DownloadTaskStatus.failed &&
              task.error != null)
            Text(
              task.error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (task.status == DownloadTaskStatus.downloading &&
              task.progress >= 0 &&
              task.speedBytesPerSec > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatRateEta(task),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 20, color: statusColor),
          if (task.status == DownloadTaskStatus.downloading ||
              task.status == DownloadTaskStatus.pending)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: tr.get('common.cancel'),
              onPressed: () => DownloadQueue.instance.cancel(task.id),
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: tr.get('common.delete'),
              onPressed: () => DownloadQueue.instance.remove(task.id),
            ),
        ],
      ),
    );
  }
}
