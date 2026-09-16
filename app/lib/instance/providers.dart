import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 实例管理 API。未连接时为 `null` —— 调用方要先看连接状态。
final instanceApiProvider = Provider<InstanceApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : InstanceApi(client);
});

/// 实例列表。
///
/// 通过 [instanceApiProvider] 间接依赖连接：重连后客户端换了实例，
/// 本 Provider 自动重跑，列表跟着刷新，页面不用管。
final instanceListProvider = FutureProvider<InstanceList>((ref) async {
  final api = ref.watch(instanceApiProvider);
  if (api == null) return InstanceList.empty;
  try {
    return await api.list();
  } on DaemonException catch (e) {
    // 断开/正在关闭：当作空列表，让页面去提示连接状态
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return InstanceList.empty;
    }
    rethrow;
  }
});

/// 当前选中的实例 id（由 daemon 的索引决定）。
final selectedInstanceIdProvider = Provider<String?>((ref) {
  return ref.watch(instanceListProvider).value?.selected;
});

/// 选中实例的「元数据 + 状态」。
final selectedInstanceDetailProvider = FutureProvider<InstanceDetail?>((
  ref,
) async {
  final api = ref.watch(instanceApiProvider);
  final id = ref.watch(selectedInstanceIdProvider);
  if (api == null || id == null) return null;
  // 两个调用都很轻（读两个小 JSON + 扫一次目录），串行就够了
  final instance = await api.get(id);
  final status = await api.status(id);
  return InstanceDetail(instance: instance, status: status);
});

/// 订阅 `instance.*` 事件：别的客户端建/删/改实例时，本端列表自动刷新。
///
/// 自己的改动也会触发一次（顶多多取一次列表，列表本身很小），
/// 换来的是「不用区分事件来源」这点简单。页面 `watch` 它即可。
final instanceEventsProvider = Provider<void>((ref) {
  // 未连接时只是登记订阅意图，连上/重连后由连接层自动补订
  unawaited(ref.read(connectionProvider.notifier).subscribe('instance.*'));

  final client = ref.watch(daemonClientProvider);
  if (client == null) return;

  final subscription = client.events.listen((event) {
    final topic = event['topic'];
    if (topic is! String || !topic.startsWith('instance.')) return;
    ref.invalidate(instanceListProvider);
    ref.invalidate(selectedInstanceDetailProvider);
  });
  ref.onDispose(subscription.cancel);
});
