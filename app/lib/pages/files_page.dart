import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';
import 'text_editor_page.dart';

/// 可用内置编辑器打开的文本文件扩展名(小写,含点)。
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

/// 文件管理页(作用于全局当前实例,对齐 V1 文件管理):
/// 目录浏览 + 面包屑、新建文件夹、上传(分片断点续传 + 进度)、
/// 下载、重命名/移动、删除、压缩(zip)、解压(zip/tar/tar.gz)。
/// 压缩/解压为异步任务(202),提交后轮询任务直至完成并刷新列表。
class FilesPage extends ConsumerWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(currentInstanceProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('文件'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: instance == null
          ? _NoInstanceHint()
          : FilesBrowser(instanceId: instance.id, key: ValueKey(instance.id)),
    );
  }
}

class _NoInstanceHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '请先在「服务器」页选择实例',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 单个目录的浏览器。
class FilesBrowser extends ConsumerStatefulWidget {
  const FilesBrowser({super.key, required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<FilesBrowser> createState() => _FilesBrowserState();
}

class _FilesBrowserState extends ConsumerState<FilesBrowser> {
  /// 当前目录(相对实例 cwd),空字符串表示根。
  String _path = '';

  List<FileEntry>? _entries;
  bool _loading = true;
  String? _error;

  /// 正在上传的文件 (名称, 已传字节, 总字节)。
  ({String name, int done, int total})? _uploading;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  static const _chunkSize = 8 * 1024 * 1024; // 8 MiB

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    if (client == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final resp = await client
          .getFilesApi()
          .listFiles(instanceId: widget.instanceId, path: _path);
      final list = resp.data;
      if (!mounted || list == null) return;
      final entries = list.entries.toList();
      // 目录在前,再按名称排序
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _entries = entries;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _enter(String dir) {
    setState(() => _path = dir);
    _load();
  }

  void _goUp() => _enter(_parentOf(_path));

  String _parentOf(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? '' : p.substring(0, i);
  }

  void _jumpTo(String p) => _enter(p);

  // ── 对话框 ──────────────────────────────────────────────

  Future<String?> _promptText({
    required String title,
    String hint = '',
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── 操作 ────────────────────────────────────────────────

  Future<void> _newFolder() async {
    final client = _client;
    if (client == null) return;
    final name = await _promptText(title: '新建文件夹', hint: '文件夹名称');
    if (name == null || !mounted) return;
    try {
      await client.getFilesApi().createDirectory(
            fsPathRequest: FsPathRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = _join(_path, name)),
          );
      _load(silent: true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  String _join(String dir, String name) {
    if (dir.isEmpty) return name;
    return '$dir/$name';
  }

  Future<void> _rename(FileEntry entry) async {
    final client = _client;
    if (client == null) return;
    final name = await _promptText(
      title: '重命名',
      initial: entry.name,
      hint: '新名称',
    );
    if (name == null || name == entry.name || !mounted) return;
    try {
      await client.getFilesApi().moveFile(
            fsMoveRequest: FsMoveRequest((b) => b
              ..instanceId = widget.instanceId
              ..from = entry.path
              ..to = _join(_parentOf(entry.path), name)),
          );
      _load(silent: true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _delete(FileEntry entry) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await _confirm(
      '删除',
      entry.isDirectory
          ? '确定删除目录「${entry.name}」吗?其下所有内容将被递归删除。'
          : '确定删除文件「${entry.name}」吗?',
    );
    if (!confirmed || !mounted) return;
    try {
      await client.getFilesApi().deleteFile(
            fsPathRequest: FsPathRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = entry.path),
          );
      _load(silent: true);
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _download(FileEntry entry) async {
    final client = _client;
    if (client == null) return;
    try {
      final bytes = (await client
              .getFilesApi()
              .downloadFile(instanceId: widget.instanceId, path: entry.path))
          .data!;
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存文件',
        fileName: entry.name,
        bytes: bytes,
      );
      if (saved != null) {
        _snack('已下载「${entry.name}」');
      }
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _upload() async {
    final client = _client;
    if (client == null || _uploading != null) return;
    final files = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (files.isEmpty || !mounted) return;
    final targetDir = _path;
    for (final file in files) {
      if (!mounted) return;
      await _uploadOne(client, file, targetDir);
    }
    _load(silent: true);
  }

  /// 三段式分片上传:init(断点续传)→ piece × n → complete。
  Future<void> _uploadOne(
      EdgecubeApiClient client, PlatformFile file, String targetDir) async {
    final total = await file.length();
    // 无本地路径(web / content uri)时预读全文,供下方内存分片。
    final Uint8List? memBytes =
        (!kIsWeb && file.path != null) ? null : await file.readAsBytes();
    try {
      final session = (await client.getFilesApi().initFileUpload(
            uploadInitRequest: UploadInitRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = targetDir
              ..fileName = file.name
              ..sizeBytes = total),
          )).data!;
      final uploadId = session.uploadId;
      var offset = session.receivedBytes; // 服务端已有部分(断点续传)
      final raf = (!kIsWeb && file.path != null)
          ? await File(file.path!).open(mode: FileMode.read)
          : null;
      try {
        while (offset < total) {
          if (!mounted) return;
          final len = math.min(_chunkSize, total - offset);
          final Uint8List chunk;
          if (raf != null) {
            await raf.setPosition(offset);
            chunk = await raf.read(len);
          } else {
            chunk = Uint8List.sublistView(memBytes!, offset, offset + len);
          }
          final prog = (await client.getFilesApi().uploadFilePiece(
                uploadId: uploadId,
                offset: offset,
                body: MultipartFile.fromBytes(
                  chunk,
                  contentType: DioMediaType('application', 'octet-stream'),
                ),
              )).data!;
          offset = prog.receivedBytes;
          if (mounted) {
            setState(() =>
                _uploading = (name: file.name, done: offset, total: total));
          }
        }
      } finally {
        await raf?.close();
      }
      await client.getFilesApi().completeFileUpload(
            uploadCompleteRequest: UploadCompleteRequest((b) => b
              ..uploadId = uploadId),
          );
      if (mounted) {
        setState(() => _uploading = null);
        _snack('「${file.name}」上传完成');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = null);
        _snack('「${file.name}」上传失败:${apiErrorMessage(e)}');
      }
    }
  }

  bool _isArchive(FileEntry e) {
    if (e.isDirectory) return false;
    final n = e.name.toLowerCase();
    return n.endsWith('.zip') ||
        n.endsWith('.tar') ||
        n.endsWith('.tar.gz') ||
        n.endsWith('.tgz');
  }

  /// 是否为可用内置编辑器打开的文本文件(按扩展名判断)。
  bool _isEditableText(FileEntry e) {
    if (e.isDirectory) return false;
    return _textExtensions.contains(p.extension(e.name).toLowerCase());
  }

  /// 在内置文本编辑器中打开 [entry]。返回后刷新列表以更新大小与内容。
  Future<void> _openEditor(FileEntry entry) async {
    if (entry.isDirectory) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(
          instanceId: widget.instanceId,
          path: entry.path,
          name: entry.name,
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _compress(FileEntry entry) async {
    final client = _client;
    if (client == null) return;
    try {
      final job = (await client.getFilesApi().compressFile(
            fsCompressRequest: FsCompressRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = entry.path),
          )).data!;
      _snack('已提交压缩任务');
      await _waitForJob(job.jobId, '压缩「${entry.name}」');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  Future<void> _extract(FileEntry entry) async {
    final client = _client;
    if (client == null) return;
    try {
      final job = (await client.getFilesApi().extractFile(
            fsPathRequest: FsPathRequest((b) => b
              ..instanceId = widget.instanceId
              ..path = entry.path),
          )).data!;
      _snack('已提交解压任务');
      await _waitForJob(job.jobId, '解压「${entry.name}」');
    } catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  /// 轮询异步任务(压缩/解压)直至终结,结束后刷新列表。
  Future<void> _waitForJob(String jobId, String what) async {
    final client = _client;
    if (client == null) return;
    try {
      while (mounted) {
        final task = (await client.getTasksApi().getTask(jobId: jobId)).data;
        if (task == null) break;
        if (task.status == TaskStatus.succeeded) {
          _load(silent: true);
          _snack('$what完成');
          return;
        }
        if (task.status == TaskStatus.failed ||
            task.status == TaskStatus.cancelled) {
          _snack('$what失败:${task.error?.message ?? task.error?.code ?? '未知原因'}');
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      // 查询异常时静默,列表仍可手动刷新
    }
  }

  // ── 视图 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Column(
      children: [
        _breadcrumb(),
        Expanded(
          child: _loading && entries == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: entries == null ? _errorView() : _list(entries),
                ),
        ),
        if (_uploading != null) _uploadProgress(),
      ],
    );
  }

  /// 面包屑 + 返回上级 + 刷新 + 工具按钮(新建文件夹/上传)。
  Widget _breadcrumb() {
    final segments = _path.isEmpty ? <String>[] : _path.split('/');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回上级',
            onPressed: _path.isEmpty ? null : _goUp,
            icon: const Icon(Icons.arrow_upward),
          ),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _crumb(0, '/', ''),
                  for (var i = 0; i < segments.length; i++)
                    _crumb(i + 1, segments[i], segments.take(i + 1).join('/')),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => _load(silent: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '新建文件夹',
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: '上传文件',
            onPressed: _uploading != null ? null : _upload,
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
    );
  }

  Widget _crumb(int index, String label, String targetPath) {
    final cs = Theme.of(context).colorScheme;
    final selected = targetPath == _path;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) {
          if (!selected) _jumpTo(targetPath);
        },
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text('加载失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _list(List<FileEntry> entries) {
    final cs = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.folder_open_outlined, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '此目录为空',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final e = entries[index];
        return _entryTile(e);
      },
    );
  }

  Widget _entryTile(FileEntry e) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = StringBuffer();
    if (e.isDirectory) {
      subtitle.write('目录');
    } else {
      subtitle.write(_formatSize(e.sizeBytes));
    }
    subtitle.write(' · ${_formatTime(e.modifiedAt)}');
    final isArchive = _isArchive(e);
    return ListTile(
      leading: Icon(
        e.isDirectory
            ? Icons.folder_outlined
            : (e.executable == true
                ? Icons.terminal_outlined
                : Icons.insert_drive_file_outlined),
        color: e.isDirectory ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(e.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle.toString()),
      onTap: e.isDirectory
          ? () => _enter(e.path)
          : (_isEditableText(e) ? () => _openEditor(e) : null),
      trailing: PopupMenuButton<_EntryAction>(
        onSelected: (action) => switch (action) {
          _EntryAction.edit => _openEditor(e),
          _EntryAction.download => _download(e),
          _EntryAction.rename => _rename(e),
          _EntryAction.compress => _compress(e),
          _EntryAction.extract => _extract(e),
          _EntryAction.delete => _delete(e),
        },
        itemBuilder: (context) => [
          if (!e.isDirectory) ...[
            const PopupMenuItem(value: _EntryAction.download, child: Text('下载')),
            if (_isEditableText(e))
              const PopupMenuItem(value: _EntryAction.edit, child: Text('编辑')),
          ],
          const PopupMenuItem(value: _EntryAction.rename, child: Text('重命名')),
          const PopupMenuItem(value: _EntryAction.compress, child: Text('压缩')),
          if (isArchive)
            const PopupMenuItem(value: _EntryAction.extract, child: Text('解压')),
          const PopupMenuItem(value: _EntryAction.delete, child: Text('删除')),
        ],
      ),
    );
  }

  Widget _uploadProgress() {
    final u = _uploading!;
    final cs = Theme.of(context).colorScheme;
    final percent = u.total > 0 ? u.done / u.total : 0.0;
    return Material(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '上传中:${u.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '${_formatSize(u.done)} / ${_formatSize(u.total)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: percent, minHeight: 6),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String _formatTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

enum _EntryAction { edit, download, rename, compress, extract, delete }