import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../connection/client.dart';
import '../../download/format.dart';
import '../../instance/providers.dart';
import '../../task/api.dart';
import '../../task/models.dart';
import '../../task/providers.dart';
import 'wizard.dart';

/// 流程最后一页：**提交 `instance-provision` 工作流，然后看它跑**。
///
/// 以前这里是前端自己串三步（`mcserver.plan` → `instance.create` →
/// `download.add`）。现在 `task.submit` 一次就把「准备服务端 → 创建实例 →
/// 下载服务端」交给 daemon 编排，页面只做两件事：把用户的选择交出去、
/// 把任务的进展画出来。
///
/// 这么改换来的东西：
///
/// * **失败不用前端收拾**：下载失败时 daemon 会逆序回滚（把刚建的实例删掉），
///   页面只需据 `rolled_back` 说一句「已自动删除」—— 不再有那份
///   「只删自己建的、页面还在才删」的手写回滚逻辑；
/// * **能看到每一步**：任务对象带steps，所以这里画的是「准备 / 创建 / 下载」
///   三步的清单，而不是一个笼统的转圈；
/// * **中途返回不中断**：任务在 daemon 那边跑完，页面只是不再显示。
///
/// 取消（返回上一页）走的是向导自己的返回，**不调 `task.cancel`** ——
/// 与「中途返回不中断下载」是同一条取舍。
class DownloadProgressPage extends ConsumerStatefulWidget {
  const DownloadProgressPage({super.key, required this.wizard});

  final DownloadWizard wizard;

  @override
  ConsumerState<DownloadProgressPage> createState() =>
      _DownloadProgressPageState();
}

class _DownloadProgressPageState extends ConsumerState<DownloadProgressPage> {
  String? _taskId;

  /// `task.submit` 那次调用的失败（参数不合法、没连上、工作流不存在……）。
  ///
  /// 注意这**只覆盖提交那一下**：任务跑起来之后的失败在任务对象里
  /// （见 [_failureMessage]）。
  Object? _submitError;
  bool _running = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _submitError = null;
    });

    final tasks = ref.read(taskApiProvider);
    if (tasks == null) {
      setState(() {
        _running = false;
        _submitError = const DaemonException('unavailable', '还没有连接到守护进程');
      });
      return;
    }

    final wizard = widget.wizard;
    final kind = wizard.kind;
    if (kind == null) {
      setState(() {
        _running = false;
        _submitError = const DaemonException('invalid_params', '没有选择服务端类型');
      });
      return;
    }

    final params = <String, dynamic>{
      'name': wizard.name,
      'type': kind.id,
      if (wizard.version != null) 'version': wizard.version,
      if (wizard.loaderVersion != null) 'loader_version': wizard.loaderVersion,
    };

    try {
      final task = await tasks.submit('instance-provision', params);
      if (!mounted) return;
      setState(() {
        _running = false;
        _taskId = task.id;
      });
    } catch (error) {
      if (!mounted) return;
      // 提交就被拒 = 没有任务、也没建过任何东西，**不需要**回滚
      setState(() {
        _running = false;
        _submitError = error;
      });
    }
  }

  /// 失败后重试：把上一轮的结果清掉，重新提交一次。
  ///
  /// 不用手工清理残局：daemon 在失败时已经把这次建的实例回滚掉了。
  /// 万一回滚也失败（实例还在），重试会撞 `instance_name_taken`，
  /// 报错信息本身就会说清楚。
  Future<void> _retry() async {
    setState(() {
      _submitError = null;
      _taskId = null;
      _finishing = false;
    });
    await _start();
  }

  /// 成功后收尾：刷新列表、关掉向导。
  void _finish() {
    if (_finishing || !mounted) return;
    _finishing = true;
    ref.invalidate(instanceListProvider);
    ref.invalidate(selectedInstanceDetailProvider);
    finishDownloadFlow(context);
  }

  @override
  Widget build(BuildContext context) {
    final taskId = _taskId;
    final task = taskId == null ? null : ref.watch(taskProvider(taskId));

    // 跑完就自动收尾。延迟一小会儿是为了让用户看到最后一步走完 ——
    // 否则最后一帧和关页几乎同时发生，看起来像「没跑完就跳走了」。
    if (task != null && task.state == TaskState.completed && !_finishing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _finish();
        });
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_title(task)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _body(task),
        ),
      ),
    );
  }

  String _title(TaskView? task) {
    if (task != null && task.title.isNotEmpty) return task.title;
    return '下载服务端';
  }

  Widget _body(TaskView? task) {
    final failure = _failureMessage(task);
    if (failure == null) {
      if (task == null) return const _PreparingView();
      return _ProgressView(task: task, summary: widget.wizard.summary);
    }
    return _FailureView(
      message: failure,
      hint: _rollbackHint(task),
      // 失败时也把清单画出来：用户一眼能看到卡在哪一步、哪几步没跑
      checklist: task == null ? null : _StepChecklist(task: task),
      onRetry: _retry,
      onBack: () => Navigator.of(context).pop(),
    );
  }

  /// 失败时给人看的那句话；没问题时返回 `null`。
  ///
  /// 两个来源：**提交那一下**（[DaemonException]，码很稳定）与**任务本身**
  /// 落到 `failed`（错误在失败那一步上，带稳定码前缀）。
  String? _failureMessage(TaskView? task) {
    if (_submitError case final error?) {
      if (error is DaemonException) return describeTaskError(error);
      return '$error';
    }
    if (task == null) return null;

    if (task.state == TaskState.cancelled) {
      return '任务已取消。已经建好的东西不会自动删掉。';
    }
    if (task.state != TaskState.failed) return null;

    // 失败那一步的错误最有用；拿不到就退回任务级的原因
    final step = _failedStep(task);
    final stepError = step?.error;
    if (stepError != null && stepError.isNotEmpty) {
      return '${step!.title}失败：${stepErrorText(stepError)}';
    }
    return task.errorMessage == null ? '任务失败' : stepErrorText(task.errorMessage);
  }

  static TaskStep? _failedStep(TaskView task) {
    for (final step in task.steps) {
      if (step.status == TaskStepStatus.failed) return step;
    }
    return null;
  }

  /// 回滚那一句补充说明。
  String? _rollbackHint(TaskView? task) {
    if (task == null || !task.rolledBack) return null;
    return '刚建好的实例已自动删除，不会留在服务器列表里';
  }
}

