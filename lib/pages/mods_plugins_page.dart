import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../files/file_entry.dart';
import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../mods/download_queue.dart';
import '../mods/icon_cache.dart';
import '../mods/mod_metadata.dart';
import '../mods/modrinth_service.dart';
import 'mod_download_page.dart';

/// 模组/插件管理页：根据实例目录下是否存在 plugins / mods 文件夹，
/// 动态显示对应选项卡。
///
/// - plugins 文件夹 → 插件管理选项卡
/// - mods 文件夹 → 模组管理选项卡 + 模组下载选项卡
///
/// 模组管理支持：识别 .jar 元数据、从 Modrinth 获取图标、检查并执行更新。
/// 模组下载支持：搜索/浏览 Modrinth、筛选、分页。
class ModsPluginsPage extends StatefulWidget {
  const ModsPluginsPage({super.key});

  @override
  State<ModsPluginsPage> createState() => _ModsPluginsPageState();
}

class _ModsPluginsPageState extends State<ModsPluginsPage>
    with SingleTickerProviderStateMixin {
  static const _kPlugins = 'plugins';
  static const _kMods = 'mods';

  bool _detected = false;
  bool _loading = true;
  bool _hasPlugins = false;
  bool _hasMods = false;
  Directory? _pluginsDir;
  Directory? _modsDir;
  TabController? _tabCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_detected) {
      _detected = true;
      _detect();
    }
  }

  Future<void> _detect() async {
    final ctrl = InstanceScope.of(context);
    final instance = ctrl.selected;
    if (instance == null) {
      if (mounted) {
        setState(() {
          _hasPlugins = false;
          _hasMods = false;
          _loading = false;
        });
      }
      return;
    }
    final dir = await ctrl.directoryFor(instance);
    final plugins = Directory(p.join(dir.path, _kPlugins));
    final mods = Directory(p.join(dir.path, _kMods));
    final hasPlugins = plugins.existsSync();
    final hasMods = mods.existsSync();

    _tabCtrl?.dispose();
    // plugins → 管理选项卡 + 下载选项卡；mods → 管理选项卡 + 下载选项卡
    final count = (hasPlugins ? 2 : 0) + (hasMods ? 2 : 0);
    _tabCtrl = count > 0 ? TabController(length: count, vsync: this) : null;

    if (!mounted) return;
    setState(() {
      _hasPlugins = hasPlugins;
      _hasMods = hasMods;
      _pluginsDir = hasPlugins ? plugins : null;
      _modsDir = hasMods ? mods : null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('modsPlugins.title')),
        bottom: _tabCtrl == null
            ? null
            : TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  if (_hasPlugins)
                    Tab(text: context.tr('modsPlugins.tab.plugins')),
                  if (_hasPlugins)
                    Tab(text: context.tr('modsPlugins.tab.downloadPlugin')),
                  if (_hasMods) Tab(text: context.tr('modsPlugins.tab.mods')),
                  if (_hasMods)
                    Tab(text: context.tr('modsPlugins.tab.download')),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tabCtrl == null
          ? _emptyState(
              theme,
              Icons.extension_outlined,
              context.tr('modsPlugins.noFolder.title'),
              context.tr('modsPlugins.noFolder.desc'),
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                if (_hasPlugins && _pluginsDir != null)
                  _ContentTab(folder: _pluginsDir!, isJarContent: true),
                if (_hasPlugins && _pluginsDir != null)
                  ModDownloadPage(
                    modsFolder: _pluginsDir!,
                    embedded: true,
                    projectType: 'plugin',
                    titleKey: 'modsPlugins.downloadPlugin',
                  ),
                if (_hasMods && _modsDir != null)
                  _ContentTab(folder: _modsDir!, isJarContent: true),
                if (_hasMods && _modsDir != null)
                  ModDownloadPage(modsFolder: _modsDir!, embedded: true),
              ],
            ),
    );
  }
}

