import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/server_service.dart';
import 'api_error.dart';

/// 下载 Tab:平台按实例类型自动决定(Java → Modrinth,PocketMine → Poggit)。
///
/// 目标目录 = 父页传入的可用目录列表([folders]),顶部 segmented 切换 plugins/mods,
/// Modrinth 的 projectType(plugin/mod)与目标目录跟随切换,两个目录都能下。
/// 下载统一走 V2 任务系统:`POST /instances/{id}/mods/download` 创建
/// download_single_file 任务(每个任务内部绑定一个 aria2 下载任务 gid),
/// 进度经下载队列横幅/任务页查看。
class DownloadTab extends ConsumerStatefulWidget {
  const DownloadTab({
    super.key,
    required this.instanceId,
    required this.folders,
    required this.pocketmine,
  });

  final String instanceId;

  /// 可用目录列表(相对实例 cwd):plugins / mods。
  final List<String> folders;

  /// 是否 PocketMine 实例(决定平台:true → Poggit,false → Modrinth)。
  final bool pocketmine;

  @override
  ConsumerState<DownloadTab> createState() => _DownloadTabState();
}

enum ModSort { relevance, downloads, follows, newest, updated }

String modSortLabel(ModSort s) => switch (s) {
      ModSort.relevance => '相关度',
      ModSort.downloads => '下载量',
      ModSort.follows => '收藏',
      ModSort.newest => '最新',
      ModSort.updated => '最近更新',
    };

