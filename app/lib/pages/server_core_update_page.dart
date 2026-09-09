import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'labels.dart';

/// 服务端核心更新页(Paper 系):
/// - 进入即调用 `GET /instances/{id}/core-update/check`,展示当前/最新版本对比;
/// - 有更新时提交 `POST /instances/{id}/core-update`(下载新 jar 替换,旧 jar
///   重命名 .disabled),轮询 `GET /tasks/{jobId}` 显示进度,完成后再检查。
///
/// 仅 Paper/Purpur/Spigot/CraftBukkit 等 Java 实例支持(supported=false 提示)。
/// 实例必须已停止(运行中更新会被后端 409 拒绝)。
class ServerCoreUpdatePage extends ConsumerStatefulWidget {
  const ServerCoreUpdatePage({super.key});

  @override
  ConsumerState<ServerCoreUpdatePage> createState() =>
      _ServerCoreUpdatePageState();
}

class _ServerCoreUpdatePageState extends ConsumerState<ServerCoreUpdatePage> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  bool _loading = true;
  String? _error;
  ServerCoreUpdateCheck? _check;
  bool _submitting = false;

  String? _jobId;
  Task? _task;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);
  InstanceSummary? get _selected => ref.read(currentInstanceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final client = _client;
    final instance = _selected;
    if (client == null || instance == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final check = (await client
              .getServerCoreApi()
              .checkServerCoreUpdate(instanceId: instance.id))
          .data!;
      if (!mounted) return;
      setState(() {
        _check = check;
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

  Future<void> _startUpdate() async {
    final client = _client;
    final instance = _selected;
    final check = _check;
    if (client == null || instance == null || check == null || _submitting) {
      return;
    }
    // 更新前确认(替换核心 jar,旧 jar 改名 .disabled)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新服务端核心'),
        content: Text(
          '将下载 ${check.latestVersion ?? '最新版本'} '
          'build ${check.latestBuild ?? '?'} 并替换现有核心 jar。'
          '旧 jar 会被重命名为 .disabled。确定继续吗?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('更新'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final url = check.downloadUrl;
    if (url == null || url.isEmpty) {
      _snack('暂无可用下载地址,无法更新');
      return;
    }

    setState(() => _submitting = true);
    try {
      final accepted = (await client.getServerCoreApi().updateServerCore(
            instanceId: instance.id,
            serverCoreUpdateRequest: ServerCoreUpdateRequest((b) => b
              ..downloadUrl = url
              ..sha256 = check.sha256
              ..fileName = null),
          )).data!;
      _snack('更新任务已开始');
      _startPolling(accepted.jobId);
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
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
          _snack('服务端核心已更新');
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _load();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      _snack('读取更新任务失败:${apiErrorMessage(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = _selected;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务端更新'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: instance == null
          ? _emptyView('请先在服务器页选择一个实例')
          : _loading && _check == null
              ? const Center(child: CircularProgressIndicator())
              : _check == null
                  ? _errorView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          _summaryCard(instance),
                          const SizedBox(height: 16),
                          if (!_check!.supported)
                            _unsupportedCard()
                          else ...[
                            _versionCard(_check!),
                            const SizedBox(height: 16),
                            if (_task != null) _taskCard(_task!),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _summaryCard(InstanceSummary instance) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text(instance.name),
        subtitle: Text(instance.id),
      ),
    );
  }

  Widget _unsupportedCard() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.block, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('该实例暂不支持服务端核心更新',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '仅支持 Paper/Purpur/Spigot/CraftBukkit 等 Java 服务端的核心 jar 更新,'
              '且需能识别工作目录中的核心文件。',
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

  Widget _versionCard(ServerCoreUpdateCheck check) {
    final cs = Theme.of(context).colorScheme;
    final hasUpdate = check.updateAvailable ?? false;
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
                  hasUpdate ? Icons.system_update_alt : Icons.check_circle,
                  color: hasUpdate ? cs.primary : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  hasUpdate ? '发现新版本' : '已是最新版本',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _versionRow(
                '当前版本',
                (check.currentVersion == null ||
                        check.currentVersion!.isEmpty)
                    ? '未知'
                    : check.currentVersion!),
            if (check.currentBuild != null)
              _versionRow('当前构建', check.currentBuild!),
            _versionRow('最新版本', check.latestVersion ?? '未知'),
            _versionRow('最新构建', check.latestBuild ?? '未知'),
            const SizedBox(height: 12),
            if (hasUpdate)
              FilledButton.icon(
                onPressed: _submitting ? null : _startUpdate,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('立即更新'),
              )
            else
              Text(
                '核心已保持最新,无需更新',
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

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
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
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
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
                Text('核心更新${taskStatusLabel(status)}',
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
          ],
        ),
      ),
    );
  }

  Widget _emptyView(String text) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.dns_outlined, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text(text)),
      ],
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
        Center(child: Text('检查失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: _load, child: const Text('重试')),
        ),
      ],
    );
  }
}