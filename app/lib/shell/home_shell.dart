import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/appearance.dart';
import 'background.dart';

/// 主页框架:竖屏时底部 NavigationBar,横屏时左侧 NavigationRail,
/// 内容区为 go_router 的 StatefulNavigationShell(各分支状态独立保留)。
///
/// 设置自定义背景(纯色/图片)后进入毛玻璃模式(PLAN §8):
/// Stack 底层为全屏背景,上层 Scaffold 透明,底栏/侧栏与内容区
/// 均以 BackdropFilter + 半透明 surface 实时透出背景。
///
/// 每个毛玻璃参数都从它自己的全局 Provider 读
/// (navBlurEnabledProvider / navBlurSigmaProvider / …),
/// 所以调「内容表面不透明度」不会顺带重建导航栏。
class HomeShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // 磨砂模式总开关:派生自 backgroundTypeProvider
    final glass = ref.watch(glassModeEnabledProvider);
    return OrientationBuilder(
      builder: (context, orientation) {
        final portrait = orientation == Orientation.portrait;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (glass) const BackgroundLayer(),
            Scaffold(
              backgroundColor: glass ? Colors.transparent : null,
              // body 延伸到底栏后面,底栏模糊时透出背景与内容
              extendBody: true,
              body: portrait
                  ? _contentArea(context, ref, glass)
                  : Row(
                      children: [
                        _rail(context, ref, glass),
                        if (!glass)
                          const VerticalDivider(width: 1, thickness: 1),
                        Expanded(child: _contentArea(context, ref, glass)),
                      ],
                    ),
              bottomNavigationBar:
                  portrait ? _navBar(context, ref, glass) : null,
            ),
          ],
        );
      },
    );
  }

  /// 内容区:容器层单次 BackdropFilter + 半透明 surface(不做逐卡片模糊)
  Widget _contentArea(BuildContext context, WidgetRef ref, bool glass) {
    final child = navigationShell;
    if (!glass) return child;
    final opacity = ref.watch(contentOpacityProvider);
    final blurEnabled = ref.watch(contentBlurEnabledProvider);
    final sigma = ref.watch(contentBlurSigmaProvider);
    final cs = Theme.of(context).colorScheme;
    Widget area = ColoredBox(
      color: cs.surface.withValues(alpha: opacity),
      child: child,
    );
    // 半径正是 0 时不必挂 BackdropFilter:AppearanceSettings 注释已约定
    // “0 = 关闭模糊”,让滑块到底就直接摘掉图层,省一次离屏采样。
    if (blurEnabled && sigma > 0) {
      area = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: area,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: area,
      ),
    );
  }

  /// 底部导航栏(竖屏),毛玻璃模式下高斯模糊 + 半透明背景
  Widget _navBar(BuildContext context, WidgetRef ref, bool glass) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(navBlurEnabledProvider);
    final sigma = ref.watch(navBlurSigmaProvider);
    final opacity = ref.watch(navOpacityProvider);
    // 同上:半径 0 视作关闭模糊,此时仅保留半透明底色
    final blur = glass && enabled && sigma > 0;
    final bar = NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onDestinationSelected,
      backgroundColor: glass ? cs.surface.withValues(alpha: opacity) : null,
      destinations: [
        for (final d in _destinations)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: d.label,
          ),
      ],
    );
    if (!blur) return bar;
    // BackdropFilter 生效范围取最近祖先 clip,不裁剪会扩大到全屏,
    // 故用 ClipRect 把模糊限定在底栏自身区域
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: bar,
      ),
    );
  }

  /// 侧边导航栏(横屏),毛玻璃模式下高斯模糊 + 半透明背景
  Widget _rail(BuildContext context, WidgetRef ref, bool glass) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(navBlurEnabledProvider);
    final sigma = ref.watch(navBlurSigmaProvider);
    final opacity = ref.watch(navOpacityProvider);
    // 同上:半径 0 视作关闭模糊,此时仅保留半透明底色
    final blur = glass && enabled && sigma > 0;
    final rail = NavigationRail(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      backgroundColor: glass ? cs.surface.withValues(alpha: opacity) : null,
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
    );
    if (!blur) return rail;
    // 同底栏:ClipRect 限定模糊范围,避免扩到全屏
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: rail,
      ),
    );
  }
}
