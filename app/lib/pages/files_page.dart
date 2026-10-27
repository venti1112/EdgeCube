import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';
import '../files/file_browser.dart';
import '../instance/providers.dart';

/// 「文件」页：管理当前选中实例目录里的文件（浏览、编辑、上传下载、压缩解压…）。
///
/// 排版：标题带实例名；没选实例时给空态。切换实例会把
/// 浏览器整个重建（`ValueKey`），于是回到新实例的根目录、多选与搜索都清掉。
class FilesPage extends ConsumerWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(selectedInstanceDetailProvider).value?.instance;
    final connected = ref.watch(isConnectedProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(instance == null ? '文件' : '文件 · ${instance.name}'),
      ),
      body: instance == null
          ? _EmptyState(connected: connected)
          : FileBrowser(
              key: ValueKey(instance.id),
              instanceId: instance.id,
            ),
    );
  }
}

/// 没有选中实例（或压根没连上）时的空态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 72,
            color: connected ? scheme.primary : scheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            connected ? '还没有实例' : '未连接到守护进程',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              connected
                  ? '请先在「服务器」页新建并选择一个实例，再管理其文件。'
                  : '连上之后这里会显示所选实例的文件。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
