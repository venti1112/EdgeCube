import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ssh_store.dart';
import '../ssh/ssh_controller.dart';
import '../ssh/ssh_scope.dart';
import '../ssh/ssh_service.dart';
import '../instance/instance_scope.dart';
import '../net/network_address.dart';

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
        _snack('没有选中的实例，无法确定 SSH 根目录');
        return;
      }
      if (!ssh.config.hasCredentials) {
        _snack('请先在下方填写用户名和密码并保存配置');
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
      _snack('操作失败：$e');
    }
  }

  /// 保存配置；若服务正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _snack('请填写用户名和密码（SSH 服务不支持匿名访问）');
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
        content: Text(ssh.isRunning ? '已保存并重启 SSH 服务' : '已保存'),
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
      appBar: AppBar(title: const Text('SSH 服务')),
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
      subtitle = '请先选择一个实例';
    } else if (!ssh.config.hasCredentials) {
      subtitle = '请先在下方填写并保存账号';
    } else {
      subtitle = '根目录：当前实例文件夹';
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
                      'SSH 服务',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (running) _statusChip(theme, '运行中'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(subtitle, style: theme.textTheme.bodySmall),
            ),
            SwitchListTile(
              title: const Text('启用 SFTP 文件访问'),
              subtitle: const Text('通过 sftp 客户端安全地传输实例目录文件'),
              value: ssh.config.sftpEnabled,
              onChanged: hasRoot ? _toggleSftp : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: const Text('启用 SSH 终端'),
              subtitle: const Text('通过 ssh 客户端进入设备交互式终端'),
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
                '连接配置',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_port, '端口', number: true),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_username, '用户名'),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _field(_password, '密码', obscure: true),
            ),
            SwitchListTile(
              title: const Text('允许写入'),
              subtitle: const Text('仅作用于 SFTP；关闭后 SFTP 只能下载，不能上传/删除/重命名'),
              value: _writable,
              onChanged: (v) => setState(() => _writable = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: const Text('启用 IPv6 访问'),
              subtitle: const Text('开启后同时监听 IPv6（双栈），可经稳定 IPv6 地址访问'),
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
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'SFTP 根目录与 SSH 终端初始目录均为当前选中实例的文件夹。SFTP 与 SSH 终端共用同一'
                '端口、账号与主机密钥，可分别启停。切换实例或保存新配置时，若服务正在运行将自动重启。\n'
                'SSH 服务强制账号密码登录，不支持匿名。「允许写入」仅作用于 SFTP，SSH 终端可执行命令'
                '不受其限制，请妥善保管账号。\n'
                '同一局域网内的设备可使用上方地址访问；外网访问需配合端口映射。'
                '开启 IPv6 后可经稳定的 IPv6 地址直接访问。',
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
            '主机密钥指纹（首次连接时核对）',
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
                tooltip: '复制指纹',
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
            tooltip: '复制命令',
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
