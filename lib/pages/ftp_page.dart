import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ftp_store.dart';
import '../ftp/ftp_controller.dart';
import '../ftp/ftp_scope.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../net/network_address.dart';

/// FTP 文件管理页：对外开放当前实例目录的 FTP 访问。
///
/// 配置持久化到 `config/ftp.json`。FTP 服务由全局 [FtpController] 管理，
/// 独立于服务器进程；切换实例或保存新配置时若 FTP 正在运行会自动重启。
class FtpPage extends StatefulWidget {
  const FtpPage({super.key});

  @override
  State<FtpPage> createState() => _FtpPageState();
}

class _FtpPageState extends State<FtpPage> {
  String? _localIp;
  String? _localIpv6;

  final _port = TextEditingController(text: '2121');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _anonymous = true;
  bool _writable = true;
  bool _ipv6 = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final ftp = FtpScope.of(context);
    final addrs = await Future.wait([
      NetworkAddress.detectIPv4(),
      NetworkAddress.detectStableIPv6(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIp = addrs[0];
      _localIpv6 = addrs[1];
      _port.text = '${ftp.config.port}';
      _username.text = ftp.config.username;
      _password.text = ftp.config.password;
      _anonymous = ftp.config.isAnonymous;
      _writable = ftp.config.writable;
      _ipv6 = ftp.config.ipv6Enabled;
    });
  }

  /// 从表单构造当前配置。
  FtpConfig _buildConfig() {
    return FtpConfig(
      enabled: FtpScope.of(context).config.enabled,
      port: int.tryParse(_port.text.trim()) ?? 2121,
      username: _anonymous ? '' : _username.text.trim(),
      password: _anonymous ? '' : _password.text,
      writable: _writable,
      ipv6Enabled: _ipv6,
    );
  }

  /// 切换 FTP 开关。
  Future<void> _toggleFtp(bool value) async {
    final ftp = FtpScope.of(context);
    final instances = InstanceScope.of(context);
    if (value && instances.selected == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ftp.noInstanceSelected'))),
      );
      return;
    }
    try {
      await ftp.setEnabled(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('ftp.operationFailed', {'error': e.toString()}),
          ),
        ),
      );
    }
  }

  /// 保存配置；若 FTP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final ftp = FtpScope.of(context);
    final config = _buildConfig();
    await ftp.applyConfig(config);
    // 重新检测地址：开启 IPv6 后可即时展示稳定 IPv6 地址。
    final ipv6 = await NetworkAddress.detectStableIPv6();
    if (!mounted) return;
    setState(() => _localIpv6 = ipv6);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ftp.isRunning
              ? context.tr('ftp.savedAndRestarted')
              : context.tr('ftp.saved'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ftp = FtpScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ftp.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(theme, ftp),
            const SizedBox(height: 16),
            _buildConfigCard(theme),
            const SizedBox(height: 16),
            _buildInfoCard(theme),
          ],
        ),
      ),
    );
  }

  // —— 状态卡片 ——

  Widget _buildStatusCard(ThemeData theme, FtpController ftp) {
    final running = ftp.isRunning;
    final port = ftp.config.port;
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
                  Icon(
                    Icons.folder_shared_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('ftp.service'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (running) _statusChip(theme, context.tr('ftp.running')),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('ftp.enableFtp')),
              subtitle: Text(
                ftp.rootDir != null
                    ? context.tr('ftp.rootDirCurrentInstance')
                    : context.tr('ftp.selectInstanceFirst'),
              ),
              value: running,
              onChanged: ftp.rootDir == null ? null : _toggleFtp,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (running) ...[
              if (_localIp != null) _addrRow(theme, 'ftp://$_localIp:$port'),
              if (ftp.config.ipv6Enabled && _localIpv6 != null)
                _addrRow(theme, 'ftp://[$_localIpv6]:$port'),
            ],
          ],
        ),
      ),
    );
  }

  // —— 配置卡片 ——

  Widget _buildConfigCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.tr('ftp.connectionConfig'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_port, context.tr('ftp.port'), number: true),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(context.tr('ftp.anonymousAccess')),
              subtitle: Text(context.tr('ftp.anonymousOffHint')),
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (!_anonymous) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _field(_username, context.tr('ftp.username')),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _field(
                  _password,
                  context.tr('ftp.password'),
                  obscure: true,
                ),
              ),
            ],
            SwitchListTile(
              title: Text(context.tr('ftp.allowWrite')),
              subtitle: Text(context.tr('ftp.writeOffHint')),
              value: _writable,
              onChanged: (v) => setState(() => _writable = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: Text(context.tr('ftp.enableIpv6')),
              subtitle: Text(context.tr('ftp.ipv6Hint')),
              value: _ipv6,
              onChanged: (v) => setState(() => _ipv6 = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _saveConfig,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(context.tr('ftp.saveConfig')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 说明卡片 ——

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('ftp.infoText'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 工具 ——

  /// 单行地址展示（等宽字体 + 复制按钮）。IPv6 地址由调用方用方括号包裹。
  Widget _addrRow(ThemeData theme, String addr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              addr,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: context.tr('ftp.copyAddress'),
            onPressed: () => Clipboard.setData(ClipboardData(text: addr)),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool obscure = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
