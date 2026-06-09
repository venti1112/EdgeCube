import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'file_entry.dart';
import 'file_service.dart';
import 'folder_picker.dart';
import 'storage_permission.dart';
import 'system_picker.dart';

enum _FileAction { rename, move, copy, export, delete }

/// 浏览并管理单个实例文件夹内的文件。
///
/// 导航被限制在 [rootDir] 之内，无法越过实例根目录。
class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key, required this.rootDir});

  final Directory rootDir;

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  static const _service = FileService();

  late Directory _current = widget.rootDir;
  List<FileEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FileBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换实例后根目录变化，回到新实例根目录。
    if (!p.equals(oldWidget.rootDir.path, widget.rootDir.path)) {
      _current = widget.rootDir;
      _load();
    }
  }

  bool get _atRoot => p.equals(_current.path, widget.rootDir.path);

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _service.list(_current);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  void _enter(FileEntry entry) {
    if (!entry.isDirectory) return;
    _current = Directory(entry.path);
    _load();
  }

  void _goUp() {
    if (_atRoot) return;
    _current = Directory(p.dirname(_current.path));
    _load();
  }

  Future<void> _importFile() async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final sourcePath =
        await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) return;
    try {
      await _service.importFile(sourcePath, _current);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('导入完成')));
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText(context, title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.isEmpty) return;
    try {
      await _service.createDirectory(_current, name);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _onAction(_FileAction action, FileEntry entry) async {
    switch (action) {
      case _FileAction.rename:
        await _rename(entry);
      case _FileAction.move:
        await _moveOrCopy(entry, isMove: true);
      case _FileAction.copy:
        await _moveOrCopy(entry, isMove: false);
      case _FileAction.export:
        await _export(entry);
      case _FileAction.delete:
        await _delete(entry);
    }
  }

  Future<void> _rename(FileEntry entry) async {
    final name = await _promptText(
      context,
      title: '重命名',
      label: '新名称',
      initialValue: entry.name,
    );
    if (name == null || name.isEmpty) return;
    try {
      await _service.rename(entry.path, name);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _moveOrCopy(FileEntry entry, {required bool isMove}) async {
    final dest = await pickFolder(
      context,
      rootDir: widget.rootDir,
      title: isMove ? '移动到' : '复制到',
      disabledPath: entry.isDirectory ? entry.path : null,
    );
    if (dest == null) return;
    try {
      if (isMove) {
        await _service.move(entry.path, Directory(dest));
      } else {
        await _service.copy(entry.path, Directory(dest));
      }
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _export(FileEntry entry) async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final destDir =
        await pickFromSystem(context, mode: SystemPickMode.directory);
    if (destDir == null) return;
    try {
      await _service.exportTo(entry.path, destDir);
      messenger.showSnackBar(const SnackBar(content: Text('导出完成')));
    } catch (e) {
      _showError(e);
    }
  }

  /// 确保已获得「管理全部文件」权限；未授予则弹窗引导用户去系统设置开启。
  Future<bool> _ensurePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要文件访问权限'),
        content: const Text(
          '导入和导出需要「所有文件访问权限」。点击「去授权」后，请在系统设置中为本应用打开该权限，再返回重试。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去授权'),
          ),
        ],
      ),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }

  Future<void> _delete(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${entry.name}」吗？${entry.isDirectory ? '该文件夹及其内容将被删除。' : ''}'),
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
    if (confirmed != true) return;
    try {
      await _service.delete(entry.path);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _Toolbar(
          atRoot: _atRoot,
          relativePath: _atRoot
              ? '根目录'
              : p.relative(_current.path, from: widget.rootDir.path),
          onUp: _goUp,
          onImport: _importFile,
          onNewFolder: _createFolder,
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                        '此文件夹为空',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (_, i) {
                          final entry = _entries[i];
                          return ListTile(
                            leading: Icon(entry.isDirectory
                                ? Icons.folder
                                : Icons.insert_drive_file_outlined),
                            title: Text(entry.name),
                            subtitle: Text(_subtitle(entry)),
                            onTap: entry.isDirectory ? () => _enter(entry) : null,
                            trailing: PopupMenuButton<_FileAction>(
                              onSelected: (a) => _onAction(a, entry),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: _FileAction.rename,
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: _FileAction.move,
                                  child: Text('移动'),
                                ),
                                PopupMenuItem(
                                  value: _FileAction.copy,
                                  child: Text('复制'),
                                ),
                                PopupMenuItem(
                                  value: _FileAction.export,
                                  child: Text('导出'),
                                ),
                                PopupMenuItem(
                                  value: _FileAction.delete,
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  String _subtitle(FileEntry entry) {
    if (entry.isDirectory) return '文件夹';
    return _formatSize(entry.size);
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.atRoot,
    required this.relativePath,
    required this.onUp,
    required this.onImport,
    required this.onNewFolder,
  });

  final bool atRoot;
  final String relativePath;
  final VoidCallback onUp;
  final VoidCallback onImport;
  final VoidCallback onNewFolder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: '上一级',
            onPressed: atRoot ? null : onUp,
          ),
          Expanded(
            child: Text(
              relativePath,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: onNewFolder,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入文件',
            onPressed: onImport,
          ),
        ],
      ),
    );
  }
}

/// 通用单行文本输入对话框，返回去除首尾空白的结果；取消返回 null。
Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
