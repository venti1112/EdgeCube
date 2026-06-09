import 'package:flutter/material.dart';

import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../widgets/placeholder_page.dart';

class ServerPage extends StatelessWidget {
  const ServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = InstanceScope.of(context);
    final selected = controller.selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器'),
        actions: [
          _InstanceSelectorButton(
            controller: controller,
            selected: selected,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑实例',
            onPressed:
                selected == null ? null : () => _editInstance(context, controller, selected),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: selected == null
          ? const PlaceholderPage(
              icon: Icons.dns_outlined,
              title: '还没有实例',
              description: '点击左上角的按钮新建一个服务器实例。',
            )
          : PlaceholderPage(
              icon: Icons.dns,
              title: selected.name,
              description: '实例文件夹：${selected.id}\n\n在这里管理该 Minecraft 服务器实例：启动、停止与配置。',
            ),
    );
  }

  Future<void> _editInstance(
    BuildContext context,
    InstanceController controller,
    Instance instance,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptName(
      context,
      title: '编辑显示名称',
      initialValue: instance.name,
    );
    if (name == null) return;
    try {
      await controller.rename(instance.id, name);
    } on DuplicateInstanceNameException {
      messenger.showSnackBar(SnackBar(content: Text('已存在同名实例：$name')));
    }
  }
}

/// AppBar 左上角的“选择实例”按钮，点击弹出实例列表底部弹窗。
class _InstanceSelectorButton extends StatelessWidget {
  const _InstanceSelectorButton({
    required this.controller,
    required this.selected,
  });

  final InstanceController controller;
  final Instance? selected;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      icon: const Icon(Icons.dns),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected?.name ?? '选择实例',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
      onPressed: () => _openSelector(context),
    );
  }

  Future<void> _openSelector(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _InstanceListSheet(controller: controller),
    );
  }
}

/// 实例列表底部弹窗：展示全部实例 + “新建实例”入口。
class _InstanceListSheet extends StatelessWidget {
  const _InstanceListSheet({required this.controller});

  final InstanceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instances = controller.instances;
    final selectedId = controller.selected?.id;

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
                '暂无实例，点击下方新建。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
                      leading: Icon(
                        instance.id == selectedId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: instance.id == selectedId
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(instance.name),
                      subtitle: Text(
                        instance.id,
                        style: theme.textTheme.bodySmall,
                      ),
                      selected: instance.id == selectedId,
                      onTap: () {
                        controller.select(instance.id);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建实例'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final name = await _promptName(
                context,
                title: '新建实例',
                initialValue: '新实例',
              );
              if (name == null) return;
              try {
                await controller.createInstance(name);
                navigator.pop();
              } on DuplicateInstanceNameException {
                messenger
                    .showSnackBar(SnackBar(content: Text('已存在同名实例：$name')));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 弹出一个文本输入对话框，返回去除首尾空白后的非空名称；取消或为空返回 null。
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String initialValue,
}) async {
  final textController = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '显示名称',
            hintText: '请输入实例名称',
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(textController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
  textController.dispose();
  if (result == null || result.isEmpty) return null;
  return result;
}
