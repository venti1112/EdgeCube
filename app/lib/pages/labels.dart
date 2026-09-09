import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:material_ui/material_ui.dart';

/// 实例五态状态机(对齐 MCSManager)的中文标签。
String instanceStatusLabel(InstanceStatus s) => switch (s) {
      InstanceStatus.busy => '忙碌',
      InstanceStatus.stopped => '已停止',
      InstanceStatus.stopping => '停止中',
      InstanceStatus.starting => '启动中',
      InstanceStatus.running => '运行中',
      _ => '未知',
    };

/// 实例状态对应的主题色。
Color instanceStatusColor(ColorScheme cs, InstanceStatus s) => switch (s) {
      InstanceStatus.running => Colors.green,
      InstanceStatus.busy || InstanceStatus.stopped => cs.onSurfaceVariant,
      InstanceStatus.starting || InstanceStatus.stopping => cs.tertiary,
      _ => cs.onSurfaceVariant,
    };

/// 附加层类型标签。
String instanceTypeLabel(InstanceType t) => switch (t) {
      InstanceType.minecraftJava => 'Minecraft Java',
      InstanceType.minecraftBedrock => 'Minecraft Bedrock',
      InstanceType.pocketmine => 'PocketMine',
      InstanceType.generic => '通用',
      _ => '未知',
    };

/// 任务状态标签。
String taskStatusLabel(TaskStatus s) => switch (s) {
      TaskStatus.queued => '排队中',
      TaskStatus.running => '进行中',
      TaskStatus.succeeded => '已完成',
      TaskStatus.failed => '失败',
      TaskStatus.cancelled => '已取消',
      _ => '未知',
    };

/// 任务状态对应的主题色。
Color taskStatusColor(ColorScheme cs, TaskStatus s) => switch (s) {
      TaskStatus.queued => cs.onSurfaceVariant,
      TaskStatus.running => cs.primary,
      TaskStatus.succeeded => Colors.green,
      TaskStatus.failed => cs.error,
      TaskStatus.cancelled => cs.onSurfaceVariant,
      _ => cs.onSurfaceVariant,
    };

/// 任务种类标签。
String taskKindLabel(TaskKind k) => switch (k) {
      TaskKind.start => '启动',
      TaskKind.stop => '停止',
      TaskKind.restart => '重启',
      TaskKind.kill => '强杀',
      TaskKind.download => '下载',
      TaskKind.export_ => '导出',
      TaskKind.backup => '备份',
      TaskKind.compress => '压缩',
      TaskKind.extract => '解压',
      TaskKind.analyze => '解析',
      TaskKind.downloadSingleFile => '单文件下载',
      _ => '未知',
    };

/// 运行时类型标签。
String runtimeTypeLabel(RuntimeType t) => switch (t) {
      RuntimeType.java => 'Java',
      RuntimeType.php => 'PHP',
      RuntimeType.frpc => 'FRPC',
      _ => '未知',
    };

/// 任务是否仍可取消(排队/进行中)。
bool taskActive(TaskStatus s) =>
    s == TaskStatus.queued || s == TaskStatus.running;

/// 任务是否已终结(成功/失败/取消)。
bool taskFinished(TaskStatus s) =>
    s == TaskStatus.succeeded || s == TaskStatus.failed || s == TaskStatus.cancelled;