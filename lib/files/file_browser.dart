import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../instance/instance_scope.dart';
import 'file_entry.dart';
import 'file_service.dart';
import 'folder_picker.dart';
import 'storage_permission.dart';
import 'system_picker.dart';
import 'text_editor_page.dart';

enum _FileAction { edit, rename, move, copy, compress, extract, export, delete }

/// 多选模式下可对多个条目一起执行的操作。
enum _BulkAction { move, copy, compress, export }

/// 可用内置编辑器打开的文本文件扩展名（小写，含点）。
const _textExtensions = <String>{
  '.txt',
  '.text',
  '.md',
  '.markdown',
  '.log',
  '.properties',
  '.conf',
  '.cfg',
  '.ini',
  '.toml',
  '.env',
  '.list',
  '.yml',
  '.yaml',
  '.json',
  '.json5',
  '.xml',
  '.html',
  '.htm',
  '.css',
  '.js',
  '.ts',
  '.sh',
  '.bat',
  '.cmd',
  '.py',
  '.lua',
  '.csv',
  '.tsv',
  '.lang',
  '.mcmeta',
  '.snbt',
};

/// 超过该大小的文件不在内置编辑器中打开，避免一次性载入内存造成卡顿。
const _maxEditableBytes = 2 * 1024 * 1024; // 2 MiB

/// 可解压的归档文件扩展名（小写，含点）。
const _archiveExtensions = <String>{
  '.zip',
  '.xz',
  '.7z',
  '.tar',
  '.gz',
  '.tgz',
  '.txz',
  '.tbz2',
  '.bz2',
  '.zst',
  '.tzst',
  '.lz4',
  '.rar',
};

/// 归档文件名需做特殊处理的复合扩展名（小写），用于推断解压子文件夹名：
/// 例如 `world.tar.gz` → `world`，而非 `world.tar`。
const _compoundArchiveExtensions = <String>[
  '.tar.gz',
  '.tar.xz',
  '.tar.bz2',
  '.tar.zst',
  '.tar.lz4',
];

