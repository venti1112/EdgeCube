import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import '../files/providers.dart';
import '../instance/providers.dart';
import '../settings/appearance.dart';
import '../shell/glass.dart';
import '../task/api.dart';
import '../task/models.dart';
import '../task/providers.dart';
import 'api.dart';
import 'client_mods_cleanup_dialog.dart';
import 'mod_download_page.dart';
import 'models.dart';
import 'providers.dart';

/// 「模组/插件管理」。
///
/// 页面结构：
///
/// * 外层 `Scaffold` + `AppBar(title:, bottom: TabBar)`。
/// * 标签数 = `(hasPlugins ? 2 : 0) + (hasMods ? 2 : 0)`，顺序「插件管理 /
///   插件下载（或 Poggit 插件）/ 模组管理 / 模组下载」（`DefaultTabController`，
///   key 带目录签名，目录一变就重建）。
/// * `_ModsTab`（管理标签）与 `ModDownloadPage(embedded: true)`（下载标签）
///   挂在 `TabBarView` 里。
/// * 一个目录都没有 → `_EmptyState(extension_outlined, '暂无模组/插件目录', …)`。
/// * 启用/禁用是「改名 `.disabled`」，删除与启停都有确认框，图标来自 SHA1 反查
///   Modrinth（改名、确认框、图标都由 daemon 提供）。
///
/// **架构分工**：
///
/// * jar 元数据、SHA1、Modrinth 请求全部由 daemon 做，本页只发 RPC
///   （`mods.installed` / `mods.match_projects` / `mods.check_updates` …）。
/// * 点「更新」提交 `mods-install` 工作流（下载在 daemon）：行上转圈、
///   装完列表自己刷新。
/// * 「清理客户端模组」的判据（`environment == client`）由 daemon 解析 jar 得到。
class ModsPage extends ConsumerStatefulWidget {
  const ModsPage({super.key});

  @override
  ConsumerState<ModsPage> createState() => _ModsPageState();
}

class _ModsPageState extends ConsumerState<ModsPage> {
  @override
  void initState() {
    super.initState();
    // **每次进页面都重扫一遍目录**：重新探测 plugins/ mods/ 在不在，
    // 再重列一遍目录。
    //
    // 为什么需要显式作废：`installedModsProvider` 故意**不是** autoDispose
    // （那是为了「标签之间来回滑不重扫」）。
    // 代价就是它会一直缓存着上次的结果 —— 用户在别处新建了 mods/ 再回来，
    // 不显式作废就永远看到「暂无模组/插件目录」。
    ref.invalidate(installedModsProvider);
    ref.invalidate(modMatchesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final instance = ref.watch(selectedInstanceDetailProvider).value?.instance;
    final connected = ref.watch(isConnectedProvider);

    if (instance == null) {
      return _Scaffold(
        body: _EmptyState(
          icon: Icons.extension_outlined,
          title: connected ? '还没有实例' : '未连接到守护进程',
          description: connected ? '先在「服务器」页选一个实例。' : '检查一下连接设置。',
        ),
      );
    }

    return ref
        .watch(installedModsProvider(instance.id))
        .when(
          loading: () => const _Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _Scaffold(
            body: _EmptyState(
              icon: Icons.error_outline,
              title: '读取失败',
              description: describeModsError(error),
            ),
          ),
          data: (data) => _ModsTabs(instanceId: instance.id, installed: data),
        );
  }
}

/// 外层脚手架（标题栏在 `_ModsTabs` 里另画，因为它要带标签条）。
///
/// 底色透明 + 关掉 surfaceTint / scrolledUnderElevation 是必须的：
/// 毛玻璃在外壳 `home_shell.dart` 上，页面自身不透明就会盖住 `BackdropFilter`。
class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('模组/插件管理'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: body,
    );
  }
}

/// 按「目录存不存在」决定标签与内容。
///
/// **标签清单与视图清单在同一个函数里生成**：`TabBar` 与 `TabBarView`
/// 都在同一处按 `if (_hasPlugins) / if (_hasMods)` 展开 ——
/// 分两处算迟早会漂（多一个少一个就对不上）。
class _ModsTabs extends StatelessWidget {
  const _ModsTabs({required this.instanceId, required this.installed});

