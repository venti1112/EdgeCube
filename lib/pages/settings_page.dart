import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../config/data_folder_store.dart';
import '../config/developer_options_store.dart';
import '../config/java_env_pref_store.dart';
import '../config/terminal_store.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import '../instance/data_folder_migration.dart';
import '../instance/instance_scope.dart';
import '../instance/instance_store.dart';
import '../theme/theme_scope.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';
import 'backup_settings_page.dart';
import 'developer_options_page.dart';
import 'keep_alive_settings_page.dart';
import 'language_settings_page.dart';
import 'network_settings_page.dart';
import 'storage_management_page.dart';
import 'widget_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoClearLogOnStart = true;
  JavaEnvPriority _javaEnvPriority = JavaEnvPriority.proot;
  bool _devModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutoClearLogOnStart();
    _loadJavaEnvPriority();
    _loadDevMode();
  }

  Future<void> _loadJavaEnvPriority() async {
    final value = await JavaEnvPrefStore.loadPriority();
    if (mounted) setState(() => _javaEnvPriority = value);
  }

  Future<void> _saveJavaEnvPriority(JavaEnvPriority value) async {
    setState(() => _javaEnvPriority = value);
    await JavaEnvPrefStore.savePriority(value);
  }

  String _javaEnvPriorityLabel(BuildContext context, JavaEnvPriority p) {
    return p == JavaEnvPriority.proot
        ? context.tr('settings.javaEnvPriority.proot')
        : context.tr('settings.javaEnvPriority.native');
  }

  /// 弹出优先级选择对话框（proot 优先 / 原生优先）。
  Future<void> _pickJavaEnvPriority() async {
    final selected = await showMiuixSingleChoice<JavaEnvPriority>(
      context: context,
      title: context.tr('settings.javaEnvPriority.dialogTitle'),
      options: JavaEnvPriority.values,
      selected: _javaEnvPriority,
      labelOf: _javaEnvPriorityLabel,
      hint: context.tr('settings.javaEnvPriority.hint'),
    );
    if (selected != null) await _saveJavaEnvPriority(selected);
  }

  Future<void> _loadAutoClearLogOnStart() async {
    final value = await TerminalStore.loadAutoClearLogOnStart();
    if (mounted) setState(() => _autoClearLogOnStart = value);
  }

  Future<void> _saveAutoClearLogOnStart(bool value) async {
    setState(() => _autoClearLogOnStart = value);
    await TerminalStore.saveAutoClearLogOnStart(value);
  }

  // ── 开发者选项 ────────────────────────────────────────────

  Future<void> _loadDevMode() async {
    final enabled = await DeveloperOptionsStore.loadEnabled();
    if (mounted) setState(() => _devModeEnabled = enabled);
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

  /// 压入子页面，返回后执行 [onReturn]（用于刷新可能被子页面改动的状态）。
  Future<void> _push(Widget page, {VoidCallback? onReturn}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) onReturn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final themeScope = ThemeScope.of(context);
    final localeScope = LocaleScope.of(context);

    return EcSettingsPage(
      title: context.tr('settings.title'),
      isTab: true,
      children: [
        MiuixSmallTitle(context.tr('settings.section.appearance')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.palette_outlined),
          title: context.tr('settings.appearance.title'),
          summary: _themeModeLabel(context, themeScope.themeMode),
          onClick: () => _push(const AppearanceSettingsPage()),
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.translate),
          title: context.tr('settings.language.title'),
          summary:
              localeScope.currentLanguageName ??
              context.tr('common.followSystem'),
          onClick: () => _push(const LanguageSettingsPage()),
        ),

        MiuixSmallTitle(context.tr('settings.section.console')),
        MiuixSwitchPreference(
          startAction: prefIcon(Icons.delete_sweep_outlined),
          title: context.tr('settings.console.autoClearLogOnStart'),
          summary: context.tr(
            'settings.console.autoClearLogOnStartDescription',
          ),
          value: _autoClearLogOnStart,
          onChanged: _saveAutoClearLogOnStart,
        ),

        if (Platform.isAndroid) ...[
          MiuixSmallTitle(context.tr('settings.section.keepAlive')),
          MiuixArrowPreference(
            startAction: prefIcon(Icons.battery_saver),
            title: context.tr('settings.keepAlive.title'),
            summary: context.tr('settings.keepAlive.subtitle'),
            onClick: () => _push(const KeepAliveSettingsPage()),
          ),
          MiuixArrowPreference(
            startAction: prefIcon(Icons.widgets_outlined),
            title: context.tr('settings.widget.title'),
            summary: context.tr('settings.widget.subtitle'),
            onClick: () => _push(const WidgetSettingsPage()),
          ),
        ],

        MiuixSmallTitle(context.tr('settings.section.storage')),
        const _CustomDataFolderTile(),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.storage),
          title: context.tr('storage.title'),
          summary: context.tr('storage.subtitle'),
          onClick: () => _push(const StorageManagementPage()),
        ),

        MiuixSmallTitle(context.tr('settings.section.backup')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.backup_outlined),
          title: context.tr('backup.settings.title'),
          summary: context.tr('backup.settings.subtitle'),
          onClick: () => _push(const BackupSettingsPage()),
        ),

        MiuixSmallTitle(context.tr('settings.section.runtime')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.memory),
          title: context.tr('settings.javaEnvPriority.title'),
          summary: context.tr('settings.javaEnvPriority.subtitle', {
            'value': _javaEnvPriorityLabel(context, _javaEnvPriority),
          }),
          onClick: _pickJavaEnvPriority,
        ),

        MiuixSmallTitle(context.tr('settings.section.network')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.lan_outlined),
          title: context.tr('settings.network.title'),
          summary: context.tr('settings.network.subtitle'),
          onClick: () => _push(const NetworkSettingsPage()),
        ),

        MiuixSmallTitle(context.tr('settings.section.other')),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.group_outlined),
          title: context.tr('settings.community.title'),
          summary: context.tr('settings.community.subtitle'),
          endActions: [const MiuixIcon(icon: Icons.open_in_new, size: 18)],
          onClick: () => launchUrl(
            Uri.parse('https://qm.qq.com/q/pnCZcmnKIS'),
            mode: LaunchMode.externalApplication,
          ),
        ),
        MiuixArrowPreference(
          startAction: prefIcon(Icons.info_outline),
          title: context.tr('settings.about.title'),
          summary: context.tr('settings.about.subtitle'),
          // 从关于页返回后刷新开发者模式状态（可能在关于页解锁了）
          onClick: () => _push(const AboutPage(), onReturn: _loadDevMode),
        ),
        // ── 开发者选项入口（仅在开发者模式启用后显示）──
        if (_devModeEnabled)
          MiuixArrowPreference(
            startAction: prefIcon(Icons.developer_mode),
            title: context.tr('settings.section.developer'),
            summary: context.tr('settings.developer.entrySubtitle'),
            // 从开发者选项页返回后刷新状态（可能关闭了开发者模式）
            onClick: () =>
                _push(const DeveloperOptionsPage(), onReturn: _loadDevMode),
          ),
      ],
    );
  }
}

