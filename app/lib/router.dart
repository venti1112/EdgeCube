import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/connecting_page.dart';
import 'pages/console_page.dart';
import 'pages/create_instance_page.dart';
import 'pages/files_page.dart';
import 'pages/frp_tunnel_detail_page.dart';
import 'pages/frp_tunnel_edit_page.dart';
import 'pages/frp_tunnel_list_page.dart';
import 'pages/instance_migrate_page.dart';
import 'pages/instance_wizard/download_progress_page.dart';
import 'pages/instance_wizard/select_category_page.dart';
import 'pages/instance_wizard/select_edition_page.dart';
import 'pages/instance_wizard/select_loader_page.dart';
import 'pages/instance_wizard/select_server_page.dart';
import 'pages/instance_wizard/select_version_page.dart';
import 'pages/manage_page.dart';
import 'pages/mods_plugins_page.dart';
import 'pages/players_page.dart';
import 'pages/runtime_install_page.dart';
import 'pages/runtime_page.dart';
import 'pages/server_config_page.dart';
import 'pages/server_core_update_page.dart';
import 'pages/servers_page.dart';
import 'pages/tasks_page.dart';
import 'server/server_service.dart';
import 'settings/add_server_page.dart';
import 'settings/appearance.dart';
import 'settings/change_credentials_page.dart';
import 'settings/devices_page.dart';
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
      // 未连接且启动已完成:只允许停留在服务器管理/添加页
      if (stage == StartupStage.finished && !connected) {
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
                routes: [
                  // 实例相关子页面:挂在 /servers 分支下,保留底栏/侧栏导航(对齐 V1)
                  GoRoute(
                    path: 'instances/create',
                    builder: (context, state) => const CreateInstancePage(),
                    routes: [
                      // 「下载服务端」向导:edition→category→server→version/loader→progress
                      GoRoute(
                        path: 'download/edition',
                        builder: (context, state) => const SelectEditionPage(),
                      ),
                      GoRoute(
                        path: 'download/category',
                        builder: (context, state) => const SelectCategoryPage(),
                      ),
                      GoRoute(
                        path: 'download/server',
                        builder: (context, state) => SelectServerPage(
                          category: state.uri.queryParameters['category']!,
                        ),
                      ),
                      GoRoute(
                        path: 'download/version',
                        builder: (context, state) => const SelectVersionPage(),
                      ),
                      GoRoute(
                        path: 'download/loader',
                        builder: (context, state) => const SelectLoaderPage(),
                      ),
                      GoRoute(
                        path: 'download/progress',
                        builder: (context, state) => const DownloadProgressPage(),
                      ),
                    ],
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
                  // 管理子页面:挂在 /manage 分支下,保留底栏/侧栏导航(对齐 V1)
                  // 玩家管理:对齐 V1 管理页首位入口
                  GoRoute(
                    path: 'players',
                    builder: (context, state) => const PlayersPage(),
                  ),
                  GoRoute(
                    path: 'runtimes',
                    builder: (context, state) => const RuntimePage(),
                    routes: [
                      GoRoute(
                        path: 'install',
                        builder: (context, state) => const RuntimeInstallPage(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'tasks',
                    builder: (context, state) => const TasksPage(),
                  ),
                  // 插件/模组管理子页面:挂在 /manage 分支下(入口对齐 V1 管理页)
                  GoRoute(
                    path: 'mods',
                    builder: (context, state) => const ModsPluginsPage(),
                  ),
                  // 服务器配置子页面:挂在 /manage 分支下(对齐 V1 管理页入口)
                  GoRoute(
                    path: 'config',
                    builder: (context, state) => const ServerConfigPage(),
                  ),
                  // 实例迁移(导出/导入)子页面:挂在 /manage 分支下(对齐 V1 管理页「实例导出」入口)
                  GoRoute(
                    path: 'migrate',
                    builder: (context, state) => const InstanceMigratePage(),
                  ),
                  // 服务端核心更新子页面:挂在 /manage 分支下(对齐 V1 管理页「服务端更新」入口)
                  GoRoute(
                    path: 'update-server',
                    builder: (context, state) => const ServerCoreUpdatePage(),
                  ),
                  // 内网穿透子页面:挂在 /manage 分支下(对齐 V1 管理页入口)
                  GoRoute(
                    path: 'frp',
                    builder: (context, state) => const FrpTunnelListPage(),
                    routes: [
                      GoRoute(
                        path: 'create',
                        builder: (context, state) => const FrpTunnelEditPage(),
                      ),
                      GoRoute(
                        path: ':tunnelId',
                        builder: (context, state) => FrpTunnelDetailPage(
                          tunnelId: state.pathParameters['tunnelId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) => FrpTunnelEditPage(
                              tunnelId: state.pathParameters['tunnelId'],
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    path: 'account',
                    builder: (context, state) => const ChangeCredentialsPage(),
                  ),
                  GoRoute(
                    path: 'devices',
                    builder: (context, state) => const DevicesPage(),
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