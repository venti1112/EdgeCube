import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// STUN（RFC 5389）over TCP 的最小实现，用于 NAT1（全锥形 NAT）打洞。
///
/// 与常见的 STUN over UDP 不同，这里刻意走 **TCP**：隧道要接受的是 TCP 入站
/// 连接（Minecraft Java 版），只有用 TCP 向 STUN 服务器发起探测，NAT 才会为
/// 「本地 TCP 端口 P」建立映射，随后外部才能经由该映射连回本机的监听端口。
///
/// 会话保持长连接（[StunTcpSession]）而非一次性探测，原因见
/// [StunTcpSession.connect] 的说明。
class StunClient {
  StunClient._();

  /// 内置的 STUN 服务器列表。
  ///
  /// 列表内每一台都经实网验证支持 **TCP** 3478 —— 大量常见 STUN 服务器
  /// （stun.l.google.com、stun.miwifi.com、stun.qq.com、stun.ekiga.net 等）
  /// 只提供 UDP，TCP 连得上却永远不回包，因此不可放进来。
  /// 顺序即尝试顺序。
  static const List<String> defaultServers = [
    'fwa.lifesizecloud.com',
    'stun.freeswitch.org',
    'turn.cloudflare.com',
    'global.turn.twilio.com',
    'stun.nextcloud.com',
    'stun.telnyx.com',
    'stun.sonetel.com',
    'stun.voip.blackberry.com',
  ];

  /// STUN 默认端口。
  static const int defaultPort = 3478;
}

/// STUN 返回的公网映射地址（本机某个本地端口在 NAT 外侧的样子）。
class StunMappedAddress {
  const StunMappedAddress(this.host, this.port);

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is StunMappedAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// STUN 协议层面的错误（超时、响应不合法、服务器返回 ERROR-CODE 等）。
class StunException implements Exception {
  const StunException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 与单台 STUN 服务器之间的一条 **长连接** TCP 会话。
///
/// ## 为什么必须保持长连接
///
/// NAT 映射由出站流量创建，并在空闲一段时间后回收。要让映射一直有效，就得
/// 持续有流量经过「本地端口 P」。MSL（Windows）的做法是每 15 秒用 P 作为源
/// 端口新建一条到 `www.baidu.com:80` 的连接；但该做法在 Linux/Android 上**不可行**：
///
/// - Linux 内核的 bind 冲突检查中，若已存在的同端口 socket 处于 `TCP_LISTEN`
///   状态，则新 bind 必须双方都带 `SO_REUSEPORT` 才不冲突；而 Dart 的
///   `ServerSocket.bind` 不设置 `SO_REUSEPORT`，也无法在 bind 前设置。
/// - 反过来，若已存在的 socket 处于 **ESTABLISHED** 且双方都带 `SO_REUSEADDR`，
///   则不冲突。`ServerSocket.bind` 在 POSIX 上默认设置 `SO_REUSEADDR`。
///
/// 因此这里改为：**探测用的这条连接本身就是保活连接**，连上后立刻用
/// [Socket.setRawOption] 给它打上 `SO_REUSEADDR`，使随后
/// `ServerSocket.bind(0.0.0.0, P)` 得以成功；之后周期性在这条连接上重发
/// Binding Request 既保活了 NAT 映射，又能顺带发现公网地址变化。
class StunTcpSession {
  StunTcpSession._(this._socket, this.server);

  /// 建立会话并完成端口复用准备。
  ///
  /// 连接成功后立即设置 `SO_REUSEADDR`——这一步是整个隧道能成立的前提，
  /// 失败则直接抛出，让上层换一台服务器重试。
  static Future<StunTcpSession> connect(
    String server, {
    int port = StunClient.defaultPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(server, port, timeout: timeout);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      _setReuseAddress(socket);
    } catch (e) {
      socket.destroy();
      throw StunException('无法为探测连接启用端口复用：$e');
    }
    return StunTcpSession._(socket, server).._listen();
  }

