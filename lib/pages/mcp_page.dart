import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/mcp_store.dart';
import '../i18n/locale_scope.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_scope.dart';
import '../net/network_address.dart';

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
  String? _localIp;
  String? _localIpv6;

  final _port = TextEditingController(text: '8765');
  bool _allowControl = true;
  bool _allowShell = false;
  bool _ipv6 = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final mcp = McpScope.of(context);
    final addrs = await Future.wait([
      NetworkAddress.detectIPv4(),
      NetworkAddress.detectStableIPv6(),
    ]);
    if (!mounted) return;
    setState(() {
      _localIp = addrs[0];
      _localIpv6 = addrs[1];
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
      await mcp.setEnabled(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('mcpPage.operationFailed', {'error': '$e'})),
        ),
      );
      return;
    }
    if (!mounted) return;
    // 开启失败（如端口被占用）时给出提示。
    if (value && !mcp.isRunning && mcp.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('mcpPage.startFailed', {'error': mcp.lastError ?? ''}),
          ),
        ),
      );
    }
  }

  /// 保存配置；若 MCP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final mcp = McpScope.of(context);
    await mcp.applyConfig(_buildConfig());
    // 重新检测地址：开启 IPv6 后可即时展示稳定 IPv6 地址。
    final ipv6 = await NetworkAddress.detectStableIPv6();
    if (!mounted) return;
    setState(() => _localIpv6 = ipv6);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mcp.isRunning
              ? context.tr('mcpPage.savedAndRestarted')
              : context.tr('mcpPage.saved'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 重新生成访问令牌。
  Future<void> _regenerateToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('mcpPage.regenerateTokenTitle')),
        content: Text(ctx.tr('mcpPage.regenerateTokenContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('mcpPage.regenerate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await McpScope.of(context).regenerateToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('mcpPage.tokenGenerated')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mcp = McpScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('mcpPage.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(theme, mcp),
            const SizedBox(height: 16),
            _buildConfigCard(theme, mcp),
            const SizedBox(height: 16),
            _buildInfoCard(theme),
          ],
        ),
      ),
    );
  }

  // —— 状态卡片 ——

  Widget _buildStatusCard(ThemeData theme, McpController mcp) {
    final running = mcp.isRunning;
    final port = mcp.config.port;
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
                    Icons.hub_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('mcpPage.title'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (running)
                    _statusChip(theme, context.tr('mcpPage.statusRunning')),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('mcpPage.enableTitle')),
              subtitle: Text(
                running
                    ? context.tr('mcpPage.enableSubtitleRunning')
                    : context.tr('mcpPage.enableSubtitleStopped'),
              ),
              value: running,
              onChanged: _toggleMcp,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (running) ...[
              if (_localIp != null)
                _addrRow(theme, 'http://$_localIp:$port/mcp'),
              if (mcp.config.ipv6Enabled && _localIpv6 != null)
                _addrRow(theme, 'http://[$_localIpv6]:$port/mcp'),
            ],
          ],
        ),
      ),
    );
  }

  // —— 配置卡片 ——

  Widget _buildConfigCard(ThemeData theme, McpController mcp) {
    final token = mcp.config.token;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.tr('mcpPage.configTitle'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.tr('mcpPage.port'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 访问令牌（只读展示 + 复制 + 重新生成）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.tr('mcpPage.tokenLabel'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: context.tr('mcpPage.copyToken'),
                        onPressed: token.isEmpty
                            ? null
                            : () => _copy(
                                token,
                                context.tr('mcpPage.tokenCopied'),
                              ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: context.tr('mcpPage.regenerate'),
                        onPressed: _regenerateToken,
                      ),
                    ],
                  ),
                ),
                child: SelectableText(
                  token.isEmpty ? context.tr('mcpPage.tokenUnset') : token,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('mcpPage.allowControl')),
              subtitle: Text(context.tr('mcpPage.allowControlSubtitle')),
              value: _allowControl,
              onChanged: (v) => setState(() => _allowControl = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: Text(context.tr('mcpPage.allowShell')),
              subtitle: Text(context.tr('mcpPage.allowShellSubtitle')),
              value: _allowShell,
              onChanged: (v) => setState(() => _allowShell = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: Text(context.tr('mcpPage.enableIpv6')),
              subtitle: Text(context.tr('mcpPage.enableIpv6Subtitle')),
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
                  label: Text(context.tr('mcpPage.saveConfig')),
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
                context.tr('mcpPage.infoText'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // —— 工具 ——

  void _copy(String text, String hint) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(hint), duration: const Duration(seconds: 2)),
    );
  }

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
            tooltip: context.tr('mcpPage.copyAddress'),
            onPressed: () => _copy(addr, context.tr('mcpPage.addressCopied')),
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
}
