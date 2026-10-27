/// 工作流任务的线上模型。
///
/// 字段名与 daemon 的**线上格式**一一对应（snake_case）。四个方法
/// （`task.submit` / `task.get` / `task.list`）与两条事件主题
/// （`task.state` / `task.progress`）返回**同一个形状** ——
/// 所以一套模型就能同时吃快照与推送。
library;

/// 任务状态。
///
/// daemon 用小写字符串；认不出来的值一律当 [unknown]，页面不该因为
/// 「daemon 加了个状态」就崩。
enum TaskState {
  /// 已入队但还没拿到并发额度。
  queued,
  running,
  completed,
  failed,

  /// 被取消了（`task.cancel`，或 daemon 关闭）。
  cancelled,

  /// 本端不认识的状态。
  unknown;

  static TaskState parse(Object? raw) => switch (raw) {
    'queued' => TaskState.queued,
    'running' => TaskState.running,
    'completed' => TaskState.completed,
    'failed' => TaskState.failed,
    'cancelled' => TaskState.cancelled,
    _ => TaskState.unknown,
  };

  /// 还在跑（排队也算）。
  bool get isActive => this == TaskState.queued || this == TaskState.running;

  /// 已经有结论了。
  bool get isFinished =>
      this == TaskState.completed ||
      this == TaskState.failed ||
      this == TaskState.cancelled;
}

/// 单个步骤的状态。
enum TaskStepStatus {
  pending,
  running,
  completed,
  failed,

  /// 前一步挂了，这一步没跑。
  skipped,

  /// 这一步被回滚掉了（前一步失败，引擎逆序撤销已完成的可回滚步骤）。
  rolledBack,
  unknown;

  static TaskStepStatus parse(Object? raw) => switch (raw) {
    'pending' => TaskStepStatus.pending,
    'running' => TaskStepStatus.running,
    'completed' => TaskStepStatus.completed,
    'failed' => TaskStepStatus.failed,
    'skipped' => TaskStepStatus.skipped,
    'rolled_back' => TaskStepStatus.rolledBack,
    _ => TaskStepStatus.unknown,
  };

  bool get isDone =>
      this == TaskStepStatus.completed ||
      this == TaskStepStatus.failed ||
      this == TaskStepStatus.skipped ||
      this == TaskStepStatus.rolledBack;
}

/// 任务里的一个步骤。
class TaskStep {
  const TaskStep({
    required this.id,
    required this.name,
    required this.title,
    required this.stepType,
    required this.status,
    this.progress,
    this.output,
    this.error,
    this.attempts = 0,
    this.durationMs = 0,
  });

  final String id;

  /// flow 内的步骤名（也是步骤间传递产出用的键）。
  final String name;

  /// 展示用标题（如「创建实例」）。
  final String title;

  /// 步骤类型（如 `instance.create`）—— 出问题时用来定位是哪个模块。
  final String stepType;

  final TaskStepStatus status;

  /// 步骤自己报的进度，形状由步骤定；下载类步骤是
  /// `{percent, downloaded, total, speed, eta_seconds}`。
  final Map<String, dynamic>? progress;

  /// 步骤的产出（下一步骤会读它）。**只有成功**的步骤有。
  final Map<String, dynamic>? output;

  /// 失败原因。**字符串自带稳定错误码前缀**（`instance_name_taken：…`）。
  final String? error;

  final int attempts;
  final int durationMs;

