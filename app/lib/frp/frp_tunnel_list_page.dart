import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 「映射隧道」页：本地已保存的隧道列表（每条都是一个可独立运行的 FRP 实例）。
///
/// 排版：右上角新增、卡片上复制地址 / 删除 / chevron，点卡片进运行页。
///
/// 这几处形态都是上面那层模型变化的直接结果：
///
/// * **没有「默认」角标**：每条隧道都是独立的实例，
///   游戏实例要连带启动哪条，在**实例设置**里选。
/// * **没有「被自动隧道占用」的提示条**：不存在「全局一个 frpc 被谁占着」。
/// * 卡片状态直接读 `frp.run.list`（一条隧道一个进程），不需要 join
///   「哪个实例在跑它」。
class FrpTunnelListPage extends ConsumerWidget {
  const FrpTunnelListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tunnels = ref.watch(frpTunnelsProvider);
    final providers =
        ref.watch(frpProvidersProvider).value ?? const <FrpProvider>[];
    // 运行态：查不到的隧道 = 没跑过（界面按「未运行」画）
    final runs = ref.watch(frpRunsProvider).value ?? const <String, FrpRun>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('映射隧道'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '添加隧道',
            onPressed: () => context.push('/manage/network/tunnels/picker'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: tunnels.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: describeFrpError(error),
          onRetry: () => ref.invalidate(frpTunnelsProvider),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(
                onAdd: () => context.push('/manage/network/tunnels/picker'),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(frpTunnelsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final tunnel in list) ...[
                      _TunnelCard(
                        tunnel: tunnel,
                        providerName: _providerName(providers, tunnel),
                        run: runs[tunnel.localId],
                        onTap: () => context.push(
                          '/manage/network/tunnels/run/${tunnel.localId}',
                        ),
                        onDelete: () => _delete(context, ref, tunnel),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  /// 卡片副标题里的平台名：自定义用固定文案，其余取平台清单里的展示名
  /// （清单还没到手时退回 key，至少不是空白）。
  static String _providerName(List<FrpProvider> providers, FrpSavedTunnel tunnel) {
    if (tunnel.isCustom) return '自定义 FRP';
    return findFrpProvider(providers, tunnel.provider)?.displayName ??
        tunnel.provider;
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FrpSavedTunnel tunnel,
  ) async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    final confirmed = await confirmDialog(
      context,
      title: '删除隧道',
      message: '确定从列表中删除隧道「${tunnel.name}」吗？（不会删除平台上的隧道）',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await api.removeTunnel(tunnel.localId);
    } on DaemonException catch (error) {
      if (context.mounted) {
        await showErrorDialog(context, describeFrpError(error));
      }
      return;
    }
    ref.invalidate(frpTunnelsProvider);
    // 记录可能还在（那条隧道可能正跑着）—— 一并刷新，别留一张对不上的卡
    ref.invalidate(frpRunsProvider);
    if (context.mounted) showSnack(context, '已删除「${tunnel.name}」');
  }
}

/// 单条隧道卡片。
///
/// 卡片左边那个图标就是它的运行态：跑着 = 实心勾、起不来 = 断云、
/// 没跑 = 空心云。状态来自 daemon 的 `frp.run.list`，页面订阅了 `frp.run`
/// 事件，所以在别处（运行页 / 游戏实例连带启动）起停这里也会跟着变。
class _TunnelCard extends StatelessWidget {
  const _TunnelCard({
    required this.tunnel,
    required this.providerName,
    required this.run,
    required this.onTap,
    required this.onDelete,
  });

  final FrpSavedTunnel tunnel;
  final String providerName;

  /// 这条隧道的运行态；`null` = 从来没起过。
  final FrpRun? run;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address = tunnel.displayAddress;
    final current = run;
    final (icon, iconColor) = switch (current) {
      FrpRun(isRunning: true) => (Icons.cloud_done_outlined, scheme.primary),
      FrpRun(hasProblem: true) => (Icons.cloud_off_outlined, scheme.error),
      _ => (Icons.cloud_outlined, scheme.onSurfaceVariant),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, size: 32, color: iconColor),
        title: Text(tunnel.name, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$providerName · ${tunnel.type.toUpperCase()}'),
            // 只在「有过动静但不是正常跑着」时多给一行：跑着的时候左边那个
            // 实心云已经说清楚了，没跑过也没必要写「未运行」占一行。
            if (current != null && !current.isRunning)
              Text(
                current.label,
                style: TextStyle(
                  color: current.hasProblem
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            if (address.isNotEmpty)
              Text(
                address,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (address.isNotEmpty)
              IconButton(
                tooltip: '复制连接地址',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  showSnack(context, '连接地址已复制');
                },
                icon: const Icon(Icons.copy, size: 18),
              ),
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '还没有隧道，点击下方按钮添加',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加隧道'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
