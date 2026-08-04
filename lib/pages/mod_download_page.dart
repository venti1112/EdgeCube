import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../mods/download_queue.dart';
import '../mods/icon_cache.dart';
import '../mods/modrinth_service.dart';
import '../mods/sources/mod_source.dart';
import '../mods/sources/mod_source_registry.dart';
import '../net/download_format.dart';
import '../net/mod_mirror.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/ec_preference.dart';

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
    final sources = await ModSourceRegistry.availableSources(
      widget.projectType,
    );
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
          !source
              .supportedLoaders(widget.projectType)
              .contains(_selectedLoader)) {
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
        showMiuixSnackbar(context.tr('modsPlugins.downloadQueued'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      // 内嵌在「模组与插件」标签页中时不显示自己的顶栏。
      topBar: widget.embedded
          ? null
          : MiuixSmallTopAppBar(
              title: context.tr(widget.titleKey),
              navigationIcon: const EcBackButton(),
            ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            if (_sources.length > 1) _buildSourceBar(theme),
            _buildSearchBar(theme),
            _buildFilterBar(theme),
            const DownloadQueueBanner(),
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  /// 平台切换条（仅当可用平台 > 1 时显示）。
  Widget _buildSourceBar(MiuixThemeData theme) {
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

  Widget _buildSearchBar(MiuixThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: EcTextField(
              controller: _controller,
              hint: context.tr('modsPlugins.searchHint'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? MiuixIconButton(
                      onPressed: () {
                        _controller.clear();
                        _search();
                      },
                      child: MiuixIcon(icon: Icons.clear, size: 18),
                    )
                  : null,
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          MiuixButton(
            onPressed: _loading ? null : _search,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: MiuixText(context.tr('modsPlugins.search')),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(MiuixThemeData theme) {
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
    MiuixThemeData theme, {
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

  Future<void> _showSortPicker(MiuixThemeData theme) async {
    final selected = await showMiuixSingleChoice<ModSortType>(
      context: context,
      title: context.tr('modsPlugins.sortLabel'),
      options: ModSortType.values,
      selected: _sort,
      labelOf: (ctx, s) => ctx.tr('modsPlugins.sort.${s.name}'),
    );
    if (selected == null || !mounted) return;
    setState(() => _sort = selected);
    _search();
  }

  Future<void> _showLoaderPicker(MiuixThemeData theme) async {
    final items = <String?>[null, ..._loaders];
    // 按**下标**而非值选择：首项「任意」的值就是 null，而取消时
    // showMiuixSingleChoice 同样返回 null，用值无法区分二者。
    final picked = await showMiuixSingleChoice<int>(
      context: context,
      title: context.tr('modsPlugins.loader'),
      options: List.generate(items.length, (i) => i),
      selected: items.indexOf(_selectedLoader),
      labelOf: (ctx, i) =>
          items[i] == null ? ctx.tr('modsPlugins.any') : _capitalize(items[i]!),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedLoader = items[picked]);
    _search();
  }

  Future<void> _showVersionPicker(MiuixThemeData theme) async {
    final releases = _gameVersions
        .where((v) => v.versionType == 'release')
        .toList();
    final others = _gameVersions
        .where((v) => v.versionType != 'release')
        .toList();
    final items = <ModrinthGameVersion?>[null, ...releases, ...others];
    final picked = await showMiuixSingleChoice<int>(
      context: context,
      title: context.tr('modsPlugins.gameVersion'),
      options: List.generate(items.length, (i) => i),
      selected: items.indexWhere((v) => v?.version == _selectedGameVersion),
      labelOf: (ctx, i) =>
          items[i] == null ? ctx.tr('modsPlugins.any') : items[i]!.version,
      summaryOf: (ctx, i) {
        final v = items[i];
        return (v != null && v.versionType != 'release') ? v.versionType : '';
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedGameVersion = items[picked]?.version);
    _search();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _buildBody(MiuixThemeData theme) {
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
                  child: MiuixInfiniteProgressIndicator(size: 20),
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
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            );
          }
          return const SizedBox(height: 16);
        }
        final hit = _results[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: MiuixCard(
            child: MiuixBasicComponent(
              startAction: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _ModIcon(url: hit.iconUrl),
              ),
              content: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      hit.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.footnote1,
                    ),
                  ],
                ),
              ],
              endActions: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_outlined,
                          size: 14,
                          color: theme.colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _formatDownloads(hit.downloads),
                          style: theme.textStyles.footnote1,
                        ),
                      ],
                    ),
                    if (hit.categories.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          hit.categories.take(2).join(', '),
                          style: theme.textStyles.footnote2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              onClick: () => _openVersions(hit),
            ),
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
    final theme = MiuixTheme.of(context);
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
                      style: theme.textStyles.title4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  MiuixIconButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: MiuixIcon(icon: Icons.close),
                  ),
                ],
              ),
            ),
            const MiuixHorizontalDivider(),
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
                        return MiuixBasicComponent(
                          content: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(v.name.isEmpty ? v.versionNumber : v.name),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    if (v.gameVersions.isNotEmpty)
                                      _chip(
                                        theme,
                                        v.gameVersions.take(3).join(', '),
                                      ),
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
                                      _chip(
                                        theme,
                                        _formatSize(v.primaryFile!.size),
                                      ),
                                    if (depCount > 0)
                                      _chip(
                                        theme,
                                        tr.get('modsPlugins.dependencyCount', {
                                          'count': '$depCount',
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                          endActions: [const Icon(Icons.chevron_right)],
                          onClick: () => _showVersionDetail(v),
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
    await showMiuixDialog<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: MiuixText(
              ctx.tr('modsPlugins.externalTitle'),
              textAlign: TextAlign.center,
              style: MiuixTheme.of(context).textStyles.title4,
            ),
          ),
          const SizedBox(height: 12),
          Text(ctx.tr('modsPlugins.externalMessage', {'url': pageUrl ?? '-'})),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                ctx.tr('common.ok'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
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
    final theme = MiuixTheme.of(context);
    final tr = LocaleScope.of(context).translations;
    final v = widget.version;
    final file = v.primaryFile;

    final requiredDeps = v.dependencies.where((d) => d.isRequired).toList();
    final optionalDeps = v.dependencies.where((d) => d.isOptional).toList();
    final incompatibleDeps = v.dependencies
        .where((d) => d.isIncompatible)
        .toList();

    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: tr.get('modsPlugins.versionDetail'),
        navigationIcon: const EcBackButton(),
      ),
      content: (padding) => ListView(
        padding: padding + const EdgeInsets.all(16),
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
                      style: theme.textStyles.title4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      v.name.isEmpty ? v.versionNumber : v.name,
                      style: theme.textStyles.body2.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
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
            MiuixCard(
              insideMargin: const EdgeInsets.all(12),
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
                  child: MiuixInfiniteProgressIndicator(size: 20),
                ),
              ),
            )
          else ...[
            if (requiredDeps.isNotEmpty) ...[
              _sectionTitle(theme, tr.get('modsPlugins.dependencies')),
              MiuixCard(
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
              MiuixCard(
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
              MiuixCard(
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
          MiuixButton(
            onPressed: _enqueueDownload,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixIcon(icon: Icons.download),
                const SizedBox(width: 8),
                MiuixText(tr.get('modsPlugins.downloadVersion')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(MiuixThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        title,
        style: theme.textStyles.subtitle.copyWith(color: theme.colors.primary),
      ),
    );
  }

  Widget _sectionCard(
    MiuixThemeData theme,
    String label,
    String? value, {
    bool isChip = false,
  }) {
    return MiuixCard(
      child: MiuixBasicComponent(
        content: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [Text(label, style: theme.textStyles.footnote1)],
          ),
        ],
        endActions: [
          // 原本作为可空参数（trailing）传入，放进非空列表需用空感知元素。
          ?(isChip
              ? EcStatusChip(value ?? '')
              : value == null
              ? null
              : MiuixText(value, style: theme.textStyles.body2)),
        ],
      ),
    );
  }

  Widget _chipWrap(MiuixThemeData theme, List<String> items) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(item, style: theme.textStyles.footnote1),
            ),
          )
          .toList(),
    );
  }

  Widget _infoRow(
    MiuixThemeData theme,
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
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? theme.textStyles.footnote1.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  )
                : theme.textStyles.footnote1,
          ),
        ),
      ],
    );
  }

  Widget _depTile(
    MiuixThemeData theme,
    ModVersionDependency dep, {
    required bool required,
    bool incompatible = false,
  }) {
    final label = _dependencyLabel(dep);
    final canNavigate = dep.projectId != null && dep.projectId!.isNotEmpty;
    final project = canNavigate ? _depProjects[dep.projectId] : null;
    return MiuixBasicComponent(
      startAction: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          incompatible
              ? Icons.block
              : required
              ? Icons.priority_high
              : Icons.low_priority,
          size: 20,
          color: incompatible
              ? theme.colors.error
              : required
              ? theme.colors.primary
              : theme.colors.onSurfaceVariantSummary,
        ),
      ),
      content: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ?dep.projectId != null
                ? Text(
                    dep.projectId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote2.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  )
                : null,
          ],
        ),
      ],
      endActions: [
        ?canNavigate
            ? Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colors.onSurfaceVariantSummary,
              )
            : null,
      ],
      onClick: canNavigate
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
        showMiuixSnackbar(tr.get('modsPlugins.downloadQueued'));
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

