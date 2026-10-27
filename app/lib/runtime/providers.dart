import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 运行环境 API。未连接时为 `null` —— 调用方先看连接状态。
final runtimeApiProvider = Provider<RuntimeApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : RuntimeApi(client);
});

/// 厂商 / 包类型表 + 本机平台。
final runtimeCatalogProvider = FutureProvider<RuntimeCatalog>((ref) async {
  final api = ref.watch(runtimeApiProvider);
  if (api == null) return _emptyCatalog;
  try {
    return await api.catalog();
  } on DaemonException catch (e) {
    if (e.code == 'disconnected' || e.code == 'unavailable') return _emptyCatalog;
    rethrow;
  }
});

const RuntimeCatalog _emptyCatalog = RuntimeCatalog(
  providers: [],
  packageTypes: [],
  defaultProvider: 'zulu',
  defaultPackageType: 'jdk',
  supported: false,
);

/// 拉版本列表的参数。
///
/// [all] = 「历史版本」那个开关：`false`（默认）只拉最新一个，
/// `true` 才拉完整列表。**默认值必须是 false** —— frp 的清单走 GitHub API，
/// 未认证只有 60 次/小时。
typedef RuntimeVersionQuery = ({String provider, String packageType, bool all});

final runtimeVersionsProvider = FutureProvider.autoDispose
    .family<RuntimeVersions, RuntimeVersionQuery>((ref, query) async {
      final api = ref.watch(runtimeApiProvider);
      if (api == null) {
        throw const DaemonException('unavailable', '还没有连接到守护进程');
      }
      return api.versions(
        provider: query.provider,
        packageType: query.packageType,
        all: query.all,
      );
    });

/// 全部环境（快照）。
final runtimeListProvider = FutureProvider<RuntimeEnvList>((ref) async {
  final api = ref.watch(runtimeApiProvider);
  if (api == null) return RuntimeEnvList.empty;
  try {
    return await api.list();
  } on DaemonException catch (e) {
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return RuntimeEnvList.empty;
    }
    rethrow;
  }
});

/// 订阅 `runtime.state`：装到哪一步了就重取列表。
///
/// 载荷是**完整的环境对象**，但列表很小（个位数环境），整份重取比在本地做
/// 「按 id 合并」简单且不会有合并错的时候。下载进度不走这条
/// （那是 `download.progress`，页面拿 `env.taskId` 去订）。
final runtimeEventsProvider = Provider<void>((ref) {
  // 未连接时只是登记订阅意图，连上/重连后由连接层自动补订
  unawaited(ref.read(connectionProvider.notifier).subscribe('runtime.state'));

  final client = ref.watch(daemonClientProvider);
  if (client == null) return;

  final subscription = client.events.listen((event) {
    if (event['topic'] != 'runtime.state') return;
    ref.invalidate(runtimeListProvider);
  });
  ref.onDispose(subscription.cancel);
});
