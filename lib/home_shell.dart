import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/network_store.dart';
import 'config/version_store.dart';
import 'files/file_browser.dart';
import 'files/storage_permission.dart';
import 'i18n/locale_scope.dart';
import 'instance/instance_migration.dart';
import 'instance/instance_scope.dart';
import 'online/online_service.dart';
import 'online/update_service.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/runtime_page.dart';
import 'pages/server_page.dart';
import 'pages/settings_page.dart';
import 'server/ecpkg_handler.dart';
import 'widgets/update_dialog.dart';

/// 应用主壳：底部导航栏 + 页面切换。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onlineService, this.lastVersion});

  final OnlineService onlineService;
  final String? lastVersion;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget> _tabPages;
  Completer<void>? _resumeWaiter;
  bool _checkingStoragePermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabPages = [
      ServerPage(onlineService: widget.onlineService),
      const ConsolePage(),
      const ManagePage(),
      const FilesPage(),
      SettingsPage(onlineService: widget.onlineService),
    ];
    EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
    EcpkgHandler.onError = _handleEcpkgError;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EcpkgHandler.onOpenEcpkg = null;
    EcpkgHandler.onError = null;
    _resumeWaiter?.complete();
    super.dispose();
  }

  void _handleOpenEcpkg(String path) {
    if (!mounted) return;
    if (!path.toLowerCase().endsWith('.ecpkg')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('runtime.notEcpkg'))),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RuntimePage(initialEcpkgPath: path),
      ),
    ).then((_) {
      if (mounted) {
        EcpkgHandler.onOpenEcpkg = _handleOpenEcpkg;
      }
    });
  }

  void _handleEcpkgError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('runtime.openEcpkgFailed', {'error': error}))),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final waiter = _resumeWaiter;
      _resumeWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      if (waiter == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureStoragePermissionGuard();
        });
      }
    }
  }

  Future<void> _runStartupTasks() async {
    final storageReady = await _ensureStoragePermissionGuard();
    if (!storageReady || !mounted) return;
    await _maybeAutoMigrateInstances();
    if (!mounted) return;
    await _showFirstLaunchDialog();
    if (!mounted) return;
    await _checkUpdatesInBackground();
  }

  Future<bool> _ensureStoragePermissionGuard() async {
    if (_checkingStoragePermission) return StoragePermission.isGranted();
    _checkingStoragePermission = true;
    try {
      while (mounted && !await StoragePermission.isGranted()) {
        final go = await _showStartupStoragePermissionDialog();
        if (go != true) return false;
        final result = await StoragePermission.request();
        if (result == null) {
          // API >= 30: intent-based flow, wait for resume from system settings
          final resumeWaiter = Completer<void>();
          _resumeWaiter = resumeWaiter;
          await resumeWaiter.future;
          await _waitForStoragePermissionGranted();
        }
      }
      return mounted;
    } finally {
      _checkingStoragePermission = false;
    }
  }

  Future<void> _waitForStoragePermissionGranted() async {
    for (var i = 0; mounted && i < 25; i++) {
      if (await StoragePermission.isGranted()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<bool?> _showStartupStoragePermissionDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('settings.storage.startupPermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: Text(ctx.tr('common.close')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeAutoMigrateInstances() async {
    if (!InstanceMigration.shouldAutoMigrateFrom(widget.lastVersion)) return;
    if (!mounted) return;
    final instances = InstanceScope.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InstanceMigrationDialog(
        onComplete: () async {
          await instances.init();
          await VersionStore.recordOpen();
        },
      ),
    );
  }

  /// 后台检查更新。失败不提示；有更新则弹出更新对话框。
  Future<void> _checkUpdatesInBackground() async {
    final info = await UpdateService.checkForUpdates();
    if (info == null) return; // 检查失败，静默处理。
    if (!mounted) return;
    final hasUpdate = await UpdateService.hasUpdate(info);
    if (!mounted || !hasUpdate) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  /// 首次启动依次询问：在线服务、镜像源（各自只询问一次）。
  Future<void> _showFirstLaunchDialog() async {
    await _maybeAskOnlineService();
    await _maybeAskMirror();
  }

  /// 询问是否启用在线服务（仅首次）。
  Future<void> _maybeAskOnlineService() async {
    if (widget.onlineService.asked) return;
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('firstLaunch.online.title')),
        content: Text(ctx.tr('firstLaunch.online.content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.disagree')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.agree')),
          ),
        ],
      ),
    );

    await widget.onlineService.markAsked();
    if (result == true) {
      await widget.onlineService.setEnabled(true);
    }
  }

  /// 询问是否启用镜像源下载服务端（仅首次）。
  Future<void> _maybeAskMirror() async {
    if (await NetworkStore.loadMirrorAsked()) return;
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/msl_logo.png',
                width: 32,
                height: 32,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(ctx.tr('firstLaunch.mirror.title'))),
          ],
        ),
        content: Text(ctx.tr('firstLaunch.mirror.content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('firstLaunch.mirror.decline')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.enable')),
          ),
        ],
      ),
    );

    await NetworkStore.saveMirrorAsked(true);
    if (result == true) {
      await NetworkStore.saveUseMirror(true);
    }
  }

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 在服务器页面按返回键：双击退出应用
        if (_selectedIndex == 0) {
          _handleExit();
          return;
        }
        // 在文件页面：先退出多选，其次返回上级目录
        if (_selectedIndex == 3) {
          if (FileBrowser.isSelecting) {
            FileBrowser.exitSelection();
            return;
          }
          if (FileBrowser.canNavigateUp) {
            FileBrowser.navigateUp();
            return;
          }
        }
        // 其它情况：返回服务器页面
        setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: _tabPages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.dns_outlined),
              selectedIcon: const Icon(Icons.dns),
              label: context.tr('nav.server'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.terminal_outlined),
              selectedIcon: const Icon(Icons.terminal),
              label: context.tr('nav.console'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune),
              label: context.tr('nav.manage'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: context.tr('nav.files'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: context.tr('nav.settings'),
            ),
          ],
        ),
      ),
    );
  }

  /// 双击返回退出应用。
  DateTime? _lastBackPress;

  Future<void> _handleExit() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
    } else {
      _lastBackPress = now;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('home.exitToast')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _InstanceMigrationDialog extends StatefulWidget {
  const _InstanceMigrationDialog({required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<_InstanceMigrationDialog> createState() =>
      _InstanceMigrationDialogState();
}

class _InstanceMigrationDialogState extends State<_InstanceMigrationDialog> {
  int _processed = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _migrate());
  }

  Future<void> _migrate() async {
    try {
      final result = await InstanceMigration.migrateLegacyInstances(
        onProgress: (processed, total) {
          if (!mounted) return;
          setState(() {
            _processed = processed;
            _total = total;
          });
        },
      );
      if (!result.success) {
        throw result.error ?? StateError('Instance migration failed');
      }
      await widget.onComplete();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      await VersionStore.recordOpen();
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == 0 ? null : _processed / _total;
    return PopScope(
      canPop: _error != null,
      child: AlertDialog(
        title: Text(context.tr('settings.storage.autoMigrateTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error == null) ...[
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
            ] else ...[
              Text(
                context.tr('settings.storage.migrateFailed', {
                  'error': _error!,
                }),
              ),
            ],
          ],
        ),
        actions: _error == null
            ? null
            : [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('common.ok')),
                ),
              ],
      ),
    );
  }
}
