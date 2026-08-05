import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_registry_store.dart';
import '../../frp/frp_scope.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/error_dialog.dart';
import '../../widgets/ec_preference.dart';
import '../../widgets/ec_text_field.dart';
import '../../widgets/miuix_snackbar.dart';

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
      name = _nameField.text.trim().isEmpty ? 'Custom' : _nameField.text.trim();
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
    showMiuixSnackbar(context.tr('frp.tunnelSaved'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('frp.provider.custom')),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MiuixTabRow(
                tabs: [context.tr('frp.easyMode'), context.tr('frp.rawMode')],
                selectedTabIndex: _easyMode ? 0 : 1,
                onTabSelected: (i) => setState(() => _easyMode = i == 0),
              ),
              const SizedBox(height: 16),
              EcTextField(
                controller: _nameField,
                label: context.tr('frp.tunnelName'),
              ),
              const SizedBox(height: 12),
              if (_easyMode) ..._buildEasyFields() else _buildRawField(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: MiuixButton(
                  onPressed: _save,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiuixIcon(icon: Icons.save, size: 18),
                      const SizedBox(width: 8),
                      MiuixText(context.tr('common.save')),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
            child: EcTextField(
              controller: _serverAddrField,
              label: context.tr('frp.serverAddr'),
              hint: 'frp.example.com',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: EcTextField(
              controller: _serverPortField,
              label: context.tr('frp.serverPort'),
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
              controller: _userField,
              label: context.tr('frp.user'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EcTextField(
              controller: _tokenField,
              label: context.tr('frp.authToken'),
              obscureText: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: MiuixOverlayDropdownPreference(
              title: context.tr('frp.protocol'),
              items: const ['TCP', 'UDP'],
              selectedIndex: _type == 'udp' ? 1 : 0,
              onSelectedIndexChange: (i) =>
                  setState(() => _type = i == 1 ? 'udp' : 'tcp'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EcTextField(
              controller: _localIpField,
              label: context.tr('frp.localIp'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: EcTextField(
              controller: _localPortField,
              label: context.tr('frp.localPort'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: EcTextField(
              controller: _remotePortField,
              label: context.tr('frp.remotePort'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      MiuixSwitchPreference(
        title: context.tr('frp.tlsEnable'),
        value: _tls,
        onChanged: (v) => setState(() => _tls = v),
        insideMargin: const EdgeInsets.symmetric(vertical: 8),
      ),
    ];
  }

  Widget _buildRawField() {
    return EcTextField(
      controller: _rawField,
      maxLines: 16,
      textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      label: 'frpc.toml',
      hint: context.tr('frp.rawConfigHint'),
    );
  }
}
