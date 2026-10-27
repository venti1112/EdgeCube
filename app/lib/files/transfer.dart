import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../connection/client.dart';
import '../connection/settings.dart';
import 'models.dart';

/// 文件传输（上传 / 下载）的抽象。
///
/// 这两件事必须走 HTTP：世界存档、服务端 jar 几十上百 MB，塞进 WS 的 JSON
/// 一问一答不现实（daemon 侧也是这么分的，见 README 的「文件管理」）。
/// 抽成接口是为了让 widget 测试不碰网络。
abstract class FileTransfer {
  /// 下载一个条目：文件拿到原样字节，目录拿到 daemon 现场打的 zip。
  Future<Uint8List> download(String instanceId, String path);

  /// 上传一个文件，返回落盘后的条目（重名时 daemon 会加 ` (1)`）。
  ///
  /// [content] 是字节流而不是 `Uint8List`：本机的大文件不该先整个读进内存。
  /// [length] 是声明的内容长度（能拿到就给，HTTP 层据此判断有没有发全）。
  Future<FileEntry> upload(
    String instanceId, {
    required String dir,
    required String name,
    required Stream<List<int>> content,
    int? length,
    bool overwrite = false,
  });
}

/// 走 daemon 的 HTTP 路由：`GET .../files/download`、`POST .../files/upload`。
class HttpFileTransfer implements FileTransfer {
  HttpFileTransfer(this._settings, {http.Client? client})
    : _client = client ?? http.Client();

  final ConnectionSettings _settings;
  final http.Client _client;

  void close() => _client.close();

  @override
  Future<Uint8List> download(String instanceId, String path) async {
    final uri = _settings.filesUri(
      instanceId,
      'download',
      query: {'path': path},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) throw _failure(response);
    return response.bodyBytes;
  }

  @override
  Future<FileEntry> upload(
    String instanceId, {
    required String dir,
    required String name,
    required Stream<List<int>> content,
    int? length,
    bool overwrite = false,
  }) async {
    final uri = _settings.filesUri(
      instanceId,
      'upload',
      query: {
        'path': dir,
        'name': name,
        if (overwrite) 'overwrite': 'true',
      },
    );
    final request = http.StreamedRequest('POST', uri);
    request.headers['content-type'] = 'application/octet-stream';
    if (length != null) request.contentLength = length;
    // 边读边发。这个 Future 不能 await —— 等它就变成「先把文件读完再发」了，
    // 内存红利全没了。
    //
    // **不能用 `content.pipe(request.sink)`**：`Stream.pipe` 的参数类型是
    // `StreamConsumer<T>`，而 `T` 取的是接收者的**运行期**类型参数。真实调用方给的是
    // `Stream<Uint8List>`（`pickFiles().readAsByteStream()` 与 `File.openRead()`
    // 都产出 `Uint8List`），于是运行期要求 `StreamConsumer<Uint8List>`，而
    // `request.sink` 是 `_StreamSinkWrapper<List<int>>` → 运行期直接抛
    // 「_StreamSinkWrapper<List<int>> is not a subtype of StreamConsumer<Uint8List>」。
    // 这里静态类型写的是 `Stream<List<int>>`，所以**编译期看不出来**，只有真发文件才炸。
    //
    // 换成 `addStream`：它要的就是 `Stream<List<int>>`（协变，`Stream<Uint8List>`
    // 天然满足）。但 `addStream` **不负责关 sink**（`pipe` = addStream + close），
    // 少的这一步必须自己补 —— 不关的话请求体永远不结束，下面那个 `send` 会一直挂着。
    unawaited(() async {
      try {
        await request.sink.addStream(content);
      } catch (_) {
        // 源读失败（文件被删/权限）：同样要关掉 sink，否则上面那个 send 挂死
      } finally {
        await request.sink.close();
      }
    }());

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) throw _failure(response);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['result'] is! Map) {
      throw const DaemonException('internal', '上传的返回不是预期形状');
    }
    final result = (decoded['result'] as Map).cast<String, dynamic>();
    final entry = result['entry'];
    if (entry is! Map) {
      throw const DaemonException('internal', '上传的返回里缺少 `entry`');
    }
    return FileEntry.fromJson(entry.cast<String, dynamic>());
  }

  /// 非 200 时把 daemon 的错误信封翻成 [`DaemonException`]。
  ///
  /// daemon 的 HTTP 错误体和 WS 一样是 `{"ok":false,"error":{…}}`
  /// （`status_for()` 已把 `*_not_found` 之类映射成 404/409/400）。
  static DaemonException _failure(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['error'] is Map) {
        final error = (decoded['error'] as Map).cast<String, dynamic>();
        return DaemonException(
          error['code'] as String? ?? 'internal',
          error['message'] as String? ?? '传输失败',
        );
      }
    } catch (_) {
      // 落到下面的兜底：不是 JSON 就当纯 HTTP 错误
    }
    return DaemonException(
      'http_${response.statusCode}',
      '传输失败（HTTP ${response.statusCode}）',
    );
  }
}
