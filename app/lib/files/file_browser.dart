import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../instance/providers.dart';
import '../shell/background.dart';
import 'api.dart';
import 'client_files.dart';
import 'dialogs.dart';
import 'editor_page.dart';
import 'image_viewer.dart';
import 'folder_picker.dart';
import 'models.dart';
import 'providers.dart';

/// 行内 ⋮ 菜单的动作。
enum _FileAction { edit, rename, move, copy, compress, extract, export, delete }

/// 多选模式下可批量执行的动作。
enum _BulkAction { move, copy, compress, export }

/// 浏览并管理某个实例目录里的文件。
///
/// 导航被限制在实例目录之内（`_path` 是**相对**实例目录的路径，`''` 即根），
/// 越不过去。交互如下：
///
/// * 工具栏：上一级 / 相对路径（根目录）/ 搜索 / 新建文件 / 新建文件夹 /
///   导入文件 / 导入文件夹；
/// * 行内 ⋮：编辑（文本文件）、重命名、移动、复制、压缩、解压、导出、删除；
/// * 长按进多选：已选 N 项 / 全选·取消全选 / 删除 / ⋮（移动、复制、压缩、导出）；
/// * 下拉刷新；刷新是**静默**的（不拆列表，滚动位置不丢），首次加载才转圈；
/// * 目录优先、忽略大小写的排序由 daemon 做。
///
/// 行为要点（都写在明处）：
///
/// * **压缩可选 zip / tar.gz / tar.xz / tar.zst**；**解压按文件名自动认格式**
///   （zip、tar 家族、7z、rar、单流 gz/xz/bz2/zst/lz4），认得的才出现「解压」；
/// * **导入 / 导出走系统对话框**：daemon 在远端，导入是「本机 → HTTP 上传」，
///   导出是「HTTP 下载 → 另存为」。因此导出的目标由用户在保存对话框里定，
///   而不是先选目录；
/// * **多选导出打成一个 zip**：一次导出多份文件没法用一串保存对话框表达，
///   让 daemon 现场打一个 zip（同「压缩」缺省格式的做法）再另存，取消即不留痕；
/// * **导入文件夹不支持 Web**：浏览器拿不到本地目录结构，那个按钮在 Web 上不显示。
class FileBrowser extends ConsumerStatefulWidget {
  const FileBrowser({super.key, required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends ConsumerState<FileBrowser> {
  /// 当前目录（相对实例目录，`''` = 根）。
  String _path = '';
  List<FileEntry> _entries = const [];
  bool _loading = true;

  /// 列表加载失败的原因（已翻成中文）；只在还没有内容时显示。
  String? _error;

  final _scroll = ScrollController();

  /// 下拉刷新的受控标志（`_load` 静默刷新，不自己转圈）。
  bool _refreshing = false;

  // —— 多选 ——

  bool _selectionMode = false;
  final _selectedPaths = <String>{};

  // —— 搜索 ——

  bool _searchMode = false;
  bool _searchRecursive = false;
  bool _searching = false;
  final _search = TextEditingController();
  List<FileEntry> _results = const [];

  /// 搜索请求令牌：只有最后一次请求的结果算数（递归搜索可能慢）。
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_runSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.removeListener(_runSearch);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _atRoot => _path.isEmpty;

  FileApi? get _api => ref.read(fileApiProvider);

  /// 「回到文件页」时顺手看一眼当前目录有没有变。
  ///
  /// 与 [`_load`] 的区别：这里**先比对、再决定要不要 setState**。列表一模一样时
  /// 连一次重建都不做 —— 每次切到文件页签都重建列表的话，滚动位置会跳回顶部，
  /// 也会白闪一下。
  ///
  /// 静默：出错不弹提示。这只是「顺手看一眼」，不该在切页签时弹个错误出来。
  Future<void> _checkAndRefresh() async {
    final api = _api;
    if (api == null) return;
    // 记下这一次查的是哪个目录：结果回来时用户可能已经点进别的目录了
    final path = _path;
    try {
      final listing = await api.list(widget.instanceId, path: path);
      if (!mounted || path != _path) return;
      if (_entriesSame(listing.entries, _entries)) return;
      setState(() {
        _entries = listing.entries;
        _error = null;
      });
    } catch (_) {
      // 静默（见上）
    }
  }

  /// 两份列表是不是同一份 —— **逐条比路径与「是不是目录」**。
  ///
  /// 只比这两样：增删改名（路径变了）才刷新；
  /// 文件大小、时间戳变了不算变化 —— 那种刷新对用户没有意义，只会白花一次重建。
  static bool _entriesSame(List<FileEntry> a, List<FileEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].isDir != b[i].isDir) {
        return false;
      }
    }
    return true;
  }

