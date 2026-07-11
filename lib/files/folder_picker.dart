import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import 'file_entry.dart';
import 'file_search_bar.dart';
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

  /// 搜索状态：搜索模式开关、是否递归、进行中标志、查询输入与结果（仅目录）。
  bool _searchMode = false;
  bool _searchRecursive = false;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  List<FileEntry> _searchResults = [];
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_runSearch);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_runSearch);
    _searchController.dispose();
    super.dispose();
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

  // —— 搜索（文件夹选择器只搜目录）——

  void _enterSearch() {
    setState(() {
      _searchMode = true;
      _searchController.clear();
      _searchResults = [];
    });
  }

  void _exitSearch() {
    setState(() {
      _searchMode = false;
      _searchController.clear();
      _searchResults = [];
      _searching = false;
    });
  }

  void _toggleSearchRecursive(bool value) {
    setState(() => _searchRecursive = value);
    _runSearch();
  }

  Future<void> _runSearch() async {
    if (!_searchMode) return;
    final token = ++_searchToken;
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await _service.search(
      _current,
      _searchController.text,
      recursive: _searchRecursive,
    );
    if (!mounted || token != _searchToken || !_searchMode) return;
    setState(() {
      // 文件夹选择器只关心目录。
      _searchResults = results.where((e) => e.isDirectory).toList();
      _searching = false;
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
    if (_atRoot) return;
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

  /// 单个文件夹列表项。[inSearch] 为 true（搜索结果）时点击进入该目录并退出搜索，
  /// 副标题显示相对当前目录的路径。
  Widget _buildFolderTile(
    FileEntry folder,
    ThemeData theme, {
    bool inSearch = false,
  }) {
    final disabled =
        widget.disabledPath != null &&
        p.equals(folder.path, widget.disabledPath!);
    final rel = p.relative(folder.path, from: _current.path);
    return ListTile(
      leading: Icon(folder.isLink ? Icons.link : Icons.folder),
      title: Text(folder.name),
      subtitle: inSearch && rel.contains(p.separator)
          ? Text(rel, style: theme.textTheme.bodySmall)
          : null,
      enabled: !disabled,
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        if (inSearch) {
          _exitSearch();
          _enter(folder.path);
        } else {
          _enter(folder.path);
        }
      },
    );
  }

  /// 搜索结果区（只含目录）。
  Widget _buildSearchBody(ThemeData theme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          context.tr('fileSearch.prompt'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          context.tr('fileSearch.noResults'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (_, i) =>
          _buildFolderTile(_searchResults[i], theme, inSearch: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // 搜索/未到根目录时拦截系统返回键：先退出搜索，其次回上一级；根目录才关闭。
      canPop: _atRoot && !_searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchMode) {
          _exitSearch();
          return;
        }
        _goUp();
      },
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchMode)
                FileSearchBar(
                  controller: _searchController,
                  recursive: _searchRecursive,
                  onRecursiveChanged: _toggleSearchRecursive,
                  onClose: _exitSearch,
                )
              else
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
                      icon: const Icon(Icons.search),
                      tooltip: context.tr('fileSearch.search'),
                      onPressed: _enterSearch,
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
                child: _searchMode
                    ? _buildSearchBody(theme)
                    : _loading
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
                        itemBuilder: (_, i) =>
                            _buildFolderTile(_folders[i], theme),
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
      ),
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
