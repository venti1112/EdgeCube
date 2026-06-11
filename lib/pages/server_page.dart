import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import '../server/system_monitor_scope.dart';
import '../widgets/placeholder_page.dart';

/// 各内置 JRE 版本的展示名。
const Map<String, String> _kVersionLabels = {
  'jre8': 'Java 8',
  'jre17': 'Java 17',
  'jre21': 'Java 21',
  'jre25': 'Java 25',
};

class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final selected = controller.selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器'),
        actions: [
          _InstanceSelectorButton(
            controller: controller,
            selected: selected,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑实例',
            onPressed:
                selected == null ? null : () => _editInstance(context, controller, selected),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: selected == null
          ? const PlaceholderPage(
              icon: Icons.dns_outlined,
              title: '还没有实例',
              description: '点击左上角的按钮新建一个服务器实例。',
            )
          : _ServerControlPanel(
              key: ValueKey(selected.id),
              instance: selected,
            ),
    );
  }

  Future<void> _editInstance(
    BuildContext context,
    InstanceController controller,
    Instance instance,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptName(
      context,
      title: '编辑显示名称',
      initialValue: instance.name,
    );
    if (name == null) return;
    try {
      await controller.rename(instance.id, name);
    } on DuplicateInstanceNameException {
      messenger.showSnackBar(SnackBar(content: Text('已存在同名实例：$name')));
    }
  }
}

/// 启动所需的上下文：实例工作目录、可作为服务端的 .jar 列表、当前架构可用的 JRE 版本。
class _LaunchContext {
  const _LaunchContext({
    required this.workingDir,
    required this.jars,
    required this.versions,
  });

  final String workingDir;
  final List<String> jars;
  final List<String> versions;
}

/// 选中实例的服务端控制面板：状态、启动配置与启动/停止操作。
class _ServerControlPanel extends StatefulWidget {
  const _ServerControlPanel({super.key, required this.instance});

  final Instance instance;

  @override
  State<_ServerControlPanel> createState() => _ServerControlPanelState();
}

class _ServerControlPanelState extends State<_ServerControlPanel> {
  late final TextEditingController _memController;
  String _version = 'jre21';
  String? _selectedJar;
  Future<_LaunchContext>? _ctxFuture;

  @override
  void initState() {
    super.initState();
    _memController = TextEditingController(
      text: (widget.instance.maxMemory ?? 2048).toString(),
    );
    _version = widget.instance.javaVersion ?? 'jre21';
    _selectedJar = widget.instance.selectedJar;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // key 绑定实例 id，State 在实例不变期间复用，故只加载一次。
    _ctxFuture ??= _loadContext();
  }

  @override
  void dispose() {
    _memController.dispose();
    super.dispose();
  }

  /// 把当前表单值持久化到实例。
  void _persistConfig() {
    final controller = InstanceScope.of(context);
    controller.updateConfig(
      widget.instance.id,
      maxMemory: int.tryParse(_memController.text.trim()),
      javaVersion: _version,
      selectedJar: _selectedJar,
    );
  }

  Future<_LaunchContext> _loadContext() {
    final instances = InstanceScope.of(context);
    final server = ServerScope.of(context);
    final future = _scan(instances, server, widget.instance);
    future.then((ctx) {
      if (!mounted) return;
      setState(() {
        // 优先保留已持久化的 jar 和版本，若无效则回退到扫描结果。
        if (_selectedJar == null || !ctx.jars.contains(_selectedJar)) {
          _selectedJar = ctx.jars.isNotEmpty ? ctx.jars.first : null;
        }
        if (!ctx.versions.contains(_version) && ctx.versions.isNotEmpty) {
          _version =
              ctx.versions.contains('jre21') ? 'jre21' : ctx.versions.first;
        }
      });
    });
    return future;
  }

