import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 设置主页:各设置项入口列表,后续设置项在此追加。
///
/// 当前只保留「外观」入口(本次搬运的毛玻璃 UI 所在页),
/// v2 补上其他设置项时在此追加。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('连接'),
            subtitle: const Text('服务器地址、端口与访问令牌'),
            trailing: const Icon(Icons.chevron_right),
            // 用 go 而不是 push:go_router 不会对 push 进来的路由跑 redirect,
            // 而「忘记服务器」正是靠 redirect 把人送回连接页的。
            onTap: () => context.go('/settings/connection'),
          ),
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
