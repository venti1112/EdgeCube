import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'labels.dart';

/// 任务列表页:下载/启动/停止/重启/强杀等后台任务。
/// 进行中(queued/running)任务在前,定时轮询 + 下拉刷新更新进度,可取消进行中任务。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  List<Task>? _tasks;
  bool _loading = true;
  String? _error;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final list = (await client.getTasksApi().listTasks(pageSize: 50)).data!;
      if (!mounted) return;
      setState(() {
        _tasks = list.items.toList();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _cancel(Task task) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消任务'),
        content: Text('确定取消「${taskKindLabel(task.kind)}」任务吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('取消任务'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await client.getTasksApi().cancelTask(jobId: task.id);
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('任务'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading && tasks == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: tasks == null
                  ? _errorView()
                  : _list(tasks),
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

  Widget _list(List<Task> tasks) {
    if (tasks.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.hourglass_empty, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '暂无任务',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (final task in tasks) ...[
          _TaskCard(task: task, onCancel: () => _cancel(task)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onCancel});

  final Task task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = taskStatusColor(cs, task.status);
    final active = taskActive(task.status);
    final progress = task.progress;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_kindIcon(task.kind), size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  taskKindLabel(task.kind),
                  style: const TextStyle(fontSize: 16),
                ),
                if (task.instanceId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.instanceId!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (active) ...[
                  TextButton(onPressed: onCancel, child: const Text('取消')),
                  const SizedBox(width: 8),
                ],
                _StatusChip(statusColor: statusColor, label: taskStatusLabel(task.status)),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.percent,
                  minHeight: 6,
                ),
              ),
            ],
            if (task.status == TaskStatus.failed && task.error != null) ...[
              const SizedBox(height: 8),
              Text(
                task.error!.message ?? task.error!.code ?? '任务失败',
                style: TextStyle(color: cs.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(TaskKind k) => switch (k) {
        TaskKind.start => Icons.play_arrow,
        TaskKind.stop => Icons.stop,
        TaskKind.restart => Icons.restart_alt,
        TaskKind.kill => Icons.bolt,
        TaskKind.download => Icons.cloud_download_outlined,
        TaskKind.export_ => Icons.archive_outlined,
        TaskKind.backup => Icons.backup_outlined,
        TaskKind.compress => Icons.folder_zip_outlined,
        TaskKind.extract => Icons.unarchive_outlined,
        TaskKind.analyze => Icons.fact_check_outlined,
        _ => Icons.help_outline,
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.statusColor, required this.label});

  final Color statusColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: statusColor)),
    );
  }
}