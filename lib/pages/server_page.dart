import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/locale_scope.dart';
import '../instance/create_instance_page.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../online/error_report_service.dart';
import '../online/online_service.dart';
import '../route_observer.dart';
import '../server/runtime_service.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import 'runtime_page.dart';
import '../server/system_monitor_scope.dart';
import '../server/system_monitor_service.dart';
import '../widgets/placeholder_page.dart';

class ServerPage extends StatelessWidget {
  const ServerPage({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final selected = controller.selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('server.title')),
        actions: [
          _InstanceSelectorButton(controller: controller, selected: selected),
          const SizedBox(width: 4),
        ],
      ),
      body: selected == null
          ? PlaceholderPage(
              icon: Icons.dns_outlined,
              title: context.tr('server.noInstanceTitle'),
              description: context.tr('server.noInstanceDescription'),
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
/// 当前架构可用的 JRE 版本与 PHP 运行时，以及运行时 id→名称映射。
class _LaunchContext {
  const _LaunchContext({
    required this.workingDir,
    required this.jars,
    required this.phars,
    required this.versions,
    required this.phpRuntimes,
    required this.runtimeNames,
  });

  final String workingDir;
  final List<String> jars;
  final List<String> phars;
  final List<String> versions;
  final List<String> phpRuntimes;
  final Map<String, String> runtimeNames;
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

class _ServerControlPanelState extends State<_ServerControlPanel>
    with RouteAware {
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
    // FRP 隧道异常退出时复用同一崩溃弹窗（导出/上传日志）。
    server.onTunnelCrashExit = _onTunnelCrashExit;
    // 监听运行时导入/删除，自动刷新可用运行时列表。
    RuntimeService.refreshSignal.addListener(_onRuntimesChanged);
  }

  /// 运行时列表变化时重新加载上下文。
  void _onRuntimesChanged() {
    if (mounted) {
      setState(() => _ctxFuture = _loadContext());
    }
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

  /// FRP 隧道异常退出回调。复用 [_CrashDialog]，由 [CrashData.kind] 控制文案。
  void _onTunnelCrashExit(CrashData crash) {
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
    // 订阅路由事件，从运行环境页返回时自动刷新可用运行时列表。
    appRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    if (mounted) {
      setState(() => _ctxFuture = _loadContext());
    }
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
    RuntimeService.refreshSignal.removeListener(_onRuntimesChanged);
    appRouteObserver.unsubscribe(this);
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
            l.contains('forge') ||
            l.contains('powernukkitx') ||
            l.contains('pnx')) {
          return 1;
        }
        return 2;
      }

      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });
    phars.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final versions = await server.availableJreIds();
    final phpRuntimes = await server.availablePhpIds();
    final runtimeService = const RuntimeService();
    final runtimes = await runtimeService.installedRuntimes();
    final runtimeNames = <String, String>{
      for (final rt in runtimes) rt.id: rt.name,
    };
    return _LaunchContext(
      workingDir: dir.path,
      jars: jars,
      phars: phars,
      versions: versions,
      phpRuntimes: phpRuntimes,
      runtimeNames: runtimeNames,
    );
  }

  /// 启动前检查 eula.txt 中 eula=true 是否已设置。
  ///
  /// - 已设置：直接返回 `true`；
  /// - 未设置：弹出 Minecraft EULA 确认对话框让用户选择，
  ///   同意后写入 `eula=true` 并返回 `true`，拒绝则返回 `false`。
  Future<bool> _ensureEula(String workingDir) async {
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
    if (!needWrite) return true;

    // EULA 尚未同意，弹窗询问用户
    if (!mounted) return false;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Minecraft EULA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '启动 Minecraft 服务端前需要同意 Minecraft 最终用户许可协议（EULA）。',
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  // 在外部浏览器打开 EULA 链接
                  launchUrl(
                    Uri.parse('https://aka.ms/MinecraftEULA'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text(
                  'https://aka.ms/MinecraftEULA',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '点击下方「同意」将向 eula.txt 写入 eula=true，'
                '表示你已阅读并同意该协议。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (agreed == true) {
      await eulaFile.writeAsString(
        '#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\n'
        'eula=true\n',
      );
      return true;
    }
    return false;
  }

  void _start(ServerController server, _LaunchContext ctx) async {
    final file = _selectedJar;

    // PHP（PocketMine）：用 PHP 运行时执行选中的 .phar。
    if (_isPhp) {
      if (ctx.phpRuntimes.isEmpty) {
        _showRuntimeRequiredDialog(isJava: false);
        return;
      }
      if (file == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('server.noPharFound'))),
        );
        return;
      }
      server.start(
        instanceId: widget.instance.id,
        instanceName: widget.instance.name,
        workingDir: ctx.workingDir,
        runtimeId: ctx.phpRuntimes.first,
        runtime: kRuntimePhp,
        jvmArgs: const [],
        programArgs: [file],
        compatMode: _compatMode,
      );
      return;
    }

    // Java：需要至少一个 JRE 运行时。
    if (ctx.versions.isEmpty) {
      _showRuntimeRequiredDialog(isJava: true);
      return;
    }

    // Java：用 JRE 执行选中的 .jar。
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('server.noJarFound'))));
      return;
    }
    final mem = int.tryParse(_memController.text.trim());
    final jvmArgs = <String>[
      if (mem != null && mem > 0) '-Xmx${mem}M',
      // 追加用户自定义 JVM 参数（以空白符/换行分隔）。
      ..._parseCustomJvmArgs(widget.instance.customJvmArgs),
    ];
    // 启动前确保 EULA 已同意，未同意则中止启动
    if (!await _ensureEula(ctx.workingDir)) return;
    server.start(
      instanceId: widget.instance.id,
      instanceName: widget.instance.name,
      workingDir: ctx.workingDir,
      runtimeId: _version,
      runtime: kRuntimeJava,
      jvmArgs: jvmArgs,
      programArgs: ['-jar', file, 'nogui'],
      compatMode: _compatMode,
    );
  }

  /// 未安装对应运行时，提示用户前往「运行环境」页导入。
  Future<void> _showRuntimeRequiredDialog({required bool isJava}) async {
    final tr = LocaleScope.of(context).translations;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('server.runtimeRequiredTitle')),
        content: Text(
          tr.get(
            isJava
                ? 'server.runtimeRequiredContentJava'
                : 'server.runtimeRequiredContentPhp',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('server.runtimeRequiredAction')),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RuntimePage()),
      );
    }
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
        context.tr('server.statusStopped'),
      ),
      ServerStatus.preparing => (
        Icons.hourglass_empty,
        Colors.orange,
        context.tr('server.statusPreparing'),
      ),
      ServerStatus.starting => (
        Icons.hourglass_top,
        Colors.orange,
        context.tr('server.statusStarting'),
      ),
      ServerStatus.running => (
        Icons.play_circle,
        Colors.green,
        context.tr('server.statusRunning'),
      ),
      ServerStatus.stopping => (
        Icons.hourglass_bottom,
        Colors.orange,
        context.tr('server.statusStopping'),
      ),
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
                        ? context.tr('server.statusWithExitCode', {
                            'status': text,
                            'code': '$exitCode',
                          })
                        : text,
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: context.tr('server.instanceConfig'),
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
              title: Text(context.tr('server.instanceConfig')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: context.tr('server.nameLabel'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 运行环境：Java（JVM 跑 .jar）/ PHP（PocketMine 跑 .phar）。
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _runtime,
                      decoration: InputDecoration(
                        labelText: context.tr('server.runtimeLabel'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: kRuntimeJava,
                          child: Text(context.tr('server.runtimeJava')),
                        ),
                        DropdownMenuItem(
                          value: kRuntimePhp,
                          child: Text(context.tr('server.runtimePhp')),
                        ),
                      ],
                      selectedItemBuilder: (context) => [
                        DropdownMenuItem<String>(
                          value: kRuntimeJava,
                          child: Text(
                            context.tr('server.runtimeJava'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem<String>(
                          value: kRuntimePhp,
                          child: Text(
                            context.tr('server.runtimePhp'),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                        isExpanded: true,
                        initialValue: ctx.versions.contains(_version)
                            ? _version
                            : null,
                        decoration: InputDecoration(
                          labelText: context.tr('server.javaVersionLabel'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final v in ctx.versions)
                            DropdownMenuItem(
                              value: v,
                              child: Text(ctx.runtimeNames[v] ?? v),
                            ),
                        ],
                        selectedItemBuilder: (context) => [
                          for (final v in ctx.versions)
                            DropdownMenuItem<String>(
                              value: v,
                              child: Text(
                                ctx.runtimeNames[v] ?? v,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                        decoration: InputDecoration(
                          labelText: context.tr('server.maxMemoryLabel'),
                          suffixText: 'MB',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      // PHP 运行时版本（只读；当前仅 PHP 8.2，且仅 arm64 提供）。
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: context.tr('server.runtimeVersionLabel'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text(
                          ctx.phpRuntimes.isNotEmpty
                              ? (ctx.runtimeNames[ctx.phpRuntimes.first] ??
                                    ctx.phpRuntimes.first)
                              : context.tr('server.phpArchUnsupported'),
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
                        decoration: InputDecoration(
                          labelText: context.tr('server.jvmArgsLabel'),
                          hintText: context.tr('server.jvmArgsHint'),
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _compatMode,
                      onChanged: (v) => setDialogState(() => _compatMode = v),
                      title: Text(context.tr('server.compatModeTitle')),
                      subtitle: Text(context.tr('server.compatModeSubtitle')),
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
                              title: Text(context.tr('server.noticeTitle')),
                              content: Text(
                                context.tr('server.duplicateName', {
                                  'name': newName,
                                }),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(context.tr('common.ok')),
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
                  child: Text(context.tr('common.save')),
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
    final label = _isPhp
        ? context.tr('server.serverPharLabel')
        : context.tr('server.serverJarLabel');
    if (files.isEmpty) {
      return Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('server.fileNotFound', {'ext': ext}),
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
              label: Text(context.tr('common.stop')),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _confirmForceStop(context, server, theme),
            icon: const Icon(Icons.dangerous_outlined),
            label: Text(context.tr('server.forceStopShort')),
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
        label: Text(context.tr('server.statusPreparing')),
      );
    }

    // 已停止：可启动。无 jar 时按钮仍可点击，由 _start 在启动前校验并提示。
    final otherRunning = server.isOtherRunning(widget.instance.id);
    final canStart = ctx != null && !otherRunning;

    String? hint;
    if (otherRunning) {
      hint = context.tr('server.otherRunningHint', {
        'name': server.runningInstanceName ?? '',
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: canStart ? () => _start(server, ctx) : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(context.tr('common.start')),
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
        title: Text(
          context.tr('server.forceStopTitle'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
        content: Text(context.tr('server.forceStopContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('server.forceStopConfirm')),
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
                selected?.name ?? context.tr('server.selectInstance'),
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
            child: Text(
              context.tr('server.selectInstance'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (instances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('server.noInstanceHint'),
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
                        tooltip: context.tr('server.deleteInstance'),
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
            title: Text(context.tr('server.newInstance')),
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
        title: Text(context.tr('server.confirmDeleteTitle')),
        content: Text(
          running
              ? context.tr('server.confirmDeleteRunning', {
                  'name': instance.name,
                })
              : context.tr('server.confirmDelete', {'name': instance.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.delete')),
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
        title: Text(
          context.tr('server.irreversibleTitle'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
        content: Text(
          context.tr('server.confirmDeleteIrreversible', {
            'name': instance.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('server.confirmDeleteButton')),
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
            Text(
              context.tr('server.systemStatus'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // 设备内存
            _MonitorRow(
              icon: Icons.memory,
              label: context.tr('server.deviceMemory'),
              value: '${info.usedMemMb} MB / ${info.totalMemMb} MB',
              percent: memPercent,
              color: _colorForPercent(memPercent, theme),
            ),
            const SizedBox(height: 12),

            // CPU 使用率
            _MonitorRow(
              icon: Icons.speed,
              label: context.tr('server.cpuUsage'),
              value: info.cpuUsage >= 0
                  ? '${info.cpuUsage.toStringAsFixed(1)}%'
                  : context.tr('server.unavailable'),
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
            Text(
              context.tr('server.serverMemory'),
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              running
                  ? '$memMb MB / $maxMemMb MB'
                  : context.tr('server.serverNotRunning'),
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
    final tunnelRunning = server.isTunnelRunning;
    final tunnelCrashed = server.isTunnelCrashed;
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
                  context.tr('server.connectionInfo'),
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
                  label: context.tr('server.lanAddress'),
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
                  context,
                  theme,
                  icon: Icons.router_outlined,
                  label: 'UPnP',
                  active: upnpActive,
                  success: upnpIp != null,
                ),
                _statusChip(
                  context,
                  theme,
                  icon: Icons.cloud_outlined,
                  label: 'FRP',
                  active: tunnelActive,
                  success: tunnelRunning,
                  error: tunnelCrashed,
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
                  label: context.tr('server.upnpPublic'),
                  value: '$upnpIp:$upnpPort',
                  canCopy: true,
                ),
              ),

            // FRP 公网地址（隧道真正连接成功后显示，与状态芯片的"已映射"一致）。
            if (tunnelRunning && frpConfig != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _infoRow(
                  context,
                  theme,
                  icon: Icons.cloud_outlined,
                  label: context.tr('server.frpPublic'),
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
  ///
  /// 优先级：error（出错，红色）> !active（未启用，灰色）> success（已映射，绿色）
  /// > active && !success（映射中，橙色）。
  Widget _statusChip(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool active,
    required bool success,
    bool error = false,
  }) {
    final Color color;
    final String statusText;
    if (error) {
      color = theme.colorScheme.error;
      statusText = context.tr('server.mappingError');
    } else if (!active) {
      color = theme.colorScheme.outline;
      statusText = context.tr('server.mappingDisabled');
    } else if (success) {
      color = Colors.green;
      statusText = context.tr('server.mappingActive');
    } else {
      color = Colors.orange;
      statusText = context.tr('server.mappingConnecting');
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
        content: Text(context.tr('server.copiedAddress', {'address': address})),
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
      final lines = <String>[
        '=== 设备信息 ===',
        'SoC 型号: ${deviceInfo.socModel}',
        '内存总量: ${sysInfo.totalMemMb} MB',
        '内存已用: ${sysInfo.usedMemMb} MB',
      ];
      // 服务端崩溃才输出运行环境信息；FRP 隧道崩溃无此概念。
      if (widget.crash.kind == 'server') {
        final envType = widget.crash.envType == 'php' ? 'PHP' : 'Java';
        final envRuntimeId = _versionLabel(widget.crash.envRuntimeId);
        lines.add('环境类型: $envType');
        lines.add('运行环境: $envRuntimeId');
      } else {
        lines.add('崩溃来源: FRP 隧道 (frpc)');
      }
      lines
        ..add('设备架构: ${deviceInfo.architecture}')
        ..add('设备制造商: ${deviceInfo.manufacturer}')
        ..add('设备型号: ${deviceInfo.model}')
        ..add('安卓版本: ${deviceInfo.androidVersion}')
        ..add('安全补丁: ${deviceInfo.securityPatch}')
        ..add('退出码: ${widget.crash.exitCode}')
        ..addAll(['================', '']);
      if (mounted) setState(() => _deviceHeader = lines.join('\n'));
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
      final prefix = widget.crash.kind == 'tunnel'
          ? 'edgecube_tunnel_crash_'
          : 'edgecube_crash_';
      final file = File(p.join(dir.path, '$prefix$ts.log'));
      await file.writeAsString(_buildFullLog());
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: context.tr(_shareTextKey),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('server.exportFailed', {'error': '$e'})),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 当前崩溃对应的分享文案翻译键（服务端 / 隧道）。
  String get _shareTextKey => widget.crash.kind == 'tunnel'
      ? 'tunnel.crashLogShareText'
      : 'server.crashLogShareText';

  /// 上传日志到 EdgeCube 服务器。
  Future<void> _uploadLog() async {
    if (_uploading) return;
    final deviceId = widget.onlineService.deviceId;
    if (deviceId == null) {
      setState(() {
        _uploadResult = context.tr('server.deviceIdUnavailable');
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
    final isTunnel = widget.crash.kind == 'tunnel';
    final titleKey = isTunnel ? 'tunnel.crashTitle' : 'server.crashTitle';
    final messageKey = onlineEnabled
        ? (isTunnel
            ? 'tunnel.crashMessageOnline'
            : 'server.crashMessageOnline')
        : (isTunnel
            ? 'tunnel.crashMessageOffline'
            : 'server.crashMessageOffline');

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 24),
          const SizedBox(width: 8),
          Text(context.tr(titleKey)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(messageKey, {'code': '${widget.crash.exitCode}'}),
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
          child: Text(context.tr('common.close')),
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
          label: Text(context.tr('server.exportLog')),
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
            label: Text(context.tr('server.uploadLog')),
          ),
      ],
    );
  }
}
