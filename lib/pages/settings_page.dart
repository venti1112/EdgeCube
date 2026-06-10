import 'dart:io';

import 'package:flutter/material.dart';

import '../server/power_service.dart';
import '../theme/theme_scope.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeScope = ThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionHeader(theme, '外观'),
          RadioGroup<ThemeMode>(
            groupValue: themeScope.themeMode,
            onChanged: (mode) {
              if (mode != null) themeScope.setThemeMode(mode);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('跟随系统'),
                  secondary: Icon(Icons.brightness_auto),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('深色模式'),
                  secondary: Icon(Icons.dark_mode),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('浅色模式'),
                  secondary: Icon(Icons.light_mode),
                  value: ThemeMode.light,
                ),
              ],
            ),
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            _sectionHeader(theme, '后台保活'),
            _buildBatteryTile(theme),
          ],
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
