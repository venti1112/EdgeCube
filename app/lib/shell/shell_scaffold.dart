import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../app_state/ui_style_scope.dart';
import '../pages/console_page.dart';
import '../pages/files_page.dart';
import '../pages/manage_page.dart';
import '../pages/server_page.dart';
import '../pages/settings_page.dart';

/// 应用主壳:底部底栏 + 上方内容区(占位空内容)。
///
/// 根据 [UiStyleScope] 选择底栏组件:
/// - [UiStyle.material3]:Material 3 `NavigationBar`
/// - [UiStyle.liquidGlass]:`GlassTabBar.bottom`
///
/// 两个分支共用同一份 `IndexedStack`(5 个占位页)。
/// 切换 [UiStyle] 即时生效(根 `EdgeCubeApp` 重建 + 本 Shell 重建)。
class ShellScaffold extends StatefulWidget {
  const ShellScaffold({super.key});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  int _selectedIndex = 0;

  static const _tabPages = <Widget>[
    ServerPage(),
    ConsolePage(),
    ManagePage(),
    FilesPage(),
    SettingsPage(),
  ];

  void _onTabSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final uiStyle = UiStyleScope.of(context).controller.value;
    final stack = IndexedStack(
      index: _selectedIndex,
      children: _tabPages,
    );

    switch (uiStyle) {
      case UiStyle.material3:
        return Scaffold(
          body: stack,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onTabSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dns),
                label: 'Server',
              ),
              NavigationDestination(
                icon: Icon(Icons.terminal),
                label: 'Console',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune),
                label: 'Manage',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                label: 'Files',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );

      case UiStyle.liquidGlass:
        return Scaffold(
          body: stack,
          bottomNavigationBar: GlassTabBar.bottom(
            tabs: const [
              GlassTab(icon: Icon(Icons.dns), label: 'Server'),
              GlassTab(icon: Icon(Icons.terminal), label: 'Console'),
              GlassTab(icon: Icon(Icons.tune), label: 'Manage'),
              GlassTab(icon: Icon(Icons.folder_outlined), label: 'Files'),
              GlassTab(icon: Icon(Icons.settings), label: 'Settings'),
            ],
            selectedIndex: _selectedIndex,
            onTabSelected: _onTabSelected,
          ),
        );
    }
  }
}