  final String instanceId;
  final InstalledMods installed;

  @override
  Widget build(BuildContext context) {
    final hasPlugins = installed.dir('plugin')?.exists ?? false;
    final hasMods = installed.dir('mod')?.exists ?? false;
    final pmmp = installed.pmmp;

    // plugins 管理 + 下载；mods 管理 + 下载
    final count = (hasPlugins ? 2 : 0) + (hasMods ? 2 : 0);

    final tabs = <Tab>[
      if (hasPlugins) const Tab(text: '插件管理'),
      if (hasPlugins) Tab(text: pmmp ? 'Poggit 插件' : '插件下载'),
      if (hasMods) const Tab(text: '模组管理'),
      if (hasMods) const Tab(text: '模组下载'),
    ];

    final views = <Widget>[
      if (hasPlugins)
        _ModsTab(instanceId: instanceId, projectType: 'plugin', pmmp: pmmp),
      if (hasPlugins)
        // PMMP 走 Poggit（`.phar` 插件源），Java 系走 Modrinth。
        // **Poggit 数据源还没接**（依赖 daemon 的 Poggit 客户端），
        // 按项目约定摆出来并置灰，不藏起来。
        pmmp
            ? const _EmptyState(
                icon: Icons.extension_outlined,
                title: 'Poggit 插件',
                description: 'Poggit 插件源（PocketMine）依赖 daemon 的 Poggit 客户端，尚未接入。',
              )
            : ModDownloadPage(
                projectType: 'plugin',
                instanceId: instanceId,
                embedded: true,
              ),
      if (hasMods)
        _ModsTab(instanceId: instanceId, projectType: 'mod', pmmp: false),
      if (hasMods)
        ModDownloadPage(
          projectType: 'mod',
          instanceId: instanceId,
          embedded: true,
        ),
    ];

    if (count == 0) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('模组/插件管理'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: const _EmptyState(
          icon: Icons.extension_outlined,
          title: '暂无模组/插件目录',
          description: '当前实例目录下未发现 plugins 或 mods 文件夹。',
        ),
      );
    }

