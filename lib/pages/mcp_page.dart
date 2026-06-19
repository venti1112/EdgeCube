import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/mcp_store.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_scope.dart';

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

  final _port = TextEditingController(text: '8765');
  bool _allowControl = true;
  bool _allowShell = false;

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
    final ip = await _detectLocalIp();
    if (!mounted) return;
    setState(() {
      _localIp = ip;
      _port.text = '${mcp.config.port}';
      _allowControl = mcp.config.allowControl;
      _allowShell = mcp.config.allowShell;
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

  /// 从表单构造当前配置（保留 enabled 与 token 不变）。
  McpConfig _buildConfig() {
    final current = McpScope.of(context).config;
    return current.copyWith(
      port: int.tryParse(_port.text.trim()) ?? 8765,
      allowControl: _allowControl,
      allowShell: _allowShell,
    );
  }

  /// 切换 MCP 开关。
  Future<void> _toggleMcp(bool value) async {
    final mcp = McpScope.of(context);
    try {
      await mcp.setEnabled(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$e')));
      return;
    }
    if (!mounted) return;
    // 开启失败（如端口被占用）时给出提示。
    if (value && !mcp.isRunning && mcp.lastError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('启动失败：${mcp.lastError}')));
    }
  }

  /// 保存配置；若 MCP 正在运行则自动重启以应用新配置。
  Future<void> _saveConfig() async {
    final mcp = McpScope.of(context);
    await mcp.applyConfig(_buildConfig());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mcp.isRunning ? '已保存并重启 MCP 服务' : '已保存'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 重新生成访问令牌。
  Future<void> _regenerateToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成令牌'),
        content: const Text('生成新令牌后，旧令牌将立即失效，已连接的客户端需使用新令牌重新连接。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await McpScope.of(context).regenerateToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已生成新令牌'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mcp = McpScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('MCP 服务')),
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
    final addr = running && _localIp != null
        ? 'http://$_localIp:${mcp.config.port}/mcp'
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
                  Icon(
                    Icons.hub_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MCP 服务',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (running) _statusChip(theme, '运行中'),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('启用 MCP 服务'),
              subtitle: Text(
                running ? '已对局域网开放（Streamable HTTP）' : '开启后供 AI Agent 连接',
              ),
              value: running,
              onChanged: _toggleMcp,
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
                      onPressed: () => _copy(addr, '已复制地址'),
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
                '连接配置',
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
                decoration: const InputDecoration(
                  labelText: '端口',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 访问令牌（只读展示 + 复制 + 重新生成）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: '访问令牌（Bearer Token）',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: '复制令牌',
                        onPressed: token.isEmpty
                            ? null
                            : () => _copy(token, '已复制令牌'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: '重新生成',
                        onPressed: _regenerateToken,
                      ),
                    ],
                  ),
                ),
                child: SelectableText(
                  token.isEmpty ? '（未设置，不鉴权）' : token,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('允许控制操作'),
              subtitle: const Text('关闭后 AI 仅能读取数据，不能启停服务端、发送命令或切换实例'),
              value: _allowControl,
              onChanged: (v) => setState(() => _allowControl = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            SwitchListTile(
              title: const Text('允许 Shell 命令执行（高风险）'),
              subtitle: const Text(
                '开启后 AI 可在设备上执行任意 shell 命令（run_shell/shell_cd）',
              ),
              value: _allowShell,
              onChanged: (v) => setState(() => _allowShell = v),
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
                'MCP 服务以 Streamable HTTP 协议运行于应用进程内，App 存活时持续可用。'
                '同一局域网内的 AI 客户端使用上方地址连接，并在 Authorization 请求头携带 '
                '「Bearer <令牌>」进行鉴权。\n'
                '「允许控制操作」开启时，AI 可启动/停止服务端、发送控制台命令、切换实例；'
                '关闭时仅能读取状态、系统资源、在线玩家与日志等信息。\n'
                '保存新配置时，若服务正在运行将自动重启以应用变更。',
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