  Future<_LaunchContext> _scan(
    InstanceController instances,
    ServerController server,
    Instance instance,
  ) async {
    final dir = await instances.directoryFor(instance);
    final jars = <String>[];
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File && entry.path.toLowerCase().endsWith('.jar')) {
          jars.add(p.basename(entry.path));
        }
      }
    }
    jars.sort((a, b) {
      int rank(String name) {
        final l = name.toLowerCase();
        if (l == 'server.jar') return 0;
        if (l.contains('server') ||
            l.contains('paper') ||
            l.contains('spigot') ||
            l.contains('purpur') ||
            l.contains('fabric') ||
            l.contains('forge')) {
          return 1;
        }
        return 2;
      }

      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });
    final versions = await server.availableVersions();
    return _LaunchContext(workingDir: dir.path, jars: jars, versions: versions);
  }

  /// 启动前自动检查并写入 eula.txt，确保 eula=true。
  Future<void> _ensureEula(String workingDir) async {
    final eulaFile = File(p.join(workingDir, 'eula.txt'));
    bool needWrite = false;
    if (await eulaFile.exists()) {
      final content = await eulaFile.readAsString();
      // 检查是否有 eula=true（不区分大小写）
      if (!RegExp(r'eula\s*=\s*true', caseSensitive: false).hasMatch(content)) {
        needWrite = true;
      }
    } else {
      needWrite = true;
    }
    if (needWrite) {
      await eulaFile.writeAsString(
        '#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\n'
        'eula=true\n',
      );
    }
  }

  void _start(ServerController server, _LaunchContext ctx) async {
    final jar = _selectedJar;
    if (jar == null) return;
    final mem = int.tryParse(_memController.text.trim());
    final jvmArgs = <String>[
      if (mem != null && mem > 0) '-Xmx${mem}M',
    ];
    // 启动前自动确保 eula=true
    await _ensureEula(ctx.workingDir);
    server.start(
      instanceId: widget.instance.id,
      instanceName: widget.instance.name,
      workingDir: ctx.workingDir,
      version: _version,
      jvmArgs: jvmArgs,
      programArgs: ['-jar', jar, 'nogui'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final instance = widget.instance;
    final active = server.isActive(instance.id);
    final status = active ? server.status : ServerStatus.stopped;

    return FutureBuilder<_LaunchContext>(
      future: _ctxFuture,
      builder: (context, snapshot) {
        final ctx = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(context, ctx, status, active ? server.lastExitCode : null),
            const SizedBox(height: 16),
            _actions(context, server, ctx, status),
            const SizedBox(height: 16),
            _MonitorCard(maxMemoryMb: widget.instance.maxMemory ?? 2048),
          ],
        );
      },
    );
  }

  Widget _statusCard(BuildContext context, _LaunchContext? ctx, ServerStatus status, int? exitCode) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String text) = switch (status) {
      ServerStatus.stopped => (Icons.stop_circle_outlined,
          theme.colorScheme.outline, '已停止'),
      ServerStatus.starting => (Icons.hourglass_top, Colors.orange, '启动中…'),
      ServerStatus.running => (Icons.play_circle, Colors.green, '运行中'),
      ServerStatus.stopping => (Icons.hourglass_bottom, Colors.orange, '停止中…'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.instance.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    status == ServerStatus.stopped && exitCode != null
                        ? '$text（上次退出码 $exitCode）'
                        : text,
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '启动配置',
              onPressed: () => _openSettings(context, ctx),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开启动配置对话框。
  Future<void> _openSettings(BuildContext context, _LaunchContext? ctx) async {
    if (ctx == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return AlertDialog(
              title: const Text('启动配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: ctx.versions.contains(_version) ? _version : null,
                      decoration: const InputDecoration(
                        labelText: 'Java 版本',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final v in ctx.versions)
                          DropdownMenuItem(
                            value: v,
                            child: Text(_kVersionLabels[v] ?? v),
                          ),
                      ],
                      onChanged: (v) {
                        setDialogState(() => _version = v ?? _version);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _memController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最大内存',
                        suffixText: 'MB',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _jarField(dialogContext, ctx),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _persistConfig();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _jarField(BuildContext context, _LaunchContext ctx) {
    final theme = Theme.of(context);
    if (ctx.jars.isEmpty) {
      return Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未在实例目录找到 .jar，请在「文件」页放入服务端 jar。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedJar,
      decoration: const InputDecoration(
        labelText: '服务端 jar',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final jar in ctx.jars)
          DropdownMenuItem(value: jar, child: Text(jar)),
      ],
      selectedItemBuilder: (context) => [
        for (final jar in ctx.jars)
          DropdownMenuItem<String>(
            value: jar,
            child: Text(
              jar,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        _selectedJar = v;
      },
    );
  }

  Widget _actions(
    BuildContext context,
    ServerController server,
    _LaunchContext? ctx,
    ServerStatus status,
  ) {
    final theme = Theme.of(context);

    if (status == ServerStatus.running) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: server.stop,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: server.forceStop,
            icon: const Icon(Icons.dangerous_outlined),
            label: const Text('强制'),
          ),
        ],
      );
    }

    if (status == ServerStatus.starting || status == ServerStatus.stopping) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text(status == ServerStatus.starting ? '启动中…' : '停止中…'),
      );
    }

    // 已停止：可启动，但需排除“他实例运行中”与“无 jar”。
    final otherRunning = server.isOtherRunning(widget.instance.id);
    final hasJar = ctx != null && _selectedJar != null;
    final canStart = !otherRunning && hasJar;

    String? hint;
    if (otherRunning) {
      hint = '实例「${server.runningInstanceName}」正在运行，请先停止它。';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: canStart ? () => _start(server, ctx) : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('启动'),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// AppBar 左上角的“选择实例”按钮，点击弹出实例列表底部弹窗。
class _InstanceSelectorButton extends StatelessWidget {
  const _InstanceSelectorButton({
    required this.controller,
    required this.selected,
  });

  final InstanceController controller;
  final Instance? selected;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      icon: const Icon(Icons.dns),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected?.name ?? '选择实例',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      onPressed: () => _openSelector(context),
    );
  }

  Future<void> _openSelector(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _InstanceListSheet(controller: controller),
    );
  }
}

