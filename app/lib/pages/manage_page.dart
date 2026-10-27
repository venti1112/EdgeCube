import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 「管理」页：各管理子页的入口列表。
///
/// 排版：入口列表，点进去是子页（底栏/侧栏保持可见），条目是 Material 的 ListTile。
/// 存档 / FTP / SSH / 整合包 …那一长串入口还没有对应的功能页，
/// 落地一个往这里加一条。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('管理'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('玩家管理'),
            subtitle: const Text('在线玩家、白名单、封禁与 OP'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/players'),
          ),
          // 服务器配置：**入口文案是通用的**（不写「编辑 server.properties」这种），
          // 因为「这个实例用的是哪种配置」由 daemon 判断、进页面才知道，
          // 不在副标题上区分三种配置。
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('服务器配置'),
            subtitle: const Text('编辑服务端的配置文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/config'),
          ),
          // 网络映射：本机对外的几条路都收在这一页。
          // FRP 隧道与 UPnP 端口映射已经能用，STUN / DDNS 摆出来置灰。
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: const Text('网络映射'),
            subtitle: const Text('UPnP 端口映射与 FRP 隧道'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/network'),
          ),
          // 模组与插件：搜索、安装、更新检查、启停与删除。
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('模组与插件'),
            subtitle: const Text('搜索安装、检查更新、启用与删除'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/mods'),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('运行环境'),
            subtitle: const Text('Java 运行环境：下载 Zulu JDK、解压与删除'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/runtime'),
          ),
          // 主机终端：daemon 那台机器本身的 shell（不是实例控制台）。
          // 与实例无关，所以放在这组入口的最后。
          ListTile(
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('主机终端'),
            subtitle: const Text('打开守护进程所在机器的 shell'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/manage/shell'),
          ),
        ],
      ),
    );
  }
}
