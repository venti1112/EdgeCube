import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';
import '../frp/providers.dart';
import '../instance/api.dart';
import '../instance/eula.dart';
import '../instance/instance_list_sheet.dart';
import '../instance/instance_settings_dialog.dart';
import '../instance/models.dart';
import '../instance/providers.dart';
import '../monitor/models.dart';
import '../monitor/providers.dart';
import '../runtime/models.dart' show RuntimeEnv, runtimeEnvTitle;
import '../runtime/providers.dart'
    show runtimeCatalogProvider, runtimeListProvider;

/// 「服务器」页：选中实例的控制面板。
///
/// **排版**：卡片集合 / 顺序 / 间距 / 每张卡里放什么都固定如下，
/// 组件一律用 `material_ui`，不引入 miuix。
///
/// 页面结构：
///
/// - 顶栏：`AppBar(title: '服务器', actions: [_InstanceSelectorButton])`
/// - 未选中实例 → `_EmptyState`
/// - 主体：`ListView(padding: 16)`，四块依次 16 间距：
///   - `_StatusCard`（图标 + 名称 + 状态 + 运行环境 / 启动命令 + 设置）
///   - `_Actions`（启动/停止、重启/强制停止、提示行）
///   - `_ConnectionCard`（标题 + 未运行占位）
///   - `_MonitorCard`（系统状态：设备内存 + CPU，见下）
///
/// 两处刻意的取舍，都因为对应的后端能力还没落地：
///
/// 1. **系统状态卡不显示「服务端内存」**：那一行要读服务端
///    进程的 VmRSS，属于进程模块。设备内存与 CPU 两行保留，数据来自 daemon
///    的 `monitor` 模块（拉 `monitor.snapshot` + 订阅 `monitor.stats`）。
/// 2. **启动 / 停止 / 重启 / 强制停止全部置灰**，并在提示行的位置说明原因 ——
///    和「新建实例」页把未实现的方式摆出来置灰是同一个做法。
///
/// 顶栏**没有**「刷新」「新建实例」两个图标按钮：新建入口在实例
/// 列表弹窗底部已经有了，刷新改由下拉刷新承担（V2 的数据在守护进程那边，
/// 需要用户能手动拉一下）。
///
/// 状态卡底部另有一个 `warnings` 提醒块：daemon 的 `instance.status.warnings`
/// （目录丢了、入口文件不在……）在这一页没有别的落点。
class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 订阅 instance.* 事件：别的客户端建/删/改实例时，本端列表自动刷新
    ref.watch(instanceEventsProvider);

    final list = ref.watch(instanceListProvider).value;
    final detail = ref.watch(selectedInstanceDetailProvider).value;

    // 用列表里的 `selected` 而不是 detail 判空：detail 是两次 WS 调用，
    // 首次加载时它必然为 null，拿它判空会让面板闪一下空态。
    // `selected` 指向一个已经不在列表里的 id（别的客户端刚把它删了）时不进面板，
    // 否则会停在一张只有「—」的卡片上。
    final selectedId = list?.selected;
    final summary = _summaryOf(list, selectedId);
    final hasSelection = summary != null || detail != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务器'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // 操作图标放在末尾（miuix 文档），所以选择器在右上角。
        actions: const [_InstanceSelectorButton(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(instanceListProvider);
          ref.invalidate(selectedInstanceDetailProvider);
        },
        child: !hasSelection
            ? _EmptyState(
                connected: ref.watch(isConnectedProvider),
                hasInstances: (list?.instances.isNotEmpty) ?? false,
              )
            : _ServerControlPanel(
                // `ValueKey(selected.id)`：换实例时整棵子树重建，
                // 面板里将来加了实例专属状态也不用自己清。
                key: ValueKey(selectedId),
                summary: summary,
                detail: detail,
              ),
      ),
    );
  }

  static InstanceSummary? _summaryOf(InstanceList? list, String? id) {
    if (list == null || id == null) return null;
    for (final instance in list.instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }
}

