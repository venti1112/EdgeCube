import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 单条隧道的运行页：启停开关 + 公网地址复制 + 实时 frpc 日志。
///
/// 排版：
///
/// * `Card` 里 平台·协议 + 状态标签 + `SwitchListTile` + 一地址行
/// * 日志区 280 高、monospace、右上角「清空」
/// * 日志**每 1s 重取一次快照**（见下文）
///
/// 「运行」的单位是一条隧道配置（= 一个 FRP 实例），与游戏实例没有从属关系。
/// 所以这里没有「默认隧道」「随服务器启停」那套概念 —— 起停就是起停，跟哪个
/// 游戏实例在用它是两件事（游戏实例可以「连带启动」它，但那是游戏实例那边的
/// 一个引用，见 `InstanceConfig::frp_tunnel_id`）。
class FrpRunPage extends ConsumerStatefulWidget {
  const FrpRunPage({super.key, required this.localId});

  final String localId;

  @override
  ConsumerState<FrpRunPage> createState() => _FrpRunPageState();
}

class _FrpRunPageState extends ConsumerState<FrpRunPage> {
  final _logScroll = ScrollController();

  /// 运行中时轮询日志的定时器。
  ///
  /// 为什么不推事件：daemon 只在**状态变化**时推 `frp.run`（起了 / 退了 / 起不来），
  /// 日志行不推 —— 那是每行一条消息，对一个调试用的看板太重了。200 行的小快照
  /// 每秒重取一次，代价可以忽略。
  Timer? _poll;

  bool _busy = false;

  @override
  void dispose() {
    _poll?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  /// 按「现在跑没跑」开关轮询（幂等，`build` 里可以放心调）。
  void _syncPolling(bool running) {
    if (running) {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) ref.invalidate(frpRunProvider(widget.localId));
      });
    } else if (_poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  /// 启动 / 停止。切完让 daemon 推的事件去刷新界面（不用本地猜状态）。
  Future<void> _toggle(bool start) async {
    final api = ref.read(frpApiProvider);
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (start) {
        await api.startRun(widget.localId);
      } else {
        await api.stopRun(widget.localId);
      }
    } catch (error) {
      if (mounted) {
        await showErrorDialog(context, describeFrpError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(frpRunProvider(widget.localId));
      ref.invalidate(frpRunsProvider);
    }
  }

  Future<void> _clearLog() async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    try {
      await api.clearRunLog(widget.localId);
    } on DaemonException {
      // 清日志失败没什么好打断用户的（下一次轮询就回到真值）
    }
    ref.invalidate(frpRunProvider(widget.localId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final tunnels = ref.watch(frpTunnelsProvider).value ?? const <FrpSavedTunnel>[];
    final providers = ref.watch(frpProvidersProvider).value ?? const <FrpProvider>[];
    final runAsync = ref.watch(frpRunProvider(widget.localId));
    final run = runAsync.value;
    final running = run?.isRunning ?? false;
    _syncPolling(running);

    FrpSavedTunnel? tunnel;
    for (final item in tunnels) {
      if (item.localId == widget.localId) {
        tunnel = item;
        break;
      }
    }
    // 隧道可能已经被删了，但记录还在 —— 标题退回日志里那个名字
    final title = tunnel?.name ??
        (run?.tunnelName.isNotEmpty == true ? run!.tunnelName : '映射隧道');
    final providerName = _providerName(tunnel, providers);
    final address = tunnel?.displayAddress ?? '';

    final statusText = run?.label;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            key: const Key('frp_run_config'),
            tooltip: '查看 frpc 配置',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push(
              '/manage/network/tunnels/config/${widget.localId}',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_outlined, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          providerName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      if (statusText != null) _StatusChip(run: run!),
                    ],
                  ),
                ),
                SwitchListTile(
                  key: const Key('frp_run_switch'),
                  title: const Text('启动隧道'),
                  subtitle: const Text('用 frpc 跑这条隧道，与游戏实例无关'),
                  value: running || _busy,
                  onChanged: _busy ? null : _toggle,
                ),
                if (address.isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.link),
                    title: Text(address, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: '复制连接地址',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: address));
                        showSnack(context, '连接地址已复制');
                      },
                    ),
                  ),
                // 起不来 / 异常退出：原因就写在卡片上，别让用户去翻日志
                if (run?.message case final message?
                    when run!.hasProblem || !running) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      message,
                      key: const Key('frp_run_message'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: run.hasProblem
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '隧道日志',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '清空日志',
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                onPressed: _clearLog,
              ),
            ],
          ),
          Container(
            height: 280,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildLog(run?.log ?? const [], scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildLog(List<String> lines, ColorScheme scheme) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无日志',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      key: const Key('frp_run_log'),
      controller: _logScroll,
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (_, index) => Text(
        lines[index],
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }

  static String _providerName(
    FrpSavedTunnel? tunnel,
    List<FrpProvider> providers,
  ) {
    if (tunnel == null) return '隧道已不在列表里';
    if (tunnel.isCustom) return '自定义 FRP';
    final provider = findFrpProvider(providers, tunnel.provider);
    return '${provider?.displayName ?? tunnel.provider} · ${tunnel.type.toUpperCase()}';
  }
}

/// 状态小标签（圆角 chip）。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.run});

  final FrpRun run;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (run.state) {
      'running' => scheme.primary,
      'failed' => scheme.error,
      _ when run.hasProblem => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        run.label,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}
