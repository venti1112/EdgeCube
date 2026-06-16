import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tunnel/tunnel_service.dart';

/// 端口映射页：通过 frp（frpc 客户端）把本机的 Minecraft 服务端映射到公网。
///
/// 配置持久化到 shared_preferences，启动后表单只读（改动需停止后重设；仅代理类
/// 配置可在运行中「热重载」）。日志与状态实时来自原生侧 [TunnelService]。
class PortMappingPage extends StatefulWidget {
  const PortMappingPage({super.key});

  @override
  State<PortMappingPage> createState() => _PortMappingPageState();
}

class _PortMappingPageState extends State<PortMappingPage> {
  static const _prefsKey = 'frpc_config';

  final _tunnel = TunnelService();

  // —— 表单控制器 ——
  final _serverAddr = TextEditingController();
  final _serverPort = TextEditingController(text: '7000');
  final _token = TextEditingController();
  final _proxyName = TextEditingController(text: 'minecraft');
  final _localPort = TextEditingController(text: '25565');
  final _remotePort = TextEditingController(text: '25565');
  final _adminPort = TextEditingController(text: '7400');
  final _adminUser = TextEditingController(text: 'admin');
  final _adminPassword = TextEditingController();
  String _proxyType = 'tcp';

  // —— 运行状态 ——
  /// null 表示已停止；否则为 preparing / starting / running。
  String? _status;
  final List<String> _logs = [];
  StreamSubscription<TunnelEvent>? _sub;
  final _logScroll = ScrollController();

  bool get _running => _status != null;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _logScroll.dispose();
    for (final c in [
      _serverAddr,
      _serverPort,
      _token,
      _proxyName,
      _localPort,
      _remotePort,
      _adminPort,
      _adminUser,
      _adminPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // —— 配置持久化 ——

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
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
        _localPort.text = '${m['localPort'] ?? 25565}';
        _remotePort.text = '${m['remotePort'] ?? 25565}';
        _adminPort.text = '${m['adminPort'] ?? 7400}';
        _adminUser.text = m['adminUser'] as String? ?? 'admin';
        _adminPassword.text = m['adminPassword'] as String? ?? '';
      });
    } catch (_) {
      // 损坏的配置忽略，使用默认值。
    }
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_buildConfig().toJsonMap()));
  }

  /// 从表单构造配置；端口非法时回退到默认值。
  FrpcConfig _buildConfig() {
    int port(TextEditingController c, int fallback) =>
        int.tryParse(c.text.trim()) ?? fallback;
    return FrpcConfig(
      serverAddr: _serverAddr.text.trim(),
      serverPort: port(_serverPort, 7000),
      authToken: _token.text.trim().isEmpty ? null : _token.text.trim(),
      proxyName: _proxyName.text.trim().isEmpty ? 'minecraft' : _proxyName.text.trim(),
      proxyType: _proxyType,
      localPort: port(_localPort, 25565),
      remotePort: port(_remotePort, 25565),
      adminPort: port(_adminPort, 7400),
      adminUser: _adminUser.text.trim().isEmpty ? null : _adminUser.text.trim(),
      adminPassword: _adminPassword.text.isEmpty ? null : _adminPassword.text,
    );
  }

  // —— 事件订阅 ——

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
        setState(() => _status = e.status);
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

  // —— 操作 ——

  Future<void> _start() async {
    if (_serverAddr.text.trim().isEmpty) {
      _toast('请填写服务器地址');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _saveConfig();
      await _tunnel.startWithConfig(_buildConfig(), name: _proxyName.text.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('启动失败：$e')));
    }
  }

  Future<void> _stop() async {
    await _tunnel.stop();
  }

  Future<void> _reload() async {
    final messenger = ScaffoldMessenger.of(context);
    final cfg = _buildConfig();
    try {
      // 先用最新表单覆盖配置文件，再触发 frpc 重新读取。
      await _tunnel.writeConfig(cfg);
      await _saveConfig();
      final ok = await _tunnel.reload(
        port: cfg.adminPort,
        user: cfg.adminUser,
        password: cfg.adminPassword,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '已请求热重载' : '热重载失败，请查看日志')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('热重载失败：$e')));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // —— UI ——

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('端口映射'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清空日志',
            onPressed: () {
              _tunnel.clearLog();
              setState(() => _logs.clear());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusCard(theme),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _sectionTitle(theme, '服务器'),
                  _field(_serverAddr, 'frps 服务器地址', hint: '例如 frp.example.com'),
                  Row(
                    children: [
                      Expanded(child: _field(_serverPort, 'frps 端口', number: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_token, 'Token（可选）')),
                    ],
                  ),
                  _sectionTitle(theme, '代理'),
                  _field(_proxyName, '代理名称'),
                  Row(
                    children: [
                      Expanded(child: _typeDropdown()),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_localPort, '本地端口', number: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_remotePort, '远程端口', number: true)),
                    ],
                  ),
                  _sectionTitle(theme, '热重载 Admin（可选）'),
                  Row(
                    children: [
                      Expanded(child: _field(_adminPort, '端口', number: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_adminUser, '用户名')),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_adminPassword, '密码', obscure: true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _actions(theme),
                  const SizedBox(height: 16),
                  _sectionTitle(theme, '日志'),
                  _logView(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(ThemeData theme) {
    final (icon, color, text) = switch (_status) {
      'running' => (Icons.cloud_done, theme.colorScheme.primary, '运行中'),
      'starting' => (Icons.cloud_sync, theme.colorScheme.tertiary, '连接中…'),
      'preparing' => (Icons.downloading, theme.colorScheme.tertiary, '准备运行时…'),
      _ => (Icons.cloud_off, theme.colorScheme.onSurfaceVariant, '已停止'),
    };
    final addr = _serverAddr.text.trim();
    final remote = _remotePort.text.trim();
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.titleMedium),
                  if (_status == 'running' && addr.isNotEmpty)
                    Text('公网入口：$addr:$remote',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(ThemeData theme) {
    if (!_running) {
      return FilledButton.icon(
        icon: const Icon(Icons.play_arrow),
        label: const Text('启动'),
        onPressed: _start,
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('热重载'),
            onPressed: _status == 'running' ? _reload : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
            onPressed: _stop,
          ),
        ),
      ],
    );
  }

  Widget _logView(ThemeData theme) {
    return Container(
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
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool number = false,
    bool obscure = false,
  }) {
    return TextField(
      controller: c,
      enabled: !_running, // 运行中锁定表单
      obscureText: obscure,
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
      onChanged: _running ? null : (v) => setState(() => _proxyType = v ?? 'tcp'),
    );
  }
}
