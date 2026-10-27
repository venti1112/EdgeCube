import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'models.dart';

/// daemon 周期性推送系统状态的事件主题。
const String kMonitorStatsTopic = 'monitor.stats';

/// 系统状态快照（设备内存 + 整机 CPU 使用率）。
///
/// 两条路一起用，缺一不可：
///
/// * 连上后先 `monitor.snapshot` **拉一次** —— daemon 的采样器虽然常驻，
///   但干等第一个 `monitor.stats` 会白等一个采样间隔（默认 2s）；
/// * 之后的更新直接用事件里那份**完整快照**，不再回一次 `monitor.snapshot`
///   —— 事件里带的就是 `monitor.snapshot` 的返回值，回拉等于把 WS 流量翻倍。
///
/// 订阅意图登记在 `build` 里：未连接时先记下，连上/重连后由连接层自动补订，
/// 页面不用自己处理断开与重连。连接换了（`daemonClientProvider` 变了）本 Provider
/// 自动重跑，旧的事件订阅在 `onDispose` 里取消。
final monitorSnapshotProvider =
    NotifierProvider<MonitorSnapshotNotifier, AsyncValue<SystemSnapshot>>(
      MonitorSnapshotNotifier.new,
    );

class MonitorSnapshotNotifier extends Notifier<AsyncValue<SystemSnapshot>> {
  @override
  AsyncValue<SystemSnapshot> build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上/重连后会自动补订
    unawaited(
      ref.read(connectionProvider.notifier).subscribe(kMonitorStatsTopic),
    );
    if (client == null) return AsyncValue.loading();

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    // 首帧别等第一个采样间隔
    unawaited(_fetchOnce(client));
    return AsyncValue.loading();
  }

  /// 推送直接就是完整快照，塞进去即可。
  void _onEvent(Map<String, dynamic> event) {
    if (event['topic'] != kMonitorStatsTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    state = AsyncValue.data(SystemSnapshot.fromJson(data.cast<String, dynamic>()));
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final raw = await client.callObject('monitor.snapshot');
      // 期间连接可能已经换掉/销毁了，这时候写 state 会抛
      if (!ref.mounted) return;
      state = AsyncValue.data(SystemSnapshot.fromJson(raw));
    } on DaemonException catch (error, stack) {
      if (!ref.mounted) return;
      state = AsyncValue.error(error, stack);
    }
  }
}
