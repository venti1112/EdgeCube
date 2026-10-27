import 'package:material_ui/material_ui.dart';

import '../../mcserver/models.dart';

/// 下载服务端流程的根路由名。
///
/// 「选择分类」页（流程第 1 页）以此名注册，最后一步完成后各页可以用
/// [finishDownloadFlow] 一次性 `popUntil` 弹回它、再把结果交回新建实例页 ——
/// 流程中间几页不需要各自知道前面几页是谁，只要知道「根在哪儿」。
const String kDownloadFlowRootRouteName = 'download_flow_root';

/// 贯穿「下载服务端」整个流程的共享状态。
///
/// 页面通过构造参数逐级传同一个实例，各自只负责展示与导航。
///
/// 这里不带下载引擎、版本映射缓存、proot 容器、运行时环境 —— **那些现在都在
/// daemon 那边**（`mcserver` 出网与缓存、`download` 下载、
/// `instance` 落盘）。这里只留「用户选了什么」。
class DownloadWizard {
  DownloadWizard({required this.name});

  /// 用户在新建实例页输入的实例名。
  ///
  /// **实例是最后一步才建的**（下载页里），所以这个名字要一路带到那里。
  final String name;

  // —— 用户的选择 ——

  /// 选中的服务端类型（`paper` / `fabric` / …）。
  ServerKind? kind;

  /// 选中的版本。`BungeeCord` 这类没有版本概念的类型留空。
  String? version;

  /// 选中的加载器版本（目前只有 Fabric 会用到）。
  String? loaderVersion;

  /// 一句话描述当前的选择，给进度页做标题用。
  String get summary {
    final kind = this.kind;
    if (kind == null) return '';
    if (version == null) return kind.name;
    if (loaderVersion == null) return '${kind.name} $version';
    return '${kind.name} $version + $loaderVersion';
  }
}

/// 结束整个下载服务端流程：一次性弹回流程根页，再把 `true` 交回新建实例页
/// （由它关闭向导、刷新列表）。
void finishDownloadFlow(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.popUntil(
    (route) => route.settings.name == kDownloadFlowRootRouteName,
  );
  navigator.pop(true);
}

/// 服务端类型的图标。
///
/// **不用 logo 素材**：V2 前端没有 assets 目录，而且那些 `.svg` 还要多引一个
/// `flutter_svg` 依赖 —— 为几个图标不值。
IconData serverIcon(String id) => switch (id) {
  'vanilla' => Icons.storage_outlined,
  'paper' => Icons.description_outlined,
  // Folia 是分区多线程，用「闪电」比再堆一个文件图标好认
  'folia' => Icons.bolt_outlined,
  'purpur' => Icons.palette_outlined,
  'leaf' => Icons.eco_outlined,
  'leaves' => Icons.energy_savings_leaf_outlined,
  'fabric' => Icons.auto_awesome_mosaic_outlined,
  'velocity' => Icons.speed_outlined,
  'bungeecord' => Icons.hub_outlined,
  _ => Icons.dns_outlined,
};

/// 分类的图标。
IconData categoryIcon(String id) => switch (id) {
  'vanilla' => Icons.storage_outlined,
  'plugin' => Icons.extension_outlined,
  'mod' => Icons.auto_awesome_mosaic_outlined,
  'proxy' => Icons.lan_outlined,
  _ => Icons.category_outlined,
};
