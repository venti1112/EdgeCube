import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'connection/state.dart';
import 'instance/create_instance_page.dart';
import 'pages/connect_page.dart';
import 'pages/placeholder_page.dart';
import 'pages/servers_page.dart';
import 'settings/appearance_page.dart';
import 'settings/connection_page.dart';
import 'settings/main.dart';
import 'shell/home_shell.dart';

/// 应用路由:StatefulShellRoute.indexedStack 保持各分支页面状态,
/// 由 HomeShell 提供底栏/侧栏导航框架。
///
/// **首次启动守卫**:从未成功连接过服务器(`persistedConnectionProvider == null`)
/// 时,任何路径都被 redirect 到 `/connect`;连接成功会把配置落盘,守卫随即放行
/// 并把页面切到主界面。配过之后即使掉线也不再回连接页(除非「忘记服务器」),
/// 断线由 HomeShell 顶部的横幅提示。
///
/// 注意:除「服务器」「设置 → 外观/连接」外,其余分支仍是占位页,
/// 真实业务页面由 v2 自行实现后替换。
/// 分支路径需与 HomeShell 的 _destinations 顺序一一对应。
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter 不感知 Riverpod 状态;不给它一个 Listenable,redirect 就只在
  // 导航时求值 ——「连上后自动进主界面」也就不会发生。
  final refresh = _ConnectionRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: ref.read(persistedConnectionProvider) == null
        ? '/connect'
        : '/servers',
    refreshListenable: refresh,
    redirect: (context, state) {
      // 这里必须直接读**真源** persistedConnectionProvider。别图省事再包一层
      // `hasSaved*` 派生 Provider:redirect 是在真源变更的监听回调里同步跑的,
      // 那一刻派生值的缓存还没失效,会读到旧值(踩过)。
      final hasSaved = ref.read(persistedConnectionProvider) != null;
      final atConnect = state.matchedLocation == '/connect';
      if (!hasSaved) return atConnect ? null : '/connect';
      // 已经配过服务器了:连接页只在首次配置时用
      if (atConnect) return '/servers';
      return null;
    },
    routes: [
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectPage(),
      ),
      // 新建实例向导：整页盖住 shell（与 V1 一样是全屏向导）
      GoRoute(
        path: '/instance/create',
        builder: (context, state) => const CreateInstancePage(),
      ),
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
                  GoRoute(
                    path: 'connection',
                    builder: (context, state) =>
                        const ConnectionSettingsPage(),
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

/// 连接相关状态一变就通知 GoRouter 重跑 redirect。
class _ConnectionRefresh extends ChangeNotifier {
  _ConnectionRefresh(Ref ref) {
    ref.listen(persistedConnectionProvider, (_, _) => notifyListeners());
    ref.listen(connectionPhaseProvider, (_, _) => notifyListeners());
  }
}
