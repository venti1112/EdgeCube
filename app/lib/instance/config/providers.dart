import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/client.dart';
import '../../connection/state.dart';
import 'api.dart';

/// 「服务器配置」接口。未连接时为 `null`。
final instanceConfigApiProvider = Provider<InstanceConfigApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : InstanceConfigApi(client);
});

/// 某个实例的服务端配置（快照）。
///
/// 只在进页面时取一次：配置是「读 → 改 → 写」的会话式编辑，中途被别人改了也
/// 不该悄悄覆盖用户正在敲的东西（那正是「保存」得用户自己按的原因）。所以这里
/// **不订阅任何事件**，要重新读就重进页面。
final instanceConfigProvider =
    FutureProvider.autoDispose.family<InstanceConfigSource, String>((
      ref,
      id,
    ) async {
      final api = ref.watch(instanceConfigApiProvider);
      if (api == null) {
        throw const DaemonException('unavailable', '还没有连接到守护进程');
      }
      return api.get(id);
    });
