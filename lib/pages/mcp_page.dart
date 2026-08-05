import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../config/mcp_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_scope.dart';
import '../net/network_address.dart';
import '../widgets/expandable_address_list.dart';
import '../widgets/miuix_snackbar.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';

/// MCP 服务页：对外开放一个 Streamable HTTP 的 MCP 服务，
/// 供外部 AI Agent 获取数据（服务器状态、系统资源、在线玩家、控制台日志等）
/// 与操作服务（启动/停止服务端、发送控制台命令、切换实例）。
///
/// 配置持久化到 `config/mcp.json`。服务由全局 [McpController] 管理，运行于
/// 应用进程内；保存新配置时若服务正在运行会自动重启。
class McpPage extends StatefulWidget {
  const McpPage({super.key});

  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  List<String>? _localIps;
  String? _localIpv6;

  final _port = TextEditingController(text: '8765');
  bool _allowControl = true;
  bool _allowShell = false;
  bool _ipv6 = false;

  @override
  void initState() {
    super.initState();
    // _loadAll 内会调用 McpScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final mcp = McpScope.of(context);
    final addrs = await Future.wait([
      NetworkAddress.detectAllIPv4(),
      NetworkAddress.detectStableIPv6(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIps = addrs[0] as List<String>;
      _localIpv6 = addrs[1] as String?;
      _port.text = '${mcp.config.port}';
      _allowControl = mcp.config.allowControl;
      _allowShell = mcp.config.allowShell;
      _ipv6 = mcp.config.ipv6Enabled;
    });
  }

  /// 从表单构造当前配置（保留 enabled 与 token 不变）。
  McpConfig _buildConfig() {
    final current = McpScope.of(context).config;
    return current.copyWith(
      port: int.tryParse(_port.text.trim()) ?? 8765,
      allowControl: _allowControl,
      allowShell: _allowShell,
      ipv6Enabled: _ipv6,
    );
  }

  /// 切换 MCP 开关。
  Future<void> _toggleMcp(bool value) async {
    final mcp = McpScope.of(context);
    try {
      await runWithLoadingDialog(
        context,
        context.tr(value ? 'common.startingService' : 'common.stoppingService'),
        () => mcp.setEnabled(value),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('mcpPage.operationFailed', {'error': '$e'}),
      );
      return;
    }
    if (!mounted) return;
    // 开启失败（如端口被占用）时给出提示。
    if (value && !mcp.isRunning && mcp.lastError != null) {
      showErrorDialog(
        context,
        context.tr('mcpPage.startFailed', {'error': mcp.lastError ?? ''}),
      );
    }
  }

  /// 保存配置；若 MCP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final mcp = McpScope.of(context);
    final config = _buildConfig();
    try {
      final ipv6 = await runWithLoadingDialog(
        context,
        context.tr('common.applyingConfig'),
        () async {
          await mcp.applyConfig(config);
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
        context.tr('mcpPage.operationFailed', {'error': '$e'}),
      );
      return;
    }
    showMiuixSnackbar(
      mcp.isRunning
          ? context.tr('mcpPage.savedAndRestarted')
          : context.tr('mcpPage.saved'),
    );
  }

  /// 重新生成访问令牌。
  Future<void> _regenerateToken() async {
    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('mcpPage.regenerateTokenTitle'),
      message: context.tr('mcpPage.regenerateTokenContent'),
      confirmLabel: context.tr('mcpPage.regenerate'),
    );
    if (!confirmed || !mounted) return;
    await McpScope.of(context).regenerateToken();
    if (!mounted) return;
    showMiuixSnackbar(context.tr('mcpPage.tokenGenerated'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final mcp = McpScope.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('mcpPage.title'), showBack: true),
      content: (padding) => ListView(
        padding: padding + const EdgeInsets.all(16),
        children: [
          _buildStatusCard(theme, mcp),
          const SizedBox(height: 16),
          _buildConfigCard(theme, mcp),
          const SizedBox(height: 16),
          _buildInfoCard(theme),
        ],
      ),
    );
  }

  // —— 状态卡片 ——

  Widget _buildStatusCard(MiuixThemeData theme, McpController mcp) {
    final running = mcp.isRunning;
    final port = mcp.config.port;
    return EcSectionCard(
      icon: Icons.hub_outlined,
      title: context.tr('mcpPage.title'),
      trailing: running
          ? EcStatusChip(context.tr('mcpPage.statusRunning'))
          : null,
      children: [
        MiuixSwitchPreference(
          title: context.tr('mcpPage.enableTitle'),
          summary: running
              ? context.tr('mcpPage.enableSubtitleRunning')
              : context.tr('mcpPage.enableSubtitleStopped'),
          value: running,
          onChanged: _toggleMcp,
        ),
        if (running)
          ExpandableAddressList(
            ips: _localIps ?? [],
            ipv6: mcp.config.ipv6Enabled ? _localIpv6 : null,
            itemBuilder: (ctx, ip, isPrimary) => [
              _addrRow(theme, 'http://$ip:$port/mcp'),
            ],
            ipv6Builder: (ctx, ipv6) => [
              _addrRow(theme, 'http://[$ipv6]:$port/mcp'),
            ],
          ),
      ],
    );
  }

  // —— 配置卡片 ——

  Widget _buildConfigCard(MiuixThemeData theme, McpController mcp) {
    final token = mcp.config.token;
    return EcSectionCard(
      title: context.tr('mcpPage.configTitle'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: EcTextField(
            controller: _port,
            label: context.tr('mcpPage.port'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(height: 8),
        // 访问令牌（只读展示 + 复制 + 重新生成）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MiuixBasicComponent(
            title: context.tr('mcpPage.tokenLabel'),
            insideMargin: const EdgeInsets.symmetric(vertical: 8),
            endActions: [
              MiuixIconButton(
                enabled: token.isNotEmpty,
                onPressed: token.isEmpty
                    ? null
                    : () => _copy(token, context.tr('mcpPage.tokenCopied')),
                child: const MiuixIcon(icon: Icons.copy, size: 18),
              ),
              MiuixIconButton(
                onPressed: _regenerateToken,
                child: const MiuixIcon(icon: Icons.refresh, size: 18),
              ),
            ],
            bottomAction: SelectableText(
              token.isEmpty ? context.tr('mcpPage.tokenUnset') : token,
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurface,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        MiuixSwitchPreference(
          title: context.tr('mcpPage.allowControl'),
          summary: context.tr('mcpPage.allowControlSubtitle'),
          value: _allowControl,
          onChanged: (v) => setState(() => _allowControl = v),
        ),
        MiuixSwitchPreference(
          title: context.tr('mcpPage.allowShell'),
          summary: context.tr('mcpPage.allowShellSubtitle'),
          value: _allowShell,
          onChanged: (v) => setState(() => _allowShell = v),
        ),
        MiuixSwitchPreference(
          title: context.tr('mcpPage.enableIpv6'),
          summary: context.tr('mcpPage.enableIpv6Subtitle'),
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
                  MiuixText(context.tr('mcpPage.saveConfig')),
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
              context.tr('mcpPage.infoText'),
              style: theme.textStyles.footnote1,
            ),
          ),
        ],
      ),
    );
  }

  // —— 工具 ——

  void _copy(String text, String hint) {
    Clipboard.setData(ClipboardData(text: text));
    showMiuixSnackbar(hint);
  }

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
            onPressed: () => _copy(addr, context.tr('mcpPage.addressCopied')),
            child: const MiuixIcon(icon: Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}