  static TaskStep fromJson(Map<String, dynamic> json) {
    final progress = json['progress'];
    final output = json['output'];
    return TaskStep(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      stepType: json['step_type']?.toString() ?? '',
      status: TaskStepStatus.parse(json['status']),
      progress: progress is Map ? progress.cast<String, dynamic>() : null,
      output: output is Map ? output.cast<String, dynamic>() : null,
      error: json['error']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一份完整的工作流任务。快照接口与两条事件主题共用这个形状。
class TaskView {
  const TaskView({
    required this.id,
    required this.flow,
    required this.title,
    required this.state,
    required this.steps,
    this.params = const {},
    this.currentStep,
    this.error,
    this.rolledBack = false,
    this.createdAtMs,
    this.startedAtMs,
    this.finishedAtMs,
    this.totalDurationMs,
  });

  final String id;

  /// 工作流名（如 `instance-provision`）。
  final String flow;

  /// 工作流的展示标题（如「创建实例并下载服务端」）。
  final String title;

  final TaskState state;

  /// 提交时的参数，原样回传（排查用）。
  final Map<String, dynamic> params;

  /// 当前正在跑（或最后跑过）的步骤名。
  final String? currentStep;

  final List<TaskStep> steps;

  /// 任务的整体失败原因，daemon 给的是
  /// `{step, message}` —— 见 [errorStep] / [errorMessage]。
  final Map<String, dynamic>? error;

  /// 失败后被回滚过（例如「实例已自动删除」）。
  final bool rolledBack;

  final int? createdAtMs;
  final int? startedAtMs;
  final int? finishedAtMs;
  final int? totalDurationMs;

  static TaskView fromJson(Map<String, dynamic> json) {
    final params = json['params'];
    final error = json['error'];
    final steps = json['steps'];
    return TaskView(
      id: json['id']?.toString() ?? '',
      flow: json['flow']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      state: TaskState.parse(json['state']),
      params: params is Map ? params.cast<String, dynamic>() : const {},
      currentStep: json['current_step']?.toString(),
      steps: steps is List
          ? steps
                .whereType<Map>()
                .map((step) => TaskStep.fromJson(step.cast<String, dynamic>()))
                .toList(growable: false)
          : const [],
      error: error is Map ? error.cast<String, dynamic>() : null,
      rolledBack: json['rolled_back'] == true,
      createdAtMs: (json['created_at_ms'] as num?)?.toInt(),
      startedAtMs: (json['started_at_ms'] as num?)?.toInt(),
      finishedAtMs: (json['finished_at_ms'] as num?)?.toInt(),
      totalDurationMs: (json['total_duration_ms'] as num?)?.toInt(),
    );
  }

  /// 失败那一步的名字（daemon 放在 `error.step` 里）。
  String? get errorStep => error?['step']?.toString();

  /// 失败原因那句话（已带错误码前缀）。
  String? get errorMessage => error?['message']?.toString();

  /// 正在跑的步骤；没有就返回 `null`。
  TaskStep? get runningStep {
    for (final step in steps) {
      if (step.status == TaskStepStatus.running) return step;
    }
    return null;
  }

  /// 「第几步 / 共几步」—— 给「正在创建实例（2/3）」这类文案用。
  ///
  /// 取**第一个还没结束**的步骤；全都结束了就取最后一步。
  int get currentStepNumber {
    if (steps.isEmpty) return 0;
    for (var i = 0; i < steps.length; i++) {
      if (!steps[i].status.isDone) return i + 1;
    }
    return steps.length;
  }

  /// 下载类步骤报的百分比（0-100）；没在下载就是 `null`。
  ///
  /// 步骤还没拿到总大小时 daemon 报 `null` —— 那种情况返回 `null`（画不确定
  /// 进度），**不要**退化成 0，否则进度条会先跳回原点。
  double? get downloadPercent {
    for (final step in steps) {
      final percent = step.progress?['percent'];
      if (percent is num) return percent.toDouble().clamp(0, 100);
    }
    return null;
  }
}

/// `task.list` 的返回。
class TaskList {
  const TaskList(this.tasks);

  final List<TaskView> tasks;

  static const TaskList empty = TaskList([]);

  int get count => tasks.length;

  static TaskList fromJson(Map<String, dynamic> json) {
    final tasks = json['tasks'];
    if (tasks is! List) return TaskList.empty;
    return TaskList(
      tasks
          .whereType<Map>()
          .map((task) => TaskView.fromJson(task.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

/// 工作流清单里的一条（`task.flows` 的载荷）—— 只用于展示有哪些流程可用。
class FlowSummary {
  const FlowSummary({required this.name, required this.title, this.stepTitles = const []});

  final String name;
  final String title;
  final List<String> stepTitles;

  static FlowSummary fromJson(Map<String, dynamic> json) {
    final steps = json['steps'];
    return FlowSummary(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      stepTitles: steps is List
          ? steps
                .whereType<Map>()
                .map((step) => step['title']?.toString() ?? '')
                .where((title) => title.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}
