import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import 'file_entry.dart';
import 'file_service.dart';

/// 弹出一个实例内的文件夹选择对话框，返回所选目标目录的路径；取消返回 null。
///
/// 导航被限制在 [rootDir] 之内；[disabledPath] 用于禁用「移入自身」的目录。
Future<String?> pickFolder(
  BuildContext context, {
  required Directory rootDir,
  required String title,
  String? disabledPath,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderPickerDialog(
      rootDir: rootDir,
      title: title,
      disabledPath: disabledPath,
    ),
  );
}

class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({
    required this.rootDir,
    required this.title,
    this.disabledPath,
  });

  final Directory rootDir;
  final String title;
  final String? disabledPath;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  static const _service = FileService();

  late Directory _current = widget.rootDir;
  List<FileEntry> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _service.list(_current);
    if (!mounted) return;
    setState(() {
      _folders = all.where((e) => e.isDirectory).toList();
      _loading = false;
    });
  }

  bool get _atRoot => p.equals(_current.path, widget.rootDir.path);

  String _relativeLabel(BuildContext context) {
    if (_atRoot) return context.tr('folderPicker.rootDirectory');
    return p.relative(_current.path, from: widget.rootDir.path);
  }

  void _enter(String path) {
    _current = Directory(path);
    _load();
  }

  void _goUp() {
    _current = Directory(p.dirname(_current.path));
    _load();
  }

  Future<void> _createFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptFolderName(context);
    if (name == null || name.isEmpty) return;
    try {
      await _service.createDirectory(_current, name);
      await _load();
    } on FileConflictException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: context.tr('folderPicker.upOneLevel'),
                  onPressed: _atRoot ? null : _goUp,
                ),
                Expanded(
                  child: Text(
                    _relativeLabel(context),
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: context.tr('folderPicker.newFolder'),
                  onPressed: _createFolder,
                ),
              ],
            ),
            const Divider(height: 1),
            SizedBox(
              height: 240,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                  ? Center(
                      child: Text(
                        context.tr('folderPicker.noSubfolders'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (_, i) {
                        final folder = _folders[i];
                        final disabled =
                            widget.disabledPath != null &&
                            p.equals(folder.path, widget.disabledPath!);
                        return ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(folder.name),
                          enabled: !disabled,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _enter(folder.path),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current.path),
          child: Text(context.tr('folderPicker.moveHere')),
        ),
      ],
    );
  }
}

Future<String?> _promptFolderName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.tr('folderPicker.newFolder')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.tr('folderPicker.folderName'),
        ),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.tr('common.cancel')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(context.tr('common.ok')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
