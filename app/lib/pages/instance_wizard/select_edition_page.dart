import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'wizard_tile.dart';

/// 下载流程第 1 页:选择版本类型(Java 版 / 基岩版)。
/// - Java 版 → 分类页(原版/插件/模组/代理)
/// - 基岩版 → 直接进服务端类型页(bedrock 分类)
class SelectEditionPage extends StatelessWidget {
  const SelectEditionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择版本类型'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          WizardTile(
            icon: Icons.coffee_outlined,
            title: 'Java 版',
            subtitle: '原版 / 插件 / 模组 / 代理服务端',
            onTap: () =>
                context.push('/servers/instances/create/download/category'),
          ),
          const SizedBox(height: 12),
          WizardTile(
            icon: Icons.diamond_outlined,
            title: '基岩版',
            subtitle: 'PocketMine 等基岩服务端',
            onTap: () => context
                .push('/servers/instances/create/download/server?category=bedrock'),
          ),
        ],
      ),
    );
  }
}