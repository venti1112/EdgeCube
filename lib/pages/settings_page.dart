import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../config/instance_path_store.dart';
import '../config/runtime_pref_store.dart';
import '../config/terminal_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../instance/instance_migration.dart';
import '../instance/instance_scope.dart';
import '../instance/instance_store.dart';
import '../server/power_service.dart';
import '../theme/theme_scope.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';
import 'language_settings_page.dart';
import 'network_settings_page.dart';
import 'storage_management_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool _ignoringBattery = true;
  bool _batteryLoaded = false;
  bool _autoClearLogOnStart = true;
  RuntimePriority _runtimePriority = RuntimePriority.proot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBattery();
    _loadAutoClearLogOnStart();
    _loadRuntimePriority();
  }

  Future<void> _loadRuntimePriority() async {
    final value = await RuntimePrefStore.loadPriority();
    if (mounted) setState(() => _runtimePriority = value);
  }

  Future<void> _saveRuntimePriority(RuntimePriority value) async {
    setState(() => _runtimePriority = value);
    await RuntimePrefStore.savePriority(value);
  }

  String _runtimePriorityLabel(BuildContext context, RuntimePriority p) {
    return p == RuntimePriority.proot
        ? context.tr('settings.runtimePriority.proot')
        : context.tr('settings.runtimePriority.native');
  }

  /// 弹出优先级选择对话框（proot 优先 / 原生优先）。
  Future<void> _pickRuntimePriority() async {
    final selected = await showDialog<RuntimePriority>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('settings.runtimePriority.dialogTitle')),
        children: [
          for (final p in RuntimePriority.values)
            ListTile(
              leading: Icon(
                p == _runtimePriority
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: p == _runtimePriority
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(_runtimePriorityLabel(ctx, p)),
              onTap: () => Navigator.of(ctx).pop(p),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Text(
              ctx.tr('settings.runtimePriority.hint'),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
    if (selected != null) await _saveRuntimePriority(selected);
  }

  Future<void> _loadAutoClearLogOnStart() async {
    final value = await TerminalStore.loadAutoClearLogOnStart();
    if (mounted) setState(() => _autoClearLogOnStart = value);
  }

  Future<void> _saveAutoClearLogOnStart(bool value) async {
    setState(() => _autoClearLogOnStart = value);
    await TerminalStore.saveAutoClearLogOnStart(value);
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
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.console')),
          SwitchListTile(
            secondary: const Icon(Icons.delete_sweep_outlined),
            title: Text(context.tr('settings.console.autoClearLogOnStart')),
            subtitle: Text(
              context.tr('settings.console.autoClearLogOnStartDescription'),
            ),
            value: _autoClearLogOnStart,
            onChanged: _saveAutoClearLogOnStart,
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            _sectionHeader(theme, context.tr('settings.section.keepAlive')),
            _buildBatteryTile(context, theme),
          ],
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.storage')),
          _CustomInstancePathTile(),
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(context.tr('storage.title')),
            subtitle: Text(context.tr('storage.subtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StorageManagementPage(),
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader(theme, context.tr('settings.section.runtime')),
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(context.tr('settings.runtimePriority.title')),
            subtitle: Text(
              context.tr('settings.runtimePriority.subtitle', {
                'value': _runtimePriorityLabel(context, _runtimePriority),
              }),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickRuntimePriority,
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
            leading: const Icon(Icons.group_outlined),
            title: Text(context.tr('settings.community.title')),
            subtitle: Text(context.tr('settings.community.subtitle')),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://qm.qq.com/q/pnCZcmnKIS'),
              mode: LaunchMode.externalApplication,
            ),
          ),
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

/// 「自定义实例文件夹」入口：显示当前 EdgeCube 数据文件夹，支持选择新位置或恢复默认。
///
/// 「实例文件夹」指 EdgeCube 数据文件夹（其下 `instances/` 子目录存放各实例）。
/// 更改路径时会把旧 EdgeCube 文件夹下的全部内容（含 `instances/`）移动到新位置
/// （复用 [InstanceMigration] 的迁移逻辑），完成后持久化新路径并通知
/// [InstanceController] 刷新依赖方（FTP/SSH 根目录同步等）。
class _CustomInstancePathTile extends StatefulWidget {
  const _CustomInstancePathTile();

  @override
  State<_CustomInstancePathTile> createState() =>
      _CustomInstancePathTileState();
}

class _CustomInstancePathTileState extends State<_CustomInstancePathTile>
    with WidgetsBindingObserver {
  String? _customPath;
  String _defaultPath = '';
  bool _loading = true;
  bool _busy = false;
  Completer<void>? _resumeWaiter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeWaiter?.complete();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final waiter = _resumeWaiter;
      _resumeWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _load() async {
    final custom = await InstancePathStore.loadCustomPath();
    final defaultDir = await builtinEdgeCubeRoot();
    if (!mounted) return;
    setState(() {
      _customPath = custom;
      _defaultPath = defaultDir.path;
      _loading = false;
    });
  }

  String get _currentPath => _customPath ?? _defaultPath;
  bool get _isCustom => _customPath != null;

  Future<void> _change() async {
    if (_busy) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final picked = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (picked == null || !mounted) return;
    final normalized = p.normalize(picked);
    if (p.equals(normalized, p.normalize(_currentPath))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('settings.storage.customPathSameAsCurrent')),
        ),
      );
      return;
    }
    await _applyChange(normalized, isReset: false);
  }

  Future<void> _reset() async {
    if (_busy || !_isCustom) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    await _applyChange(_defaultPath, isReset: true);
  }

  Future<void> _applyChange(String targetPath, {required bool isReset}) async {
    final instances = InstanceScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = Directory(_currentPath);
    final target = Directory(targetPath);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('settings.storage.customPathConfirmTitle')),
        content: Text(
          isReset
              ? context.tr('settings.storage.customPathResetConfirmMessage', {
                  'path': targetPath,
                })
              : context.tr('settings.storage.customPathConfirmMessage', {
                  'path': targetPath,
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await showDialog<InstanceMigrationResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PathMigrationDialog(source: source, target: target),
      );
      if (!mounted) return;
      if (result == null) return;
      await InstancePathStore.saveCustomPath(isReset ? null : targetPath);
      instances.refreshAfterPathChange();
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_resultMessage(result, isReset))),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('settings.storage.customPathFailed', {
              'error': error.toString(),
            }),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resultMessage(InstanceMigrationResult result, bool isReset) {
    if (!result.success) {
      return context.tr('settings.storage.customPathPartial', {
        'migrated': '${result.migrated}',
        'skipped': '${result.skipped}',
        'failed': '${result.failed}',
      });
    }
    return context.tr('settings.storage.customPathSuccess', {
      'migrated': '${result.migrated}',
      'skipped': '${result.skipped}',
    });
  }

  Future<bool> _ensurePermission() async {
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
      // API >= 30：跳转系统设置，等待返回前台后重新查询。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _loading
        ? context.tr('common.loading')
        : (_isCustom
              ? _customPath!
              : '${context.tr('settings.storage.customPathDefault')} · $_defaultPath');
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text(context.tr('settings.storage.customPathTitle')),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _isCustom
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _change,
                  child: Text(context.tr('settings.storage.customPathChange')),
                ),
          onTap: _busy ? null : _change,
        ),
        if (_isCustom && !_busy)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restore, size: 18),
                label: Text(context.tr('settings.storage.customPathReset')),
              ),
            ),
          ),
      ],
    );
  }
}

/// 自定义路径变更时的实例文件迁移进度对话框。
class _PathMigrationDialog extends StatefulWidget {
  const _PathMigrationDialog({required this.source, required this.target});

  final Directory source;
  final Directory target;

  @override
  State<_PathMigrationDialog> createState() => _PathMigrationDialogState();
}

class _PathMigrationDialogState extends State<_PathMigrationDialog> {
  int _processed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrate());
  }

  Future<void> _migrate() async {
    final result = await InstanceMigration.migrateBetween(
      source: widget.source,
      target: widget.target,
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
                        ? context.tr('settings.storage.customPathMigrating')
                        : context.tr(
                            'settings.storage.customPathMigratingProgress',
                            {'processed': '$_processed', 'total': '$_total'},
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.tr('settings.storage.customPathMigratingDoNotClose')),
          ],
        ),
      ),
    );
  }
}
