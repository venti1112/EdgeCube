import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'dialogs.dart';
import 'models.dart';
import 'providers.dart';

/// 弹出一个实例内的文件夹选择对话框，返回所选目录的**相对路径**；取消返回 `null`。
///
/// 导航被限制在实例目录之内（`root` 恒为 `''`）；[disabledPath] 用来禁掉
/// 「移入自身」的那个目录（禁掉入口即禁掉整棵子树）。
Future<String?> showFolderPicker(
  BuildContext context, {
  required String instanceId,
  required String title,
  String? disabledPath,
  String confirmLabel = '移动到此处',
}) => showDialog<String>(
  context: context,
  builder: (_) => FolderPickerDialog(
    instanceId: instanceId,
    title: title,
    disabledPath: disabledPath,
    confirmLabel: confirmLabel,
  ),
);

class FolderPickerDialog extends ConsumerStatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.instanceId,
    required this.title,
    this.disabledPath,
    this.confirmLabel = '移动到此处',
  });

  final String instanceId;
  final String title;
  final String? disabledPath;
  final String confirmLabel;

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  String _path = '';
  List<FileEntry> _folders = const [];
  bool _loading = true;
  String? _error;

  bool _searchMode = false;
  bool _recursive = false;
  bool _searching = false;
  final _searchController = TextEditingController();
  List<FileEntry> _searchResults = const [];
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_runSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.removeListener(_runSearch);
    _searchController.dispose();
    super.dispose();
  }

  bool get _atRoot => _path.isEmpty;

  /// 当前目录的显示名：根目录用占位文案，其余用相对路径。
  String get _label => _atRoot ? '根目录' : _path;

  Future<void> _load() async {
    final api = ref.read(fileApiProvider);
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await api.list(widget.instanceId, path: _path);
      if (!mounted) return;
      setState(() {
        _folders = listing.entries.where((e) => e.isDir).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeFileError(error);
        _loading = false;
      });
    }
  }

  void _enter(String path) {
    _path = path;
    unawaited(_load());
  }

  void _goUp() {
    if (_atRoot) return;
    final at = _path.lastIndexOf('/');
    _enter(at < 0 ? '' : _path.substring(0, at));
  }

  Future<void> _createFolder() async {
    final name = await promptText(
      context,
      title: '新建文件夹',
      label: '文件夹名称',
    );
    if (name == null || name.isEmpty) return;
    final api = ref.read(fileApiProvider);
    if (api == null) return;
    try {
      await api.createDir(widget.instanceId, name: name, path: _path);
      await _load();
    } catch (error) {
      if (mounted) await showErrorDialog(context, describeFileError(error));
    }
  }

  // ── 搜索（文件夹选择器只关心目录）──

  void _enterSearch() => setState(() {
    _searchMode = true;
    _searchController.clear();
    _searchResults = const [];
  });

  void _exitSearch() => setState(() {
    _searchMode = false;
    _searchController.clear();
    _searchResults = const [];
    _searching = false;
  });

  void _toggleRecursive() {
    setState(() => _recursive = !_recursive);
    unawaited(_runSearch());
  }

  Future<void> _runSearch() async {
    if (!_searchMode) return;
    final api = ref.read(fileApiProvider);
    if (api == null) return;
    final query = _searchController.text;
    final token = ++_searchToken;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final outcome = await api.search(
        widget.instanceId,
        path: _path,
        query: query,
        recursive: _recursive,
      );
      if (!mounted || token != _searchToken || !_searchMode) return;
      setState(() {
        _searchResults = outcome.entries.where((e) => e.isDir).toList();
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
        _error = describeFileError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // 搜索中或还没到根：先退出搜索、其次回上一级，根目录才真的关窗
      canPop: _atRoot && !_searchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searchMode) {
          _exitSearch();
          return;
        }
        _goUp();
      },
      child: AlertDialog(
        title: Text(widget.title, textAlign: TextAlign.center),
        content: SizedBox(
          width: 420,
          height: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchMode)
                _searchBar(theme)
              else
                _navBar(theme),
              const Divider(height: 1),
              Expanded(child: _searchMode ? _searchBody(theme) : _browserBody(theme)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('folder_picker_confirm'),
            onPressed: () => Navigator.of(context).pop(_path),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }

  Widget _navBar(ThemeData theme) => Row(
    children: [
      IconButton(
        key: const Key('folder_picker_up'),
        tooltip: '上一级',
        onPressed: _atRoot ? null : _goUp,
        icon: const Icon(Icons.arrow_upward),
      ),
      Expanded(
        child: Text(
          _label,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
      IconButton(
        key: const Key('folder_picker_search'),
        tooltip: '搜索',
        onPressed: _enterSearch,
        icon: const Icon(Icons.search),
      ),
      IconButton(
        key: const Key('folder_picker_new'),
        tooltip: '新建文件夹',
        onPressed: _createFolder,
        icon: const Icon(Icons.create_new_folder_outlined),
      ),
    ],
  );

  Widget _searchBar(ThemeData theme) => Row(
    children: [
      IconButton(
        tooltip: '退出搜索',
        onPressed: _exitSearch,
        icon: const Icon(Icons.arrow_back),
      ),
      Expanded(
        child: TextField(
          key: const Key('folder_picker_search_field'),
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '在当前目录下搜索…',
            isDense: true,
          ),
        ),
      ),
      IconButton(
        tooltip: '包含子目录',
        onPressed: _toggleRecursive,
        icon: Icon(
          _recursive ? Icons.account_tree : Icons.account_tree_outlined,
          color: _recursive ? theme.colorScheme.primary : null,
        ),
      ),
    ],
  );

  Widget _browserBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _centered(theme, _error!);
    if (_folders.isEmpty) return _centered(theme, '没有子文件夹');
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _folders.length,
      itemBuilder: (_, index) => _folderTile(_folders[index], theme),
    );
  }

  Widget _searchBody(ThemeData theme) {
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_searchController.text.trim().isEmpty) {
      return _centered(theme, '输入名称以搜索当前目录');
    }
    if (_searchResults.isEmpty) return _centered(theme, '没有匹配的文件或目录');
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _searchResults.length,
      itemBuilder: (_, index) =>
          _folderTile(_searchResults[index], theme, inSearch: true),
    );
  }

  Widget _centered(ThemeData theme, String text) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _folderTile(FileEntry folder, ThemeData theme, {bool inSearch = false}) {
    final disabled = widget.disabledPath != null &&
        widget.disabledPath == folder.path;
    final parent = inSearch ? _searchParentOf(folder.path) : _path;
    final relative = parent.isEmpty
        ? folder.name
        : folder.path.substring(parent.length + 1);
    return ListTile(
      dense: true,
      enabled: !disabled,
      leading: Icon(folder.isLink ? Icons.link : Icons.folder),
      title: Text(folder.name),
      subtitle: inSearch && relative != folder.name ? Text(relative) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: disabled
          ? null
          : () {
              if (inSearch) _exitSearch();
              _enter(folder.path);
            },
    );
  }

  /// 搜索结果里这条目录的父路径（`a/b/c` → `a/b`），用来算相对显示路径。
  static String _searchParentOf(String path) {
    final at = path.lastIndexOf('/');
    return at < 0 ? '' : path.substring(0, at);
  }
}