/// 没有选中实例时的空态（图标 72 + 标题 + 说明，整体居中）。
///
/// 连不上守护进程时说明真实原因是「连不上」而不是「没有实例」 ——
/// 后者会让人白找一圈。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.connected, required this.hasInstances});

  final bool connected;
  final bool hasInstances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (String title, String description) = switch ((
      connected,
      hasInstances,
    )) {
      (false, _) => ('未连接到守护进程', '顶部横幅可以看到原因，连上后这里会列出实例。'),
      (true, true) => ('没有选中的实例', '点击右上角的按钮选一个实例。'),
      _ => ('还没有实例', '点击右上角的按钮新建一个服务器实例。'),
    };

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // 空态也要能下拉刷新，所以套一个撑满视口的滚动体
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 72,
                  color: connected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏右上角的「选择实例」按钮：图标 + 当前实例名 + 下拉箭头。
///
/// 名称最大宽度 140，超长省略。
/// 点开是底部的实例列表弹窗，切换 / 删除 / 新建都在里面。
class _InstanceSelectorButton extends ConsumerWidget {
  const _InstanceSelectorButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedName = _selectedName(ref.watch(instanceListProvider).value);

    return TextButton.icon(
      key: const Key('servers_instance_selector'),
      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurface),
      icon: const Icon(Icons.dns),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selectedName ?? '选择实例',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      onPressed: () => InstanceListSheet.show(context),
    );
  }

  /// 当前选中实例的名字（从列表里按 `selected` 找，找不到返回 null）。
  ///
  /// 不走 `selectedInstanceDetailProvider`：那是「元数据 + 状态」的两次请求，
  /// 只为了显示一个名字不值得，而且它加载中时这里会闪一下「选择实例」。
  static String? _selectedName(InstanceList? list) {
    final id = list?.selected;
    if (id == null) return null;
    for (final instance in list!.instances) {
      if (instance.id == id) return instance.name;
    }
    return null;
  }
}

/// 选中实例的控制面板。
///
/// 卡片顺序与间距：状态 → 操作 → 连接信息 → 系统状态，各 16 间距。
class _ServerControlPanel extends StatelessWidget {
  const _ServerControlPanel({super.key, this.summary, this.detail});

  /// 列表里的摘要（详情还没回来时先拿它显示名字）。
  final InstanceSummary? summary;

  /// 元数据 + 状态；首次加载时是 null。
  final InstanceDetail? detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _StatusCard(summary: summary, detail: detail),
        const SizedBox(height: 16),
        _Actions(detail: detail),
        const SizedBox(height: 16),
        _ConnectionCard(detail: detail),
        const SizedBox(height: 16),
        const _MonitorCard(),
      ],
    );
  }
}

