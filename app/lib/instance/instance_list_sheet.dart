import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 实例列表底部弹窗：全部实例 + 新建入口。
///
/// 排版照 V1 的 `_InstanceListSheet`：标题 → 空态提示 / 列表（单选图标 +
/// 名称 + id + 删除按钮）→ 分隔线 → 「新建实例」。
class InstanceListSheet extends ConsumerWidget {
  const InstanceListSheet({super.key});

  /// 打开弹窗。
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const InstanceListSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = ref.watch(instanceListProvider).value;
    final instances = list?.instances ?? const <InstanceSummary>[];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('选择实例', style: theme.textTheme.titleMedium),
          ),
          if (instances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '还没有实例，先在下面新建一个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final instance in instances)
                    ListTile(
                      key: Key('instance_row_${instance.id}'),
                      leading: Icon(
                        instance.selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: instance.selected ? scheme.primary : null,
                      ),
                      title: Text(instance.name),
                      subtitle: Text(
                        instance.id,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                        onPressed: () => confirmDeleteInstance(
                          context,
                          ref,
                          instance,
                        ),
                      ),
                      onTap: () => _select(context, ref, instance),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('instance_new_row'),
            leading: const Icon(Icons.add),
            title: const Text('新建实例'),
            onTap: () async {
              final navigator = Navigator.of(context);
              await context.push('/instance/create');
              // 新建页回来（无论成没成）都刷一次列表
              ref.invalidate(instanceListProvider);
              if (navigator.canPop()) navigator.pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    InstanceSummary instance,
  ) async {
    final api = ref.read(instanceApiProvider);
    if (api == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await api.select(instance.id);
      ref.invalidate(instanceListProvider);
      ref.invalidate(selectedInstanceDetailProvider);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('切换实例失败：${describeInstanceError(e)}')),
      );
      return;
    }
    if (navigator.canPop()) navigator.pop();
  }
}

/// 两步确认后删除实例（V1 的做法：先普通确认，再强调不可恢复）。
Future<void> confirmDeleteInstance(
  BuildContext context,
  WidgetRef ref,
  InstanceSummary instance,
) async {
  final first = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('删除实例'),
      content: Text('确定删除「${instance.name}」吗？它的实例目录及其中所有文件都会被删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return;

  final second = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('此操作不可恢复'),
      content: Text('「${instance.name}」的全部文件将被永久删除，无法撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('确认删除'),
        ),
      ],
    ),
  );
  if (second != true || !context.mounted) return;

  final api = ref.read(instanceApiProvider);
  if (api == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await api.delete(instance.id);
    ref.invalidate(instanceListProvider);
    ref.invalidate(selectedInstanceDetailProvider);
    messenger?.showSnackBar(SnackBar(content: Text('已删除「${instance.name}」')));
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('删除失败：${describeInstanceError(e)}')),
    );
  }
}
