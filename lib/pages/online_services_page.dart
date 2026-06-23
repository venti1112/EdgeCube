import 'package:flutter/material.dart';

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
    setState(() => _switching = true);
    try {
      await _svc.setEnabled(value);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
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