/// 状态卡：
/// 状态图标（40）+ 实例名 + 状态文字 + 启动配置两行 + 右侧设置按钮。
///
/// 启动配置那两行：表单模式先给「运行环境：…」，再给
/// 「启动命令：…」（daemon 现拼出来的那条，也是真正会跑的那条）；手动模式
/// 没有运行环境可显示，只留启动命令。
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.summary, required this.detail});

  final InstanceSummary? summary;
  final InstanceDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instance = detail?.instance;
    final phase = detail?.status.phase ?? ServerPhase.stopped;
    final (icon, color) = _phaseVisual(phase, scheme);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instance?.name ?? summary?.name ?? '—',
                    key: const Key('servers_instance_name'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phase.label,
                    key: const Key('servers_phase_label'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                  // 「运行环境：…」这一行表单模式才给，手动模式没有环境可显示
                  if (instance != null) ...[
                    if (!instance.manualCommand) ...[
                      const SizedBox(height: 4),
                      Text(
                        '运行环境：${_runtimeEnvLabel(ref, instance.runtimeEnvId)}',
                        key: const Key('servers_runtime_env'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '启动命令：${instance.launchCommandLabel}',
                      key: const Key('servers_startup_command'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  // 连带启动的映射隧道（选了才有）：是哪一条、它现在跑没跑。
                  // 名字与运行态都来自 FRP 那边 —— 隧道是**独立实例**，
                  // 实例这里只存了一个引用，不该再存一份状态。
                  if (instance?.frpTunnelId case final tunnelId?
                      when tunnelId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '映射隧道：${_frpTunnelLabel(ref, tunnelId)}',
                      key: const Key('servers_frp_status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (detail != null && detail!.status.warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _WarningBox(warnings: detail!.status.warnings),
                  ],
                ],
              ),
            ),
            IconButton(
              key: const Key('servers_edit_instance'),
              tooltip: '实例设置',
              icon: const Icon(Icons.settings_outlined),
              // 详情还没回来时不给点：对话框要拿完整元数据填充
              onPressed: instance == null
                  ? null
                  : () => showInstanceSettingsDialog(context, ref, instance),
            ),
          ],
        ),
      ),
    );
  }

  /// 运行环境 id → 显示名。
  ///
  /// 环境记录可能已经不在了（在「运行环境」页删掉了，或装在别的机器上）——
  /// 那种时候照实说「不在了」，别装成没事：启动会以 `instance_runtime_missing` 失败。
  String _runtimeEnvLabel(WidgetRef ref, String? id) {
    if (id == null || id.isEmpty) return '未选';
    final environments =
        ref.watch(runtimeListProvider).value?.environments ?? const <RuntimeEnv>[];
    final catalog = ref.watch(runtimeCatalogProvider).value;
    for (final env in environments) {
      if (env.id == id) return runtimeEnvTitle(catalog, env);
    }
    return '$id（不在了）';
  }
}

/// 阶段 → (图标, 颜色)：运行中 = 绿、过渡态 = 橙、已停止 = 灰。
/// 一律映射到主题色（V2 跟主题走，不写死 `Colors.green` 之类）。
///
/// daemon 还给了一个 `crashed` 阶段：进程异常退出必须和「用户主动停止」区分开。
(IconData, Color) _phaseVisual(ServerPhase phase, ColorScheme scheme) =>
    switch (phase) {
      ServerPhase.stopped => (Icons.stop_circle_outlined, scheme.outline),
      ServerPhase.preparing => (Icons.hourglass_empty, scheme.tertiary),
      ServerPhase.starting => (Icons.hourglass_top, scheme.tertiary),
      ServerPhase.running => (Icons.play_circle, scheme.primary),
      ServerPhase.stopping => (Icons.hourglass_bottom, scheme.tertiary),
      ServerPhase.crashed => (Icons.error_outline, scheme.error),
    };

