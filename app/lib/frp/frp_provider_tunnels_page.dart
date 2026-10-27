import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 平台隧道管理页：Tab1「我的隧道」（挑一条存到本地）+ Tab2「创建隧道」。
///
/// 平台侧的一切（列表 / 节点 / 创建 / 删除）都由 daemon 去说（`frp.remote.*`），
/// 本页只发表单；保存进本地列表也是 daemon 落盘（`frp.tunnels.save`）。
/// 令牌失效有专门一条通路：daemon 回 `frp_unauthorized` / `frp_not_logged_in`
/// 时清掉本地令牌、提示「登录已失效，请重新登录」并替换成登录页。
class FrpProviderTunnelsPage extends ConsumerStatefulWidget {
  const FrpProviderTunnelsPage({super.key, required this.providerKey});

  final String providerKey;

  @override
  ConsumerState<FrpProviderTunnelsPage> createState() =>
      _FrpProviderTunnelsPageState();
}

class _FrpProviderTunnelsPageState extends ConsumerState<FrpProviderTunnelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  FrpAccount? _account;
  List<FrpRemoteTunnel>? _tunnels;
  List<FrpNode>? _nodes;
  bool _loadingTunnels = false;
  bool _loadingNodes = false;
  bool _creating = false;
  bool _handlingInvalid = false;

  // —— 创建表单 ——
  final _nameField = TextEditingController(
    text: 'EdgeCube_${1000 + Random().nextInt(9000)}',
  );
  final _localIpField = TextEditingController(text: '127.0.0.1');
  final _localPortField = TextEditingController(text: '25565');
  final _remotePortField = TextEditingController();
  String _type = 'tcp';
  FrpNode? _selectedNode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccount());
    unawaited(_refreshTunnels());
    unawaited(_refreshNodes());
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

  Future<void> _loadAccount() async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    try {
      final status = await api.account(widget.providerKey);
      if (mounted) setState(() => _account = status.account);
    } on DaemonException {
      // 账号条只是装饰，读不到就不显示
    }
  }

  /// 令牌失效（daemon 说这个令牌不好使了）：清凭据 → 提示 → 回登录页。
  ///
  /// 三个并发加载会撞上同一个错，只处理第一次，免得叠出两个对话框。
  Future<void> _handleTokenInvalid() async {
    if (_handlingInvalid) return;
    _handlingInvalid = true;
    final api = ref.read(frpApiProvider);
    try {
      await api?.logout(widget.providerKey);
    } on DaemonException {
      // 清凭据失败也无所谓，反正本地已经不算登录了
    }
    if (!mounted) return;
    await showErrorDialog(context, '登录已失效，请重新登录');
    if (!mounted) return;
    context.pushReplacement(
      '/manage/network/tunnels/login/${widget.providerKey}',
    );
  }

  Future<void> _refreshTunnels() async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    setState(() => _loadingTunnels = true);
    try {
      final list = await api.remoteTunnels(widget.providerKey);
      if (mounted) setState(() => _tunnels = list);
    } on DaemonException catch (error) {
      if (!mounted) return;
      if (isFrpTokenInvalid(error)) {
        await _handleTokenInvalid();
        return;
      }
      await showErrorDialog(context, describeFrpError(error));
    } finally {
      if (mounted) setState(() => _loadingTunnels = false);
    }
  }

  Future<void> _refreshNodes() async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    setState(() => _loadingNodes = true);
    try {
      final list = await api.remoteNodes(widget.providerKey);
      if (!mounted) return;
      setState(() {
        _nodes = list;
        _selectedNode ??= _firstOnline(list);
        _randomizeRemotePort();
      });
    } on DaemonException catch (error) {
      if (!mounted) return;
      if (isFrpTokenInvalid(error)) {
        await _handleTokenInvalid();
        return;
      }
      await showErrorDialog(context, describeFrpError(error));
    } finally {
      if (mounted) setState(() => _loadingNodes = false);
    }
  }

  static FrpNode? _firstOnline(List<FrpNode> nodes) {
    for (final node in nodes) {
      if (node.online) return node;
    }
    return null;
  }

  FrpNode? _nodeById(String id) {
    for (final node in _nodes ?? const <FrpNode>[]) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// 在所选节点端口范围内随机一个远程端口。
  void _randomizeRemotePort() {
    final min = _selectedNode?.minPort ?? 10000;
    final max = _selectedNode?.maxPort ?? 60000;
    if (max > min) {
      _remotePortField.text = '${min + Random().nextInt(max - min)}';
    }
  }

  /// 把平台侧隧道存进本地列表，然后退回隧道列表页（本页与平台选择页一起弹掉）。
  Future<void> _saveTunnel(FrpRemoteTunnel tunnel) async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    final node = _nodeById(tunnel.nodeId);
    final nodeName = tunnel.nodeName.isNotEmpty
        ? tunnel.nodeName
        : (node?.name ?? tunnel.nodeId);
    final remoteAddress = tunnel.remoteAddress.isNotEmpty
        ? tunnel.remoteAddress
        : ((node != null && node.hostname.isNotEmpty && tunnel.remotePort != null)
              ? '${node.hostname}:${tunnel.remotePort}'
              : '');
    try {
      await api.saveTunnel(
        FrpTunnelInput.remote(
          provider: widget.providerKey,
          name: tunnel.name,
          remoteTunnelId: tunnel.id,
          nodeId: tunnel.nodeId,
          nodeName: nodeName,
          type: tunnel.type,
          localIp: tunnel.localIp,
          localPort: tunnel.localPort,
          remotePort: tunnel.remotePort,
          remoteAddress: remoteAddress,
        ),
      );
    } on DaemonException catch (error) {
      if (!mounted) return;
      if (isFrpTokenInvalid(error)) {
        await _handleTokenInvalid();
        return;
      }
      await showErrorDialog(context, describeFrpError(error));
      return;
    }
    ref.invalidate(frpTunnelsProvider);
    if (!mounted) return;
    showSnack(context, '隧道已保存到列表');
    context.pop();
    if (context.canPop()) context.pop();
  }

  /// 删除平台上的隧道。
  Future<void> _deleteRemote(FrpRemoteTunnel tunnel) async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    final confirmed = await confirmDialog(
      context,
      title: '删除远端隧道',
      message: '确定在平台上删除隧道「${tunnel.name}」吗？此操作不可恢复。',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final (_, error) = await runWithLoading(
      context,
      '正在删除隧道…',
      () => api.deleteRemoteTunnel(widget.providerKey, tunnel.id),
    );
    if (!mounted) return;
    if (error != null) {
      if (isFrpTokenInvalid(error)) {
        await _handleTokenInvalid();
        return;
      }
      await showErrorDialog(context, describeFrpError(error));
      return;
    }
    await _refreshTunnels();
  }

  Future<void> _createTunnel() async {
    final api = ref.read(frpApiProvider);
    final node = _selectedNode;
    if (api == null || node == null) return;
    setState(() => _creating = true);
    try {
      // 端口空着就发 null，由 daemon 统一回「请完整填写隧道名称与端口」
      await api.createRemoteTunnel(
        provider: widget.providerKey,
        nodeId: node.id,
        name: _nameField.text.trim(),
        type: _type,
        localIp: _localIpField.text.trim(),
        localPort: int.tryParse(_localPortField.text.trim()),
        remotePort: int.tryParse(_remotePortField.text.trim()),
      );
    } on DaemonException catch (error) {
      if (!mounted) return;
      if (isFrpTokenInvalid(error)) {
        await _handleTokenInvalid();
        return;
      }
      await showErrorDialog(context, describeFrpError(error));
      return;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    if (!mounted) return;
    showSnack(context, '隧道创建成功');
    _tabs.animateTo(0);
    await _refreshTunnels();
  }

  Future<void> _logout() async {
    final api = ref.read(frpApiProvider);
    try {
      await api?.logout(widget.providerKey);
    } on DaemonException {
      // 断线时清不掉也无所谓
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = _account;
    final provider = findFrpProvider(
      ref.watch(frpProvidersProvider).value ?? const [],
      widget.providerKey,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(provider?.displayName ?? widget.providerKey),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: () => unawaited(_logout()),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              account?.displayText ?? '…',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: '我的隧道'), Tab(text: '创建隧道')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildTunnelsTab(theme), _buildCreateTab(theme)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunnelsTab(ThemeData theme) {
    final tunnels = _tunnels;
    if (tunnels == null && _loadingTunnels) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tunnels == null || tunnels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '该账号下暂无隧道',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => unawaited(_refreshTunnels()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
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
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  tunnel.online
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_outlined,
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
                      tooltip: '删除',
                      onPressed: () => unawaited(_deleteRemote(tunnel)),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                    FilledButton(
                      onPressed: () => unawaited(_saveTunnel(tunnel)),
                      child: const Text('使用'),
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
    if (nodes == null && _loadingNodes) {
      return const Center(child: CircularProgressIndicator());
    }
    final list = nodes ?? const <FrpNode>[];
    final selected = _selectedNode;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          // FormField 的初值只在挂载时读一次，选择变了靠换 key 重建
          key: ValueKey('frp_node_${selected?.id}'),
          initialValue: selected?.id,
          decoration: const InputDecoration(
            labelText: '节点',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final node in list)
              DropdownMenuItem(value: node.id, child: Text(node.label)),
          ],
          onChanged: list.isEmpty
              ? null
              : (id) => setState(() {
                  _selectedNode = id == null ? null : _nodeById(id);
                  _randomizeRemotePort();
                }),
        ),
        if (selected != null && selected.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            selected.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('frp_create_name'),
          controller: _nameField,
          enabled: !_creating,
          decoration: const InputDecoration(
            labelText: '隧道名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(
            labelText: '协议',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'tcp', child: Text('TCP')),
            DropdownMenuItem(value: 'udp', child: Text('UDP')),
          ],
          onChanged: _creating
              ? null
              : (value) => setState(() => _type = value ?? 'tcp'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _localIpField,
                enabled: !_creating,
                decoration: const InputDecoration(
                  labelText: '本地地址',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _localPortField,
                enabled: !_creating,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '本地端口',
                  border: OutlineInputBorder(),
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
                enabled: !_creating,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '远程端口',
                  helperText: selected?.minPort != null
                      ? '${selected!.minPort} - ${selected.maxPort}'
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: '随机端口',
              onPressed: () => setState(_randomizeRemotePort),
              icon: const Icon(Icons.casino_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _creating || selected == null
              ? null
              : () => unawaited(_createTunnel()),
          icon: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add, size: 18),
          label: const Text('创建隧道'),
        ),
      ],
    );
  }
}
