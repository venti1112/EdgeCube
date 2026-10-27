import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 下载队列 API。未连接时为 `null` —— 调用方先看连接状态。
final downloadApiProvider = Provider<DownloadApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : DownloadApi(client);
});

/// daemon 推的两条主题：进度（会重复推）与状态变化（只在变了时推）。
const String kDownloadProgressTopic = 'download.progress';
const String kDownloadStateTopic = 'download.state';

/// 全部下载任务（快照）。
final downloadListProvider = FutureProvider<DownloadList>((ref) async {
  final api = ref.watch(downloadApiProvider);
  if (api == null) return DownloadList.empty;
  try {
    return await api.list();
  } on DaemonException catch (e) {
    // 断开/正在关闭：当作空列表，让页面去提示连接状态
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return DownloadList.empty;
    }
    rethrow;
  }
});

/// 单个任务的进度。
///
/// **进页先拉一次快照，之后靠事件更新** —— 和 monitor 那套「首拉 + 订阅」一致。
/// 为什么不能只订阅：事件只推「变化」，进页那一刻任务可能已经下到一半了，
/// 光等下一个事件会先空一帧。
///
/// 订阅意图登记在 `build` 里：未连接时先记下，连上/重连后由连接层自动补订。
final downloadTaskProvider =
    NotifierProvider.autoDispose.family<DownloadTaskNotifier, DownloadTask?, String>(
      DownloadTaskNotifier.new,
    );

class DownloadTaskNotifier extends Notifier<DownloadTask?> {
  DownloadTaskNotifier(this.taskId);

  final String taskId;

  @override
  DownloadTask? build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上/重连后会自动补订
    unawaited(
      ref.read(connectionProvider.notifier).subscribe(kDownloadProgressTopic),
    );
    unawaited(
      ref.read(connectionProvider.notifier).subscribe(kDownloadStateTopic),
    );
    if (client == null) return null;

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_fetchOnce(client));
    return null;
  }

  /// 事件里就是**完整的任务对象**（与 `download.status` 同形），整份替换即可。
  void _onEvent(Map<String, dynamic> event) {
    final topic = event['topic'];
    if (topic != kDownloadProgressTopic && topic != kDownloadStateTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    final payload = data.cast<String, dynamic>();
    if (payload['id'] != taskId) return;
    state = DownloadTask.fromJson(payload);
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final task = await DownloadApi(client).status(taskId);
      // 期间连接可能已经换掉/销毁了，这时候写 state 会抛
      if (!ref.mounted) return;
      state = task;
    } on DaemonException {
      // 任务不存在（daemon 重启过？）：保持 null，页面自己决定怎么提示
      if (ref.mounted) state = null;
    }
  }
}

/// 实时下载队列：进页先拉一次快照，之后靠 daemon 的两条事件主题更新。
///
/// 为什么不用 [downloadListProvider]：那是一次性快照，队列在变（进度、状态），
/// 只靠它画面会卡在旧状态。这里订阅 `download.progress` / `download.state`，
/// 事件来了整份重取——与 [DownloadTaskNotifier] 同一套路（进页先拉 + 订阅）。
final downloadListStreamProvider =
    NotifierProvider.autoDispose<DownloadListNotifier, DownloadList>(
      DownloadListNotifier.new,
    );

class DownloadListNotifier extends Notifier<DownloadList> {
  @override
  DownloadList build() {
    final client = ref.watch(daemonClientProvider);
    // 未连接时也先登记订阅意图，连上/重连后由连接层自动补订
    unawaited(
      ref.read(connectionProvider.notifier).subscribe(kDownloadProgressTopic),
    );
    unawaited(
      ref.read(connectionProvider.notifier).subscribe(kDownloadStateTopic),
    );
    if (client == null) return DownloadList.empty;

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_fetch());
    return DownloadList.empty;
  }

  void _onEvent(Map<String, dynamic> event) {
    final topic = event['topic'];
    if (topic != kDownloadProgressTopic && topic != kDownloadStateTopic) return;
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final api = ref.read(downloadApiProvider);
    if (api == null) {
      state = DownloadList.empty;
      return;
    }
    try {
      state = await api.list();
    } on DaemonException {
      // 断线/重启：保持空列表，让界面去提示连接状态，而不是把整页变红
      state = DownloadList.empty;
    }
  }
}
