import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';

/// daemon 推送在线玩家变化的事件主题。
const String kPlayersTopic = 'instance.players';

/// 某个实例的玩家名单读写接口；未连接时为 `null`。
final playersApiProvider = Provider.family<PlayersApi?, String>((ref, id) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : PlayersApi(client, id);
});

/// 某个实例的在线玩家。
///
/// **名单是 daemon 解析出来的**，本 Provider 只做两件事：连上后拉一次快照
/// （`instance.players.online`），之后收 `instance.players` 事件 —— 事件里就是
/// 完整名单，整份替换即可，不用再回拉一次。
///
/// 为什么不在 App 里解析日志：服务端不提供「谁在线」这种接口，只能从输出里认人，
/// 而控制台历史是有上限的一段；前端拿它解析，断线或错过一帧就必然漏事件。
/// 进程在 daemon 手里，从头到尾的输出流只有它拿得到。
///
/// 订阅意图登记在 `build` 里：未连接时先记下，连上/重连后由连接层自动补订。
/// 连接换了（`daemonClientProvider` 变了）本 Provider 自动重跑，旧的事件订阅
/// 在 `onDispose` 里取消。
final onlinePlayersProvider =
    NotifierProvider.autoDispose.family<OnlinePlayersNotifier, List<String>, String>(
      OnlinePlayersNotifier.new,
    );

class OnlinePlayersNotifier extends Notifier<List<String>> {
  OnlinePlayersNotifier(this.instanceId);

  final String instanceId;

  @override
  List<String> build() {
    final client = ref.watch(daemonClientProvider);

    // 未连接时也登记：连上/重连后会自动补订
    unawaited(ref.read(connectionProvider.notifier).subscribe(kPlayersTopic));
    if (client == null) return const [];

    final subscription = client.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);

    // 首帧别等第一次变化：连上时可能已经有人在服务器里
    unawaited(_fetchOnce(client));
    return const [];
  }

  /// 推送就是完整名单，整份替换即可（daemon 只在名单真的变了时才推）。
  void _onEvent(Map<String, dynamic> event) {
    if (event['topic'] != kPlayersTopic) return;
    final data = event['data'];
    if (data is! Map || data['id'] != instanceId) return;
    state = _sortedNames(data['players']);
  }

  Future<void> _fetchOnce(DaemonClient client) async {
    try {
      final raw = await client.callObject(
        'instance.players.online',
        params: {'id': instanceId},
      );
      // 期间连接可能已经换掉/销毁了，这时候写 state 会抛
      if (!ref.mounted) return;
      state = _sortedNames(raw['players']);
    } on DaemonException {
      // 断线 / 实例刚被删：当作没人 —— 页面本来就有「服务端未运行」这一层提示
      if (ref.mounted) state = const [];
    }
  }

  /// 名单排过序再显示（`toList()..sort()`）。
  static List<String> _sortedNames(Object? players) {
    if (players is! List) return const [];
    return [
      for (final name in players)
        if (name is String) name,
    ]..sort();
  }
}