/// 浏览并管理单个实例文件夹内的文件。
///
/// 导航被限制在 [rootDir] 之内，无法越过实例根目录。
class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key, required this.rootDir});

  final Directory rootDir;

  /// 当前文件浏览器是否不在根目录（供返回键处理使用）。
  static bool get canNavigateUp => _FileBrowserState._active?.canGoUp ?? false;

  /// 让当前文件浏览器返回上一级目录（供返回键处理使用）。
  static void navigateUp() => _FileBrowserState._active?.goUp();

  /// 当前文件浏览器是否处于多选模式（供返回键处理使用）。
  static bool get isSelecting =>
      _FileBrowserState._active?._selectionMode ?? false;

  /// 退出多选模式（供返回键处理使用）。
  static void exitSelection() => _FileBrowserState._active?._clearSelection();

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  static const _service = FileService();

  /// 当前活跃的 FileBrowser 实例引用，供 HomeShell 处理系统返回键时查询。
  static _FileBrowserState? _active;

  late Directory _current = widget.rootDir;
  List<FileEntry> _entries = [];
  bool _loading = true;

  /// 多选模式开关与已选中条目的路径集合。
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _active = this;
    _load();
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(FileBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换实例后根目录变化，回到新实例根目录并退出多选。
    if (!p.equals(oldWidget.rootDir.path, widget.rootDir.path)) {
      _selectionMode = false;
      _selectedPaths.clear();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  void _enter(FileEntry entry) {
    if (!entry.isDirectory) return;
    _current = Directory(entry.path);
    _load();
  }

  /// 是否为可用内置编辑器打开的文本文件（按扩展名判断）。
  bool _isEditableText(FileEntry entry) {
    if (entry.isDirectory) return false;
    return _textExtensions.contains(p.extension(entry.name).toLowerCase());
  }

  /// 是否为可解压的归档文件（按扩展名判断，支持复合扩展名如 .tar.gz）。
  bool _isArchive(FileEntry entry) {
    if (entry.isDirectory) return false;
    final lower = entry.name.toLowerCase();
    if (_compoundArchiveExtensions.any(lower.endsWith)) return true;
    return _archiveExtensions.contains(p.extension(lower));
  }

  /// 在内置文本编辑器中打开 [entry]；过大文件拒绝打开。返回后刷新列表以更新大小。
  Future<void> _openEditor(FileEntry entry) async {
    if (entry.isDirectory) return;
    if (entry.size > _maxEditableBytes) {
      _showError('文件过大，无法在内置编辑器中打开（上限 2 MB）。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(path: entry.path, name: entry.name),
      ),
    );
    if (mounted) await _load();
  }

  /// 是否已回到实例根目录（供外部返回键处理使用）。
  bool get canGoUp => !p.equals(_current.path, widget.rootDir.path);

  /// 返回上一级目录（供外部返回键处理使用）。
  void goUp() => _goUp();

  void _goUp() {
    if (_atRoot) return;
    _current = Directory(p.dirname(_current.path));
    _load();
  }

  Future<void> _importFile() async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final instances = InstanceScope.of(context);
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) return;
    try {
      await _service.importFile(sourcePath, _current);
      await _load();
      // 通知服务器页重新扫描，新导入的 jar 可被立即识别。
      instances.notifyInstanceFilesChanged();
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

  /// 新建一个空白文件；若为可编辑文本类型，创建后直接打开内置编辑器。
  Future<void> _createFile() async {
    final instances = InstanceScope.of(context);
    final name = await _promptText(context, title: '新建文件', label: '文件名称');
    if (name == null || name.isEmpty) return;
    try {
      final file = await _service.createFile(_current, name);
      await _load();
      // 新文件可能是 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
      final entry = FileEntry(
        path: file.path,
        name: p.basename(file.path),
        isDirectory: false,
        size: 0,
        modified: DateTime.now(),
      );
      if (_isEditableText(entry) && mounted) {
        await _openEditor(entry);
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _onAction(_FileAction action, FileEntry entry) async {
    switch (action) {
      case _FileAction.edit:
        await _openEditor(entry);
      case _FileAction.rename:
        await _rename(entry);
      case _FileAction.move:
        await _moveOrCopy(entry, isMove: true);
      case _FileAction.copy:
        await _moveOrCopy(entry, isMove: false);
      case _FileAction.compress:
        await _compress(entry);
      case _FileAction.extract:
        await _extract(entry);
      case _FileAction.export:
        await _export(entry);
      case _FileAction.delete:
        await _delete(entry);
    }
  }

  Future<void> _rename(FileEntry entry) async {
    final instances = InstanceScope.of(context);
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
      // 重命名可能改变根目录的 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _moveOrCopy(FileEntry entry, {required bool isMove}) async {
    final instances = InstanceScope.of(context);
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
      // 移动/复制可能改变根目录的 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _export(FileEntry entry) async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;
    try {
      await _service.exportTo(entry.path, destDir);
      messenger.showSnackBar(const SnackBar(content: Text('导出完成')));
    } catch (e) {
      _showError(e);
    }
  }

  /// 压缩单个文件或文件夹为同名 zip，输出到当前目录。
  Future<void> _compress(FileEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在压缩…'),
            ],
          ),
        ),
      ),
    );
    try {
      await _service.compress(entry.path, _current);
      if (mounted) Navigator.of(context).pop();
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('压缩完成')));
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  /// 解压归档文件到以文件名（去全部归档扩展名）命名的子文件夹中。
  Future<void> _extract(FileEntry entry) async {
    final instances = InstanceScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final subfolderName = _archiveBaseName(entry.name);
    // 解压可能耗时，显示不可取消的加载对话框。
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在解压…'),
            ],
          ),
        ),
      ),
    );
    try {
      await _service.extract(entry.path, _current, subfolderName);
      if (mounted) Navigator.of(context).pop(); // 关闭加载对话框
      await _load();
      // 解压出的文件可能含 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
      messenger.showSnackBar(const SnackBar(content: Text('解压完成')));
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // 关闭加载对话框
      _showError(e);
    }
  }

  /// 去掉归档文件名的全部扩展名作为解压子文件夹名。
  /// 复合扩展名（.tar.gz 等）整体去掉；单层扩展名去掉一层。
  String _archiveBaseName(String name) {
    final lower = name.toLowerCase();
    for (final ext in _compoundArchiveExtensions) {
      if (lower.endsWith(ext)) {
        return name.substring(0, name.length - ext.length);
      }
    }
    return p.basenameWithoutExtension(name);
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
    final instances = InstanceScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text(
          '确定删除「${entry.name}」吗？${entry.isDirectory ? '该文件夹及其内容将被删除。' : ''}',
        ),
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
      // 删除可能移除根目录的 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
    } catch (e) {
      _showError(e);
    }
  }

  // —— 多选 ——

  /// 当前已选中的条目（按当前列表顺序）。
  List<FileEntry> get _selectedEntries =>
      _entries.where((e) => _selectedPaths.contains(e.path)).toList();

  /// 进入多选模式并选中 [entry]（长按触发）。
  void _enterSelection(FileEntry entry) {
    setState(() {
      _selectionMode = true;
      _selectedPaths.add(entry.path);
    });
  }

  /// 切换某条目的选中状态；取消最后一项时退出多选模式。
  void _toggleSelected(FileEntry entry) {
    setState(() {
      if (!_selectedPaths.remove(entry.path)) {
        _selectedPaths.add(entry.path);
      }
      if (_selectedPaths.isEmpty) _selectionMode = false;
    });
  }

  /// 全选 / 取消全选当前目录下的条目。
  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _entries.length) {
        _selectedPaths.clear();
        _selectionMode = false;
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_entries.map((e) => e.path));
      }
    });
  }

  /// 退出多选模式并清空选择。
  void _clearSelection() {
    if (!_selectionMode && _selectedPaths.isEmpty) return;
    if (!mounted) {
      _selectionMode = false;
      _selectedPaths.clear();
      return;
    }
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _onBulkAction(_BulkAction action) {
    switch (action) {
      case _BulkAction.move:
        _moveSelected();
      case _BulkAction.copy:
        _copySelected();
      case _BulkAction.compress:
        _compressSelected();
      case _BulkAction.export:
        _exportSelected();
    }
  }

  /// 汇报批量操作结果；[failed] 为失败条目名称列表。
  void _reportBulkResult(String action, List<String> failed) {
    if (!mounted) return;
    final msg = failed.isEmpty
        ? '$action完成'
        : '$action完成，${failed.length} 项失败：${failed.join('、')}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除选中的 ${entries.length} 项吗？其中的文件夹及其内容将一并删除。'),
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
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.delete(entry.path);
      } catch (_) {
        failed.add(entry.name);
      }
    }
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult('删除', failed);
  }

  Future<void> _moveSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final dest = await pickFolder(
      context,
      rootDir: widget.rootDir,
      title: '移动 ${entries.length} 项到',
    );
    if (dest == null) return;
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.move(entry.path, Directory(dest));
      } catch (_) {
        failed.add(entry.name);
      }
    }
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult('移动', failed);
  }

  Future<void> _copySelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final dest = await pickFolder(
      context,
      rootDir: widget.rootDir,
      title: '复制 ${entries.length} 项到',
    );
    if (dest == null) return;
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.copy(entry.path, Directory(dest));
      } catch (_) {
        failed.add(entry.name);
      }
    }
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult('复制', failed);
  }

  Future<void> _exportSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.exportTo(entry.path, destDir);
      } catch (_) {
        failed.add(entry.name);
      }
    }
    _clearSelection();
    _reportBulkResult('导出', failed);
  }

  Future<void> _compressSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在压缩…'),
            ],
          ),
        ),
      ),
    );
    try {
      await _service.compressMany(
        entries.map((e) => e.path).toList(),
        _current,
        '压缩文件.zip',
      );
      if (mounted) Navigator.of(context).pop();
      _clearSelection();
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('压缩完成')));
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _selectionMode
            ? _buildSelectionBar(theme)
            : _Toolbar(
                atRoot: _atRoot,
                relativePath: _atRoot
                    ? '根目录'
                    : p.relative(_current.path, from: widget.rootDir.path),
                onUp: _goUp,
                onImport: _importFile,
                onNewFolder: _createFolder,
                onNewFile: _createFile,
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
                      final selected = _selectedPaths.contains(entry.path);
                      return ListTile(
                        selected: _selectionMode && selected,
                        leading: _selectionMode
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggleSelected(entry),
                              )
                            : Icon(
                                entry.isDirectory
                                    ? Icons.folder
                                    : Icons.insert_drive_file_outlined,
                              ),
                        title: Text(entry.name),
                        subtitle: Text(_subtitle(entry)),
                        onTap: _selectionMode
                            ? () => _toggleSelected(entry)
                            : entry.isDirectory
                            ? () => _enter(entry)
                            : _isEditableText(entry)
                            ? () => _openEditor(entry)
                            : null,
                        onLongPress: _selectionMode
                            ? null
                            : () => _enterSelection(entry),
                        trailing: _selectionMode
                            ? null
                            : PopupMenuButton<_FileAction>(
                                onSelected: (a) => _onAction(a, entry),
                                itemBuilder: (_) => [
                                  if (!entry.isDirectory)
                                    const PopupMenuItem(
                                      value: _FileAction.edit,
                                      child: Text('编辑'),
                                    ),
                                  const PopupMenuItem(
                                    value: _FileAction.rename,
                                    child: Text('重命名'),
                                  ),
                                  const PopupMenuItem(
                                    value: _FileAction.move,
                                    child: Text('移动'),
                                  ),
                                  const PopupMenuItem(
                                    value: _FileAction.copy,
                                    child: Text('复制'),
                                  ),
                                  const PopupMenuItem(
                                    value: _FileAction.compress,
                                    child: Text('压缩'),
                                  ),
                                  if (_isArchive(entry))
                                    const PopupMenuItem(
                                      value: _FileAction.extract,
                                      child: Text('解压'),
                                    ),
                                  const PopupMenuItem(
                                    value: _FileAction.export,
                                    child: Text('导出'),
                                  ),
                                  const PopupMenuItem(
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

  /// 多选模式下的顶部操作栏：退出、计数、全选、删除、更多（移动/复制/导出）。
  Widget _buildSelectionBar(ThemeData theme) {
    final count = _selectedPaths.length;
    final allSelected = _entries.isNotEmpty && count == _entries.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '退出多选',
            onPressed: _clearSelection,
          ),
          Expanded(
            child: Text(
              '已选 $count 项',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            tooltip: allSelected ? '取消全选' : '全选',
            onPressed: _entries.isEmpty ? null : _toggleSelectAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: count == 0 ? null : _deleteSelected,
          ),
          PopupMenuButton<_BulkAction>(
            enabled: count > 0,
            tooltip: '更多操作',
            onSelected: _onBulkAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _BulkAction.move, child: Text('移动')),
              PopupMenuItem(value: _BulkAction.copy, child: Text('复制')),
              PopupMenuItem(value: _BulkAction.compress, child: Text('压缩')),
              PopupMenuItem(value: _BulkAction.export, child: Text('导出')),
            ],
          ),
        ],
      ),
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
    required this.onNewFile,
  });

  final bool atRoot;
  final String relativePath;
  final VoidCallback onUp;
  final VoidCallback onImport;
  final VoidCallback onNewFolder;
  final VoidCallback onNewFile;

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
            icon: const Icon(Icons.note_add_outlined),
            tooltip: '新建文件',
            onPressed: onNewFile,
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
