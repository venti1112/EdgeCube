import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 实例终端 WS 客户端(契约 ws.md §5,/api/v1/ws/terminal)。
///
/// 帧协议:文本帧 JSON `{type,id,event,data}`(request/response/event),
/// 二进制帧 = 原始 PTY 字节(双向)。请求以 uuid 关联响应。
class TerminalClient {
  TerminalClient({
    required this.host,
    required this.port,
    required this.token,
    this.onData,
    this.onState,
    this.onWatcherCount,
    this.onDone,
  });

  final String host;
  final int port;
  final String token;

  /// PTY 原始输出(utf8 流式解码后的文本块)。
  final void Function(String text)? onData;

  /// 实例状态变化(state 事件)。
  final void Function(String status, int? exitCode)? onState;

  /// watcher 数变化。
  final void Function(int count)? onWatcherCount;

  /// 连接关闭(含失败)。
  final void Function(String? reason)? onDone;

  WebSocketChannel? _channel;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  ChunkedConversionSink<List<int>>? _decoderSink;
  int _nextId = 0;

  bool get connected => _channel != null;

  /// 建立连接(鉴权错误时抛 [WebSocketChannelException])。
  Future<void> connect() async {
    final url = Uri.parse(
      'ws://$host:$port/api/v1/ws/terminal?token=$token',
    );
    final channel = WebSocketChannel.connect(url);
    _channel = channel;
    // 流式 utf8 解码:跨块的中文等多字节序列不被截断
    _decoderSink = utf8.decoder.startChunkedConversion(
      _TextSink(onData),
    );
    channel.stream.listen(
      (data) {
        if (data is Uint8List || data is List<int>) {
          _decoderSink?.add(data as List<int>);
        } else if (data is String) {
          _handleText(data);
        }
      },
      onError: (Object error) {
        _fail('$error');
      },
      onDone: () {
        _fail(null);
      },
      cancelOnError: true,
    );
    // 等 WebSocket 打开(错误在此抛出)
    await channel.ready;
  }

  /// open:打开实例终端会话(实例未运行时仅回放历史日志,不自动启动)。
  /// 返回 opened 数据(含 status,已停止实例为 'stopped')。
  Future<Map<String, dynamic>> open(
    String instanceId, {
    int? cols,
    int? rows,
    bool replay = true,
  }) async {
    final data = await request('open', {
      'instanceId': instanceId,
      'cols': ?cols,
      'rows': ?rows,
      'replay': replay,
    });
    return (data['opened'] as Map<String, dynamic>?) ?? const {};
  }

  /// write:终端按键(文本)。
  Future<void> write(String input) =>
      request('write', {'input': input}).then<void>((_) {});

  /// input:命令框一行命令(自动补换行)。
  Future<void> sendCommand(String command) =>
      request('input', {'command': command}).then<void>((_) {});

  /// resize:本 watcher 终端尺寸变化。
  Future<void> resize(int cols, int rows) =>
      request('resize', {'cols': cols, 'rows': rows}).then<void>((_) {});

  /// close:关闭会话与连接(不停止实例)。
  Future<void> close() async {
    try {
      await request('close', {}).timeout(const Duration(seconds: 1));
    } catch (_) {}
    _fail(null);
    await _channel?.sink.close();
  }

  /// 发送原始按键字节(直接走 pty stdin)。
  void writeBytes(List<int> bytes) {
    _channel?.sink.add(bytes);
  }

  /// RPC 请求:id 关联响应。
  Future<Map<String, dynamic>> request(String event, Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) {
      return Future.error(StateError('终端未连接'));
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    channel.sink.add(
      jsonEncode({'type': 'request', 'id': id, 'event': event, 'data': data}),
    );
    return completer.future;
  }

  void _handleText(String text) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = frame['type'] as String?;
    switch (type) {
      case 'response':
        final id = frame['id'] as String?;
        final completer = _pending.remove(id);
        if (completer != null && !completer.isCompleted) {
          if (frame['status'] == 'ok') {
            final data = frame['data'];
            completer.complete(
              data is Map<String, dynamic> ? data : const {},
            );
          } else {
            final data = frame['data'];
            final message =
                data is Map ? (data['message'] ?? '请求失败') : '请求失败';
            completer.completeError(TerminalException('$message'));
          }
        }
      case 'event':
        final event = frame['event'] as String?;
        final data = frame['data'];
        if (data is! Map) return;
        switch (event) {
          case 'replay':
            final lines = data['lines'];
            if (lines is List) {
              final buffer = StringBuffer();
              for (final line in lines) {
                if (line is Map) {
                  final text = line['text'];
                  if (text is String) {
                    // 每行以 CRLF 收尾:xterm 对单独 LF 只下移光标不回行首,
                    // 长行 wrap/窗口 resize 后会导致下一行从错位列起写
                    buffer.write(text);
                    buffer.write('\r\n');
                  }
                }
              }
              final text = buffer.toString();
              if (text.isNotEmpty) onData?.call(text);
            }
          case 'state':
            onState?.call(
              (data['status'] as String?) ?? 'unknown',
              (data['exitCode'] as num?)?.toInt(),
            );
          case 'watchers':
            onWatcherCount?.call((data['count'] as num?)?.toInt() ?? 0);
        }
      case 'error':
        _fail((frame['message'] as String?) ?? '连接被服务器关闭');
    }
  }

  void _fail(String? reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(TerminalException(reason ?? '连接已关闭'));
      }
    }
    _pending.clear();
    _decoderSink?.close();
    _decoderSink = null;
    _channel = null;
    onDone?.call(reason);
  }
}

/// 终端请求失败。
class TerminalException implements Exception {
  const TerminalException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// utf8 流式解码的目标 sink(解码出的文本块写进终端)。
class _TextSink implements ChunkedConversionSink<String> {
  _TextSink(this._onData);

  final void Function(String)? _onData;

  @override
  void add(String chunk) => _onData?.call(chunk);

  @override
  void close() {}
}