/// 准备中：`task.submit` 还没回来。
class _PreparingView extends StatelessWidget {
  const _PreparingView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('正在准备下载…'),
      ],
    );
  }
}

/// 进行中：三步清单 + 下载细节。
class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.task, required this.summary});

  final TaskView task;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = task.downloadPercent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 72,
            height: 72,
            // 总大小还不知道时画不确定进度（引擎要等第一块数据到了才有这个值）
            child: percent == null
                ? const CircularProgressIndicator(strokeWidth: 6)
                : CircularProgressIndicator(value: percent / 100, strokeWidth: 6),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _headline(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            summary,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
        if (_downloadLine() case final line?) ...[
          const SizedBox(height: 12),
          Text(line, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (_speedLine() case final line?) ...[
          const SizedBox(height: 4),
          Text(
            line,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        // 工作流把「准备 → 创建 → 下载」摊开了，就照着画出来 ——
        // 出问题时用户一眼能看到卡在哪一步
        _StepChecklist(task: task),
      ],
    );
  }

  /// 标题那句话：正在跑哪一步、走到第几步。
  ///
  /// 带上「(2/3)」是因为多步流程里「还剩几步」比「在干嘛」更让人安心。
  String _headline() {
    final step = task.runningStep;
    final position = task.currentStepNumber;
    final total = task.steps.length;
    if (step != null) {
      return total == 0 ? step.title : '${step.title}（$position/$total）';
    }
    return position == 0 ? '正在准备…' : '正在处理（$position/$total）';
  }

  /// 下载那一步的步骤进度（`{downloaded, total, speed, eta_seconds}`）。
  Map<String, dynamic>? get _downloadProgress {
    for (final step in task.steps) {
      final progress = step.progress;
      if (progress != null && progress['downloaded'] is num) return progress;
    }
    return null;
  }

  /// `41.5% · 1.5 MB / 3.6 MB`，不知道总大小时只报已下载的量。
  String? _downloadLine() {
    final progress = _downloadProgress;
    if (progress == null) return null;
    final done = formatBytes((progress['downloaded'] as num).toInt());
    final total = progress['total'];
    if (total is! num || total <= 0) return done;
    final percent = task.downloadPercent;
    final head = percent == null ? '' : '${percent.toStringAsFixed(1)}% · ';
    return '$head$done / ${formatBytes(total.toInt())}';
  }

  String? _speedLine() {
    final progress = _downloadProgress;
    if (progress == null) return null;
    final speed = progress['speed'];
    if (speed is! num || speed <= 0) return null;
    final text = formatSpeed(speed.toInt());
    final eta = progress['eta_seconds'];
    if (eta is! num || eta <= 0) return text;
    return '$text · 剩余 ${formatEta(eta.toInt())}';
  }
}

/// 三步清单。当前那步转圈，完成的打勾，跳过/回滚用灰色说明。
class _StepChecklist extends StatelessWidget {
  const _StepChecklist({required this.task});

  final TaskView task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in task.steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 22, height: 22, child: _icon(step, scheme)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: TextStyle(
                      color: _isMuted(step) ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
                if (_trailing(step) case final text?)
                  Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static bool _isMuted(TaskStep step) =>
      step.status == TaskStepStatus.skipped ||
      step.status == TaskStepStatus.rolledBack ||
      step.status == TaskStepStatus.pending;

  Widget _icon(TaskStep step, ColorScheme scheme) => switch (step.status) {
    TaskStepStatus.completed => Icon(
      Icons.check_circle,
      size: 20,
      color: scheme.primary,
    ),
    TaskStepStatus.running => const CircularProgressIndicator(strokeWidth: 2.5),
    TaskStepStatus.failed => Icon(Icons.error, size: 20, color: scheme.error),
    TaskStepStatus.rolledBack => const Icon(Icons.undo, size: 18),
    TaskStepStatus.skipped => const Icon(Icons.remove, size: 18),
    _ => const Icon(Icons.circle_outlined, size: 18),
  };

  static String? _trailing(TaskStep step) => switch (step.status) {
    TaskStepStatus.rolledBack => '已撤销',
    TaskStepStatus.skipped => '未执行',
    _ => null,
  };
}

/// 失败：图标 + 原因 + （有的话）步骤清单 + 重试 / 返回。
class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.message,
    required this.hint,
    required this.checklist,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final String? hint;

  /// 失败时也要能看到「跑到哪一步了」—— 传 `null` 表示这一轮还没拿到任务对象。
  final Widget? checklist;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (checklist != null) ...[
            const SizedBox(height: 20),
            checklist!,
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: onBack, child: const Text('返回')),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
