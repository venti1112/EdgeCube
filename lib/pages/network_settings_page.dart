import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/network_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../net/msl_mirror.dart';
import '../online/online_service.dart';
import '../server/proot_service.dart';

/// 网络设置页面：镜像源、自定义 DNS、更新检查与运行环境下载地址。
///
/// 开启镜像源后，新建实例下载服务端时优先通过 MSL 镜像源加速；
/// 镜像不可用时自动回退官方源。
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  bool _useMirror = false;
  bool _loaded = false;

  final _dnsController = TextEditingController();
  String _dnsOriginal = '';
  bool _dnsLoaded = false;

  bool _enableBetaUpdates = true;
  bool _betaLoaded = false;

  String _updateCheckUrl = '';
  bool _updateCheckLoaded = false;
  bool _updateCheckIsCustom = false;

  String _ecpkgCatalogUrl = '';
  bool _ecpkgCatalogLoaded = false;
  bool _ecpkgCatalogIsCustom = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadDns();
    _loadBetaUpdates();
    _loadUpdateCheckUrl();
    _loadEcpkgCatalogUrl();
  }

  Future<void> _load() async {
    final v = await NetworkStore.loadUseMirror();
    if (!mounted) return;
    setState(() {
      _useMirror = v;
      _loaded = true;
    });
  }

  Future<void> _onToggle(bool value) async {
    setState(() => _useMirror = value);
    await NetworkStore.saveUseMirror(value);
  }

  Future<void> _loadDns() async {
    final v = await NetworkStore.loadCustomDns();
    if (!mounted) return;
    setState(() {
      _dnsController.text = v;
      _dnsOriginal = v;
      _dnsLoaded = true;
    });
  }

  /// 校验 DNS 字符串：逗号分隔的 IP 地址，至少一个有效项。
  bool _validateDns(String text) {
    final parts = text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final ips = parts.toList();
    if (ips.isEmpty) return false;
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
    for (final ip in ips) {
      if (!ipv4.hasMatch(ip) && !ipv6.hasMatch(ip)) return false;
    }
    return true;
  }

  Future<void> _saveDns() async {
    final text = _dnsController.text.trim();
    if (!_validateDns(text)) {
      showErrorDialog(context, context.tr('network.dnsInvalid'));
      return;
    }
    await NetworkStore.saveCustomDns(text);
    // 立即同步到所有 proot rootfs 的 /etc/resolv.conf
    try {
      await const ProotService().updateProotDns();
    } catch (_) {}
    setState(() => _dnsOriginal = text);
  }

  Future<void> _resetDns() async {
    const defaults = '8.8.8.8,1.1.1.1';
    _dnsController.text = defaults;
    await NetworkStore.saveCustomDns(defaults);
    // 立即同步到所有 proot rootfs 的 /etc/resolv.conf
    try {
      await const ProotService().updateProotDns();
    } catch (_) {}
    setState(() => _dnsOriginal = defaults);
  }

  // ── 测试版更新 ──

  Future<void> _loadBetaUpdates() async {
    final value = await NetworkStore.loadBetaUpdates();
    if (!mounted) return;
    setState(() {
      _enableBetaUpdates = value;
      _betaLoaded = true;
    });
  }

  Future<void> _saveBetaUpdates(bool value) async {
    setState(() => _enableBetaUpdates = value);
    await NetworkStore.saveBetaUpdates(value);
  }

  // ── 更新检查地址 ──

  Future<void> _loadUpdateCheckUrl() async {
    final urls = await NetworkStore.loadUpdateCheckUrls();
    if (!mounted) return;
    setState(() {
      _updateCheckIsCustom = urls.isNotEmpty;
      _updateCheckUrl = urls.isNotEmpty
          ? urls.first
          : OnlineService.defaultUpdateCheckUrls.first;
      _updateCheckLoaded = true;
    });
  }

  Future<void> _saveUpdateCheckUrl(String? url) async {
    if (url != null && url.isNotEmpty) {
      await NetworkStore.saveUpdateCheckUrls([url]);
    } else {
      await NetworkStore.saveUpdateCheckUrls([]);
    }
    await _loadUpdateCheckUrl();
  }

  // ── 运行环境下载地址 ──

  Future<void> _loadEcpkgCatalogUrl() async {
    final urls = await NetworkStore.loadEcpkgCatalogUrls();
    if (!mounted) return;
    setState(() {
      _ecpkgCatalogIsCustom = urls.isNotEmpty;
      _ecpkgCatalogUrl = urls.isNotEmpty
          ? urls.first
          : OnlineService.defaultEcpkgCatalogUrls.first;
      _ecpkgCatalogLoaded = true;
    });
  }

  Future<void> _saveEcpkgCatalogUrl(String? url) async {
    if (url != null && url.isNotEmpty) {
      await NetworkStore.saveEcpkgCatalogUrls([url]);
    } else {
      await NetworkStore.saveEcpkgCatalogUrls([]);
    }
    await _loadEcpkgCatalogUrl();
  }

  // ── URL 编辑对话框 ──

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
              context.tr('network.urlEditHint'),
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
    }
  }

  @override
  void dispose() {
    _dnsController.dispose();
    super.dispose();
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
          _sectionHeader(theme, context.tr('network.dns')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              context.tr('network.dnsDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dnsController,
                    decoration: InputDecoration(
                      labelText: context.tr('network.dns'),
                      hintText: context.tr('network.dnsHint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: const Icon(Icons.dns_outlined),
                    ),
                    enabled: _dnsLoaded,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: (_dnsLoaded &&
                          _dnsController.text.trim() != _dnsOriginal)
                      ? _saveDns
                      : null,
                  child: Text(context.tr('common.save')),
                ),
              ],
            ),
          ),
          if (_dnsLoaded &&
              _dnsController.text.trim() != '8.8.8.8,1.1.1.1')
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _resetDns,
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text(context.tr('network.dnsReset')),
                ),
              ),
            ),
          const Divider(),
          _sectionHeader(theme, context.tr('network.updateSection')),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: Text(context.tr('settings.enableBetaUpdates')),
            subtitle: Text(context.tr('settings.enableBetaUpdatesDesc')),
            value: _enableBetaUpdates,
            onChanged: _betaLoaded ? _saveBetaUpdates : null,
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(context.tr('network.updateCheckUrl')),
            subtitle: Text(
              _updateCheckLoaded
                  ? (_updateCheckIsCustom
                      ? _updateCheckUrl
                      : context.tr('network.useDefaultUrl'))
                  : context.tr('common.loading'),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updateCheckIsCustom)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _saveUpdateCheckUrl(null),
                  ),
                const Icon(Icons.edit_outlined, size: 18),
              ],
            ),
            onTap: _updateCheckLoaded
                ? () => _editUrl(
                      title: context.tr('network.updateCheckUrl'),
                      hint: 'URL',
                      currentValue: _updateCheckUrl,
                      onSave: (v) => _saveUpdateCheckUrl(v),
                    )
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(context.tr('network.ecpkgCatalogUrl')),
            subtitle: Text(
              _ecpkgCatalogLoaded
                  ? (_ecpkgCatalogIsCustom
                      ? _ecpkgCatalogUrl
                      : context.tr('network.useDefaultUrl'))
                  : context.tr('common.loading'),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_ecpkgCatalogIsCustom)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _saveEcpkgCatalogUrl(null),
                  ),
                const Icon(Icons.edit_outlined, size: 18),
              ],
            ),
            onTap: _ecpkgCatalogLoaded
                ? () => _editUrl(
                      title: context.tr('network.ecpkgCatalogUrl'),
                      hint: 'URL',
                      currentValue: _ecpkgCatalogUrl,
                      onSave: (v) => _saveEcpkgCatalogUrl(v),
                    )
                : null,
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
