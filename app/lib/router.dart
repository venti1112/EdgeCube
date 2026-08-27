import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/connecting_page.dart';
import 'pages/console_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/servers_page.dart';
import 'server/server_service.dart';
import 'settings/add_server_page.dart';
import 'settings/appearance.dart';
import 'settings/change_credentials_page.dart';
import 'settings/main.dart';
import 'settings/server_settings_page.dart';
import 'shell/home_shell.dart';

/// 连接会话/启动阶段变化时通知 GoRouter 刷新 redirect:
/// 启动连接结束后由连接页跳转主界面或服务器管理页。
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionProvider, (previous, next) => notifyListeners());
    ref.listen(startupStageProvider, (previous, next) => notifyListeners());
  }
}

/// 应用路由:StatefulShellRoute.indexedStack 保持各分支页面状态,
/// 由 HomeShell 提供底栏/侧栏导航框架。
///
/// 启动流程:冷启动首先进入 /connecting 连接页;
/// 连接结束:成功进入主界面,失败(或无任何服务器可连)进入服务器管理页。
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/connecting',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final stage = ref.read(startupStageProvider);
      final connected = ref.read(sessionProvider) != null;
      final loc = state.matchedLocation;

      // 启动连接中:只允许显示连接页
      if (stage == StartupStage.connecting && loc != '/connecting') {
        return '/connecting';
      }
      // 启动连接结束:离开连接页,按结果进入主界面或服务器管理页
      if (stage == StartupStage.finished && loc == '/connecting') {
        return connected ? '/servers' : '/settings/servers';
      }
      // 未连接:只允许停留在服务器管理/添加页
      if (!connected) {
        const allowed = {'/settings/servers', '/settings/servers/add'};
        if (!allowed.contains(loc)) return '/settings/servers';
      }
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
                    path: 'account',
                    builder: (context, state) => const ChangeCredentialsPage(),
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
        path: '/connecting',
        builder: (context, state) => const ConnectingPage(),
      ),
    ],
  );
  return router;
});