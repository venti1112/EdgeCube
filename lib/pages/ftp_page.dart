import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../config/ftp_store.dart';
import '../ftp/ftp_controller.dart';
import '../ftp/ftp_scope.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../instance/instance_scope.dart';
import '../net/network_address.dart';
import '../widgets/expandable_address_list.dart';
import '../widgets/miuix_snackbar.dart';

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
  List<String>? _localIps;
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
    // _loadAll 内会调用 FtpScope.of(context)，依赖 inherited widget，
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
    final ftp = FtpScope.of(context);
    final addrs = await Future.wait([
      NetworkAddress.detectAllIPv4(),
      NetworkAddress.detectStableIPv6(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIps = addrs[0] as List<String>;
      _localIpv6 = addrs[1] as String?;
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
      showErrorDialog(context, context.tr('ftp.noInstanceSelected'));
      return;
    }
    try {
      await runWithLoadingDialog(
        context,
        context.tr(value ? 'common.startingService' : 'common.stoppingService'),
        () => ftp.setEnabled(value),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('ftp.operationFailed', {'error': e.toString()}),
      );
    }
  }

  /// 保存配置；若 FTP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final ftp = FtpScope.of(context);
    final config = _buildConfig();
    try {
      final ipv6 = await runWithLoadingDialog(
        context,
        context.tr('common.applyingConfig'),
        () async {
          await ftp.applyConfig(config);
          // 重新检测地址：开启 IPv6 后可即时展示稳定 IPv6 地址。
          return NetworkAddress.detectStableIPv6();
        },
      );
      if (!mounted) return;
      setState(() => _localIpv6 = ipv6);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('ftp.operationFailed', {'error': e.toString()}),
      );
      return;
    }
    showMiuixSnackbar(
      ftp.isRunning
          ? context.tr('ftp.savedAndRestarted')
          : context.tr('ftp.saved'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final ftp = FtpScope.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('ftp.title'), showBack: true),
      content: (padding) => ListView(
        padding: padding + const EdgeInsets.all(16),
        children: [
          _buildStatusCard(theme, ftp),
          const SizedBox(height: 16),
          _buildConfigCard(theme),
          const SizedBox(height: 16),
          _buildInfoCard(theme),
        ],
      ),
    );
  }

  // —— 状态卡片 ——

  Widget _buildStatusCard(MiuixThemeData theme, FtpController ftp) {
    final running = ftp.isRunning;
    final port = ftp.config.port;
    return EcSectionCard(
      icon: Icons.folder_shared_outlined,
      title: context.tr('ftp.service'),
      trailing: running ? EcStatusChip(context.tr('ftp.running')) : null,
      children: [
        MiuixSwitchPreference(
          title: context.tr('ftp.enableFtp'),
          summary: ftp.rootDir != null
              ? context.tr('ftp.rootDirCurrentInstance')
              : context.tr('ftp.selectInstanceFirst'),
          value: running,
          enabled: ftp.rootDir != null,
          onChanged: _toggleFtp,
        ),
        if (running)
          ExpandableAddressList(
            ips: _localIps ?? [],
            ipv6: ftp.config.ipv6Enabled ? _localIpv6 : null,
            itemBuilder: (ctx, ip, isPrimary) => [
              _addrRow(theme, 'ftp://$ip:$port'),
            ],
            ipv6Builder: (ctx, ipv6) => [
              _addrRow(theme, 'ftp://[$ipv6]:$port'),
            ],
          ),
      ],
    );
  }

  // —— 配置卡片 ——

  Widget _buildConfigCard(MiuixThemeData theme) {
    return EcSectionCard(
      title: context.tr('ftp.connectionConfig'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _field(_port, context.tr('ftp.port'), number: true),
        ),
        const SizedBox(height: 8),
        MiuixSwitchPreference(
          title: context.tr('ftp.anonymousAccess'),
          summary: context.tr('ftp.anonymousOffHint'),
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v),
        ),
        if (!_anonymous) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _field(_username, context.tr('ftp.username')),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _field(_password, context.tr('ftp.password'), obscure: true),
          ),
          const SizedBox(height: 8),
        ],
        MiuixSwitchPreference(
          title: context.tr('ftp.allowWrite'),
          summary: context.tr('ftp.writeOffHint'),
          value: _writable,
          onChanged: (v) => setState(() => _writable = v),
        ),
        MiuixSwitchPreference(
          title: context.tr('ftp.enableIpv6'),
          summary: context.tr('ftp.ipv6Hint'),
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
                  MiuixText(context.tr('ftp.saveConfig')),
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
      insideMargin: const EdgeInsets.all(12),
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
              context.tr('ftp.infoText'),
              style: theme.textStyles.footnote1,
            ),
          ),
        ],
      ),
    );
  }

  // —— 工具 ——

  /// 单行地址展示（等宽字体 + 复制按钮）。IPv6 地址由调用方用方括号包裹。
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
