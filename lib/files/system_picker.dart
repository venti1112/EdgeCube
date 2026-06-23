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
/// 返回所选路径；用户取消返回 null。
Future<String?> pickFromSystem(
  BuildContext context, {
  required SystemPickMode mode,
}) async {
  final root = await StoragePermission.externalStorageRoot();
  final startDir = Directory(root ?? '/');
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => _SystemPickerPage(startDir: startDir, mode: mode),
    ),
  );
}

class _SystemPickerPage extends StatefulWidget {
  const _SystemPickerPage({required this.startDir, required this.mode});

  final Directory startDir;
  final SystemPickMode mode;

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
          if (pickingDir)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_current.path),
              child: Text(
                context.tr('picker.selectHere'),
                style: TextStyle(color: theme.colorScheme.onPrimary),
              ),
            ),
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
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          context.tr('picker.emptyFolder'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final entry = _entries[i];
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
