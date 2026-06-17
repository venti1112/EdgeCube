import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../server/server_scope.dart';
import '../tunnel/tunnel_service.dart';

/// 网络映射页：UPnP 自动端口映射 + FRP 隧道，均随服务器自动启停。
///
/// 所有配置持久化到 SharedPreferences。
class PortMappingPage extends StatefulWidget {
  const PortMappingPage({super.key});

  @override
  State<PortMappingPage> createState() => _PortMappingPageState();
}

class _PortMappingPageState extends State<PortMappingPage> {
  static const _frpcPrefsKey = 'frpc_config';

  final _tunnel = TunnelService();

  // —— UPnP / FRP 开关状态 ——
  bool _upnpEnabled = false;
  bool _tunnelEnabled = false;

  // —— FRP 表单控制器 ——
  final _serverAddr = TextEditingController();
  final _serverPort = TextEditingController(text: '7000');
  final _token = TextEditingController();
  final _proxyName = TextEditingController(text: 'minecraft');
  final _remotePort = TextEditingController(text: '25565');
  String _proxyType = 'tcp';

  // —— 隧道运行状态 ——
  String? _tunnelStatus;
  final List<String> _logs = [];
  final _logScroll = ScrollController();
  StreamSubscription<TunnelEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _logScroll.dispose();
    for (final c in [_serverAddr, _serverPort, _token, _proxyName, _remotePort]) {
      c.dispose();
    }
    super.dispose();
  }

  // —— 加载 ——

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _upnpEnabled = prefs.getBool('upnp_enabled') ?? false;
      _tunnelEnabled = prefs.getBool('tunnel_enabled') ?? false;
    });
    // 加载 FRP 配置。
    final raw = prefs.getString(_frpcPrefsKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _serverAddr.text = m['serverAddr'] as String? ?? '';
        _serverPort.text = '${m['serverPort'] ?? 7000}';
        _token.text = m['authToken'] as String? ?? '';
        _proxyName.text = m['proxyName'] as String? ?? 'minecraft';
        _proxyType = m['proxyType'] as String? ?? 'tcp';
        _remotePort.text = '${m['remotePort'] ?? 25565}';
      });
    } catch (_) {
      // 损坏的配置忽略。
    }
  }

  // —— 保存 + 即时生效 ——

  /// 从表单构造 FrpcConfig（localPort 为占位值，实际运行时由 ServerController 注入）。
  FrpcConfig _buildFrpcConfig() {
    int port(TextEditingController c, int fallback) =>
        int.tryParse(c.text.trim()) ?? fallback;
    return FrpcConfig(
      serverAddr: _serverAddr.text.trim(),
      serverPort: port(_serverPort, 7000),
      authToken: _token.text.trim().isEmpty ? null : _token.text.trim(),
      proxyName: _proxyName.text.trim().isEmpty ? 'minecraft' : _proxyName.text.trim(),
      proxyType: _proxyType,
      localPort: 25565,
      remotePort: port(_remotePort, 25565),
    );
  }

  Future<void> _setUpnp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('upnp_enabled', value);
    if (!mounted) return;
    setState(() => _upnpEnabled = value);
    final server = ServerScope.of(context);
    if (value) {
      server.enableUpnpNow();
    } else {
      server.disableUpnpNow();
    }
  }

  Future<void> _setTunnel(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tunnel_enabled', value);
    if (!mounted) return;
    setState(() => _tunnelEnabled = value);
    final server = ServerScope.of(context);
    if (value) {
      server.enableTunnelNow(_buildFrpcConfig());
    } else {
      server.disableTunnelNow();
    }
  }

  Future<void> _saveFrpcConfig() async {
    // 持久化到 SharedPreferences。
    final config = _buildFrpcConfig();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_frpcPrefsKey, jsonEncode(config.toJsonMap()));
    if (!mounted) return;
    // 若隧道正在运行，即时重启以应用新配置。
    final server = ServerScope.of(context);
    if (server.isRunning) {
      server.applyTunnelConfig(config);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 2)),
    );
  }

  // —— 隧道状态订阅 ——

  void _subscribe() {
    _sub = _tunnel.events().listen((e) {
      if (!mounted) return;
      if (e is TunnelLogEvent) {
        setState(() {
          _logs.add(e.line);
          if (_logs.length > 2000) _logs.removeRange(0, _logs.length - 2000);
        });
        _scrollLogToBottom();
      } else if (e is TunnelStateEvent) {
        setState(() => _tunnelStatus = e.status);
      }
    });
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  // —— UI ——

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络映射'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildUpnpCard(theme),
            const SizedBox(height: 16),
            _buildFrpcCard(theme),
            if (_tunnelStatus != null) ...[
              const SizedBox(height: 16),
              _buildLogSection(theme),
            ],
          ],
        ),
      ),
    );
  }

  // —— UPnP 卡片 ——

  Widget _buildUpnpCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.router_outlined, size: 20,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('路由器端口映射',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary)),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('启用自动端口映射'),
              subtitle: const Text(
                '服务器启动后自动在路由器上开放端口\n需路由器支持 UPnP / NAT-PMP / NAT-PCP 协议',
              ),
              value: _upnpEnabled,
              onChanged: _setUpnp,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ],
        ),
      ),
    );
  }

  // —— FRP 卡片 ——

  Widget _buildFrpcCard(ThemeData theme) {
    final statusText = switch (_tunnelStatus) {
      'running' => '隧道运行中',
      'starting' => '隧道连接中…',
      'preparing' => '隧道准备中…',
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, size: 20,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('FRP 隧道',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary)),
                  ),
                  if (statusText != null)
                    _statusChip(theme, statusText),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('启用 FRP 隧道'),
              subtitle: const Text(
                '通过 frps 服务器将本地服务映射到公网\n服务器启动时自动连接，停止时自动断开',
              ),
              value: _tunnelEnabled,
              onChanged: _setTunnel,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (_tunnelEnabled) ...[
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('frps 服务器',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary)),
              ),
              _px(_field(_serverAddr, '服务器地址', hint: '例如 frp.example.com')),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _field(_serverPort, '端口', number: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_token, 'Token（可选）')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('代理',
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _typeDropdown()),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_proxyName, '代理名称')),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_remotePort, '远程端口', number: true)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '本地端口自动使用当前服务器的 server-port',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _saveFrpcConfig,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('保存配置'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(ThemeData theme, String text) {
    final color = _tunnelStatus == 'running'
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: theme.textTheme.labelSmall?.copyWith(color: color)),
    );
  }

  // —— 工具 ——

  Widget _buildLogSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('隧道日志',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                tooltip: '清空日志',
                onPressed: () {
                  _tunnel.clearLog();
                  setState(() => _logs.clear());
                },
              ),
            ],
          ),
        ),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: _logs.isEmpty
              ? Center(
                  child: Text('暂无日志',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                )
              : ListView.builder(
                  controller: _logScroll,
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, height: 1.3),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _px(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child);

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool number = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters:
          number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _typeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _proxyType,
      decoration: const InputDecoration(
        labelText: '类型',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'tcp', child: Text('TCP')),
        DropdownMenuItem(value: 'udp', child: Text('UDP')),
      ],
      onChanged: (v) => setState(() => _proxyType = v ?? 'tcp'),
    );
  }
}
