import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_provider_service.dart';
import '../../frp/frp_registry_store.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/loading_dialog.dart';
import '../../widgets/miuix_dialog.dart';
import '../../widgets/ec_preference.dart';
import '../../widgets/ec_text_field.dart';
import '../../widgets/miuix_snackbar.dart';
import 'frp_provider_login_page.dart';

/// 供应商隧道管理页：Tab1「我的隧道」（选择保存到本地）+ Tab2「创建隧道」。
class FrpProviderTunnelsPage extends StatefulWidget {
  const FrpProviderTunnelsPage({
    super.key,
    required this.provider,
    required this.token,
    required this.account,
  });

  final FrpProvider provider;
  final String token;
  final FrpAccount account;

  @override
  State<FrpProviderTunnelsPage> createState() => _FrpProviderTunnelsPageState();
}

class _FrpProviderTunnelsPageState extends State<FrpProviderTunnelsPage> {
  /// 当前标签页下标。Miuix 无 TabBarView 对应物，改用 EcTabbedView
  /// （MiuixTabRow + PageView）承载，选中项由本页持有。
  int _tabIndex = 0;

  List<FrpRemoteTunnel>? _tunnels;
  List<FrpNode>? _nodes;
  bool _loadingTunnels = false;
  bool _loadingNodes = false;

