import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';

/// 隧道详情页:配置卡(基本信息 + 代理规则)+ 启停/编辑/删除 + 日志区。
///
/// 隧道运行时每 1 秒轮询 /frp/status 与 /frp/logs 并自动滚底;
/// 停止后保留最后一次日志(进入页面时加载一次)。frpc 进程全局唯一,
/// 若 frpc 正运行其他隧道,本页操作会收到对应 409 提示。
class FrpTunnelDetailPage extends ConsumerStatefulWidget {
  const FrpTunnelDetailPage({super.key, required this.tunnelId});

  final String tunnelId;

  @override
  ConsumerState<FrpTunnelDetailPage> createState() =>
      _FrpTunnelDetailPageState();
}

class _FrpTunnelDetailPageState extends ConsumerState<FrpTunnelDetailPage> {
  static const _pollInterval = Duration(seconds: 1);

  Timer? _timer;
  TunnelInfo? _tunnel;
  FrpStatus? _status;
  List<String> _logs = [];
  bool _loading = true;
  String? _error;
  String? _busy;
  final _logScroll = ScrollController();

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _running =>
      _status?.running == true && _status!.tunnelId == widget.tunnelId;

  /// 首次加载:隧道详情 + 状态 + 一次日志(展示上次运行输出)。
  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final api = client.getFrpApi();
      final tunnel =
          (await api.getFrpTunnel(tunnelId: widget.tunnelId)).data;
      final status = (await api.getFrpStatus()).data;
      if (!mounted || tunnel == null) return;
      setState(() {
        _tunnel = tunnel;
        _status = status;
        _error = null;
        _loading = false;
      });
      await _loadLogs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  /// 运行中轮询:状态 + 日志(仅当有任何隧道运行时拉日志,避免无效请求)。
  Future<void> _poll() async {
    final client = _client;
    if (client == null) return;
    try {
      final api = client.getFrpApi();
      final status = (await api.getFrpStatus()).data;
      if (!mounted) return;
      setState(() => _status = status);
      if (status?.running == true) await _loadLogs();
    } catch (_) {
      // 轮询失败静默,下次重试
    }
  }

  Future<void> _loadLogs() async {
    final client = _client;
    if (client == null) return;
    try {
      final logs = (await client.getFrpApi().getFrpLogs(tail: 500)).data;
      if (!mounted || logs == null) return;
      final next = logs.toList();
      final changed =
          _logs.length != next.length ||
          (_logs.isNotEmpty && _logs.last != next.last);
      if (!changed) return;
      setState(() => _logs = next);
      if (_running && _logScroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      // 日志拉取失败静默
    }
  }

  Future<void> _start() async {
    final client = _client;
    if (client == null || _busy != null) return;
    setState(() => _busy = 'start');
    try {
      await client.getFrpApi().startFrpc(
            startFrpcRequest:
                StartFrpcRequest((b) => b..tunnelId = widget.tunnelId),
          );
      if (!mounted) return;
      _snack('已启动');
      _load();
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _stop() async {
    final client = _client;
    if (client == null || _busy != null) return;
    setState(() => _busy = 'stop');
    try {
      await client.getFrpApi().stopFrpc();
      if (!mounted) return;
      _snack('已停止');
      _load();
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete() async {
    final client = _client;
    if (client == null) return;
    final tunnel = _tunnel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除隧道'),
        content: Text('确定删除隧道「${tunnel?.name}」吗?'),
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
      await client.getFrpApi().deleteFrpTunnel(tunnelId: widget.tunnelId);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tunnel = _tunnel;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(tunnel?.name ?? '隧道详情'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: tunnel == null || _running
                ? null
                : () async {
                    await context.push('/manage/frp/${widget.tunnelId}/edit');
                    _load();
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: tunnel == null
                ? null
                : () async {
                    await _delete();
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading && tunnel == null
          ? const Center(child: CircularProgressIndicator())
          : tunnel == null
              ? _errorView()
              : _body(tunnel),
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
        Center(
          child: TextButton(
            onPressed: () {
              context.pop(true);
            },
            child: const Text('返回'),
          ),
        ),
      ],
    );
  }

  Widget _body(TunnelInfo tunnel) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 运行状态卡
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _running
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 32,
                  color: _running ? Colors.green : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _running ? '运行中' : '已停止',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _status?.startedAt != null
                            ? '启动于 ${_fmtTime(_status!.startedAt!)}'
                            : (_status?.exitCode != null
                                ? '上次退出码 ${_status!.exitCode}'
                                : 'frpc 当前未运行'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_busy != null)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _running ? _stop : _start,
                    icon: Icon(
                      _running ? Icons.stop_outlined : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(_running ? '停止' : '启动'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 服务器信息
        _sectionCard('服务器', Icons.dns_outlined, [
          _kv('服务器地址', tunnel.serverAddr),
          _kv('服务器端口', '${tunnel.serverPort}'),
          if (tunnel.user != null && tunnel.user!.isNotEmpty)
            _kv('用户名', tunnel.user!),
          if (tunnel.authToken != null && tunnel.authToken!.isNotEmpty)
            _kv('鉴权 Token', '••••••••'),
        ]),
        const SizedBox(height: 12),
        // 代理规则
        _sectionCard('代理规则(${tunnel.proxies.length})',
            Icons.account_tree_outlined, [
          for (final p in tunnel.proxies) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.name} · ${p.type.name.toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _proxyDesc(p),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        // 日志
        _sectionTitle('日志', Icons.terminal_outlined),
        const SizedBox(height: 8),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _logScroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: _logs.length,
                  itemBuilder: (context, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title, icon),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  static String _proxyDesc(TunnelProxy p) {
    final base = '${p.localIp}:${p.localPort}';
    final portType = p.type == ProxyType.tcp || p.type == ProxyType.udp;
    if (portType) {
      return '本地 $base → 远程 ${p.remotePort}';
    }
    return '本地 $base → 域名 ${(p.customDomains ?? BuiltList<String>()).join(', ')}';
  }

  static String _fmtTime(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