class _DownloadTabState extends ConsumerState<DownloadTab> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool get _poggit => widget.pocketmine;

  /// 当前选中的目标目录(plugins / mods)。
  String? _selectedFolder;

  // 通用状态
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  // ── Modrinth ──
  List<ModrinthSearchHit> _results = [];
  int _totalHits = 0;
  List<String> _gameVersions = [];
  String? _selectedGameVersion;
  String? _selectedLoader;
  ModSort _sort = ModSort.relevance;

  // ── Poggit ──
  List<PoggitPlugin> _allPlugins = [];
  List<PoggitPlugin> _poggitResults = [];
  List<String> _tags = [];
  String? _selectedTag;
  bool _sortByName = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  /// projectType:插件(paper 等) vs 模组(fabric 等),随目标目录切换。
  String get _projectType => _selectedFolder == 'plugins' ? 'plugin' : 'mod';

  List<String> get _loaders => _projectType == 'plugin'
      ? const ['paper', 'spigot', 'velocity', 'bungeecord']
      : const ['fabric', 'forge', 'quilt', 'neoforge'];

  @override
  void initState() {
    super.initState();
    _selectedFolder = widget.folders.isNotEmpty ? widget.folders.first : null;
    _scrollCtrl.addListener(_onScroll);
    if (_poggit) {
      _loadPoggit();
    } else {
      _loadGameVersions();
      _search();
    }
  }

  /// 切换目标目录:Modrinth 重新按新 projectType 搜索;Poggit 平台不变仅改落盘目录。
  void _switchFolder(String folder) {
    if (folder == _selectedFolder) return;
    setState(() {
      _selectedFolder = folder;
      _loading = true;
    });
    _results = [];
    _totalHits = 0;
    _error = null;
    if (_poggit) {
      _applyPoggitFilter();
    } else {
      _search();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onScroll() {
    if (_poggit) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _search(more: true);
    }
  }

  // ── Modrinth ──────────────────────────────────────────────

  Future<void> _loadGameVersions() async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.getModsApi().modrinthGameVersions();
      if (!mounted) return;
      setState(() => _gameVersions = resp.data!.toList());
    } catch (_) {
      // 筛选器不可用不影响搜索
    }
  }

  Future<void> _search({bool more = false}) async {
    final client = _client;
    if (client == null || _poggit) return;
    if (more && (_loadingMore || _loading)) return;
    if (more && _results.length >= _totalHits) return;
    final query = _controller.text.trim();
    final offset = more ? _results.length : 0;
    if (!more) {
      setState(() {
        _loading = true;
        _error = null;
        if (offset == 0) _results = [];
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final resp = await client.getModsApi().modrinthSearch(
            query: query,
            offset: offset,
            limit: 20,
            gameVersion: _selectedGameVersion,
            loader: _selectedLoader,
            sort: _sort.name,
            projectType: _projectType,
          );
      if (!mounted) return;
      final data = resp.data!;
      setState(() {
        if (more) {
          _results.addAll(data.hits);
        } else {
          _results = data.hits.toList();
          _totalHits = data.totalHits;
        }
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!more) _error = apiErrorMessage(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _showVersionSheet(ModrinthSearchHit hit) async {
    final downloaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ModrinthVersionSheet(
        instanceId: widget.instanceId,
        folder: _selectedFolder!,
        projectId: hit.projectId,
        title: hit.title,
        iconUrl: hit.iconUrl,
        filterGameVersion: _selectedGameVersion,
        filterLoader: _selectedLoader,
      ),
    );
    if (downloaded == true && mounted) _snack('已加入下载队列');
  }

  // ── Poggit ────────────────────────────────────────────────

  Future<void> _loadPoggit() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await client.getModsApi().poggitPlugins();
      if (!mounted) return;
      final all = resp.data!.toList();
      final tagSet = <String>{};
      for (final p in all) {
        tagSet.addAll(p.tag ?? const []);
      }
      final tags = tagSet.toList()..sort();
      setState(() {
        _allPlugins = all;
        _tags = tags;
        _loading = false;
      });
      _applyPoggitFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _applyPoggitFilter() {
    final query = _controller.text.trim().toLowerCase();
    final tag = _selectedTag;
    final sortByName = _sortByName;
    var list = _allPlugins.where((p) {
      if (query.isNotEmpty && !p.name.toLowerCase().contains(query)) {
        return false;
      }
      if (tag != null && !(p.tag ?? const <String>[]).contains(tag)) return false;
      return true;
    }).toList();
    if (sortByName) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      list.sort((a, b) => (b.dl ?? 0).compareTo(a.dl ?? 0));
    }
    if (mounted) {
      setState(() {
        _poggitResults = list;
        _loading = false;
      });
    }
  }

  void _searchPoggit() {
    setState(() => _loading = true);
    _applyPoggitFilter();
  }

  Future<void> _downloadPoggit(PoggitPlugin plugin) async {
    final client = _client;
    final url = plugin.artifactUrl;
    if (client == null || url == null || url.isEmpty) {
      _snack('该插件没有可下载文件');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('下载「${plugin.name}」'),
        content: Text('${plugin.version ?? ''}\n将加入下载队列,可稍后查看进度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await client.getInstancesApi().downloadInstanceMod(
            instanceId: widget.instanceId,
            modDownloadRequest: ModDownloadRequest((b) => b
              ..url = url
              ..destPath = _selectedFolder!
              ..displayName = '${plugin.name} · ${plugin.version ?? ''}'),
          );
      _snack('已加入下载队列');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  // ── 构建 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        if (widget.folders.length > 1) _buildFolderSegmented(),
        _buildFilterBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _centerMessage(Icons.cloud_off, '加载失败:$_error')
                  : _poggit
                      ? (_poggitResults.isEmpty
                          ? _centerMessage(Icons.inbox_outlined, '未找到插件')
                          : _poggitList())
                      : (_results.isEmpty
                          ? _centerMessage(Icons.inbox_outlined, '未找到结果')
                          : _modrinthList()),
        ),
      ],
    );
  }

  /// 目录切换 segmented 按钮(插件/模组),目标目录与平台跟随。
  Widget _buildFolderSegmented() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<String>(
        selected: {_selectedFolder!},
        onSelectionChanged: (s) => _switchFolder(s.first),
        segments: [
          for (final f in widget.folders)
            ButtonSegment(
              value: f,
              label: Text(f == 'plugins' ? '插件' : '模组'),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: _poggit ? '搜索 PocketMine 插件' : '搜索模组/插件',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) => _poggit ? _searchPoggit() : _search(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed:
                _loading ? null : () => _poggit ? _searchPoggit() : _search(),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (_poggit) ...[
            _filterChip(
              label: _sortByName ? '按名称' : '按下载量',
              icon: Icons.sort,
              onTap: () {
                setState(() => _sortByName = !_sortByName);
                _applyPoggitFilter();
              },
            ),
            if (_tags.isNotEmpty)
              _filterChip(
                label: _selectedTag ?? '全部类型',
                icon: Icons.category_outlined,
                onTap: () => _showTagPicker(),
              ),
          ] else ...[
            _filterChip(
              label: modSortLabel(_sort),
              icon: Icons.sort,
              onTap: () => _showSortPicker(),
            ),
            _filterChip(
              label: _selectedLoader ?? '任意加载器',
              icon: Icons.extension_outlined,
              onTap: () => _showLoaderPicker(),
            ),
            if (_gameVersions.isNotEmpty)
              _filterChip(
                label: _selectedGameVersion ?? '任意版本',
                icon: Icons.verified_outlined,
                onTap: () => _showVersionPicker(),
              ),
            if (_selectedLoader != null || _selectedGameVersion != null)
              ActionChip(
                label: const Text('清除筛选'),
                avatar: const Icon(Icons.clear_all, size: 16),
                onPressed: () {
                  setState(() {
                    _selectedLoader = null;
                    _selectedGameVersion = null;
                  });
                  _search();
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }

  Future<void> _showSortPicker() async {
    final picked = await showModalBottomSheet<ModSort>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in ModSort.values)
              ListTile(
                title: Text(modSortLabel(s)),
                trailing: s == _sort ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = picked);
    _search();
  }

  Future<void> _showLoaderPicker() async {
    final items = <String?>[null, ..._loaders];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              ListTile(
                title: Text(items[i] == null
                    ? '任意加载器'
                    : items[i]!.toUpperCase()),
                trailing: items[i] == _selectedLoader
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedLoader = items[picked]);
    _search();
  }

  Future<void> _showVersionPicker() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('任意版本'),
              trailing: _selectedGameVersion == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final v in _gameVersions)
              ListTile(
                title: Text(v),
                trailing: v == _selectedGameVersion
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedGameVersion = picked.isEmpty ? null : picked);
    _search();
  }

  Future<void> _showTagPicker() async {
    final items = <String?>[null, ..._tags];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              ListTile(
                title: Text(items[i] ?? '全部类型'),
                trailing: items[i] == _selectedTag
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTag = items[picked]);
    _applyPoggitFilter();
  }

  Widget _modrinthList() {
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _results.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _results.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
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
                  '共 $_totalHits 个结果',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return const SizedBox(height: 8);
        }
        final hit = _results[i];
        return ListTile(
          leading: _ModIcon(url: hit.iconUrl),
          title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            hit.description ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_outlined, size: 14),
                  const SizedBox(width: 2),
                  Text(_formatCount(hit.downloads ?? 0)),
                ],
              ),
              if (hit.categories != null && hit.categories!.isNotEmpty)
                Text(
                  hit.categories!.take(2).join(', '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          onTap: () => _showVersionSheet(hit),
        );
      },
    );
  }

  Widget _poggitList() {
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _poggitResults.length,
      itemBuilder: (ctx, i) {
        final p = _poggitResults[i];
        return ListTile(
          leading: _ModIcon(url: p.icon),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              p.version ?? '',
              if (p.tag != null && p.tag!.isNotEmpty) p.tag!.join(', '),
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _formatCount(p.dl ?? 0),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          onTap: () => _downloadPoggit(p),
        );
      },
    );
  }

  Widget _centerMessage(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int count) {
    if (count < 1000) return '$count';
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}

