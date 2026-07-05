import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../mods/download_queue.dart';
import '../mods/icon_cache.dart';
import '../mods/poggit_service.dart';
import 'mod_download_page.dart' show DownloadQueueBanner, showDownloadQueueSheet;

/// Poggit 排序方式。
enum PoggitSort { downloads, updated, name }

/// Poggit 插件下载页：搜索 PocketMine-MP 插件并下载到指定目录。
///
/// 数据源为 Poggit 官方 API（https://poggit.pmmp.io/plugins.min.json）。
/// 由于 Poggit 的 name 参数为精确匹配，搜索在客户端进行模糊过滤。
/// 支持分类、API 版本、状态筛选和排序。
class PoggitDownloadPage extends StatefulWidget {
  const PoggitDownloadPage({
    super.key,
    required this.pluginsFolder,
    this.embedded = false,
  });

  final Directory pluginsFolder;
  final bool embedded;

  @override
  State<PoggitDownloadPage> createState() => _PoggitDownloadPageState();
}

class _PoggitDownloadPageState extends State<PoggitDownloadPage> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<PoggitPlugin> _allPlugins = [];
  List<PoggitPlugin> _results = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  // 筛选状态
  PoggitSort _sort = PoggitSort.downloads;
  String? _selectedCategory; // null = 任意
  String? _selectedApi; // null = 任意
  bool _officialOnly = false;
  bool _hidePreRelease = false;
  bool _hideOutdated = true; // 默认隐藏过时插件

  // 从数据中提取的可选值（加载完成后填充）
  List<String> _categories = [];
  List<String> _apiVersions = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadPlugins();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <=
        _scrollCtrl.position.minScrollExtent + 100) {
      // 顶部下拉时不触发分页（Poggit 一次性加载全部，无需分页）
    }
  }

  Future<void> _loadPlugins({bool forceRefresh = false}) async {
    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final plugins = await PoggitService.fetchPlugins(
        forceRefresh: forceRefresh,
      );
      // 提取可选分类与 API 版本（去重并排序）
      final categorySet = <String>{};
      final apiSet = <String>{};
      for (final p in plugins) {
        for (final c in p.categories) {
          if (c.categoryName.isNotEmpty) categorySet.add(c.categoryName);
        }
        for (final a in p.api) {
          if (a.from.isNotEmpty) apiSet.add(a.from);
        }
      }
      final categories = categorySet.toList()..sort();
      final apiVersions = apiSet.toList()
        ..sort((x, y) => _compareApiVersions(x, y));
      if (!mounted) return;
      setState(() {
        _allPlugins = plugins;
        _categories = categories;
        _apiVersions = apiVersions;
        // 若已选筛选值在新数据中不存在，则重置
        if (_selectedCategory != null &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
        if (_selectedApi != null && !apiVersions.contains(_selectedApi)) {
          _selectedApi = null;
        }
        _results = _applyFilters();
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  /// PocketMine API 版本号比较（按数字段比较，如 5.0.0 > 4.0.0）。
  int _compareApiVersions(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final xa = i < pa.length ? (pa[i] ?? 0) : 0;
      final xb = i < pb.length ? (pb[i] ?? 0) : 0;
      if (xa != xb) return xa.compareTo(xb);
    }
    return a.compareTo(b);
  }

  /// 应用当前所有筛选条件（搜索 + 分类 + API + 状态）与排序。
  List<PoggitPlugin> _applyFilters() {
    var result = _allPlugins;
    if (_selectedCategory != null) {
      result = result
          .where(
            (p) => p.categories.any((c) => c.categoryName == _selectedCategory),
          )
          .toList();
    }
    if (_selectedApi != null) {
      result = result
          .where((p) => p.api.any((a) => a.from == _selectedApi))
          .toList();
    }
    if (_officialOnly) {
      result = result.where((p) => p.isOfficial).toList();
    }
    if (_hidePreRelease) {
      result = result.where((p) => !p.isPreRelease).toList();
    }
    if (_hideOutdated) {
      result = result.where((p) => !p.isOutdated).toList();
    }
    // 应用搜索
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      result = PoggitService.search(result, query);
    }
    // 排序
    final sorted = List<PoggitPlugin>.from(result);
    switch (_sort) {
      case PoggitSort.downloads:
        sorted.sort((a, b) => b.downloads.compareTo(a.downloads));
      case PoggitSort.updated:
        sorted.sort((a, b) => b.submissionDate.compareTo(a.submissionDate));
      case PoggitSort.name:
        sorted.sort((a, b) {
          final an = a.projectName.isNotEmpty ? a.projectName : a.name;
          final bn = b.projectName.isNotEmpty ? b.projectName : b.name;
          return an.toLowerCase().compareTo(bn.toLowerCase());
        });
    }
    return sorted;
  }

  /// 任何筛选条件变化时调用，重新计算结果列表。
  void _refilter() {
    setState(() {
      _results = _applyFilters();
    });
  }

  void _search() {
    _refilter();
  }

  /// 是否有任何筛选条件被启用（用于显示「清除筛选」按钮）。
  bool get _hasActiveFilters {
    return _selectedCategory != null ||
        _selectedApi != null ||
        _officialOnly ||
        _hidePreRelease ||
        !_hideOutdated; // _hideOutdated 默认 true，关闭才算"启用筛选"
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedApi = null;
      _officialOnly = false;
      _hidePreRelease = false;
      _hideOutdated = true;
      _results = _applyFilters();
    });
  }

  void _openVersions(PoggitPlugin plugin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _PoggitVersionSheet(
        plugin: plugin,
        pluginsFolder: widget.pluginsFolder,
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
              content: Text(context.tr('poggit.downloadQueued')),
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
          : AppBar(title: Text(context.tr('poggit.title'))),
      body: Column(
        children: [
          _buildSearchBar(theme),
          _buildFilterBar(theme),
          const DownloadQueueBanner(),
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
                hintText: context.tr('poggit.searchHint'),
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
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
            tooltip: context.tr('common.refresh'),
            onPressed: _refreshing ? null : () => _loadPlugins(forceRefresh: true),
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
            label: context.tr('poggit.sortLabel'),
            value: context.tr('poggit.sort.${_sort.name}'),
            icon: Icons.sort,
            onTap: () => _showSortPicker(theme),
          ),
          _filterChip(
            label: context.tr('poggit.category'),
            value: _selectedCategory ?? context.tr('poggit.any'),
            icon: Icons.category_outlined,
            onTap: () => _showCategoryPicker(theme),
          ),
          _filterChip(
            label: context.tr('poggit.apiVersion'),
            value: _selectedApi ?? context.tr('poggit.any'),
            icon: Icons.api_outlined,
            onTap: () => _showApiPicker(theme),
          ),
          _toggleChip(
            label: context.tr('poggit.officialOnly'),
            icon: Icons.verified_outlined,
            active: _officialOnly,
            onTap: () {
              setState(() {
                _officialOnly = !_officialOnly;
                _results = _applyFilters();
              });
            },
          ),
          _toggleChip(
            label: context.tr('poggit.hidePreRelease'),
            icon: Icons.visibility_off_outlined,
            active: _hidePreRelease,
            onTap: () {
              setState(() {
                _hidePreRelease = !_hidePreRelease;
                _results = _applyFilters();
              });
            },
          ),
          _toggleChip(
            label: context.tr('poggit.hideOutdated'),
            icon: Icons.warning_amber_outlined,
            active: _hideOutdated,
            onTap: () {
              setState(() {
                _hideOutdated = !_hideOutdated;
                _results = _applyFilters();
              });
            },
          ),
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: ActionChip(
                label: Text(context.tr('modsPlugins.clearFilter')),
                avatar: const Icon(Icons.clear_all, size: 16),
                onPressed: _clearFilters,
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
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

  /// 切换型筛选 Chip：激活时高亮显示。
  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: FilterChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _showSortPicker(ThemeData theme) {
    final options = PoggitSort.values;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('poggit.sortLabel')),
        children: options
            .map(
              (s) => SimpleDialogOption(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _sort = s);
                  _results = _applyFilters();
                },
                child: Row(
                  children: [
                    if (_sort == s)
                      Icon(Icons.check, color: theme.colorScheme.primary)
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 8),
                    Text(context.tr('poggit.sort.${s.name}')),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showCategoryPicker(ThemeData theme) {
    _showOptionPicker(
      theme,
      title: context.tr('poggit.category'),
      options: _categories,
      selected: _selectedCategory,
      onSelected: (v) {
        setState(() => _selectedCategory = v);
        _results = _applyFilters();
      },
    );
  }

  void _showApiPicker(ThemeData theme) {
    // API 版本降序排列（最新在前）
    final apis = List<String>.from(_apiVersions)..sort((a, b) => _compareApiVersions(b, a));
    _showOptionPicker(
      theme,
      title: context.tr('poggit.apiVersion'),
      options: apis,
      selected: _selectedApi,
      onSelected: (v) {
        setState(() => _selectedApi = v);
        _results = _applyFilters();
      },
    );
  }

  /// 通用单选弹窗：含「任意」选项。
  void _showOptionPicker(
    ThemeData theme, {
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onSelected,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSelected(null);
            },
            child: Row(
              children: [
                if (selected == null)
                  Icon(Icons.check, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 24),
                const SizedBox(width: 8),
                Text(context.tr('poggit.any')),
              ],
            ),
          ),
          ...options.map((opt) {
            final isSel = opt == selected;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.of(ctx).pop();
                onSelected(opt);
              },
              child: Row(
                children: [
                  if (isSel)
                    Icon(Icons.check, color: theme.colorScheme.primary)
                  else
                    const SizedBox(width: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      opt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              context.tr('poggit.loading'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return _centerMessage(
        theme,
        Icons.error_outline,
        context.tr('poggit.loadFailed', {'error': _error!}),
      );
    }
    if (_results.isEmpty) {
      return _centerMessage(
        theme,
        Icons.inbox_outlined,
        context.tr('poggit.noResults'),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadPlugins(forceRefresh: true),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _results.length,
        itemBuilder: (ctx, i) {
          final plugin = _results[i];
          return _buildPluginCard(theme, plugin);
        },
      ),
    );
  }

  Widget _buildPluginCard(ThemeData theme, PoggitPlugin plugin) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CachedModIcon(url: plugin.iconUrl, size: 40),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plugin.projectName.isNotEmpty ? plugin.projectName : plugin.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (plugin.isOfficial)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.verified,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (plugin.isOutdated)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (plugin.tagline.isNotEmpty)
              Text(
                plugin.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (plugin.mainCategory.isNotEmpty)
                  _chip(theme, plugin.mainCategory),
                if (plugin.version.isNotEmpty)
                  _chip(theme, 'v${plugin.version}'),
                _downloadsChip(theme, plugin.downloads),
              ],
            ),
          ],
        ),
        onTap: () => _openVersions(plugin),
      ),
    );
  }

  Widget _downloadsChip(ThemeData theme, int downloads) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_outlined,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          Text(
            _formatDownloads(downloads),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  String _formatDownloads(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ───────────────────────────── 版本选择弹层 ─────────────────────────────

class _PoggitVersionSheet extends StatefulWidget {
  const _PoggitVersionSheet({
    required this.plugin,
    required this.pluginsFolder,
    required this.onDownloaded,
  });

  final PoggitPlugin plugin;
  final Directory pluginsFolder;
  final VoidCallback onDownloaded;

  @override
  State<_PoggitVersionSheet> createState() => _PoggitVersionSheetState();
}

class _PoggitVersionSheetState extends State<_PoggitVersionSheet> {
  List<PoggitPlugin> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    try {
      final name = widget.plugin.name;
      final versions = await PoggitService.getPluginVersions(name);
      // 按提交时间降序排列（最新版本在前）
      versions.sort((a, b) => b.submissionDate.compareTo(a.submissionDate));
      if (!mounted) return;
      setState(() {
        _versions = versions;
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

  void _enqueueDownload(PoggitPlugin version) {
    final destPath = p.join(widget.pluginsFolder.path, version.fileName);
    DownloadQueue.instance.enqueue(
      url: version.artifactUrl,
      destPath: destPath,
      filename: version.fileName,
      projectTitle: widget.plugin.projectName.isNotEmpty
          ? widget.plugin.projectName
          : widget.plugin.name,
      versionName: version.version,
      iconUrl: widget.plugin.iconUrl,
    );
    // 不在此处显示 SnackBar：此处 context 是 sheet 的 BuildContext，
    // sheet 关闭后会失效，导致 SnackBar 永不消失且"查看队列"按钮点击无效。
    // 改由父页面在 sheet 关闭后的 .then() 回调中用稳定的 context 显示。
    widget.onDownloaded();
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
                      widget.plugin.projectName.isNotEmpty
                          ? widget.plugin.projectName
                          : widget.plugin.name,
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
            if (widget.plugin.tagline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.plugin.tagline,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        tr.get('poggit.loadFailed', {'error': _error!}),
                      ),
                    )
                  : _versions.isEmpty
                  ? Center(child: Text(tr.get('poggit.noVersions')))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _versions.length,
                      itemBuilder: (ctx, i) {
                        final v = _versions[i];
                        return _buildVersionTile(theme, v);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVersionTile(ThemeData theme, PoggitPlugin v) {
    final isCurrent = v.id == widget.plugin.id;
    return ListTile(
      leading: isCurrent
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 24)
          : Icon(Icons.history, color: theme.colorScheme.onSurfaceVariant, size: 24),
      title: Text(v.version),
      subtitle: Wrap(
        spacing: 6,
        children: [
          if (v.api.isNotEmpty)
            _chip(theme, 'API ${v.api.first.from}~${v.api.first.to}'),
          if (v.isPreRelease)
            _chipWithColor(theme, context.tr('poggit.preRelease'), theme.colorScheme.tertiary),
          if (v.isOutdated)
            _chipWithColor(theme, context.tr('poggit.outdated'), theme.colorScheme.error),
          if (v.submissionDate != 0) _chip(theme, _formatDate(v.submissionDate)),
        ],
      ),
      trailing: FilledButton.tonalIcon(
        icon: const Icon(Icons.download, size: 18),
        label: Text(context.tr('common.add')),
        onPressed: () => _enqueueDownload(v),
      ),
    );
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ───────────────────────────── 通用组件 ─────────────────────────────

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

// 重载：带颜色参数的 _chip（用于状态标签）
Widget _chipWithColor(ThemeData theme, String label, Color color) {
  return Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
    ),
    child: Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

Widget _centerMessage(ThemeData theme, IconData icon, String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
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
