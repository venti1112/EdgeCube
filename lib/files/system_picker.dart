import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import 'file_entry.dart';
import 'file_service.dart';
import 'storage_permission.dart';

enum SystemPickMode { file, directory }

/// 打开自建的系统文件浏览器，从外部存储中选择文件或目录。
///
/// 调用前需已获得「管理全部文件」权限（由调用方负责确权）。
/// [allowedExtensions] 仅在 [SystemPickMode.file] 下生效：限制可见/可选文件的
/// 扩展名（大小写不敏感，含「.」，如 `.jar`、`.tar.gz`）；为 null 或空表示不过滤。
/// 返回所选路径；用户取消返回 null。
Future<String?> pickFromSystem(
  BuildContext context, {
  required SystemPickMode mode,
  List<String>? allowedExtensions,
}) async {
  final root = await StoragePermission.externalStorageRoot();
  final startDir = Directory(root ?? '/');
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => _SystemPickerPage(
        startDir: startDir,
        mode: mode,
        allowedExtensions: allowedExtensions,
      ),
    ),
  );
}

class _SystemPickerPage extends StatefulWidget {
  const _SystemPickerPage({
    required this.startDir,
    required this.mode,
    this.allowedExtensions,
  });

  final Directory startDir;
  final SystemPickMode mode;

  /// 仅在选择文件（[SystemPickMode.file]）时生效：限制可见/可选文件的扩展名
  /// （大小写不敏感，含「.」，如 `.jar`、`.tar.gz`）。为 null 或空表示不过滤。
  final List<String>? allowedExtensions;

  @override
  State<_SystemPickerPage> createState() => _SystemPickerPageState();
}

class _SystemPickerPageState extends State<_SystemPickerPage> {
  static const _service = FileService();

  late Directory _current = widget.startDir;
  List<FileEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.list(_current);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('picker.cannotReadDir', {'error': e.toString()});
        _loading = false;
      });
    }
  }

  /// 是否已到达内部存储根目录（不允许再返回上级）。
  bool get _atRoot => p.equals(_current.path, widget.startDir.path);

  bool get _canGoUp => !_atRoot;

  void _enter(FileEntry entry) {
    _current = Directory(entry.path);
    _load();
  }

  void _goUp() {
    if (!_canGoUp) return;
    _current = Directory(p.dirname(_current.path));
    _load();
  }

  /// 在当前目录下新建文件夹（仅目录选择模式可用）。
  Future<void> _createFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptFolderName(context);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _service.createDirectory(_current, name);
      await _load();
    } on FileConflictException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('picker.createFolderFailed', {'error': e.toString()}),
          ),
        ),
      );
    }
  }

  /// 是否启用了扩展名过滤（仅文件选择模式且给定了非空列表）。
  bool get _hasFilter =>
      widget.mode == SystemPickMode.file &&
      widget.allowedExtensions != null &&
      widget.allowedExtensions!.isNotEmpty;

  /// 条目在当前过滤下是否可见：目录恒显示，文件需扩展名匹配。
  bool _isVisible(FileEntry entry) {
    if (entry.isDirectory) return true;
    if (!_hasFilter) return true;
    final lower = entry.name.toLowerCase();
    return widget.allowedExtensions!.any(
      (ext) => lower.endsWith(ext.toLowerCase()),
    );
  }

  /// 顶部类型过滤提示条：告知用户当前仅显示哪些扩展名的文件。
  Widget _buildFilterHint(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('picker.filterHint', {
                'types': widget.allowedExtensions!.join(' '),
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickingDir = widget.mode == SystemPickMode.directory;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pickingDir
              ? context.tr('picker.selectTargetFolder')
              : context.tr('picker.selectFileToImport'),
        ),
        actions: [
          if (pickingDir) ...[
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: context.tr('picker.newFolder'),
              onPressed: _createFolder,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_current.path),
                child: Text(context.tr('picker.selectHere')),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: context.tr('picker.upOneLevel'),
              onPressed: _canGoUp ? _goUp : null,
            ),
            title: Text(
              _atRoot ? context.tr('picker.internalStorage') : _current.path,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          if (_hasFilter) _buildFilterHint(theme),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final visible = _entries.where(_isVisible).toList();
    if (visible.isEmpty) {
      // 文件夹本身为空，或所有文件都被类型过滤掉了，分别给出文案。
      final filteredOut = _hasFilter && _entries.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            filteredOut
                ? context.tr('picker.noMatchingFiles', {
                    'types': widget.allowedExtensions!.join(' '),
                  })
                : context.tr('picker.emptyFolder'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final entry = visible[i];
        final selectableFile =
            widget.mode == SystemPickMode.file && entry.isFile;
        return ListTile(
          leading: Icon(
            entry.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined,
          ),
          title: Text(entry.name),
          trailing: entry.isDirectory ? const Icon(Icons.chevron_right) : null,
          onTap: entry.isDirectory
              ? () => _enter(entry)
              : selectableFile
              ? () => Navigator.of(context).pop(entry.path)
              : null,
        );
      },
    );
  }
}

/// 弹出输入框让用户输入新文件夹名称；取消或留空返回 null。
Future<String?> _promptFolderName(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.tr('picker.newFolder')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.tr('picker.folderName')),
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