Widget _chip(MiuixThemeData theme, String label) {
  return Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: theme.textStyles.footnote2),
  );
}

Widget _centerMessage(MiuixThemeData theme, IconData icon, String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colors.onSurfaceVariantSummary),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
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

    final theme = MiuixTheme.of(context);
    final current = queue.current;
    final pending = queue.pendingCount;
    final completed = queue.completedCount;
    final failed = queue.failedCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colors.primaryContainer,
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
                            tween: Tween(
                              begin: current.progress,
                              end: current.progress,
                            ),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.linear,
                            builder: (context, value, _) =>
                                CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 2,
                                ),
                          )
                        : const MiuixInfiniteProgressIndicator(size: 20),
                  )
                else
                  Icon(
                    Icons.download_done,
                    size: 18,
                    color: theme.colors.primary,
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
                          style: theme.textStyles.body2.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Text(
                          context.tr('modsPlugins.queueEmpty'),
                          maxLines: 1,
                          style: theme.textStyles.body2.copyWith(
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
                          style: theme.textStyles.footnote2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colors.onSurfaceVariantSummary,
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
    final theme = MiuixTheme.of(context);
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
                      style: theme.textStyles.title4,
                    ),
                  ),
                  if (queue.hasActiveTasks)
                    MiuixTextButton(
                      tr.get('modsPlugins.cancelAll'),
                      onPressed: () => DownloadQueue.instance.cancelAll(),
                    ),
                  if (queue.tasks.any(
                    (t) =>
                        t.status == DownloadTaskStatus.completed ||
                        t.status == DownloadTaskStatus.failed ||
                        t.status == DownloadTaskStatus.cancelled,
                  ))
                    MiuixTextButton(
                      tr.get('modsPlugins.clearFinished'),
                      onPressed: () => DownloadQueue.instance.removeFinished(),
                    ),
                  MiuixIconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: MiuixIcon(icon: Icons.close),
                  ),
                ],
              ),
            ),
            const MiuixHorizontalDivider(),
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
    final theme = MiuixTheme.of(context);

    IconData statusIcon;
    Color? statusColor;
    switch (task.status) {
      case DownloadTaskStatus.downloading:
        statusIcon = Icons.downloading;
        statusColor = theme.colors.primary;
        break;
      case DownloadTaskStatus.pending:
        statusIcon = Icons.schedule;
        statusColor = theme.colors.onSurfaceVariantSummary;
        break;
      case DownloadTaskStatus.completed:
        statusIcon = Icons.check_circle;
        statusColor = theme.colors.primary;
        break;
      case DownloadTaskStatus.failed:
        statusIcon = Icons.error_outline;
        statusColor = theme.colors.error;
        break;
      case DownloadTaskStatus.cancelled:
        statusIcon = Icons.cancel;
        statusColor = theme.colors.onSurfaceVariantSummary;
        break;
    }

    return MiuixBasicComponent(
      startAction: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: _ModIcon(url: task.iconUrl),
      ),
      content: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              task.projectTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.versionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1,
                ),
                if (task.status == DownloadTaskStatus.downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: task.progress >= 0
                        ? TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: task.progress,
                              end: task.progress,
                            ),
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
                    style: theme.textStyles.footnote2.copyWith(
                      color: theme.colors.error,
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
                      style: theme.textStyles.footnote2.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
      endActions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 20, color: statusColor),
            if (task.status == DownloadTaskStatus.downloading ||
                task.status == DownloadTaskStatus.pending)
              MiuixIconButton(
                onPressed: () => DownloadQueue.instance.cancel(task.id),
                child: MiuixIcon(icon: Icons.close, size: 18),
              )
            else
              MiuixIconButton(
                onPressed: () => DownloadQueue.instance.remove(task.id),
                child: MiuixIcon(icon: Icons.delete_outline, size: 18),
              ),
          ],
        ),
      ],
    );
  }
}
