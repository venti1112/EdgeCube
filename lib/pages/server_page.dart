import 'package:flutter/material.dart';
import '../widgets/placeholder_page.dart';

class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器')),
      body: const PlaceholderPage(
        icon: Icons.dns,
        title: '服务器',
        description: '在这里管理你的 Minecraft 服务器实例：创建、启动与停止。',
      ),
    );
  }
}
