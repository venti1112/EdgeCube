import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'pages/placeholder_page.dart';
import 'settings/appearance_page.dart';
import 'settings/main.dart';
import 'shell/home_shell.dart';

/// 应用路由:StatefulShellRoute.indexedStack 保持各分支页面状态,
/// 由 HomeShell 提供底栏/侧栏导航框架。
///
/// 注意:除「设置 → 外观」外,以下分支目前都是占位页 —— 本次只搬运
/// V1 的毛玻璃 UI,真实业务页面由 v2 自行实现后替换。
/// 分支路径需与 HomeShell 的 _destinations 顺序一一对应。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/servers',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/servers',
                builder: (context, state) => const PlaceholderPage(
                  title: '服务器',
                  icon: Icons.dns_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/console',
                builder: (context, state) => const PlaceholderPage(
                  title: '控制台',
                  icon: Icons.terminal_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/manage',
                builder: (context, state) => const PlaceholderPage(
                  title: '管理',
                  icon: Icons.dashboard_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder: (context, state) => const PlaceholderPage(
                  title: '文件',
                  icon: Icons.folder_outlined,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'appearance',
                    builder: (context, state) => const AppearancePage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
