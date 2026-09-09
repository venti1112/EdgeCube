import 'dart:async';

import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'labels.dart';

/// 安装运行时页:按类型拉取官方源可安装版本清单(Java: Adoptium JRE),
/// 逐项发起安装(POST /runtimes/install → 202 jobId),轮询 GET /tasks/{jobId}
/// 展示进度,支持取消。daemon 同一时间仅允许一个安装任务(409 task_conflict)。
class RuntimeInstallPage extends ConsumerStatefulWidget {
  const RuntimeInstallPage({super.key});

  @override
  ConsumerState<RuntimeInstallPage> createState() => _RuntimeInstallPageState();
}

/// 单个版本安装任务的页内状态。
class _InstallJob {
  _InstallJob({required this.taskId});

  final String taskId;
  Task? task;

  /// 进度轮询失败(展示重试,停止自动刷新)。
  bool pollFailed = false;
}

class _RuntimeInstallPageState extends ConsumerState<RuntimeInstallPage> {
  static const _pollInterval = Duration(seconds: 1);

  RuntimeType _type = RuntimeType.java;

  /// FRPC 是否已展开旧版本(默认收起:只展示最新版,不请求任何旧版本信息)。
  bool _showAll = false;

  RuntimeCatalog? _catalog;
  List<RuntimeInfo> _installed = [];
  bool _loading = true;
  String? _error;

  /// 提交中的安装任务:version -> 页内任务状态(终结后成功即移除)。
  final Map<String, _InstallJob> _jobs = {};
  Timer? _pollTimer;

  /// 是否正在提交安装请求(防连点)。
  bool _submitting = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
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

  /// 拉取可安装清单与已安装列表(已安装版本在清单中打勾)。
  Future<void> _load({bool retried = false}) async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final catalogResp =
          await client.getRuntimesApi().getRuntimeCatalog(type: _type);
      final installedResp = await client.getRuntimesApi().listRuntimes();
      final catalog = catalogResp.data;
      final installed = installedResp.data?.toList() ?? <RuntimeInfo>[];
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _installed = installed;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      // 瞬时连接失败(隧道/网络抖动)自动重试一次,避免误报「无法连接服务器」
      if (!retried &&
          e is DioException &&
          switch (e.type) {
            DioExceptionType.connectionTimeout ||
            DioExceptionType.receiveTimeout ||
            DioExceptionType.connectionError =>
              true,
            _ => false,
          }) {
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        return _load(retried: true);
      }
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  bool _isInstalled(String version) =>
      _installed.any((r) => r.type == _type && r.version == version);

  /// 展开/收起旧版本(仅 FRPC):展开才请求全量清单,收起恢复仅最新。
  void _toggleShowAll() {
    setState(() {
      _showAll = !_showAll;
      _catalog = null;
      _error = null;
    });
    _load();
  }

