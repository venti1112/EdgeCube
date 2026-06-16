import 'package:flutter/material.dart';

import 'players_page.dart';
import 'port_mapping_page.dart';

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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayersPage()),
              ),
            ),
            const SizedBox(height: 12),
            _ManageEntryTile(
              icon: Icons.lan_outlined,
              title: '端口映射',
              subtitle: '通过 frp 将服务器映射到公网访问',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PortMappingPage()),
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
