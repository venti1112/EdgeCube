import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../connection/client.dart';
import '../connection/state.dart';
import '../files/dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 平台登录页：浏览器授权登录（MSL / OpenFrp / ChmlFrp）或令牌粘贴登录
/// （Sakura / ME Frp）。
///
/// 三条路径（已存令牌静默验证、浏览器授权、令牌粘贴），**授权请求的发起与轮询在
/// daemon 里**（见 daemon 的 `frp::login`）。本页做的事只有：
///
/// * 进页面时读一次会话状态（`frp.login.status`）—— 用户离开又回来时能接上
///   正在跑的授权；已存令牌则联网复核一次（`frp.account` 带 `verify`）；
/// * 点「浏览器登录」→ `frp.login.start` 拿授权地址 → 用系统浏览器打开；
/// * 订阅 `frp.login` 事件看进度，成功就进隧道管理页；
/// * 取消 / 复制链接 / 重新打开这些按钮。
class FrpLoginPage extends ConsumerStatefulWidget {
  const FrpLoginPage({super.key, required this.providerKey});

  final String providerKey;

  @override
  ConsumerState<FrpLoginPage> createState() => _FrpLoginPageState();
}

class _FrpLoginPageState extends ConsumerState<FrpLoginPage> {
  final _tokenField = TextEditingController();

  StreamSubscription<Map<String, dynamic>>? _events;
  DaemonClient? _boundClient;

  /// 首次检查（正在跑的会话 / 已存令牌）还没出结果时为真。
  bool _checking = true;

  /// 某个 RPC 在飞。
  bool _busy = false;

  /// 当前授权会话（`waiting` 时页面上显示等待区）。
  FrpLoginSession? _session;

  /// 已经问过一次 daemon 的会话状态（冷启动挂载早于 WS 连上时先问不到）。
  bool _savedLoginChecked = false;

  bool get _waiting => _session?.isWaiting ?? false;

  @override
  void initState() {
    super.initState();
    // 授权进度是 daemon 推的：登记订阅意图（未连接时连上后自动补订）
    unawaited(ref.read(connectionProvider.notifier).subscribe(kFrpLoginTopic));
    _bindEvents(ref.read(daemonClientProvider));
    unawaited(_checkSavedLogin());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _tokenField.dispose();
    super.dispose();
  }

  /// 换连接就重挂事件监听（掉线重连后新客户端是另一个实例）。
  void _bindEvents(DaemonClient? client) {
    if (identical(client, _boundClient)) return;
    _boundClient = client;
    unawaited(_events?.cancel());
    _events = client?.events.listen(_onEvent);
  }

  /// `frp.login` 事件：daemon 那边授权有结果了。
  void _onEvent(Map<String, dynamic> event) {
    if (event['topic'] != kFrpLoginTopic) return;
    final data = event['data'];
    if (data is! Map) return;
    final session = FrpLoginSession.fromJson(data.cast<String, dynamic>());
    if (session.provider != widget.providerKey || !mounted) return;
    setState(() => _session = session);
    if (session.isSuccess) {
      _enterTunnels();
    } else if (session.state == FrpLoginState.error) {
      unawaited(showErrorDialog(context, session.message));
    }
  }

  /// 进页面时的两条快路：接上正在跑的授权，或拿已存令牌直接进去。
  Future<void> _checkSavedLogin() async {
    final api = ref.read(frpApiProvider);
    if (api == null) {
      // 还没连上：别当成「没有会话」，等 `daemonClientProvider` 变了再问一次
      if (mounted) setState(() => _checking = false);
      return;
    }
    _savedLoginChecked = true;
    try {
      final session = await api.loginStatus(widget.providerKey);
      if (!mounted) return;
      if (session.isWaiting) {
        setState(() {
          _session = session;
          _checking = false;
        });
        return;
      }
      if (session.isSuccess) {
        _enterTunnels();
        return;
      }
      // 已存令牌：联网复核（验不过 daemon 会顺手清掉本地令牌）
      final status = await api.account(widget.providerKey, verify: true);
      if (!mounted) return;
      if (status.canSkipLogin) {
        _enterTunnels();
        return;
      }
    } on DaemonException catch (error) {
      // 复核失败（断线 / 平台不通）就老实展示登录表单
      debugPrint('自动登录检查失败：$error');
    }
    if (mounted) setState(() => _checking = false);
  }