/// 模组/插件图标(优先平台图标,加载失败/缺失回退通用图标)。
class _ModIcon extends StatelessWidget {
  const _ModIcon({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.extension_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    final u = url;
    if (u == null || u.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        u,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// Modrinth 版本选择底部弹层。
class _ModrinthVersionSheet extends ConsumerStatefulWidget {
  const _ModrinthVersionSheet({
    required this.instanceId,
    required this.folder,
    required this.projectId,
    required this.title,
    this.iconUrl,
    this.filterGameVersion,
    this.filterLoader,
  });

  final String instanceId;
  final String folder;
  final String projectId;
  final String title;
  final String? iconUrl;
  final String? filterGameVersion;
  final String? filterLoader;

  @override
  ConsumerState<_ModrinthVersionSheet> createState() =>
      _ModrinthVersionSheetState();
}

class _ModrinthVersionSheetState
    extends ConsumerState<_ModrinthVersionSheet> {
  List<ModrinthVersion> _versions = [];
  bool _loading = true;
  String? _error;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await client.getModsApi().modrinthProjectVersions(
            projectId: widget.projectId,
            gameVersion: widget.filterGameVersion,
            loader: widget.filterLoader,
          );
      if (!mounted) return;
      setState(() {
        _versions = resp.data!.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('加载失败:$_error'))
                    : _versions.isEmpty
                        ? const Center(child: Text('没有匹配的版本'))
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: _versions.length,
                            itemBuilder: (ctx, i) {
                              final v = _versions[i];
                              final deps = v.dependencies ?? const <ModrinthDependency>[];
                              return ListTile(
                                title: Text(
                                  v.name == null || v.name!.isEmpty
                                      ? v.versionNumber
                                      : v.name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final gv in (v.gameVersions ?? const <String>[])
                                        .take(3))
                                      _chip(gv),
                                    for (final l in (v.loaders ?? const <String>[]))
                                      _chip(l),
                                    if (v.files != null &&
                                        v.files!.isNotEmpty)
                                      _chip(_formatSize(v.files!.first.size)),
                                    if (deps.any((d) =>
                                        d.projectId != null &&
                                        d.projectId!.isNotEmpty))
                                      _chip('${deps.length} 个依赖'),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final downloaded =
                                      await Navigator.of(ctx).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => _ModrinthVersionDetailPage(
                                        instanceId: widget.instanceId,
                                        folder: widget.folder,
                                        title: widget.title,
                                        iconUrl: widget.iconUrl,
                                        version: v,
                                      ),
                                      fullscreenDialog: true,
                                    ),
                                  );
                                  if (downloaded == true && ctx.mounted) {
                                    Navigator.of(ctx).pop(true);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// Modrinth 版本详情页:文件信息 + 依赖列表 + 下载。
class _ModrinthVersionDetailPage extends ConsumerStatefulWidget {
  const _ModrinthVersionDetailPage({
    required this.instanceId,
    required this.folder,
    required this.title,
    this.iconUrl,
    required this.version,
  });

  final String instanceId;
  final String folder;
  final String title;
  final String? iconUrl;
  final ModrinthVersion version;

  @override
  ConsumerState<_ModrinthVersionDetailPage> createState() =>
      _ModrinthVersionDetailPageState();
}

class _ModrinthVersionDetailPageState
    extends ConsumerState<_ModrinthVersionDetailPage> {
  final Map<String, ModrinthProject> _depProjects = {};
  bool _loadingDeps = true;

  ModrinthVersion get _v => widget.version;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _loadDeps();
  }

  Future<void> _loadDeps() async {
    final client = _client;
    final depIds = (_v.dependencies ?? const <ModrinthDependency>[])
        .where((d) => d.projectId != null && d.projectId!.isNotEmpty)
        .map((d) => d.projectId!)
        .toSet()
        .toList();
    if (client == null || depIds.isEmpty) {
      if (mounted) setState(() => _loadingDeps = false);
      return;
    }
    try {
      final resp = await client.getModsApi().modrinthProjects(
            ids: BuiltList<String>(depIds),
          );
      if (!mounted) return;
      setState(() {
        for (final p in resp.data!) {
          _depProjects[p.id] = p;
        }
        _loadingDeps = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDeps = false);
    }
  }

  ModrinthVersionFile? get _primaryFile {
    final files = _v.files ?? const <ModrinthVersionFile>[];
    if (files.isEmpty) return null;
    return files.where((f) => f.primary).firstOrNull ?? files.first;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download() async {
    final client = _client;
    final file = _primaryFile;
    if (client == null || file == null) return;
    final displayName = _v.name == null || _v.name!.isEmpty
        ? '${widget.title} · ${_v.versionNumber}'
        : '${widget.title} · ${_v.name}';
    try {
      await client.getInstancesApi().downloadInstanceMod(
            instanceId: widget.instanceId,
            modDownloadRequest: ModDownloadRequest((b) => b
              ..url = file.url
              ..destPath = widget.folder
              ..fileName = file.filename
              ..displayName = displayName),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  void _openDep(String projectId, String title, String? iconUrl) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ModrinthVersionSheet(
        instanceId: widget.instanceId,
        folder: widget.folder,
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
      ),
    );
  }

  String _depLabel(ModrinthDependency dep) {
    final p = dep.projectId == null ? null : _depProjects[dep.projectId];
    if (p != null) return p.title;
    return '依赖项目';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _v;
    final file = _primaryFile;
    final deps = v.dependencies ?? const <ModrinthDependency>[];
    final requiredDeps = deps.where((d) => d.dependencyType == 'required').toList();
    final optionalDeps = deps.where((d) => d.dependencyType == 'optional').toList();
    final incompatibleDeps = deps
        .where((d) => d.dependencyType == 'incompatible')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('版本详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _ModIcon(url: widget.iconUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      v.name == null || v.name!.isEmpty
                          ? v.versionNumber
                          : v.name!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow('版本号', v.versionNumber),
          if (v.gameVersions != null && v.gameVersions!.isNotEmpty)
            _infoRow('游戏版本', v.gameVersions!.join(', ')),
          if (v.loaders != null && v.loaders!.isNotEmpty)
            _infoRow('加载器', v.loaders!.join(', ')),
          if (file != null) ...[
            _infoRow('文件名', file.filename),
            if (file.size != null) _infoRow('大小', _formatSize(file.size)),
            if (file.hashes?.sha1 != null)
              _infoRow('SHA1', file.hashes!.sha1!),
          ],
          const Divider(height: 32),
          if (_loadingDeps)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (requiredDeps.isNotEmpty) ...[
              _sectionTitle('必需依赖'),
              for (final d in requiredDeps) _depTile(d),
            ],
            if (optionalDeps.isNotEmpty) ...[
              _sectionTitle('可选依赖'),
              for (final d in optionalDeps) _depTile(d),
            ],
            if (incompatibleDeps.isNotEmpty) ...[
              _sectionTitle('不兼容'),
              for (final d in incompatibleDeps) _depTile(d),
            ],
            if (requiredDeps.isEmpty &&
                optionalDeps.isEmpty &&
                incompatibleDeps.isEmpty)
              const Text('无依赖'),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: file == null ? null : _download,
            icon: const Icon(Icons.download),
            label: const Text('下载此版本'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _depTile(ModrinthDependency dep) {
    final canNavigate = dep.projectId != null && dep.projectId!.isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        dep.dependencyType == 'incompatible'
            ? Icons.block
            : dep.dependencyType == 'required'
                ? Icons.priority_high
                : Icons.low_priority,
        size: 20,
        color: dep.dependencyType == 'incompatible'
            ? Theme.of(context).colorScheme.error
            : null,
      ),
      title: Text(_depLabel(dep), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: dep.projectId != null
          ? Text(dep.projectId!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: canNavigate ? const Icon(Icons.chevron_right) : null,
      onTap: canNavigate
          ? () => _openDep(dep.projectId!, _depLabel(dep),
              _depProjects[dep.projectId]?.iconUrl)
          : null,
    );
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '未知';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
