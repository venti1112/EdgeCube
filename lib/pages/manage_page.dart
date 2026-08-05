import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../widgets/ec_preference.dart';
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
            ],
          ),
        ),
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
