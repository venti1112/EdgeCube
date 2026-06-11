import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'files/file_browser.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/players_page.dart';
import 'pages/server_page.dart';
import 'pages/settings_page.dart';

/// 应用主壳：底部导航栏 + 页面切换。
///
/// 使用 [IndexedStack] 让所有页面常驻，切换时保留各自滚动位置与状态
/// （例如控制台日志），而不是每次切换都重建页面。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    ServerPage(),
    ConsolePage(),
    PlayersPage(),
    FilesPage(),
    SettingsPage(),
  ];

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
        // 在文件页面且不在根目录：返回上级目录
        if (_selectedIndex == 3 && FileBrowser.canNavigateUp) {
          FileBrowser.navigateUp();
          return;
        }
        // 其它情况：返回服务器页面
        setState(() => _selectedIndex = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _pages,
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
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: '玩家',
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
