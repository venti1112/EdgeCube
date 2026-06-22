import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/network_store.dart';
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('网络设置')),
      body: ListView(
        children: [
          _sectionHeader(theme, '下载源'),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('使用镜像源下载服务端'),
            subtitle: const Text(
              '开启后通过 MSL 镜像源加速下载，国内网络更快；镜像不可用时自动回退官方源',
            ),
            value: _useMirror,
            onChanged: _loaded ? _onToggle : null,
          ),
          const Divider(),
          _sectionHeader(theme, '关于镜像源'),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/msl_logo.png',
                width: 40,
                height: 40,
              ),
            ),
            title: const Text('镜像源由 MSL 开服器提供'),
            subtitle: const Text('mslmc.cn · 点击访问官网'),
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
