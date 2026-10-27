import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 自定义 FRP 配置页：简易表单生成 TOML，或整段粘贴 TOML。
///
/// **拼 TOML 与校验都不在这里** —— 本页只把用户填的字段交给 daemon
/// （`frp.tunnels.save` + `custom_form` / `custom_toml`），
/// 生成规则只有 daemon 里那一份，
/// 校验不通过时也由 daemon 回那两句提示语。
class FrpCustomConfigPage extends ConsumerStatefulWidget {
  const FrpCustomConfigPage({super.key});

  @override
  ConsumerState<FrpCustomConfigPage> createState() => _FrpCustomConfigPageState();
}

class _FrpCustomConfigPageState extends ConsumerState<FrpCustomConfigPage> {
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
  bool _saving = false;

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

  Future<void> _save() async {
    final api = ref.read(frpApiProvider);
    if (api == null) {
      showSnack(context, '还没有连接到守护进程');
      return;
    }
    final input = _easyMode
        ? FrpTunnelInput.customForm(
            name: _nameField.text.trim(),
            serverAddr: _serverAddrField.text.trim(),
            serverPort: int.tryParse(_serverPortField.text.trim()),
            user: _userField.text.trim(),
            authToken: _tokenField.text.trim(),
            type: _type,
            localIp: _localIpField.text.trim(),
            localPort: int.tryParse(_localPortField.text.trim()),
            remotePort: int.tryParse(_remotePortField.text.trim()),
            tlsEnable: _tls,
          )
        : FrpTunnelInput.customRaw(
            name: _nameField.text.trim(),
            toml: _rawField.text,
          );

    setState(() => _saving = true);
    final FrpTunnelSaveResult saved;
    try {
      saved = await api.saveTunnel(input);
    } on DaemonException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      // invalid_params 的 message 就是那两句固定文案（「请完整填写隧道名称与端口」
      // /「配置内容不能为空」），别的错误按码翻译。
      await showErrorDialog(context, describeFrpError(error));
      return;
    }
    if (!mounted) return;
    ref.invalidate(frpTunnelsProvider);
    showSnack(
      context,
      saved.configError.isEmpty
          ? '隧道已保存到列表'
          : '隧道已保存，但配置生成失败：${saved.configError}',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('自定义 FRP'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'easy', label: Text('简易表单')),
              ButtonSegment(value: 'raw', label: Text('粘贴配置')),
            ],
            selected: {_easyMode ? 'easy' : 'raw'},
            onSelectionChanged: _saving
                ? null
                : (selection) =>
                      setState(() => _easyMode = selection.first == 'easy'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('frp_custom_name'),
            controller: _nameField,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: '隧道名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_easyMode) ..._easyFields() else _rawFieldWidget(),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  List<Widget> _easyFields() => [
    Row(
      children: [
        Expanded(
          flex: 3,
          child: _text(_serverAddrField, '服务器地址', hint: 'frp.example.com'),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _text(
            _serverPortField,
            '服务器端口',
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(child: _text(_userField, '用户名（可选）')),
        const SizedBox(width: 12),
        Expanded(
          child: _text(_tokenField, '鉴权 Token（可选）', obscureText: true),
        ),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: '协议',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'tcp', child: Text('TCP')),
              DropdownMenuItem(value: 'udp', child: Text('UDP')),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _type = value ?? 'tcp'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _text(_localIpField, '本地地址')),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(child: _text(_localPortField, '本地端口', keyboardType: TextInputType.number)),
        const SizedBox(width: 12),
        Expanded(child: _text(_remotePortField, '远程端口', keyboardType: TextInputType.number)),
      ],
    ),
    const SizedBox(height: 4),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('启用 TLS 加密传输'),
      value: _tls,
      onChanged: _saving ? null : (value) => setState(() => _tls = value),
    ),
  ];

  Widget _rawFieldWidget() => TextField(
    key: const Key('frp_custom_raw'),
    controller: _rawField,
    enabled: !_saving,
    maxLines: 16,
    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    decoration: const InputDecoration(
      labelText: 'frpc.toml',
      hintText: '粘贴完整的 frpc TOML 配置',
      border: OutlineInputBorder(),
      alignLabelWithHint: true,
    ),
  );

  Widget _text(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    enabled: !_saving,
    obscureText: obscureText,
    keyboardType: keyboardType,
    inputFormatters: keyboardType == TextInputType.number
        ? [FilteringTextInputFormatter.digitsOnly]
        : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}
