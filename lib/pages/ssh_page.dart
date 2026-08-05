import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../config/ssh_store.dart';
import '../i18n/i18n_service.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../instance/instance_scope.dart';
import '../net/network_address.dart';
import '../ssh/ssh_controller.dart';
import '../ssh/ssh_scope.dart';
import '../ssh/ssh_service.dart';
import '../widgets/expandable_address_list.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';

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
  List<String>? _localIps;
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
    // _loadAll 内会调用 SshScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
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
      NetworkAddress.detectAllIPv4(),
      NetworkAddress.detectStableIPv6(),
      SshService.hostKeyFingerprint(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIps = results[0] as List<String>;
      _localIpv6 = results[1] as String?;
      _fingerprint = results[2] as String?;
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
        _showError(context.tr('ssh.noInstanceSelected'));
        return;
      }
      if (!ssh.config.hasCredentials) {
        _showError(context.tr('ssh.credentialsRequired'));
        return;
      }
    }
    try {
      await runWithLoadingDialog(
        context,
        context.tr(value ? 'common.startingService' : 'common.stoppingService'),
        () => sftp ? ssh.setSftpEnabled(value) : ssh.setShellEnabled(value),
      );
    } catch (e) {
      _showError(tr('ssh.operationFailed', {'error': e.toString()}));
    }
  }

  /// 保存配置；若服务正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _showError(context.tr('ssh.credentialsRequiredSave'));
      return;
    }
    final ssh = SshScope.of(context);
    final config = _buildConfig();
    try {
      final ipv6 = await runWithLoadingDialog(
        context,
        context.tr('common.applyingConfig'),
        () async {
          await ssh.applyConfig(config);
          // 重新检测地址：开启 IPv6 后可即时展示稳定 IPv6 地址。
          return NetworkAddress.detectStableIPv6();
        },
      );
      if (!mounted) return;
      setState(() => _localIpv6 = ipv6);
    } catch (e) {
      _showError(tr('ssh.operationFailed', {'error': e.toString()}));
      return;
    }
    showMiuixSnackbar(
      ssh.isRunning
          ? context.tr('ssh.savedAndRestarted')
          : context.tr('ssh.saved'),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    showErrorDialog(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final ssh = SshScope.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('ssh.title'), showBack: true),
      content: (padding) => Padding(
        padding: padding,
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

  Widget _buildStatusCard(MiuixThemeData theme, SshController ssh) {
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
    return EcSectionCard(
      icon: Icons.dns_outlined,
      title: context.tr('ssh.service'),
      trailing: running ? EcStatusChip(context.tr('ssh.running')) : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: MiuixText(subtitle, style: theme.textStyles.footnote1),
        ),
        MiuixSwitchPreference(
          title: context.tr('ssh.enableSftp'),
          summary: context.tr('ssh.sftpHint'),
          value: ssh.config.sftpEnabled,
          enabled: hasRoot,
          onChanged: _toggleSftp,
        ),
        MiuixSwitchPreference(
          title: context.tr('ssh.enableShell'),
          summary: context.tr('ssh.shellHint'),
          value: ssh.config.shellEnabled,
          enabled: hasRoot,
          onChanged: _toggleShell,
        ),
        if (running) ...[
          const SizedBox(height: 4),
          ExpandableAddressList(
            ips: _localIps ?? [],
            ipv6: ssh.config.ipv6Enabled ? _localIpv6 : null,
            itemBuilder: (ctx, ip, isPrimary) => [
              if (ssh.config.sftpEnabled)
                _addrRow(theme, 'sftp -P $port $user@$ip'),
              if (ssh.config.shellEnabled)
                _addrRow(theme, 'ssh -p $port $user@$ip'),
            ],
            ipv6Builder: (ctx, ipv6) => [
              if (ssh.config.sftpEnabled)
                _addrRow(theme, 'sftp -P $port $user@[$ipv6]'),
              if (ssh.config.shellEnabled)
                _addrRow(theme, 'ssh -p $port $user@[$ipv6]'),
            ],
          ),
        ],
        if (_fingerprint != null) _buildFingerprint(theme),
      ],
    );
  }

  // —— 配置卡片 ——

  Widget _buildConfigCard(MiuixThemeData theme) {
    return EcSectionCard(
      title: context.tr('ssh.connectionConfig'),
      children: [
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
          child: _field(_password, context.tr('ssh.password'), obscure: true),
        ),
        const SizedBox(height: 8),
        MiuixSwitchPreference(
          title: context.tr('ssh.allowWrite'),
          summary: context.tr('ssh.writeOffHint'),
          value: _writable,
          onChanged: (v) => setState(() => _writable = v),
        ),
        MiuixSwitchPreference(
          title: context.tr('ssh.enableIpv6'),
          summary: context.tr('ssh.ipv6Hint'),
          value: _ipv6,
          onChanged: (v) => setState(() => _ipv6 = v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            // MiuixButton 贴内容尺寸，不会自动撑满，需显式给宽。
            width: double.infinity,
            child: MiuixButton(
              onPressed: _saveConfig,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiuixIcon(icon: Icons.save, size: 18),
                  const SizedBox(width: 8),
                  MiuixText(context.tr('ssh.saveConfig')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // —— 说明卡片 ——

  Widget _buildInfoCard(MiuixThemeData theme) {
    return MiuixCard(
      colors: MiuixCardColors(
        color: theme.colors.surfaceContainerHighest,
        contentColor: theme.colors.onSurfaceContainerHighest,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixIcon(
            icon: Icons.info_outline,
            size: 18,
            tint: theme.colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MiuixText(
              context.tr('ssh.infoText'),
              style: theme.textStyles.footnote1,
            ),
          ),
        ],
      ),
    );
  }

  // —— 主机密钥指纹 ——

  Widget _buildFingerprint(MiuixThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixText(
            context.tr('ssh.fingerprintTitle'),
            style: theme.textStyles.footnote2,
            color: theme.colors.onSurfaceVariantSummary,
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _fingerprint!,
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurface,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              MiuixIconButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _fingerprint!)),
                child: const MiuixIcon(icon: Icons.copy, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // —— 工具 ——

  /// 单行连接命令展示（等宽字体 + 复制按钮）。IPv6 地址由调用方用方括号包裹。
  Widget _addrRow(MiuixThemeData theme, String addr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              addr,
              style: theme.textStyles.body2.copyWith(
                fontFamily: 'monospace',
                color: theme.colors.primary,
              ),
            ),
          ),
          MiuixIconButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: addr)),
            child: const MiuixIcon(icon: Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool obscure = false,
  }) {
    return EcTextField(
      controller: c,
      label: label,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      obscureText: obscure,
    );
  }
}
