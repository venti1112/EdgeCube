import 'package:flutter/material.dart';

import '../account/account_controller.dart';
import '../account/account_models.dart';
import '../account/account_scope.dart';
import '../i18n/locale_scope.dart';
import '../online/online_service.dart';
import 'account_verify_page.dart';
import 'online_services_page.dart';

/// 账号页：未登录时展示「登录 / 注册」表单，已登录时展示个人资料与登出。
///
/// 通过 [AccountScope] 读取全局 [AccountController]，并用 [ListenableBuilder]
/// 监听登录态：登录 / 登出后自动在同一页面内切换视图。
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('account.title'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: account,
          builder: (context, _) {
            // 硬性 gating：未启用在线服务时，账号功能整体不可用，只展示引导。
            if (!account.available) {
              return _OnlineRequiredView(onlineService: account.onlineService);
            }
            return account.isLoggedIn
                ? _ProfileView(account: account)
                : const _AuthView();
          },
        ),
      ),
    );
  }
}

// ─────────────────────── 未启用在线服务：功能不可用 ───────────────────────

/// 在线服务未启用时的引导视图。
///
/// 账号功能依赖「在线服务」总开关：未启用时不展示任何登录 / 注册 / 资料内容，
/// 仅提供一个入口引导用户前往「在线服务」页面开启。
class _OnlineRequiredView extends StatelessWidget {
  const _OnlineRequiredView({required this.onlineService});

  final OnlineService? onlineService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('account.online.title'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('account.online.desc'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onlineService == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              OnlineServicesPage(onlineService: onlineService!),
                        ),
                      );
                    },
              icon: const Icon(Icons.cloud_outlined, size: 18),
              label: Text(context.tr('account.online.action')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 已登录：个人资料 ───────────────────────────

class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.account});

  final AccountController account;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.account.logout();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.success && result.message.isNotEmpty
                ? result.message
                : context.tr('account.loggedOut'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.account.user;
    final session = widget.account.session;
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    _avatarLetter(user),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _infoTile(
                theme,
                Icons.badge_outlined,
                context.tr('account.field.username'),
                user.username,
              ),
              const Divider(height: 1),
              _infoTile(
                theme,
                Icons.person_outline,
                context.tr('account.field.nickname'),
                user.nickname,
              ),
              const Divider(height: 1),
              _infoTile(
                theme,
                Icons.email_outlined,
                context.tr('account.field.email'),
                user.email,
              ),
              if (session != null && session.device.isNotEmpty) ...[
                const Divider(height: 1),
                _infoTile(
                  theme,
                  Icons.smartphone_outlined,
                  context.tr('account.field.device'),
                  session.device,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout, size: 18),
            label: Text(context.tr('account.logout')),
          ),
        ),
      ],
    );
  }

  String _avatarLetter(AccountUser user) {
    final name = user.displayName.trim();
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  Widget _infoTile(ThemeData theme, IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: SelectableText(value, style: theme.textTheme.bodyLarge),
    );
  }
}

// ─────────────────────────── 未登录：登录 / 注册 ───────────────────────────

class _AuthView extends StatefulWidget {
  const _AuthView();

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          tabs: [
            Tab(text: context.tr('account.tab.login')),
            Tab(text: context.tr('account.tab.register')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _LoginForm(onGoRegister: () => _tab.animateTo(1)),
              _RegisterForm(onRegistered: () => _tab.animateTo(0)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 登录表单。
class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.onGoRegister});

  final VoidCallback onGoRegister;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm>
    with AutomaticKeepAliveClientMixin {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = _account.text.trim();
    final password = _password.text;
    if (account.isEmpty || password.isEmpty) {
      _snack(context.tr('account.error.emptyFields'));
      return;
    }
    setState(() => _submitting = true);
    final controller = AccountScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await controller.login(
        account: account,
        password: password,
      );
      if (!mounted) return;
      if (result.success) {
        // 登录成功后本页由 ListenableBuilder 自动切换为个人资料视图。
        return;
      }
      // 邮箱未验证：引导去验证页，验证成功后自动重试登录。
      if (result.code == 403) {
        final verified = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                AccountVerifyPage(account: account, password: password),
          ),
        );
        if (verified == true && mounted) {
          await controller.login(account: account, password: password);
        }
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _account,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.tr('account.field.account'),
            helperText: context.tr('account.field.accountHelper'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: context.tr('account.field.password'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
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
                : Text(context.tr('account.login')),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.tr('account.noAccount')),
            TextButton(
              onPressed: widget.onGoRegister,
              child: Text(context.tr('account.tab.register')),
            ),
          ],
        ),
      ],
    );
  }
}

/// 注册表单。
class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.onRegistered});

  /// 注册并验证成功后回调（切回登录 Tab）。
  final VoidCallback onRegistered;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm>
    with AutomaticKeepAliveClientMixin {
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  static final RegExp _usernameRe = RegExp(r'^[a-zA-Z0-9_.-]+$');
  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _username.dispose();
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 前端预校验，对齐后端 binding 规则，减少无效请求。
  String? _validate() {
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (username.length < 3 || username.length > 64) {
      return context.tr('account.error.usernameLength');
    }
    if (!_usernameRe.hasMatch(username)) {
      return context.tr('account.error.usernameChars');
    }
    if (!_emailRe.hasMatch(email)) {
      return context.tr('account.error.emailFormat');
    }
    if (password.length < 6) {
      return context.tr('account.error.passwordLength');
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      _snack(error);
      return;
    }
    setState(() => _submitting = true);
    final controller = AccountScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final account = _email.text.trim();
    final password = _password.text;
    try {
      final result = await controller.register(
        username: _username.text.trim(),
        email: account,
        password: password,
        nickname: _nickname.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (!result.success) return;
      // 注册成功：进入验证页完成邮箱验证。
      final verified = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              AccountVerifyPage(account: account, password: password),
        ),
      );
      if (verified == true && mounted) {
        widget.onRegistered();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.tr('account.field.username'),
            helperText: context.tr('account.field.usernameHelper'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nickname,
          decoration: InputDecoration(
            labelText: context.tr('account.field.nicknameOptional'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.tr('account.field.email'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: context.tr('account.field.password'),
            helperText: context.tr('account.field.passwordHelper'),
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
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
                : Text(context.tr('account.register')),
          ),
        ),
      ],
    );
  }
}
