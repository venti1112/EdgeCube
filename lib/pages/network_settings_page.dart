import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/network_store.dart';
import '../i18n/locale_scope.dart';
import '../net/msl_mirror.dart';

/// 网络设置页面：控制是否使用镜像源（MSL 开服器）下载服务端。
///
/// 开启后，新建实例下载服务端时优先通过 MSL 镜像源加速；镜像不可用时
/// 自动回退官方源。
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  bool _useMirror = false;
  String _backendApiBaseUrl = NetworkStore.defaultBackendApiBaseUrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await NetworkStore.loadUseMirror();
    final apiUrl = await NetworkStore.loadBackendApiBaseUrl();
    if (!mounted) return;
    setState(() {
      _useMirror = v;
      _backendApiBaseUrl = apiUrl;
      _loaded = true;
    });
  }

  Future<void> _onToggle(bool value) async {
    setState(() => _useMirror = value);
    await NetworkStore.saveUseMirror(value);
  }

  Future<void> _showBackendUrlDialog() async {
    final controller = TextEditingController(text: _backendApiBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('network.backendApiUrl')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('network.backendApiUrlWarning'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'URL',
              ),
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
    if (result != null && result != _backendApiBaseUrl) {
      setState(() => _backendApiBaseUrl = result);
      await NetworkStore.saveBackendApiBaseUrl(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('network.title'))),
      body: ListView(
        children: [
          _sectionHeader(theme, context.tr('network.downloadSource')),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: Text(context.tr('network.useMirror')),
            subtitle: Text(context.tr('network.useMirrorDesc')),
            value: _useMirror,
            onChanged: _loaded ? _onToggle : null,
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('network.backendApiUrl')),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(context.tr('network.backendApiUrl')),
            subtitle: Text(_backendApiBaseUrl,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _loaded ? _showBackendUrlDialog : null,
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('network.aboutMirror')),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/msl_logo.png',
                width: 40,
                height: 40,
              ),
            ),
            title: Text(context.tr('network.mirrorByMsl')),
            subtitle: Text(context.tr('network.mirrorSite')),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse(MslMirror.officialSite),
              mode: LaunchMode.externalApplication,
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
