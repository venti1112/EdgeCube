import 'package:flutter/material.dart';

import '../account/account_scope.dart';
import '../i18n/locale_scope.dart';
import '../online/online_service.dart';

/// 在线服务设置页面：提供总开关控制所有在线服务的启用状态。
///
/// 需要连接外部服务器的功能。后续实际在线服务在此页面中添加。
class OnlineServicesPage extends StatefulWidget {
  const OnlineServicesPage({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  State<OnlineServicesPage> createState() => _OnlineServicesPageState();
}

class _OnlineServicesPageState extends State<OnlineServicesPage> {
  bool _switching = false;

  OnlineService get _svc => widget.onlineService;

  Future<void> _onToggle(bool value) async {
    // 关闭在线服务且当前已登录：先弹窗确认，确认后「先登出、再关闭」。
    // 顺序很关键——登出须在在线服务仍启用时进行，才能向后端发出登出请求
    // （关闭后账号功能整体不可用，logout 将只清本地而不请求后端）。
    if (!value) {
      final account = AccountScope.of(context);
      if (account.isLoggedIn) {
        final confirmed = await _confirmLogoutOnDisable();
        if (confirmed != true) {
          // 取消：保持开启状态，重建让开关回到「开」。
          if (mounted) setState(() {});
          return;
        }
        setState(() => _switching = true);
        try {
          await account.logout();
          await _svc.setEnabled(false);
        } finally {
          if (mounted) setState(() => _switching = false);
        }
        return;
      }
    }

    setState(() => _switching = true);
    try {
      await _svc.setEnabled(value);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// 关闭在线服务前的确认弹窗，提示将同时退出登录。
  Future<bool?> _confirmLogoutOnDisable() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('online.logoutOnDisable.title')),
        content: Text(ctx.tr('online.logoutOnDisable.content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('online.logoutOnDisable.confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('online.title'))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              context.tr('online.masterSwitch'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: Text(context.tr('online.enableService')),
            subtitle: Text(context.tr('online.disableHint')),
            value: _svc.enabled,
            onChanged: _switching ? null : _onToggle,
          ),
          if (_svc.enabled && _svc.deviceId != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.tr('online.deviceIdSection'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(context.tr('online.deviceId')),
              subtitle: SelectableText(
                _svc.deviceId!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              context.tr('online.serviceList'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(context.tr('online.noMoreServices')),
            subtitle: Text(context.tr('online.comingSoon')),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
