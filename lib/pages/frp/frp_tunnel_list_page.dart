import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/network_store.dart';
import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import 'frp_provider_picker_page.dart';
import 'frp_run_page.dart';

/// 「映射隧道」主页：已保存隧道列表，可运行/停止/删除，入口新增隧道。
///
/// 从 MSL 开服器的 FrpcList 移植。所有供应商的隧道统一运行在上游原版
/// frpc（运行时包）上，frpc 进程全局唯一。
class FrpTunnelListPage extends StatefulWidget {
  const FrpTunnelListPage({super.key});

  @override
  State<FrpTunnelListPage> createState() => _FrpTunnelListPageState();
}

class _FrpTunnelListPageState extends State<FrpTunnelListPage> {
  /// 默认映射隧道 localId（FRP 开关打开时随服务端启停），用于「默认」角标。
  String? _defaultTunnelId;

  @override
  void initState() {
    super.initState();
    _loadDefaultTunnelId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FrpScope.of(context).init();
    });
  }

  Future<void> _loadDefaultTunnelId() async {
    final id = await NetworkStore.loadDefaultFrpTunnelId();
    if (mounted) setState(() => _defaultTunnelId = id);
  }

  Future<void> _addTunnel() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FrpProviderPickerPage()),
    );
    if (mounted) FrpScope.of(context).reload();
  }

  Future<void> _deleteTunnel(SavedFrpTunnel tunnel) async {
    final trans = LocaleScope.of(context).translations;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trans.get('frp.deleteTitle')),
        content: Text(trans.get('frp.deleteMessage', {'name': tunnel.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(trans.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(trans.get('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await FrpScope.of(context).removeTunnel(tunnel.localId);
      // 删除默认隧道时 removeTunnel 已清除设置，重载以同步角标。
      _loadDefaultTunnelId();
    }
  }

  Future<void> _openRunPage(SavedFrpTunnel tunnel) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FrpRunPage(tunnel: tunnel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frp = FrpScope.of(context);
    final tunnels = frp.tunnels;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('frp.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('frp.addTunnel'),
            onPressed: _addTunnel,
          ),
        ],
      ),
      body: SafeArea(
        child: tunnels.isEmpty
            ? _buildEmpty(theme)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (frp.occupiedByAutoTunnel) ...[
                    _buildOccupiedHint(theme),
                    const SizedBox(height: 12),
                  ],
                  for (final tunnel in tunnels) ...[
                    _TunnelCard(
                      tunnel: tunnel,
                      running: frp.runningLocalId == tunnel.localId ||
                          frp.autoRunningLocalId == tunnel.localId,
                      connected: (frp.isConnected &&
                              frp.runningLocalId == tunnel.localId) ||
                          (frp.autoConnected &&
                              frp.autoRunningLocalId == tunnel.localId),
                      starting: frp.startingLocalId == tunnel.localId,
                      isDefault: _defaultTunnelId == tunnel.localId,
                      onTap: () => _openRunPage(tunnel),
                      onDelete: () => _deleteTunnel(tunnel),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('frp.emptyList'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _addTunnel,
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.tr('frp.addTunnel')),
          ),
        ],
      ),
    );
  }

  /// 服务端自动隧道占用 frpc 进程时的提示条。
  Widget _buildOccupiedHint(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('frp.occupiedByAuto'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条隧道卡片。
class _TunnelCard extends StatelessWidget {
  const _TunnelCard({
    required this.tunnel,
    required this.running,
    required this.connected,
    required this.starting,
    required this.isDefault,
    required this.onTap,
    required this.onDelete,
  });

  final SavedFrpTunnel tunnel;
  final bool running;
  final bool connected;
  final bool starting;

  /// 是否为默认映射隧道（FRP 开关打开时随服务端启停）。
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerName = tunnel.provider == FrpProvider.custom
        ? context.tr('frp.provider.custom')
        : tunnel.provider.displayName;
    final address = tunnel.displayAddress;
    return Card(
      child: ListTile(
        leading: Icon(
          connected
              ? Icons.cloud_done_outlined
              : (running || starting
                  ? Icons.cloud_sync_outlined
                  : Icons.cloud_outlined),
          size: 32,
          color: connected
              ? theme.colorScheme.primary
              : (running || starting
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                tunnel.name,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.tr('frp.defaultBadge'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$providerName · ${tunnel.type.toUpperCase()}'),
            if (address.isNotEmpty)
              Text(address, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (address.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: context.tr('frp.copyAddress'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('frp.addressCopied')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: context.tr('common.delete'),
              onPressed: onDelete,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
      ),
    );
  }
}
