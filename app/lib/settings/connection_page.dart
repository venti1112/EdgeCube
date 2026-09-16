import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/settings.dart';
import '../connection/state.dart';

/// 连接设置:改地址/端口/令牌后重连,或断开、忘记这台服务器。
///
/// 与首次启动的连接页共用同一批单项 Provider(`daemonHost/Port/Token`),
/// 所以在这里改完再去连接页,看到的是同一份值。
class ConnectionSettingsPage extends ConsumerStatefulWidget {
  const ConnectionSettingsPage({super.key});

  @override
  ConsumerState<ConnectionSettingsPage> createState() =>
      _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState
    extends ConsumerState<ConnectionSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: ref.read(daemonHostProvider));
    _port = TextEditingController(
      text: ref.read(daemonPortProvider).toString(),
    );
    _token = TextEditingController(text: ref.read(daemonTokenProvider));
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  /// 保存并重连。写入的是单项 Provider(聚合状态),不直接碰存储 ——
  /// 存储只在「连成功」时由 ConnectionNotifier 落盘。
  Future<void> _saveAndConnect() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final parsed = ConnectionSettings.parseHostInput(_host.text);
    final host = parsed.host;
    final port = parsed.port ?? int.parse(_port.text.trim());
    final token = _token.text.trim();
    _host.text = host;
    _port.text = port.toString();

    await ref.read(daemonHostProvider.notifier).set(host);
    await ref.read(daemonPortProvider.notifier).set(port);
    await ref.read(daemonTokenProvider.notifier).set(token);

    final ok = await ref
        .read(connectionProvider.notifier)
        .connect(ConnectionSettings(host: host, port: port, token: token));

    if (ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已连接')));
    }
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忘记这台服务器？'),
        content: const Text('将清除已保存的地址与令牌，并回到连接页。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('忘记'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 清空后 persistedConnection 变 null → 路由守卫把人送回连接页
    await ref.read(connectionProvider.notifier).forget();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('连接'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 当前状态
          Row(
            children: [
              Icon(
                status.isConnected
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: status.isConnected ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.isConnected
                      ? '已连接到 ${status.target}'
                      : (status.error ?? '未连接'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  key: const Key('settings_host'),
                  controller: _host,
                  enabled: !status.isConnecting,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    prefixIcon: Icon(Icons.dns_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: ConnectionSettings.validateHost,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('settings_port'),
                  controller: _port,
                  enabled: !status.isConnecting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    prefixIcon: Icon(Icons.numbers_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: ConnectionSettings.validatePort,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('settings_token'),
                  controller: _token,
                  enabled: !status.isConnecting,
                  obscureText: !_showToken,
                  decoration: InputDecoration(
                    labelText: '访问令牌',
                    hintText: 'daemon 未开启鉴权时留空',
                    prefixIcon: const Icon(Icons.key_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _showToken ? '隐藏令牌' : '显示令牌',
                      icon: Icon(
                        _showToken
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            key: const Key('settings_connect'),
            onPressed: status.isConnecting ? null : _saveAndConnect,
            icon: status.isConnecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(status.isConnecting ? '连接中…' : '保存并重连'),
          ),
          const SizedBox(height: 8),
          if (status.isConnected)
            OutlinedButton.icon(
              key: const Key('settings_disconnect'),
              onPressed: () => ref.read(connectionProvider.notifier).disconnect(),
              icon: const Icon(Icons.link_off),
              label: const Text('断开连接'),
            ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('忘记这台服务器', style: TextStyle(color: scheme.error)),
            subtitle: const Text('清除保存的地址与令牌，下次启动重新填写'),
            onTap: _confirmForget,
          ),
        ],
      ),
    );
  }
}
