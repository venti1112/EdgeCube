import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 主页框架:竖屏时底部 NavigationBar,横屏时左侧 NavigationRail,
/// 内容区为 go_router 的 StatefulNavigationShell(各分支状态独立保留)。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations =
      <({IconData icon, IconData selectedIcon, String label})>[
    (icon: Icons.dns_outlined, selectedIcon: Icons.dns, label: '服务器'),
    (icon: Icons.terminal_outlined, selectedIcon: Icons.terminal, label: '控制台'),
    (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: '管理'),
    (icon: Icons.folder_outlined, selectedIcon: Icons.folder, label: '文件'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '设置'),
  ];

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // 再次点击当前页签时回到该分支初始页
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.portrait) {
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onDestinationSelected,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: navigationShell),
            ],
          ),
        );
      },
    );
  }
}
