import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../frp/frp_models.dart';
import '../../frp/frp_provider.dart';
import '../../frp/frp_provider_service.dart';
import '../../i18n/locale_scope.dart';
import '../../widgets/error_dialog.dart';
import 'frp_provider_tunnels_page.dart';

/// 供应商登录页：已存 token 自动验证进入；否则提供 token 粘贴、
/// 邮箱/用户名 + 密码，或浏览器授权登录（视供应商支持）。
class FrpProviderLoginPage extends StatefulWidget {
  const FrpProviderLoginPage({super.key, required this.provider});

  final FrpProvider provider;

  @override
  State<FrpProviderLoginPage> createState() => _FrpProviderLoginPageState();
}

class _FrpProviderLoginPageState extends State<FrpProviderLoginPage> {
  final _tokenField = TextEditingController();
  final _accountField = TextEditingController();
  final _passwordField = TextEditingController();
  final _twoFactorField = TextEditingController();

  bool _busy = false;
  bool _autoLoginTried = false;
  bool _needTwoFactor = false;

  /// true = 主登录方式（浏览器/密码）tab，false = token 粘贴 tab。
  bool _usePrimary = false;

  // 浏览器授权登录会话状态。
  FrpBrowserLoginSession? _browserSession;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _usePrimary = widget.provider.supportsPasswordLogin ||
        widget.provider.supportsBrowserLogin;
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _polling = false;
    _tokenField.dispose();
    _accountField.dispose();
    _passwordField.dispose();
    _twoFactorField.dispose();
    super.dispose();
  }

  /// 已存 token：静默验证，成功直接进入隧道管理页。
  Future<void> _tryAutoLogin() async {
    final token = await FrpProviderService.savedToken(widget.provider);
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _autoLoginTried = true);
      return;
    }
    setState(() => _busy = true);
    try {
      final account = await FrpProviderService.userInfo(widget.provider, token);
      if (!mounted) return;
      _enterTunnelsPage(token, account);
    } catch (_) {
      // token 失效：清除并展示登录表单。
      await FrpProviderService.logout(widget.provider);
      if (mounted) setState(() {});
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _autoLoginTried = true;
        });
      }
    }
  }

  Future<void> _loginWithToken() async {
    final token = _tokenField.text.trim();
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final account = await FrpProviderService.userInfo(widget.provider, token);
      await FrpProviderService.saveToken(widget.provider, token);
      if (!mounted) return;
      _enterTunnelsPage(token, account);
    } on FrpApiException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          LocaleScope.of(context)
              .translations
              .get('frp.networkError', {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithPassword() async {
    final account = _accountField.text.trim();
    final password = _passwordField.text;
    if (account.isEmpty || password.isEmpty) return;
    setState(() => _busy = true);
    try {
      final token = await FrpProviderService.loginWithPassword(
        widget.provider,
        account,
        password,
        twoFactorCode:
            _needTwoFactor ? _twoFactorField.text.trim() : null,
      );
      final info = await FrpProviderService.userInfo(widget.provider, token);
      await FrpProviderService.saveToken(widget.provider, token);
      if (!mounted) return;
      _enterTunnelsPage(token, info);
    } on FrpApiException catch (e) {
      if (!mounted) return;
      if (e.needTwoFactor) {
        setState(() => _needTwoFactor = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('frp.twoFactorRequired')),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        showErrorDialog(context, e.message);
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          LocaleScope.of(context)
              .translations
              .get('frp.networkError', {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 浏览器授权登录 ─────────────────────────────────────────────
  Future<void> _startBrowserLogin() async {
    setState(() => _busy = true);
    try {
      final session =
          await FrpProviderService.createBrowserLogin(widget.provider);
      if (!mounted) return;
      setState(() {
        _browserSession = session;
        _busy = false;
        _polling = true;
      });
      await _launchAuthUrl(session.url);
      unawaited(_pollBrowserLogin());
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showError(e);
      }
    }
  }

  Future<void> _launchAuthUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打开失败时用户可用「复制链接」手动打开。
    }
  }

  /// 每 5s 轮询一次授权结果，最多约 300s（会话/UUID 有效期）。
  /// OpenFrp 远程登录推荐 1 次/5s，MSL 会话同样为 5 分钟，故统一取 5s。
  Future<void> _pollBrowserLogin() async {
    const interval = Duration(seconds: 5);
    const maxAttempts = 60;
    final session = _browserSession;
    if (session == null) return;
    var attempts = 0;
    while (mounted && _polling && attempts < maxAttempts) {
      await Future.delayed(interval);
      if (!mounted || !_polling) return;
      attempts++;
      try {
        final token = await FrpProviderService.pollBrowserLogin(
          widget.provider,
          session,
        );
        if (token != null) {
          await _completeBrowserLogin(token);
          return;
        }
      } catch (_) {
        // 单次轮询失败（网络抖动等）不中断，继续等待。
      }
    }
    // 超时未授权：复位并提示。
    if (mounted && _polling) {
      setState(() {
        _polling = false;
        _browserSession = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('frp.browserLoginExpired'))),
      );
    }
  }

  Future<void> _completeBrowserLogin(String token) async {
    try {
      final account = await FrpProviderService.userInfo(widget.provider, token);
      await FrpProviderService.saveToken(widget.provider, token);
      if (!mounted) return;
      setState(() => _polling = false);
      _enterTunnelsPage(token, account);
    } catch (e) {
      if (mounted) {
        setState(() => _polling = false);
        _showError(e);
      }
    }
  }

  void _cancelBrowserLogin() {
    setState(() {
      _polling = false;
      _browserSession = null;
    });
  }

  Future<void> _reopenAuthLink() async {
    final url = _browserSession?.url;
    if (url != null) await _launchAuthUrl(url);
  }

  Future<void> _copyAuthLink() async {
    final url = _browserSession?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('frp.browserLoginLinkCopied'))),
      );
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    if (e is FrpApiException) {
      showErrorDialog(context, e.message);
    } else {
      showErrorDialog(
        context,
        LocaleScope.of(context)
            .translations
            .get('frp.networkError', {'error': '$e'}),
      );
    }
  }

  void _enterTunnelsPage(String token, FrpAccount account) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FrpProviderTunnelsPage(
          provider: widget.provider,
          token: token,
          account: account,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.provider.displayName)),
      body: SafeArea(
        child: !_autoLoginTried
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.provider.experimental) ...[
                    _buildExperimentalHint(theme),
                    const SizedBox(height: 12),
                  ],
                  _buildLoginCard(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildExperimentalHint(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.science_outlined,
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('frp.experimentalHint'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginCard(ThemeData theme) {
    final supportsPassword = widget.provider.supportsPasswordLogin;
    final supportsBrowser = widget.provider.supportsBrowserLogin;
    final hasPrimary = supportsPassword || supportsBrowser;
    final browserMode = supportsBrowser && _usePrimary;
    final passwordMode = supportsPassword && _usePrimary;
    return Card(
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
                  context.tr('frp.loginTitle'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasPrimary) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(context.tr(supportsBrowser
                        ? 'frp.loginByBrowser'
                        : 'frp.loginByPassword')),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(context.tr('frp.loginByToken')),
                  ),
                ],
                selected: {_usePrimary},
                onSelectionChanged: _polling
                    ? null
                    : (v) => setState(() => _usePrimary = v.first),
              ),
              const SizedBox(height: 16),
            ],
            if (browserMode) ...[
              _buildBrowserSection(theme),
            ] else if (passwordMode) ...[
              TextField(
                controller: _accountField,
                decoration: InputDecoration(
                  labelText: context.tr('frp.username'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordField,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('frp.password'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_needTwoFactor) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _twoFactorField,
                  decoration: InputDecoration(
                    labelText: context.tr('frp.twoFactorCode'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ] else ...[
              TextField(
                controller: _tokenField,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('frp.accessToken'),
                  hintText: context.tr('frp.accessTokenHint'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('frp.tokenHelp.${widget.provider.key}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // 浏览器等待授权时，操作按钮在 section 内提供，隐藏底部主按钮。
            if (!(browserMode && _polling)) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : (browserMode
                          ? _startBrowserLogin
                          : (passwordMode
                              ? _loginWithPassword
                              : _loginWithToken)),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          browserMode ? Icons.open_in_browser : Icons.login,
                          size: 18,
                        ),
                  label: Text(context.tr(
                      browserMode ? 'frp.browserLoginStart' : 'frp.login')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBrowserSection(ThemeData theme) {
    if (!_polling) {
      return Text(
        context.tr('frp.browserLoginHint'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr('frp.browserLoginWaiting'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _reopenAuthLink,
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: Text(context.tr('frp.browserLoginReopen')),
            ),
            OutlinedButton.icon(
              onPressed: _copyAuthLink,
              icon: const Icon(Icons.copy, size: 18),
              label: Text(context.tr('frp.browserLoginCopyLink')),
            ),
            TextButton.icon(
              onPressed: _cancelBrowserLogin,
              icon: const Icon(Icons.close, size: 18),
              label: Text(context.tr('frp.browserLoginCancel')),
            ),
          ],
        ),
      ],
    );
  }
}
