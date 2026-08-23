import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 设置主页:各设置项入口列表,后续设置项在此追加。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观'),
            subtitle: const Text('主题模式与主题色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/appearance'),
          ),
        ],
      ),
    );
  }
}
