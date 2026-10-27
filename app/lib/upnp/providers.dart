import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// daemon 推送 UPnP 状态变化的事件主题。
///
/// 事件里带的就是 `upnp.status` 的完整快照（网关 + 全部行），收到直接替换，
/// 不用回拉。变化点：网关状态翻转、某行映射成功 / 失败、行增删。
const String kUpnpEvtTopic = 'upnp.evt';

/// UPnP 的 RPC 接口。未连接时为 `null`。
final upnpApiProvider = Provider<UpnpApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : UpnpApi(client);
});

/// 状态总览（「网络映射」页那张卡）。
///
/// 两条路一起用（同 `monitor`）：
///
/// * 连上后先 `upnp.status` **拉一次** —— 那只是 daemon 的内存快照，不联网，
///   不拉的话要等下一个事件才知道现状；
/// * 之后的更新直接用 `upnp.evt` 事件里那份**完整快照**，不再回拉。
///
/// daemon 侧**不会**跟着这个订阅去联网：发现网关只在实例启停 / 点「重新探测」
/// 时发生，所以进页面本身不会触发网络探测。
final upnpStatusProvider =
    NotifierProvider<UpnpStatusNotifier, AsyncValue<UpnpStatus>>(
      UpnpStatusNotifier.new,
    );

class UpnpStatusNotifier extends Notifier<AsyncValue<UpnpStatus>> {
  @override
  AsyncValue<UpnpStatus> build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上 / 重连后由连接层自动补订
    unawaited(ref.read(connectionProvider.notifier).subscribe(kUpnpEvtTopic));
    if (client == null) return AsyncValue.loading();

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    unawaited(_fetchOnce(client));
    return AsyncValue.loading();
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['topic'] != kUpnpEvtTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    state = AsyncValue.data(
      UpnpStatus.fromJson(data.cast<String, dynamic>()),
    );
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final raw = await client.callObject('upnp.status');
      if (!ref.mounted) return;
      state = AsyncValue.data(UpnpStatus.fromJson(raw));
    } on DaemonException catch (error, stack) {
      if (!ref.mounted) return;
      state = AsyncValue.error(error, stack);
    }
  }

  /// 「重新探测」按钮：立即发现网关（可能等几秒超时）。
  ///
  /// daemon 在调用期间就会把 `searching` → `ready`/`error` 经 `upnp.evt`
  /// 推过来，这里拿到的返回只是最后定稿的那一份。失败时**保留旧快照**
  /// 并把异常抛给调用方（卡片弹提示），不把整张卡打成错误态。
  Future<void> probe() async {
    final api = ref.read(upnpApiProvider);
    if (api == null) return;
    final status = await api.probe();
    if (!ref.mounted) return;
    state = AsyncValue.data(status);
  }
}
