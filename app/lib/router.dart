import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/servers_page.dart';
import 'server/server_service.dart';
import 'settings/add_server_page.dart';
import 'settings/appearance.dart';
import 'settings/main.dart';
import 'settings/server_settings_page.dart';
import 'shell/home_shell.dart';

/// 启动引导条件变化时通知 GoRouter 刷新 redirect:
/// 服务器列表或 local.key 状态变化(如添加服务器成功)后自动回到主界面。
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(serverNeedSetupProvider, (previous, next) => notifyListeners());
  }
}

/// 应用路由:StatefulShellRoute.indexedStack 保持各分支页面状态,
/// 由 HomeShell 提供底栏/侧栏导航框架。
///
/// 启动引导:没有任何服务器配置且本机无 local.key 时,
/// 强制跳转 /setup 引导用户添加服务器(避免进入无可用的空界面)。
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/servers',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final needSetup = ref.read(serverNeedSetupProvider);
      final onSetup = state.matchedLocation == '/setup';
      if (needSetup && !onSetup) return '/setup';
      if (!needSetup && onSetup) return '/servers';
      return null;
    },
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
                  GoRoute(
                    path: 'servers',
                    builder: (context, state) => const ServerSettingsPage(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        builder: (context, state) => const AddServerPage(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const AddServerPage(setupMode: true),
      ),
    ],
  );
  return router;
});