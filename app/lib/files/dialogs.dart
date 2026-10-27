import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

/// 文件模块共用的小对话框：输入、确认、报错、加载遮罩、提示条。
///
/// 一律用 Material 的组件实现。

/// 单行文本输入对话框；返回去掉首尾空白的结果，取消返回 `null`。
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String confirmLabel = '确定',
}) => showDialog<String>(
  context: context,
  builder: (_) => _PromptDialog(
    title: title,
    label: label,
    initialValue: initialValue,
    confirmLabel: confirmLabel,
  ),
);

/// 输入框的 controller 由弹窗自己持有。`showDialog` 的 Future 是在
/// route 开始退场时就完成的，此时弹窗还要再建几帧 —— 在外面释放 controller
/// 会踩到「已释放还在用」的断言。
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void initState() {
    super.initState();
    // 选中初始文本：重命名时用户最常做的是直接覆盖整名
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('prompt_text_field'),
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// 压缩输出格式（与 daemon 的 `parse_compress_format` 一一对应）。
///
/// 解压不用选格式：daemon 按文件名自己认。
const List<({String value, String label})> compressFormats = [
  (value: 'zip', label: 'zip'),
  (value: 'tar.gz', label: 'tar.gz'),
  (value: 'tar.xz', label: 'tar.xz'),
  (value: 'tar.zst', label: 'tar.zst'),
];

/// 压缩对话框的返回值：包名 + 格式。
typedef ArchiveChoice = ({String name, String format});

/// 压缩对话框：问包名和输出格式，取消返回 `null`。
///
/// 名字**不用带后缀**：daemon 会按格式补，也会把已有的别的归档后缀换掉
/// （输入 `备份.zip` 选 tar.gz → `备份.tar.gz`）。
Future<ArchiveChoice?> promptArchive(
  BuildContext context, {
  String initialName = '压缩文件',
}) => showDialog<ArchiveChoice>(
  context: context,
  builder: (_) => _ArchiveDialog(initialName: initialName),
);

class _ArchiveDialog extends StatefulWidget {
  const _ArchiveDialog({required this.initialName});

  final String initialName;

  @override
  State<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends State<_ArchiveDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String _format = 'zip';

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, format: _format));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('压缩为'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('archive_name_field'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '压缩包名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('archive_format_field'),
          initialValue: _format,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '格式',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final format in compressFormats)
              DropdownMenuItem(value: format.value, child: Text(format.label)),
          ],
          onChanged: (value) => setState(() => _format = value ?? 'zip'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        key: const Key('archive_confirm'),
        onPressed: _submit,
        child: const Text('压缩'),
      ),
    ],
  );
}

/// 是 / 否确认框。
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('confirm_dialog_ok'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 报错对话框（标题固定「错误」，一个「知道了」）。
Future<void> showErrorDialog(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );

/// 跑一个异步动作，期间盖一个**不可取消**的加载对话框。
///
/// 返回 `(结果, 错误)`：调用方自己决定怎么报错（有的地方弹框、有的地方
/// 只记一条失败清单）。用 `removeRoute` 精确摘掉自己那个 route ——
/// 期间就算别的东西被推上来，也不会误 pop 掉。
Future<(T?, Object?)> runWithLoading<T>(
  BuildContext context,
  String message,
  Future<T> Function() action,
) => runWithProgress(context, ValueNotifier<String>(message), action);

/// 同 [runWithLoading]，差别是文案由 [progress] 驱动 ——
/// 批量上传这类「一长串子任务」要显示当前进度（`3/12`）。
Future<(T?, Object?)> runWithProgress<T>(
  BuildContext context,
  ValueListenable<String> progress,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, text, _) => Text(text),
            )),
          ],
        ),
      ),
    ),
  );
  navigator.push(route);
  try {
    return (await action(), null);
  } catch (error) {
    return (null, error);
  } finally {
    navigator.removeRoute(route);
  }
}

/// 一条轻提示。
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}