  final Socket _socket;

  /// 服务器主机名，仅用于日志。
  final String server;

  /// 本地端口 —— NAT 映射的内侧端点，隧道监听套接字要绑定的就是它。
  int get localPort => _socket.port;

  final _pending = <String, Completer<StunMappedAddress>>{};
  final _done = Completer<void>();
  final _rand = Random.secure();

  /// 累积的入站字节，按 STUN 分帧规则逐条切出完整消息。
  List<int> _buffer = [];
  bool _closed = false;

  bool get isClosed => _closed;

  /// 连接断开（正常关闭或出错）时完成。
  Future<void> get done => _done.future;

  void _listen() {
    _socket.listen(
      _onData,
      onError: (Object e) => _shutdown('探测连接出错：$e'),
      onDone: () => _shutdown('探测连接已被对端关闭'),
      cancelOnError: true,
    );
  }

  /// 发起一次 Binding 事务，返回本连接的公网映射地址。
  ///
  /// 同一会话可重复调用（用于保活与公网地址变化检测）。
  Future<StunMappedAddress> requestMapping({
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (_closed) {
      return Future.error(const StunException('探测连接已关闭'));
    }
    final txId = Uint8List.fromList(
      List<int>.generate(12, (_) => _rand.nextInt(256)),
    );
    final key = _hex(txId);
    final completer = Completer<StunMappedAddress>();
    _pending[key] = completer;
    try {
      _socket.add(_buildBindingRequest(txId));
    } catch (e) {
      _pending.remove(key);
      return Future.error(StunException('发送 Binding 请求失败：$e'));
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(key);
        throw const StunException('等待 STUN 响应超时');
      },
    );
  }

  Future<void> close() async {
    _shutdown(null);
    try {
      _socket.destroy();
    } catch (_) {
      // 已断开，忽略。
    }
  }

  // —— 内部 ——

  void _onData(Uint8List chunk) {
    _buffer = [..._buffer, ...chunk];
    // 单条 STUN 消息不会很大，超出上限说明对端不是 STUN 服务器，直接放弃。
    if (_buffer.length > 8192) {
      _shutdown('响应数据异常（非 STUN 服务器？）');
      return;
    }
    while (_buffer.length >= 20) {
      final length = (_buffer[2] << 8) | _buffer[3];
      final total = 20 + length;
      if (_buffer.length < total) return;
      final message = Uint8List.fromList(_buffer.sublist(0, total));
      _buffer = _buffer.sublist(total);
      _handleMessage(message);
    }
  }

  void _handleMessage(Uint8List message) {
    // 校验 magic cookie，非 STUN 报文直接忽略。
    if (message[4] != 0x21 ||
        message[5] != 0x12 ||
        message[6] != 0xA4 ||
        message[7] != 0x42) {
      return;
    }
    final type = (message[0] << 8) | message[1];
    final key = _hex(message.sublist(8, 20));
    final completer = _pending.remove(key);
    if (completer == null || completer.isCompleted) return;

    // 0x0101 = Binding Success Response，0x0111 = Binding Error Response。
    if (type == 0x0111) {
      completer.completeError(
        StunException('STUN 服务器返回错误：${_parseErrorCode(message) ?? '未知'}'),
      );
      return;
    }
    if (type != 0x0101) {
      completer.completeError(
        StunException('非预期的 STUN 响应类型 0x${type.toRadixString(16)}'),
      );
      return;
    }
    final mapped = _parseMappedAddress(message);
    if (mapped == null) {
      completer.completeError(const StunException('响应中没有可用的映射地址'));
    } else {
      completer.complete(mapped);
    }
  }

  /// 断开会话并让所有在途事务失败。
  void _shutdown(String? reason) {
    if (_closed) return;
    _closed = true;
    final error = StunException(reason ?? '探测连接已关闭');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
  }

  // —— 报文编解码 ——

