import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../files/storage_permission.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_migration.dart';
import '../instance/instance_scope.dart';
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
  bool _migratingInstances = false;
  Completer<void>? _resumeWaiter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBattery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeWaiter?.complete();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统电池设置页返回前台时刷新状态。
    if (state == AppLifecycleState.resumed) _refreshBattery();
    if (state == AppLifecycleState.resumed) {
      final waiter = _resumeWaiter;
      _resumeWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
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

  Future<void> _migrateInstances() async {
    if (_migratingInstances) return;
    setState(() => _migratingInstances = true);
    final instances = InstanceScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await _ensureMigrationStoragePermission()) return;
      if (!mounted) return;
      final result = await showDialog<InstanceMigrationResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ManualInstanceMigrationDialog(),
      );
      if (!mounted) return;
      if (result == null) return;
      await instances.init();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_migrationMessage(context, result))),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('settings.storage.migrateFailed', {
              'error': error.toString(),
            }),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _migratingInstances = false);
    }
  }

  Future<bool> _ensureMigrationStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('settings.storage.permissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
    if (go != true) return false;
    final result = await StoragePermission.request();
    if (result == null) {
      // API >= 30: intent-based flow, wait for resume from system settings
      final resumeWaiter = Completer<void>();
      _resumeWaiter = resumeWaiter;
      await resumeWaiter.future;
      await _waitForStoragePermissionGranted();
    }
    if (!mounted) return false;
    return StoragePermission.isGranted();
  }

  Future<void> _waitForStoragePermissionGranted() async {
    for (var i = 0; mounted && i < 25; i++) {
      if (await StoragePermission.isGranted()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  String _migrationMessage(
    BuildContext context,
    InstanceMigrationResult result,
  ) {
    if (!result.hasWork) {
      return context.tr('settings.storage.migrateNoData');
    }
    if (!result.success) {
      return context.tr('settings.storage.migratePartial', {
        'migrated': '${result.migrated}',
        'skipped': '${result.skipped}',
        'failed': '${result.failed}',
      });
    }
    return context.tr('settings.storage.migrateSuccess', {
      'migrated': '${result.migrated}',
      'skipped': '${result.skipped}',
    });
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
          _sectionHeader(theme, context.tr('settings.section.storage')),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(context.tr('settings.storage.migrateTitle')),
            subtitle: Text(context.tr('settings.storage.migrateSubtitle')),
            trailing: _migratingInstances
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: _migrateInstances,
                    child: Text(context.tr('settings.storage.migrateAction')),
                  ),
            onTap: _migratingInstances ? null : _migrateInstances,
          ),
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

class _ManualInstanceMigrationDialog extends StatefulWidget {
  const _ManualInstanceMigrationDialog();

  @override
  State<_ManualInstanceMigrationDialog> createState() =>
      _ManualInstanceMigrationDialogState();
}

class _ManualInstanceMigrationDialogState
    extends State<_ManualInstanceMigrationDialog> {
  int _processed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrate());
  }

  Future<void> _migrate() async {
    final result = await InstanceMigration.migrateLegacyInstances(
      onProgress: (processed, total) {
        if (!mounted) return;
        setState(() {
          _processed = processed;
          _total = total;
        });
      },
    );
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? null : _processed / _total;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircularProgressIndicator(value: progress),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    _total == 0
                        ? context.tr('settings.storage.migrating')
                        : context.tr('settings.storage.migratingProgress', {
                            'processed': '$_processed',
                            'total': '$_total',
                          }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.tr('settings.storage.migratingDoNotClose')),
          ],
        ),
      ),
    );
  }
}
