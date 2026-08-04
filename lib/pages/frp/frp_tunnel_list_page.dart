import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../../config/network_store.dart';
import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/ec_preference.dart';
import '../../widgets/miuix_dialog.dart';
import '../../widgets/miuix_snackbar.dart';
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FrpProviderPickerPage()));
    if (mounted) FrpScope.of(context).reload();
  }

  Future<void> _deleteTunnel(SavedFrpTunnel tunnel) async {
    final trans = LocaleScope.of(context).translations;
    final confirmed = await showMiuixConfirm(
      context,
      title: trans.get('frp.deleteTitle'),
      message: trans.get('frp.deleteMessage', {'name': tunnel.name}),
      cancelLabel: trans.get('common.cancel'),
      confirmLabel: trans.get('common.confirm'),
    );
    if (confirmed == true && mounted) {
      await FrpScope.of(context).removeTunnel(tunnel.localId);
      // 删除默认隧道时 removeTunnel 已清除设置，重载以同步角标。
      _loadDefaultTunnelId();
    }
  }

  Future<void> _openRunPage(SavedFrpTunnel tunnel) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FrpRunPage(tunnel: tunnel)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final frp = FrpScope.of(context);
    final tunnels = frp.tunnels;
    return MiuixScaffold(
      topBar: MiuixSmallTopAppBar(
        title: context.tr('frp.title'),
        navigationIcon: const EcBackButton(),
        actions: [
          MiuixIconButton(
            onPressed: _addTunnel,
            child: MiuixIcon(icon: Icons.add),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: SafeArea(
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
                        running:
                            frp.runningLocalId == tunnel.localId ||
                            frp.autoRunningLocalId == tunnel.localId,
                        connected:
                            (frp.isConnected &&
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
      ),
    );
  }

  Widget _buildEmpty(MiuixThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 56, color: theme.colors.outline),
          const SizedBox(height: 12),
          Text(
            context.tr('frp.emptyList'),
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 16),
          MiuixButton(
            onPressed: _addTunnel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixIcon(icon: Icons.add, size: 18),
                const SizedBox(width: 8),
                MiuixText(context.tr('frp.addTunnel')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 服务端自动隧道占用 frpc 进程时的提示条。
  Widget _buildOccupiedHint(MiuixThemeData theme) {
    return Padding(
      padding: EdgeInsets.zero,
      child: MiuixCard(
        insideMargin: const EdgeInsets.all(12),
        colors: MiuixCardColors(
          color: theme.colors.surfaceContainerHighest,
          contentColor: MiuixTheme.of(context).colors.onSurface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: theme.colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('frp.occupiedByAuto'),
                style: theme.textStyles.footnote1,
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
    final theme = MiuixTheme.of(context);
    final providerName = tunnel.provider == FrpProvider.custom
        ? context.tr('frp.provider.custom')
        : tunnel.provider.displayName;
    final address = tunnel.displayAddress;
    return MiuixCard(
      insideMargin: EdgeInsets.zero,
      child: MiuixBasicComponent(
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        startAction: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: MiuixIcon(
            icon: connected
                ? Icons.cloud_done_outlined
                : (running || starting
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_outlined),
            size: 32,
            tint: connected
                ? theme.colors.primary
                : (running || starting
                      ? theme.colors.onTertiaryContainer
                      : theme.colors.onSurfaceVariantSummary),
          ),
        ),
        // MiuixBasicComponent 的 title 只接受字符串，而这里标题行需要带一个
        // 「默认」徽标，故改用 content 槽自绘整块文本区。
        content: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: MiuixText(
                      tunnel.name,
                      style: theme.textStyles.body1,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (isDefault) ...[
                    const SizedBox(width: 6),
                    EcStatusChip(context.tr('frp.defaultBadge')),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              MiuixText(
                '$providerName · ${tunnel.type.toUpperCase()}',
                style: theme.textStyles.footnote1,
                color: theme.colors.onSurfaceVariantSummary,
              ),
              if (address.isNotEmpty)
                MiuixText(
                  address,
                  style: theme.textStyles.footnote1,
                  color: theme.colors.onSurfaceVariantSummary,
                ),
            ],
          ),
        ],
        endActions: [
          if (address.isNotEmpty)
            MiuixIconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: address));
                showMiuixSnackbar(context.tr('frp.addressCopied'));
              },
              child: const MiuixIcon(icon: Icons.copy, size: 18),
            ),
          MiuixIconButton(
            onPressed: onDelete,
            child: const MiuixIcon(icon: Icons.delete_outline, size: 20),
          ),
          const MiuixIcon(icon: Icons.chevron_right),
        ],
        onClick: onTap,
      ),
    );
  }
}
