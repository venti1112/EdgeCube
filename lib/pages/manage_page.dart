import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../instance/create_download_edition_page.dart';
import '../instance/create_instance_page.dart';
import '../instance/download_session.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../server/server_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/error_dialog.dart';
import 'allay_properties_page.dart';
import 'instance_export_page.dart';
import 'mods_plugins_page.dart';
import 'players_page.dart';
import 'port_mapping_page.dart';
import 'ftp_page.dart';
import 'mcp_page.dart';
import 'pnx_properties_page.dart';
import 'runtime_page.dart';
import 'server_properties_page.dart';
import 'shell_page.dart';
import 'ssh_page.dart';

/// 「管理」入口页：以卡片选择进入各管理子页面（玩家管理 / 端口映射），
/// 风格与新建实例向导中的选项卡一致。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('manage.title'), showBack: false),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ManageEntryTile(
                icon: Icons.people_outline,
                title: context.tr('manage.players.title'),
                subtitle: context.tr('manage.players.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const PlayersPage())),
              ),
              const SizedBox(height: 12),
              _ServerConfigTile(),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.extension_outlined,
                title: context.tr('manage.modsPlugins.title'),
                subtitle: context.tr('manage.modsPlugins.subtitle'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ModsPluginsPage()),
                ),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.lan_outlined,
                title: context.tr('manage.network.title'),
                subtitle: context.tr('manage.network.subtitle'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PortMappingPage()),
                ),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.folder_shared_outlined,
                title: context.tr('manage.ftp.title'),
                subtitle: context.tr('manage.ftp.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const FtpPage())),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.dns_outlined,
                title: context.tr('manage.ssh.title'),
                subtitle: context.tr('manage.ssh.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SshPage())),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.hub_outlined,
                title: context.tr('manage.mcp.title'),
                subtitle: context.tr('manage.mcp.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const McpPage())),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.memory,
                title: context.tr('manage.runtime.title'),
                subtitle: context.tr('manage.runtime.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const RuntimePage())),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.terminal,
                title: context.tr('manage.shell.title'),
                subtitle: context.tr('manage.shell.subtitle'),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ShellPage())),
              ),
              const SizedBox(height: 12),
              _ManageEntryTile(
                icon: Icons.archive_outlined,
                title: context.tr('manage.export.title'),
                subtitle: context.tr('manage.export.subtitle'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InstanceExportPage()),
                ),
              ),
              const SizedBox(height: 12),
              const _UpdateServerTile(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 服务端更新器入口：复用下载流程的「选择版本」页，在更新模式下替换已有实例
/// 的服务端文件，不创建新实例、不改配置，强制走官方源。
///
/// 点击后进入独立的实例选择页，选择要更新的实例后进入下载流程。
/// 更新前会检查服务端是否正在运行（运行中提示先停止）。
class _UpdateServerTile extends StatelessWidget {
  const _UpdateServerTile();

  Future<void> _startUpdate(BuildContext context) async {
    final ctrl = InstanceScope.of(context);

    // 无实例时提示。
    if (ctrl.instances.isEmpty) {
      showErrorDialog(context, context.tr('manage.updateServer.noInstance'));
      return;
    }

    // 服务端运行时不允许更新，提示先停止。
    if (await ServerService().isRunning()) {
      if (!context.mounted) return;
      showErrorDialog(
        context,
        context.tr('manage.updateServer.serverRunning'),
      );
      return;
    }

    if (!context.mounted) return;
    // 本页注册为下载流程根路由：finishDownloadFlow 的 popUntil 会弹回本页，
    // 再 pop 一次回到管理页根。
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: kDownloadFlowRootRouteName),
        builder: (_) => const SelectInstanceForUpdatePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ManageEntryTile(
      icon: Icons.system_update_alt,
      title: context.tr('manage.updateServer.title'),
      subtitle: context.tr('manage.updateServer.subtitle'),
      onTap: () => _startUpdate(context),
    );
  }
}