  // ── 取数 ────────────────────────────────────────────────────────────────

  /// 取当前目录的列表。
  ///
  /// 首次加载（手上没内容）才转圈；之后一律静默刷新 —— 直接替换列表 widget
  /// 会连滚动位置一起丢掉。
  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '连接已断开';
        _entries = const [];
      });
      return;
    }
    if (_entries.isEmpty) setState(() => _loading = true);
    try {
      final listing = await api.list(widget.instanceId, path: _path);
      if (!mounted) return;
      setState(() {
        _entries = listing.entries;
        _error = null;
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

  Future<void> _handlePullRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// 文件操作可能动了根目录的 jar / 目录大小：让服务器页重取一遍。
  ///
  /// 做法也就是 V2 里惯用的那两行（见 `servers_page.dart`）。
  void _notifyInstanceFilesChanged() {
    ref.invalidate(instanceListProvider);
    ref.invalidate(selectedInstanceDetailProvider);
  }

  // ── 导航 ────────────────────────────────────────────────────────────────

  void _enter(FileEntry entry) {
    if (!entry.isDir) return;
    _path = entry.path;
    unawaited(_load());
  }

  void _goUp() {
    if (_atRoot) return;
    final at = _path.lastIndexOf('/');
    _path = at < 0 ? '' : _path.substring(0, at);
    unawaited(_load());
  }

  // ── 搜索 ────────────────────────────────────────────────────────────────

  void _enterSearch() => setState(() {
    _selectionMode = false;
    _selectedPaths.clear();
    _searchMode = true;
    _results = const [];
    _search.clear();
  });

  void _exitSearch() => setState(() {
    _searchMode = false;
    _searching = false;
    _results = const [];
    _search.clear();
  });

  void _toggleSearchRecursive(bool value) {
    setState(() => _searchRecursive = value);
    unawaited(_runSearch());
  }

  Future<void> _runSearch() async {
    if (!_searchMode) return;
    final api = _api;
    if (api == null) return;
    final query = _search.text;
    final token = ++_searchToken;
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
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
        recursive: _searchRecursive,
      );
      if (!mounted || token != _searchToken || !_searchMode) return;
      setState(() {
        _results = outcome.entries;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      showSnack(context, describeFileError(error));
    }
  }

  /// 从搜索结果点进目录：跳过去并退出搜索。
  void _openFromSearch(FileEntry entry) {
    if (!entry.isDir) return;
    _path = entry.path;
    _exitSearch();
    unawaited(_load());
  }

  // ── 单条目动作 ──────────────────────────────────────────────────────────

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

  Future<void> _openEditor(FileEntry entry) async {
    if (entry.isDir) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => Stack(
          fit: StackFit.expand,
          children: [
            // 这一页推在根 Navigator 上（整屏编辑），外壳那层背景被盖住了 ——
            // 自己补一层，不然透明的 Scaffold 会把页面露成白底。
            const BackgroundLayer(),
            TextEditorPage(
              instanceId: widget.instanceId,
              path: entry.path,
              name: entry.name,
            ),
          ],
        ),
      ),
    );
    // 回来后静默重取：文件可能已经改过（大小、时间都不对了）
    if (mounted) await _load();
  }

  /// 打开图片查看器：把服务端机器上的图片下载下来，全屏预览（可缩放）。
  Future<void> _openImage(FileEntry entry) async {
    if (entry.isDir) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ImageViewerPage(
          instanceId: widget.instanceId,
          path: entry.path,
          name: entry.name,
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final api = _api;
    if (api == null) return;
    final name = await promptText(context, title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.isEmpty) return;
    try {
      await api.createDir(widget.instanceId, name: name, path: _path);
      await _load();
    } catch (error) {
      if (mounted) await showErrorDialog(context, describeFileError(error));
    }
  }

  /// 新建空白文件；是可编辑的文本类型就顺手打开编辑器。
  Future<void> _createFile() async {
    final api = _api;
    if (api == null) return;
    final name = await promptText(context, title: '新建文件', label: '文件名称');
    if (name == null || name.isEmpty) return;
    try {
      final entry = await api.createFile(
        widget.instanceId,
        name: name,
        path: _path,
      );
      await _load();
      _notifyInstanceFilesChanged();
      if (entry.isEditableText && mounted) await _openEditor(entry);
    } catch (error) {
      if (mounted) await showErrorDialog(context, describeFileError(error));
    }
  }

  Future<void> _rename(FileEntry entry) async {
    final api = _api;
    if (api == null) return;
    final name = await promptText(
      context,
      title: '重命名',
      label: '新名称',
      initialValue: entry.name,
    );
    if (name == null || name.isEmpty) return;
    try {
      await api.rename(widget.instanceId, path: entry.path, name: name);
      await _load();
      _notifyInstanceFilesChanged();
    } catch (error) {
      if (mounted) await showErrorDialog(context, describeFileError(error));
    }
  }

  Future<void> _moveOrCopy(FileEntry entry, {required bool isMove}) async {
    final api = _api;
    if (api == null) return;
    final dest = await showFolderPicker(
      context,
      instanceId: widget.instanceId,
      title: isMove ? '移动到' : '复制到',
      confirmLabel: isMove ? '移动到此处' : '复制到此处',
      // 文件夹不能移进自己里面（连子树一起禁）
      disabledPath: entry.isDir ? entry.path : null,
    );
    if (dest == null || !mounted) return;
    final (_, error) = await runWithLoading(
      context,
      isMove ? '正在移动…' : '正在复制…',
      () => isMove
          ? api.move(widget.instanceId, path: entry.path, dest: dest)
          : api.copy(widget.instanceId, path: entry.path, dest: dest),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    await _load();
    _notifyInstanceFilesChanged();
  }

  /// 压缩单个条目：问包名和格式（预填「目录全名 / 文件去扩展名」，与 daemon
  /// 的缺省名规则一致），取消就什么都不做。
  Future<void> _compress(FileEntry entry) async {
    final api = _api;
    if (api == null) return;
    final choice = await promptArchive(context, initialName: _archiveBaseName(entry));
    if (choice == null || !mounted) return;
    final (_, error) = await runWithLoading(
      context,
      '正在压缩…',
      () => api.compress(
        widget.instanceId,
        paths: [entry.path],
        dest: _path,
        name: choice.name,
        format: choice.format,
      ),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    showSnack(context, '压缩完成');
    await _load();
  }

  /// 压缩对话框的预填名：目录用全名，文件去掉最后一个扩展名。
  String _archiveBaseName(FileEntry entry) {
    if (entry.isDir) return entry.name;
    final at = entry.name.lastIndexOf('.');
    return at > 0 ? entry.name.substring(0, at) : entry.name;
  }

  /// 解压：子文件夹名沿用 daemon 的缺省规则（归档名去掉全部扩展名）。
  Future<void> _extract(FileEntry entry) async {
    final api = _api;
    if (api == null) return;
    final (_, error) = await runWithLoading(
      context,
      '正在解压…',
      () => api.extract(widget.instanceId, path: entry.path, dest: _path),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    showSnack(context, '解压完成');
    await _load();
    _notifyInstanceFilesChanged();
  }

  Future<void> _export(FileEntry entry) async {
    await _downloadToFile(
      paths: [entry.path],
      fileName: entry.isDir ? '${entry.name}.zip' : entry.name,
    );
  }

  Future<void> _delete(FileEntry entry) async {
    final api = _api;
    if (api == null) return;
    final confirmed = await confirmDialog(
      context,
      title: '删除',
      message:
          '确定删除「${entry.name}」吗？'
          '${entry.isDir ? '该文件夹及其内容将被删除。' : ''}',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final (_, error) = await runWithLoading(
      context,
      '正在删除…',
      () => api.delete(widget.instanceId, path: entry.path),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    await _load();
    _notifyInstanceFilesChanged();
  }

  // ── 导入 / 导出 ─────────────────────────────────────────────────────────

  Future<void> _importFile() async {
    final transfer = ref.read(fileTransferProvider);
    if (transfer == null) {
      showSnack(context, '未连接到守护进程');
      return;
    }
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final file = picked.single;
    final (_, error) = await runWithLoading(
      context,
      '正在导入…',
      () => transfer.upload(
        widget.instanceId,
        dir: _path,
        name: file.name,
        content: file.readAsByteStream(),
        length: file.lengthSync(),
      ),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, '导入失败：${describeFileError(error)}');
      return;
    }
    showSnack(context, '导入完成');
    await _load();
    _notifyInstanceFilesChanged();
  }

  Future<void> _importFolder() async {
    final api = _api;
    final transfer = ref.read(fileTransferProvider);
    if (api == null || transfer == null) {
      showSnack(context, '未连接到守护进程');
      return;
    }
    final LocalFolderPick? picked;
    try {
      picked = await pickLocalFolder();
    } catch (error) {
      if (mounted) await showErrorDialog(context, '读取本地文件夹失败：$error');
      return;
    }
    if (picked == null || !mounted) return;
    final folder = picked;

    final progress = ValueNotifier<String>('正在导入…');
    final failed = <String>[];
    final total = folder.items.length;
    final (_, error) = await runWithProgress(context, progress, () async {
      // 目录先建出来（含空目录），文件按「相对路径 → 服务端子目录」逐个上传
      await api.createDir(widget.instanceId, name: folder.name, path: _path);
      final root = _atRoot ? folder.name : '$_path/${folder.name}';
      var done = 0;
      for (final item in folder.items) {
        final dir = item.dir.isEmpty ? root : '$root/${item.dir}';
        try {
          if (item.isDir) {
            await api.createDir(widget.instanceId, name: item.name, path: dir);
          } else {
            await transfer.upload(
              widget.instanceId,
              dir: dir,
              name: item.name,
              content: item.read(),
              length: item.length,
            );
          }
        } catch (_) {
          failed.add(item.relativePath);
        }
        done++;
        progress.value = '正在导入 $done/$total：${item.relativePath}';
      }
    });
    progress.dispose();
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    await _load();
    _notifyInstanceFilesChanged();
    _reportBulkResult('导入', failed);
  }

  /// 下载 [paths]（单个文件＝原样字节，目录＝daemon 现场打的 zip）并另存为。
  ///
  /// 多选用一个 zip 包：一次导出多份文件没法用一串保存对话框表达。
  Future<void> _downloadToFile({
    required List<String> paths,
    required String fileName,
  }) async {
    final api = _api;
    final transfer = ref.read(fileTransferProvider);
    if (api == null || transfer == null) {
      showSnack(context, '未连接到守护进程');
      return;
    }
    Uint8List? data;
    Object? failure;
    var name = fileName;
    if (paths.length == 1) {
      final (bytes, error) = await runWithLoading<Uint8List>(
        context,
        '正在导出…',
        () => transfer.download(widget.instanceId, paths.single),
      );
      data = bytes;
      failure = error;
    } else {
      // 先在实例目录里打一个 zip，下载完立刻删掉（保存时取消也不留痕）
      final (created, error) = await runWithLoading<(FileEntry, Uint8List)>(
        context,
        '正在导出…',
        () async {
          final zip = await api.compress(
            widget.instanceId,
            paths: paths,
            dest: _path,
            name: '导出.zip',
          );
          try {
            return (zip, await transfer.download(widget.instanceId, zip.path));
          } finally {
            await api.delete(widget.instanceId, path: zip.path);
          }
        },
      );
      failure = error;
      data = created?.$2;
      if (mounted) await _load(); // 临时 zip 建过又删了，列表重取一遍
    }
    if (!mounted) return;
    if (failure != null) {
      await showErrorDialog(context, '导出失败：${describeFileError(failure)}');
      return;
    }
    final bytes = data;
    if (bytes == null) return;
    try {
      final saved = await FilePicker.saveFile(fileName: name, bytes: bytes);
      if (saved != null && mounted) showSnack(context, '导出完成');
    } catch (error) {
      if (mounted) await showErrorDialog(context, '导出失败：$error');
    }
  }

  // ── 多选 ────────────────────────────────────────────────────────────────

  List<FileEntry> get _selectedEntries =>
      _entries.where((e) => _selectedPaths.contains(e.path)).toList();

  void _enterSelection(FileEntry entry) => setState(() {
    _selectionMode = true;
    _selectedPaths.add(entry.path);
  });

  void _toggleSelected(FileEntry entry) => setState(() {
    if (!_selectedPaths.remove(entry.path)) _selectedPaths.add(entry.path);
    if (_selectedPaths.isEmpty) _selectionMode = false;
  });

  void _toggleSelectAll() => setState(() {
    if (_selectedPaths.length == _entries.length) {
      _selectedPaths.clear();
      _selectionMode = false;
    } else {
      _selectedPaths
        ..clear()
        ..addAll(_entries.map((e) => e.path));
    }
  });

  void _clearSelection() {
    if (!_selectionMode && _selectedPaths.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  Future<void> _onBulkAction(_BulkAction action) async {
    switch (action) {
      case _BulkAction.move:
        await _moveSelected();
      case _BulkAction.copy:
        await _copySelected();
      case _BulkAction.compress:
        await _compressSelected();
      case _BulkAction.export:
        await _exportSelected();
    }
  }

  /// 汇报批量结果：全成功报个数，有失败就列出名字。
  void _reportBulkResult(String actionName, List<String> failed) {
    if (!mounted) return;
    if (failed.isEmpty) {
      showSnack(context, '$actionName完成');
    } else {
      unawaited(
        showErrorDialog(
          context,
          '$actionName完成，${failed.length} 项失败：${failed.join('、')}',
        ),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final api = _api;
    final entries = _selectedEntries;
    if (api == null || entries.isEmpty) return;
    final confirmed = await confirmDialog(
      context,
      title: '删除',
      message: '确定删除选中的 ${entries.length} 项吗？其中的文件夹及其内容将一并删除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final failed = <String>[];
    await runWithLoading(context, '正在删除…', () async {
      for (final entry in entries) {
        try {
          await api.delete(widget.instanceId, path: entry.path);
        } catch (_) {
          failed.add(entry.name);
        }
      }
    });
    if (!mounted) return;
    _clearSelection();
    await _load();
    _notifyInstanceFilesChanged();
    _reportBulkResult('删除', failed);
  }

  Future<void> _moveSelected() async {
    final api = _api;
    final entries = _selectedEntries;
    if (api == null || entries.isEmpty) return;
    final dest = await showFolderPicker(
      context,
      instanceId: widget.instanceId,
      title: '移动 ${entries.length} 项到',
    );
    if (dest == null || !mounted) return;
    await _runBulk(
      entries: entries,
      message: '正在移动…',
      actionName: '移动',
      action: (entry) =>
          api.move(widget.instanceId, path: entry.path, dest: dest),
    );
  }

  Future<void> _copySelected() async {
    final api = _api;
    final entries = _selectedEntries;
    if (api == null || entries.isEmpty) return;
    final dest = await showFolderPicker(
      context,
      instanceId: widget.instanceId,
      title: '复制 ${entries.length} 项到',
    );
    if (dest == null || !mounted) return;
    await _runBulk(
      entries: entries,
      message: '正在复制…',
      actionName: '复制',
      action: (entry) =>
          api.copy(widget.instanceId, path: entry.path, dest: dest),
    );
  }

  Future<void> _exportSelected() async {
    final entries = _selectedEntries;
    if (entries.isEmpty) return;
    await _downloadToFile(
      paths: [for (final entry in entries) entry.path],
      fileName: '导出.zip',
    );
    if (mounted) _clearSelection();
  }

  /// 批量压缩：先问包名和格式（可取消），再一次性压成一个归档。
  Future<void> _compressSelected() async {
    final api = _api;
    final entries = _selectedEntries;
    if (api == null || entries.isEmpty) return;
    final choice = await promptArchive(context);
    if (choice == null || !mounted) return;
    final (_, error) = await runWithLoading(
      context,
      '正在压缩…',
      () => api.compress(
        widget.instanceId,
        paths: [for (final entry in entries) entry.path],
        dest: _path,
        name: choice.name,
        format: choice.format,
      ),
    );
    if (!mounted) return;
    if (error != null) {
      await showErrorDialog(context, describeFileError(error));
      return;
    }
    _clearSelection();
    showSnack(context, '压缩完成');
    await _load();
  }

  /// 逐个跑一遍 [action]，数个失败数再统一汇报。
  Future<void> _runBulk({
    required List<FileEntry> entries,
    required String message,
    required String actionName,
    required Future<void> Function(FileEntry entry) action,
  }) async {
    final failed = <String>[];
    await runWithLoading(context, message, () async {
      for (final entry in entries) {
        try {
          await action(entry);
        } catch (_) {
          failed.add(entry.name);
        }
      }
    });
    if (!mounted) return;
    _clearSelection();
    await _load();
    _notifyInstanceFilesChanged();
    _reportBulkResult(actionName, failed);
  }

  // ── 界面 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 「回到文件页」的信号（`HomeShell` 切到文件页签时 `bump()`）。
    // 用 `listen` 而不是 `watch`：这是一次**事件**，不是要参与重建的状态。
    ref.listen(filesRefreshProvider, (_, _) => unawaited(_checkAndRefresh()));

    // 重连后客户端换了实例，列表得重取一次
    ref.listen(fileApiProvider, (previous, next) {
      if (previous != next) unawaited(_load());
    });

    return PopScope(
      // 根目录、没有多选、不在搜索：才让系统返回到上一层（退出 App）
      canPop: _atRoot && !_selectionMode && !_searchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectionMode) {
          _clearSelection();
          return;
        }
        if (_searchMode) {
          _exitSearch();
          return;
        }
        _goUp();
      },
      child: Column(
        children: [
          if (_searchMode)
            _searchBar()
          else if (_selectionMode)
            _selectionBar()
          else
            _toolbar(),
          const Divider(height: 1),
          Expanded(child: _searchMode ? _searchBody() : _listBody()),
        ],
      ),
    );
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('files_up'),
          tooltip: '上一级',
          onPressed: _atRoot ? null : _goUp,
          icon: const Icon(Icons.arrow_upward),
        ),
        Expanded(
          child: Text(
            _atRoot ? '根目录' : _path,
            key: const Key('files_path'),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          key: const Key('files_search'),
          tooltip: '搜索',
          onPressed: _enterSearch,
          icon: const Icon(Icons.search),
        ),
        IconButton(
          key: const Key('files_new_file'),
          tooltip: '新建文件',
          onPressed: _createFile,
          icon: const Icon(Icons.note_add_outlined),
        ),
        IconButton(
          key: const Key('files_new_folder'),
          tooltip: '新建文件夹',
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        IconButton(
          key: const Key('files_import'),
          tooltip: '导入文件',
          onPressed: _importFile,
          icon: const Icon(Icons.file_upload_outlined),
        ),
        // Web 上遍历不了本机目录，这个按钮不显示
        if (folderImportSupported())
          IconButton(
            key: const Key('files_import_folder'),
            tooltip: '导入文件夹',
            onPressed: _importFolder,
            icon: const Icon(Icons.drive_folder_upload_outlined),
          ),
      ],
    ),
  );

  Widget _selectionBar() {
    final count = _selectedPaths.length;
    final allSelected = _entries.isNotEmpty && count == _entries.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('files_exit_selection'),
            tooltip: '退出多选',
            onPressed: _clearSelection,
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              '已选 $count 项',
              key: const Key('files_selected_count'),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: const Key('files_select_all'),
            tooltip: allSelected ? '取消全选' : '全选',
            onPressed: _entries.isEmpty ? null : _toggleSelectAll,
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          ),
          IconButton(
            key: const Key('files_delete_selected'),
            tooltip: '删除',
            onPressed: count == 0 ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<_BulkAction>(
            key: const Key('files_bulk_menu'),
            tooltip: '更多操作',
            enabled: count > 0,
            onSelected: (action) => unawaited(_onBulkAction(action)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _BulkAction.move, child: Text('移动')),
              PopupMenuItem(value: _BulkAction.copy, child: Text('复制')),
              PopupMenuItem(value: _BulkAction.compress, child: Text('压缩')),
              PopupMenuItem(value: _BulkAction.export, child: Text('导出')),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('files_search_close'),
          tooltip: '退出搜索',
          onPressed: _exitSearch,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: TextField(
            key: const Key('files_search_field'),
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '在当前目录下搜索…',
            ),
          ),
        ),
        IconButton(
          key: const Key('files_search_recursive'),
          tooltip: '包含子目录',
          onPressed: () => _toggleSearchRecursive(!_searchRecursive),
          icon: Icon(
            _searchRecursive
                ? Icons.account_tree
                : Icons.account_tree_outlined,
            color: _searchRecursive
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
      ],
    ),
  );

  Widget _listBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _handlePullRefresh,
      // 刷新是静默的（不拆列表），转圈交给 RefreshIndicator 自己
      child: _entries.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(child: _emptyHint()),
                ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _entries.length,
              itemBuilder: (_, index) => _entryTile(_entries[index]),
            ),
    );
  }

  Widget _emptyHint() {
    final theme = Theme.of(context);
    final error = _error;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error ?? '此文件夹为空',
        key: const Key('files_empty_hint'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: error == null
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    );
  }

  Widget _searchBody() {
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_search.text.trim().isEmpty || _results.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty ? '输入名称以搜索当前目录' : '没有匹配的文件或目录',
          key: const Key('files_search_hint'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (_, index) => _entryTile(_results[index], inSearch: true),
    );
  }

  /// 一个条目。[inSearch] 用于搜索结果：不给多选、点目录会跳过去，
  /// 副标题显示相对路径。
  Widget _entryTile(FileEntry entry, {bool inSearch = false}) {
    final selected = _selectedPaths.contains(entry.path);
    return ListTile(
      key: Key('file_row_${entry.path}'),
      dense: true,
      leading: _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelected(entry),
            )
          : Icon(_iconFor(entry)),
      title: Text(entry.name),
      subtitle: Text(inSearch ? _searchSubtitle(entry) : _subtitle(entry)),
      trailing: _selectionMode
          ? null
          : PopupMenuButton<_FileAction>(
              key: Key('file_menu_${entry.path}'),
              tooltip: '更多操作',
              onSelected: (action) => unawaited(_onAction(action, entry)),
              itemBuilder: (_) => [
                // 白名单只管「点行就直接进编辑器」；编辑本身对任何文件都开放
                // （菜单里只排除目录）。
                if (!entry.isDir)
                  const PopupMenuItem(value: _FileAction.edit, child: Text('编辑')),
                const PopupMenuItem(value: _FileAction.rename, child: Text('重命名')),
                const PopupMenuItem(value: _FileAction.move, child: Text('移动')),
                const PopupMenuItem(value: _FileAction.copy, child: Text('复制')),
                const PopupMenuItem(value: _FileAction.compress, child: Text('压缩')),
                if (entry.isArchive)
                  const PopupMenuItem(value: _FileAction.extract, child: Text('解压')),
                const PopupMenuItem(value: _FileAction.export, child: Text('导出')),
                const PopupMenuItem(value: _FileAction.delete, child: Text('删除')),
              ],
              icon: const Icon(Icons.more_vert),
            ),
      onLongPress: inSearch || _selectionMode
          ? null
          : () => _enterSelection(entry),
      onTap: _selectionMode
          ? () => _toggleSelected(entry)
          : entry.isDir
          ? () => inSearch ? _openFromSearch(entry) : _enter(entry)
          : entry.isImage
          ? () => unawaited(_openImage(entry))
          : entry.isEditableText
          ? () => unawaited(_openEditor(entry))
          : null,
    );
  }

  /// 搜索结果里的副标题：显示相对当前目录的路径；直接子项就没必要重复了。
  String _searchSubtitle(FileEntry entry) {
    final parent = entry.path.lastIndexOf('/');
    final dir = parent < 0 ? '' : entry.path.substring(0, parent);
    if (dir == _path) return _subtitle(entry);
    return _path.isEmpty ? entry.path : dir.substring(_path.length + 1);
  }

  String _subtitle(FileEntry entry) {
    if (entry.isLink) {
      final target = entry.linkTarget;
      return (target == null || target.isEmpty) ? '符号链接' : '符号链接 → $target';
    }
    if (entry.isDir) return '文件夹';
    return formatSize(entry.size);
  }

  IconData _iconFor(FileEntry entry) {
    if (entry.isLink) return Icons.link;
    return entry.isDir ? Icons.folder : Icons.insert_drive_file_outlined;
  }
}