  /// 发起安装:POST /runtimes/install → 202 jobId,开始轮询。
  Future<void> _install(RuntimeCatalogEntry entry) async {
    if (_activeJob != null || _submitting) return;
    final client = _client;
    if (client == null) {
      _snack('未连接到服务器');
      return;
    }
    setState(() => _submitting = true);
    try {
      final resp = await client.getRuntimesApi().installRuntime(
            runtimeInstallRequest: RuntimeInstallRequest((b) => b
              ..type = _type
              ..version = entry.version),
          );
      final jobId = resp.data?.jobId;
      if (!mounted) return;
      if (jobId == null) {
        _snack('安装任务创建失败');
      } else {
        setState(() {
          _jobs[entry.version] = _InstallJob(taskId: jobId);
          _startPolling();
        });
      }
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 当前进行中的安装(daemon 全局同时只允许一个安装任务)。
  MapEntry<String, _InstallJob>? get _activeJob {
    for (final e in _jobs.entries) {
      final status = e.value.task?.status;
      if (status == null || taskActive(status)) return e;
    }
    return null;
  }

  /// 取消某版本的安装任务。
  Future<void> _cancel(String version) async {
    final job = _jobs[version];
    final client = _client;
    if (job == null || client == null) return;
    try {
      final task = (await client.getTasksApi().cancelTask(jobId: job.taskId)).data;
      if (!mounted) return;
      setState(() {
        job.task = task ?? job.task;
        job.pollFailed = false;
      });
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  /// 轮询全部安装任务(通常至多一个),终结时收尾。
  void _startPolling() {
    _pollTimer?.cancel();
    if (_jobs.isEmpty) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final client = _client;
    if (client == null) return;
    if (_jobs.isEmpty) {
      _pollTimer?.cancel();
      return;
    }
    var anyActive = false;
    for (final entry in _jobs.entries.toList()) {
      final job = entry.value;
      final status = job.task?.status;
      if (status != null && !taskActive(status)) continue; // 终结等待展示
      try {
        final task = (await client.getTasksApi().getTask(jobId: job.taskId)).data!;
        if (!mounted) return;
        setState(() {
          job.task = task;
          job.pollFailed = false;
        });
        if (taskActive(task.status)) {
          anyActive = true;
        } else if (task.status == TaskStatus.succeeded) {
          // 安装成功:移除任务并刷新已安装列表
          setState(() => _jobs.remove(entry.key));
          _snack('${runtimeTypeLabel(_type)} ${entry.key} 安装完成');
          _load();
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => job.pollFailed = true);
        _pollTimer?.cancel();
        return;
      }
    }
    if (!anyActive) _pollTimer?.cancel();
  }

  void _retryPoll() {
    for (final job in _jobs.values) {
      job.pollFailed = false;
    }
    _startPolling();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('安装运行时'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<RuntimeType>(
              segments: const [
                ButtonSegment(
                  value: RuntimeType.java,
                  icon: Icon(Icons.coffee_outlined),
                  label: Text('Java'),
                ),
                ButtonSegment(
                  value: RuntimeType.php,
                  icon: Icon(Icons.integration_instructions_outlined),
                  label: Text('PHP'),
                ),
                ButtonSegment(
                  value: RuntimeType.frpc,
                  icon: Icon(Icons.hub_outlined),
                  label: Text('FRPC'),
                ),
              ],
              selected: {_type},
              // java/php/frpc 均从官方源在线安装
              onSelectionChanged: (selection) {
                final next = selection.first;
                if (next == _type) return;
                if (_activeJob != null) {
                  _snack('有安装任务进行中,完成后再切换类型');
                  return;
                }
                setState(() {
                  _type = next;
                  _catalog = null;
                  // 切回 FRPC 时默认收起旧版本(不请求旧版本信息)
                  _showAll = false;
                });
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '环境统一安装到 daemon 数据目录的 runtimes 目录,并可为每个实例选择使用。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading && _catalog == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _catalog == null
                    ? _errorView()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _list(_catalog!.entries.toList()),
                      ),
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
        Center(child: Text('加载失败:$_error')),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _list(List<RuntimeCatalogEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.inbox_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '官方源暂无可安装版本',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      children: [
        // FRPC:默认仅展示最新版(后端只请求最新 release),点展开才拉旧版本
        if (_type == RuntimeType.frpc)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: cs.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: Icon(
                _showAll ? Icons.expand_less : Icons.expand_more,
                color: cs.primary,
              ),
              title: Text(_showAll ? '收起旧版本' : '展开旧版本'),
              subtitle: Text(
                _showAll
                    ? '已展示全部版本'
                    : '默认仅展示最新版本,展开才会拉取旧版本信息',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              onTap: _toggleShowAll,
            ),
          ),
        for (final entry in entries) ...[
          _entryTile(entry),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _entryTile(RuntimeCatalogEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final installed = _isInstalled(entry.version);
    final job = _jobs[entry.version];
    final activeJob = _activeJob;
    final busyOther = activeJob != null && activeJob.key != entry.version;

    final subtitle = StringBuffer('推荐组合 · 官方源下载');
    if (entry.sizeBytes != null) {
      subtitle.write(' · ${_fmtBytes(entry.sizeBytes)}');
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    switch (_type) {
                      RuntimeType.java => Icons.coffee_outlined,
                      RuntimeType.php => Icons.integration_instructions_outlined,
                      RuntimeType.frpc => Icons.hub_outlined,
                      _ => Icons.memory_outlined,
                    },
                    size: 20,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.version,
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (installed) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle,
                                size: 16, color: Colors.green),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.toString(),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (job == null)
                  FilledButton.tonal(
                    onPressed: installed || busyOther || _submitting
                        ? null
                        : () => _install(entry),
                    child: Text(installed ? '已安装' : '安装'),
                  ),
              ],
            ),
            if (job != null) ...[
              const SizedBox(height: 10),
              _jobProgress(entry.version, job),
            ],
          ],
        ),
      ),
    );
  }

  /// 单版本安装任务的进度/结果区。
  Widget _jobProgress(String version, _InstallJob job) {
    final cs = Theme.of(context).colorScheme;
    final task = job.task;

    if (job.pollFailed) {
      return Row(
        children: [
          Text('查询进度失败', style: TextStyle(color: cs.error)),
          const Spacer(),
          TextButton(onPressed: _retryPoll, child: const Text('重试')),
        ],
      );
    }
    if (task == null) {
      return const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('正在创建安装任务…'),
        ],
      );
    }

    final progress = task.progress;
    final terminal = !taskActive(task.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              switch (task.status) {
                TaskStatus.succeeded => Icons.check_circle,
                TaskStatus.failed => Icons.error_outline,
                TaskStatus.cancelled => Icons.cancel_outlined,
                _ => Icons.downloading,
              },
              size: 18,
              color: taskStatusColor(cs, task.status),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${taskStatusLabel(task.status)}'
                '${task.phase == null ? '' : ' · ${task.phase}'}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (!terminal)
              TextButton.icon(
                onPressed: () => _cancel(version),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('取消'),
              ),
          ],
        ),
        if (!terminal) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress?.percent,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_fmtBytes(progress?.receivedBytes)} / ${_fmtBytes(progress?.totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (progress?.speedBytesPerSec != null)
                Text(
                  '${_fmtBytes(progress!.speedBytesPerSec)}/s',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
        if (terminal && task.status != TaskStatus.succeeded) ...[
          if (task.error?.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                task.error!.message!,
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _jobs.remove(version));
                _startPolling();
              },
              child: const Text('关闭'),
            ),
          ),
        ],
      ],
    );
  }

  static String _fmtBytes(int? v) {
    if (v == null) return '未知';
    if (v >= 1 << 30) return '${(v / (1 << 30)).toStringAsFixed(2)}GB';
    if (v >= 1 << 20) return '${(v / (1 << 20)).toStringAsFixed(1)}MB';
    if (v >= 1 << 10) return '${(v / (1 << 10)).toStringAsFixed(1)}KB';
    return '${v}B';
  }
}
