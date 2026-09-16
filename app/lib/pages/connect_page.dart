import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/settings.dart';
import '../connection/state.dart';

/// 首次启动的连接页:填地址 / 端口 / 令牌,连上即进入主界面。
///
/// 它是**路由守卫**守出来的:只有 `persistedConnectionProvider == null`
/// (即从未成功连接过)时才会出现。连接成功会把配置落盘,于是守卫放行、
/// 自动切到主界面;之后的启动直接进主界面,断线由顶部横幅负责提示。
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    // 从全局 Provider 回填:可能是上次「忘记服务器」前留下的残值
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 用户很可能把 `ws://192.168.1.10:8787/ws` 整段粘进地址栏:
    // 先整理成 host + port,再写回输入框,免得下次看到的还是那坨。
    final parsed = ConnectionSettings.parseHostInput(_host.text);
    final host = parsed.host;
    final port = parsed.port ?? int.parse(_port.text.trim());
    final token = _token.text.trim();
    _host.text = host;
    _port.text = port.toString();

    await ref.read(daemonHostProvider.notifier).set(host);
    await ref.read(daemonPortProvider.notifier).set(port);
    await ref.read(daemonTokenProvider.notifier).set(token);

    // 成功后 persistedConnection 变化 → 路由守卫把页面切到主界面,
    // 这里不需要(也不应该)自己 navigate。
    await ref
        .read(connectionProvider.notifier)
        .connect(ConnectionSettings(host: host, port: port, token: token));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(connectionProvider);
    final connecting = status.isConnecting;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 56,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'EdgeCube',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '连接到 EdgeCube 守护进程',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      key: const Key('connect_host'),
                      controller: _host,
                      enabled: !connecting,
                      autofillHints: const [AutofillHints.url],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: '${ConnectionSettings.hostExample} 或 ws://host:${ConnectionSettings.defaultPort}',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: ConnectionSettings.validateHost,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      key: const Key('connect_port'),
                      controller: _port,
                      enabled: !connecting,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '${ConnectionSettings.defaultPort}',
                        prefixIcon: Icon(Icons.numbers_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: ConnectionSettings.validatePort,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      key: const Key('connect_token'),
                      controller: _token,
                      enabled: !connecting,
                      obscureText: !_showToken,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!connecting) _submit();
                      },
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
                          onPressed: () =>
                              setState(() => _showToken = !_showToken),
                        ),
                      ),
                    ),

                    // 连接失败时给原因,而不是让人对着转圈猜
                    if (status.error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBox(message: status.error!),
                    ],

                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('connect_submit'),
                      onPressed: connecting ? null : _submit,
                      icon: connecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(connecting ? '连接中…' : '连接'),
                    ),
                    const SizedBox(height: 14),

                    // 实时预览最终请求地址,排查连通性问题时很省事
                    _TargetPreview(host: _host, port: _port),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 连接失败原因。
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('connect_error'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// 实时显示将要连接的 WS 地址。
class _TargetPreview extends StatelessWidget {
  const _TargetPreview({required this.host, required this.port});

  final TextEditingController host;
  final TextEditingController port;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([host, port]),
      builder: (context, _) {
        final parsed = ConnectionSettings.parseHostInput(host.text);
        final hostText = parsed.host.isEmpty ? '未填写' : parsed.host;
        final portText = (parsed.port ?? int.tryParse(port.text.trim()))
            ?.toString() ??
            '?';
        return Text(
          'ws://$hostText:$portText${ConnectionSettings.wsPath}',
          key: const Key('connect_target_preview'),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        );
      },
    );
  }
}
