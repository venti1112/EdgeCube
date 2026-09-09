import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'wizard_tile.dart';

/// 下载流程第 2 页(Java 版独有):选择服务端分类。
/// 固定四分类(与 V1 一致);分类下的具体服务端类型由 daemon
/// /catalog/server-types 提供,在服务端类型页按分类过滤展示。
class SelectCategoryPage extends StatelessWidget {
  const SelectCategoryPage({super.key});

  void _select(BuildContext context, String category) {
    context.push('/servers/instances/create/download/server?category=$category');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择服务端分类'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WizardTile(
            icon: Icons.storage_outlined,
            title: '原版',
            subtitle: 'Mojang 官方,纯净无插件',
            onTap: () => _select(context, 'vanilla'),
          ),
          const SizedBox(height: 12),
          WizardTile(
            icon: Icons.extension_outlined,
            title: '插件',
            subtitle: '支持 Bukkit/Spigot 插件(Paper 等)',
            onTap: () => _select(context, 'plugin'),
          ),
          const SizedBox(height: 12),
          WizardTile(
            icon: Icons.auto_awesome_mosaic_outlined,
            title: '模组',
            subtitle: 'Fabric 等模组加载器服务端',
            onTap: () => _select(context, 'mod'),
          ),
          const SizedBox(height: 12),
          WizardTile(
            icon: Icons.lan_outlined,
            title: '代理',
            subtitle: 'Velocity / BungeeCord 代理端',
            onTap: () => _select(context, 'proxy'),
          ),
        ],
      ),
    );
  }
}