/// 实例列表底部弹窗：展示全部实例 + “新建实例”入口。
class _InstanceListSheet extends StatelessWidget {
  const _InstanceListSheet({required this.controller});

  final InstanceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instances = controller.instances;
    final selectedId = controller.selected?.id;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('选择实例', style: theme.textTheme.titleMedium),
          ),
          if (instances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '暂无实例，点击下方新建。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final instance in instances)
                    ListTile(
                      leading: Icon(
                        instance.id == selectedId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: instance.id == selectedId
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(instance.name),
                      subtitle: Text(
                        instance.id,
                        style: theme.textTheme.bodySmall,
                      ),
                      selected: instance.id == selectedId,
                      onTap: () {
                        controller.select(instance.id);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建实例'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final name = await _promptName(
                context,
                title: '新建实例',
                initialValue: '新实例',
              );
              if (name == null) return;
              try {
                await controller.createInstance(name);
                navigator.pop();
              } on DuplicateInstanceNameException {
                messenger
                    .showSnackBar(SnackBar(content: Text('已存在同名实例：$name')));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 弹出一个文本输入对话框，返回去除首尾空白后的非空名称；取消或为空返回 null。
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String initialValue,
}) async {
  final textController = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '显示名称',
            hintText: '请输入实例名称',
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
  textController.dispose();
  if (result == null || result.isEmpty) return null;
  return result;
}

/// 系统监控数据面板：设备内存、CPU 使用率，以及服务端内存（运行时显示）。
class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.maxMemoryMb});

  /// 用户配置的 JVM 最大堆内存（MB）。
  final int maxMemoryMb;

  @override
  Widget build(BuildContext context) {
    final monitor = SystemMonitorScope.of(context);
    final info = monitor.info;
    final theme = Theme.of(context);

    final server = ServerScope.of(context);
    final serverRunning = server.status == ServerStatus.running;

    final memPercent = info.usedMemPercent;
    final cpuPercent = info.cpuUsage >= 0 ? info.cpuUsage : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统状态', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),

            // 设备内存
            _MonitorRow(
              icon: Icons.memory,
              label: '设备内存',
              value: '${info.usedMemMb} MB / ${info.totalMemMb} MB',
              percent: memPercent,
              color: _colorForPercent(memPercent, theme),
            ),
            const SizedBox(height: 12),

            // CPU 使用率
            _MonitorRow(
              icon: Icons.speed,
              label: 'CPU 使用率',
              value: info.cpuUsage >= 0
                  ? '${info.cpuUsage.toStringAsFixed(1)}%'
                  : '不可用',
              percent: cpuPercent,
              color: _colorForPercent(cpuPercent, theme),
            ),

            // 服务端内存（仅运行时显示）
            if (serverRunning && info.serverMemMb != null) ...[
              const SizedBox(height: 12),
              _ServerMemRow(memMb: info.serverMemMb!, maxMemMb: maxMemoryMb),
            ],
          ],
        ),
      ),
    );
  }

  static Color _colorForPercent(double percent, ThemeData theme) {
    if (percent >= 85) return theme.colorScheme.error;
    if (percent >= 65) return Colors.orange;
    return theme.colorScheme.primary;
  }
}

/// 单项监控行：图标 + 标签 + 数值 + 进度条。
class _MonitorRow extends StatelessWidget {
  const _MonitorRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _AnimatedProgressBar(
          percent: percent,
          color: color,
          theme: theme,
        ),
      ],
    );
  }
}

/// 服务端内存行：当前 VmRSS / 用户设置最大值 + 进度条。
class _ServerMemRow extends StatelessWidget {
  const _ServerMemRow({required this.memMb, required this.maxMemMb});

  final int memMb;
  final int maxMemMb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = maxMemMb > 0 ? (memMb / maxMemMb) * 100.0 : 0.0;
    final color = _MonitorCard._colorForPercent(percent, theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dns, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('服务端内存', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              '$memMb MB / $maxMemMb MB',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _AnimatedProgressBar(
          percent: percent,
          color: color,
          theme: theme,
        ),
      ],
    );
  }
}

/// 带平滑过渡动画的进度条。
/// 使用 TweenAnimationBuilder 在 percent 变化时平滑插值宽度。
class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({
    required this.percent,
    required this.color,
    required this.theme,
  });

  final double percent;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: (percent.clamp(0.0, 100.0)) / 100.0,
        end: (percent.clamp(0.0, 100.0)) / 100.0,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, v, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: SizedBox.expand(
                    child: ColoredBox(color: color),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
