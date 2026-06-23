import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import 'instance_export_page.dart';
import 'players_page.dart';
import 'port_mapping_page.dart';
import 'ftp_page.dart';
import 'mcp_page.dart';
import 'server_properties_page.dart';
import 'shell_page.dart';
import 'ssh_page.dart';

/// 「管理」入口页：以卡片选择进入各管理子页面（玩家管理 / 端口映射），
/// 风格与新建实例向导中的选项卡一致。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('manage.title'))),
      body: SafeArea(
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
            _ManageEntryTile(
              icon: Icons.tune,
              title: context.tr('manage.serverProperties.title'),
              subtitle: context.tr('manage.serverProperties.subtitle'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerPropertiesPage()),
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
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}
