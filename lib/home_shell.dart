import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/network_store.dart';
import 'files/file_browser.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _showFirstLaunchDialog());
    // 启动时后台检查更新；检查失败静默忽略，仅在检查成功且有更新时提示。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdatesInBackground());
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
        title: const Text('启用在线服务'),
        content: const Text(
          'EdgeCube 提供了一些在线服务以提升使用体验。'
          '启用后将生成唯一设备标识用于服务识别。'
          '我们可能会收集您的设备信息以改进软件。\n'
          '您是否同意启用在线服务？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意'),
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
            const Expanded(child: Text('使用镜像源下载')),
          ],
        ),
        content: const Text(
          '下载服务端时可使用 MSL 镜像源加速，国内网络下载更快、更稳定；'
          '镜像不可用时会自动回退官方源。\n'
          '是否启用镜像源下载？\n\n'
          '镜像源服务由 MSL 开服器（mslmc.cn）提供，可随时在「设置 → 网络设置」中更改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('暂不启用'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('启用'),
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
        body: IndexedStack(
          index: _selectedIndex,
          children: _tabPages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.dns_outlined),
              selectedIcon: Icon(Icons.dns),
              label: '服务器',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal),
              label: '控制台',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: '管理',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '文件',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
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
        const SnackBar(
          content: Text('再按一次退出'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