  /// 发起浏览器授权。`frp.login.start` 一返回，daemon 就已经在轮询了。
  Future<void> _startBrowserLogin() async {
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final FrpLoginSession session;
    try {
      session = await api.loginStart(widget.providerKey);
    } on DaemonException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showErrorDialog(context, describeFrpError(error));
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _busy = false;
    });
    await _openAuthUrl(session.url);
  }

  Future<void> _loginWithToken() async {
    final token = _tokenField.text.trim();
    if (token.isEmpty) return;
    final api = ref.read(frpApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.loginWithToken(widget.providerKey, token);
      if (!mounted) return;
      _enterTunnels();
    } on DaemonException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showErrorDialog(context, describeFrpError(error));
    }
  }

  /// 取消授权：daemon 停轮询、作废会话。
  Future<void> _cancelBrowserLogin() async {
    final api = ref.read(frpApiProvider);
    setState(() => _session = null);
    try {
      await api?.loginCancel(widget.providerKey);
    } on DaemonException {
      // 会话可能刚好已经结束了，取消失败无所谓
    }
  }

  Future<void> _openAuthUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开时用户可以用「复制链接」手动打开
    }
  }

  Future<void> _copyAuthLink() async {
    final url = _session?.url ?? '';
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) showSnack(context, '链接已复制');
  }

  void _enterTunnels() {
    if (!mounted) return;
    context.pushReplacement(
      '/manage/network/tunnels/provider/${widget.providerKey}',
    );
  }

  @override
  Widget build(BuildContext context) {
    // 连接换了（掉线重连）重新挂事件监听；冷启动时页面挂载可能早于连上，
    // 那会儿问不到会话状态，连上后补问一次。
    ref.listen(daemonClientProvider, (_, next) {
      _bindEvents(next);
      if (next != null && !_savedLoginChecked) {
        unawaited(_checkSavedLogin());
      }
    });

    final provider = findFrpProvider(
      ref.watch(frpProvidersProvider).value ?? const [],
      widget.providerKey,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(provider?.displayName ?? '账号登录'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [_buildLoginCard(context, provider)],
            ),
    );
  }

  Widget _buildLoginCard(BuildContext context, FrpProvider? provider) {
    final theme = Theme.of(context);
    if (provider == null) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('未知的映射平台，请返回重新选择。'),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.login, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '账号登录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (provider.browserLogin) ..._browserSection(theme, provider),
            if (provider.tokenLogin) ..._tokenSection(theme, provider),
            if (!provider.browserLogin && !provider.tokenLogin)
              const Text('该平台不需要登录。'),
          ],
        ),
      ),
    );
  }

  List<Widget> _browserSection(ThemeData theme, FrpProvider provider) {
    if (!_waiting) {
      return [
        Text(
          '点击下方按钮，在浏览器中完成账号授权后将自动登录。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _startBrowserLogin,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_browser, size: 18),
          label: const Text('浏览器登录'),
        ),
      ];
    }
    final session = _session!;
    return [
      Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('已打开授权页面，请在浏览器中完成授权…')),
        ],
      ),
      if (session.userCode.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '用户代码（若链接未自动带入，请在浏览器中输入）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                session.userCode,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => unawaited(_openAuthUrl(session.url)),
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('重新打开'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(_copyAuthLink()),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制链接'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(_cancelBrowserLogin()),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('取消'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _tokenSection(ThemeData theme, FrpProvider provider) {
    return [
      TextField(
        key: const Key('frp_access_token'),
        controller: _tokenField,
        enabled: !_busy,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '访问 Token',
          hintText: '从平台官网个人中心复制',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        provider.tokenHelp,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _loginWithToken,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.login, size: 18),
        label: const Text('登录'),
      ),
    ];
  }
}
