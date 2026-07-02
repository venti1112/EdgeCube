import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/account_scope.dart';
import '../i18n/locale_scope.dart';

/// 邮箱验证码验证页。
///
/// 由注册成功后、或登录返回「邮箱未验证(403)」时进入。[account] 与 [password]
/// 由上游流程带入，无需用户重新输入；用户在此输入 6 位验证码完成验证，
/// 也可在冷却结束后重新发送验证码。验证成功后 `Navigator.pop(true)` 返回。
class AccountVerifyPage extends StatefulWidget {
  const AccountVerifyPage({
    super.key,
    required this.account,
    required this.password,
  });

  /// 邮箱或用户名（后端验证接口以此定位用户）。
  final String account;

  /// 账号密码（后端验证接口需二次校验密码）。
  final String password;

  @override
  State<AccountVerifyPage> createState() => _AccountVerifyPageState();
}

class _AccountVerifyPageState extends State<AccountVerifyPage> {
  final _code = TextEditingController();
  bool _submitting = false;
  bool _resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _code.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      _snack(context.tr('account.error.codeFormat'));
      return;
    }
    setState(() => _submitting = true);
    final account = AccountScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await account.verify(
        account: widget.account,
        password: widget.password,
        code: code,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success) navigator.pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final account = AccountScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await account.resendVerification(
        account: widget.account,
        password: widget.password,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success) _startCooldown();
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = _resendCooldown == 0 && !_resending;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('account.verify.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('account.verify.hint', {
                          'account': widget.account,
                        }),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: context.tr('account.verify.codeLabel'),
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('account.verify.submit')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: canResend ? _resend : null,
                child: Text(
                  _resendCooldown > 0
                      ? context.tr('account.verify.resendCooldown', {
                          'seconds': '$_resendCooldown',
                        })
                      : context.tr('account.verify.resend'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
