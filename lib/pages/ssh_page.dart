import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ssh_store.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../net/network_address.dart';
import '../ssh/ssh_controller.dart';
import '../ssh/ssh_scope.dart';
import '../ssh/ssh_service.dart';

/// SSH 服务页：对外开放当前实例目录的 SFTP 文件访问与 SSH 远程终端。
///
/// 同一 SSH 服务器同时提供 SFTP 与 SSH 终端，共用端口、账号与主机密钥，两项能力各由开关
/// 独立启停。配置持久化到 `config/ssh.json`。服务由全局 [SshController] 管理，独立于服务端
/// 进程；切换实例或保存新配置时若服务正在运行会自动重启。
class SshPage extends StatefulWidget {
  const SshPage({super.key});

  @override
  State<SshPage> createState() => _SshPageState();
}

class _SshPageState extends State<SshPage> {
  String? _localIp;
  String? _localIpv6;
  String? _fingerprint;

  final _port = TextEditingController(text: '2222');
  final _username = TextEditingController();
  final _password = TextEditingController();
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
    final ssh = SshScope.of(context);
    final results = await Future.wait([
      NetworkAddress.detectIPv4(),
      NetworkAddress.detectStableIPv6(),
      SshService.hostKeyFingerprint(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIp = results[0];
      _localIpv6 = results[1];
      _fingerprint = results[2];
      _port.text = '${ssh.config.port}';
      _username.text = ssh.config.username;
      _password.text = ssh.config.password;
      _writable = ssh.config.writable;
      _ipv6 = ssh.config.ipv6Enabled;
    });
  }

  /// 从表单构造新配置（保留当前 SFTP/SSH 终端开关状态，开关由状态卡片单独控制）。
  SshConfig _buildConfig() {
    final current = SshScope.of(context).config;
    return current.copyWith(
      port: int.tryParse(_port.text.trim()) ?? 2222,
      username: _username.text.trim(),
      password: _password.text,
      writable: _writable,
      ipv6Enabled: _ipv6,
    );
  }

  /// 切换 SFTP 文件访问开关。
  Future<void> _toggleSftp(bool value) => _toggle(value, sftp: true);

  /// 切换 SSH 终端开关。
  Future<void> _toggleShell(bool value) => _toggle(value, sftp: false);

  Future<void> _toggle(bool value, {required bool sftp}) async {
    final ssh = SshScope.of(context);
    if (value) {
      if (InstanceScope.of(context).selected == null) {
        _snack(context.tr('ssh.noInstanceSelected'));
        return;
      }
      if (!ssh.config.hasCredentials) {
        _snack(context.tr('ssh.credentialsRequired'));
        return;
      }
    }
    try {
      if (sftp) {
        await ssh.setSftpEnabled(value);
      } else {
        await ssh.setShellEnabled(value);
      }
    } catch (e) {
      _snack(context.tr('ssh.operationFailed', {'error': e.toString()}));
    }
  }

  /// 保存配置；若服务正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _snack(context.tr('ssh.credentialsRequiredSave'));
      return;
    }
    final ssh = SshScope.of(context);
    await ssh.applyConfig(_buildConfig());
    // 重新检测地址：开启 IPv6 后可即时展示稳定 IPv6 地址。
    final ipv6 = await NetworkAddress.detectStableIPv6();
    if (!mounted) return;
    setState(() => _localIpv6 = ipv6);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ssh.isRunning
              ? context.tr('ssh.savedAndRestarted')
              : context.tr('ssh.saved'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ssh = SshScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ssh.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(theme, ssh),
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

  Widget _buildStatusCard(ThemeData theme, SshController ssh) {
    final running = ssh.isRunning;
    final port = ssh.config.port;
    final user = ssh.config.username;
    final hasRoot = ssh.rootDir != null;
    final String subtitle;
    if (!hasRoot) {
      subtitle = context.tr('ssh.selectInstanceFirst');
    } else if (!ssh.config.hasCredentials) {
      subtitle = context.tr('ssh.fillAndSaveAccount');
    } else {
      subtitle = context.tr('ssh.rootDirCurrentInstance');
    }
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
                    Icons.dns_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('ssh.service'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (running) _statusChip(theme, context.tr('ssh.running')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(subtitle, style: theme.textTheme.bodySmall),
            ),
            SwitchListTile(
              title: Text(context.tr('ssh.enableSftp')),
              subtitle: Text(context.tr('ssh.sftpHint')),
              value: ssh.config.sftpEnabled,
              onChanged: hasRoot ? _toggleSftp : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: Text(context.tr('ssh.enableShell')),
              subtitle: Text(context.tr('ssh.shellHint')),
              value: ssh.config.shellEnabled,
              onChanged: hasRoot ? _toggleShell : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (running) ...[
              const SizedBox(height: 4),
              if (ssh.config.sftpEnabled) ...[
                if (_localIp != null)
                  _addrRow(theme, 'sftp -P $port $user@$_localIp'),
                if (ssh.config.ipv6Enabled && _localIpv6 != null)
                  _addrRow(theme, 'sftp -P $port $user@[$_localIpv6]'),
              ],
              if (ssh.config.shellEnabled) ...[
                if (_localIp != null)
                  _addrRow(theme, 'ssh -p $port $user@$_localIp'),
                if (ssh.config.ipv6Enabled && _localIpv6 != null)
                  _addrRow(theme, 'ssh -p $port $user@[$_localIpv6]'),
              ],
            ],
            if (_fingerprint != null) _buildFingerprint(theme),
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
                context.tr('ssh.connectionConfig'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_port, context.tr('ssh.port'), number: true),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_username, context.tr('ssh.username')),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(
                _password,
                context.tr('ssh.password'),
                obscure: true,
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('ssh.allowWrite')),
              subtitle: Text(context.tr('ssh.writeOffHint')),
              value: _writable,
              onChanged: (v) => setState(() => _writable = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: Text(context.tr('ssh.enableIpv6')),
              subtitle: Text(context.tr('ssh.ipv6Hint')),
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
                  label: Text(context.tr('ssh.saveConfig')),
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
                context.tr('ssh.infoText'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 主机密钥指纹 ——

  Widget _buildFingerprint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('ssh.fingerprintTitle'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _fingerprint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: context.tr('ssh.copyFingerprint'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _fingerprint!)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // —— 工具 ——

  /// 单行连接命令展示（等宽字体 + 复制按钮）。IPv6 地址由调用方用方括号包裹。
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
            tooltip: context.tr('ssh.copyCommand'),
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
