import 'package:built_collection/built_collection.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';

/// 隧道创建/编辑双用表单页。
///
/// [tunnelId] 为 null 表示创建(POST /frp/tunnels),非 null 表示编辑
/// (先 GET 详情回填,保存时 PUT 全量替换)。基本信息 + 动态代理列表,
/// 按代理类型切换 remotePort(tcp/udp)/customDomains(http/https) 字段。
class FrpTunnelEditPage extends ConsumerStatefulWidget {
  const FrpTunnelEditPage({super.key, this.tunnelId});

  /// null = 创建;非 null = 编辑。
  final String? tunnelId;

  @override
  ConsumerState<FrpTunnelEditPage> createState() => _FrpTunnelEditPageState();
}

/// 单个代理的表单状态。
class _ProxyForm {
  _ProxyForm({
    this.type = ProxyType.tcp,
    String name = '',
    String localIp = '127.0.0.1',
    String localPort = '',
    String remotePort = '',
    String customDomains = '',
  }) {
    this.name.text = name;
    this.localIp.text = localIp;
    this.localPort.text = localPort;
    this.remotePort.text = remotePort;
    this.customDomains.text = customDomains;
  }

  final TextEditingController name = TextEditingController();
  final TextEditingController localIp = TextEditingController();
  final TextEditingController localPort = TextEditingController();
  final TextEditingController remotePort = TextEditingController();
  final TextEditingController customDomains = TextEditingController();
  ProxyType type;

  void dispose() {
    name.dispose();
    localIp.dispose();
    localPort.dispose();
    remotePort.dispose();
    customDomains.dispose();
  }
}

class _FrpTunnelEditPageState extends ConsumerState<FrpTunnelEditPage> {
  final _name = TextEditingController();
  final _serverAddr = TextEditingController();
  final _serverPort = TextEditingController(text: '7000');
  final _user = TextEditingController();
  final _authToken = TextEditingController();
  final List<_ProxyForm> _proxies = [];
  bool _loading = false;
  bool _saving = false;

