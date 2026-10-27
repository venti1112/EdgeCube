import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'connection/state.dart';
import 'console/console_page.dart';
import 'frp/frp_custom_config_page.dart';
import 'frp/frp_login_page.dart';
import 'frp/frp_provider_picker_page.dart';
import 'frp/frp_provider_tunnels_page.dart';
import 'frp/frp_run_page.dart';
import 'frp/frp_tunnel_config_page.dart';
import 'frp/frp_tunnel_list_page.dart';
import 'instance/create_instance_page.dart';
import 'instance/config/config_page.dart';
import 'local_service/settings.dart';
import 'local_service/state.dart';
import 'mods/mods_page.dart';
import 'pages/connect_page.dart';
import 'pages/files_page.dart';
import 'pages/manage_page.dart';
import 'pages/port_mapping_page.dart';
import 'pages/servers_page.dart';
import 'pages/shell_page.dart';
import 'players/players_page.dart';
import 'runtime/runtime_download_page.dart';
import 'runtime/runtime_page.dart';
import 'settings/about_page.dart';
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
/// 只有「首次连接设置」(`/connect`)是盖住 shell 的全屏路由;
/// 其余页面全部挂在对应分支的子路由下 —— 子页、向导都不会盖住
/// 底栏/侧栏,且各分支的子页堆栈互相独立保留(切走再切回还在原子页,
/// 再点一次当前页签回分支根页)。
/// 分支路径需与 HomeShell 的 _destinations 顺序一一对应。
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter 不感知 Riverpod 状态;不给它一个 Listenable,redirect 就只在
  // 导航时求值 ——「连上后自动进主界面」也就不会发生。
  final refresh = _ConnectionRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation:
        (ref.read(persistedConnectionProvider) != null ||
            ref.read(localServiceEnabledProvider))
        ? '/servers'
        : '/connect',
    refreshListenable: refresh,
    redirect: (context, state) {
      // 这里必须直接读**真源** persistedConnectionProvider。别图省事再包一层
      // `hasSaved*` 派生 Provider:redirect 是在真源变更的监听回调里同步跑的,
      // 那一刻派生值的缓存还没失效,会读到旧值(踩过)。
      final hasSaved = ref.read(persistedConnectionProvider) != null;
      // 本地服务是独立开关:开了它就算「已配置」,不必先去连接页。
      final localEnabled = ref.read(localServiceEnabledProvider);
      final local = ref.read(localServiceProvider);
      final localUsable = localEnabled && local.supported != false;
      final configured = hasSaved || localUsable;

      final atConnect = state.matchedLocation == '/connect';
      if (!configured) return atConnect ? null : '/connect';

      // 本地服务准备中 / 启动失败时留在连接页:那里有转圈、状态与日志。
      // 就绪后 LocalServiceNotifier 会自动连接,连接成功再把页面放行到主界面。
      if (atConnect) {
        final connected =
            ref.read(connectionPhaseProvider) == ConnectionPhase.connected;
        if (localUsable && !local.status.isRunning && !connected) return null;
        return '/servers';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectPage(),
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
                routes: [
                  // 新建实例向导：入口在服务器页右上角的实例列表弹窗里
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateInstancePage(),
                  ),
                ],
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
                routes: [
                  GoRoute(
                    path: 'players',
                    builder: (context, state) => const PlayersPage(),
                  ),
                  // 服务器配置：管理页点进去的子页。**入口文案通用**，进来才问
                  // daemon「这个实例有哪种配置」（判断在后端）。
                  GoRoute(
                    path: 'config',
                    builder: (context, state) => const InstanceConfigPage(),
                  ),
                  // 网络映射：本机对外的几条路的总入口：
                  // FRP 隧道 + UPnP 端口映射（已实现）+ STUN / DDNS（置灰）。FRP 那些子页挂在它
                  // 下面的 `tunnels/` 命名空间里，与「网络映射」是一层从属关系。
                  GoRoute(
                    path: 'network',
                    builder: (context, state) => const PortMappingPage(),
                    routes: [
                      GoRoute(
                        path: 'tunnels',
                        builder: (context, state) => const FrpTunnelListPage(),
                        routes: [
                          GoRoute(
                            path: 'picker',
                            builder: (context, state) =>
                                const FrpProviderPickerPage(),
                          ),
                          GoRoute(
                            path: 'custom',
                            builder: (context, state) =>
                                const FrpCustomConfigPage(),
                          ),
                          GoRoute(
                            path: 'login/:provider',
                            builder: (context, state) => FrpLoginPage(
                              providerKey:
                                  state.pathParameters['provider'] ?? '',
                            ),
                          ),
                          GoRoute(
                            path: 'provider/:provider',
                            builder: (context, state) => FrpProviderTunnelsPage(
                              providerKey:
                                  state.pathParameters['provider'] ?? '',
                            ),
                          ),
                          // 单条隧道的**运行页**（启停 + 日志）—— 一条隧道一个 FRP 实例
                          GoRoute(
                            path: 'run/:localId',
                            builder: (context, state) => FrpRunPage(
                              localId: state.pathParameters['localId'] ?? '',
                            ),
                          ),
                          // 那条隧道的 frpc 配置（看 / 重新生成）。配置生成是 V2 已有的能力，从运行页右上角进。
                          GoRoute(
                            path: 'config/:localId',
                            builder: (context, state) => FrpTunnelConfigPage(
                              localId: state.pathParameters['localId'] ?? '',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // 模组与插件：管理页点进去的子页。
                  //
                  // **没有「下载页」这条路由**：「插件管理 / 插件下载 / 模组管理 /
                  // 模组下载」是同一页的四个标签，下载页嵌在标签里。
                  GoRoute(
                    path: 'mods',
                    builder: (context, state) => const ModsPage(),
                  ),
                  // 运行环境：管理页点进去的子页
                  GoRoute(
                    path: 'runtime',
                    builder: (context, state) => const RuntimePage(),
                    routes: [
                      GoRoute(
                        path: 'download',
                        builder: (context, state) =>
                            const RuntimeDownloadPage(),
                      ),
                    ],
                  ),
                  // 主机终端：daemon 所在机器上的 shell（不是实例控制台）。
                  // 入口在管理页，路径挂在 manage 下面，底栏保持 5 项。
                  GoRoute(
                    path: 'shell',
                    builder: (context, state) => const ShellPage(),
                  ),
                ],
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
                    path: 'connection',
                    builder: (context, state) => const ConnectionSettingsPage(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
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
    ref.listen(localServiceEnabledProvider, (_, _) => notifyListeners());
    // 只盯阶段:日志每来一行都刷新路由没有意义
    ref.listen(
      localServiceProvider.select((snapshot) => snapshot.status.phase),
      (_, _) => notifyListeners(),
    );
  }
}
