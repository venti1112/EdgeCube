import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// daemon 推送 STUN 状态变化的事件主题。
///
/// 事件里带的就是 `stun.status` 的完整快照（设置 + 全部隧道行），收到直接替换，
/// 不用回拉。变化点：设置保存、行增删、某条隧道的相位 / 地址 / 错误翻转。
///
/// 速度统计**不推** —— 那是每秒都在动的东西，卡片可见时由界面每秒
/// `refresh()` 补这一口（同 FRP 运行日志的理由）。
const String kStunEvtTopic = 'stun.evt';

/// STUN 的 RPC 接口。未连接时为 `null`。
final stunApiProvider = Provider<StunApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : StunApi(client);
});

/// 状态总览（「网络映射」页那张 STUN 卡）。
///
/// 两条路一起用（同 `monitor` / `upnp`）：
///
/// * 连上后先 `stun.status` **拉一次** —— 那只是 daemon 的内存快照，不联网；
/// * 之后的更新直接用 `stun.evt` 事件里那份**完整快照**，不再回拉。
///
/// daemon 侧**不会**跟着这个订阅去联网：隧道只在实例启停 / 设置变更时建拆，
/// 所以进页面本身不会触发任何探测。
final stunStatusProvider =
    NotifierProvider<StunStatusNotifier, AsyncValue<StunStatus>>(
      StunStatusNotifier.new,
    );

class StunStatusNotifier extends Notifier<AsyncValue<StunStatus>> {
  @override
  AsyncValue<StunStatus> build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上 / 重连后由连接层自动补订
    unawaited(ref.read(connectionProvider.notifier).subscribe(kStunEvtTopic));
    if (client == null) return AsyncValue.loading();

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_fetchOnce(client));
    return AsyncValue.loading();
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['topic'] != kStunEvtTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    state = AsyncValue.data(StunStatus.fromJson(data.cast<String, dynamic>()));
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final raw = await client.callObject('stun.status');
      if (!ref.mounted) return;
      state = AsyncValue.data(StunStatus.fromJson(raw));
    } on DaemonException catch (error, stack) {
      if (!ref.mounted) return;
      state = AsyncValue.error(error, stack);
    }
  }

  /// 重拉一次总览（速度统计这类事件不推的字段靠它）。失败保留旧快照。
  Future<void> refresh() async {
    final api = ref.read(stunApiProvider);
    if (api == null) return;
    try {
      final status = await api.status();
      if (!ref.mounted) return;
      state = AsyncValue.data(status);
    } on DaemonException {
      // 网络抖动 / 正在关闭：保旧快照，下一次刷新再补
    }
  }
}

/// 隧道日志（环形缓冲快照，最多 500 行）。
///
/// 日志行 daemon **不推**（每行一条消息对一个调试看板太重了，同 FRP 运行日志
/// 的理由）—— 卡片可见且隧道在探测 / 转发时，由界面每秒 invalidate 一次；
/// 「清空日志」后也 invalidate 它重拉。
final stunLogsProvider = FutureProvider<StunLogs>((ref) async {
  final api = ref.watch(stunApiProvider);
  if (api == null) return StunLogs.empty;
  try {
    return await api.logs();
  } on DaemonException catch (e) {
    // 断开 / 正在关闭：当作空日志，页面自己去提示连接状态
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return StunLogs.empty;
    }
    rethrow;
  }
});
