import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/server_service.dart';
import '../settings/appearance.dart';

/// 全局「当前操作实例」状态(对齐 V1 `InstanceController.selected`):
/// 同一时间只能选中一个实例,服务器页正文、文件/控制台等操作页均作用于该实例。
///
/// 选中项按服务器持久化:连接某服务器后其 overview 落地时自动恢复上次选中,
/// 无记录或记录已失效时回退到第一个实例;切换服务器/会话变化时自动重置。
final currentInstanceProvider =
    NotifierProvider<CurrentInstanceNotifier, InstanceSummary?>(
  CurrentInstanceNotifier.new,
);

class CurrentInstanceNotifier extends Notifier<InstanceSummary?> {
  static const _storagePrefix = 'selectedInstanceId_';

  @override
  InstanceSummary? build() {
    // 服务器/会话变化时自动重置选中,等待服务器页 overview 落地后恢复
    ref.watch(currentServerIdProvider);
    ref.watch(sessionProvider);
    return null;
  }

  /// 切换选中实例并持久化(选择弹窗点击 / 实例创建成功后调用)。
  Future<void> select(InstanceSummary summary) async {
    state = summary;
    await _persist(summary.id);
  }

  /// 服务器页 overview 落地后调用:
  /// - 当前选中仍存在:用最新摘要刷新(状态/名称等随列表更新);
  /// - 否则按持久化记录恢复;记录失效或从未选中过时回退到第一个实例。
  Future<void> syncWithOverview(InstanceOverview overview) async {
    final items = overview.items;
    final current = state;
    if (current != null) {
      final latest = _find(items, current.id);
      if (latest != null) {
        state = latest;
        return;
      }
      // 当前选中已被删除,走下方恢复逻辑
    }
    final serverId = ref.read(currentServerIdProvider);
    final savedId = await _readSavedId(serverId);
    final saved = savedId == null ? null : _find(items, savedId);
    if (saved != null) {
      await select(saved);
      return;
    }
    if (items.isNotEmpty) {
      await select(items.first);
    }
  }

  static InstanceSummary? _find(Iterable<InstanceSummary> items, String id) {
    for (final s in items) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _persist(String instanceId) async {
    final serverId = ref.read(currentServerIdProvider);
    if (serverId == null) return;
    await ref.read(storageProvider).write('$_storagePrefix$serverId', instanceId);
  }

  Future<String?> _readSavedId(String? serverId) async {
    if (serverId == null) return null;
    final raw =
        await ref.read(storageProvider).read('$_storagePrefix$serverId');
    return (raw == null || raw.isEmpty) ? null : raw;
  }
}