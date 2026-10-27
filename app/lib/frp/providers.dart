import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// daemon 推送授权进度的事件主题（`waiting` / `success` / `error`）。
const String kFrpLoginTopic = 'frp.login';

/// FRP 的 RPC 接口。未连接时为 `null` —— 调用方要先看连接状态。
final frpApiProvider = Provider<FrpApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : FrpApi(client);
});

/// 平台清单。以 daemon 为唯一真源（登录方式的能力判断也在那边），
/// 所以这里不缓存到本地，每次进「选择映射平台」重拉一次。
final frpProvidersProvider = FutureProvider<List<FrpProvider>>((ref) async {
  final api = ref.watch(frpApiProvider);
  if (api == null) return const [];
  try {
    return await api.providers();
  } on DaemonException catch (e) {
    // 断开 / 正在关闭：当作空清单，页面自己去提示连接状态
    if (e.code == 'disconnected' || e.code == 'unavailable') return const [];
    rethrow;
  }
});

/// 本地已保存的隧道列表。
///
/// 保存 / 删除之后调 `ref.invalidate(frpTunnelsProvider)` 重拉；
/// daemon 不为隧道列表推事件（只有授权进度有主题）。
final frpTunnelsProvider = FutureProvider<List<FrpSavedTunnel>>((ref) async {
  final api = ref.watch(frpApiProvider);
  if (api == null) return const [];
  try {
    return await api.tunnels();
  } on DaemonException catch (e) {
    if (e.code == 'disconnected' || e.code == 'unavailable') return const [];
    rethrow;
  }
});

/// 从平台清单里按 key 找一个（找不到返回 `null`）。
FrpProvider? findFrpProvider(List<FrpProvider> providers, String key) {
  for (final provider in providers) {
    if (provider.key == key) return provider;
  }
  return null;
}

// ══════════════════════════════════════════════════════════════════════════
// FRP 实例的运行
// ══════════════════════════════════════════════════════════════════════════

/// daemon 推送运行态变化的主题（某条隧道起了 / 退出了 / 起不来）。
const String kFrpRunTopic = 'frp.run';

/// 订阅 `frp.run`：运行态一变就重拉运行清单。
///
/// 与页面解耦（页面只要 `watch` 这个 Provider 就自动跟上）：隧道是**独立实例**，
/// 它可能在别的页面被起停（比如游戏实例的「连带启动」），本页也得跟着变。
final Provider<void> frpRunEventsProvider = Provider<void>((ref) {
  // 未连接时只是登记意图，连上 / 重连后由连接层补订
  unawaited(ref.read(connectionProvider.notifier).subscribe(kFrpRunTopic));

  final client = ref.watch(daemonClientProvider);
  if (client == null) return;
  final subscription = client.events.listen((event) {
    if (event['topic'] != kFrpRunTopic) return;
    ref.invalidate(frpRunsProvider);
    // 运行页看的是单条（含日志），也让它重拉
    final localId = event['data'] is Map
        ? (event['data'] as Map)['local_id']
        : null;
    if (localId is String && localId.isNotEmpty) {
      ref.invalidate(frpRunProvider(localId));
    }
  });
  ref.onDispose(subscription.cancel);
});

/// 能拿来跑隧道的 frpc 运行环境 + 当前生效的那个（「网络映射」页的 FRP 卡）。
final frpRuntimesProvider = FutureProvider<FrpcRuntimeList>((ref) async {
  final api = ref.watch(frpApiProvider);
  if (api == null) return FrpcRuntimeList.empty;
  try {
    return await api.runtimes();
  } on DaemonException catch (e) {
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return FrpcRuntimeList.empty;
    }
    rethrow;
  }
});

/// 所有 FRP 实例的运行态，按隧道 id 索引（列表页拿它 join 隧道）。
///
/// 查不到的隧道 = 从来没起过（`frp.run.list` 里没有它的记录），
/// 界面按「未运行」画。
final FutureProvider<Map<String, FrpRun>> frpRunsProvider =
    FutureProvider<Map<String, FrpRun>>((ref) async {
      // 先挂上订阅意图，再取快照 —— 反过来会漏掉这中间的状态变化
      ref.watch(frpRunEventsProvider);
      final api = ref.watch(frpApiProvider);
      if (api == null) return const {};
      try {
        final runs = await api.runs();
        return {for (final run in runs) run.localId: run};
      } on DaemonException catch (e) {
        if (e.code == 'disconnected' || e.code == 'unavailable') {
          return const {};
        }
        rethrow;
      }
    });

/// 单条隧道的运行态（**含日志**）—— 运行页看的东西。
final frpRunProvider = FutureProvider.autoDispose.family<FrpRun?, String>((
  ref,
  localId,
) async {
  ref.watch(frpRunEventsProvider);
  final api = ref.watch(frpApiProvider);
  if (api == null) return null;
  return api.run(localId);
});
