import 'dart:io';

import 'package:flutter/material.dart';

import '../online/online_service.dart';
import '../server/power_service.dart';
import '../theme/theme_scope.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';
import 'online_services_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool _ignoringBattery = true;
  bool _batteryLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBattery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统电池设置页返回前台时刷新状态。
    if (state == AppLifecycleState.resumed) _refreshBattery();
  }

  Future<void> _refreshBattery() async {
    final ignoring = await PowerService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _ignoringBattery = ignoring;
      _batteryLoaded = true;
    });
  }

  Future<void> _requestIgnoreBattery() async {
    await PowerService.requestIgnoreBatteryOptimizations();
    // 请求后立即刷新一次；返回前台时还会再刷新。
    await _refreshBattery();
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.light:
        return '浅色模式';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionHeader(theme, '外观'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观设置'),
            subtitle: Text(_themeModeLabel(themeScope.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsPage(),
                ),
              );
            },
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            _sectionHeader(theme, '后台保活'),
            _buildBatteryTile(theme),
          ],
          const Divider(),
          _sectionHeader(theme, '在线服务'),
          ListenableBuilder(
            listenable: widget.onlineService,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('在线服务'),
              subtitle: Text(widget.onlineService.enabled ? '已启用' : '已关闭'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OnlineServicesPage(
                      onlineService: widget.onlineService,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          _sectionHeader(theme, '其他'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('版本信息、开源许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AboutPage(),
                ),
              );
            },
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

  Widget _buildBatteryTile(ThemeData theme) {
    final String subtitle;
    final Widget? trailing;
    if (!_batteryLoaded) {
      subtitle = '检查中…';
      trailing = null;
    } else if (_ignoringBattery) {
      subtitle = '已加入白名单，锁屏后服务端更不易被系统结束';
      trailing = const Icon(Icons.check_circle, color: Colors.green);
    } else {
      subtitle = '未加入白名单，锁屏或退到后台时服务端可能被系统结束';
      trailing = FilledButton.tonal(
        onPressed: _requestIgnoreBattery,
        child: const Text('去设置'),
      );
    }

    return ListTile(
      leading: const Icon(Icons.battery_saver),
      title: const Text('忽略电池优化'),
      subtitle: Text(subtitle),
      trailing: trailing,
      // 已在白名单中时无需再申请；点击整行等同于点击「去设置」。
      onTap: (!_batteryLoaded || _ignoringBattery) ? null : _requestIgnoreBattery,
    );
  }
}
