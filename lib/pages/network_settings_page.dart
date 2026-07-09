import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/network_store.dart';
import '../i18n/locale_scope.dart';
import '../net/msl_mirror.dart';

/// 网络设置页面：控制是否使用镜像源（MSL 开服器）下载服务端。
///
/// 开启后，新建实例下载服务端时优先通过 MSL 镜像源加速；镜像不可用时
/// 自动回退官方源。
///
/// 在线服务相关配置（后端地址、更新检查、运行环境下载）在「在线服务」页面中。
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadDns();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('network.dnsInvalid'))),
      );
      return;
    }
    await NetworkStore.saveCustomDns(text);
    setState(() => _dnsOriginal = text);
  }

  Future<void> _resetDns() async {
    const defaults = '8.8.8.8,1.1.1.1';
    _dnsController.text = defaults;
    await NetworkStore.saveCustomDns(defaults);
    setState(() => _dnsOriginal = defaults);
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