/// 单个选项卡内容。
///
/// [isJarContent] 为 true 时启用模组/插件识别、图标获取与更新功能。
class _ContentTab extends StatefulWidget {
  const _ContentTab({required this.folder, this.isJarContent = false});
  final Directory folder;
  final bool isJarContent;

  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> {
  static const _service = FileService();

  // 文件列表
  List<FileEntry> _entries = [];
  bool _loading = true;
  bool _importing = false;

  // 模组识别
  final Map<String, ModMetadata?> _metadata = {};

  // 模组图标（path → iconUrl）
  final Map<String, String?> _icons = {};

  // 更新检查
  final Map<String, String> _sha1Hashes = {}; // path → sha1
  final Map<String, ModrinthVersion> _updates = {}; // path → 最新版本
  bool _checkingUpdates = false;
  final Set<String> _updatingPaths = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 加载文件列表 ──────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _service.list(widget.folder);
    if (!mounted) return;
    // 仅显示根目录下的 .jar 和 .jar.disabled 文件
    final jars = entries.where((e) => e.isFile && _isJar(e.name)).toList();
    setState(() {
      _entries = jars;
      _loading = false;
      _metadata.clear();
      _icons.clear();
      _sha1Hashes.clear();
      _updates.clear();
    });
    if (widget.isJarContent) {
      _identifyMods();
    }
  }

  // ── 模组识别 ──────────────────────────────────────────────────

  /// 单个 jar 解析失败时返回 null，避免异常中断批量处理。
  Future<ModMetadata?> _safeParse(String path) async {
    try {
      return await ModMetadataParser.parse(path);
    } catch (_) {
      return null;
    }
  }

