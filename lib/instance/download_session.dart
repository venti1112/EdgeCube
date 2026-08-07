import 'package:flutter/material.dart';

import 'create_instance_page.dart';
import 'instance_controller.dart';

/// 下载服务端流程的根路由名。
///
/// 「选择类型」页（流程第 1 页）以此名注册，完成下载/安装后各页可用
/// [finishDownloadFlow] 一次性 `popUntil` 弹回，将 [CreateInstanceResult.done]
/// 传回名称输入页。
const String kDownloadFlowRootRouteName = 'download_flow_root';

/// 贯穿「下载服务端」整个流程的共享状态。
///
/// 各页面通过构造参数逐级传递同一个实例，保存用户在流程中做出的选择
/// （服务端类型、版本、加载器版本等）与拉取到的版本映射缓存。页面本身只负责
/// 展示与导航，具体的下载/安装逻辑在 `download_runner.dart` 中。
class DownloadSession {
  /// 新建实例流程：输入名称后下载服务端并创建实例配置。
  DownloadSession({required this.controller, required this.name})
    : updateMode = false,
      updateInstanceId = null;

  /// 更新模式：替换已有实例的服务端文件，不创建新实例、不修改实例配置，
  /// 强制走官方源以保证获取最新版本。
  DownloadSession.forUpdate({
    required this.controller,
    required this.updateInstanceId,
  }) : name = '',
       updateMode = true;

  /// 实例控制器，用于创建/删除实例、写配置。
  final InstanceController controller;

  /// 用户在名称页输入的实例名（更新模式下为空）。
  final String name;

  /// 是否为更新模式：替换已有实例的服务端文件，不创建新实例、不改配置。
  final bool updateMode;

  /// 更新模式下要替换服务端文件的已有实例 id；非更新模式为 null。
  final String? updateInstanceId;

  // —— 用户选择 ——

  /// 具体服务端类型（vanilla / paper / fabric / forge / neoforge / velocity /
  /// bungeecord / pocketmine / powernukkitx / allay / survivalcraft ...）。
  String? serverType;

  /// Java 服务端分类（vanilla / plugin / mod / proxy），仅 Java 类型使用。
  String? javaServerCategory;

  /// 通用版本选择（Vanilla / Paper / 基岩端 / Survivalcraft 等直接选版本的类型）。
  String? selectedVersion;

  /// Fabric 流程中选择的 Minecraft 版本与 Loader 版本。
  String? selectedMcVersion;
  String? selectedLoaderVersion;

  /// Forge 流程中选择的 MC 版本与 Forge 版本。
  String? selectedForgeMcVersion;
  String? selectedForgeVersion;

  /// NeoForge 流程中选择的 MC 版本与 NeoForge 版本。
  String? selectedNeoforgeMcVersion;
  String? selectedNeoforgeVersion;

  /// Survivalcraft 流程中选择的 proot 容器信息。
  String? selectedProotRootfsId;
  String? selectedProotRootfsDir;

  // —— 版本映射缓存 ——

  /// Vanilla 版本 → 版本详情页 URL。
  Map<String, String> vanillaVersionUrls = {};

  /// PocketMine-MP 版本 → MCBE 客户端版本。
  final Map<String, String> pocketmineMcpeVersions = {};

  /// PowerNukkitX 版本 → MCBE 客户端版本。
  final Map<String, String> powernukkitxMcVersions = {};

  /// Forge 全量版本映射 {mcVersion: [forgeVersion...]}。
  Map<String, List<String>> forgeVersionMap = {};

  /// NeoForge 全量版本映射 {mcVersion: [neoforgeVersion...]}。
  Map<String, List<String>> neoforgeVersionMap = {};
}

/// 结束整个下载服务端流程：一次性 `popUntil` 弹回流程根页面，再将
/// [CreateInstanceResult.done] 传回名称输入页，由其关闭向导并刷新列表。
void finishDownloadFlow(BuildContext context) {
  final navigator = Navigator.of(context);
  navigator.popUntil(
    (route) => route.settings.name == kDownloadFlowRootRouteName,
  );
  navigator.pop(CreateInstanceResult.done);
}
