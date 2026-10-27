import '../connection/client.dart';
import 'models.dart';

/// 文件管理接口：把 daemon 的 `instance.files.*` 方法包成普通的 Dart 调用。
///
/// 一切错误都以 [`DaemonException`] 抛出，`code` 是稳定字符串
/// （`file_not_found` / `file_exists` / `file_utf8` / …）；
/// 上传/下载走 HTTP，不在这里（见 `transfer.dart`）。
class FileApi {
  const FileApi(this._client);

  final DaemonClient _client;

  /// 列出某个目录。目录不存在时 daemon 回空列表而不是报错。
  Future<FileListing> list(String id, {String path = ''}) async {
    final result = await _client.callObject(
      'instance.files.list',
      params: {'id': id, 'path': path},
    );
    return FileListing.fromJson(result);
  }

  /// 按名称子串搜索。[recursive] 为 false 时只找当前目录的直接子项。
  Future<SearchOutcome> search(
    String id, {
    required String path,
    required String query,
    bool recursive = false,
  }) async {
    final result = await _client.callObject(
      'instance.files.search',
      params: {
        'id': id,
        'path': path,
        'query': query,
        'recursive': recursive,
      },
    );
    return SearchOutcome.fromJson(result);
  }

  Future<FileEntry> createDir(
    String id, {
    required String name,
    String path = '',
  }) => _entry('instance.files.mkdir', id, {'name': name, 'path': path});

  Future<FileEntry> createFile(
    String id, {
    required String name,
    String path = '',
  }) => _entry('instance.files.create', id, {'name': name, 'path': path});

  /// 同目录内改名。
  Future<FileEntry> rename(
    String id, {
    required String path,
    required String name,
  }) => _entry('instance.files.rename', id, {'path': path, 'name': name});

  /// 删除文件/文件夹/符号链接（目录递归）。已经不在了返回 `false`（幂等）。
  Future<bool> delete(String id, {required String path}) async {
    final result = await _client.callObject(
      'instance.files.delete',
      params: {'id': id, 'path': path},
    );
    return result['deleted'] as bool? ?? false;
  }

  /// 复制到 [dest] 目录；重名自动加 ` (n)`。
  Future<FileEntry> copy(
    String id, {
    required String path,
    required String dest,
  }) => _entry('instance.files.copy', id, {'path': path, 'dest': dest});

  /// 移动到 [dest] 目录；重名报错（与 [copy] 的语义不同）。
  Future<FileEntry> move(
    String id, {
    required String path,
    required String dest,
  }) => _entry('instance.files.move', id, {'path': path, 'dest': dest});

  /// 读文本。[raw] 为 true 时按 latin1 兜底（「强制打开」）。
  Future<TextFile> readText(
    String id, {
    required String path,
    bool raw = false,
  }) async {
    final result = await _client.callObject(
      'instance.files.read',
      params: {'id': id, 'path': path, 'raw': raw},
    );
    return TextFile.fromJson(result);
  }

  /// 覆盖写入文本，返回新的字节数。
  Future<int> writeText(
    String id, {
    required String path,
    required String content,
  }) async {
    final result = await _client.callObject(
      'instance.files.write',
      params: {'id': id, 'path': path, 'content': content},
    );
    return (result['size'] as num?)?.toInt() ?? content.length;
  }

  /// 把若干条目压成一个归档（缺省名：单个源去扩展名，多个源「压缩文件」）。
  ///
  /// [format] 是 `zip`（缺省）/ `tar.gz` / `tar.xz` / `tar.zst`；
  /// daemon 会按格式补后缀、并换掉名字里已有的别的归档后缀。
  Future<FileEntry> compress(
    String id, {
    required List<String> paths,
    String dest = '',
    String? name,
    String format = 'zip',
  }) => _entry('instance.files.compress', id, {
    'paths': paths,
    'dest': dest,
    'format': format,
    if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
  });

  /// 解压归档到 [dest] 下的新子目录（格式由 daemon 按文件名识别）。
  Future<FileEntry> extract(
    String id, {
    required String path,
    String dest = '',
    String? name,
  }) => _entry('instance.files.extract', id, {
    'path': path,
    'dest': dest,
    if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
  });

  Future<FileEntry> _entry(
    String method,
    String id,
    Map<String, dynamic> params,
  ) async {
    final result = await _client.callObject(
      method,
      params: {'id': id, ...params},
    );
    final entry = result['entry'];
    if (entry is! Map) {
      throw DaemonException('internal', '$method 的返回里缺少 `entry`：$result');
    }
    return FileEntry.fromJson(entry.cast<String, dynamic>());
  }
}
