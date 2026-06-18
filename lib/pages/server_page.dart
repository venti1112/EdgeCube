import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../instance/create_instance_page.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../online/error_report_service.dart';
import '../online/online_service.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import '../server/system_monitor_scope.dart';
import '../server/system_monitor_service.dart';
import '../widgets/placeholder_page.dart';

/// 各内置运行时版本的展示名（JRE 与 PHP）。
const Map<String, String> _kVersionLabels = {
  'jre17': 'Java 17',
  'jre21': 'Java 21',
  'jre25': 'Java 25',
  'php8.2': 'PHP 8.2',
};

class ServerPage extends StatelessWidget {
  const ServerPage({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final selected = controller.selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器'),
        actions: [
          _InstanceSelectorButton(controller: controller, selected: selected),
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
              filesRevision: controller.filesRevision,
              onlineService: onlineService,
            ),
    );
  }
}

/// 启动所需的上下文：实例工作目录、可作为服务端的文件列表（.jar / .phar）、
/// 当前架构可用的 JRE 版本与 PHP 运行时。
class _LaunchContext {
  const _LaunchContext({
    required this.workingDir,
    required this.jars,
    required this.phars,
    required this.versions,
    required this.phpRuntimes,
  });

  final String workingDir;
  final List<String> jars;
  final List<String> phars;
  final List<String> versions;
  final List<String> phpRuntimes;
}

/// 选中实例的服务端控制面板：状态、启动配置与启动/停止操作。
class _ServerControlPanel extends StatefulWidget {
  const _ServerControlPanel({
    super.key,
    required this.instance,
    required this.filesRevision,
    required this.onlineService,
  });

  final Instance instance;

  /// 实例目录文件修订号，变化时触发重新扫描 jar。
  final int filesRevision;

  final OnlineService onlineService;

  @override
  State<_ServerControlPanel> createState() => _ServerControlPanelState();
}

class _ServerControlPanelState extends State<_ServerControlPanel> {
  late final TextEditingController _memController;
  late final TextEditingController _jvmArgsController;
  String _runtime = kRuntimeJava;
  String _version = 'jre21';
  String? _selectedJar;
  bool _compatMode = false;
  Future<_LaunchContext>? _ctxFuture;

  bool get _isPhp => _runtime == kRuntimePhp;

  @override
  void initState() {
    super.initState();
    _memController = TextEditingController(
      text: (widget.instance.maxMemory ?? 2048).toString(),
    );
    _jvmArgsController = TextEditingController(
      text: widget.instance.customJvmArgs ?? '',
    );
    _runtime = widget.instance.runtime;
    _version = widget.instance.javaVersion ?? 'jre21';
    _selectedJar = widget.instance.selectedJar;
    _compatMode = widget.instance.compatMode;
    // 设置崩溃回调：服务端意外退出时弹出报告弹窗。
    final server = ServerScope.of(context);
    server.onCrashExit = _onCrashExit;
  }

