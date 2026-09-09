import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../server/server_service.dart';
import '../api_error.dart';
import '../labels.dart';
import 'download_flow_state.dart';

/// 下载流程收尾页:轮询 GET /tasks/{jobId} 展示下载进度,支持取消。
/// - 下载完成 → 清理向导会话 → 「进入实例列表」
/// - 失败/取消 → 「重新选择」(删除半成品实例后返回上一页) / 「返回实例列表」
/// 未完成时拦截系统返回,确认后取消任务并删除实例(对齐 V1 dispose 清理)。
class DownloadProgressPage extends ConsumerStatefulWidget {
  const DownloadProgressPage({super.key});

  @override
  ConsumerState<DownloadProgressPage> createState() =>
      _DownloadProgressPageState();
}

class _DownloadProgressPageState extends ConsumerState<DownloadProgressPage> {
  static const _pollInterval = Duration(seconds: 1);

  Timer? _pollTimer;
  Task? _task;
  bool _pollFailed = false;

  /// 任务是否已终结(成功/失败/取消),之后不拦截返回。
  bool _finished = false;

  String? get _jobId {
    final flow = ref.read(downloadFlowProvider);
    return flow?.downloadTaskId;
  }

  String? get _instanceId {
    final flow = ref.read(downloadFlowProvider);
    return flow?.instanceId;
  }

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _jobId;
      if (id == null) {
        // 无任务(异常直达本页):退回向导根页
        if (mounted) context.go('/servers/instances/create');
        return;
      }
      _startPolling(id);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollFailed = false;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetchTask(jobId));
  }

  Future<void> _fetchTask(String jobId) async {
    final client = _client;
    if (client == null) return;
    try {
      final task = (await client.getTasksApi().getTask(jobId: jobId)).data!;
      if (!mounted) return;
      setState(() {
        _task = task;
        _pollFailed = false;
        if (!taskActive(task.status)) {
          _finished = true;
          _pollTimer?.cancel();
        }
      });
      if (!taskActive(task.status)) {
        _cleanupFlow();
      }
    } catch (_) {
      // 轮询失败:停止自动刷新,展示重试按钮,避免死循环
      _pollTimer?.cancel();
      if (mounted) setState(() => _pollFailed = true);
    }
  }

  /// 任务终结后清理向导会话(实例已创建,不随会话删除)。
  void _cleanupFlow() {
    ref.read(downloadFlowProvider.notifier).clear();
  }

  Future<void> _cancelJob() async {
    final jobId = _jobId;
    final client = _client;
    if (jobId == null || client == null) return;
    try {
      final task = (await client.getTasksApi().cancelTask(jobId: jobId)).data;
      if (!mounted) return;
      setState(() => _task = task ?? _task);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  /// 尽力删除实例(失败清理场景,忽略错误)。
  Future<void> _deleteInstance() async {
    final id = _instanceId;
    final client = _client;
    if (id == null || client == null) return;
    try {
      await client.getInstancesApi().deleteInstance(instanceId: id);
    } catch (_) {}
  }

  /// 未完成时拦截系统返回/AppBar 返回:确认后取消任务并删除半成品实例。
  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃下载?'),
        content: const Text('返回将取消下载任务并删除已创建的实例。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续下载'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _pollTimer?.cancel();
    final jobId = _jobId;
    final client = _client;
    if (jobId != null && client != null) {
      try {
        await client.getTasksApi().cancelTask(jobId: jobId);
      } catch (_) {}
    }
    await _deleteInstance();
    ref.read(downloadFlowProvider.notifier).clear();
    if (mounted) context.go('/servers');
  }

  /// 失败/取消后「重新选择」:删除半成品实例并返回上一选择页。
  Future<void> _reselect() async {
    await _deleteInstance();
    ref.read(downloadFlowProvider.notifier).clear();
    if (mounted) context.pop();
  }

  void _retryPoll() {
    final id = _jobId;
    if (id == null) return;
    setState(() => _pollFailed = false);
    _startPolling(id);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(downloadFlowProvider);
    final instanceName = flow?.name ?? '该实例';
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('正在下载服务端'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '正在下载服务端',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '实例「$instanceName」已创建,等待下载完成后即可启动',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_pollFailed)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        '查询任务进度失败',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _retryPoll,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_task == null)
              const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('查询任务进度…'),
                    ],
                  ),
                ),
              )
            else
              _taskCard(_task!),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Task task) {
    final cs = Theme.of(context).colorScheme;
    final progress = task.progress;
    final terminal = !taskActive(task.status);
    final statusColor = taskStatusColor(cs, task.status);
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
                  terminal ? Icons.check_circle : Icons.downloading,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    taskStatusLabel(task.status),
                    style: TextStyle(fontSize: 16, color: statusColor),
                  ),
                ),
                if (taskActive(task.status))
                  TextButton.icon(
                    onPressed: _cancelJob,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('取消'),
                  ),
              ],
            ),
            if (task.phase != null) ...[
              const SizedBox(height: 4),
              Text(
                task.phase!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.percent,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_fmtBytes(progress.receivedBytes)} / '
                    '${_fmtBytes(progress.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (progress.speedBytesPerSec != null)
                    Text(
                      '${_fmtBytes(progress.speedBytesPerSec)}/s',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              if (progress.percent != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(progress.percent! * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (taskActive(task.status) && progress.etaSeconds != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '预计还需 ${_fmtEta(progress.etaSeconds!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (terminal) ...[
              const SizedBox(height: 8),
              if (task.status == TaskStatus.failed) ...[
                const Text('下载失败'),
                if (task.error?.message != null)
                  Text(
                    task.error!.message!,
                    style: TextStyle(color: cs.error),
                  ),
              ] else if (task.status == TaskStatus.cancelled)
                const Text('下载已取消'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (task.status == TaskStatus.failed ||
                      task.status == TaskStatus.cancelled) ...[
                    TextButton(
                      onPressed: _reselect,
                      child: const Text('重新选择'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => context.go('/servers'),
                      child: const Text('返回实例列表'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: () => context.go('/servers'),
                      icon: const Icon(Icons.format_list_bulleted),
                      label: const Text('进入实例列表'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 秒 → 人类可读剩余时间(≥1h 显示小时,否则 mm:ss)。
  static String _fmtEta(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return '$h小时$m分';
    }
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m分$s秒';
  }

  static String _fmtBytes(int? v) {
    if (v == null) return '未知';
    if (v >= 1 << 30) return '${(v / (1 << 30)).toStringAsFixed(2)}GB';
    if (v >= 1 << 20) return '${(v / (1 << 20)).toStringAsFixed(1)}MB';
    if (v >= 1 << 10) return '${(v / (1 << 10)).toStringAsFixed(1)}KB';
    return '${v}B';
  }
}