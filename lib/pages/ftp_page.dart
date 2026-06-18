import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ftp_store.dart';
import '../ftp/ftp_controller.dart';
import '../ftp/ftp_scope.dart';
import '../instance/instance_scope.dart';

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

  final _port = TextEditingController(text: '2121');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _anonymous = true;
  bool _writable = true;

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
    final ip = await _detectLocalIp();
    if (!mounted) return;
    setState(() {
      _localIp = ip;
      _port.text = '${ftp.config.port}';
      _username.text = ftp.config.username;
      _password.text = ftp.config.password;
      _anonymous = ftp.config.isAnonymous;
      _writable = ftp.config.writable;
    });
  }

  /// 获取本机局域网 IPv4 地址（排除回环）。
  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // 忽略
    }
    return null;
  }

  /// 从表单构造当前配置。
  FtpConfig _buildConfig() {
    return FtpConfig(
      enabled: FtpScope.of(context).config.enabled,
      port: int.tryParse(_port.text.trim()) ?? 2121,
      username: _anonymous ? '' : _username.text.trim(),
      password: _anonymous ? '' : _password.text,
      writable: _writable,
    );
  }

  /// 切换 FTP 开关。
  Future<void> _toggleFtp(bool value) async {
    final ftp = FtpScope.of(context);
    final instances = InstanceScope.of(context);
    if (value && instances.selected == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有选中的实例，无法确定 FTP 根目录')),
      );
      return;
    }
    try {
      await ftp.setEnabled(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    }
  }

  /// 保存配置；若 FTP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final ftp = FtpScope.of(context);
    final config = _buildConfig();
    await ftp.applyConfig(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ftp.isRunning ? '已保存并重启 FTP 服务' : '已保存'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ftp = FtpScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('FTP 文件管理')),
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
    final addr = running && _localIp != null
        ? 'ftp://$_localIp:$port'
        : null;
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
                  Icon(Icons.folder_shared_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FTP 服务',
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  if (running) _statusChip(theme, '运行中'),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('启用 FTP 访问'),
              subtitle: Text(ftp.rootDir != null
                  ? '根目录：当前实例文件夹'
                  : '请先选择一个实例'),
              value: running,
              onChanged: ftp.rootDir == null ? null : _toggleFtp,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (addr != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                      tooltip: '复制地址',
                      onPressed: () => Clipboard.setData(ClipboardData(text: addr)),
                    ),
                  ],
                ),
              ),
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
                '连接配置',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_port, '端口', number: true),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('匿名访问'),
              subtitle: const Text('关闭后需填写用户名和密码'),
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (!_anonymous) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _field(_username, '用户名'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _field(_password, '密码', obscure: true),
              ),
            ],
            SwitchListTile(
              title: const Text('允许写入'),
              subtitle: const Text('关闭后仅可下载，不能上传/删除/重命名'),
              value: _writable,
              onChanged: (v) => setState(() => _writable = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _saveConfig,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('保存配置'),
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
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'FTP 根目录为当前选中实例的文件夹。切换实例或保存新配置时，'
                '若 FTP 正在运行将自动重启以应用变更。\n'
                '同一局域网内的设备可使用上方地址访问；外网访问需配合端口映射。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 工具 ——

  Widget _statusChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
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
