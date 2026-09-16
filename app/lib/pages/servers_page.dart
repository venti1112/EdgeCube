import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';
import '../instance/instance_list_sheet.dart';
import '../instance/instance_settings_dialog.dart';
import '../instance/models.dart';
import '../instance/providers.dart';

/// 连接事件：有人接入/断开时刷新 `core.info`，让「当前连接数」是活的。
const _connectionTopics = ['core.conn_opened', 'core.conn_closed'];

final _connectionEventsProvider = Provider<void>((ref) {
  for (final topic in _connectionTopics) {
    unawaited(ref.read(connectionProvider.notifier).subscribe(topic));
  }

  final client = ref.watch(daemonClientProvider);
  if (client == null) return;

  final subscription = client.events.listen((event) {
    if (_connectionTopics.contains(event['topic'])) {
      ref.invalidate(serverInfoProvider);
    }
  });
  ref.onDispose(subscription.cancel);
});

/// 「服务器」页：实例列表 / 选中 / 信息 / 编辑 / 删除 / 新建。
///
/// 排版对应 V1 的两块 UI：顶部的**实例选择器**（点开是底部的实例列表弹窗，
/// 见 `InstanceListSheet`）+ 实例信息卡片；编辑走 `InstanceSettingsDialog`
/// （V1 的「实例设置」对话框），删除走两步确认。
class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 订阅 instance.* / core.conn_* 事件，两者的变化都会自动刷新页面
    ref.watch(instanceEventsProvider);
    ref.watch(_connectionEventsProvider);

    final connected = ref.watch(isConnectedProvider);
    final list = ref.watch(instanceListProvider).value;
    final detail = ref.watch(selectedInstanceDetailProvider).value;
    final info = ref.watch(serverInfoProvider);

    void refresh() {
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
      ref.invalidate(serverInfoProvider);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务器'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
          IconButton(
            tooltip: '新建实例',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/instance/create');
              refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refresh(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _InstanceSelectorCard(
              connected: connected,
              list: list,
              detail: detail,
            ),
            const SizedBox(height: 12),
            _InstanceInfoCard(detail: detail),
            const SizedBox(height: 12),
            _DaemonCard(info: info),
          ],
        ),
      ),
    );
  }
}

/// 实例选择卡：显示当前实例，点开是实例列表弹窗（V1 的实例选择器）。
class _InstanceSelectorCard extends ConsumerWidget {
  const _InstanceSelectorCard({
    required this.connected,
    required this.list,
    required this.detail,
  });

  final bool connected;
  final InstanceList? list;
  final InstanceDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instances = list?.instances ?? const <InstanceSummary>[];
    final selected = detail?.instance;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('当前实例', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  key: const Key('servers_edit_instance'),
                  tooltip: '实例设置',
                  icon: const Icon(Icons.tune),
                  onPressed: selected == null
                      ? null
                      : () => showInstanceSettingsDialog(context, ref, selected),
                ),
                IconButton(
                  key: const Key('servers_delete_instance'),
                  tooltip: '删除实例',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: selected == null || !connected
                      ? null
                      : () => confirmDeleteInstance(
                          context,
                          ref,
                          InstanceSummary(
                            id: selected.id,
                            name: selected.name,
                            selected: true,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!connected)
              Text(
                '未连接到守护进程，读不到实例列表',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              )
            else if (instances.isEmpty)
              Text(
                '还没有实例，点右上角「+」新建一个',
                key: const Key('servers_no_instance'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              // V1 的实例选择按钮：名称 + 下拉箭头
              InkWell(
                key: const Key('servers_instance_selector'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => InstanceListSheet.show(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          selected?.name ?? '选择实例',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                      const SizedBox(width: 8),
                      Text(
                        '（共 ${instances.length} 个实例）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (selected != null)
              Text(
                'id: ${selected.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 实例信息卡：元数据 + 磁盘状态 + 提醒。
class _InstanceInfoCard extends StatelessWidget {
  const _InstanceInfoCard({required this.detail});

  final InstanceDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = detail;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('实例信息', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (current != null)
                  _ServerPhaseChip(phase: current.status.phase),
              ],
            ),
            const SizedBox(height: 8),
            if (current == null)
              Text(
                '未选中实例',
                key: const Key('servers_info_empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              _row(theme, '名称', current.instance.name),
              _row(theme, '运行环境', runtimeLabel(current.instance.runtime)),
              _row(
                theme,
                '运行环境 ID',
                current.instance.runtimeEnvId ?? '（未指定）',
              ),
              if (!current.instance.isProot)
                _row(theme, '最大内存', current.instance.memoryLabel),
              if (!current.instance.isProot)
                _row(
                  theme,
                  '服务端文件',
                  current.instance.serverFile ?? '（未指定）',
                ),
              if (current.instance.customJvmArgs != null)
                _row(theme, 'JVM 参数', current.instance.customJvmArgs!),
              _row(theme, '兼容模式', current.instance.compatMode ? '开启' : '关闭'),
              _row(
                theme,
                '关服自动重启',
                current.instance.autoRestartOnExit ? '开启' : '关闭',
              ),
              _row(theme, '实例目录', current.status.dir),
              _row(
                theme,
                '占用空间',
                '${current.status.sizeHuman}'
                    '${current.status.sizeTruncated ? '（下限）' : ''}'
                    ' · ${current.status.fileCount} 个文件'
                    ' · ${current.status.dirCount} 个子目录',
              ),
              _row(theme, '创建时间', _formatTime(current.instance.createdAtMs)),
              _row(theme, '最后修改', _formatTime(current.instance.updatedAtMs)),
              if (!current.status.processManaged)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '进程管理尚未接入：这里只反映磁盘状态，阶段恒为「已停止」。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (current.status.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                _WarningBox(warnings: current.status.warnings),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    ),
  );
}

/// 元数据/目录有问题时的提醒块。
class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('servers_warnings'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 生命周期阶段标签。
class _ServerPhaseChip extends StatelessWidget {
  const _ServerPhaseChip({required this.phase});

  final ServerPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (phase) {
      ServerPhase.running => scheme.primary,
      ServerPhase.crashed => scheme.error,
      ServerPhase.stopped => scheme.outline,
      _ => scheme.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        phase.label,
        key: const Key('server_phase_chip'),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

/// 守护进程信息卡（`core.info` 的返回值）。
class _DaemonCard extends StatelessWidget {
  const _DaemonCard({required this.info});

  final AsyncValue<Map<String, dynamic>> info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('守护进程', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            info.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Text(
                '读取失败：$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
              data: (data) {
                if (data.isEmpty) {
                  return Text(
                    '未连接，暂无数据',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  children: [
                    _row(theme, '产品', '${data['product']} ${data['version']}'),
                    _row(theme, '监听地址', '${data['bind']}'),
                    _row(theme, '运行时长', '${data['uptime_human']}'),
                    _row(theme, '平台', '${data['os']} / ${data['arch']}'),
                    _row(theme, '当前连接数', '${data['connections']}'),
                    _row(theme, '事件订阅数', '${data['subscribers']}'),
                    _row(
                      theme,
                      '鉴权',
                      data['auth_required'] == true ? '开启' : '关闭',
                    ),
                    _row(
                      theme,
                      '配置文件',
                      '${data['config_path'] ?? '（默认值）'}',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    ),
  );
}
