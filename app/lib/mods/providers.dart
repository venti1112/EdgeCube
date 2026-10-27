import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import 'api.dart';
import 'models.dart';

/// 模组 / 插件接口。未连接时为 `null` —— 调用方先看连接状态。
final modsApiProvider = Provider<ModsApi?>((ref) {
  final client = ref.watch(daemonClientProvider);
  return client == null ? null : ModsApi(client);
});

/// 源 / 项目类型 / 加载器 / 排序表。
///
/// 页面上的每个筛选器都从这一份来 —— **前端不硬编码任何平台名、加载器名**，
/// 所以 daemon 加一个源不需要改 App（与 `runtimeCatalogProvider` 同一个套路）。
final modsCatalogProvider = FutureProvider<ModCatalog>((ref) async {
  final api = ref.watch(modsApiProvider);
  if (api == null) return ModCatalog.empty;
  try {
    return await api.catalog();
  } on DaemonException catch (e) {
    // 断开/正在关闭：给空表让页面去提示连接状态，而不是把整页变成报错
    if (e.code == 'disconnected' || e.code == 'unavailable') {
      return ModCatalog.empty;
    }
    rethrow;
  }
});

/// 某个项目类型下可选的游戏版本与加载器。
///
/// 按项目类型分开缓存：模组与插件的加载器集合不一样，而游戏版本清单是同一份
/// （daemon 那边也按类型分开缓存，但底层是同一个上游清单）。
final modsTagsProvider = FutureProvider.autoDispose
    .family<ModTags, String>((ref, projectType) async {
      final api = ref.watch(modsApiProvider);
      if (api == null) return ModTags.empty;
      try {
        return await api.tags(projectType: projectType);
      } on DaemonException catch (e) {
        if (e.code == 'disconnected' || e.code == 'unavailable') {
          return ModTags.empty;
        }
        rethrow;
      }
    });

/// 某个实例里已装的模组与插件。
///
/// 按实例 id 分（切实例就是另一份清单）；`mods.changed` 到了就整份重取 ——
/// 列表很小（个体量级的文件），重取比在本地按文件名合并简单且不会合并错。
///
/// **故意不是 `autoDispose`**：从「模组管理」滑到「模组下载」再滑回来
/// 不重扫目录，否则每次滑动都要重开一遍所有 jar。V2 的 `TabBarView`
/// 默认会销毁离屏的标签，所以靠「provider 不随 widget 销毁」来做到 ——
/// 刷新交给刷新按钮与 `mods.changed`。
final installedModsProvider = FutureProvider.family<InstalledMods, String>((
  ref,
  instanceId,
) async {
      final api = ref.watch(modsApiProvider);
      if (api == null || instanceId.isEmpty) return InstalledMods.empty;
      try {
        return await api.installed(instanceId);
      } on DaemonException catch (e) {
        if (e.code == 'disconnected' || e.code == 'unavailable') {
          return InstalledMods.empty;
        }
        rethrow;
      }
    });

/// 已装文件 → 上游项目（**图标**）。
///
/// 图标显示在每个条目左侧；拿不到就退回「按加载器上色」的方块。哈希在
/// daemon 那边有缓存，所以「检查更新」那次不会重算一遍。
///
/// 同样**不是 `autoDispose`**（理由见 [installedModsProvider]）。
typedef ModMatchQuery = ({String instanceId, String? projectType});

final modMatchesProvider = FutureProvider.family<ModMatchReport, ModMatchQuery>((
  ref,
  query,
) async {
      final api = ref.watch(modsApiProvider);
      if (api == null || query.instanceId.isEmpty) return ModMatchReport.empty;
      try {
        return await api.matchProjects(
          instanceId: query.instanceId,
          projectType: query.projectType,
        );
      } on DaemonException catch (e) {
        // 拿不到图标不该让整页报错（图标获取失败不影响使用）：
        // 列表照常显示，只是左侧退回彩色方块。
        if (e.code == 'disconnected' ||
            e.code == 'unavailable' ||
            e.code == 'mods_upstream_error' ||
            e.code == 'mods_parse_error') {
          return ModMatchReport.empty;
        }
        rethrow;
      }
    });

/// 订阅 `mods.changed`：**任何客户端**装了 / 删了 / 启停了模组都回刷列表。
///
/// 没有这条订阅时，另一台设备（或另一个浏览器标签）改过之后，本机要等用户
/// 手动下拉才会看见 —— 而对一个「服务端装了什么」的列表来说，看到陈旧内容是
/// 会误导人的。
final modsEventsProvider = Provider<void>((ref) {
  // 未连接时只是登记订阅意图，连上/重连后由连接层自动补订
  unawaited(ref.read(connectionProvider.notifier).subscribe('mods.changed'));

  final client = ref.watch(daemonClientProvider);
  if (client == null) return;

  final subscription = client.events.listen((event) {
    if (event['topic'] != 'mods.changed') return;
    ref.invalidate(installedModsProvider);
  });
  ref.onDispose(subscription.cancel);
});
