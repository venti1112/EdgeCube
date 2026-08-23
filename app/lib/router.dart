import 'package:go_router/go_router.dart';

import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/servers_page.dart';
import 'settings/appearance.dart';
import 'settings/main.dart';
import 'shell/home_shell.dart';

/// 应用路由:StatefulShellRoute.indexedStack 保持各分支页面状态,
/// 由 HomeShell 提供底栏/侧栏导航框架。
final router = GoRouter(
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
              builder: (context, state) => const ServersPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/console',
              builder: (context, state) => const ConsolePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/manage',
              builder: (context, state) => const ManagePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/files',
              builder: (context, state) => const FilesPage(),
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
