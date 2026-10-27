import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'model.dart';
import 'settings.dart';
import 'state.dart';

/// 连接页与连接设置页共用的本地服务卡片。
///
/// 平台不支持时(Web、尚未接入原生进程的桌面端)不显示入口;
/// 设置页额外带一个开关,它就是「本地服务」这个独立配置项。
class LocalServicePanel extends ConsumerStatefulWidget {
  const LocalServicePanel({
    super.key,
    this.showSwitch = false,
    this.showLogs = true,
  });

  /// 设置页显示开关(持久化「打开应用时自动启动」);连接页只给按钮。
  final bool showSwitch;
  final bool showLogs;

  @override
  ConsumerState<LocalServicePanel> createState() => _LocalServicePanelState();
}

class _LocalServicePanelState extends ConsumerState<LocalServicePanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = ref.watch(localServiceEnabledProvider);
    final snapshot = ref.watch(localServiceProvider);
    final status = snapshot.status;

    if (snapshot.supported == null) return const SizedBox.shrink();
    if (snapshot.supported == false) {
      if (!widget.showSwitch) return const SizedBox.shrink();
      // 开关可能是从别的平台带过来的残值:允许关掉,但不能启动
      return Card(
        margin: EdgeInsets.zero,
        child: SwitchListTile(
          key: const Key('local_service_switch'),
          title: const Text('本地服务'),
          subtitle: const Text('当前平台暂不支持本地服务'),
          value: enabled,
          onChanged: enabled
              ? (value) {
                  if (!value) {
                    ref.read(localServiceEnabledProvider.notifier).set(false);
                  }
                }
              : null,
        ),
      );
    }

    final busy = status.isBusy;
    return Card(
      key: const Key('local_service_panel'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showSwitch)
              SwitchListTile(
                key: const Key('local_service_switch'),
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Icon(
                      Icons.memory_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('本地服务'),
                  ],
                ),
                subtitle: const Text('打开应用时自动启动本机 daemon，关闭时停止'),
                value: enabled,
                onChanged: (value) {
                  final notifier = ref.read(localServiceProvider.notifier);
                  if (value) {
                    notifier.start();
                  } else {
                    notifier.stop();
                  }
                },
              )
            else
              Row(
                children: [
                  Icon(Icons.memory_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('本地服务', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            if (!widget.showSwitch) ...[
              const SizedBox(height: 4),
              Text(
                '在运行 App 的设备上启动 daemon，仅本机可访问',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),

            _StatusLine(status: status),
            if (status.phase == LocalServicePhase.failed &&
                snapshot.error != null) ...[
              const SizedBox(height: 4),
              Text(
                snapshot.error!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                if (!status.isActive)
                  FilledButton.tonalIcon(
                    key: const Key('local_service_start'),
                    onPressed: () =>
                        ref.read(localServiceProvider.notifier).start(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动本地服务'),
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('local_service_stop'),
                    onPressed: status.phase == LocalServicePhase.stopping
                        ? null
                        : () => ref.read(localServiceProvider.notifier).stop(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      status.phase == LocalServicePhase.stopping
                          ? '正在停止…'
                          : '停止本地服务',
                    ),
                  ),
              ],
            ),

            if (widget.showLogs) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('启动日志', style: theme.textTheme.labelMedium),
                  const Spacer(),
                  if (snapshot.logs.isNotEmpty)
                    TextButton(
                      key: const Key('local_service_log_clear'),
                      onPressed: () =>
                          ref.read(localServiceProvider.notifier).clearLogs(),
                      child: const Text('清空'),
                    ),
                ],
              ),
              _LogBox(lines: snapshot.logs),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行状态:转圈 / 对勾 / 错误 / 电源图标 + 说明。
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final LocalServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData? icon, Color color) = switch (status.phase) {
      LocalServicePhase.running => (Icons.check_circle_outline, scheme.primary),
      LocalServicePhase.failed => (Icons.error_outline, scheme.error),
      LocalServicePhase.stopped => (
        Icons.circle_outlined,
        scheme.onSurfaceVariant,
      ),
      _ => (null, scheme.onSurfaceVariant),
    };
    final text = switch (status.phase) {
      LocalServicePhase.stopped =>
        status.prepared ? '未启动（本地环境已就绪）' : '未启动，首次启动会准备本地环境',
      LocalServicePhase.preparing => status.message ?? '正在准备本地环境…',
      LocalServicePhase.starting => status.message ?? '正在启动本地服务…',
      LocalServicePhase.stopping => status.message ?? '正在停止本地服务…',
      LocalServicePhase.running =>
        '已启动：${status.host ?? '127.0.0.1'}:${status.port ?? '?'}',
      LocalServicePhase.failed => status.message ?? '启动失败',
    };
    return Row(
      key: const Key('local_service_status'),
      children: [
        if (icon == null)
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        else
          Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 有界高度的日志框:新日志到达时自动滚到底部。
class _LogBox extends StatefulWidget {
  const _LogBox({required this.lines});

  final List<String> lines;

  @override
  State<_LogBox> createState() => _LogBoxState();
}

class _LogBoxState extends State<_LogBox> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant _LogBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length) _scrollToBottom();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11.5,
      height: 1.35,
      color: scheme.onSurfaceVariant,
    );
    return Container(
      key: const Key('local_service_logs'),
      height: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: widget.lines.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.zero,
              itemCount: widget.lines.length,
              itemBuilder: (context, index) =>
                  Text(widget.lines[index], style: style),
            ),
    );
  }
}
