import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'labels.dart';

/// 实例迁移页:导出(当前实例打包为归档) + 导入(本地归档还原为新实例)。
///
/// - 导出:提交 `POST /instances/{id}/export` 后台任务(必须已停止),轮询
///   `GET /tasks/{jobId}` 显示进度,完成后经 `GET /instances/{id}/export/download`
///   下载归档保存到本地(web/桌面/移动端均走 FilePicker 保存)。
/// - 导入:选择本地 zip/tar.gz 归档 → 三段式分片上传(`/fs/upload-*`)到所选
///   来源实例 cwd → 提交 `POST /instances/import` 后台任务,完成后新实例
///   出现在实例列表(服务器页 3s 轮询自动可见)。
///
/// 入口:服务器页控制面板「实例工具」卡片(实例相关功能收敛到服务器页)。
class InstanceMigratePage extends ConsumerStatefulWidget {
  const InstanceMigratePage({super.key});

  @override
  ConsumerState<InstanceMigratePage> createState() =>
      _InstanceMigratePageState();
}

class _InstanceMigratePageState extends ConsumerState<InstanceMigratePage> {
  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('实例迁移'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: '导出'),
              Tab(text: '导入'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ExportTab(client: _client),
            _ImportTab(client: _client),
          ],
        ),
      ),
    );
  }
}

/// 实例概览加载:进入时拉取一次,返回实例列表摘要(items)。
Future<List<InstanceSummary>> loadInstanceItems(
    EdgecubeApiClient? client) async {
  if (client == null) return const [];
  final overview = (await client.getInstancesApi().getInstancesOverview()).data;
  return overview?.items.toList() ?? const [];
}

// ────────────────────────── 导出 Tab ──────────────────────────

class _ExportTab extends ConsumerStatefulWidget {
  const _ExportTab({this.client});

  final EdgecubeApiClient? client;

  @override
  ConsumerState<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends ConsumerState<_ExportTab> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  bool _starting = false;
  List<InstanceSummary> _items = const [];

  ExportRequestFormatEnum _format = ExportRequestFormatEnum.zip;
  bool _includeLogs = false;

  String? _jobId;
  Task? _task;

