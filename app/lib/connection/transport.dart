import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 一次 WS 连接所需的最小能力集合。
///
/// 抽出接口有两个目的:测试里可以注入假传输,不必真开 socket;
/// 将来若要换传输(加 TLS、走本地 IPC)也不影响协议层。
abstract interface class DaemonTransport {
  /// 建立连接。握手失败(端口不通、令牌不对)必须在这里抛异常。
  Future<void> connect(Uri uri);

  /// 发送一帧文本。
  void send(String payload);

  /// 入站文本帧。连接结束或出错时正常关闭。
  Stream<String> get incoming;

  /// 关闭连接。
  Future<void> close([int? code, String? reason]);
}

/// 基于 `web_socket_channel` 的真实实现:移动端/桌面走 dart:io,Web 端走浏览器 WebSocket。
class WebSocketDaemonTransport implements DaemonTransport {
  WebSocketChannel? _channel;
  final _incoming = StreamController<String>.broadcast();

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      // `ready` 在握手被拒时抛错——「令牌不对」正是靠它识别出来的。
      await channel.ready;
    } catch (_) {
      // 注意:这里**不能** await sink.close()。底层连接从未建立,
      // 这个 Future 可能永远不返回,会把上层连接流程一起挂死(踩过)。
      unawaited(channel.sink.close());
      rethrow;
    }
    _channel = channel;
    channel.stream.listen(
      (data) {
        if (_incoming.isClosed) return;
        if (data is String) {
          _incoming.add(data);
        } else if (data is List<int>) {
          _incoming.add(utf8.decode(data));
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_incoming.isClosed) _incoming.addError(error, stack);
      },
      onDone: () {
        if (!_incoming.isClosed) _incoming.close();
      },
      cancelOnError: false,
    );
  }

  @override
  void send(String payload) => _channel?.sink.add(payload);

  @override
  Future<void> close([int? code, String? reason]) async {
    final channel = _channel;
    _channel = null;
    if (!_incoming.isClosed) _incoming.close();
    if (channel == null) return;
    // 对端已经消失时关闭握手也可能等不到回应,给个上限,别拖住退出流程。
    await channel.sink
        .close(code, reason)
        .timeout(const Duration(seconds: 2), onTimeout: () {});
  }
}

/// 传输工厂。测试里 override 成假实现即可脱离真实网络。
typedef DaemonTransportFactory = DaemonTransport Function();

final daemonTransportFactoryProvider = Provider<DaemonTransportFactory>(
  (ref) => WebSocketDaemonTransport.new,
);