  bool get _isEdit => widget.tunnelId != null;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      // 新建时给一行默认 TCP 代理
      _proxies.add(_ProxyForm(
        name: 'minecraft',
        localPort: '25565',
        remotePort: '25566',
      ));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _serverAddr.dispose();
    _serverPort.dispose();
    _user.dispose();
    _authToken.dispose();
    for (final p in _proxies) {
      p.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final tunnel = (await client
              .getFrpApi()
              .getFrpTunnel(tunnelId: widget.tunnelId!))
          .data;
      if (!mounted || tunnel == null) return;
      setState(() {
        _name.text = tunnel.name;
        _serverAddr.text = tunnel.serverAddr;
        _serverPort.text = tunnel.serverPort.toString();
        _user.text = tunnel.user ?? '';
        _authToken.text = tunnel.authToken ?? '';
        _proxies.clear();
        for (final p in tunnel.proxies) {
          _proxies.add(_ProxyForm(
            type: p.type,
            name: p.name,
            localIp: p.localIp,
            localPort: p.localPort.toString(),
            remotePort: p.remotePort?.toString() ?? '',
            customDomains: (p.customDomains ?? BuiltList<String>()).join(','),
          ));
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('加载失败:${apiErrorMessage(e)}');
    }
  }

  /// 校验并收集请求体,失败返回 null 并提示。
  TunnelInput? _collect() {
    final name = _name.text.trim();
    final serverAddr = _serverAddr.text.trim();
    final serverPort = int.tryParse(_serverPort.text.trim());
    if (name.isEmpty || serverAddr.isEmpty || serverPort == null ||
        serverPort < 1 || serverPort > 65535) {
      _snack('请填写隧道名称、服务器地址与有效端口(1-65535)');
      return null;
    }
    if (_proxies.isEmpty) {
      _snack('至少需要一个代理');
      return null;
    }
    final proxies = <TunnelProxy>[];
    for (final p in _proxies) {
      final pName = p.name.text.trim();
      final localIp = p.localIp.text.trim();
      final localPort = int.tryParse(p.localPort.text.trim());
      if (pName.isEmpty || localIp.isEmpty ||
          localPort == null || localPort < 1 || localPort > 65535) {
        _snack('代理「${pName.isEmpty ? '(未命名)' : pName}」的本地地址无效');
        return null;
      }
      final isPortType = p.type == ProxyType.tcp || p.type == ProxyType.udp;
      if (isPortType) {
        final remotePort = int.tryParse(p.remotePort.text.trim());
        if (remotePort == null || remotePort < 1 || remotePort > 65535) {
          _snack('代理「$pName」需填写远程端口(1-65535)');
          return null;
        }
        proxies.add(TunnelProxy((b) => b
          ..name = pName
          ..type = p.type
          ..localIp = localIp
          ..localPort = localPort
          ..remotePort = remotePort));
      } else {
        final domains = p.customDomains.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (domains.isEmpty) {
          _snack('代理「$pName」需填写至少一个自定义域名');
          return null;
        }
        proxies.add(TunnelProxy((b) => b
          ..name = pName
          ..type = p.type
          ..localIp = localIp
          ..localPort = localPort
          ..customDomains.replace(domains)));
      }
    }
    return TunnelInput((b) => b
      ..name = name
      ..serverAddr = serverAddr
      ..serverPort = serverPort
      ..user = _user.text.trim().isEmpty ? null : _user.text.trim()
      ..authToken =
          _authToken.text.isEmpty ? null : _authToken.text
      ..proxies.replace(proxies));
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _saving) return;
    final input = _collect();
    if (input == null) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await client
            .getFrpApi()
            .updateFrpTunnel(tunnelId: widget.tunnelId!, tunnelInput: input);
        _snack('已保存');
      } else {
        await client.getFrpApi().createFrpTunnel(tunnelInput: input);
        _snack('已创建');
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_isEdit ? '编辑隧道' : '新建隧道'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('基本信息', Icons.dns_outlined),
                _textField(_name, '隧道名称', hint: '如 minecraft-tcp'),
                const SizedBox(height: 12),
                _textField(_serverAddr, '服务器地址', hint: 'frp.example.com'),
                const SizedBox(height: 12),
                _textField(
                  _serverPort,
                  '服务器端口',
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _textField(_user, '用户名(可选)'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _textField(_authToken, '鉴权 Token(可选)',
                          obscureText: true),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _sectionTitle('代理规则', Icons.account_tree_outlined),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _proxies.add(_ProxyForm());
                      }),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加代理'),
                    ),
                  ],
                ),
                for (var i = 0; i < _proxies.length; i++) ...[
                  _proxyCard(i, _proxies[i]),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(_isEdit ? '保存修改' : '创建隧道'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _proxyCard(int index, _ProxyForm p) {
    final cs = Theme.of(context).colorScheme;
    final isPortType = p.type == ProxyType.tcp || p.type == ProxyType.udp;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('代理 ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (_proxies.length > 1)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        p.dispose();
                        _proxies.removeAt(index);
                      });
                    },
                    tooltip: '移除',
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: cs.error),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<ProxyType>(
              initialValue: p.type,
              decoration: const InputDecoration(
                labelText: '协议类型',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final t in ProxyType.values)
                  DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())),
              ],
              onChanged: (v) => setState(() {
                if (v != null) p.type = v;
              }),
            ),
            const SizedBox(height: 12),
            _textField(p.name, '代理名称', hint: '如 minecraft'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _textField(p.localIp, '本地地址',
                      hint: '127.0.0.1'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(
                    p.localPort,
                    '本地端口',
                    keyboardType: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isPortType)
              _textField(
                p.remotePort,
                '远程端口',
                keyboardType: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
              )
            else
              _textField(
                p.customDomains,
                '自定义域名(逗号分隔)',
                hint: 'mc.example.com,play.example.com',
              ),
          ],
        ),
      ),
    );
  }
}
