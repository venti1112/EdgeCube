import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../download/format.dart';
import '../instance/providers.dart';
import '../download/models.dart';
import '../download/providers.dart';
import '../settings/appearance.dart';
import '../shell/glass.dart';
import '../task/providers.dart';
import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 模组/插件下载页：跨平台搜索并下载到指定实例（数据全来自 daemon）。
///
/// 排版：搜索框 + 「搜索」按钮、筛选 Chip 行
/// （排序 / 加载器 / 游戏版本 / 清除筛选）、结果计数与触底翻页、点结果弹「版本选择」
/// 底部弹层、点版本进「版本详情」、底部「下载此版本」提交 `mods-install` 工作流。
///
/// **下载源与队列（都是 daemon 架构带来的）**：
/// * 下载源由 daemon 的 `mods.sources` 聚合，前端只有一份目录，没有「源切换条」。
/// * 点「下载此版本」提交 daemon 的 `mods-install` 工作流（成功提示
///   「已加入下载队列」）。队列横幅/详情读 daemon 的
///   `download.*` 队列（[downloadListStreamProvider]）。
/// * daemon 的 `download` 模块**还没有** cancel / clear 方法，所以本页里「清除已结束」
///   「全部取消」以及每条任务的取消/删除按钮都按项目约定**摆出来并置灰**
///   （`onPressed: null`），等 daemon 的 download 模块补上这两个方法再接上。
///
/// 本页被嵌进「模组/插件管理」页的标签里时（`embedded: true` 不画自己的 AppBar，
/// 因为外层已经有了）；standalone 路由进来时画自己的 AppBar。构造参数 `instanceId`
/// 决定搜索/安装落到哪个实例、以及队列横幅只显示属于当前实例的任务。
class ModDownloadPage extends ConsumerStatefulWidget {
  const ModDownloadPage({
    super.key,
    required this.projectType,
    required this.instanceId,
    this.embedded = false,
  });

  /// `mod` / `plugin` —— 搜索范围，也是装到哪个目录的依据。
  final String projectType;

  /// 当前选中的实例 id（搜索/安装/队列过滤都按它）。
  final String instanceId;

  /// 内嵌在「模组/插件管理」标签里时为 true（不画 AppBar）。
  final bool embedded;

  @override
  ConsumerState<ModDownloadPage> createState() => _ModDownloadPageState();
}

