import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 控制台连接的最小抽象：一条**收帧**的流 + 一个**发帧**的函数。
///
/// 生产实现是 [`WebSocketPtyTransport`]；测试用手搓的内存实现 ——
/// 不然为了验协议解析还得真起一个服务端。
///
/// 「帧」就是 WebSocket 那一套：`String` = 文本帧（控制 JSON），
/// `List<int>` = 二进制帧（原始输出）。
abstract class PtyTransport {
  /// 收到的帧。
  Stream<dynamic> get frames;

  /// 发一帧。
  void send(dynamic frame);

  /// 关掉。
  Future<void> close();
}

/// 生产实现：一条真正的 WebSocket。
class WebSocketPtyTransport implements PtyTransport {
  WebSocketPtyTransport(Uri url) : _channel = WebSocketChannel.connect(url);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get frames => _channel.stream;

  @override
  void send(dynamic frame) => _channel.sink.add(frame);

  @override
  Future<void> close() async {
    // 已经关过的通道再关一次会抛，这里吞掉 —— 调用方经常在 dispose 里重复关。
    try {
      await _channel.sink.close();
    } catch (_) {
      // 无所谓
    }
  }
}

/// 传输工厂。测试里 override 成假实现即可脱离真实网络。
typedef PtyTransportFactory = PtyTransport Function(Uri);

final ptyTransportFactoryProvider = Provider<PtyTransportFactory>(
  (ref) => WebSocketPtyTransport.new,
);
