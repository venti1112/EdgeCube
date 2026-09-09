import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';

/// 内网穿透隧道列表页:隧道卡片(名称/服务器地址/代理数)+ 启停开关 + 删除。
///
/// frpc 进程全局唯一(同时最多运行一条隧道),运行状态经 GET /frp/status
/// 每 3 秒轮询;运行中的隧道在卡片上显示运行徽标。点击卡片进入详情页。
class FrpTunnelListPage extends ConsumerStatefulWidget {
  const FrpTunnelListPage({super.key});

  @override
  ConsumerState<FrpTunnelListPage> createState() => _FrpTunnelListPageState();
}

class _FrpTunnelListPageState extends ConsumerState<FrpTunnelListPage> {
  static const _pollInterval = Duration(seconds: 3);

  Timer? _timer;
  List<TunnelInfo>? _tunnels;
  FrpStatus? _status;
  bool _loading = true;
  String? _error;

  /// 正在启停的隧道 id(防连点,对应开关转圈)。
  String? _busyId;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final api = client.getFrpApi();
      final tunnels =
          (await api.listFrpTunnels()).data ?? BuiltList<TunnelInfo>();
      final status = (await api.getFrpStatus()).data;
      if (!mounted) return;
      setState(() {
        _tunnels = tunnels.toList();
        _status = status;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _start(TunnelInfo tunnel) async {
    final client = _client;
    if (client == null || _busyId != null) return;
    setState(() => _busyId = tunnel.id);
    try {
      await client.getFrpApi().startFrpc(
            startFrpcRequest:
                StartFrpcRequest((b) => b..tunnelId = tunnel.id),
          );
      if (!mounted) return;
      _snack('「${tunnel.name}」已启动');
      _load();
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _stop(TunnelInfo tunnel) async {
    final client = _client;
    if (client == null || _busyId != null) return;
    setState(() => _busyId = tunnel.id);
    try {
      await client.getFrpApi().stopFrpc();
      if (!mounted) return;
      _snack('「${tunnel.name}」已停止');
      _load();
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(TunnelInfo tunnel) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除隧道'),
        content: Text('确定删除隧道「${tunnel.name}」吗?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await client.getFrpApi().deleteFrpTunnel(tunnelId: tunnel.id);
      _load();
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  bool _isRunning(TunnelInfo tunnel) =>
      _status?.running == true && _status!.tunnelId == tunnel.id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('内网穿透'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/manage/frp/create');
          // 创建页返回后刷新列表
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('新建隧道'),
      ),
      body: _loading && _tunnels == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _tunnels == null
                  ? _errorView()
                  : _list(_tunnels!),
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
        Center(child: Text('加载失败:$_error')),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _list(List<TunnelInfo> tunnels) {
    final cs = Theme.of(context).colorScheme;
    if (tunnels.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.hub_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '还没有隧道',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '点击右下角「新建隧道」填写 frps 服务端与代理规则',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (final tunnel in tunnels) ...[
          _TunnelCard(
            tunnel: tunnel,
            running: _isRunning(tunnel),
            busy: _busyId == tunnel.id,
            onTap: () async {
              await context.push('/manage/frp/${tunnel.id}');
              _load();
            },
            onToggle: (on) => on ? _start(tunnel) : _stop(tunnel),
            onDelete: () => _delete(tunnel),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TunnelCard extends StatelessWidget {
  const _TunnelCard({
    required this.tunnel,
    required this.running,
    required this.busy,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final TunnelInfo tunnel;
  final bool running;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (running ? cs.primaryContainer : cs.secondaryContainer)
                      .withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Icon(
                  running ? Icons.cloud_done_outlined : Icons.hub_outlined,
                  size: 22,
                  color: running ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tunnel.name,
                            style: const TextStyle(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (running) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.circle, size: 8, color: Colors.green),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tunnel.serverAddr}:${tunnel.serverPort} · '
                      '${tunnel.proxies.length} 个代理',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
                Switch(value: running, onChanged: onToggle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
