import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_provider_service.dart';
import '../../frp/frp_registry_store.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/loading_dialog.dart';
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

class _FrpProviderTunnelsPageState extends State<FrpProviderTunnelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

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
    _tabs.dispose();
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
      final list =
          await FrpProviderService.tunnelList(widget.provider, widget.token);
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
      final list =
          await FrpProviderService.nodeList(widget.provider, widget.token);
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
          : (node != null && node.hostname.isNotEmpty &&
                  tunnel.remotePort != null
              ? '${node.hostname}:${tunnel.remotePort}'
              : ''),
    );
    if (!mounted) return;
    await FrpScope.of(context).saveTunnel(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('frp.tunnelSaved')),
        duration: const Duration(seconds: 2),
      ),
    );
    // 返回隧道列表页（弹出本页与供应商选择页）。
    final navigator = Navigator.of(context);
    navigator.pop();
    if (navigator.canPop()) navigator.pop();
  }

  /// 删除远端隧道。
  Future<void> _deleteRemote(FrpRemoteTunnel tunnel) async {
    final trans = LocaleScope.of(context).translations;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trans.get('frp.deleteRemoteTitle')),
        content: Text(trans.get('frp.deleteRemoteMessage', {'name': tunnel.name})),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('frp.tunnelCreated')),
          duration: const Duration(seconds: 2),
        ),
      );
      _tabs.animateTo(0);
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.provider.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: context.tr('frp.logout'),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('frp.myTunnels')),
            Tab(text: context.tr('frp.createTunnel')),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildAccountBar(theme),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildTunnelsTab(theme),
                  _buildCreateTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountBar(ThemeData theme) {
    final account = widget.account;
    final quota = (account.usedTunnels != null && account.maxTunnels != null)
        ? ' · ${account.usedTunnels}/${account.maxTunnels}'
        : '';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${account.username}'
        '${account.group.isNotEmpty ? ' (${account.group})' : ''}$quota',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Widget _buildTunnelsTab(ThemeData theme) {
    final tunnels = _tunnels;
    if (_loadingTunnels && tunnels == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tunnels == null || tunnels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('frp.noRemoteTunnels'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _refreshTunnels,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(context.tr('common.refresh')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshTunnels,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final tunnel in tunnels) ...[
            Card(
              child: ListTile(
                leading: Icon(
                  tunnel.online ? Icons.cloud_done_outlined : Icons.cloud_outlined,
                  color: tunnel.online
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(tunnel.name),
                subtitle: Text(
                  '${tunnel.type.toUpperCase()} · '
                  '${tunnel.localIp}:${tunnel.localPort} → '
                  '${tunnel.displayAddress}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: context.tr('common.delete'),
                      onPressed: () => _deleteRemote(tunnel),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _saveTunnel(tunnel),
                      child: Text(context.tr('frp.useTunnel')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateTab(ThemeData theme) {
    final nodes = _nodes;
    if (_loadingNodes && nodes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<FrpNode>(
          isExpanded: true,
          initialValue: _selectedNode,
          decoration: InputDecoration(
            labelText: context.tr('frp.node'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final node in nodes ?? <FrpNode>[])
              DropdownMenuItem(
                value: node,
                child: Text(
                  '${node.name}'
                  '${node.vip ? ' [VIP]' : ''}'
                  '${node.online ? '' : ' (${context.tr('frp.nodeOffline')})'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _selectedNode = v;
            _randomizeRemotePort();
          }),
        ),
        if (_selectedNode?.description.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            _selectedNode!.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _nameField,
          decoration: InputDecoration(
            labelText: context.tr('frp.tunnelName'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: InputDecoration(
            labelText: context.tr('frp.protocol'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'tcp', child: Text('TCP')),
            DropdownMenuItem(value: 'udp', child: Text('UDP')),
          ],
          onChanged: (v) => setState(() => _type = v ?? 'tcp'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _localIpField,
                decoration: InputDecoration(
                  labelText: context.tr('frp.localIp'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _localPortField,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.tr('frp.localPort'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _remotePortField,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.tr('frp.remotePort'),
                  helperText: _selectedNode?.minPort != null
                      ? '${_selectedNode!.minPort} - ${_selectedNode!.maxPort}'
                      : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.casino_outlined),
              tooltip: context.tr('frp.randomPort'),
              onPressed: () => setState(_randomizeRemotePort),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _creating || _selectedNode == null ? null : _createTunnel,
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(context.tr('frp.createTunnel')),
          ),
        ),
      ],
    );
  }
}