class _ModDownloadPageState extends ConsumerState<ModDownloadPage> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ModHit> _hits = [];
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  String? _selectedLoader;
  String? _selectedGameVersion;
  String _sort = 'relevance';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    // 进页先自动搜一次（按默认排序浏览）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(reset: true));
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

  /// 空搜索词时按下载量排（query 为空时用 downloads 排序）。
  String get _effectiveSort =>
      _controller.text.trim().isEmpty ? 'downloads' : _sort;

  Future<void> _search({required bool reset}) async {
    final api = ref.read(modsApiProvider);
    if (api == null) {
      if (!mounted) return;
      setState(() {
        _error = const DaemonException('unavailable', '还没有连接到守护进程');
        _loading = false;
      });
      return;
    }
    if (_loading) return;
    if (!reset && (!_hasMore || _error != null)) return;

    final query = _controller.text.trim();
    final offset = reset ? 0 : _hits.length;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _hits = [];
        _total = 0;
        _hasMore = false;
      }
    });

    try {
      final page = await api.search(
        projectType: widget.projectType,
        query: query,
        loader: _selectedLoader,
        gameVersion: _selectedGameVersion,
        sort: _effectiveSort,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hits.addAll(page.hits);
        _total = page.total;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _error != null) return;
    if (!_hasMore) return;
    final api = ref.read(modsApiProvider);
    if (api == null) return;

    setState(() => _loadingMore = true);
    try {
      final page = await api.search(
        projectType: widget.projectType,
        query: _controller.text.trim(),
        loader: _selectedLoader,
        gameVersion: _selectedGameVersion,
        sort: _effectiveSort,
        offset: _hits.length,
      );
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hits.addAll(page.hits);
        _total = page.total;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openVersions(ModHit hit) {
    _showVersionSheet(
      projectId: hit.projectId,
      title: hit.title,
      iconUrl: hit.iconUrl,
      pageUrl: hit.pageUrl,
    );
  }

  void _showVersionSheet({
    required String projectId,
    required String title,
    String? iconUrl,
    String? pageUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _VersionSheet(
        projectId: projectId,
        title: title,
        iconUrl: iconUrl,
        pageUrl: pageUrl,
        instanceId: widget.instanceId,
        projectType: widget.projectType,
        loader: _selectedLoader,
        gameVersion: _selectedGameVersion,
        onDownloaded: () => Navigator.of(context).pop(true),
      ),
    ).then((downloaded) {
      // sheet 关闭后用父页面（下载页）稳定的 context 显示 SnackBar，
      // 避免 sheet 的 context 失效导致 SnackBar 永不消失。
      if (downloaded == true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入下载队列')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(modsCatalogProvider);
    final tagsAsync = ref.watch(modsTagsProvider(widget.projectType));
    final catalog = catalogAsync.value ?? ModCatalog.empty;
    final tags = tagsAsync.value ?? ModTags.empty;

    final body = Column(
      children: [
        _buildSearchBar(),
        _buildFilterBar(catalog, tags),
        DownloadQueueBanner(instanceId: widget.instanceId),
        Expanded(child: _buildBody(catalog, tags, catalogAsync.isLoading)),
      ],
    );

    if (widget.embedded) return body;

    final typeName = widget.projectType == 'plugin' ? '下载插件' : '下载模组';
    return Scaffold(
      appBar: AppBar(title: Text(typeName)),
      body: body,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '输入模组名称搜索...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: '清空',
                          onPressed: () {
                            _controller.clear();
                            _search(reset: true);
                          },
                        ),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _search(reset: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _loading ? null : () => _search(reset: true),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ModCatalog catalog, ModTags tags) {
    final loaders = tags.loaders.map((l) => l.id).toList();
    final bar = SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _filterChip(
            label: '排序',
            value: _sortLabel(catalog),
            icon: Icons.sort,
            onTap: () => _showSortPicker(catalog),
          ),
          if (loaders.isNotEmpty)
            _filterChip(
              label: '加载器',
              value: _selectedLoader ?? '任意',
              icon: Icons.extension_outlined,
              onTap: () => _showLoaderPicker(tags),
            ),
          _filterChip(
            label: '游戏版本',
            // 列表是空的时候要说清楚为什么 —— 否则用户看到的是「菜单里只有任意」，
            // 完全无从判断（daemon 没跟着重新构建就是这样）
            value: tags.shapeMismatch
                ? '需重启守护进程'
                : (_selectedGameVersion ?? '任意'),
            icon: Icons.verified_outlined,
            onTap: () => _showVersionPicker(tags),
          ),
          if (_selectedLoader != null || _selectedGameVersion != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: ActionChip(
                label: const Text('清除筛选'),
                avatar: const Icon(Icons.clear_all, size: 16),
                onPressed: () {
                  setState(() {
                    _selectedLoader = null;
                    _selectedGameVersion = null;
                  });
                  _search(reset: true);
                },
              ),
            ),
        ],
      ),
    );
    // 芯片内部那层 canvas Material 也要透（见 glassCanvas 注释）。
    return ref.watch(glassModeEnabledProvider)
        ? glassCanvas(context, bar)
        : bar;
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

  String _sortLabel(ModCatalog catalog) {
    final found = catalog.sorts.where((s) => s.id == _sort).firstOrNull;
    return found?.name ?? _sort;
  }

  Future<void> _showSortPicker(ModCatalog catalog) async {
    if (catalog.sorts.isEmpty) return;
    final picked = await _showSingleChoice(
      context: context,
      title: '排序',
      labels: catalog.sorts.map((s) => s.name).toList(),
      selectedIndex: catalog.sorts.indexWhere((s) => s.id == _sort),
    );
    if (picked == null || !mounted) return;
    setState(() => _sort = catalog.sorts[picked].id);
    _search(reset: true);
  }

  /// 加载器选择菜单。
  ///
  /// **只能用「这个项目类型」的加载器表**（`ModTags.loaders`，来自 daemon 的
  /// `PROJECT_TYPES[].loaders`）。拿全平台的总表会让插件页出现
  /// Fabric / Forge 这种模组加载器。
  ///
  /// 菜单里的文案用 `_capitalize(id)`（所以是 `Neoforge` / `Bungeecord`
  /// 而不是品牌写法），**筛选条上显示的仍是原始 id**（有意不一致）。
  Future<void> _showLoaderPicker(ModTags tags) async {
    final loaders = tags.loaders;
    if (loaders.isEmpty) return;
    // 首项是「任意」（值 null）—— 所以按下标选
    final items = <String?>[null, ...loaders.map((l) => l.id)];
    final selected = _selectedLoader == null
        ? 0
        : items.indexOf(_selectedLoader);
    final picked = await _showSingleChoice(
      context: context,
      title: '加载器',
      labels: [for (final id in items) id == null ? '任意' : _capitalize(id)],
      selectedIndex: selected < 0 ? 0 : selected,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedLoader = items[picked]);
    _search(reset: true);
  }

  /// 首字母大写，其余原样。
  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// 游戏版本选择菜单。
  ///
  /// **正式版排在前面、其余（快照 / beta / alpha）
  /// 排在后面**，两组内部保持上游顺序；非正式版的副标题写它的类型。
  Future<void> _showVersionPicker(ModTags tags) async {
    final releases = tags.gameVersions.where((v) => v.isRelease).toList();
    final others = tags.gameVersions.where((v) => !v.isRelease).toList();
    final items = <ModGameVersion?>[null, ...releases, ...others];

    final selected = _selectedGameVersion == null
        ? 0
        : items.indexWhere((v) => v?.version == _selectedGameVersion);
    final picked = await _showSingleChoice(
      context: context,
      title: '游戏版本',
      labels: [for (final v in items) v?.version ?? '任意'],
      summaries: [
        for (final v in items) (v == null || v.isRelease) ? '' : v.versionType,
      ],
      selectedIndex: selected < 0 ? 0 : selected,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedGameVersion = items[picked]?.version);
    _search(reset: true);
  }

  Widget _buildBody(ModCatalog catalog, ModTags tags, bool loadingCatalog) {
    if (loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loading && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centerMessage(
        context,
        Icons.error_outline,
        describeModsError(_error!),
      );
    }
    if (_hits.isEmpty) {
      return _centerMessage(context, Icons.inbox_outlined, '未找到结果');
    }

    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _hits.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _hits.length) {
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
          if (!_hasMore) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '共 $_total 项结果',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return const SizedBox(height: 16);
        }
        final hit = _hits[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _HitCard(hit: hit, onTap: () => _openVersions(hit)),
        );
      },
    );
  }
}