  /// 服务端意外退出回调。
  void _onCrashExit(CrashData crash) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _CrashDialog(crash: crash, onlineService: widget.onlineService),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // key 绑定实例 id，State 在实例不变期间复用，故只加载一次。
    _ctxFuture ??= _loadContext();
  }

  @override
  void didUpdateWidget(covariant _ServerControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 实例配置变化（如下载完成后 selectedJar/javaVersion 更新、导入 phar 改变 runtime）时，同步表单值。
    final configChanged =
        oldWidget.instance.selectedJar != widget.instance.selectedJar ||
        oldWidget.instance.javaVersion != widget.instance.javaVersion ||
        oldWidget.instance.runtime != widget.instance.runtime ||
        oldWidget.instance.compatMode != widget.instance.compatMode;
    if (configChanged) {
      _runtime = widget.instance.runtime;
      _version = widget.instance.javaVersion ?? 'jre21';
      _selectedJar = widget.instance.selectedJar;
      _compatMode = widget.instance.compatMode;
    }
    // 配置变化，或用户在「文件」页导入 jar 使 filesRevision 自增时，重新扫描目录。
    // 仅文件变化时不重置表单，扫描完成后由 _loadContext 回退无效的 jar 选择。
    if (configChanged || oldWidget.filesRevision != widget.filesRevision) {
      _ctxFuture = _loadContext();
    }
  }

  @override
  void dispose() {
    _memController.dispose();
    _jvmArgsController.dispose();
    super.dispose();
  }

  /// 把当前表单值持久化到实例。
  void _persistConfig() {
    final controller = InstanceScope.of(context);
    final argsText = _jvmArgsController.text.trim();
    controller.updateConfig(
      widget.instance.id,
      runtime: _runtime,
      maxMemory: int.tryParse(_memController.text.trim()),
      javaVersion: _version,
      selectedJar: _selectedJar,
      customJvmArgs: argsText.isEmpty ? null : argsText,
      compatMode: _compatMode,
      clearCustomJvmArgs: argsText.isEmpty,
    );
  }

  Future<_LaunchContext> _loadContext() {
    final instances = InstanceScope.of(context);
    final server = ServerScope.of(context);
    final future = _scan(instances, server, widget.instance);
    future.then((ctx) {
      if (!mounted) return;
      setState(() {
        // 优先保留已持久化的服务端文件与版本，若无效则回退到扫描结果。
        final files = _isPhp ? ctx.phars : ctx.jars;
        if (_selectedJar == null || !files.contains(_selectedJar)) {
          _selectedJar = files.isNotEmpty ? files.first : null;
        }
        if (!ctx.versions.contains(_version) && ctx.versions.isNotEmpty) {
          _version = ctx.versions.contains('jre21')
              ? 'jre21'
              : ctx.versions.first;
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
    final phars = <String>[];
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        final lower = entry.path.toLowerCase();
        if (lower.endsWith('.jar')) {
          jars.add(p.basename(entry.path));
        } else if (lower.endsWith('.phar')) {
          phars.add(p.basename(entry.path));
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
    phars.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final versions = await server.availableVersions();
    final phpRuntimes = await server.availablePhpRuntimes();
    return _LaunchContext(
      workingDir: dir.path,
      jars: jars,
      phars: phars,
      versions: versions,
      phpRuntimes: phpRuntimes,
    );
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
    final file = _selectedJar;

    // PHP（PocketMine）：用 PHP 运行时执行选中的 .phar。
    if (_isPhp) {
      if (ctx.phpRuntimes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前设备架构不支持 PHP 运行环境。')));
        return;
      }
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未在实例目录找到 .phar，请先在「文件」页放入 PocketMine 的 phar。'),
          ),
        );
        return;
      }
      server.start(
        instanceId: widget.instance.id,
        instanceName: widget.instance.name,
        workingDir: ctx.workingDir,
        version: ctx.phpRuntimes.first,
        runtime: kRuntimePhp,
        jvmArgs: const [],
        programArgs: [file],
        compatMode: _compatMode,
      );
      return;
    }

    // Java：用 JRE 执行选中的 .jar。
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未在实例目录找到 .jar，请先在「文件」页放入服务端 jar。')),
      );
      return;
    }
    final mem = int.tryParse(_memController.text.trim());
    final jvmArgs = <String>[
      if (mem != null && mem > 0) '-Xmx${mem}M',
      // 追加用户自定义 JVM 参数（以空白符/换行分隔）。
      ..._parseCustomJvmArgs(widget.instance.customJvmArgs),
    ];
    // 启动前自动确保 eula=true
    await _ensureEula(ctx.workingDir);
    server.start(
      instanceId: widget.instance.id,
      instanceName: widget.instance.name,
      workingDir: ctx.workingDir,
      version: _version,
      runtime: kRuntimeJava,
      jvmArgs: jvmArgs,
      programArgs: ['-jar', file, 'nogui'],
      compatMode: _compatMode,
    );
  }

  /// 解析自定义 JVM 参数文本（每行或空格分隔）为参数列表。
  static List<String> _parseCustomJvmArgs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
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
            _statusCard(
              context,
              server,
              ctx,
              status,
              active ? server.lastExitCode : null,
            ),
            if (status == ServerStatus.running) ...[
              const SizedBox(height: 16),
              _ConnectionCard(server: server),
            ],
            const SizedBox(height: 16),
            _actions(context, server, ctx, status),
            const SizedBox(height: 16),
            _MonitorCard(maxMemoryMb: widget.instance.maxMemory ?? 2048),
          ],
        );
      },
    );
  }

  Widget _statusCard(
    BuildContext context,
    ServerController server,
    _LaunchContext? ctx,
    ServerStatus status,
    int? exitCode,
  ) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String text) = switch (status) {
      ServerStatus.stopped => (
        Icons.stop_circle_outlined,
        theme.colorScheme.outline,
        '已停止',
      ),
      ServerStatus.preparing => (Icons.hourglass_empty, Colors.orange, '准备中…'),
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
                  Text(
                    widget.instance.name,
                    style: theme.textTheme.titleMedium,
                  ),
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
              tooltip: '实例配置',
              onPressed: () => _openSettings(context, server, ctx),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开启动配置对话框。
  Future<void> _openSettings(
    BuildContext context,
    ServerController server,
    _LaunchContext? ctx,
  ) async {
    if (ctx == null) return;
    final nameController = TextEditingController(text: widget.instance.name);
    final controller = InstanceScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return AlertDialog(
              title: const Text('实例配置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 运行环境：Java（JVM 跑 .jar）/ PHP（PocketMine 跑 .phar）。
                    DropdownButtonFormField<String>(
                      initialValue: _runtime,
                      decoration: const InputDecoration(
                        labelText: '运行环境',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: kRuntimeJava,
                          child: Text('Java（Minecraft）'),
                        ),
                        DropdownMenuItem(
                          value: kRuntimePhp,
                          child: Text('PHP（PocketMine）'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null || v == _runtime) return;
                        setDialogState(() {
                          _runtime = v;
                          // 切换运行环境后，把服务端文件/版本回退到该环境下的有效默认值。
                          if (_isPhp) {
                            _selectedJar = ctx.phars.isNotEmpty
                                ? ctx.phars.first
                                : null;
                          } else {
                            _selectedJar = ctx.jars.isNotEmpty
                                ? ctx.jars.first
                                : null;
                            if (!ctx.versions.contains(_version) &&
                                ctx.versions.isNotEmpty) {
                              _version = ctx.versions.contains('jre21')
                                  ? 'jre21'
                                  : ctx.versions.first;
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (!_isPhp) ...[
                      DropdownButtonFormField<String>(
                        initialValue: ctx.versions.contains(_version)
                            ? _version
                            : null,
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
                    ] else ...[
                      // PHP 运行时版本（只读；当前仅 PHP 8.2，且仅 arm64 提供）。
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '运行时版本',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text(
                          ctx.phpRuntimes.isNotEmpty
                              ? (_kVersionLabels[ctx.phpRuntimes.first] ??
                                    ctx.phpRuntimes.first)
                              : '当前设备架构不支持 PHP',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _serverFileField(dialogContext, ctx),
                    const SizedBox(height: 16),
                    if (!_isPhp) ...[
                      TextField(
                        controller: _jvmArgsController,
                        maxLines: 4,
                        minLines: 2,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        decoration: const InputDecoration(
                          labelText: '自定义 JVM 参数',
                          hintText:
                              '每行或空格分隔一个参数，例如：\n-Dfml.ignoreInvalidMinecraftCertificates=true\n-XX:+UseG1GC',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _compatMode,
                      onChanged: (v) => setDialogState(() => _compatMode = v),
                      title: const Text('兼容模式'),
                      subtitle: const Text(
                        '准备完成、服务端进程启动后立即标记为「运行中」，跳过「启动中」。'
                        '适用于不输出 Done 标志的非标准服务端。',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    if (newName.isNotEmpty && newName != widget.instance.name) {
                      try {
                        await controller.rename(widget.instance.id, newName);
                      } on DuplicateInstanceNameException {
                        if (context.mounted) {
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('提示'),
                              content: Text('已存在同名实例：$newName'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }
                    }
                    _persistConfig();
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
  }

  Widget _serverFileField(BuildContext context, _LaunchContext ctx) {
    final theme = Theme.of(context);
    final files = _isPhp ? ctx.phars : ctx.jars;
    final ext = _isPhp ? '.phar' : '.jar';
    final label = _isPhp ? '服务端 phar' : '服务端 jar';
    if (files.isEmpty) {
      return Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未在实例目录找到 $ext，请在「文件」页放入服务端文件。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }
    // 持久化的选择可能属于另一种运行环境（jar/phar），回退到首个有效项以避免下拉断言。
    final value = files.contains(_selectedJar) ? _selectedJar : files.first;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final f in files) DropdownMenuItem(value: f, child: Text(f)),
      ],
      selectedItemBuilder: (context) => [
        for (final f in files)
          DropdownMenuItem<String>(
            value: f,
            child: Text(f, overflow: TextOverflow.ellipsis),
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

    if (status == ServerStatus.running ||
        status == ServerStatus.starting ||
        status == ServerStatus.stopping) {
      final canStop = status == ServerStatus.running;
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: canStop ? server.stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmForceStop(context, server, theme),
            icon: const Icon(Icons.dangerous_outlined),
            label: const Text('强制'),
          ),
        ],
      );
    }

    if (status == ServerStatus.preparing) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('准备中…'),
      );
    }

    // 已停止：可启动。无 jar 时按钮仍可点击，由 _start 在启动前校验并提示。
    final otherRunning = server.isOtherRunning(widget.instance.id);
    final canStart = ctx != null && !otherRunning;

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

  /// 确认后强制结束服务端进程。
  Future<void> _confirmForceStop(
    BuildContext context,
    ServerController server,
    ThemeData theme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('强制停止', style: TextStyle(color: theme.colorScheme.error)),
        content: const Text('强制结束可能导致服务端数据丢失，确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认强制停止'),
          ),
        ],
      ),
    );
    if (confirmed == true) server.forceStop();
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
    final server = ServerScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) =>
          _InstanceListSheet(controller: controller, server: server),
    );
  }
}

/// 实例列表底部弹窗：展示全部实例 + “新建实例”入口。
class _InstanceListSheet extends StatelessWidget {
  const _InstanceListSheet({required this.controller, required this.server});

  final InstanceController controller;
  final ServerController server;

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
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: '删除实例',
                        onPressed: () =>
                            _confirmDelete(context, instance, theme),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建实例'),
            onTap: () async {
              final navigator = Navigator.of(context);
              final result = await navigator.push<CreateInstanceResult>(
                MaterialPageRoute(builder: (_) => const CreateInstancePage()),
              );
              if (result == CreateInstanceResult.done) {
                navigator.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  /// 两次确认后删除实例：第一次普通确认，第二次强调不可恢复。
  Future<void> _confirmDelete(
    BuildContext context,
    InstanceSummary instance,
    ThemeData theme,
  ) async {
    final navigator = Navigator.of(context);
    final running = server.isActive(instance.id);
    // 第一次确认
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          running
              ? '实例「${instance.name}」正在运行，删除前将自动停止服务。确定删除吗？'
              : '确定要删除实例「${instance.name}」吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (first != true) return;

    if (!context.mounted) return;
    // 第二次确认：强调不可恢复
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('不可恢复', style: TextStyle(color: theme.colorScheme.error)),
        content: Text('删除后实例「${instance.name}」的所有文件将永久丢失，确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (second != true) return;

    // 若该实例正在运行，先强制停止
    if (running) {
      await server.forceStop();
    }

    await controller.deleteInstance(instance.id);
    if (navigator.canPop()) navigator.pop();
  }
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
    final serverStatus = server.status;
    final serverProcessAlive =
        serverStatus == ServerStatus.starting ||
        serverStatus == ServerStatus.running ||
        serverStatus == ServerStatus.stopping;

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

            // 服务端内存（常驻显示，未运行时显示提示信息）
            const SizedBox(height: 12),
            _ServerMemRow(
              memMb: serverProcessAlive ? info.serverMemMb : null,
              maxMemMb: maxMemoryMb,
            ),
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
        _AnimatedProgressBar(percent: percent, color: color, theme: theme),
      ],
    );
  }
}

/// 服务端内存行：当前 VmRSS / 用户设置最大值 + 进度条。
/// [memMb] 为 null 时表示服务端未运行。
class _ServerMemRow extends StatelessWidget {
  const _ServerMemRow({required this.memMb, required this.maxMemMb});

  final int? memMb;
  final int maxMemMb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = memMb != null;
    final percent = running && maxMemMb > 0 ? (memMb! / maxMemMb) * 100.0 : 0.0;
    final color = running
        ? _MonitorCard._colorForPercent(percent, theme)
        : theme.colorScheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.dns,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text('服务端内存', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              running ? '$memMb MB / $maxMemMb MB' : '服务端未运行',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _AnimatedProgressBar(percent: percent, color: color, theme: theme),
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
                  child: SizedBox.expand(child: ColoredBox(color: color)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 获取设备局域网 IP 地址（优先 WiFi，其次有线）。
Future<String?> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      // 跳过回环接口。
      if (iface.name == 'lo' || iface.name == 'lo0') continue;
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (_) {
    // 网络权限问题或接口不可用。
  }
  return null;
}

/// 连接信息卡片：显示内网 IP、映射状态、公网 IP。
///
/// 仅在服务器运行时显示。
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.server});

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upnpActive = server.isUpnpActive;
    final tunnelActive = server.isTunnelActive;
    final upnpIp = server.upnpExternalIp;
    final upnpPort = server.upnpMappedPort;
    final frpConfig = server.activeFrpcConfig;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行。
            Row(
              children: [
                Icon(Icons.link, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '连接信息',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 内网连接地址。
            FutureBuilder<String?>(
              future: _getLocalIp(),
              builder: (context, snapshot) {
                final localIp = snapshot.data ?? '…';
                return _infoRow(
                  context,
                  theme,
                  icon: Icons.lan_outlined,
                  label: '内网地址',
                  value: '$localIp:${upnpPort ?? 25565}',
                  canCopy: snapshot.hasData,
                );
              },
            ),

            // 映射状态指示器。
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _statusChip(
                  theme,
                  icon: Icons.router_outlined,
                  label: 'UPnP',
                  active: upnpActive,
                  success: upnpIp != null,
                ),
                _statusChip(
                  theme,
                  icon: Icons.cloud_outlined,
                  label: 'FRP',
                  active: tunnelActive,
                  success: tunnelActive,
                ),
              ],
            ),

            // UPnP 公网 IP（映射成功时显示）。
            if (upnpActive && upnpIp != null && upnpPort != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _infoRow(
                  context,
                  theme,
                  icon: Icons.public,
                  label: 'UPnP 公网',
                  value: '$upnpIp:$upnpPort',
                  canCopy: true,
                ),
              ),

            // FRP 公网地址（隧道运行时显示）。
            if (tunnelActive && frpConfig != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _infoRow(
                  context,
                  theme,
                  icon: Icons.cloud_outlined,
                  label: 'FRP 公网',
                  value: '${frpConfig.serverAddr}:${frpConfig.remotePort}',
                  canCopy: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 信息行：图标 + 标签 + 值，可选复制按钮。
  Widget _infoRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    bool canCopy = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canCopy)
          InkWell(
            onTap: () => _copyAddress(context, value),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// 状态芯片：显示映射功能的启用状态。
  Widget _statusChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool active,
    required bool success,
  }) {
    final Color color;
    final String statusText;
    if (!active) {
      color = theme.colorScheme.outline;
      statusText = '未启用';
    } else if (success) {
      color = Colors.green;
      statusText = '已映射';
    } else {
      color = Colors.orange;
      statusText = '连接中';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label $statusText',
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  void _copyAddress(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $address'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// 崩溃报告弹窗
// ──────────────────────────────────────────────────────────

/// 服务端意外退出时展示的崩溃报告对话框。
///
/// 提供导出日志（通过系统分享）和上传日志（在线服务启用时）功能。
class _CrashDialog extends StatefulWidget {
  const _CrashDialog({required this.crash, required this.onlineService});

  final CrashData crash;
  final OnlineService onlineService;

  @override
  State<_CrashDialog> createState() => _CrashDialogState();
}

class _CrashDialogState extends State<_CrashDialog> {
  bool _exporting = false;
  bool _uploading = false;
  bool _uploadOk = false;
  String? _uploadResult;

  /// 设备信息 + 系统信息头部，在 init 时异步获取。
  String _deviceHeader = '正在获取设备信息…';

  @override
  void initState() {
    super.initState();
    _loadDeviceHeader();
  }

  Future<void> _loadDeviceHeader() async {
    try {
      final monitorService = SystemMonitorService();
      final deviceInfo = await monitorService.getDeviceInfo();
      final sysInfo = await monitorService.getSystemInfo();
      final envType = widget.crash.envType == 'php' ? 'PHP' : 'Java';
      final envVersion = _versionLabel(widget.crash.envVersion);
      final header = [
        '=== 设备信息 ===',
        'SoC 型号: ${deviceInfo.socModel}',
        '内存总量: ${sysInfo.totalMemMb} MB',
        '内存已用: ${sysInfo.usedMemMb} MB',
        '环境类型: $envType',
        '环境版本: $envVersion',
        '设备架构: ${deviceInfo.architecture}',
        '设备制造商: ${deviceInfo.manufacturer}',
        '设备型号: ${deviceInfo.model}',
        '安卓版本: ${deviceInfo.androidVersion}',
        '安全补丁: ${deviceInfo.securityPatch}',
        '退出码: ${widget.crash.exitCode}',
        '================',
        '',
      ].join('\n');
      if (mounted) setState(() => _deviceHeader = header);
    } catch (_) {
      if (mounted) setState(() => _deviceHeader = '(设备信息获取失败)\n\n');
    }
  }

  static String _versionLabel(String version) {
    const labels = {
      'jre17': 'Java 17',
      'jre21': 'Java 21',
      'jre25': 'Java 25',
      'php8.2': 'PHP 8.2',
    };
    return labels[version] ?? version;
  }

  /// 拼接完整日志内容（设备信息 + 控制台输出）。
  String _buildFullLog() => '$_deviceHeader${widget.crash.logLines.join('\n')}';

  /// 导出日志：写入临时文件并通过系统分享发送。
  Future<void> _exportLog() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, 'edgecube_crash_$ts.log'));
      await file.writeAsString(_buildFullLog());
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'EdgeCube 服务端崩溃日志'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 上传日志到 EdgeCube 服务器。
  Future<void> _uploadLog() async {
    if (_uploading) return;
    final deviceId = widget.onlineService.deviceId;
    if (deviceId == null) {
      setState(() {
        _uploadResult = '设备 ID 不可用';
        _uploadOk = false;
      });
      return;
    }
    setState(() {
      _uploading = true;
      _uploadResult = null;
      _uploadOk = false;
    });
    final result = await ErrorReportService.upload(
      logContent: _buildFullLog(),
      deviceId: deviceId,
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _uploadOk = result.success;
      _uploadResult = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onlineEnabled =
        widget.onlineService.enabled && widget.onlineService.deviceId != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 24),
          const SizedBox(width: 8),
          const Text('服务端意外退出'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '服务端进程已意外退出（退出码 ${widget.crash.exitCode}）。'
            '您可以导出日志用于排查，'
            '${onlineEnabled ? '或上传日志帮助我们改进。' : '或启用在线服务以上传日志帮助我们改进。'}',
          ),
          if (_uploadResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _uploadResult!,
              style: TextStyle(
                color: _uploadOk ? Colors.green : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        OutlinedButton.icon(
          onPressed: _exporting ? null : _exportLog,
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: const Text('导出日志'),
        ),
        if (onlineEnabled)
          FilledButton.icon(
            onPressed: _uploading ? null : _uploadLog,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: const Text('上传日志'),
          ),
      ],
    );
  }
}
