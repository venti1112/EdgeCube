import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'files/file_browser.dart';
import 'online/online_service.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/server_page.dart';
import 'pages/settings_page.dart';

/// 应用主壳：底部导航栏 + 页面切换。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onlineService});

  final OnlineService onlineService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  List<Widget> get _tabPages => [
    ServerPage(onlineService: widget.onlineService),
    const ConsolePage(),
    const ManagePage(),
    const FilesPage(),
    SettingsPage(onlineService: widget.onlineService),
  ];

  @override
  void initState() {
    super.initState();
    // 首次启动弹窗：询问是否启用在线服务。
    WidgetsBinding.instance.addPostFrameCallback((_) => _showFirstLaunchDialog());
  }

  Future<void> _showFirstLaunchDialog() async {
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