/// 服务端更新器第 1 页：选择要更新的实例。
///
/// 以卡片列表展示全部实例，当前选中实例以单选图标高亮。选定后创建更新模式的
/// [DownloadSession] 并进入下载流程的「选择版本」页。
class SelectInstanceForUpdatePage extends StatelessWidget {
  const SelectInstanceForUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = InstanceScope.of(context);
    final theme = MiuixTheme.of(context);
    final selectedId = ctrl.selected?.id;
    final instances = ctrl.instances;

    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('manage.updateServer.selectInstance'),
        showBack: true,
      ),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              for (final instance in instances) ...[
                EcCardTile(
                  leading: Icon(
                    instance.id == selectedId
                        ? Icons.radio_button_checked
                        : Icons.dns_outlined,
                    size: 36,
                    color: instance.id == selectedId
                        ? theme.colors.primary
                        : null,
                  ),
                  title: instance.name,
                  summary: instance.id,
                  onTap: () => _enterUpdateFlow(context, ctrl, instance),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _enterUpdateFlow(
    BuildContext context,
    InstanceController ctrl,
    InstanceSummary instance,
  ) async {
    final session = DownloadSession.forUpdate(
      controller: ctrl,
      updateInstanceId: instance.id,
    );
    // SelectEditionPage 不再注册为流程根路由；本页（实例选择页）才是根路由，
    // 这样 finishDownloadFlow 的 popUntil 会弹回本页，再 pop 一次回到管理页。
    await Navigator.of(context).push<CreateInstanceResult>(
      MaterialPageRoute(
        builder: (_) => SelectEditionPage(session: session),
      ),
    );
  }
}

/// 服务器配置入口：自动检测 pnx.yml / server-settings.yml / server.properties
/// 并导航到对应编辑页。
class _ServerConfigTile extends StatefulWidget {
  const _ServerConfigTile();

  @override
  State<_ServerConfigTile> createState() => _ServerConfigTileState();
}

/// 检测到的服务端配置类型。null 表示仍在加载。
enum _ServerConfigKind { pnx, allay, vanilla }

class _ServerConfigTileState extends State<_ServerConfigTile> {
  _ServerConfigKind? _kind; // null = loading
  InstanceController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = InstanceScope.of(context);
    if (ctrl != _ctrl) {
      _ctrl?.removeListener(_detect);
      _ctrl = ctrl;
      _ctrl?.addListener(_detect);
    }
    _detect();
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_detect);
    super.dispose();
  }

  Future<void> _detect() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final instance = ctrl.selected;
    if (instance == null) {
      if (mounted) setState(() => _kind = _ServerConfigKind.vanilla);
      return;
    }
    final dir = await ctrl.directoryFor(instance);
    // 优先级：pnx.yml > server-settings.yml (Allay) > server.properties。
    if (File(p.join(dir.path, 'pnx.yml')).existsSync()) {
      if (mounted) setState(() => _kind = _ServerConfigKind.pnx);
      return;
    }
    if (File(p.join(dir.path, 'server-settings.yml')).existsSync()) {
      if (mounted) setState(() => _kind = _ServerConfigKind.allay);
      return;
    }
    if (mounted) setState(() => _kind = _ServerConfigKind.vanilla);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final title = switch (kind) {
      _ServerConfigKind.pnx => context.tr('manage.pnxProperties.title'),
      _ServerConfigKind.allay => context.tr('manage.allayProperties.title'),
      _ServerConfigKind.vanilla => context.tr('manage.serverProperties.title'),
      null => context.tr('manage.serverProperties.title'),
    };
    final subtitle = switch (kind) {
      _ServerConfigKind.pnx => context.tr('manage.pnxProperties.subtitle'),
      _ServerConfigKind.allay => context.tr('manage.allayProperties.subtitle'),
      _ServerConfigKind.vanilla => context.tr(
        'manage.serverProperties.subtitle',
      ),
      null => context.tr('manage.serverProperties.subtitle'),
    };
    return _ManageEntryTile(
      icon: Icons.tune,
      title: title,
      subtitle: subtitle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => switch (kind) {
            _ServerConfigKind.pnx => const PnxPropertiesPage(),
            _ServerConfigKind.allay => const AllayPropertiesPage(),
            _ServerConfigKind.vanilla => const ServerPropertiesPage(),
            null => const ServerPropertiesPage(),
          },
        ),
      ),
    );
  }
}

/// 管理入口卡片。
class _ManageEntryTile extends StatelessWidget {
  const _ManageEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MiuixCard(
      child: MiuixBasicComponent(
        startAction: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(icon, size: 36),
        ),
        content: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              Text(subtitle),
            ],
          ),
        ],
        endActions: [const Icon(Icons.chevron_right)],
        onClick: onTap,
      ),
    );
  }
}
