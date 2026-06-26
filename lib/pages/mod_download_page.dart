import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../mods/download_queue.dart';
import '../mods/modrinth_service.dart';

/// 模组下载页：搜索 Modrinth 并下载模组到指定 mods 目录。
///
/// 支持搜索、浏览、筛选（游戏版本 / 加载器）和排序，
/// 参考 PCL-CE 的 PageComp 实现分页加载（offset + limit）。
class ModDownloadPage extends StatefulWidget {
  const ModDownloadPage({super.key, required this.modsFolder, this.embedded = false});

  final Directory modsFolder;
  final bool embedded;

  @override
  State<ModDownloadPage> createState() => _ModDownloadPageState();
}

class _ModDownloadPageState extends State<ModDownloadPage> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ModrinthSearchHit> _results = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _totalHits = 0;

  // 筛选
  List<ModrinthGameVersion> _gameVersions = [];
  String? _selectedGameVersion;
  String? _selectedLoader; // fabric, forge, quilt, neoforge
  ModrinthSort _sort = ModrinthSort.relevance;

  static const _loaders = ['fabric', 'forge', 'quilt', 'neoforge'];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadGameVersions();
    _search(); // 初始加载浏览列表
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadGameVersions() async {
    try {
      final versions = await ModrinthService.getGameVersions();
      if (!mounted) return;
      setState(() => _gameVersions = versions);
    } catch (_) {
      // 忽略，筛选器不可用不影响搜索
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _totalHits = 0;
    });
    try {
      final result = await ModrinthService.search(
        query,
        offset: 0,
        gameVersion: _selectedGameVersion,
        loader: _selectedLoader,
        sort: query.isEmpty ? ModrinthSort.downloads : _sort,
      );
      if (!mounted) return;
      setState(() {
        _results = result.hits;
        _totalHits = result.totalHits;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _error != null) return;
    if (_results.length >= _totalHits) return;
    setState(() => _loadingMore = true);
    try {
      final query = _controller.text.trim();
      final result = await ModrinthService.search(
        query,
        offset: _results.length,
        gameVersion: _selectedGameVersion,
        loader: _selectedLoader,
        sort: query.isEmpty ? ModrinthSort.downloads : _sort,
      );
      if (!mounted) return;
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

  void _openVersions(ModrinthSearchHit hit) {
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VersionSheet(
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
        modsFolder: widget.modsFolder,
        filterGameVersion: _selectedGameVersion,
        filterLoader: _selectedLoader,
        onDownloaded: () {
          Navigator.of(context).pop(true);
        },
      ),
    ).then((downloaded) {
      if (downloaded == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('modsPlugins.downloadSuccess'))),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(context.tr('modsPlugins.downloadMod'))),
      body: Column(
        children: [
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          const _DownloadQueueBanner(),
          Expanded(child: _buildBody(theme)),
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
          _filterChip(
            theme,
            label: context.tr('modsPlugins.loader'),
            value: _selectedLoader ?? context.tr('modsPlugins.any'),
            icon: Icons.extension_outlined,
            onTap: () => _showLoaderPicker(theme),
          ),
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
    final options = ModrinthSort.values;
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
                    Text(l == null
                        ? context.tr('modsPlugins.any')
                        : _capitalize(l)),
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
                    Text(v == null
                        ? context.tr('modsPlugins.any')
                        : v.version),
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
        context.tr('modsPlugins.noResults'),
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
                  context.tr('modsPlugins.noMore', {
                    'count': '$_totalHits',
                  }),
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
    required this.projectId,
    required this.title,
    required this.iconUrl,
    required this.modsFolder,
    required this.onDownloaded,
    this.filterGameVersion,
    this.filterLoader,
  });

  final String projectId;
  final String title;
  final String? iconUrl;
  final Directory modsFolder;
  final VoidCallback onDownloaded;
  final String? filterGameVersion;
  final String? filterLoader;

  @override
  State<_VersionSheet> createState() => _VersionSheetState();
}

class _VersionSheetState extends State<_VersionSheet> {
  List<ModrinthVersion> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    try {
      final versions = await ModrinthService.getVersions(
        widget.projectId,
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

  List<ModrinthVersion> _applyFilters(List<ModrinthVersion> versions) {
    var filtered = versions;
    if (widget.filterGameVersion != null) {
      filtered = filtered.where((v) =>
          v.gameVersions.contains(widget.filterGameVersion)).toList();
    }
    if (widget.filterLoader != null) {
      filtered = filtered.where((v) =>
          v.loaders.contains(widget.filterLoader)).toList();
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
                            tr.get('modsPlugins.searchFailed',
                                {'error': _error!}),
                          ),
                        )
                      : _versions.isEmpty
                          ? Center(
                              child: Text(tr.get('modsPlugins.noResults')),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: _versions.length,
                              itemBuilder: (ctx, i) {
                                final v = _versions[i];
                                final depCount = v.dependencies
                                    .where((d) => d.projectId != null)
                                    .length;
                                return ListTile(
                                  title: Text(v.name.isEmpty
                                      ? v.versionNumber
                                      : v.name),
                                  subtitle: Wrap(
                                    spacing: 6,
                                    children: [
                                      if (v.gameVersions.isNotEmpty)
                                        _chip(
                                          theme,
                                          v.gameVersions.take(3).join(', '),
                                        ),
                                      if (v.loaders.isNotEmpty)
                                        _chip(
                                          theme,
                                          v.loaders.join(', '),
                                        ),
                                      _chip(
                                        theme,
                                        tr.get('modsPlugins.releaseType.'
                                            '${v.versionType}'),
                                      ),
                                      if (v.primaryFile != null)
                                        _chip(
                                          theme,
                                          _formatSize(v.primaryFile!.size),
                                        ),
                                      if (depCount > 0)
                                        _chip(
                                          theme,
                                          tr.get('modsPlugins.dependencyCount',
                                              {'count': '$depCount'}),
                                        ),
                                    ],
                                  ),
                                  trailing:
                                      const Icon(Icons.chevron_right),
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

  void _showVersionDetail(ModrinthVersion version) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VersionDetailPage(
          projectId: widget.projectId,
          title: widget.title,
          iconUrl: widget.iconUrl,
          version: version,
          modsFolder: widget.modsFolder,
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
    required this.projectId,
    required this.title,
    required this.iconUrl,
    required this.version,
    required this.modsFolder,
    required this.onDownloaded,
  });

  final String projectId;
  final String title;
  final String? iconUrl;
  final ModrinthVersion version;
  final Directory modsFolder;
  final VoidCallback onDownloaded;

  @override
  State<_VersionDetailPage> createState() => _VersionDetailPageState();
}

class _VersionDetailPageState extends State<_VersionDetailPage> {
  // 依赖项目 ID → 项目信息
  final Map<String, ModrinthProject> _depProjects = {};
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
      final projects = await ModrinthService.getProjects(depIds);
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
  void _enqueueDownload() {
    final file = widget.version.primaryFile;
    if (file == null) return;
    final destPath = p.join(widget.modsFolder.path, file.filename);
    DownloadQueue.instance.enqueue(
      url: file.url,
      destPath: destPath,
      filename: file.filename,
      projectTitle: widget.title,
      versionName: widget.version.name.isEmpty
          ? widget.version.versionNumber
          : widget.version.name,
      iconUrl: widget.iconUrl,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.tr('modsPlugins.downloadQueued')),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: context.tr('modsPlugins.viewQueue'),
            onPressed: () => _showQueueSheet(context),
          ),
        ),
      );
  }

  String _dependencyLabel(ModrinthDependency dep) {
    if (dep.dependencyName != null && dep.dependencyName!.isNotEmpty) {
      return dep.dependencyName!;
    }
    final project = dep.projectId != null ? _depProjects[dep.projectId] : null;
    if (project != null) return project.title;
    if (dep.fileName != null) return dep.fileName!;
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
    final incompatibleDeps =
        v.dependencies.where((d) => d.isIncompatible).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.get('modsPlugins.versionDetail')),
      ),
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
          _sectionCard(theme, tr.get('modsPlugins.versionName'),
              v.name.isEmpty ? v.versionNumber : v.name),
          _sectionCard(theme, tr.get('modsPlugins.versionNumber'),
              v.versionNumber),
          _sectionCard(
              theme,
              tr.get('modsPlugins.publishedAt'),
              tr.get('modsPlugins.publishedAt',
                  {'date': _formatDate(v.datePublished)})),
          _sectionCard(
              theme,
              tr.get('modsPlugins.releaseType.${v.versionType}'),
              null,
              isChip: true),

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
                    _infoRow(theme, tr.get('modsPlugins.fileName'),
                        file.filename),
                    const SizedBox(height: 6),
                    _infoRow(
                        theme, tr.get('modsPlugins.fileSize'), _formatSize(file.size)),
                    if (file.sha1 != null) ...[
                      const SizedBox(height: 6),
                      _infoRow(theme, tr.get('modsPlugins.sha1'),
                          file.sha1!,
                          mono: true),
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
                      .map((d) => _depTile(theme, d, required: false,
                          incompatible: true))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (requiredDeps.isEmpty &&
                optionalDeps.isEmpty &&
                incompatibleDeps.isEmpty)
              _sectionCard(theme, tr.get('modsPlugins.dependencies'),
                  tr.get('modsPlugins.noDependencies')),
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

  Widget _sectionCard(ThemeData theme, String label, String? value,
      {bool isChip = false}) {
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
          .map((item) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(item, style: theme.textTheme.labelMedium),
              ))
          .toList(),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value,
      {bool mono = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace', fontSize: 11)
                : theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _depTile(
    ThemeData theme,
    ModrinthDependency dep, {
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
          ? Text(dep.projectId!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ))
          : null,
      trailing: canNavigate
          ? Icon(Icons.chevron_right, size: 20,
              color: theme.colorScheme.onSurfaceVariant)
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
      builder: (_) => _VersionSheet(
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
        modsFolder: widget.modsFolder,
        onDownloaded: () {
          Navigator.of(context).pop(true);
        },
      ),
    ).then((downloaded) {
      if (downloaded == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LocaleScope.of(context)
                  .translations
                  .get('modsPlugins.downloadSuccess'),
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
    if (url == null || url!.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.extension, size: 24),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 40,
          height: 40,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.extension, size: 24),
        ),
      ),
    );
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
    child: Text(
      label,
      style: theme.textTheme.labelSmall,
    ),
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

// ── 下载队列横幅 ──────────────────────────────────────────────

/// 下载队列状态横幅。监听全局 [DownloadQueue]，有任务时显示。
class _DownloadQueueBanner extends StatefulWidget {
  const _DownloadQueueBanner();

  @override
  State<_DownloadQueueBanner> createState() => _DownloadQueueBannerState();
}

class _DownloadQueueBannerState extends State<_DownloadQueueBanner> {
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

    return Material(
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        onTap: () => _showQueueSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (current != null)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: current.progress >= 0 ? current.progress : null,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(Icons.download_done,
                    size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (current != null)
                      Text(
                        '${current.projectTitle} · '
                        '${current.progress >= 0 ? '${(current.progress * 100).toInt()}%' : '...'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        context.tr('modsPlugins.queueEmpty'),
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (pending > 0 || completed > 0 || failed > 0)
                      Text(
                        [
                          if (pending > 0)
                            context.tr('modsPlugins.queuePending',
                                {'count': '$pending'}),
                          if (completed > 0)
                            context.tr('modsPlugins.queueCompleted',
                                {'count': '$completed'}),
                          if (failed > 0)
                            context.tr('modsPlugins.queueFailed',
                                {'count': '$failed'}),
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
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

void _showQueueSheet(BuildContext context) {
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
                  if (queue.tasks.any((t) =>
                      t.status == DownloadTaskStatus.completed ||
                      t.status == DownloadTaskStatus.failed ||
                      t.status == DownloadTaskStatus.cancelled))
                    TextButton(
                      onPressed: () =>
                          DownloadQueue.instance.removeFinished(),
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
                  ? Center(
                      child: Text(tr.get('modsPlugins.queueEmpty')),
                    )
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
              child: LinearProgressIndicator(
                value: task.progress >= 0 ? task.progress : null,
              ),
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