/// 搜索结果卡。
class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit, required this.onTap});

  final ModHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ModIcon(url: hit.iconUrl, loaders: hit.loaders),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hit.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
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
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatDownloads(hit.downloads),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (hit.categories.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hit.categories.take(2).join(', '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 40×40 图标：没有就按加载器上色。
class _ModIcon extends StatelessWidget {
  const _ModIcon({required this.url, this.loaders = const []});

  final String? url;
  final List<String> loaders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 40.0;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            _loaderColor(loaders.firstOrNull) ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.extension_outlined,
        color: scheme.onSurfaceVariant,
        size: 24,
      ),
    );

    final url = this.url;
    if (url == null || url.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

Color? _loaderColor(String? loader) => switch (loader) {
  'fabric' => const Color(0xFFDDAAFF),
  'forge' => const Color(0xFFFFAA6B),
  'quilt' => const Color(0xFFAADDFF),
  'neoforge' => const Color(0xFFFF6B6B),
  'bukkit' => const Color(0xFFAAFFAA),
  'bungeecord' => const Color(0xFFFFDD6B),
  'velocity' => const Color(0xFF6BDDFF),
  'pocketmine' => const Color(0xFFAAFFDD),
  _ => null,
};

Widget _centerMessage(BuildContext context, IconData icon, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

String _formatDownloads(int count) {
  if (count < 1000) return '$count';
  if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '${(count / 1000000).toStringAsFixed(1)}M';
}

/// 单选对话框。
///
/// **按「下标」而不是「值」选**：
/// 选项里有一项是「任意」，它的值就是 `null`，而用户点取消时同样返回 `null`
/// —— 用值无法区分「选了任意」与「取消了」。所以调用方传进来的 `options` 是**下标**，
/// 拿到下标之后自己去查真实值。
///
/// [summaries] 是逐项的副标题（用来给非正式版的游戏版本显示版本类型）。
Future<int?> _showSingleChoice({
  required BuildContext context,
  required String title,
  required List<String> labels,
  required int selectedIndex,
  List<String>? summaries,
}) async {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: RadioGroup<int>(
          groupValue: selectedIndex,
          onChanged: (v) {
            if (v != null) Navigator.of(ctx).pop(v);
          },
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < labels.length; i++)
                ListTile(
                  title: Text(labels[i]),
                  subtitle:
                      (summaries != null &&
                          i < summaries.length &&
                          summaries[i].isNotEmpty)
                      ? Text(summaries[i])
                      : null,
                  leading: Radio<int>(value: i),
                  onTap: () => Navigator.of(ctx).pop(i),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── 版本选择底部弹层 ──────────────────────────────────────────────

class _VersionSheet extends ConsumerStatefulWidget {
  const _VersionSheet({
    required this.projectId,
    required this.title,
    this.iconUrl,
    this.pageUrl,
    required this.instanceId,
    required this.projectType,
    this.loader,
    this.gameVersion,
    required this.onDownloaded,
  });

  final String projectId;
  final String title;
  final String? iconUrl;
  final String? pageUrl;
  final String instanceId;
  final String projectType;
  final String? loader;
  final String? gameVersion;
  final VoidCallback onDownloaded;

  @override
  ConsumerState<_VersionSheet> createState() => _VersionSheetState();
}

class _VersionSheetState extends ConsumerState<_VersionSheet> {
  List<ModVersion> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final api = ref.read(modsApiProvider);
    if (api == null) {
      if (!mounted) return;
      setState(() {
        _error = '还没有连接到守护进程';
        _loading = false;
      });
      return;
    }
    try {
      final versions = await api.versions(
        projectId: widget.projectId,
        loader: widget.loader,
        gameVersion: widget.gameVersion,
      );
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeModsError(e);
        _loading = false;
      });
    }
  }

  void _showVersionDetail(ModVersion version) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            // `fullscreenDialog: true`：详情页是「盖住一层的弹页」，
            // 标题栏左边是关闭（×）而不是返回箭头
            fullscreenDialog: true,
            builder: (_) => _VersionDetailPage(
              instanceId: widget.instanceId,
              projectType: widget.projectType,
              projectId: widget.projectId,
              title: widget.title,
              iconUrl: widget.iconUrl,
              pageUrl: widget.pageUrl,
              version: version,
              loader: widget.loader,
              gameVersion: widget.gameVersion,
              onDownloaded: () => Navigator.of(context).pop(true),
            ),
          ),
        )
        .then((downloaded) {
          // 版本详情页下载成功后弹回这里（true），再弹回下载页让父页面显示 SnackBar。
          if (mounted && downloaded == true) Navigator.of(context).pop(true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text('搜索失败：$_error'))
                : _versions.isEmpty
                ? const Center(child: Text('未找到结果'))
                : ListView.builder(
                    // 弹层里**没有额外 padding**，行本身也不是 Card
                    // （结果列表那种才套 Card）
                    controller: scrollCtrl,
                    itemCount: _versions.length,
                    itemBuilder: (ctx, i) => _VersionRow(
                      version: _versions[i],
                      onTap: () => _showVersionDetail(_versions[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.version, required this.onTap});

  final ModVersion version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final depCount = version.dependencies
        .where((d) => d.projectId != null && d.projectId!.isNotEmpty)
        .length;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.name.isEmpty ? version.versionNumber : version.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (version.gameVersions.isNotEmpty)
                        _chip(context, version.gameVersions.take(3).join(', ')),
                      if (version.loaders.isNotEmpty)
                        _chip(context, version.loaders.join(', ')),
                      _chip(context, _releaseTypeLabel(version.kind)),
                      if (version.primaryFile != null)
                        _chip(
                          context,
                          formatModSize(version.primaryFile!.size),
                        ),
                      if (depCount > 0) _chip(context, '$depCount 个前置'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

Widget _chip(BuildContext context, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: Theme.of(context).textTheme.bodySmall),
  );
}

String _releaseTypeLabel(String kind) => switch (kind) {
  'release' => '正式版',
  'beta' => '测试版',
  'alpha' => '实验版',
  _ => kind,
};

// ── 版本详情页 ──────────────────────────────────────────────────────

class _VersionDetailPage extends ConsumerStatefulWidget {
  const _VersionDetailPage({
    required this.instanceId,
    required this.projectType,
    required this.projectId,
    required this.title,
    this.iconUrl,
    this.pageUrl,
    required this.version,
    this.loader,
    this.gameVersion,
    required this.onDownloaded,
  });

  final String instanceId;
  final String projectType;
  final String projectId;
  final String title;
  final String? iconUrl;
  final String? pageUrl;
  final ModVersion version;
  final String? loader;
  final String? gameVersion;
  final VoidCallback onDownloaded;

  @override
  ConsumerState<_VersionDetailPage> createState() => _VersionDetailPageState();
}

class _VersionDetailPageState extends ConsumerState<_VersionDetailPage> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = widget.version;
    final file = v.primaryFile;

    final requiredDeps = v.dependencies.where((d) => d.isRequired).toList();
    final optionalDeps = v.dependencies
        .where((d) => d.kind == 'optional')
        .toList();
    final incompatibleDeps = v.dependencies
        .where((d) => d.kind == 'incompatible')
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('版本详情'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _ModIcon(url: widget.iconUrl, loaders: v.loaders),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      v.name.isEmpty ? v.versionNumber : v.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
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
          _sectionCard(
            scheme,
            '版本名称',
            v.name.isEmpty ? v.versionNumber : v.name,
          ),
          _sectionCard(scheme, '版本号', v.versionNumber),
          _sectionCard(
            scheme,
            '发布于 {date}',
            '发布于 ${_formatDate(v.datePublished)}',
          ),
          _sectionCard(scheme, _releaseTypeLabel(v.kind), null, isChip: true),
          if (v.gameVersions.isNotEmpty) ...[
            _sectionTitle(scheme, '游戏版本'),
            _chipWrap(scheme, v.gameVersions),
            const SizedBox(height: 12),
          ],
          if (v.loaders.isNotEmpty) ...[
            _sectionTitle(scheme, '加载器'),
            _chipWrap(scheme, v.loaders),
            const SizedBox(height: 12),
          ],
          if (file != null) ...[
            _sectionTitle(scheme, '文件信息'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(scheme, '文件名', file.filename),
                    const SizedBox(height: 6),
                    _infoRow(scheme, '文件大小', formatModSize(file.size)),
                    if (file.sha1 != null) ...[
                      const SizedBox(height: 6),
                      _infoRow(scheme, 'SHA1', file.sha1!, mono: true),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (requiredDeps.isNotEmpty) ...[
            _sectionTitle(scheme, '前置依赖'),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: requiredDeps
                    .map((d) => _depTile(scheme, d, required: true))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (optionalDeps.isNotEmpty) ...[
            _sectionTitle(scheme, '可选依赖'),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: optionalDeps
                    .map((d) => _depTile(scheme, d, required: false))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (incompatibleDeps.isNotEmpty) ...[
            _sectionTitle(scheme, '不兼容'),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: incompatibleDeps
                    .map(
                      (d) => _depTile(
                        scheme,
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
            _sectionCard(scheme, '前置依赖', '无'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _enqueueDownload,
            icon: const Icon(Icons.download),
            label: const Text('下载此版本'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme scheme, String title) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: scheme.primary),
    ),
  );

  Widget _sectionCard(
    ColorScheme scheme,
    String label,
    String? value, {
    bool isChip = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (isChip)
              _chip(context, value ?? '')
            else if (value != null)
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _chipWrap(ColorScheme scheme, List<String> items) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: items.map((item) => _chip(context, item)).toList(),
  );

  Widget _infoRow(
    ColorScheme scheme,
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  )
                : Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _depTile(
    ColorScheme scheme,
    ModDependency dep, {
    required bool required,
    bool incompatible = false,
  }) {
    final label = dep.projectId != null && dep.projectId!.isNotEmpty
        ? (dep.fileName ?? dep.projectId!)
        : '未知模组';
    final canNavigate = dep.projectId != null && dep.projectId!.isNotEmpty;
    return ListTile(
      leading: Icon(
        incompatible
            ? Icons.block
            : required
            ? Icons.priority_high
            : Icons.low_priority,
        color: incompatible
            ? scheme.error
            : required
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: canNavigate && dep.projectId != null
          ? Text(
              dep.projectId!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          : null,
      trailing: canNavigate ? const Icon(Icons.chevron_right) : null,
      onTap: canNavigate && dep.projectId != null
          ? () => _openDependency(projectId: dep.projectId!, title: label)
          : null,
    );
  }

  /// 打开依赖项目的版本选择弹层。
  void _openDependency({required String projectId, required String title}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _VersionSheet(
        projectId: projectId,
        title: title,
        instanceId: widget.instanceId,
        projectType: widget.projectType,
        loader: widget.loader,
        gameVersion: widget.gameVersion,
        onDownloaded: () => Navigator.of(context).pop(true),
      ),
    ).then((downloaded) {
      // 依赖弹层里下载成功 → 这里显示「已加入下载队列」提示
      // （依赖下载的 SnackBar 由打开它的详情页显示）。
      if (downloaded == true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入下载队列')));
      }
    });
  }

  /// 提交 `mods-install` 工作流（V2 的「下载」落地方式）。
  ///
  /// 外链文件（daemon 没给可下载 url）无法直连下载，提示前往官网。
  Future<void> _enqueueDownload() async {
    final file = widget.version.primaryFile;
    if (file == null) return;

    if (file.url.isEmpty) {
      await _showExternalDialog();
      return;
    }

    final api = ref.read(taskApiProvider);
    if (api == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('下载失败：还没有连接到守护进程')));
      return;
    }

    try {
      await api.submit('mods-install', {
        'instance_id': widget.instanceId,
        'project_id': widget.projectId,
        'project_type': widget.projectType,
        'version_id': widget.version.id,
        'loader': widget.loader,
        'game_version': widget.gameVersion,
      });
      if (!mounted) return;
      // 不在此处显示 SnackBar：详情页的 context 即将随页面 pop 失效，
      // 由父页面（下载页）在弹层关闭后的 .then() 用稳定 context 显示。
      widget.onDownloaded();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：${describeModsError(e)}')));
    }
  }

  Future<void> _showExternalDialog() async {
    final url = widget.pageUrl ?? '-';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需前往官网下载'),
        content: SingleChildScrollView(
          child: Text('该资源由作者托管在站外，无法直接下载。请前往官网获取：\n$url'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── 下载队列横幅 ────────────────────────────────────────────────────

/// 下载队列状态横幅。读 daemon 的 `download.*` 队列（[downloadListStreamProvider]），
/// 只显示属于当前实例的任务；有任务时显示。
///
/// [instanceId] 不传时取当前选中的实例（[selectedInstanceIdProvider]），
/// 这样「模组/插件管理」页里也能直接用它（横幅挂在管理页）。
class DownloadQueueBanner extends ConsumerStatefulWidget {
  const DownloadQueueBanner({super.key, this.instanceId});

  final String? instanceId;

  @override
  ConsumerState<DownloadQueueBanner> createState() =>
      _DownloadQueueBannerState();
}

class _DownloadQueueBannerState extends ConsumerState<DownloadQueueBanner> {
  @override
  Widget build(BuildContext context) {
    final instanceId =
        widget.instanceId ?? ref.watch(selectedInstanceIdProvider);
    if (instanceId == null) return const SizedBox.shrink();

    final list = ref.watch(downloadListStreamProvider);
    final tasks = list.tasks.where((t) => t.instanceId == instanceId).toList();
    if (tasks.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final current = _currentTask(tasks);
    final pending = tasks.where((t) => t.state == DownloadState.queued).length;
    final completed = tasks
        .where((t) => t.state == DownloadState.completed)
        .length;
    final failed = tasks.where((t) => t.state == DownloadState.error).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => showDownloadQueueSheet(context, instanceId),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (current != null)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: current.fraction == null
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : CircularProgressIndicator(
                            value: current.fraction,
                            strokeWidth: 2,
                          ),
                  )
                else
                  Icon(Icons.download_done, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (current != null)
                        Text(
                          _bannerTitle(current),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        )
                      else
                        Text(
                          '下载队列为空',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      if (pending > 0 || completed > 0 || failed > 0)
                        Text(
                          [
                            if (pending > 0) '等待中 $pending',
                            if (completed > 0) '已完成 $completed',
                            if (failed > 0) '失败 $failed',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bannerTitle(DownloadTask task) {
    final title = task.filename ?? task.target ?? '下载任务';
    final parts = <String>[title];
    if (task.fraction != null) {
      parts.add('${(task.fraction! * 100).toInt()}%');
    }
    if (task.downloadSpeed > 0) parts.add(formatSpeed(task.downloadSpeed));
    return parts.join(' · ');
  }

  DownloadTask? _currentTask(List<DownloadTask> tasks) {
    for (final t in tasks) {
      if (t.state == DownloadState.downloading ||
          t.state == DownloadState.connecting ||
          t.state == DownloadState.verifying ||
          t.state == DownloadState.seeding ||
          t.state == DownloadState.paused) {
        return t;
      }
    }
    return null;
  }
}

void showDownloadQueueSheet(BuildContext context, String instanceId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _QueueSheet(instanceId: instanceId),
  );
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = ref.watch(downloadListStreamProvider);
    final tasks = list.tasks
        .where((t) => t.instanceId == widget.instanceId)
        .toList()
        .reversed
        .toList();

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
                    '下载队列',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // daemon 的 download 模块还没有 clear/cancel，按约定置灰。
                TextButton(onPressed: null, child: const Text('清除已结束')),
                TextButton(onPressed: null, child: const Text('全部取消')),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: tasks.isEmpty
                ? const Center(child: Text('下载队列为空'))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: tasks.length,
                    itemBuilder: (ctx, i) => _QueueTile(task: tasks[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = switch (task.state) {
      DownloadState.downloading ||
      DownloadState.connecting ||
      DownloadState.verifying ||
      DownloadState.seeding ||
      DownloadState.paused => scheme.primary,
      DownloadState.completed => scheme.primary,
      DownloadState.error => scheme.error,
      DownloadState.queued => scheme.onSurfaceVariant,
      _ => scheme.onSurfaceVariant,
    };
    final statusIcon = switch (task.state) {
      DownloadState.downloading ||
      DownloadState.connecting ||
      DownloadState.verifying ||
      DownloadState.seeding ||
      DownloadState.paused => Icons.downloading,
      DownloadState.completed => Icons.check_circle,
      DownloadState.error => Icons.error_outline,
      DownloadState.queued => Icons.schedule,
      _ => Icons.help,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(statusIcon, size: 20, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.filename ?? task.target ?? '下载任务',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (task.state == DownloadState.downloading) ...[
                    const SizedBox(height: 4),
                    task.fraction == null
                        ? const LinearProgressIndicator()
                        : LinearProgressIndicator(value: task.fraction),
                  ] else if (task.state == DownloadState.error &&
                      task.error?.message != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.error!.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                  if (task.state == DownloadState.downloading &&
                      task.fraction != null &&
                      task.downloadSpeed > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatRateEta(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // daemon 的 download 模块还没有 cancel/remove，按约定置灰。
            IconButton(
              onPressed: null,
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRateEta(DownloadTask task) {
  final speed = formatSpeed(task.downloadSpeed);
  final eta = formatEta(task.etaSeconds);
  return eta.isEmpty ? speed : '$speed · $eta';
}
