import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'mod_download_queue.dart';
import 'mods_download_tab.dart';

/// 插件/模组管理页(作用于全局当前实例,对齐 V1 模组/插件管理):
/// 顶层动态目录 Tab(管理)+ 末尾固定 1 个「下载」Tab。
///
/// 元数据检查放在后端:
/// 1. 页面加载先经 `GET mods/metadata` 获取文件列表显示(未解析项 metadata 为 null);
/// 2. 加载后自动触发 `POST mods/analyze` 创建解析任务(202 返回 jobId);
/// 3. 轮询 `GET /tasks/{jobId}` 直至终结;
/// 4. 任务成功后重新 `GET mods/metadata` 获取解析结果展示,并对已识别 sha1 的条目
///    自动做更新检查(Modrinth version_files),有新版本的在列表项显示更新横幅,
///    点击自动下载最新版,成功后旧文件由后端重命名 `.disabled`。
///
/// 文件管理操作(禁用/启用切换 .disabled 后缀、删除)复用 /fs/* 沙箱接口;
/// 导入复用 /fs 分片上传;下载队列横幅位于页面顶部(轮询 download_single_file 任务)。
class ModsPluginsPage extends ConsumerStatefulWidget {
  const ModsPluginsPage({super.key});

  @override
  ConsumerState<ModsPluginsPage> createState() => _ModsPluginsPageState();
}

