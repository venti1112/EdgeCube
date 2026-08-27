import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';

/// 修改账密页:修改当前账户的用户名与密码。
/// 需已连接服务器(持有 Bearer token)方可操作。
class ChangeCredentialsPage extends ConsumerStatefulWidget {
  const ChangeCredentialsPage({super.key});

  @override
  ConsumerState<ChangeCredentialsPage> createState() =>
      _ChangeCredentialsPageState();
}

class _ChangeCredentialsPageState extends ConsumerState<ChangeCredentialsPage> {
  // 修改用户名
  final _newUsernameController = TextEditingController();
  bool _savingUsername = false;

  // 修改密码
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _savingPassword = false;

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 将 DioException 映射为用户可读提示。
  String _authError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return '登录已失效,请重新登录';
    if (status == 403) return '当前来源被服务器拒绝';
    if (status == null && e.type == DioExceptionType.connectionError) {
      return '无法连接服务器';
    }
    return '请求失败:${status ?? e.type.name}';
  }

  Future<void> _changeUsername() async {
    if (_savingUsername) return;
    final client = ref.read(edgecubeClientProvider);
    if (client == null) {
      _snack('未连接服务器,请先在"设置 → 服务器"中连接');
      return;
    }
    final name = _newUsernameController.text.trim();
    if (name.isEmpty || name.length > 64) return _snack('用户名需为 1-64 个字符');

    setState(() => _savingUsername = true);
    try {
      await client.getAuthApi().changeUsername(
            changeUsernameRequest: ChangeUsernameRequest((b) => b
              ..newUsername = name),
          );
      _snack('用户名已修改');
      _newUsernameController.clear();
    } on DioException catch (e) {
      _snack(_authError(e));
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  Future<void> _changePassword() async {
    if (_savingPassword) return;
    final client = ref.read(edgecubeClientProvider);
    if (client == null) {
      _snack('未连接服务器,请先在"设置 → 服务器"中连接');
      return;
    }
    final newPassword = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (newPassword.length < 8 || newPassword.length > 128) {
      return _snack('新密码长度需为 8-128 个字符');
    }
    if (newPassword != confirm) return _snack('两次输入的新密码不一致');

    setState(() => _savingPassword = true);
    try {
      await client.getAuthApi().changePassword(
            changePasswordRequest: ChangePasswordRequest((b) => b
              ..newPassword = newPassword),
          );
      _snack('密码已修改');
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } on DioException catch (e) {
      _snack(_authError(e));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(edgecubeClientProvider) != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('修改账密'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (!connected)
            Card(
              child: ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('未连接服务器'),
                subtitle: const Text('连接服务器后才能修改账密'),
              ),
            )
          else ...[
            _sectionTitle('修改用户名'),
            TextFormField(
              controller: _newUsernameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '新用户名'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingUsername ? null : _changeUsername,
                icon: _savingUsername
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.badge_outlined),
                label: Text(_savingUsername ? '提交中…' : '修改用户名'),
              ),
            ),
            const Divider(height: 40),
            _sectionTitle('修改密码'),
            TextFormField(
              controller: _newPasswordController,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '新密码',
                helperText: '8-128 个字符',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingPassword ? null : _changePassword,
                icon: _savingPassword
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password),
                label: Text(_savingPassword ? '提交中…' : '修改密码'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
}