import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../instance/instance_scope.dart';
import '../widgets/error_dialog.dart';
import '../widgets/loading_dialog.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import 'file_entry.dart';
import 'file_search_bar.dart';
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

  /// 当前文件浏览器是否处于搜索模式（供返回键处理使用）。
  static bool get isSearching =>
      _FileBrowserState._active?._searchMode ?? false;

  /// 退出搜索模式（供返回键处理使用）。
  static void exitSearch() => _FileBrowserState._active?._exitSearch();

  /// 检查当前目录的实际文件列表与已显示的是否一致，不一样则刷新（保留滚动位置）。
  static void checkAndRefresh() =>
      _FileBrowserState._active?._checkAndRefresh();

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  static const _service = FileService();

  /// 当前活跃的 FileBrowser 实例引用，供 HomeShell 处理系统返回键时查询。
  static _FileBrowserState? _active;

  /// 本实例被 push 到导航栈时，暂存被覆盖的上一个 [_active]，
  /// 以便 dispose 时精确恢复——否则被 push 的容器文件浏览器关闭后，
  /// 常驻文件页（IndexedStack 内）的返回键处理会失效。
  _FileBrowserState? _previousActive;

  late Directory _current = widget.rootDir;
  List<FileEntry> _entries = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();

  /// 多选模式开关与已选中条目的路径集合。
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  /// 搜索模式开关、查询输入、是否递归子目录、搜索结果与进行中标志。
  /// 搜索限定在当前目录 [_current] 下；[_searchRecursive] 默认 false（不含子目录）。
  bool _searchMode = false;
  bool _searchRecursive = false;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  List<FileEntry> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _previousActive = _active;
    _active = this;
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    // 仅当自己仍是活跃实例时才让位，恢复被自己覆盖的上一个（若存在）。
    if (_active == this) _active = _previousActive;
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

  /// 下拉刷新：MiuixPullToRefresh 的 isRefreshing 是受控参数，须自行置回。
  bool _pullRefreshing = false;

  Future<void> _handlePullRefresh() async {
    if (_pullRefreshing) return;
    setState(() => _pullRefreshing = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _pullRefreshing = false);
    }
  }

  Future<void> _load() async {
    // 首次加载时显示转圈；已有列表数据时静默刷新，不替换 ListView，
    // 避免销毁重建导致滚动位置丢失。
    final isFirstLoad = _entries.isEmpty;
    if (isFirstLoad) setState(() => _loading = true);
    final entries = await _service.list(_current);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// 检查当前目录实际文件列表与已显示的是否一致，不一样则静默刷新（保留滚动位置）。
  Future<void> _checkAndRefresh() async {
    final fresh = await _service.list(_current);
    if (!mounted) return;
    if (_entriesSame(fresh, _entries)) return;
    setState(() {
      _entries = fresh;
      _loading = false;
    });
  }

  /// 两个文件列表的内容是否完全相同（按路径与类型比较）。
  bool _entriesSame(List<FileEntry> a, List<FileEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].isDirectory != b[i].isDirectory) {
        return false;
      }
    }
    return true;
  }

  void _showError(Object error) {
    showErrorDialog(context, error.toString());
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

  /// 在内置文本编辑器中打开 [entry]。返回后刷新列表以更新大小。
  Future<void> _openEditor(FileEntry entry) async {
    if (entry.isDirectory) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(path: entry.path, name: entry.name),
      ),
    );
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

  // —— 搜索 ——

  /// 进入搜索模式：退出多选，清空上次查询与结果。
  void _enterSearch() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
      _searchMode = true;
      _searchController.clear();
      _searchResults = [];
    });
  }

  /// 退出搜索模式，回到普通浏览。
  void _exitSearch() {
    setState(() {
      _searchMode = false;
      _searchController.clear();
      _searchResults = [];
      _searching = false;
    });
  }

  /// 切换「包含子目录」并按当前查询重新搜索。
  void _toggleSearchRecursive(bool value) {
    setState(() => _searchRecursive = value);
    _runSearch();
  }

  /// 查询文本变化时触发搜索。
  void _onSearchChanged() => _runSearch();

  /// 依据当前查询与递归开关执行搜索，写入 [_searchResults]。
  ///
  /// 用请求令牌规避竞态：递归搜索可能较慢，只有最后一次请求的结果被采用。
  int _searchToken = 0;
  Future<void> _runSearch() async {
    if (!_searchMode) return;
    final query = _searchController.text;
    final token = ++_searchToken;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await _service.search(
      _current,
      query,
      recursive: _searchRecursive,
    );
    if (!mounted || token != _searchToken || !_searchMode) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _importFile() async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final instances = InstanceScope.of(context);
    final importingMessage = context.tr('fileBrowser.importing');
    final successMessage = context.tr('fileBrowser.importSuccess');
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) return;
    if (!mounted) return;
    _showLoadingDialog(importingMessage);
    try {
      await _service.importFile(sourcePath, _current);
      if (mounted) Navigator.of(context).pop();
      await _load();
      instances.notifyInstanceFilesChanged();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  Future<void> _importFolder() async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final instances = InstanceScope.of(context);
    final importingMessage = context.tr('fileBrowser.importing');
    final successMessage = context.tr('fileBrowser.importFolderSuccess');
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (sourcePath == null) return;
    if (!mounted) return;
    _showLoadingDialog(importingMessage);
    try {
      await _service.importFile(sourcePath, _current);
      if (mounted) Navigator.of(context).pop();
      await _load();
      instances.notifyInstanceFilesChanged();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  Future<void> _createFolder() async {
    final name = await _promptText(
      context,
      title: context.tr('fileBrowser.newFolderTitle'),
      label: context.tr('fileBrowser.folderName'),
    );
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
    final name = await _promptText(
      context,
      title: context.tr('fileBrowser.newFileTitle'),
      label: context.tr('fileBrowser.fileName'),
    );
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
      title: context.tr('common.rename'),
      label: context.tr('fileBrowser.newName'),
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
      title: isMove
          ? context.tr('fileBrowser.moveTo')
          : context.tr('fileBrowser.copyTo'),
      disabledPath: entry.isDirectory ? entry.path : null,
    );
    if (dest == null || !mounted) return;
    _showLoadingDialog(context.tr(isMove ? 'common.moving' : 'common.copying'));
    try {
      if (isMove) {
        await _service.move(entry.path, Directory(dest));
      } else {
        await _service.copy(entry.path, Directory(dest));
      }
      if (mounted) Navigator.of(context).pop();
      await _load();
      // 移动/复制可能改变根目录的 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  Future<void> _export(FileEntry entry) async {
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final exportingMessage = context.tr('fileBrowser.exporting');
    final successMessage = context.tr('fileBrowser.exportSuccess');
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;
    if (!mounted) return;
    _showLoadingDialog(exportingMessage);
    try {
      await _service.exportTo(entry.path, destDir);
      if (mounted) Navigator.of(context).pop();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  /// 压缩单个文件或文件夹为同名 zip，输出到当前目录。
  Future<void> _compress(FileEntry entry) async {
    final compressingMessage = context.tr('fileBrowser.compressing');
    final successMessage = context.tr('fileBrowser.compressSuccess');
    if (!mounted) return;
    _showLoadingDialog(compressingMessage);
    try {
      await _service.compress(entry.path, _current);
      if (mounted) Navigator.of(context).pop();
      await _load();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  /// 解压归档文件到以文件名（去全部归档扩展名）命名的子文件夹中。
  Future<void> _extract(FileEntry entry) async {
    final instances = InstanceScope.of(context);
    final extractingMessage = context.tr('fileBrowser.extracting');
    final successMessage = context.tr('fileBrowser.extractSuccess');
    final subfolderName = _archiveBaseName(entry.name);
    if (!mounted) return;
    _showLoadingDialog(extractingMessage);
    try {
      await _service.extract(entry.path, _current, subfolderName);
      if (mounted) Navigator.of(context).pop(); // 关闭加载对话框
      await _load();
      // 解压出的文件可能含 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // 关闭加载对话框
      _showError(e);
    }
  }

  /// 显示不可取消的加载对话框，操作完成后由调用方 pop 关闭。
  void _showLoadingDialog(String message) =>
      showLoadingDialog(context, message);

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
    final go = await showMiuixConfirm(
      context,
      title: context.tr('fileBrowser.permissionTitle'),
      message: context.tr('fileBrowser.permissionContent'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('fileBrowser.grantPermission'),
    );
    if (go == true) {
      await StoragePermission.request();
    }
    return false;
  }

  Future<void> _delete(FileEntry entry) async {
    final instances = InstanceScope.of(context);
    final confirmed = await showMiuixDialog<bool>(
      context: context,
      title: context.tr('common.delete'),
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('fileBrowser.deleteConfirm', {
              'name': entry.name,
              'extra': entry.isDirectory
                  ? context.tr('fileBrowser.deleteFolderExtra')
                  : '',
            }),
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                context.tr('common.cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              MiuixTextButton(
                context.tr('common.delete'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _showLoadingDialog(context.tr('common.deleting'));
    try {
      await _service.delete(entry.path);
      if (mounted) Navigator.of(context).pop();
      await _load();
      // 删除可能移除根目录的 jar，通知服务器页重新扫描。
      instances.notifyInstanceFilesChanged();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
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
  void _reportBulkResult(String actionName, List<String> failed) {
    if (!mounted) return;
    if (failed.isEmpty) {
      final msg = context.tr('fileBrowser.bulkSuccess', {'action': actionName});
      showMiuixSnackbar(msg);
    } else {
      showErrorDialog(
        context,
        context.tr('fileBrowser.bulkPartial', {
          'action': actionName,
          'count': failed.length.toString(),
          'list': failed.join('、'),
        }),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final deleteLabel = context.tr('common.delete');
    final confirmed = await showMiuixDialog<bool>(
      context: context,
      title: context.tr('common.delete'),
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('fileBrowser.deleteSelectedConfirm', {
              'count': entries.length.toString(),
            }),
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                context.tr('common.cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              MiuixTextButton(
                context.tr('common.delete'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _showLoadingDialog(context.tr('common.deleting'));
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.delete(entry.path);
      } catch (_) {
        failed.add(entry.name);
      }
    }
    if (mounted) Navigator.of(context).pop();
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult(deleteLabel, failed);
  }

  Future<void> _moveSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final moveLabel = context.tr('fileBrowser.move');
    final dest = await pickFolder(
      context,
      rootDir: widget.rootDir,
      title: context.tr('fileBrowser.moveItemsTo', {
        'count': entries.length.toString(),
      }),
    );
    if (dest == null || !mounted) return;
    _showLoadingDialog(context.tr('common.moving'));
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.move(entry.path, Directory(dest));
      } catch (_) {
        failed.add(entry.name);
      }
    }
    if (mounted) Navigator.of(context).pop();
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult(moveLabel, failed);
  }

  Future<void> _copySelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final instances = InstanceScope.of(context);
    final copyLabel = context.tr('common.copy');
    final dest = await pickFolder(
      context,
      rootDir: widget.rootDir,
      title: context.tr('fileBrowser.copyItemsTo', {
        'count': entries.length.toString(),
      }),
    );
    if (dest == null || !mounted) return;
    _showLoadingDialog(context.tr('common.copying'));
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.copy(entry.path, Directory(dest));
      } catch (_) {
        failed.add(entry.name);
      }
    }
    if (mounted) Navigator.of(context).pop();
    _clearSelection();
    await _load();
    instances.notifyInstanceFilesChanged();
    _reportBulkResult(copyLabel, failed);
  }

  Future<void> _exportSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    if (!await _ensurePermission()) return;
    if (!mounted) return;
    final exportLabel = context.tr('fileBrowser.export');
    final exportingMessage = context.tr('fileBrowser.exporting');
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;
    if (!mounted) return;
    _showLoadingDialog(exportingMessage);
    final failed = <String>[];
    for (final entry in entries) {
      try {
        await _service.exportTo(entry.path, destDir);
      } catch (_) {
        failed.add(entry.name);
      }
    }
    if (mounted) Navigator.of(context).pop();
    _clearSelection();
    _reportBulkResult(exportLabel, failed);
  }

  Future<void> _compressSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    final compressingMessage = context.tr('fileBrowser.compressing');
    final successMessage = context.tr('fileBrowser.compressSuccess');

    // 让用户输入压缩包名称（可取消）；自动补 .zip 后缀。
    final inputName = await _promptText(
      context,
      title: context.tr('fileBrowser.compressTitle'),
      label: context.tr('fileBrowser.archiveName'),
      initialValue: context.tr('fileBrowser.defaultArchiveName'),
    );
    if (inputName == null || inputName.isEmpty) return;
    if (!mounted) return;
    final archiveName = inputName.toLowerCase().endsWith('.zip')
        ? inputName
        : '$inputName.zip';

    _showLoadingDialog(compressingMessage);
    try {
      await _service.compressMany(
        entries.map((e) => e.path).toList(),
        _current,
        archiveName,
      );
      if (mounted) Navigator.of(context).pop();
      _clearSelection();
      await _load();
      showMiuixSnackbar(successMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    if (_searchMode) return _buildSearchView(theme);
    return Column(
      children: [
        _selectionMode
            ? _buildSelectionBar(theme)
            : _Toolbar(
                atRoot: _atRoot,
                relativePath: _atRoot
                    ? context.tr('fileBrowser.rootDir')
                    : p.relative(_current.path, from: widget.rootDir.path),
                onUp: _goUp,
                onSearch: _enterSearch,
                onImport: _importFile,
                onImportFolder: _importFolder,
                onNewFolder: _createFolder,
                onNewFile: _createFile,
              ),
        const MiuixHorizontalDivider(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : MiuixPullToRefresh(
                  // _load 只在首次加载时置 _loading（避免刷新时销毁列表丢失
                  // 滚动位置），故下拉刷新需要一个独立的受控标志。
                  isRefreshing: _pullRefreshing,
                  onRefresh: _handlePullRefresh,
                  child: _entries.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Text(
                                    context.tr('fileBrowser.emptyFolder'),
                                    style: theme.textStyles.body2.copyWith(
                                      color:
                                          theme.colors.onSurfaceVariantSummary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _entries.length,
                          itemBuilder: (_, i) => _buildEntryTile(_entries[i]),
                        ),
                ),
        ),
      ],
    );
  }

  /// 单个文件/目录列表项。[inSearch] 为 true 时用于搜索结果：
  /// 无多选/长按选择，点击目录会跳转到该目录（退出搜索），副标题显示相对路径。
  Widget _buildEntryTile(FileEntry entry, {bool inSearch = false}) {
    final selected = _selectedPaths.contains(entry.path);
    // MiuixBasicComponent 没有 onLongPress，而「长按进入多选」是本页核心交互，
    // 故外面套一层 GestureDetector 补回（translucent 让内部点击照常生效）。
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _selectionMode || inSearch
          ? null
          : () => _enterSelection(entry),
      child: MiuixBasicComponent(
        startAction: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _selectionMode
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelected(entry),
                )
              : Icon(_iconFor(entry)),
        ),
        title: entry.name,
        summary: inSearch ? _searchSubtitle(entry) : _subtitle(entry),
        endActions: [
          if (!_selectionMode)
            MiuixOverlayIconDropdownMenu(
              entry: MiuixDropdownEntry(
                items: [
                  if (!entry.isDirectory)
                    MiuixDropdownItem(
                      text: context.tr('common.edit'),
                      onClick: () => _onAction(_FileAction.edit, entry),
                    ),
                  MiuixDropdownItem(
                    text: context.tr('common.rename'),
                    onClick: () => _onAction(_FileAction.rename, entry),
                  ),
                  MiuixDropdownItem(
                    text: context.tr('fileBrowser.move'),
                    onClick: () => _onAction(_FileAction.move, entry),
                  ),
                  MiuixDropdownItem(
                    text: context.tr('common.copy'),
                    onClick: () => _onAction(_FileAction.copy, entry),
                  ),
                  MiuixDropdownItem(
                    text: context.tr('fileBrowser.compress'),
                    onClick: () => _onAction(_FileAction.compress, entry),
                  ),
                  if (_isArchive(entry))
                    MiuixDropdownItem(
                      text: context.tr('fileBrowser.extract'),
                      onClick: () => _onAction(_FileAction.extract, entry),
                    ),
                  MiuixDropdownItem(
                    text: context.tr('fileBrowser.export'),
                    onClick: () => _onAction(_FileAction.export, entry),
                  ),
                  MiuixDropdownItem(
                    text: context.tr('common.delete'),
                    onClick: () => _onAction(_FileAction.delete, entry),
                  ),
                ],
              ),
              child: const MiuixIcon(icon: Icons.more_vert),
            ),
        ],
        onClick: _selectionMode
            ? () => _toggleSelected(entry)
            : entry.isDirectory
            ? () => inSearch ? _openFromSearch(entry) : _enter(entry)
            : _isEditableText(entry)
            ? () => _openEditor(entry)
            : null,
      ),
    );
  }

  /// 搜索模式视图：顶部搜索栏 + 结果列表。
  Widget _buildSearchView(MiuixThemeData theme) {
    return Column(
      children: [
        FileSearchBar(
          controller: _searchController,
          recursive: _searchRecursive,
          onRecursiveChanged: _toggleSearchRecursive,
          onClose: _exitSearch,
        ),
        const MiuixHorizontalDivider(),
        Expanded(child: _buildSearchBody(theme)),
      ],
    );
  }

  Widget _buildSearchBody(MiuixThemeData theme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Text(
          context.tr('fileSearch.prompt'),
          style: theme.textStyles.body2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          context.tr('fileSearch.noResults'),
          style: theme.textStyles.body2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (_, i) => _buildEntryTile(_searchResults[i], inSearch: true),
    );
  }

  /// 从搜索结果点击目录：跳转到该目录并退出搜索。
  void _openFromSearch(FileEntry entry) {
    if (!entry.isDirectory) return;
    _current = Directory(entry.path);
    _exitSearch();
    _load();
  }

  /// 搜索结果条目的副标题：显示相对当前目录的路径（递归搜索时便于定位）。
  String _searchSubtitle(FileEntry entry) {
    final rel = p.relative(entry.path, from: _current.path);
    // 直接子项（rel 无分隔符）回退到普通副标题，避免与文件名重复。
    if (!rel.contains(p.separator)) return _subtitle(entry);
    return rel;
  }

  /// 多选模式下的顶部操作栏：退出、计数、全选、删除、更多（移动/复制/导出）。
  Widget _buildSelectionBar(MiuixThemeData theme) {
    final count = _selectedPaths.length;
    final allSelected = _entries.isNotEmpty && count == _entries.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          MiuixIconButton(
            onPressed: _clearSelection,
            child: MiuixIcon(icon: Icons.close),
          ),
          Expanded(
            child: Text(
              context.tr('fileBrowser.selectedCount', {
                'count': count.toString(),
              }),
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.title4,
            ),
          ),
          MiuixIconButton(
            onPressed: _entries.isEmpty ? null : _toggleSelectAll,
            child: MiuixIcon(
              icon: allSelected ? Icons.deselect : Icons.select_all,
            ),
          ),
          MiuixIconButton(
            onPressed: count == 0 ? null : _deleteSelected,
            child: MiuixIcon(icon: Icons.delete_outline),
          ),
          MiuixOverlayIconDropdownMenu(
            enabled: count > 0,
            entry: MiuixDropdownEntry(
              items: [
                MiuixDropdownItem(
                  text: context.tr('fileBrowser.move'),
                  onClick: () => _onBulkAction(_BulkAction.move),
                ),
                MiuixDropdownItem(
                  text: context.tr('common.copy'),
                  onClick: () => _onBulkAction(_BulkAction.copy),
                ),
                MiuixDropdownItem(
                  text: context.tr('fileBrowser.compress'),
                  onClick: () => _onBulkAction(_BulkAction.compress),
                ),
                MiuixDropdownItem(
                  text: context.tr('fileBrowser.export'),
                  onClick: () => _onBulkAction(_BulkAction.export),
                ),
              ],
            ),
            child: const MiuixIcon(icon: Icons.more_vert),
          ),
        ],
      ),
    );
  }

  String _subtitle(FileEntry entry) {
    if (entry.isLink) {
      final target = entry.linkTarget;
      return (target == null || target.isEmpty)
          ? context.tr('fileBrowser.symlink')
          : context.tr('fileBrowser.symlinkTo', {'target': target});
    }
    if (entry.isDirectory) return context.tr('fileBrowser.folder');
    return _formatSize(entry.size);
  }

  /// 条目图标：符号链接优先显示链接标识，其次目录/文件。
  IconData _iconFor(FileEntry entry) {
    if (entry.isLink) return Icons.link;
    return entry.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined;
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
    required this.onSearch,
    required this.onImport,
    required this.onImportFolder,
    required this.onNewFolder,
    required this.onNewFile,
  });

  final bool atRoot;
  final String relativePath;
  final VoidCallback onUp;
  final VoidCallback onSearch;
  final VoidCallback onImport;
  final VoidCallback onImportFolder;
  final VoidCallback onNewFolder;
  final VoidCallback onNewFile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          MiuixIconButton(
            onPressed: atRoot ? null : onUp,
            child: MiuixIcon(icon: Icons.arrow_upward),
          ),
          Expanded(
            child: Text(
              relativePath,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          MiuixIconButton(
            onPressed: onSearch,
            child: MiuixIcon(icon: Icons.search),
          ),
          MiuixIconButton(
            onPressed: onNewFile,
            child: MiuixIcon(icon: Icons.note_add_outlined),
          ),
          MiuixIconButton(
            onPressed: onNewFolder,
            child: MiuixIcon(icon: Icons.create_new_folder_outlined),
          ),
          MiuixIconButton(
            onPressed: onImport,
            child: MiuixIcon(icon: Icons.file_upload_outlined),
          ),
          MiuixIconButton(
            onPressed: onImportFolder,
            child: MiuixIcon(icon: Icons.drive_folder_upload_outlined),
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
  final result = await showMiuixDialog<String>(
    context: context,
    title: title,
    builder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EcTextField(
          controller: controller,
          label: label,
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          autofocus: true,
        ),
        const SizedBox(height: 20),
        MiuixDialogActions(
          children: [
            MiuixTextButton(
              dialogContext.tr('common.cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            MiuixTextButton(
              dialogContext.tr('common.ok'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
          ],
        ),
      ],
    ),
  );
  // 延后到下一帧再 dispose：showDialog 的 Future 在 Navigator.pop 时即完成，
  // 此时弹窗 widget 树可能仍在当前帧内拆解，TextField 仍持有对 controller 的
  // 依赖。立即 dispose 会触发 "_dependents.isEmpty is not true" 断言。
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}
