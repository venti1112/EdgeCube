import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'download/category_page.dart';
import 'download/wizard.dart';
import 'providers.dart';

/// 新建实例向导：输入名称 → 选择创建方式。
///
/// 排版：名称输入框 → 24 间距 → 一列卡片磁贴
/// （图标 + 标题 + 说明）。
///
/// **已实现**：「创建空实例」与「下载服务端」。后者的实例是在**下载向导的最后一步**
/// 才建的（先选类型 / 版本，再建实例并下载，中途反悔不会留下空实例；
/// 下载失败也会把刚建的那个删掉，见 `download/progress_page.dart`）。
/// 导入那三种还依赖没落地的能力（本机文件上传、整合包解析），摆出来但置灰。
class CreateInstancePage extends ConsumerStatefulWidget {
  const CreateInstancePage({super.key});

  @override
  ConsumerState<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends ConsumerState<CreateInstancePage> {
  final _nameController = TextEditingController(text: '新实例');
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 创建空实例：不下载也不导入，直接建目录 + 元数据。
  Future<void> _createEmpty() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _error('实例名称不能为空');
      return;
    }
    final api = ref.read(instanceApiProvider);
    if (api == null) {
      await _error('还没有连接到守护进程');
      return;
    }

    setState(() => _creating = true);
    try {
      await api.create(name: name);
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('已创建「$name」')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      await _error(describeInstanceError(e));
    }
  }

  Future<void> _error(String message) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('创建失败'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  /// 「下载服务端」：进向导（分类 → 服务端 → 版本 → 下载）。
  ///
  /// 这一页只做两件事：**校验名字**（要一路带到向导最后一步）与**接结果**。
  /// 实例由向导的最后一步创建 —— 中途反悔就什么都不会留下。
  Future<void> _downloadServer() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _error('实例名称不能为空');
      return;
    }

    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        // 流程根要有个名字：最后一步靠它一次弹回这里
        settings: const RouteSettings(name: kDownloadFlowRootRouteName),
        builder: (_) => DownloadCategoryPage(wizard: DownloadWizard(name: name)),
      ),
    );
    if (!mounted || finished != true) return;

    ref.invalidate(instanceListProvider);
    ref.invalidate(selectedInstanceDetailProvider);
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('已创建「$name」，服务端已下载完成')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('新建实例'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('create_instance_name'),
            controller: _nameController,
            enabled: !_creating,
            decoration: const InputDecoration(
              labelText: '实例名称',
              hintText: '例如 生存服',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _ServerTypeTile(
            key: const Key('create_instance_empty'),
            icon: Icons.create_new_folder_outlined,
            title: '创建空实例',
            subtitle: '只建一个空的实例目录，服务端文件稍后自己放进去',
            onTap: _creating ? null : _createEmpty,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            key: const Key('create_instance_download'),
            icon: Icons.cloud_download_outlined,
            title: '下载服务端',
            subtitle: '从官方源下载原版 / 各类服务端，建好实例并自动写好启动命令',
            onTap: _creating ? null : _downloadServer,
          ),
          const SizedBox(height: 12),
          const _ServerTypeTile(
            icon: Icons.file_upload_outlined,
            title: '导入服务端',
            subtitle: '选择本机的 jar / phar 文件导入',
          ),
          const SizedBox(height: 12),
          const _ServerTypeTile(
            icon: Icons.archive_outlined,
            title: '导入压缩包',
            subtitle: '把服务端压缩包解压到新实例',
          ),
          const SizedBox(height: 12),
          const _ServerTypeTile(
            icon: Icons.inventory_2_outlined,
            title: '导入整合包',
            subtitle: '解析整合包并安装服务端与模组',
          ),
        ],
      ),
    );
  }
}

/// 创建方式磁贴（图标 + 标题 + 说明的卡片）。
///
/// [onTap] 为 `null` 时置灰并标注「即将支持」。
class _ServerTypeTile extends StatelessWidget {
  const _ServerTypeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, size: 28),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : Text(
                '即将支持',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}
