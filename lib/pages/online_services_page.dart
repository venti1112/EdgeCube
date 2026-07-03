import 'package:flutter/material.dart';

import '../account/account_scope.dart';
import '../i18n/locale_scope.dart';
import '../online/online_service.dart';

/// 在线服务设置页面：提供总开关与控制各在线服务访问地址。
///
/// 需要连接外部服务器的功能。
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
    if (!value) {
      final account = AccountScope.of(context);
      if (account.isLoggedIn) {
        final confirmed = await _confirmLogoutOnDisable();
        if (confirmed != true) {
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

  Future<void> _editUrl({
    required String title,
    required String hint,
    required String currentValue,
    required Future<void> Function(String value) onSave,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('online.urlEditHint'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: hint,
              ),
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(context.tr('common.save')),
          ),
        ],
      ),
    );
    if (result != null && result != currentValue) {
      await onSave(result);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = _svc;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('online.title'))),
      body: ListView(
        children: [
          _sectionHeader(theme, context.tr('online.masterSwitch')),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_outlined),
            title: Text(context.tr('online.enableService')),
            subtitle: Text(context.tr('online.disableHint')),
            value: svc.enabled,
            onChanged: _switching ? null : _onToggle,
          ),
          if (svc.enabled && svc.deviceId != null) ...[
            const Divider(),
            _sectionHeader(theme, context.tr('online.deviceIdSection')),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(context.tr('online.deviceId')),
              subtitle: SelectableText(
                svc.deviceId!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const Divider(),
          _sectionHeader(theme, context.tr('online.serviceUrls')),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(context.tr('online.backendApiUrl')),
            subtitle: Text(
              svc.backendApiBaseUrl,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _editUrl(
              title: context.tr('online.backendApiUrl'),
              hint: 'URL',
              currentValue: svc.backendApiBaseUrl,
              onSave: (v) => svc.setBackendApiBaseUrl(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(context.tr('online.updateCheckUrl')),
            subtitle: Text(
              svc.hasCustomUpdateCheckUrl
                  ? svc.updateCheckUrl
                  : context.tr('online.useDefaultUrl'),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (svc.hasCustomUpdateCheckUrl)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () async {
                      await svc.setUpdateCheckUrl(null);
                      if (mounted) setState(() {});
                    },
                  ),
                const Icon(Icons.edit_outlined, size: 18),
              ],
            ),
            onTap: () => _editUrl(
              title: context.tr('online.updateCheckUrl'),
              hint: 'URL',
              currentValue: svc.updateCheckUrl,
              onSave: (v) => svc.setUpdateCheckUrl(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(context.tr('online.ecpkgCatalogUrl')),
            subtitle: Text(
              svc.hasCustomEcpkgCatalogUrl
                  ? svc.ecpkgCatalogUrl
                  : context.tr('online.useDefaultUrl'),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (svc.hasCustomEcpkgCatalogUrl)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () async {
                      await svc.setEcpkgCatalogUrl(null);
                      if (mounted) setState(() {});
                    },
                  ),
                const Icon(Icons.edit_outlined, size: 18),
              ],
            ),
            onTap: () => _editUrl(
              title: context.tr('online.ecpkgCatalogUrl'),
              hint: 'URL',
              currentValue: svc.ecpkgCatalogUrl,
              onSave: (v) => svc.setEcpkgCatalogUrl(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
