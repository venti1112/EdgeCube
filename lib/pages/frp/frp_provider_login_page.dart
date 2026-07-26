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

/// 供应商登录页：已存 token 自动验证进入；否则按供应商提供浏览器授权登录
/// 或令牌粘贴登录。MSL/OpenFrp/ChmlFrp 走浏览器登录，SakuraFrp/ME Frp
/// 走令牌粘贴登录。
class FrpProviderLoginPage extends StatefulWidget {
  const FrpProviderLoginPage({super.key, required this.provider});

  final FrpProvider provider;

  @override
  State<FrpProviderLoginPage> createState() => _FrpProviderLoginPageState();
}

class _FrpProviderLoginPageState extends State<FrpProviderLoginPage> {
  final _tokenField = TextEditingController();

  bool _busy = false;
  bool _autoLoginTried = false;

  // 浏览器授权登录会话状态。
  FrpBrowserLoginSession? _browserSession;
  bool _polling = false;

  bool get _useBrowserLogin => widget.provider.supportsBrowserLogin;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _polling = false;
    _tokenField.dispose();
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
      await FrpProviderService.saveAccount(widget.provider, account);
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
      } on FrpApiException catch (e) {
        // 致命错误（响应字段缺失/解密失败等）：UUID 已被消费，停止轮询并报错。
        setState(() {
          _polling = false;
          _browserSession = null;
        });
        _showError(e);
        return;
      } catch (_) {
        // 单次轮询失败（网络抖动等）不中断，继续等待。
      }
    }
    // 超时未授权：复位并弹窗提示。
    if (mounted && _polling) {
      setState(() {
        _polling = false;
        _browserSession = null;
      });
      showErrorDialog(context, context.tr('frp.browserLoginExpired'));
    }
  }

  Future<void> _completeBrowserLogin(String token) async {
    try {
      final account = await FrpProviderService.userInfo(widget.provider, token);
      await FrpProviderService.saveToken(widget.provider, token);
      await FrpProviderService.saveAccount(widget.provider, account);
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

                  _buildLoginCard(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginCard(ThemeData theme) {
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
            if (_useBrowserLogin) ...[
              _buildBrowserSection(theme),
              // 浏览器等待授权时，操作按钮在 section 内提供，隐藏底部主按钮。
              if (!_polling) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _startBrowserLogin,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_browser, size: 18),
                    label: Text(context.tr('frp.browserLoginStart')),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _loginWithToken,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 18),
                  label: Text(context.tr('frp.login')),
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
        // 设备码流程（ChmlFrp）：展示用户短码，供手动输入场景使用。
        if (_browserSession?.userCode.isNotEmpty == true) ...[
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
                  context.tr('frp.deviceCodeLabel'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _browserSession!.userCode,
                  style: theme.textTheme.headlineSmall?.copyWith(
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
