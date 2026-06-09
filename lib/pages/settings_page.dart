import 'package:flutter/material.dart';
import '../widgets/placeholder_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: const PlaceholderPage(
        icon: Icons.settings,
        title: '设置',
        description: '调整应用主题、服务器默认参数与通知偏好。',
      ),
    );
  }
}