  /// 分批并行解析模组元数据，每批完成后统一 setState，避免频繁重建列表。
  Future<void> _identifyMods() async {
    final jars = _entries.where((e) => e.isFile && _isJar(e.name)).toList();
    if (jars.isEmpty) return;

    // 每批并行解析 6 个：平衡 isolate 开销与 UI 响应
    const batchSize = 6;
    for (var i = 0; i < jars.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, jars.length);
      final batch = jars.sublist(i, end);
      final results = await Future.wait(batch.map((e) => _safeParse(e.path)));
      if (!mounted) return;
      setState(() {
        for (var j = 0; j < batch.length; j++) {
          _metadata[batch[j].path] = results[j];
        }
      });
    }
    // 识别完成后获取模组图标
    if (mounted) _fetchModIcons(jars);
  }

  // ── 获取模组图标 ──────────────────────────────────────────────

  /// 安全计算 SHA1，失败时返回空串占位。
  Future<(String, String)> _safeSha1(String path) async {
    try {
      final hash = await ModrinthService.computeSha1(path);
      return (path, hash);
    } catch (_) {
      return (path, '');
    }
  }

  /// 分批并行计算 SHA1，限制并发度避免同时打开过多文件 / 创建过多 isolate。
  Future<List<(String, String)>> _computeHashesBatched(
    List<FileEntry> jars,
  ) async {
    const batchSize = 8;
    final results = <(String, String)>[];
    for (var i = 0; i < jars.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, jars.length);
      final batch = jars.sublist(i, end);
      results.addAll(await Future.wait(batch.map((j) => _safeSha1(j.path))));
    }
    return results;
  }

  Future<void> _fetchModIcons(List<FileEntry> jars) async {
    if (jars.isEmpty) return;
    try {
      // 分批并行计算 SHA1
      final hashResults = await _computeHashesBatched(jars);

      final hashToPath = <String, String>{};
      for (final (path, hash) in hashResults) {
        if (hash.isEmpty) continue;
        _sha1Hashes[path] = hash;
        hashToPath[hash] = path;
      }

      // 通过 SHA1 查询 Modrinth 版本信息（获取 project_id）
      final versionMap = await ModrinthService.getVersionsByHashes(
        _sha1Hashes.values.toList(),
      );

      // 收集所有 project_id
      final projectIdToPath = <String, String>{};
      for (final entry in versionMap.entries) {
        final hash = entry.key;
        final version = entry.value;
        final path = hashToPath[hash];
        if (path != null && version.projectId.isNotEmpty) {
          projectIdToPath[version.projectId] = path;
        }
      }

      if (projectIdToPath.isEmpty) return;

      // 批量获取项目信息（含图标 URL）
      final projects = await ModrinthService.getProjects(
        projectIdToPath.keys.toList(),
      );
      if (!mounted) return;
      setState(() {
        for (final project in projects) {
          final path = projectIdToPath[project.id];
          if (path != null) {
            _icons[path] = project.iconUrl;
          }
        }
      });
    } catch (_) {
      // 图标获取失败不影响使用
    }
  }

  // ── 更新检查 ──────────────────────────────────────────────────

  Future<void> _checkUpdates() async {
    final jars = _entries.where((e) => e.isFile && _isJar(e.name)).toList();
    if (jars.isEmpty) return;

    setState(() {
      _checkingUpdates = true;
      _updates.clear();
    });

    try {
      // 复用已计算的 SHA1，未计算则现算（分批并行）
      if (_sha1Hashes.isEmpty) {
        final hashResults = await _computeHashesBatched(jars);
        for (final (path, hash) in hashResults) {
          if (hash.isNotEmpty) _sha1Hashes[path] = hash;
        }
      }

      final hashToPath = <String, String>{};
      for (final entry in _sha1Hashes.entries) {
        hashToPath[entry.value] = entry.key;
      }

      // 查询 Modrinth 更新
      final updateResults = await ModrinthService.checkUpdates(
        _sha1Hashes.values.toList(),
      );

      // 对比哈希判断是否需要更新
      for (final entry in updateResults.entries) {
        final localHash = entry.key;
        final latestVersion = entry.value;
        final path = hashToPath[localHash];
        if (path == null) continue;
        // 如果最新版本的文件 SHA1 与本地相同，则无需更新
        final latestFileSha1 = latestVersion.primaryFile?.sha1;
        if (latestFileSha1 != null && latestFileSha1 == localHash) continue;
        _updates[path] = latestVersion;
      }

      if (!mounted) return;
      setState(() => _checkingUpdates = false);

      // 提示结果
      final messenger = ScaffoldMessenger.of(context);
      final tr = LocaleScope.of(context).translations;
      if (_updates.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('modsPlugins.noUpdates'))),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr.get('modsPlugins.updatesAvailable', {
                'count': '${_updates.length}',
              }),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingUpdates = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocaleScope.of(
              context,
            ).translations.get('modsPlugins.searchFailed', {'error': '$e'}),
          ),
        ),
      );
    }
  }

  // ── 更新单个模组 ──────────────────────────────────────────────

  /// 将模组更新任务加入下载队列。
  ///
  /// 下载完成后队列会自动替换旧文件，并通过 [_refreshAfterUpdate]
  /// 就地更新列表条目，避免全列表刷新导致图标/元数据重新加载。
  void _updateMod(FileEntry entry) {
    final version = _updates[entry.path];
    if (version == null) return;
    final file = version.primaryFile;
    if (file == null) return;

    final destPath = p.join(widget.folder.path, file.filename);
    final meta = _metadata[entry.path];

    DownloadQueue.instance.enqueue(
      url: file.url,
      destPath: destPath,
      filename: file.filename,
      projectTitle: meta?.name ?? entry.name,
      versionName: version.name.isEmpty ? version.versionNumber : version.name,
      iconUrl: _icons[entry.path],
      replacePath: entry.path,
      onComplete: () => _refreshAfterUpdate(entry.path, destPath),
    );

    // 标记为更新中（队列下载期间显示进度）
    setState(() => _updatingPaths.add(entry.path));
  }

  /// 更新完成后就地刷新列表，不触发全列表重载。
  ///
  /// 下载成功时：旧文件已被队列删除，新文件位于 [destPath]，
  /// 替换条目并仅对新文件重新识别元数据/图标/哈希。
  /// 下载失败/取消时：旧文件仍在，仅清理更新状态。
  Future<void> _refreshAfterUpdate(String oldPath, String destPath) async {
    if (!mounted) return;
    final newFile = File(destPath);

    if (!newFile.existsSync()) {
      // 下载失败或取消，旧文件仍在 → 仅清理状态
      setState(() {
        _updatingPaths.remove(oldPath);
      });
      return;
    }

    // 下载成功：旧文件已删除，新文件存在
    final newName = p.basename(destPath);
    final newEntry = entryFromEntity(newFile, newName);

    // 清理旧路径缓存
    _metadata.remove(oldPath);
    _icons.remove(oldPath);
    _sha1Hashes.remove(oldPath);
    _updates.remove(oldPath);

    setState(() {
      final idx = _entries.indexWhere((e) => e.path == oldPath);
      if (idx >= 0) {
        _entries[idx] = newEntry;
      } else {
        _entries.add(newEntry);
      }
      _updatingPaths.remove(oldPath);
    });

    // 仅对新文件重新识别元数据、图标与哈希
    await _identifySingleMod(newEntry);
  }

  /// 对单个 jar 文件重新识别元数据、计算 SHA1 并获取图标。
  Future<void> _identifySingleMod(FileEntry entry) async {
    final meta = await _safeParse(entry.path);
    if (!mounted) return;
    setState(() => _metadata[entry.path] = meta);

    try {
      final hash = await ModrinthService.computeSha1(entry.path);
      if (hash.isEmpty || !mounted) return;
      _sha1Hashes[entry.path] = hash;

      final versionMap = await ModrinthService.getVersionsByHashes([hash]);
      final version = versionMap[hash];
      if (version == null || version.projectId.isEmpty || !mounted) return;

      final projects = await ModrinthService.getProjects([version.projectId]);
      if (projects.isNotEmpty && mounted) {
        setState(() => _icons[entry.path] = projects.first.iconUrl);
      }
    } catch (_) {
      // 图标获取失败不影响使用
    }
  }

  // ── 选择更新 ──────────────────────────────────────────────────

  /// 弹出更新选择对话框，让用户勾选要更新的模组。
  Future<void> _showUpdateSelection() async {
    final tr = LocaleScope.of(context).translations;
    final theme = Theme.of(context);

    // 收集可更新的条目
    final updatable = <MapEntry<FileEntry, ModrinthVersion>>[];
    for (final path in _updates.keys) {
      final entry = _entries.where((e) => e.path == path).firstOrNull;
      if (entry != null) {
        updatable.add(MapEntry(entry, _updates[path]!));
      }
    }
    if (updatable.isEmpty) return;

    // 默认全部选中
    final selected = <String, bool>{
      for (final e in updatable) e.key.path: true,
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final selectedCount = selected.values.where((v) => v).length;
          return AlertDialog(
            title: Text(tr.get('modsPlugins.selectUpdates')),
            contentPadding: const EdgeInsets.only(top: 16),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: selected.values.every((v) => v)
                              ? null
                              : () {
                                  setDialogState(() {
                                    for (final k in selected.keys) {
                                      selected[k] = true;
                                    }
                                  });
                                },
                          child: Text(tr.get('modsPlugins.selectAll')),
                        ),
                        TextButton(
                          onPressed: selected.values.any((v) => v)
                              ? () {
                                  setDialogState(() {
                                    for (final k in selected.keys) {
                                      selected[k] = false;
                                    }
                                  });
                                }
                              : null,
                          child: Text(tr.get('modsPlugins.deselectAll')),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: updatable.length,
                      itemBuilder: (ctx, i) {
                        final entry = updatable[i].key;
                        final version = updatable[i].value;
                        final meta = _metadata[entry.path];
                        final name = (meta != null && meta.name.isNotEmpty)
                            ? meta.name
                            : entry.name;
                        final oldVersion = meta?.version ?? '?';
                        final newVersion = version.name.isEmpty
                            ? version.versionNumber
                            : version.name;
                        return CheckboxListTile(
                          value: selected[entry.path],
                          onChanged: (v) {
                            setDialogState(() {
                              selected[entry.path] = v ?? false;
                            });
                          },
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$oldVersion → $newVersion',
                            style: theme.textTheme.bodySmall,
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
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr.get('common.cancel')),
              ),
              FilledButton(
                onPressed: selectedCount == 0
                    ? null
                    : () => Navigator.of(ctx).pop(true),
                child: Text(
                  tr.get('modsPlugins.updateSelected', {
                    'count': '$selectedCount',
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      for (final entry in updatable) {
        if (selected[entry.key.path] == true) {
          _updateMod(entry.key);
        }
      }
    }
  }

  // ── 启用/禁用 ────────────────────────────────────────────────

  /// 切换模组/插件的启用状态。
  ///
  /// `.jar` → `.jar.disabled`（禁用），`.jar.disabled` → `.jar`（启用）。
  /// 原地更新条目，保留已获取的元数据/图标/哈希（迁移到新路径）。
  Future<void> _toggleEnabled(FileEntry entry) async {
    final tr = LocaleScope.of(context).translations;
    final messenger = ScaffoldMessenger.of(context);
    final isDisabled = entry.name.toLowerCase().endsWith('.jar.disabled');

    // 弹窗确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDisabled
              ? tr.get('modsPlugins.confirmEnable')
              : tr.get('modsPlugins.confirmDisable'),
        ),
        content: Text(entry.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isDisabled
                  ? tr.get('modsPlugins.enable')
                  : tr.get('modsPlugins.disable'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final newName = isDisabled
        ? entry.name.substring(0, entry.name.length - '.disabled'.length)
        : '${entry.name}.disabled';
    final newPath = isDisabled
        ? entry.path.substring(0, entry.path.length - '.disabled'.length)
        : '${entry.path}.disabled';
    try {
      await File(entry.path).rename(newPath);
      if (!mounted) return;
      // 原地更新条目，迁移已缓存的数据到新路径
      setState(() {
        final idx = _entries.indexWhere((e) => e.path == entry.path);
        if (idx >= 0) {
          _entries[idx] = FileEntry(
            path: newPath,
            name: newName,
            isDirectory: false,
            size: entry.size,
            modified: DateTime.now(),
          );
        }
        // 迁移缓存
        _transferCache(entry.path, newPath);
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr.get(
              isDisabled
                  ? 'modsPlugins.enableFailed'
                  : 'modsPlugins.disableFailed',
              {'error': '$e'},
            ),
          ),
        ),
      );
    }
  }

  /// 将旧路径的缓存数据迁移到新路径。
  void _transferCache(String oldPath, String newPath) {
    if (_metadata.containsKey(oldPath)) {
      _metadata[newPath] = _metadata.remove(oldPath);
    }
    if (_icons.containsKey(oldPath)) {
      _icons[newPath] = _icons.remove(oldPath);
    }
    if (_sha1Hashes.containsKey(oldPath)) {
      final hash = _sha1Hashes.remove(oldPath);
      if (hash != null) _sha1Hashes[newPath] = hash;
    }
    if (_updates.containsKey(oldPath)) {
      _updates.remove(oldPath);
    }
  }

  // ── 导入文件 ──────────────────────────────────────────────────

  Future<bool> _ensurePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('fileBrowser.permissionTitle')),
        content: Text(ctx.tr('fileBrowser.permissionContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('fileBrowser.grantPermission')),
          ),
        ],
      ),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }

  Future<void> _import() async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.jar'],
    );
    if (sourcePath == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    setState(() => _importing = true);
    try {
      await _service.importFile(sourcePath, widget.folder);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('modsPlugins.importSuccess'))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('modsPlugins.importFailed', {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── 删除文件 ──────────────────────────────────────────────────

  Future<void> _delete(FileEntry entry) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('common.delete')),
        content: Text(
          tr.get('modsPlugins.deleteConfirm', {'name': entry.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.delete(entry.path);
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('modsPlugins.deleteFailed', {'error': '$e'})),
        ),
      );
    }
  }

  // ── 辅助方法 ──────────────────────────────────────────────────

  bool _isJar(String name) =>
      name.toLowerCase().endsWith('.jar') ||
      name.toLowerCase().endsWith('.jar.disabled');

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── 构建 UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHeader(theme),
        const DownloadQueueBanner(),
        if (widget.isJarContent && _updates.isNotEmpty)
          _buildUpdateBanner(theme),
        Expanded(
          child: _entries.isEmpty
              ? _emptyState(
                  theme,
                  Icons.inbox_outlined,
                  context.tr('modsPlugins.empty.title'),
                  context.tr('modsPlugins.empty.desc'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) => _buildListTile(theme, _entries[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          Text(
            context.tr('modsPlugins.count', {'count': '${_entries.length}'}),
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          if (widget.isJarContent) ...[
            if (_checkingUpdates)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.system_update, size: 20),
                tooltip: context.tr('modsPlugins.checkUpdates'),
                onPressed: _checkUpdates,
              ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: context.tr('common.refresh'),
            onPressed: _load,
          ),
          if (_importing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: context.tr('modsPlugins.import'),
              onPressed: _import,
            ),
        ],
      ),
    );
  }

  Widget _buildUpdateBanner(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.update, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('modsPlugins.updatesAvailable', {
                'count': '${_updates.length}',
              }),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: _updatingPaths.isNotEmpty ? null : _showUpdateSelection,
            child: Text(context.tr('modsPlugins.selectUpdates')),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile(ThemeData theme, FileEntry entry) {
    final meta = _metadata[entry.path];
    final iconUrl = _icons[entry.path];
    final hasUpdate = _updates.containsKey(entry.path);
    final isUpdating = _updatingPaths.contains(entry.path);
    final isDisabled =
        entry.isFile && entry.name.toLowerCase().endsWith('.jar.disabled');
    final isJarFile = entry.isFile && _isJar(entry.name);

    // 标题：模组名称 > 文件名（禁用时去掉 .disabled 后缀）
    String title;
    if (meta != null && meta.name.isNotEmpty) {
      title = meta.name;
    } else if (isDisabled) {
      title = entry.name.substring(0, entry.name.length - '.disabled'.length);
    } else {
      title = entry.name;
    }

    // 副标题
    String? subtitle;
    if (meta != null) {
      final parts = <String>[];
      if (meta.version != null) parts.add(meta.version!);
      if (meta.loaderLabel.isNotEmpty) parts.add(meta.loaderLabel);
      if (parts.isNotEmpty) {
        subtitle =
            parts.join(' · ') +
            (meta.description != null ? '\n${meta.description}' : '');
      } else if (meta.description != null) {
        subtitle = meta.description!;
      }
    } else if (entry.isFile) {
      subtitle = _formatSize(entry.size);
    }

    return Card(
      color: isDisabled ? theme.colorScheme.surfaceContainerLow : null,
      child: ListTile(
        leading: _buildLeading(theme, entry, meta, iconUrl),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isDisabled
              ? theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                )
              : null,
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDisabled
                      ? theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        )
                      : null,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isJarFile)
              IconButton(
                icon: Icon(
                  isDisabled ? Icons.check_circle_outline : Icons.block,
                  size: 20,
                  color: isDisabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                tooltip: isDisabled
                    ? context.tr('modsPlugins.enable')
                    : context.tr('modsPlugins.disable'),
                onPressed: () => _toggleEnabled(entry),
              ),
            if (hasUpdate && !isDisabled)
              isUpdating
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        Icons.update,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip: context.tr('modsPlugins.update'),
                      onPressed: () => _updateMod(entry),
                    ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(entry),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建列表项前导图标。
  ///
  /// 优先显示从 Modrinth 获取的缓存图标，其次按加载器显示彩色方块，
  /// 最后回退到通用扩展图标。
  Widget _buildLeading(
    ThemeData theme,
    FileEntry entry,
    ModMetadata? meta,
    String? iconUrl,
  ) {
    // 有 Modrinth 图标 URL 时显示缓存图标（加载中/失败回退到彩色方块）
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return CachedModIcon(
        url: iconUrl,
        size: 40,
        fallback: meta != null ? _coloredBox(theme, meta) : null,
      );
    }

    // 图标仍在加载中且有元数据 → 显示彩色方块
    if (meta != null) {
      return _coloredBox(theme, meta);
    }

    // 无元数据 → 通用图标
    return const Icon(Icons.extension_outlined, size: 32);
  }

  Widget _coloredBox(ThemeData theme, ModMetadata meta) {
    final color = switch (meta.loader) {
      ModLoader.fabric => const Color.fromARGB(255, 221, 170, 255),
      ModLoader.forge => const Color.fromARGB(255, 255, 170, 107),
      ModLoader.quilt => const Color.fromARGB(255, 170, 221, 255),
      ModLoader.neoforge => const Color.fromARGB(255, 255, 107, 107),
      ModLoader.bukkit => const Color.fromARGB(255, 170, 255, 170),
      ModLoader.bungeecord => const Color.fromARGB(255, 255, 221, 107),
      ModLoader.velocity => const Color.fromARGB(255, 107, 221, 255),
      ModLoader.unknown => theme.colorScheme.surfaceContainerHighest,
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

/// 空白占位状态。
Widget _emptyState(ThemeData theme, IconData icon, String title, String desc) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            desc,
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
