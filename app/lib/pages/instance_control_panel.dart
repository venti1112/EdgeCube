import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'labels.dart';

/// 当前实例控制面板(完全对齐 V1 `_ServerControlPanel`):
/// 状态卡(大状态图标 + 实例名 + 状态文案 + 运行环境标签 + 设置齿轮) →
/// 操作区(第一行整宽「启动/停止」主按钮,第二行「重启 | 强制停止」等分;
/// 无删除按钮——删除入口在服务器页的实例选择列表,对齐 V1) →
/// 页脚附加卡片(系统状态监控卡)。
/// 实例配置经状态卡齿轮弹出的「实例配置」对话框编辑(名称/运行环境/启动命令/
/// 停止命令/自动重启/开机自启),保存即全量 PUT。状态经 3 秒轮询刷新。
class InstanceControlPanel extends ConsumerStatefulWidget {
  const InstanceControlPanel({
    super.key,
    required this.instanceId,
    this.onDeleted,
    this.footer = const [],
  });

  final String instanceId;

  /// 删除实例成功后的回调(供页面刷新列表并触发选中项回退)。
  final VoidCallback? onDeleted;

  /// 追加在面板列表末尾的附加卡片(如系统状态监控卡,对齐 V1 面板布局)。
  final List<Widget> footer;

  @override
  ConsumerState<InstanceControlPanel> createState() =>
      _InstanceControlPanelState();
}

class _InstanceControlPanelState extends ConsumerState<InstanceControlPanel> {
  static const _pollInterval = Duration(seconds: 3);

  Timer? _timer;
  InstanceDetail? _detail;
  bool _loading = true;
  String? _error;

