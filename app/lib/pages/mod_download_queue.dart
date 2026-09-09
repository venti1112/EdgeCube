import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'labels.dart';

/// 当前实例的「单文件下载」任务(download_single_file)集合。
///
/// 下载队列基于 V2 任务系统:每个任务绑定一个 aria2 下载任务 gid,按实例分组
/// FIFO 串行执行,经 `GET /tasks?instanceId=` 轮询进度/状态,`DELETE /tasks/{jobId}`
/// 取消,`DELETE /instances/{id}/mods/downloads` 清除已终结任务。
List<Task> downloadTasksOf(List<Task> tasks) =>
    tasks.where((t) => t.kind == TaskKind.downloadSingleFile).toList();

Future<List<Task>> _fetchDownloadTasks(
    EdgecubeApiClient client, String instanceId) async {
  final list =
      (await client.getTasksApi().listTasks(instanceId: instanceId, pageSize: 50))
          .data!;
  return downloadTasksOf(list.items.toList());
}

String _formatSpeed(int bytesPerSec) {
  if (bytesPerSec < 1024) return '$bytesPerSec B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

String _formatEta(int seconds) {
  if (seconds < 0) return '';
  if (seconds < 60) return '~${seconds}s';
  return '~${(seconds / 60).ceil()}m';
}

/// 下载队列横幅:顶部显示当前下载进度/排队数,点击弹层查看明细。
/// 无 download_single_file 任务时隐藏。
class DownloadQueueBanner extends ConsumerStatefulWidget {
  const DownloadQueueBanner({super.key, required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<DownloadQueueBanner> createState() =>
      _DownloadQueueBannerState();
}

class _DownloadQueueBannerState extends ConsumerState<DownloadQueueBanner> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  List<Task> _tasks = const [];

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final tasks = await _fetchDownloadTasks(client, widget.instanceId);
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (_) {
      // 轮询失败静默,保持上次状态
    }
  }

  Task? get _current =>
      _tasks.where((t) => t.status == TaskStatus.running).firstOrNull;
  int get _queued => _tasks.where((t) => t.status == TaskStatus.queued).length;
  int get _finished => _tasks.where((t) => taskFinished(t.status)).length;

  @override
  Widget build(BuildContext context) {
    if (_tasks.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final current = _current;
    final progress = current?.progress;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showDownloadQueueSheet(context, instanceId: widget.instanceId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (current != null)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: (progress?.percent != null)
                        ? CircularProgressIndicator(
                            value: progress!.percent,
                            strokeWidth: 2.5,
                          )
                        : const CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(Icons.download_done, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current?.displayName ??
                            (_queued > 0 ? '等待下载' : '下载队列'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (current != null && progress != null)
                        Text(
                          [
                            if (progress.percent != null)
                              '${(progress.percent! * 100).toInt()}%',
                            if (progress.speedBytesPerSec != null &&
                                progress.speedBytesPerSec! > 0)
                              _formatSpeed(progress.speedBytesPerSec!),
                            if (progress.etaSeconds != null &&
                                progress.etaSeconds! > 0)
                              _formatEta(progress.etaSeconds!),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onPrimaryContainer),
                        )
                      else
                        Text(
                          [
                            if (_queued > 0) '$_queued 个排队',
                            if (_finished > 0) '$_finished 个已完成',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开下载队列详情弹层(对齐 V1「查看队列」体验)。
void showDownloadQueueSheet(BuildContext context, {required String instanceId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _DownloadQueueSheet(instanceId: instanceId),
  );
}

class _DownloadQueueSheet extends ConsumerStatefulWidget {
  const _DownloadQueueSheet({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_DownloadQueueSheet> createState() =>
      _DownloadQueueSheetState();
}

class _DownloadQueueSheetState extends ConsumerState<_DownloadQueueSheet> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  List<Task> _tasks = const [];
  bool _busy = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      final tasks = await _fetchDownloadTasks(client, widget.instanceId);
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (_) {
      // 静默
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 取消全部进行中(queued/running)任务。
  Future<void> _cancelAll() async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    try {
      for (final t in _tasks.where((t) => taskActive(t.status))) {
        try {
          await client.getTasksApi().cancelTask(jobId: t.id);
        } catch (_) {
          // 单个失败继续
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 清除已终结任务。
  Future<void> _clearFinished() async {
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    try {
      final resp =
          await client.getInstancesApi().clearFinishedModDownloads(instanceId: widget.instanceId);
      _snack('已清除 ${resp.data?.cleared ?? 0} 个已完成任务');
      await _refresh();
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOne(Task task) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.getTasksApi().cancelTask(jobId: task.id);
      await _refresh();
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks.reversed.toList(); // 最新的在上
    final hasActive = _tasks.any((t) => taskActive(t.status));
    final hasFinished = _tasks.any((t) => taskFinished(t.status));
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
                  child: Text('下载队列',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (hasActive)
                  TextButton(
                    onPressed: _busy ? null : _cancelAll,
                    child: const Text('取消全部'),
                  ),
                if (hasFinished)
                  TextButton(
                    onPressed: _busy ? null : _clearFinished,
                    child: const Text('清除已完成'),
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
            child: tasks.isEmpty
                ? const Center(child: Text('暂无下载任务'))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: tasks.length,
                    itemBuilder: (ctx, i) =>
                        _QueueTile(task: tasks[i], onCancel: () => _cancelOne(tasks[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.task, required this.onCancel});

  final Task task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = taskActive(task.status);
    final progress = task.progress;
    final statusColor = taskStatusColor(cs, task.status);
    return ListTile(
      leading: Icon(
        active ? Icons.downloading : Icons.download_done,
        color: statusColor,
      ),
      title: Text(
        task.displayName ?? taskKindLabel(task.kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress?.percent != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress!.percent, minHeight: 4),
            const SizedBox(height: 2),
            Text(
              [
                if (progress.percent != null)
                  '${(progress.percent! * 100).toInt()}%',
                if (progress.receivedBytes != null && progress.totalBytes != null)
                  '${_formatBytes(progress.receivedBytes!)} / ${_formatBytes(progress.totalBytes!)}',
                if (progress.speedBytesPerSec != null &&
                    progress.speedBytesPerSec! > 0)
                  _formatSpeed(progress.speedBytesPerSec!),
                if (progress.etaSeconds != null && progress.etaSeconds! > 0)
                  _formatEta(progress.etaSeconds!),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ] else if (task.status == TaskStatus.failed && task.error != null)
            Text(
              task.error!.message ?? task.error!.code ?? '下载失败',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.error, fontSize: 12),
            )
          else
            Text(
              taskStatusLabel(task.status),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
      trailing: active
          ? IconButton(
              tooltip: '取消',
              onPressed: onCancel,
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
