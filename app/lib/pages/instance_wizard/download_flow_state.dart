import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../server/server_service.dart';
import '../current_instance.dart';

/// 「下载服务端」向导跨页面共享的选择状态(白盒子,由各选择页逐步填充)。
/// 进入向导时由名称页初始化并锁定 name;下载进度页结束后清理。
class DownloadFlowState {
  DownloadFlowState({required this.name});

  /// 实例名称(进入向导时锁定)。
  final String name;

  /// 选定服务端类型 id(vanilla / paper / ... / allay)。
  String? serverType;

  /// 服务端类型分类(vanilla / plugin / mod / proxy / bedrock)。
  String? category;

  /// 简单类型选中版本(bungeecord 无版本概念)。
  String? version;

  /// hasLoader 类型(fabric)选中的 Minecraft 版本。
  String? mcVersion;

  /// 加载器版本(fabric 必选)。
  String? loaderVersion;

  /// 下载目标文件名(/catalog/download-info 返回)。
  String? fileName;

  /// 是否走「选加载器」流程(来自 ServerTypeInfo.hasLoader)。
  bool hasLoader = false;

  /// 创建实例后 daemon 回写的实例 id(失败清理用)。
  String? instanceId;

  /// 创建实例后 daemon 回写的下载任务 id(下载页据此轮询)。
  String? downloadTaskId;
}

/// 向导会话状态(Null = 未在流程中);进入向导时重置、下载页完成后清理。
class DownloadFlowNotifier extends Notifier<DownloadFlowState?> {
  @override
  DownloadFlowState? build() => null;

  /// 进入向导:重置会话并锁定实例名称。
  void enter(DownloadFlowState flow) => state = flow;

  /// 向导结束:清理会话(下载完成/取消/失败)。
  void clear() => state = null;
}

final downloadFlowProvider =
    NotifierProvider<DownloadFlowNotifier, DownloadFlowState?>(
        DownloadFlowNotifier.new);

/// 服务端类型的展示元数据(图标 + 标题 + 副标题)。
class ServerTypeMeta {
  const ServerTypeMeta({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

const Map<String, ServerTypeMeta> _serverTypeMetas = {
  'vanilla': ServerTypeMeta(
    icon: Icons.cottage_outlined,
    title: 'Vanilla 原版',
    subtitle: 'Mojang 官方原版服务端',
  ),
  'paper': ServerTypeMeta(
    icon: Icons.auto_awesome,
    title: 'Paper',
    subtitle: '高性能插件服务端(含 Spigot API)',
  ),
  'spigot': ServerTypeMeta(
    icon: Icons.extension_outlined,
    title: 'Spigot',
    subtitle: '经典插件服务端',
  ),
  'craftbukkit': ServerTypeMeta(
    icon: Icons.widgets_outlined,
    title: 'CraftBukkit',
    subtitle: 'Bukkit 插件服务端鼻祖',
  ),
  'purpur': ServerTypeMeta(
    icon: Icons.gesture,
    title: 'Purpur',
    subtitle: 'Paper 分支,更多配置项与优化',
  ),
  'leaf': ServerTypeMeta(
    icon: Icons.eco_outlined,
    title: 'Leaf',
    subtitle: 'Paper 分支,生电向性能优化',
  ),
  'leaves': ServerTypeMeta(
    icon: Icons.energy_savings_leaf_outlined,
    title: 'Leaves',
    subtitle: 'Paper 分支,红石/生电友好',
  ),
  'fabric': ServerTypeMeta(
    icon: Icons.auto_awesome_mosaic_outlined,
    title: 'Fabric',
    subtitle: '轻量模组加载器服务端',
  ),
  'velocity': ServerTypeMeta(
    icon: Icons.rocket_launch_outlined,
    title: 'Velocity',
    subtitle: '现代高性能代理端',
  ),
  'bungeecord': ServerTypeMeta(
    icon: Icons.lan_outlined,
    title: 'BungeeCord',
    subtitle: '经典代理端(直接下载最新构建)',
  ),
  'pocketmine': ServerTypeMeta(
    icon: Icons.diamond_outlined,
    title: 'PocketMine-MP',
    subtitle: '基岩版 PHP 服务端',
  ),
  'powernukkitx': ServerTypeMeta(
    icon: Icons.power_outlined,
    title: 'PowerNukkitX',
    subtitle: '基岩版 Java 服务端(Nukkit 系)',
  ),
  'allay': ServerTypeMeta(
    icon: Icons.all_inclusive_outlined,
    title: 'Allay',
    subtitle: '基岩版 Rust 服务端',
  ),
};

/// 某服务端类型的展示元数据(未知类型返回 null,调用方兜底)。
ServerTypeMeta? serverTypeMeta(String type) => _serverTypeMetas[type];

/// 服务端类型 → 实例类型。
InstanceType instanceTypeFor(String type) => switch (type) {
      'pocketmine' => InstanceType.pocketmine,
      'powernukkitx' || 'allay' => InstanceType.minecraftBedrock,
      _ => InstanceType.minecraftJava,
    };

/// 默认启动命令(依据类型与落盘文件名;fileName 来自下载信息)。
String defaultStartCommand(String type, String fileName) => switch (type) {
      'pocketmine' => 'php $fileName',
      'powernukkitx' || 'allay' => 'java -Xmx512M -jar $fileName nogui',
      _ => 'java -Xmx1024M -jar $fileName nogui',
    };

/// 向 daemon 组装下载信息并创建实例:GET /catalog/download-info 取直链/校验值/
/// 落盘文件名 → POST /instances(带 downloadUrl/fileName/checksum)→ 202 回写
/// downloadTaskId。调用成功后将实例 id 与任务 id 写入 [flow]。
///
/// 抛出的异常由页面统一经 [apiErrorMessage] 呈现。
Future<void> startInstanceDownload(WidgetRef ref, DownloadFlowState flow) async {
  final client = ref.read(edgecubeClientProvider);
  if (client == null) {
    throw StateError('未连接到服务器');
  }
  final type = flow.serverType!;
  // hasLoader 类型用 mcVersion+loaderVersion;bungeecord 无版本参数
  final info = (await client.getCatalogApi().getCatalogDownloadInfo(
        type: type,
        version: (flow.hasLoader || type == 'bungeecord') ? null : flow.version,
        mcVersion: flow.hasLoader ? flow.mcVersion : null,
        loaderVersion: flow.hasLoader ? flow.loaderVersion : null,
      ))
      .data!;
  flow.fileName = info.fileName;
  final resp = await client.getInstancesApi().createInstance(
        instanceConfig: InstanceConfig((b) => b
          ..name = flow.name
          ..type = instanceTypeFor(type)
          ..startCommand = defaultStartCommand(type, info.fileName)
          ..downloadUrl = info.url
          ..fileName = info.fileName
          ..checksum = info.checksum),
      );
  flow.instanceId = resp.data?.id;
  flow.downloadTaskId = resp.data?.downloadTaskId;
  // 创建成功即设为全局当前实例(对齐 V1 createInstance 自动选中);
  // 下载进行中其状态由 daemon 维护,进度页结束后仍保持选中。
  final created = resp.data;
  final createdId = created?.id;
  if (created != null && createdId != null) {
    await ref.read(currentInstanceProvider.notifier).select(
          InstanceSummary((b) => b
            ..id = createdId
            ..name = created.name
            ..status = InstanceStatus.starting
            ..type = instanceTypeFor(type)),
        );
  }
}