/// 「自定义数据文件夹」入口：显示当前 EdgeCube 数据文件夹，支持选择新位置或恢复默认。
///
/// EdgeCube 数据文件夹下的 `instances/` 子目录存放各实例的工作文件夹。
/// 更改路径时会把旧 EdgeCube 文件夹下的全部内容（含 `instances/`）移动到新位置
/// （复用 [DataFolderMigration] 的迁移逻辑），完成后持久化新路径并通知
/// [InstanceController] 刷新依赖方（FTP/SSH 根目录同步等）。
class _CustomDataFolderTile extends StatefulWidget {
  const _CustomDataFolderTile();

  @override
  State<_CustomDataFolderTile> createState() => _CustomDataFolderTileState();
}

class _CustomDataFolderTileState extends State<_CustomDataFolderTile>
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
    final custom = await DataFolderStore.loadCustomPath();
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
      showErrorDialog(
        context,
        context.tr('settings.storage.dataFolderSameAsCurrent'),
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
    final source = Directory(_currentPath);
    final target = Directory(targetPath);

    final confirmed = await showMiuixConfirm(
      context,
      title: context.tr('settings.storage.dataFolderConfirmTitle'),
      message: isReset
          ? context.tr('settings.storage.dataFolderResetConfirmMessage', {
              'path': targetPath,
            })
          : context.tr('settings.storage.dataFolderConfirmMessage', {
              'path': targetPath,
            }),
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await showMiuixDialog<DataFolderMigrationResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PathMigrationDialog(source: source, target: target),
      );
      if (!mounted) return;
      if (result == null) return;
      await DataFolderStore.saveCustomPath(isReset ? null : targetPath);
      instances.refreshAfterPathChange();
      await _load();
      if (!mounted) return;
      // 部分文件迁移失败属于错误，用弹窗提示；全部成功用 Snackbar。
      if (result.success) {
        showMiuixSnackbar(_resultMessage(result, isReset));
      } else {
        showErrorDialog(context, _resultMessage(result, isReset));
      }
    } catch (error) {
      if (!mounted) return;
      showErrorDialog(
        context,
        context.tr('settings.storage.dataFolderFailed', {
          'error': error.toString(),
        }),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _resultMessage(DataFolderMigrationResult result, bool isReset) {
    if (!result.success) {
      return context.tr('settings.storage.dataFolderPartial', {
        'migrated': '${result.migrated}',
        'skipped': '${result.skipped}',
        'failed': '${result.failed}',
      });
    }
    return context.tr('settings.storage.dataFolderSuccess', {
      'migrated': '${result.migrated}',
      'skipped': '${result.skipped}',
    });
  }

  Future<bool> _ensurePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showMiuixDialog<bool>(
      context: context,
      barrierDismissible: false,
      title: context.tr('instance.storagePermissionTitle'),
      summary: context.tr('settings.storage.permissionMessage'),
      builder: (ctx) => MiuixDialogActions(
        children: [
          MiuixTextButton(
            ctx.tr('common.cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          MiuixButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            colors: MiuixButtonDefaults.buttonColorsPrimary(ctx),
            child: MiuixText(ctx.tr('instance.goGrant')),
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
    final theme = MiuixTheme.of(context);
    final subtitle = _loading
        ? context.tr('common.loading')
        : (_isCustom
              ? _customPath!
              : '${context.tr('settings.storage.dataFolderDefault')} · $_defaultPath');
    return MiuixBasicComponent(
      startAction: prefIcon(Icons.folder_open),
      title: context.tr('settings.storage.dataFolderTitle'),
      summary: subtitle,
      // 自定义路径用主色标出，与默认路径区分。
      summaryColor: _isCustom
          ? MiuixBasicComponentColors(
              color: theme.colors.primary,
              disabledColor: theme.colors.disabledOnSecondaryVariant,
            )
          : null,
      enabled: !_busy,
      onClick: _busy ? null : _change,
      endActions: [
        if (_busy)
          const MiuixInfiniteProgressIndicator(size: 22)
        else
          MiuixButton(
            onPressed: _change,
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            minWidth: 0,
            minHeight: 0,
            child: MiuixText(
              context.tr('settings.storage.dataFolderChange'),
              style: theme.textStyles.button,
            ),
          ),
      ],
      bottomAction: (_isCustom && !_busy)
          ? Align(
              alignment: Alignment.centerLeft,
              child: MiuixTextButton(
                context.tr('settings.storage.dataFolderReset'),
                onPressed: _reset,
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minWidth: 0,
                minHeight: 0,
              ),
            )
          : null,
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
    final result = await DataFolderMigration.migrateBetween(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 总数未知时用不定长转圈，已知则显示确定进度环。
              progress == null
                  ? const MiuixInfiniteProgressIndicator()
                  : MiuixCircularProgressIndicator(progress: progress),
              const SizedBox(width: 20),
              Expanded(
                child: MiuixText(
                  _total == 0
                      ? context.tr('settings.storage.dataFolderMigrating')
                      : context.tr(
                          'settings.storage.dataFolderMigratingProgress',
                          {'processed': '$_processed', 'total': '$_total'},
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MiuixText(
            context.tr('settings.storage.dataFolderMigratingDoNotClose'),
          ),
        ],
      ),
    );
  }
}
