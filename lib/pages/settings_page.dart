import 'dart:io';

import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import '../online/online_service.dart';
import '../server/power_service.dart';
import '../theme/theme_scope.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';
import 'language_settings_page.dart';
import 'network_settings_page.dart';
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

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return context.tr('themeMode.system');
      case ThemeMode.dark:
        return context.tr('themeMode.dark');
      case ThemeMode.light:
        return context.tr('themeMode.light');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeScope = ThemeScope.of(context);
    final localeScope = LocaleScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.title'))),
      body: ListView(
        children: [
          _sectionHeader(theme, context.tr('settings.section.appearance')),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(context.tr('settings.appearance.title')),
            subtitle: Text(_themeModeLabel(context, themeScope.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(context.tr('settings.language.title')),
            subtitle: Text(
              localeScope.currentLanguageName ??
                  context.tr('common.followSystem'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LanguageSettingsPage()),
              );
            },
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            _sectionHeader(theme, context.tr('settings.section.keepAlive')),
            _buildBatteryTile(context, theme),
          ],
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.online')),
          ListenableBuilder(
            listenable: widget.onlineService,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(context.tr('settings.online.title')),
              subtitle: Text(
                widget.onlineService.enabled
                    ? context.tr('settings.online.enabled')
                    : context.tr('settings.online.disabled'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        OnlineServicesPage(onlineService: widget.onlineService),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.network')),
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: Text(context.tr('settings.network.title')),
            subtitle: Text(context.tr('settings.network.subtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NetworkSettingsPage()),
              );
            },
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.other')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('settings.about.title')),
            subtitle: Text(context.tr('settings.about.subtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutPage()));
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

  Widget _buildBatteryTile(BuildContext context, ThemeData theme) {
    final String subtitle;
    final Widget? trailing;
    if (!_batteryLoaded) {
      subtitle = context.tr('settings.battery.checking');
      trailing = null;
    } else if (_ignoringBattery) {
      subtitle = context.tr('settings.battery.whitelisted');
      trailing = const Icon(Icons.check_circle, color: Colors.green);
    } else {
      subtitle = context.tr('settings.battery.notWhitelisted');
      trailing = FilledButton.tonal(
        onPressed: _requestIgnoreBattery,
        child: Text(context.tr('common.goToSettings')),
      );
    }

    return ListTile(
      leading: const Icon(Icons.battery_saver),
      title: Text(context.tr('settings.battery.title')),
      subtitle: Text(subtitle),
      trailing: trailing,
      // 已在白名单中时无需再申请；点击整行等同于点击「去设置」。
      onTap: (!_batteryLoaded || _ignoringBattery)
          ? null
          : _requestIgnoreBattery,
    );
  }
}
