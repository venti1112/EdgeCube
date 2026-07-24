import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_registry_store.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/error_dialog.dart';

/// 自定义 FRP 配置页：简易表单生成 TOML，或整段粘贴 TOML。
class FrpCustomConfigPage extends StatefulWidget {
  const FrpCustomConfigPage({super.key});

  @override
  State<FrpCustomConfigPage> createState() => _FrpCustomConfigPageState();
}

class _FrpCustomConfigPageState extends State<FrpCustomConfigPage> {
  /// true = 简易表单模式，false = 原样粘贴模式。
  bool _easyMode = true;

  final _nameField = TextEditingController(text: 'EdgeCube');
  final _serverAddrField = TextEditingController();
  final _serverPortField = TextEditingController(text: '7000');
  final _userField = TextEditingController();
  final _tokenField = TextEditingController();
  final _localIpField = TextEditingController(text: '127.0.0.1');
  final _localPortField = TextEditingController(text: '25565');
  final _remotePortField = TextEditingController(text: '25566');
  final _rawField = TextEditingController();
  String _type = 'tcp';
  bool _tls = true;

  @override
  void dispose() {
    _nameField.dispose();
    _serverAddrField.dispose();
    _serverPortField.dispose();
    _userField.dispose();
    _tokenField.dispose();
    _localIpField.dispose();
    _localPortField.dispose();
    _remotePortField.dispose();
    _rawField.dispose();
    super.dispose();
  }

  String _q(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// 从简易表单生成 TOML。
  String _buildEasyToml() {
    final buffer = StringBuffer()
      ..writeln('serverAddr = ${_q(_serverAddrField.text.trim())}')
      ..writeln('serverPort = ${_serverPortField.text.trim()}');
    final user = _userField.text.trim();
    if (user.isNotEmpty) buffer.writeln('user = ${_q(user)}');
    final token = _tokenField.text.trim();
    if (token.isNotEmpty) buffer.writeln('auth.token = ${_q(token)}');
    buffer
      ..writeln('transport.tls.enable = $_tls')
      ..writeln('log.to = "console"')
      ..writeln('log.level = "info"')
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln('name = ${_q(_nameField.text.trim())}')
      ..writeln('type = ${_q(_type)}')
      ..writeln('localIP = ${_q(_localIpField.text.trim())}')
      ..writeln('localPort = ${_localPortField.text.trim()}')
      ..writeln('remotePort = ${_remotePortField.text.trim()}');
    return buffer.toString();
  }

  Future<void> _save() async {
    final trans = LocaleScope.of(context).translations;
    final String toml;
    final String name;
    final int? localPort;
    final int? remotePort;
    if (_easyMode) {
      if (_serverAddrField.text.trim().isEmpty ||
          int.tryParse(_serverPortField.text.trim()) == null ||
          int.tryParse(_localPortField.text.trim()) == null ||
          int.tryParse(_remotePortField.text.trim()) == null ||
          _nameField.text.trim().isEmpty) {
        showErrorDialog(context, trans.get('frp.createInvalid'));
        return;
      }
      toml = _buildEasyToml();
      name = _nameField.text.trim();
      localPort = int.parse(_localPortField.text.trim());
      remotePort = int.parse(_remotePortField.text.trim());
    } else {
      if (_rawField.text.trim().isEmpty) {
        showErrorDialog(context, trans.get('frp.rawConfigEmpty'));
        return;
      }
      toml = _rawField.text;
      name = _nameField.text.trim().isEmpty
          ? 'Custom'
          : _nameField.text.trim();
      localPort = null;
      remotePort = null;
    }
    final saved = SavedFrpTunnel(
      localId: await FrpRegistryStore.newLocalId(),
      provider: FrpProvider.custom,
      name: name,
      type: _easyMode ? _type : 'tcp',
      localIp: _easyMode ? _localIpField.text.trim() : '127.0.0.1',
      localPort: localPort ?? 25565,
      remotePort: remotePort,
      remoteAddress: _easyMode && remotePort != null
          ? '${_serverAddrField.text.trim()}:$remotePort'
          : '',
      customToml: toml,
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('frp.provider.custom'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(context.tr('frp.easyMode')),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(context.tr('frp.rawMode')),
                ),
              ],
              selected: {_easyMode},
              onSelectionChanged: (v) => setState(() => _easyMode = v.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameField,
              decoration: InputDecoration(
                labelText: context.tr('frp.tunnelName'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_easyMode) ..._buildEasyFields() else _buildRawField(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 18),
                label: Text(context.tr('common.save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEasyFields() {
    return [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _serverAddrField,
              decoration: InputDecoration(
                labelText: context.tr('frp.serverAddr'),
                hintText: 'frp.example.com',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _serverPortField,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.tr('frp.serverPort'),
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
              controller: _userField,
              decoration: InputDecoration(
                labelText: context.tr('frp.user'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _tokenField,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.tr('frp.authToken'),
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
            child: DropdownButtonFormField<String>(
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
          ),
          const SizedBox(width: 12),
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
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
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
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _remotePortField,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.tr('frp.remotePort'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        title: Text(context.tr('frp.tlsEnable')),
        value: _tls,
        onChanged: (v) => setState(() => _tls = v),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ];
  }

  Widget _buildRawField() {
    return TextField(
      controller: _rawField,
      maxLines: 16,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: 'frpc.toml',
        hintText: context.tr('frp.rawConfigHint'),
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
