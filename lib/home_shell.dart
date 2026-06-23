import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/network_store.dart';
import 'files/file_browser.dart';
import 'i18n/locale_scope.dart';
import 'online/online_service.dart';
import 'online/update_service.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/server_page.dart';
import 'pages/settings_page.dart';
import 'widgets/update_dialog.dart';

/// 应用主壳：底部导航栏 + 页面切换。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  late final List<Widget> _tabPages;

  @override
  void initState() {
    super.initState();
    _tabPages = [
      ServerPage(onlineService: widget.onlineService),
      const ConsolePage(),
      const ManagePage(),
      const FilesPage(),
      SettingsPage(onlineService: widget.onlineService),
    ];
    // 首次启动弹窗：询问是否启用在线服务。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showFirstLaunchDialog(),
    );
    // 启动时后台检查更新；检查失败静默忽略，仅在检查成功且有更新时提示。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkUpdatesInBackground(),
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
