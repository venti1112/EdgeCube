import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 「管理」入口页:以卡片选择进入各管理子页面。
/// 布局风格对齐 V1 管理页(V1: MiuixCard + 图标/标题/副标题/右箭头)。
/// 实例相关入口已收敛到「服务器」页(右上角选择实例菜单):本页仅列后台管理类入口。
class ManagePage extends StatelessWidget {
  const ManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ManageEntryTile(
          icon: Icons.people_outline,
          title: '玩家管理',
          subtitle: '在线玩家、白名单、封禁与 OP 管理',
          onTap: () => context.push('/manage/players'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.memory,
          title: '运行时',
          subtitle: '已安装的 Java/PHP/FRPC 运行时',
          onTap: () => context.push('/manage/runtimes'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.hourglass_bottom_outlined,
          title: '任务',
          subtitle: '下载/实例操作等后台任务与进度',
          onTap: () => context.push('/manage/tasks'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.extension_outlined,
          title: '插件/模组',
          subtitle: '管理插件/模组,从 Modrinth/Poggit 下载',
          onTap: () => context.push('/manage/mods'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.hub_outlined,
          title: '内网穿透',
          subtitle: 'frpc 隧道管理,frpc 进程全局唯一',
          onTap: () => context.push('/manage/frp'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.tune,
          title: '服务器配置',
          subtitle: '可视化编辑当前实例的服务器配置文件',
          onTap: () => context.push('/manage/config'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.archive_outlined,
          title: '实例迁移',
          subtitle: '导出当前实例为归档,或从归档导入还原为新实例',
          onTap: () => context.push('/manage/migrate'),
        ),
        const SizedBox(height: 12),
        _ManageEntryTile(
          icon: Icons.system_update_alt,
          title: '服务端更新',
          subtitle: '检查并更新当前实例的服务端核心版本',
          onTap: () => context.push('/manage/update-server'),
        ),
      ],
    );
  }
}

/// 管理入口卡片(对齐 V1 的「图标 + 标题 + 副标题 + 右箭头」样式)。
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
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 36, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}