    // `DefaultTabController` 必须包住 `AppBar` 里的 `TabBar`（不只是 body 的
    // `TabBarView`），否则 `TabBar` 找不到控制器。key 带目录签名：第一次装模组
    // 时 `mods/` 才出现、标签数从 0 变 4，不重建的话控制器长度对不上。
    return DefaultTabController(
      key: ValueKey('mods-tabs-$hasPlugins-$hasMods-$pmmp'),
      length: count,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('模组/插件管理'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          bottom: TabBar(
            // 四个中文标签在手机宽度下放不下 → 可以左右滑
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 20),
            tabs: tabs,
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

/// 一个「管理」标签：文件列表 + 顶部的计数与操作按钮。
///
/// 结构：`Column[ _Header, DownloadQueueBanner,
/// if (有更新) _UpdateBanner, Expanded(列表 / 空态) ]`。
class _ModsTab extends ConsumerStatefulWidget {
  const _ModsTab({
    required this.instanceId,
    required this.projectType,
    required this.pmmp,
  });

  final String instanceId;
  final String projectType;
  final bool pmmp;

  @override
  ConsumerState<_ModsTab> createState() => _ModsTabState();
}

class _ModsTabState extends ConsumerState<_ModsTab> {
  /// 「检查更新」的结果，按**文件名**索引。
  ModUpdateReport? _updates;

  bool _checkingUpdates = false;
  bool _cleaningMods = false;
  bool _importing = false;

  /// 文件名 → 正在跑的那次更新的任务 id。
  ///
  /// V2 的下载在 daemon，得拿着任务 id 才知道什么时候结束。
  final _updateTasks = <String, String>{};

  /// 任务结束的订阅（跑完就取消）。
  final _updateSubs = <String, ProviderSubscription<TaskView?>>{};

  /// 目录后缀：PMMP 认 `.phar`，Java 系认 `.jar`。
  List<String> get _exts => widget.pmmp ? const ['phar'] : const ['jar'];

  /// 这个文件算不算「该管的插件文件」。
  bool _isPluginFile(String name) {
    final lower = name.toLowerCase();
    return _exts.any(
      (ext) => lower.endsWith('.$ext') || lower.endsWith('.$ext.disabled'),
    );
  }

  @override
  void dispose() {
    for (final sub in _updateSubs.values) {
      sub.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedModsProvider(widget.instanceId));
    final dir = installed.value?.dir(widget.projectType);
    final matches =
        ref
            .watch(
              modMatchesProvider((
                instanceId: widget.instanceId,
                projectType: widget.projectType,
              )),
            )
            .value ??
        ModMatchReport.empty;

    // 只列「该管的插件文件」，别的文件不显示
    final files = (dir?.files ?? const <InstalledMod>[])
        .where((file) => _isPluginFile(file.fileName))
        .toList(growable: false);

    return Column(
      children: [
        _Header(
          count: files.length,
          // 检查更新与「客户端模组清理」只对 Java 系显示
          canCheckUpdates: !widget.pmmp,
          checkingUpdates: _checkingUpdates,
          cleaningMods: _cleaningMods,
          importing: _importing,
          onCheckUpdates: _checkUpdates,
          onCleanup: _showClientModsCleanup,
          onRefresh: () {
            ref.invalidate(installedModsProvider);
            ref.invalidate(modMatchesProvider);
          },
          onImport: _import,
        ),
        const DownloadQueueBanner(),
        if (_updates != null && _updates!.updates.isNotEmpty)
          _UpdateBanner(
            count: _updates!.updateCount,
            onSelect: _showUpdateSelection,
          ),
        Expanded(
          child: files.isEmpty
              ? const _EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '暂无内容',
                  description: '点击右上角按钮导入文件。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final update = _updates?.byFileName[file.fileName];
                    return _ModCard(
                      file: file,
                      iconUrl: matches.byFileName[file.fileName]?.iconUrl,
                      hasUpdate: update?.hasUpdate ?? false,
                      updating: _updateTasks.containsKey(file.fileName),
                      onToggle: () => _toggleEnabled(file),
                      onUpdate: () => _updateMod(file),
                      onDelete: () => _delete(file),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── 检查更新 ──────────────────────────────────────────────────────────

  /// 把已装文件的 SHA1 交给 daemon，它去和上游比。
  ///
  /// 算哈希要整读一遍文件，所以这是**用户主动点**的动作。
  Future<void> _checkUpdates() async {
    final api = ref.read(modsApiProvider);
    if (api == null || _checkingUpdates) return;

    setState(() {
      _checkingUpdates = true;
      _updates = null;
    });
    try {
      final report = await api.checkUpdates(
        instanceId: widget.instanceId,
        projectType: widget.projectType,
      );
      if (!mounted) return;
      setState(() {
        _checkingUpdates = false;
        _updates = report;
      });
      _snack(
        report.updateCount == 0 ? '所有模组均为最新' : '${report.updateCount} 个模组可更新',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _checkingUpdates = false);
      await _showError('搜索失败：${describeModsError(error)}');
    }
  }

  /// 选中要更新的条目（默认全选），确认后逐个提交。
  ///
  /// 全选 / 取消全选、复选框列表
  /// （副行是「旧版本 新版本」）、取消 / `更新选中 (N)`。
  Future<void> _showUpdateSelection() async {
    final report = _updates;
    if (report == null) return;

    final files =
        ref.read(installedModsProvider(widget.instanceId)).value
            ?.dir(widget.projectType)
            ?.files ??
        const <InstalledMod>[];

    final updatable = <MapEntry<InstalledMod, ModVersion>>[];
    for (final entry in report.byFileName.entries) {
      final latest = entry.value.latest;
      if (!entry.value.hasUpdate || latest == null) continue;
      final file = files.where((f) => f.fileName == entry.key).firstOrNull;
      if (file != null) updatable.add(MapEntry(file, latest));
    }
    if (updatable.isEmpty) return;

    final selected = <String, bool>{
      for (final entry in updatable) entry.key.fileName: true,
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final selectedCount = selected.values.where((v) => v).length;
          final allSelected = selected.values.every((v) => v);
          final noneSelected = !selected.values.any((v) => v);
          return AlertDialog(
            title: const Text('选择更新'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: allSelected
                            ? null
                            : () => setDialogState(() {
                                for (final key in selected.keys) {
                                  selected[key] = true;
                                }
                              }),
                        child: const Text('全选'),
                      ),
                      TextButton(
                        onPressed: noneSelected
                            ? null
                            : () => setDialogState(() {
                                for (final key in selected.keys) {
                                  selected[key] = false;
                                }
                              }),
                        child: const Text('取消全选'),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: updatable.length,
                      itemBuilder: (context, index) {
                        final file = updatable[index].key;
                        final version = updatable[index].value;
                        final meta = file.meta;
                        final name = meta?.displayName ?? file.displayName;
                        final oldVersion = meta?.version ?? '?';
                        final newVersion = version.name.isEmpty
                            ? version.versionNumber
                            : version.name;
                        return CheckboxListTile(
                          value: selected[file.fileName] ?? false,
                          onChanged: (value) => setDialogState(
                            () => selected[file.fileName] = value ?? false,
                          ),
                          title: Text(name),
                          subtitle: Text('$oldVersion $newVersion'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selectedCount == 0
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: Text('更新选中 ($selectedCount)'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    for (final entry in updatable) {
      if (selected[entry.key.fileName] == true) {
        await _updateMod(entry.key);
      }
    }
  }

  /// 更新一个模组：提交 `mods-install`，行上转圈，装完刷新列表。
  ///
  /// 替换也在 daemon（`mods.download` 步骤会在下载成功后删掉被替换的旧版本）：
  /// 行上转圈 → 列表刷新成新版本。
  Future<void> _updateMod(InstalledMod file) async {
    final latest = _updates?.byFileName[file.fileName]?.latest;
    if (latest == null || _updateTasks.containsKey(file.fileName)) return;

    final tasks = ref.read(taskApiProvider);
    if (tasks == null) {
      await _showError('还没有连接到守护进程');
      return;
    }

    setState(() => _updateTasks[file.fileName] = '');
    try {
      final task = await tasks.submit('mods-install', {
        'instance_id': widget.instanceId,
        'project_id': latest.projectId,
        'project_type': widget.projectType,
        'version_id': latest.id,
      });
      if (!mounted) return;
      setState(() => _updateTasks[file.fileName] = task.id);
      _watchUpdate(file, task.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _updateTasks.remove(file.fileName));
      final message = error is DaemonException
          ? describeTaskError(error)
          : '$error';
      await _showError('更新失败：$message');
    }
  }

  /// 盯着那次更新的任务，跑到终态就收尾。
  void _watchUpdate(InstalledMod file, String taskId) {
    _updateSubs[file.fileName]?.close();
    _updateSubs[file.fileName] = ref.listenManual<TaskView?>(
      taskProvider(taskId),
      (previous, next) {
        final task = next;
        if (task == null || !task.state.isFinished) return;
        _updateSubs.remove(file.fileName)?.close();
        if (!mounted) return;
        setState(() => _updateTasks.remove(file.fileName));
        ref.invalidate(installedModsProvider);
        if (task.state == TaskState.failed) {
          final step = task.steps
              .where((step) => step.status == TaskStepStatus.failed)
              .firstOrNull;
          _snack('更新失败：${stepErrorText(step?.error ?? task.errorMessage)}');
        } else if (task.state == TaskState.completed) {
          _snack('更新完成');
        }
      },
    );
  }

  // ── 启用 / 禁用 ──────────────────────────────────────────────────────

  /// 改名（`.jar` ↔ `.jar.disabled`）。**有确认框**。
  Future<void> _toggleEnabled(InstalledMod file) async {
    final api = ref.read(modsApiProvider);
    if (api == null) return;
    final isDisabled = !file.enabled;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isDisabled ? '确认启用' : '确认禁用'),
        content: Text(file.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isDisabled ? '启用' : '禁用'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await api.setEnabled(
        instanceId: widget.instanceId,
        projectType: widget.projectType,
        fileName: file.fileName,
        enabled: isDisabled,
      );
      if (!mounted) return;
      ref.invalidate(installedModsProvider);
      ref.invalidate(modMatchesProvider);
    } catch (error) {
      if (!mounted) return;
      await _showError(
        isDisabled
            ? '启用失败：${describeModsError(error)}'
            : '禁用失败：${describeModsError(error)}',
      );
    }
  }

  // ── 删除 ──────────────────────────────────────────────────────────────

  Future<void> _delete(InstalledMod file) async {
    final api = ref.read(modsApiProvider);
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${file.fileName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await api.remove(
        instanceId: widget.instanceId,
        projectType: widget.projectType,
        fileName: file.fileName,
      );
      if (!mounted) return;
      setState(() => _updates = null);
      ref.invalidate(installedModsProvider);
      ref.invalidate(modMatchesProvider);
    } catch (error) {
      if (!mounted) return;
      await _showError('删除失败：${describeModsError(error)}');
    }
  }

  // ── 导入文件 ──────────────────────────────────────────────────────────

  /// 从本机选一个 `.jar`（PMMP 是 `.phar`）传进实例目录：选完走 daemon 的
  /// HTTP 上传（文件在服务端机器上，前端只能把字节送过去）。
  Future<void> _import() async {
    if (_importing) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _exts,
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;

    setState(() => _importing = true);
    try {
      await ref.read(fileTransferProvider)!.upload(
        widget.instanceId,
        dir: widget.projectType == 'plugin' ? 'plugins' : 'mods',
        name: file.name,
        content: file.readAsByteStream(),
        length: file.lengthSync(),
      );
      if (!mounted) return;
      ref.invalidate(installedModsProvider);
      ref.invalidate(modMatchesProvider);
      _snack('导入完成');
    } catch (error) {
      if (!mounted) return;
      await _showError('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── 客户端模组清理 ────────────────────────────────────────────────────

  /// 「客户端专属模组」= 元数据里 `environment == client`（daemon 给的）。
  ///
  /// 元数据缺失（`unknown`）的**不列入**，避免误删服务端模组 ——
  /// V2 直接读 `mods.installed`（jar 由 daemon 解析）。
  Future<void> _showClientModsCleanup() async {
    final api = ref.read(modsApiProvider);
    if (api == null || _cleaningMods) return;

    final installed = ref.read(installedModsProvider(widget.instanceId)).value;
    final clientMods = (installed?.dir('mod')?.files ?? const <InstalledMod>[])
        .where((file) => file.meta?.isClientOnly ?? false)
        .toList(growable: false);

    setState(() => _cleaningMods = true);
    final result = await showClientModsCleanupDialog(
      context,
      api: api,
      instanceId: widget.instanceId,
      mods: clientMods,
    );
    if (!mounted) return;
    setState(() => _cleaningMods = false);

    if (result == null) {
      _snack('未找到可识别的客户端模组');
    } else if (result) {
      ref.invalidate(installedModsProvider);
      ref.invalidate(modMatchesProvider);
    }
  }

  // ── 小工具 ────────────────────────────────────────────────────────────

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('出错了'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 顶部一行：`共 N 项` + 右侧四个按钮（检查更新 / 清理客户端模组 / 刷新 / 导入）。
///
/// `EdgeInsets.fromLTRB(16, 12, 4, 4)`，按钮忙时换成同尺寸的转圈。
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.canCheckUpdates,
    required this.checkingUpdates,
    required this.cleaningMods,
    required this.importing,
    required this.onCheckUpdates,
    required this.onCleanup,
    required this.onRefresh,
    required this.onImport,
  });

  final int count;
  final bool canCheckUpdates;
  final bool checkingUpdates;
  final bool cleaningMods;
  final bool importing;
  final VoidCallback onCheckUpdates;
  final VoidCallback onCleanup;
  final VoidCallback onRefresh;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          Text('共 $count 项', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (canCheckUpdates) ...[
            _BusyIconButton(
              busy: checkingUpdates,
              icon: Icons.system_update,
              tooltip: '检查更新',
              onPressed: onCheckUpdates,
            ),
            _BusyIconButton(
              busy: cleaningMods,
              icon: Icons.cleaning_services_outlined,
              tooltip: '清理客户端模组',
              onPressed: onCleanup,
            ),
          ],
          _BusyIconButton(
            busy: false,
            icon: Icons.refresh,
            tooltip: '刷新',
            onPressed: onRefresh,
          ),
          _BusyIconButton(
            busy: importing,
            icon: Icons.add,
            tooltip: '导入文件',
            onPressed: onImport,
            busyPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ],
      ),
    );
  }
}

/// 一个图标按钮；忙的时候原地换成转圈。
class _BusyIconButton extends StatelessWidget {
  const _BusyIconButton({
    required this.busy,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busyPadding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final bool busy;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final EdgeInsets busyPadding;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return Padding(
        padding: busyPadding,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
    );
  }
}

/// 「N 个模组可更新」横幅 + 「选择更新」。
///
/// primaryContainer 底、圆角 8、
/// `margin: symmetric(horizontal: 16, vertical: 4)`、
/// `padding: symmetric(horizontal: 12, vertical: 8)`。
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.count, required this.onSelect});

  final int count;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.update, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count 个模组可更新',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: onSelect, child: const Text('选择更新')),
        ],
      ),
    );
  }
}

/// 列表里的一张卡。
///
/// 左侧 40×40 图标 →（16 间距）→ 主行 + 可选副行
/// → 右侧按钮组（启用/禁用、更新、删除）。禁用过的整卡变灰、标题带删除线。
class _ModCard extends ConsumerWidget {
  const _ModCard({
    required this.file,
    required this.iconUrl,
    required this.hasUpdate,
    required this.updating,
    required this.onToggle,
    required this.onUpdate,
    required this.onDelete,
  });

  final InstalledMod file;
  final String? iconUrl;
  final bool hasUpdate;
  final bool updating;
  final VoidCallback onToggle;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = !file.enabled;
    // 毛玻璃模式下不写死颜色:交给主题的玻璃卡(半透明),禁用态再压暗一档,
    // 保留「灰一档」的区分。
    final glass = ref.watch(glassModeEnabledProvider);
    final Color? color = glass
        ? (disabled ? glassEntryFill(scheme, alpha: 0.28) : null)
        : (disabled ? scheme.surfaceContainer : scheme.surface);

    return Card(
      margin: EdgeInsets.zero,
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _LeadingIcon(url: iconUrl, meta: file.meta),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: disabled
                        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                  if (file.subtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: disabled
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: disabled ? '启用' : '禁用',
                  iconSize: 20,
                  icon: Icon(
                    disabled ? Icons.check_circle_outline : Icons.block,
                    color: disabled ? scheme.onSurfaceVariant : scheme.primary,
                  ),
                  onPressed: onToggle,
                ),
                if (hasUpdate && !disabled)
                  updating
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: '更新',
                          iconSize: 20,
                          icon: Icon(Icons.update, color: scheme.primary),
                          onPressed: onUpdate,
                        ),
                IconButton(
                  tooltip: '删除',
                  iconSize: 20,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表左侧那个 40×40 的图标。
///
/// 三级回退：Modrinth 图标 → 按加载器上色的方块 →
/// 通用扩展图标。
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.url, required this.meta});

  final String? url;
  final ModMeta? meta;

  @override
  Widget build(BuildContext context) {
    final fallback = meta != null
        ? _LoaderBox(meta: meta!)
        : const Icon(Icons.extension_outlined, size: 32);
    final url = this.url;
    if (url == null || url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // 图挂了（外网 / CDN 被挡）不该把整行炸了，退回彩色方块
        errorBuilder: (context, error, stack) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 按加载器上色的方块。
class _LoaderBox extends StatelessWidget {
  const _LoaderBox({required this.meta});

  final ModMeta meta;

  @override
  Widget build(BuildContext context) {
    final color = switch (meta.loader) {
      'fabric' => const Color.fromARGB(255, 221, 170, 255),
      'forge' => const Color.fromARGB(255, 255, 170, 107),
      'quilt' => const Color.fromARGB(255, 170, 221, 255),
      'neoforge' => const Color.fromARGB(255, 255, 107, 107),
      'bukkit' => const Color.fromARGB(255, 170, 255, 170),
      'bungeecord' => const Color.fromARGB(255, 255, 221, 107),
      'velocity' => const Color.fromARGB(255, 107, 221, 255),
      'pocketmine' => const Color.fromARGB(255, 170, 255, 221),
      _ => Theme.of(context).colorScheme.surfaceContainerHighest,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.extension, size: 24, color: Colors.white),
    );
  }
}

/// 空态 / 占位：图标 48 + 12 + 标题 + 4 + 说明。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              description,
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
}