/// 操作区：
/// 第一行整宽的主按钮（启动 / 停止），第二行等分的「重启 | 强制停止」，
/// 最后是反馈行。
///
/// 按钮的可用条件：
///
/// | 阶段 | 主按钮 | 重启 | 强制停止 |
/// | --- | --- | --- | --- |
/// | 已停止 / 异常退出 | 启动 | 禁用 | 禁用 |
/// | 准备中 / 启动中 | 禁用（转圈） | 禁用 | **可用**（卡住了要能兜底） |
/// | 运行中 | 停止 | 可用 | 可用 |
/// | 停止中 | 禁用（转圈） | 禁用 | **可用** |
///
/// V2 的 daemon 每个实例一条 PTY，**可以同时跑多个**，不会因为
/// 「别的实例在跑」就把启动拦下来。
class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.detail});

  final InstanceDetail? detail;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  /// 有请求在飞：期间禁掉所有按钮，免得连点两次启动。
  bool _busy = false;

  /// 上一次操作的失败原因（显示在反馈行）。
  String? _error;

  Instance? get _instance => widget.detail?.instance;

  ServerPhase get _phase => widget.detail?.status.phase ?? ServerPhase.stopped;

  Future<void> _run(
    Future<Map<String, dynamic>> Function(InstanceApi api, String id) action,
  ) async {
    final instance = _instance;
    final api = ref.read(instanceApiProvider);
    if (instance == null || api == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(api, instance.id);
      // 阶段变化会由 `instance.phase` 事件推回来（页面已订阅 instance.*），
      // 这里再主动拉一次，省得事件还没到界面先空一拍。
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeInstanceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 启动：先过 EULA，再真的启动。
  ///
  /// **不同意就当没点过启动**（直接 return），
  /// 而不是弹一个错误。
  Future<void> _start() => _run((api, id) async {
    // 不同意：返回一个空结果直接收工（`_run` 的动作要回一份 Map）
    if (!await ensureEulaAgreed(context, api, id)) return const {};
    return api.start(id);
  });

  /// 强制停止会丢未保存的数据，所以要先确认。
  Future<void> _confirmForceStop() async {
    final instance = _instance;
    if (instance == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('强制停止'),
        content: Text('将直接结束「${instance.name}」的进程，可能丢失未保存的数据。确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('强制停止'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run((api, id) => api.kill(id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = _phase;
    final alive = phase != ServerPhase.stopped && phase != ServerPhase.crashed;
    final hasInstance = _instance != null;

    final canStart = hasInstance && !alive && !_busy;
    final canStop = hasInstance && phase == ServerPhase.running && !_busy;
    final canForceStop = hasInstance && alive && !_busy;
    final canRestart = hasInstance && phase == ServerPhase.running && !_busy;

    final primary = switch (phase) {
      ServerPhase.stopped || ServerPhase.crashed => FilledButton.icon(
        key: const Key('servers_start'),
        // **先过 EULA**，不同意就什么都不做。
        // 重启不过这道关卡 —— 重启直接调 `restart`。
        onPressed: canStart ? _start : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('启动'),
      ),
      ServerPhase.running => FilledButton.icon(
        key: const Key('servers_stop'),
        onPressed: canStop ? () => _run((api, id) => api.stop(id)) : null,
        icon: const Icon(Icons.stop),
        label: const Text('停止'),
      ),
      _ => FilledButton.icon(
        key: const Key('servers_busy'),
        onPressed: null,
        icon: const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text(phase.label),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('servers_restart'),
                onPressed: canRestart
                    ? () => _run((api, id) => api.restart(id))
                    : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('重启'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('servers_force_stop'),
                onPressed: canForceStop ? _confirmForceStop : null,
                icon: const Icon(Icons.dangerous_outlined),
                label: const Text('强制停止'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('servers_action_error'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ] else if (!hasInstance) ...[
          const SizedBox(height: 8),
          Text(
            '还没选中实例。',
            key: const Key('servers_action_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 连接信息卡。
///
/// 地址那几块还没做（直连地址少一段「路由器映射到哪」的信息，
/// 映射状态去「网络映射」页看 UPnP 卡）：这里先如实反映进程侧 ——
/// 跑没跑、pid 是多少；未运行时给一句「服务端未运行」占位。
class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.detail});

  final InstanceDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = detail?.status;
    final phase = status?.phase ?? ServerPhase.stopped;
    final alive = phase != ServerPhase.stopped && phase != ServerPhase.crashed;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '连接信息',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alive
                        ? '服务端正在运行（pid ${status?.pid ?? '未知'}）'
                        : '服务端未运行',
                    key: const Key('servers_server_not_running'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: alive ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (alive) ...[
              const SizedBox(height: 8),
              Text(
                '内网地址、端口映射与公网入口要等网络模块 —— 那几块还没搬过来。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 系统状态卡：
/// 标题 + 「设备内存」+「CPU 使用率」两行（图标 + 标签 + 数值 + 进度条）。
///
/// **刻意不放「服务端内存」行**：那一行读的是服务端进程的 VmRSS，
/// 属于进程模块，现在恒为「服务端未运行」，摆着只会误导。
///
/// 数据来自 daemon 的 `monitor` 模块（拉一次 `monitor.snapshot` + 订阅
/// `monitor.stats` 推送，见 `monitor/providers.dart`）。读不到时两行显示「不可用」
/// 并走灰色 —— 不假装有占用。
class _MonitorCard extends ConsumerWidget {
  const _MonitorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final asyncSnapshot = ref.watch(monitorSnapshotProvider);
    final snapshot = asyncSnapshot.value;

    Color colorFor(double percent, bool available) =>
        available ? _percentColor(percent, scheme) : scheme.outline;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统状态', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _MonitorRow(
              icon: Icons.memory,
              label: '设备内存',
              value: snapshot?.memoryLabel ?? '不可用',
              percent: snapshot?.memoryPercent ?? 0,
              color: colorFor(
                snapshot?.memoryPercent ?? 0,
                snapshot?.hasMemory ?? false,
              ),
            ),
            const SizedBox(height: 12),
            _MonitorRow(
              icon: Icons.speed,
              label: 'CPU 使用率',
              value: snapshot?.cpuLabel ?? '不可用',
              percent: snapshot?.cpuPercent ?? 0,
              color: colorFor(
                snapshot?.cpuPercent ?? 0,
                snapshot?.hasCpu ?? false,
              ),
            ),
            if (_noteFor(asyncSnapshot) case final note?) ...[
              const SizedBox(height: 8),
              Text(
                note,
                key: const Key('servers_monitor_note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 只在**真的要说点什么**的时候给一行脚注：
  /// 读失败（还没连上 / 方法不存在）、平台不支持、以及 CPU 还没出读数
  /// （daemon 刚起来，第一份快照里 `cpu_usage` 必然是 null）。
  static String? _noteFor(AsyncValue<SystemSnapshot> async) {
    if (async.hasError) return '读取系统状态失败：${async.error}';
    final snapshot = async.value;
    if (snapshot == null) return null; // 还在加载：两行显示「不可用」即可，不必多话
    if (!snapshot.supported) return '守护进程所在平台不支持读取系统状态。';
    if (!snapshot.hasCpu) return 'CPU 使用率需要连续两次采样，稍后自动出现。';
    return null;
  }
}

/// 占用率 → 颜色：≥85% 危险、≥65% 警告、其余正常。
Color _percentColor(double percent, ColorScheme scheme) {
  if (percent >= 85) return scheme.error;
  if (percent >= 65) return scheme.tertiary;
  return scheme.primary;
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
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
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
        _ProgressBar(percent: percent, color: color),
      ],
    );
  }
}

/// 带平滑过渡的进度条。
///
/// `TweenAnimationBuilder` 会把当前动画值当作新的起点去追新的 `end`，
/// 所以这里 `begin == end` 是故意的：首次渲染不animate，之后每次数值变化才插值。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = (percent.clamp(0.0, 100.0)) / 100.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: fraction, end: fraction),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, value, _) => Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: scheme.surfaceContainerHighest),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: SizedBox.expand(child: ColoredBox(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 元数据/目录有问题时的提醒块（`instance.status.warnings`）。
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

/// 「映射隧道：<名字> · <状态>」里那半句。
///
/// 名字与运行态都从 FRP 那边取（`frp.tunnels.list` / `frp.run.list`）：
/// 游戏实例只存了一个 `frp_tunnel_id` 引用，别的都不在它那儿。查不到就退回 id，
/// 至少让用户知道「连着一条已经不在了的隧道」。
String _frpTunnelLabel(WidgetRef ref, String tunnelId) {
  final tunnels = ref.watch(frpTunnelsProvider).value ?? const [];
  String name = tunnelId;
  for (final tunnel in tunnels) {
    if (tunnel.localId == tunnelId) {
      name = tunnel.name;
      break;
    }
  }
  final run = (ref.watch(frpRunsProvider).value ?? const {})[tunnelId];
  return '$name · ${run?.label ?? '未运行'}';
}