  /// 正在提交的操作按钮,防止连点。
  String? _busy;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final detail = (await client
              .getInstancesApi()
              .getInstance(instanceId: widget.instanceId))
          .data!;
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String action, Future<void> Function() call) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      await call();
      _snack('已提交$action操作');
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ────────────────────────── 操作(对齐 V1 _actions) ──────────────────────────

  /// 强制停止:确认后提交强杀(V1 _confirmForceStop)。
  Future<void> _confirmKill() async {
    if (_busy != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('强制停止'),
        content: const Text('确定强制结束该实例进程吗?未保存的数据可能丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('强制停止'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('强杀', () => _client!
        .getInstancesApi()
        .killInstance(instanceId: widget.instanceId));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return _loading && detail == null
        ? const Center(child: CircularProgressIndicator())
        : detail == null
            ? _errorView()
            : RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _statusCard(detail),
                    const SizedBox(height: 16),
                    _actions(detail),
                    for (final item in widget.footer) ...[
                      const SizedBox(height: 16),
                      item,
                    ],
                  ],
                ),
              );
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text('加载失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(
          child: TextButton(onPressed: _load, child: const Text('重试')),
        ),
      ],
    );
  }

  // ────────────────────────── 状态卡(对齐 V1 _statusCard) ──────────────────────────

  Widget _statusCard(InstanceDetail detail) {
    final cs = Theme.of(context).colorScheme;
    final status = detail.status.status;
    final config = detail.config;
    // 注意:生成的 InstanceStatus 为 built_value EnumClass(非 Dart enum),
    // switch 表达式无法穷尽检查,须保留 `_` 兜底(与 labels.dart 口径一致)。
    final (IconData icon, Color color, String text) = switch (status) {
      InstanceStatus.stopped => (
        Icons.stop_circle_outlined,
        cs.outline,
        instanceStatusLabel(status),
      ),
      InstanceStatus.starting => (
        Icons.hourglass_top,
        Colors.orange,
        instanceStatusLabel(status),
      ),
      InstanceStatus.running => (
        Icons.play_circle,
        Colors.green,
        instanceStatusLabel(status),
      ),
      InstanceStatus.stopping => (
        Icons.hourglass_bottom,
        Colors.orange,
        instanceStatusLabel(status),
      ),
      _ => (
        Icons.hourglass_empty,
        Colors.orange,
        instanceStatusLabel(status),
      ),
    };
    // 已停止且存在上次退出码时,状态文案附带退出码(对齐 V1 statusWithExitCode)
    final exitCode = detail.status.exitCode;
    final statusText = status == InstanceStatus.stopped && exitCode != null
        ? '$text(退出码 $exitCode)'
        : text;
    return Card(
      margin: EdgeInsets.zero,
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
                    config.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color),
                  ),
                  if (config.runtimeId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '使用环境:${config.runtimeId}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
              tooltip: '实例配置',
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────── 操作按钮(对齐 V1 _actions) ──────────────────────────

  Widget _actions(InstanceDetail detail) {
    final busy = _busy != null;
    final status = detail.status.status;
    final running = status == InstanceStatus.running;
    final stopped = status == InstanceStatus.stopped;

    // 第一行主按钮(整宽):已停止显示「启动」,其余显示「停止」(仅运行中可点);
    // 忙碌态显示进度占位(对齐 V1 preparing 分支)。
    final Widget primaryButton = switch (status) {
      InstanceStatus.busy => FilledButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('忙碌'),
        ),
      InstanceStatus.stopped => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : () => _run('启动', () => _client!
                .getInstancesApi()
                .startInstance(instanceId: widget.instanceId)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动'),
          ),
        ),
      _ => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: running && !busy ? () => _run('停止', () => _client!
                .getInstancesApi()
                .stopInstance(instanceId: widget.instanceId)) : null,
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
          ),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第一行:启动 / 停止(整宽)
        primaryButton,
        const SizedBox(height: 12),
        // 第二行:重启(左) | 强制停止(右),等分
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: running && !busy ? () => _run('重启', () => _client!
                    .getInstancesApi()
                    .restartInstance(instanceId: widget.instanceId)) : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt, size: 18),
                    SizedBox(width: 8),
                    Text('重启'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: !stopped && !busy ? _confirmKill : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dangerous_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('强杀'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ────────────────────────── 实例配置对话框(对齐 V1 _openSettings) ──────────────────────────

  /// 打开「实例配置」对话框:名称 / 运行环境 / 启动命令 / 优雅停止命令 /
  /// 自动重启 / 开机自启。保存即全量 PUT(daemon 无独立 rename 接口,
  /// 重名由后端 409 提示)。
  Future<void> _openSettings() async {
    final client = _client;
    final config = _detail?.config;
    if (client == null || config == null) return;

    // 先拉取已安装运行时供「运行环境」下拉选择
    setState(() => _busy = '配置');
    List<RuntimeInfo> runtimes;
    try {
      runtimes = (await client.getRuntimesApi().listRuntimes()).data!.toList();
    } catch (e) {
      if (mounted) {
        _snack(apiErrorMessage(e));
        setState(() => _busy = null);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);

    final nameController = TextEditingController(text: config.name);
    final startController =
        TextEditingController(text: config.startCommand ?? '');
    final stopController = TextEditingController(text: config.stopCommand ?? '');
    String? runtimeId = config.runtimeId;
    bool autoRestart = config.autoRestart ?? false;
    bool autoStartOnBoot = config.autoStartOnBoot ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('实例配置', textAlign: TextAlign.center),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '实例名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 运行环境:daemon 已安装的运行时(对齐 V1 运行环境下拉)
                  DropdownButtonFormField<String?>(
                    initialValue: runtimeId,
                    decoration: const InputDecoration(
                      labelText: '运行环境',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('不指定(使用系统环境)'),
                      ),
                      for (final r in runtimes)
                        DropdownMenuItem<String?>(
                          value: r.id,
                          child:
                              Text('${runtimeTypeLabel(r.type)} ${r.version}'),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => runtimeId = v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: startController,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '启动命令',
                      hintText: 'java -Xmx1024M -jar server.jar nogui',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: stopController,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '优雅停止命令',
                      hintText: '^C',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动重启'),
                    subtitle: const Text('进程意外退出后自动拉起'),
                    value: autoRestart,
                    onChanged: (v) => setDialogState(() => autoRestart = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开机自启'),
                    subtitle: const Text('daemon 启动时自动启动该实例'),
                    value: autoStartOnBoot,
                    onChanged: (v) =>
                        setDialogState(() => autoStartOnBoot = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    // 先取值再释放控制器(dispose 后不可再读取 text)
    final newName = nameController.text.trim();
    final newStartCommand = startController.text.trim();
    final newStopCommand = stopController.text.trim();
    nameController.dispose();
    startController.dispose();
    stopController.dispose();
    if (saved != true || !mounted) return;

    // 保存:全量替换(未编辑字段透传原值)
    await _run('保存', () async {
      await client.getInstancesApi().updateInstance(
            instanceId: widget.instanceId,
            instanceConfig: InstanceConfig((b) {
              b
                ..id = config.id
                ..name = newName.isNotEmpty ? newName : config.name
                ..stopTimeoutSeconds = config.stopTimeoutSeconds
                ..workingDirectory = config.workingDirectory
                ..inputEncoding = config.inputEncoding
                ..outputEncoding = config.outputEncoding
                ..autoRestartMaxTimes = config.autoRestartMaxTimes
                ..type = config.type
                ..runtimeId = runtimeId
                ..startCommand = newStartCommand
                ..stopCommand = newStopCommand
                ..autoRestart = autoRestart
                ..autoStartOnBoot = autoStartOnBoot;
              if (config.environment != null) {
                b.environment.replace(config.environment!);
              }
              if (config.terminal != null) {
                b.terminal = config.terminal!.toBuilder();
              }
            }),
          );
      _load();
    });
  }
}
