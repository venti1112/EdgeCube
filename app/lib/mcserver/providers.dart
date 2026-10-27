import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 服务端目录 API。未连接时为 `null`。
final mcserverApiProvider = Provider<McserverApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : McserverApi(client);
});

/// 分类 + 类型表。
///
/// daemon 那边是编译期常量，但这里仍然走一次 RPC：**前端不硬编码任何源的知识**，
/// daemon 加一个服务端，App 不用改。缓存交给 Riverpod 自己。
final serverCatalogProvider = FutureProvider<ServerCatalog>((ref) async {
  final api = ref.watch(mcserverApiProvider);
  if (api == null) return ServerCatalog.empty;
  try {
    return await api.types();
  } on DaemonException catch (e) {
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return ServerCatalog.empty;
    }
    rethrow;
  }
});

/// 某个类型的版本列表（新版本在前）。
///
/// `autoDispose`：用户退出向导就该把结果扔掉 —— 版本列表可能有一两百条。
final serverVersionsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, type) async {
      final api = ref.watch(mcserverApiProvider);
      if (api == null) return const [];
      return api.versions(type);
    });

/// 查加载器版本的两个参数。
typedef LoaderQuery = ({String type, String mcVersion});

/// 某个 Minecraft 版本下可用的加载器版本（目前只有 Fabric）。
final serverLoadersProvider = FutureProvider.autoDispose
    .family<List<String>, LoaderQuery>((ref, query) async {
      final api = ref.watch(mcserverApiProvider);
      if (api == null) return const [];
      return api.loaders(type: query.type, mcVersion: query.mcVersion);
    });

/// 查下载计划的三个参数。
typedef PlanQuery = ({String type, String version, String? loaderVersion});

/// 「下什么」：下载地址 + 校验 + 文件名 + 建议启动命令。
final serverPlanProvider = FutureProvider.autoDispose
    .family<ServerPlan, PlanQuery>((ref, query) async {
      final api = ref.watch(mcserverApiProvider);
      if (api == null) {
        throw const DaemonException('unavailable', '还没有连接到守护进程');
      }
      return api.plan(
        type: query.type,
        version: query.version,
        loaderVersion: query.loaderVersion,
      );
    });
