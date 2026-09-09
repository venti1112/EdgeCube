import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'instance_control_panel.dart';
import 'system_monitor_card.dart';

/// 服务器页(完全对齐 V1):
/// AppBar 右上角「当前实例选择按钮」—— 显示选中实例名,点击弹出单选列表
/// (radio 单选,点击即切换全局当前实例,底部固定「创建实例」入口);
/// 正文为「当前实例控制面板」(状态 + 操作 + 配置),同一时间只操作一个实例。
/// overview 3s 轮询仅用于选择弹窗列表与选中项恢复/回退。
class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  static const _pollInterval = Duration(seconds: 3);

  Timer? _timer;
  InstanceOverview? _overview;
  bool _loading = true;
  String? _error;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    // 定时刷新:选择弹窗列表保持最新,同时同步选中项状态/回退
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
      final overview = (await client.getInstancesApi().getInstancesOverview())
          .data!;
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _error = null;
        _loading = false;
      });
      // 同步全局当前实例:恢复该服务器上次选中/回退第一个/移除已删除项
      ref.read(currentInstanceProvider.notifier).syncWithOverview(overview);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  /// 右上角「当前实例选择按钮」:bottom sheet 单选实例列表(对齐 V1
  /// _InstanceListSheet:radio 单选行 + 副标题实例 id + 行尾删除图标,
  /// 点击行即切换全局当前实例;底部分隔线 + 「新建实例」入口)。
  /// 删除走两次确认(第二次强调不可恢复),成功后收起弹窗并刷新。
  void _openInstancePicker() {
    final items =
        _overview?.items.toList() ?? const <InstanceSummary>[];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final selectedId = ref.read(currentInstanceProvider)?.id;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    '选择实例',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '还没有实例,点击下方「新建实例」开始',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final s in items)
                            ListTile(
                              leading: Icon(
                                s.id == selectedId
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: s.id == selectedId
                                    ? cs.primary
                                    : null,
                              ),
                              title: Text(s.name),
                              subtitle: Text(
                                s.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: cs.error,
                                tooltip: '删除',
                                onPressed: () =>
                                    _confirmDeleteInstance(s, sheetContext),
                              ),
                              onTap: () {
                                // 单选:切换全局当前实例,不跳转(对齐 V1)
                                ref
                                    .read(currentInstanceProvider.notifier)
                                    .select(s);
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建实例'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/servers/instances/create');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 两次确认后删除实例(对齐 V1 _confirmDelete):第一次普通确认,
  /// 第二次强调不可恢复;运行中先强杀再删除,成功后收起弹窗并刷新。
  Future<void> _confirmDeleteInstance(
    InstanceSummary instance,
    BuildContext sheetContext,
  ) async {
    // 先捕获弹窗导航器:确认链路多次 await 后用其收起 bottom sheet
    // (对齐 V1 的 navigator 捕获模式)。
    final sheetNavigator = Navigator.of(sheetContext);
    final first = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: const Text('删除实例'),
        content: Text('确定删除实例「${instance.name}」吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    // 第二次确认:强调不可恢复(用页面自身的 context,由 State.mounted 守卫)
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('不可恢复'),
        content: Text(
            '实例「${instance.name}」的配置将被删除且无法恢复,确定继续吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

    final client = _client;
    if (client == null) return;
    try {
      // 运行中先强杀(失败不阻断删除,对齐 V1 先停止再删除的语义)
      if (instance.status == InstanceStatus.running) {
        try {
          await client.getInstancesApi()
              .killInstance(instanceId: instance.id);
        } catch (_) {}
      }
      await client.getInstancesApi().deleteInstance(instanceId: instance.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    _load(silent: true);
    // 删除成功后收起实例列表弹窗(对齐 V1;sheet 已关闭时 canPop 为 false)
    if (sheetNavigator.canPop()) sheetNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(currentInstanceProvider);
    final overview = _overview;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务器'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openInstancePicker,
            icon: const Icon(Icons.dns),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    selected?.name ?? '选择实例',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && overview == null
          ? const Center(child: CircularProgressIndicator())
          : overview == null
              ? _errorView()
              : selected == null
                  ? _emptyView()
                  : InstanceControlPanel(
                      key: ValueKey(selected.id),
                      instanceId: selected.id,
                      onDeleted: () => _load(silent: true),
                      // 系统状态监控卡(对齐 V1 面板:状态/操作/配置之后附监控)
                      footer: const [SystemMonitorCard()],
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

  Widget _emptyView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.dns_outlined, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '还没有实例',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '点击右上角「选择实例」→「新建实例」开始',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}