  EdgecubeApiClient? get _client => widget.client ?? ref.read(edgecubeClientProvider);
  InstanceSummary? get _selected => ref.read(currentInstanceProvider);

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await loadInstanceItems(_client);
    if (mounted) setState(() => _items = items);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _startPolling(String jobId) {
    _timer?.cancel();
    setState(() {
      _jobId = jobId;
      _task = null;
    });
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final client = _client;
    final jobId = _jobId;
    if (client == null || jobId == null || !mounted) return;
    try {
      final task = (await client.getTasksApi().getTask(jobId: jobId)).data!;
      if (!mounted) return;
      setState(() => _task = task);
      if (taskFinished(task.status)) _timer?.cancel();
    } catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      _snack('读取导出任务失败:${apiErrorMessage(e)}');
    }
  }

  Future<void> _startExport() async {
    final client = _client;
    final instance = _selected;
    if (client == null || instance == null || _starting) return;
    setState(() => _starting = true);
    try {
      final accepted = (await client
              .getInstancesApi()
              .exportInstance(
                instanceId: instance.id,
                exportRequest: ExportRequest((b) => b
                  ..format = _format
                  ..includeLogs = _includeLogs),
              ))
          .data!;
      _snack('导出任务已开始');
      _startPolling(accepted.jobId);
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancelExport() async {
    final client = _client;
    final jobId = _jobId;
    if (client == null || jobId == null) return;
    try {
      await client.getTasksApi().cancelTask(jobId: jobId);
      _timer?.cancel();
      _snack('已取消导出');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _downloadArchive() async {
    final client = _client;
    final instance = _selected;
    final jobId = _jobId;
    if (client == null || instance == null || jobId == null) return;
    try {
      final Uint8List bytes =
          (await client.getTransferApi().downloadInstanceExport(
                instanceId: instance.id,
                exportTaskId: jobId,
              ))
              .data!;
      final ext =
          _format == ExportRequestFormatEnum.tarPeriodGz ? 'tar.gz' : 'zip';
      final fileName = '${instance.name}-${jobId.substring(0, 8)}.$ext';
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存导出归档',
        fileName: fileName,
        bytes: bytes,
      );
      if (saved != null) _snack('归档已下载:$saved');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  bool get _exportBusy {
    final task = _task;
    return task != null && !taskFinished(task.status);
  }

  @override
  Widget build(BuildContext context) {
    final instance = _selected;
    final items = _items;
    // 选中实例的最新状态(overview 落地才有)
    InstanceStatus? status;
    if (instance != null) {
      for (final s in items) {
        if (s.id == instance.id) {
          status = s.status;
          break;
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (instance == null)
          const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Column(
              children: [
                Icon(Icons.dns_outlined, size: 56),
                SizedBox(height: 12),
                Text('请先在服务器页选择一个实例'),
              ],
            ),
          )
        else ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(instance.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (status != null)
                    Row(
                      children: [
                        Text(
                          '状态:${instanceStatusLabel(status)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: status == InstanceStatus.stopped
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : Theme.of(context).colorScheme.error,
                              ),
                        ),
                        if (status != InstanceStatus.stopped) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '导出前请先停止实例(运行中提交会被拒绝)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text('工作目录与配置将打包为归档,可跨设备导入还原',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('归档格式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ExportRequestFormatEnum>(
            segments: const [
              ButtonSegment(
                value: ExportRequestFormatEnum.zip,
                label: Text('ZIP'),
                icon: Icon(Icons.archive_outlined),
              ),
              ButtonSegment(
                value: ExportRequestFormatEnum.tarPeriodGz,
                label: Text('TAR.GZ'),
                icon: Icon(Icons.compress),
              ),
            ],
            selected: {_format},
            onSelectionChanged: _exportBusy
                ? null
                : (set) => setState(() => _format = set.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('包含日志'),
            subtitle: const Text('打包时保留 logs 日志目录(增大归档体积)'),
            value: _includeLogs,
            onChanged: _exportBusy
                ? null
                : (v) => setState(() => _includeLogs = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _exportBusy || _starting ? null : _startExport,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('开始导出'),
          ),
          if (_task != null) ...[
            const SizedBox(height: 16),
            _taskCard(_task!),
          ],
        ],
      ],
    );
  }

  Widget _taskCard(Task task) {
    final cs = Theme.of(context).colorScheme;
    final status = task.status;
    final progress = task.progress;
    final percent = progress?.percent;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status == TaskStatus.succeeded
                      ? Icons.check_circle
                      : status == TaskStatus.failed
                          ? Icons.error
                          : Icons.hourglass_top,
                  color: taskStatusColor(cs, status),
                ),
                const SizedBox(width: 8),
                Text('导出${taskStatusLabel(status)}',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            if (task.phase != null) ...[
              const SizedBox(height: 8),
              Text('阶段:${task.phase}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (percent != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: percent.clamp(0, 1)),
              ),
              const SizedBox(height: 4),
              Text('${(percent * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 8),
              Text('失败原因:${task.error!.message}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.error)),
            ],
            const SizedBox(height: 12),
            if (taskActive(status))
              OutlinedButton(
                onPressed: _cancelExport,
                child: const Text('取消导出'),
              ),
            if (status == TaskStatus.succeeded)
              FilledButton.icon(
                onPressed: _downloadArchive,
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载归档'),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────── 导入 Tab ──────────────────────────

class _ImportTab extends ConsumerStatefulWidget {
  const _ImportTab({this.client});

  final EdgecubeApiClient? client;

  @override
  ConsumerState<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<_ImportTab> {
  static const _chunkSize = 8 * 1024 * 1024;
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  PlatformFile? _file;
  bool _uploading = false;
  double _uploadPercent = 0;
  List<InstanceSummary> _items = const [];
  String? _targetId;

  String? _jobId;
  Task? _task;

  EdgecubeApiClient? get _client => widget.client ?? ref.read(edgecubeClientProvider);
  InstanceSummary? get _selected => ref.read(currentInstanceProvider);

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await loadInstanceItems(_client);
    if (mounted) setState(() => _items = items);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'tar', 'gz'],
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _file = files.first;
      _jobId = null;
      _task = null;
    });
  }

  /// 归档上传到目标实例 cwd 根目录,返回 cwd 内相对路径。
  Future<String> _uploadTo(String instanceId, PlatformFile file) async {
    final client = _client!;
    final total = await file.length();
    // 无本地路径(web)时预读全文,供下方内存分片
    final Uint8List? memBytes =
        (file.path == null) ? await file.readAsBytes() : null;
    final session = (await client.getFilesApi().initFileUpload(
          uploadInitRequest: UploadInitRequest((b) => b
            ..instanceId = instanceId
            ..path = '.'
            ..fileName = file.name
            ..sizeBytes = total),
        )).data!;
    final uploadId = session.uploadId;
    var offset = session.receivedBytes; // 断点续传:跳过服务端已有部分
    final raf = file.path == null ? null : File(file.path!).openSync();
    try {
      while (offset < total) {
        if (!mounted) return file.name;
        final len = math.min(_chunkSize, total - offset);
        final Uint8List chunk;
        if (raf != null) {
          raf.setPositionSync(offset);
          chunk = raf.readSync(len);
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
        if (mounted) {
          setState(() => _uploadPercent = total == 0 ? 0 : offset / total);
        }
      }
    } finally {
      raf?.closeSync();
    }
    final done = (await client.getFilesApi().completeFileUpload(
          uploadCompleteRequest: UploadCompleteRequest((b) => b
            ..uploadId = uploadId),
        )).data!;
    return done.path;
  }

  Future<void> _startImport() async {
    final client = _client;
    final file = _file;
    final targetId = _targetId ?? _selected?.id;
    if (client == null || file == null || targetId == null || _uploading) {
      _snack('请选择归档文件与目标实例');
      return;
    }
    setState(() => _uploading = true);
    try {
      final archivePath = await _uploadTo(targetId, file);
      if (!mounted) {
        setState(() => _uploading = false);
        return;
      }
      setState(() => _uploading = false);
      final accepted = (await client.getTransferApi().importInstance(
            importRequest: ImportRequest((b) => b
              ..sourceInstanceId = targetId
              ..archivePath = archivePath),
          )).data!;
      _snack('导入任务已开始');
      _startPolling(accepted.jobId);
    } catch (e) {
      if (mounted) setState(() => _uploading = false);
      _snack('导入失败:${apiErrorMessage(e)}');
    }
  }

  void _startPolling(String jobId) {
    _timer?.cancel();
    setState(() {
      _jobId = jobId;
      _task = null;
    });
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  Future<void> _poll() async {
    final client = _client;
    final jobId = _jobId;
    if (client == null || jobId == null || !mounted) return;
    try {
      final task = (await client.getTasksApi().getTask(jobId: jobId)).data!;
      if (!mounted) return;
      setState(() => _task = task);
      if (taskFinished(task.status)) {
        _timer?.cancel();
        if (task.status == TaskStatus.succeeded) {
          _snack('导入完成,新实例已创建');
          _loadItems();
        }
      }
    } catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      _snack('读取导入任务失败:${apiErrorMessage(e)}');
    }
  }

  bool get _importBusy {
    final task = _task;
    return _uploading || (task != null && !taskFinished(task.status));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择归档文件',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _importBusy ? null : _pickFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label:
                      Text(_file == null ? '选择 zip/tar.gz 归档' : _file!.name),
                ),
                const SizedBox(height: 4),
                Text(
                  '提示:归档应为 EdgeCube 导出文件(含 config.json 与 files/ 目录)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('上传到实例', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('归档先上传到所选实例的工作目录,再在该实例上解包还原为新实例',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _targetId ?? selected?.id,
                  decoration: const InputDecoration(
                    labelText: '目标实例(暂存归档)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in _items)
                      DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text('${s.name}(${s.id.substring(0, 8)}…)'),
                      ),
                    if (_items.isEmpty && selected != null)
                      DropdownMenuItem<String?>(
                        value: selected.id,
                        child: Text('${selected.name}(当前)'),
                      ),
                  ],
                  onChanged: _importBusy
                      ? null
                      : (v) => setState(() => _targetId = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_file == null || _importBusy) ? null : _startImport,
          icon: const Icon(Icons.download_outlined),
          label: Text(_uploading ? '上传中…' : '开始导入'),
        ),
        if (_uploading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _uploadPercent.clamp(0, 1)),
          ),
          const SizedBox(height: 4),
          Text(
            '上传进度:${(_uploadPercent * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
        if (_task != null) ...[
          const SizedBox(height: 16),
          _importTaskCard(_task!),
        ],
      ],
    );
  }

  Widget _importTaskCard(Task task) {
    final cs = Theme.of(context).colorScheme;
    final status = task.status;
    final progress = task.progress;
    final percent = progress?.percent;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status == TaskStatus.succeeded
                      ? Icons.check_circle
                      : status == TaskStatus.failed
                          ? Icons.error
                          : Icons.hourglass_top,
                  color: taskStatusColor(cs, status),
                ),
                const SizedBox(width: 8),
                Text('导入${taskStatusLabel(status)}',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            if (task.phase != null) ...[
              const SizedBox(height: 8),
              Text('阶段:${task.phase}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (percent != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: percent.clamp(0, 1)),
              ),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 8),
              Text('失败原因:${task.error!.message}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.error)),
            ],
            if (status == TaskStatus.succeeded) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                icon: const Icon(Icons.arrow_back),
                label: const Text('新实例已创建,返回查看'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}