  /// Binding Request：类型 0x0001、长度 0、magic cookie、12 字节事务 ID。
  static Uint8List _buildBindingRequest(Uint8List txId) {
    final message = Uint8List(20);
    message[0] = 0x00;
    message[1] = 0x01;
    message[2] = 0x00;
    message[3] = 0x00;
    message[4] = 0x21;
    message[5] = 0x12;
    message[6] = 0xA4;
    message[7] = 0x42;
    message.setRange(8, 20, txId);
    return message;
  }

  /// 遍历属性，优先取 XOR-MAPPED-ADDRESS（0x0020），回退 MAPPED-ADDRESS（0x0001）。
  ///
  /// 只接受 IPv4（family = 0x01）：隧道要绑定的是 IPv4 监听端口，
  /// 拿到 IPv6 映射对本功能没有意义。
  static StunMappedAddress? _parseMappedAddress(Uint8List message) {
    StunMappedAddress? fallback;
    final payloadLength = (message[2] << 8) | message[3];
    final end = min(20 + payloadLength, message.length);
    var offset = 20;
    while (offset + 4 <= end) {
      final type = (message[offset] << 8) | message[offset + 1];
      final length = (message[offset + 2] << 8) | message[offset + 3];
      final valueStart = offset + 4;
      if (valueStart + length > end) break;

      if ((type == 0x0020 || type == 0x0001) && length >= 8) {
        final family = message[valueStart + 1];
        if (family == 0x01) {
          var port = (message[valueStart + 2] << 8) | message[valueStart + 3];
          final ip = Uint8List.fromList(
            message.sublist(valueStart + 4, valueStart + 8),
          );
          if (type == 0x0020) {
            // XOR-MAPPED-ADDRESS：端口与地址分别与 magic cookie 异或。
            port ^= 0x2112;
            ip[0] ^= 0x21;
            ip[1] ^= 0x12;
            ip[2] ^= 0xA4;
            ip[3] ^= 0x42;
          }
          final address = StunMappedAddress(ip.join('.'), port);
          if (type == 0x0020) return address;
          fallback ??= address;
        }
      }
      // 属性值按 4 字节对齐填充。
      offset = valueStart + length + ((4 - (length % 4)) % 4);
    }
    return fallback;
  }

  /// 解析 ERROR-CODE（0x0009）属性，形如 `401 Unauthorized`。
  static String? _parseErrorCode(Uint8List message) {
    final payloadLength = (message[2] << 8) | message[3];
    final end = min(20 + payloadLength, message.length);
    var offset = 20;
    while (offset + 4 <= end) {
      final type = (message[offset] << 8) | message[offset + 1];
      final length = (message[offset + 2] << 8) | message[offset + 3];
      final valueStart = offset + 4;
      if (valueStart + length > end) break;
      if (type == 0x0009 && length >= 4) {
        final code = message[valueStart + 2] * 100 + message[valueStart + 3];
        final reason = String.fromCharCodes(
          message.sublist(valueStart + 4, valueStart + length),
        );
        return '$code $reason';
      }
      offset = valueStart + length + ((4 - (length % 4)) % 4);
    }
    return null;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// `SOL_SOCKET` 下 `SO_REUSEADDR` 的取值（各平台不同）。
///
/// Dart 只为少数选项提供了具名常量，`SO_REUSEADDR` 不在其中，故按平台硬编码。
int get _soReuseAddr => (Platform.isLinux || Platform.isAndroid) ? 2 : 4;

/// 给已连接的 socket 打上 `SO_REUSEADDR`。
///
/// bind 冲突检查读取的是对端 socket **当前** 的 `sk_reuse` 标志，因此在
/// connect 之后设置同样有效——这正是本实现能在保活连接存活期间把
/// `ServerSocket` 绑定到同一本地端口的原因。
void _setReuseAddress(Socket socket) {
  socket.setRawOption(
    RawSocketOption.fromInt(RawSocketOption.levelSocket, _soReuseAddr, 1),
  );
}