  // —— 创建表单 ——
  final _nameField = TextEditingController(
    text: 'EdgeCube_${1000 + Random().nextInt(9000)}',
  );
  final _localIpField = TextEditingController(text: '127.0.0.1');
  final _localPortField = TextEditingController(text: '25565');
  final _remotePortField = TextEditingController();
  String _type = 'tcp';
  FrpNode? _selectedNode;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _refreshTunnels();
    _refreshNodes();
  }

  @override
  void dispose() {
    _nameField.dispose();
    _localIpField.dispose();
    _localPortField.dispose();
    _remotePortField.dispose();
    super.dispose();
  }

  /// token 失效（FrpApiException）：清除凭据，弹窗提示并替换为登录页。
  Future<void> _handleTokenInvalid() async {
    await FrpProviderService.logout(widget.provider);
    if (!mounted) return;
    await showErrorDialog(context, context.tr('frp.tokenExpired'));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FrpProviderLoginPage(provider: widget.provider),
      ),
    );
  }

  Future<void> _refreshTunnels() async {
    setState(() => _loadingTunnels = true);
    try {
      final list = await FrpProviderService.tunnelList(
        widget.provider,
        widget.token,
      );
      if (mounted) setState(() => _tunnels = list);
    } on FrpApiException catch (_) {
      if (mounted) _handleTokenInvalid();
    } catch (e) {
      if (mounted) showErrorDialog(context, '$e');
    } finally {
      if (mounted) setState(() => _loadingTunnels = false);
    }
  }

  Future<void> _refreshNodes() async {
    setState(() => _loadingNodes = true);
    try {
      final list = await FrpProviderService.nodeList(
        widget.provider,
        widget.token,
      );
      if (mounted) {
        setState(() {
          _nodes = list;
          _selectedNode ??= list.where((n) => n.online).firstOrNull;
          _randomizeRemotePort();
        });
      }
    } on FrpApiException catch (_) {
      if (mounted) _handleTokenInvalid();
    } catch (e) {
      if (mounted) showErrorDialog(context, '$e');
    } finally {
      if (mounted) setState(() => _loadingNodes = false);
    }
  }

  /// 在所选节点端口范围内随机一个远程端口。
  void _randomizeRemotePort() {
    final node = _selectedNode;
    final min = node?.minPort ?? 10000;
    final max = node?.maxPort ?? 60000;
    if (max > min) {
      _remotePortField.text = '${min + Random().nextInt(max - min)}';
    }
  }

  /// 把远端隧道保存到本地注册表并返回隧道列表页。
  Future<void> _saveTunnel(FrpRemoteTunnel tunnel) async {
    final node = _nodes?.where((n) => n.id == tunnel.nodeId).firstOrNull;
    final saved = SavedFrpTunnel(
      localId: await FrpRegistryStore.newLocalId(),
      provider: widget.provider,
      name: tunnel.name,
      remoteTunnelId: tunnel.id,
      nodeId: tunnel.nodeId,
      nodeName: tunnel.nodeName.isNotEmpty
          ? tunnel.nodeName
          : (node?.name ?? tunnel.nodeId),
      type: tunnel.type,
      localIp: tunnel.localIp,
      localPort: tunnel.localPort,
      remotePort: tunnel.remotePort,
      remoteAddress: tunnel.remoteAddress.isNotEmpty
          ? tunnel.remoteAddress
          : (node != null &&
                    node.hostname.isNotEmpty &&
                    tunnel.remotePort != null
                ? '${node.hostname}:${tunnel.remotePort}'
                : ''),
    );
    if (!mounted) return;
    await FrpScope.of(context).saveTunnel(saved);
    if (!mounted) return;
    showMiuixSnackbar(context.tr('frp.tunnelSaved'));
    // 返回隧道列表页（弹出本页与供应商选择页）。
    final navigator = Navigator.of(context);
    navigator.pop();
    if (navigator.canPop()) navigator.pop();
  }

  /// 删除远端隧道。
  Future<void> _deleteRemote(FrpRemoteTunnel tunnel) async {
    final trans = LocaleScope.of(context).translations;
    final confirmed = await showMiuixConfirm(
      context,
      title: trans.get('frp.deleteRemoteTitle'),
      message: trans.get('frp.deleteRemoteMessage', {'name': tunnel.name}),
      cancelLabel: trans.get('common.cancel'),
      confirmLabel: trans.get('common.confirm'),
    );
    if (confirmed != true || !mounted) return;
    try {
      await runWithLoadingDialog(
        context,
        trans.get('frp.deletingTunnel'),
        () => FrpProviderService.deleteTunnel(
          widget.provider,
          widget.token,
          tunnel.id,
        ),
      );
      await _refreshTunnels();
    } catch (e) {
      if (mounted) showErrorDialog(context, '$e');
    }
  }

  Future<void> _createTunnel() async {
    final node = _selectedNode;
    if (node == null) return;
    final name = _nameField.text.trim();
    final localPort = int.tryParse(_localPortField.text.trim());
    final remotePort = int.tryParse(_remotePortField.text.trim());
    if (name.isEmpty || localPort == null || remotePort == null) {
      showErrorDialog(context, context.tr('frp.createInvalid'));
      return;
    }
    setState(() => _creating = true);
    try {
      await FrpProviderService.createTunnel(
        widget.provider,
        widget.token,
        node: node,
        name: name,
        type: _type,
        localIp: _localIpField.text.trim(),
        localPort: localPort,
        remotePort: remotePort,
      );
      if (!mounted) return;
      showMiuixSnackbar(context.tr('frp.tunnelCreated'));
      setState(() => _tabIndex = 0);
      await _refreshTunnels();
    } catch (e) {
      if (mounted) showErrorDialog(context, '$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _logout() async {
    await FrpProviderService.logout(widget.provider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: widget.provider.displayName,

        actions: [
          MiuixIconButton(
            onPressed: _logout,
            child: const MiuixIcon(icon: Icons.logout),
          ),
        ],
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            _buildAccountBar(theme),
            Expanded(
              child: EcTabbedView(
                index: _tabIndex,
                onTabChanged: (i) => setState(() => _tabIndex = i),
                tabs: [
                  context.tr('frp.myTunnels'),
                  context.tr('frp.createTunnel'),
                ],
                children: [_buildTunnelsTab(theme), _buildCreateTab(theme)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountBar(MiuixThemeData theme) {
    final account = widget.account;
    final quota = (account.usedTunnels != null && account.maxTunnels != null)
        ? ' · ${account.usedTunnels}/${account.maxTunnels}'
        : '';
    return Container(
      width: double.infinity,
      color: theme.colors.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${account.username}'
        '${account.group.isNotEmpty ? ' (${account.group})' : ''}$quota',
        style: theme.textStyles.footnote1,
      ),
    );
  }

  Widget _buildTunnelsTab(MiuixThemeData theme) {
    final tunnels = _tunnels;
    if (_loadingTunnels && tunnels == null) {
      return const Center(child: MiuixInfiniteProgressIndicator());
    }
    if (tunnels == null || tunnels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('frp.noRemoteTunnels'),
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(height: 12),
            MiuixButton(
              onPressed: _refreshTunnels,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiuixIcon(icon: Icons.refresh, size: 18),
                  const SizedBox(width: 8),
                  MiuixText(context.tr('common.refresh')),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // isRefreshing 受控，复用已有的 _loadingTunnels。
    return MiuixPullToRefresh(
      isRefreshing: _loadingTunnels,
      onRefresh: _refreshTunnels,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final tunnel in tunnels) ...[
            MiuixCard(
              insideMargin: EdgeInsets.zero,
              child: MiuixBasicComponent(
                startAction: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: MiuixIcon(
                    icon: tunnel.online
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    tint: tunnel.online
                        ? theme.colors.primary
                        : theme.colors.onSurfaceVariantSummary,
                  ),
                ),
                title: tunnel.name,
                summary:
                    '${tunnel.type.toUpperCase()} · '
                    '${tunnel.localIp}:${tunnel.localPort} → '
                    '${tunnel.displayAddress}',
                endActions: [
                  MiuixIconButton(
                    onPressed: () => _deleteRemote(tunnel),
                    child: MiuixIcon(icon: Icons.delete_outline, size: 20),
                  ),
                  MiuixButton(
                    onPressed: () => _saveTunnel(tunnel),
                    child: MiuixText(context.tr('frp.useTunnel')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateTab(MiuixThemeData theme) {
    final nodes = _nodes;
    if (_loadingNodes && nodes == null) {
      return const Center(child: MiuixInfiniteProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Builder(
          builder: (context) {
            final list = nodes ?? <FrpNode>[];
            return MiuixOverlayDropdownPreference(
              title: context.tr('frp.node'),
              items: [
                for (final node in list)
                  '${node.name}'
                      '${node.vip ? ' [VIP]' : ''}'
                      '${node.online ? '' : ' (${context.tr('frp.nodeOffline')})'}',
              ],
              selectedIndex: _selectedNode == null
                  ? 0
                  : list.indexOf(_selectedNode!).clamp(0, list.length),
              enabled: list.isNotEmpty,
              onSelectedIndexChange: (i) => setState(() {
                _selectedNode = list[i];
                _randomizeRemotePort();
              }),
            );
          },
        ),
        if (_selectedNode?.description.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            _selectedNode!.description,
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        EcTextField(
          controller: _nameField,
          label: context.tr('frp.tunnelName'),
        ),
        const SizedBox(height: 12),
        MiuixOverlayDropdownPreference(
          title: context.tr('frp.protocol'),
          items: const ['TCP', 'UDP'],
          selectedIndex: _type == 'udp' ? 1 : 0,
          onSelectedIndexChange: (i) =>
              setState(() => _type = i == 1 ? 'udp' : 'tcp'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: EcTextField(
                controller: _localIpField,
                label: context.tr('frp.localIp'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EcTextField(
                controller: _localPortField,
                label: context.tr('frp.localPort'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: EcTextField(
                controller: _remotePortField,
                label: context.tr('frp.remotePort'),
                helperText: _selectedNode?.minPort != null
                    ? '${_selectedNode!.minPort} - ${_selectedNode!.maxPort}'
                    : null,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            MiuixIconButton(
              onPressed: () => setState(_randomizeRemotePort),
              child: MiuixIcon(icon: Icons.casino_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: MiuixButton(
            onPressed: _creating || _selectedNode == null
                ? null
                : _createTunnel,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _creating
                    ? const MiuixInfiniteProgressIndicator(size: 18)
                    : const MiuixIcon(icon: Icons.add, size: 18),
                const SizedBox(width: 8),
                MiuixText(context.tr('frp.createTunnel')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
