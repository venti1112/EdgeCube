import 'package:flutter/material.dart';

import 'players_page.dart';
import 'port_mapping_page.dart';
import 'ftp_page.dart';
import 'mcp_page.dart';
import 'server_properties_page.dart';

/// 「管理」入口页：以卡片选择进入各管理子页面（玩家管理 / 端口映射），
/// 风格与新建实例向导中的选项卡一致。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ManageEntryTile(
              icon: Icons.people_outline,
              title: '玩家管理',
              subtitle: '在线玩家、白名单、封禁与 OP',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PlayersPage())),
            ),
            const SizedBox(height: 12),
            _ManageEntryTile(
              icon: Icons.tune,
              title: '服务器配置',
              subtitle: '编辑 server.properties',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerPropertiesPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ManageEntryTile(
              icon: Icons.lan_outlined,
              title: '网络映射',
              subtitle: 'UPnP 端口映射与 FRP 隧道',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PortMappingPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ManageEntryTile(
              icon: Icons.folder_shared_outlined,
              title: 'FTP 文件管理',
              subtitle: '通过 FTP 对外开放实例目录访问',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const FtpPage())),
            ),
            const SizedBox(height: 12),
            _ManageEntryTile(
              icon: Icons.hub_outlined,
              title: 'MCP 服务',
              subtitle: '供 AI Agent 获取数据与操作服务',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const McpPage())),
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
