import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 工作流任务 API。未连接时为 `null` —— 调用方先看连接状态。
final taskApiProvider = Provider<TaskApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : TaskApi(client);
});

/// daemon 推的两条主题：状态变化（含步骤级）与步骤进度。
const String kTaskStateTopic = 'task.state';
const String kTaskProgressTopic = 'task.progress';

/// 全部任务（快照）。任务列表页用；不用它做「当前任务」的轮询。
final taskListProvider = FutureProvider<TaskList>((ref) async {
  final api = ref.watch(taskApiProvider);
  if (api == null) return TaskList.empty;
  try {
    return await api.list();
  } on DaemonException catch (e) {
    // 断开/正在关闭：当作空列表，让页面去提示连接状态
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return TaskList.empty;
    }
    rethrow;
  }
});

/// 单个任务的实时状态。
///
/// **进页先拉一次快照，之后靠事件更新** —— 与 `downloadTaskProvider` 同一套
/// 做法。为什么不能只订阅：事件只在「变了」时推，进页那一刻任务可能已经跑到
/// 第三步了，光等下一个事件会先空一帧（页面会闪一下「准备中」）。
///
/// 订阅意图登记在 `build` 里：未连接时先记下，连上/重连后由连接层自动补订。
final taskProvider =
    NotifierProvider.autoDispose.family<TaskNotifier, TaskView?, String>(
      TaskNotifier.new,
    );

class TaskNotifier extends Notifier<TaskView?> {
  TaskNotifier(this.taskId);

  final String taskId;

  @override
  TaskView? build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上/重连后会自动补订
    unawaited(ref.read(connectionProvider.notifier).subscribe(kTaskStateTopic));
    unawaited(ref.read(connectionProvider.notifier).subscribe(kTaskProgressTopic));
    if (client == null) return null;

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_fetchOnce(client));
    return null;
  }

  /// 事件里就是**完整的任务对象**（与 `task.get` 同形），整份替换即可。
  ///
  /// 两条主题共用同一个形状是有意的：`task.state` 只在步骤状态变了时推，
  /// `task.progress` 在步骤进行中反复推 —— 页面不需要区分，谁先到谁生效。
  void _onEvent(Map<String, dynamic> event) {
    final topic = event['topic'];
    if (topic != kTaskStateTopic && topic != kTaskProgressTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    final payload = data.cast<String, dynamic>();
    if (payload['id'] != taskId) return;
    state = TaskView.fromJson(payload);
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final task = await TaskApi(client).get(taskId);
      // 期间连接可能已经换掉/销毁了，这时候写 state 会抛
      if (!ref.mounted) return;
      state = task;
    } on DaemonException {
      // 任务不存在（daemon 重启过？）：保持 null，页面自己决定怎么提示
      if (ref.mounted) state = null;
    }
  }
}