class _ModsPluginsPageState extends ConsumerState<ModsPluginsPage>
    with SingleTickerProviderStateMixin {
  static const _kPlugins = 'plugins';
  static const _kMods = 'mods';

  /// 存在的目录(按检测顺序),用于动态生成管理 Tab;末尾固定「下载」Tab。
  List<String>? _folders;
  bool _loading = true;

  /// 目录探测阶段遇到的非「目录不存在」错误(如鉴权/网络),用于空态提示。
  String? _probeError;

  /// 是否 PocketMine 实例(决定下载平台:true → Poggit,false → Modrinth)。
  bool _pocketmine = false;

  TabController? _tabCtrl;
  int _tabIndex = 0;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当前实例变化时(重新)检测目录
    ref.listen(currentInstanceProvider, (previous, next) {
      if (previous?.id != next?.id) _detect();
    });
  }

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  /// 检测实例工作目录下是否存在 plugins / mods 目录:
  /// 经 `GET mods/metadata` 探测——目录存在返回 200,不存在返回 400 invalid_path。
  Future<void> _detect() async {
    final client = _client;
    final instance = ref.read(currentInstanceProvider);
    if (client == null || instance == null) {
      if (mounted) {
        setState(() {
          _folders = null;
          _loading = false;
        });
      }
      return;
    }
    _tabCtrl?.dispose();
    _tabCtrl = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _pocketmine = instance.type == InstanceType.pocketmine;
      });
    }
    final folders = <String>[];
    String? probeError;
    for (final folder in const [_kPlugins, _kMods]) {
      try {
        await client
            .getInstancesApi()
            .getInstanceModsMetadata(instanceId: instance.id, path: folder);
        folders.add(folder);
      } on DioException catch (e) {
        // 400 invalid_path = 目录不存在,忽略;其余错误(鉴权/网络)记录用于空态提示
        if (e.response?.statusCode != 400) {
          probeError = apiErrorMessage(e);
        }
      } catch (e) {
        probeError = apiErrorMessage(e);
      }
    }
    if (!mounted) return;
    // 管理 Tab 每个目录一个 + 末尾固定「下载」Tab
    _tabCtrl = folders.isEmpty
        ? null
        : TabController(length: folders.length + 1, vsync: this);
    _tabCtrl?.addListener(() {
      if (_tabCtrl != null && _tabCtrl!.index != _tabIndex && mounted) {
        setState(() => _tabIndex = _tabCtrl!.index);
      }
    });
    setState(() {
      _folders = folders;
      _probeError = probeError;
      _tabIndex = 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final instance = ref.watch(currentInstanceProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('插件/模组'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        bottom: _tabCtrl == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: TabBar(
                  controller: _tabCtrl,
                  tabs: [
                    for (final folder in _folders!)
                      Tab(text: folder == _kPlugins ? '插件' : '模组'),
                    const Tab(text: '下载'),
                  ],
                ),
              ),
      ),
      body: instance == null
          ? _NoInstanceHint()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _tabCtrl == null
                  ? (_probeError != null
                      ? _probeErrorState()
                      : _emptyState(
                          Icons.extension_outlined,
                          '未发现插件/模组目录',
                          '实例工作目录下没有 plugins 或 mods 文件夹,可在「文件」页创建后返回。',
                        ))
                  : Column(
                      children: [
                        DownloadQueueBanner(instanceId: instance.id),
                        Expanded(
                          child: TabBarView(
                            controller: _tabCtrl,
                            children: [
                              for (final folder in _folders!)
                                ModFolderTab(
                                  key: ValueKey('${instance.id}/$folder'),
                                  instanceId: instance.id,
                                  folder: folder,
                                  pocketmine: _pocketmine,
                                ),
                              DownloadTab(
                                key: ValueKey('${instance.id}/download'),
                                instanceId: instance.id,
                                folders: _folders!,
                                pocketmine: _pocketmine,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _emptyState(IconData icon, String title, String desc) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 目录探测出错(鉴权/网络等)时的错误态,带重试。
  Widget _probeErrorState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '加载失败:$_probeError',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _detect, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _NoInstanceHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '请先在「服务器」页选择实例',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 单个目录(plugins / mods)的管理内容:文件列表 + 自动元数据解析 + 更新检查。
class ModFolderTab extends ConsumerStatefulWidget {
  const ModFolderTab({
    super.key,
    required this.instanceId,
    required this.folder,
    required this.pocketmine,
  });

  final String instanceId;
  final String folder;

  /// 是否 PocketMine 实例(PocketMine 不做 Modrinth 更新检查)。
  final bool pocketmine;

  @override
  ConsumerState<ModFolderTab> createState() => _ModFolderTabState();
}

class _ModFolderTabState extends ConsumerState<ModFolderTab> {
  static const _chunkSize = 8 * 1024 * 1024; // 8 MiB

  /// 文件列表(metadata 为 null = 未解析/未识别)。
  List<ModMetadataEntry>? _items;
  bool _loading = true;
  String? _error;

  /// 解析任务进行中(提交后轮询)。
  bool _analyzing = false;

  /// 本会话是否已自动触发过解析(避免 unrecognized 文件导致的重复解析循环)。
  bool _autoAnalyzed = false;

  /// 更新检查结果:sha1 -> 更新的版本(用于显示更新横幅 + 自动下载)。
  Map<String, ModrinthVersion> _updates = {};
  bool _checkingUpdates = false;

  /// 正在导入的文件名(显示进度)。
  String? _importing;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final resp = await client.getInstancesApi().getInstanceModsMetadata(
            instanceId: widget.instanceId,
            path: widget.folder,
          );
      final list = resp.data;
      if (!mounted || list == null) return;
      setState(() {
        _items = list.items.toList();
        _error = null;
        _loading = false;
      });
      _maybeAutoAnalyze();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  /// 加载后自动触发:首次有未解析文件时提交解析任务;全已解析则直接做更新检查。
  void _maybeAutoAnalyze() {
    if (_autoAnalyzed || _analyzing) return;
    final items = _items;
    if (items == null) return;
    _autoAnalyzed = true;
    if (items.isEmpty) {
      _checkUpdates();
      return;
    }
    if (items.any((e) => e.metadata == null)) {
      _analyze();
    } else {
      _checkUpdates();
    }
  }

  /// 核心流程:提交解析任务 → 轮询任务状态 → 完成后拉取解析结果 + 更新检查。
  Future<void> _analyze() async {
    final client = _client;
    if (client == null || _analyzing) return;
    setState(() => _analyzing = true);
    try {
      final job = (await client.getInstancesApi().analyzeInstanceMods(
            instanceId: widget.instanceId,
            modsAnalyzeRequest: ModsAnalyzeRequest((b) => b..path = widget.folder),
          ))
          .data!;
      // 轮询任务状态(间隔 1s,直至终结)
      while (mounted) {
        final task = (await client.getTasksApi().getTask(jobId: job.jobId)).data;
        if (task == null) break;
        if (task.status == TaskStatus.succeeded) {
          // _autoAnalyzed 已置位,刷新后 _maybeAutoAnalyze 直接走更新检查
          await _load(silent: true);
          _snack('解析完成');
          return;
        }
        if (task.status == TaskStatus.failed ||
            task.status == TaskStatus.cancelled) {
          _snack('解析失败:${task.error?.message ?? task.error?.code ?? '未知原因'}');
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  /// 更新检查:对已识别 sha1 的条目批量调 Modrinth version_files(仅 Java 实例)。
  /// 返回的版本主文件 sha1 与本地不一致 → 有新版本,记入 [_updates] 显示横幅。
  Future<void> _checkUpdates() async {
    final client = _client;
    final items = _items;
    if (client == null || widget.pocketmine || items == null || items.isEmpty) {
      return;
    }
    final sha1s =
        items.map((e) => e.sha1).whereType<String>().toList(growable: false);
    if (sha1s.isEmpty || _checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      final resp = await client.getModsApi().modrinthVersionFiles(
            modrinthVersionFilesRequest: ModrinthVersionFilesRequest(
              (b) => b..hashes.addAll(sha1s),
            ),
          );
      if (!mounted) return;
      final map = resp.data ?? BuiltMap<String, ModrinthVersion>();
      final updates = <String, ModrinthVersion>{};
      for (final entry in items) {
        final sha1 = entry.sha1;
        if (sha1 == null) continue;
        final v = map[sha1];
        if (v == null) continue;
        final files = v.files ?? const <ModrinthVersionFile>[];
        final primary =
            files.where((f) => f.primary).firstOrNull ?? files.firstOrNull;
        final remoteSha1 = primary?.hashes?.sha1;
        if (remoteSha1 != null &&
            remoteSha1.isNotEmpty &&
            remoteSha1.toLowerCase() != sha1.toLowerCase()) {
          updates[sha1] = v;
        }
      }
      setState(() {
        _updates = updates;
        _checkingUpdates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  /// 更新横幅点击:自动下载最新版本(不经选择),成功后旧文件由后端改 `.disabled`。
  Future<void> _autoUpdate(ModMetadataEntry entry) async {
    final client = _client;
    final v = entry.sha1 == null ? null : _updates[entry.sha1];
    if (client == null || v == null) return;
    final files = v.files ?? const <ModrinthVersionFile>[];
    final file = files.where((f) => f.primary).firstOrNull ?? files.firstOrNull;
    if (file == null) {
      _snack('该版本没有可下载文件');
      return;
    }
    final displayName = v.name == null || v.name!.isEmpty
        ? '${entry.name} · ${v.versionNumber}'
        : '${v.name} · ${v.versionNumber}';
    try {
      await client.getInstancesApi().downloadInstanceMod(
            instanceId: widget.instanceId,
            modDownloadRequest: ModDownloadRequest((b) => b
              ..url = file.url
              ..destPath = widget.folder
              ..fileName = file.filename
              ..displayName = displayName
              ..replacePath = entry.path),
          );
      _snack('已加入下载队列:$displayName');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  /// 禁用/启用切换:.jar/.phar ↔ .jar.disabled/.phar.disabled(经 /fs/move 重命名)。
  Future<void> _toggleEnabled(ModMetadataEntry entry) async {
    final client = _client;
    if (client == null) return;
    final lower = entry.name.toLowerCase();
    final isDisabled =
        lower.endsWith('.jar.disabled') || lower.endsWith('.phar.disabled');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDisabled ? '启用' : '禁用'),
        content: Text(isDisabled
            ? '确定启用「${entry.name}」吗?'
            : '确定禁用「${entry.name}」吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isDisabled ? '启用' : '禁用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final newPath = isDisabled
        ? entry.path.substring(0, entry.path.length - '.disabled'.length)
        : '${entry.path}.disabled';
    try {
      await client.getFilesApi().moveFile(
            fsMoveRequest: FsMoveRequest((b) => b
              ..instanceId = widget.instanceId
              ..from = entry.path
              ..to = newPath),
          );
      await _load(silent: true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _delete(ModMetadataEntry entry) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${entry.name}」吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await client.getFilesApi().deleteFile(
            fsPathRequest: FsPathRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = entry.path),
          );
      await _load(silent: true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  // ── 导入(本机文件 → 实例目录,复用 /fs 分片上传) ─────────────

  Future<void> _import() async {
    final client = _client;
    if (client == null || _importing != null) return;
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      if (!mounted) return;
      await _uploadOne(client, file);
    }
    // 导入完成后刷新列表并自动解析新文件
    _autoAnalyzed = false;
    await _load(silent: true);
  }

  /// 三段式分片上传到当前目录:init(断点续传)→ piece × n → complete。
  Future<void> _uploadOne(EdgecubeApiClient client, PlatformFile file) async {
    final total = await file.length();
    // 无本地路径(web / content uri)时预读全文,供下方内存分片。
    final Uint8List? memBytes =
        (!kIsWeb && file.path != null) ? null : await file.readAsBytes();
    if (mounted) setState(() => _importing = file.name);
    try {
      final session = (await client.getFilesApi().initFileUpload(
            uploadInitRequest: UploadInitRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = widget.folder
              ..fileName = file.name
              ..sizeBytes = total),
          )).data!;
      final uploadId = session.uploadId;
      var offset = session.receivedBytes; // 服务端已有部分(断点续传)
      final raf = (!kIsWeb && file.path != null)
          ? await File(file.path!).open(mode: FileMode.read)
          : null;
      try {
        while (offset < total) {
          if (!mounted) return;
          final len = math.min(_chunkSize, total - offset);
          final Uint8List chunk;
          if (raf != null) {
            await raf.setPosition(offset);
            chunk = await raf.read(len);
          } else {
            chunk = Uint8List.sublistView(memBytes!, offset, offset + len);
          }
          final prog = (await client.getFilesApi().uploadFilePiece(
                uploadId: uploadId,
                offset: offset,
                body: MultipartFile.fromBytes(
                  chunk,
                  contentType: DioMediaType('application', 'octet-stream'),
                ),
              )).data!;
          offset = prog.receivedBytes;
        }
      } finally {
        await raf?.close();
      }
      await client.getFilesApi().completeFileUpload(
            uploadCompleteRequest: UploadCompleteRequest((b) => b
              ..uploadId = uploadId),
          );
      if (mounted) _snack('「${file.name}」导入完成');
    } catch (e) {
      if (mounted) _snack('「${file.name}」导入失败:${apiErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      children: [
        _header(),
        Expanded(
          child: _loading && items == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: items == null ? _errorView() : _list(items),
                ),
        ),
      ],
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final count = _items?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            '$count 个文件',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (_checkingUpdates)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_importing != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 120,
                child: Text(
                  '导入中:$_importing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          IconButton(
            tooltip: '导入',
            onPressed: _importing != null ? null : _import,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _analyzing ? null : () => _load(silent: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text('加载失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _list(List<ModMetadataEntry> items) {
    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.inbox_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '此目录为空',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final entry = items[index];
        final update =
            entry.sha1 == null ? null : _updates[entry.sha1];
        final tile = _entryTile(entry);
        if (update == null) return tile;
        return Column(
          children: [
            tile,
            _updateBanner(entry, update),
            const Divider(height: 1, indent: 56),
          ],
        );
      },
    );
  }

  Widget _entryTile(ModMetadataEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final meta = entry.metadata;
    final lower = entry.name.toLowerCase();
    final isDisabled =
        lower.endsWith('.jar.disabled') || lower.endsWith('.phar.disabled');
    // 标题:元数据名称优先,否则文件名(禁用时去掉 .disabled 后缀)
    final title = (meta != null && meta.name.isNotEmpty)
        ? meta.name
        : (isDisabled
            ? entry.name.substring(0, entry.name.length - '.disabled'.length)
            : entry.name);
    // 副标题:解析成功 → 版本 · 加载器 + 描述;未解析 → 大小 + 提示
    final String subtitle;
    if (meta != null) {
      final parts = <String>[];
      if (meta.version != null && meta.version!.isNotEmpty) {
        parts.add(meta.version!);
      }
      final loaderLabel = modLoaderLabel(meta.loader);
      if (loaderLabel.isNotEmpty) parts.add(loaderLabel);
      if (parts.isNotEmpty) {
        subtitle = parts.join(' · ') +
            (meta.description != null && meta.description!.isNotEmpty
                ? '\n${meta.description}'
                : '');
      } else {
        subtitle = meta.description ?? _formatSize(entry.sizeBytes);
      }
    } else {
      subtitle = '${_formatSize(entry.sizeBytes)} · 未解析';
    }
    return ListTile(
      leading: _leadingIcon(entry, isDisabled),
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: isDisabled
            ? TextStyle(
                color: cs.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isDisabled ? '启用' : '禁用',
            onPressed: _analyzing ? null : () => _toggleEnabled(entry),
            icon: Icon(
              isDisabled ? Icons.check_circle_outline : Icons.block,
              color: isDisabled ? cs.onSurfaceVariant : cs.primary,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: _analyzing ? null : () => _delete(entry),
            icon: Icon(Icons.delete_outline, color: cs.error),
          ),
        ],
      ),
    );
  }

  /// 图标:优先 icon_url,其次加载器彩色方块,最后通用图标。
  Widget _leadingIcon(ModMetadataEntry entry, bool isDisabled) {
    final iconUrl = entry.iconUrl;
    final fallback = _ColoredBox(loader: entry.metadata?.loader, disabled: isDisabled);
    if (iconUrl == null || iconUrl.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        iconUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// 更新横幅:检测到新版本时展示,点击自动下载最新版。
  Widget _updateBanner(ModMetadataEntry entry, ModrinthVersion version) {
    final cs = Theme.of(context).colorScheme;
    final files = version.files ?? const <ModrinthVersionFile>[];
    final file = files.where((f) => f.primary).firstOrNull ?? files.firstOrNull;
    return Container(
      color: cs.tertiaryContainer,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 56, right: 8),
        leading: Icon(Icons.system_update_alt, color: cs.onTertiaryContainer),
        title: Text(
          '发现新版本:${version.versionNumber}',
          style: TextStyle(
            fontSize: 13,
            color: cs.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: TextButton(
          onPressed: file == null ? null : () => _autoUpdate(entry),
          child: const Text('更新'),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 加载器彩色方块(对齐 V1 _coloredBox),无元数据时回退通用扩展图标。
class _ColoredBox extends StatelessWidget {
  const _ColoredBox({required this.loader, required this.disabled});

  final ModLoader? loader;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (loader == null) {
      return const Icon(Icons.extension_outlined, size: 32);
    }
    final color = modLoaderColor(loader!);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: disabled ? color.withValues(alpha: .4) : color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.extension, size: 24, color: Colors.white),
    );
  }
}

/// 加载器中文标签(对齐后端 ModLoader::label)。
String modLoaderLabel(ModLoader loader) => switch (loader.name) {
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

/// 加载器品牌色(对齐 V1 _coloredBox 色板)。
Color modLoaderColor(ModLoader loader) => switch (loader.name) {
      'fabric' => const Color(0xFFDAA9FF),
      'forge' => const Color(0xFFFFAA6B),
      'quilt' => const Color(0xFFAADAFF),
      'neoforge' => const Color(0xFFFF6B6B),
      'bukkit' => const Color(0xFFAAFFAA),
      'bungeecord' => const Color(0xFFFFDD6B),
      'velocity' => const Color(0xFF6BDAFF),
      'pocketmine' => const Color(0xFFAADADD),
      _ => const Color(0xFF9E9E9E),
    };
