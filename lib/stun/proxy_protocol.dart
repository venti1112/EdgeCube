import 'dart:io';
import 'dart:typed_data';

/// PROXY protocol v2 头部构造（HAProxy 规范）。
///
/// 隧道转发会让服务端只看到 `127.0.0.1`，开启后在转发的第一批字节前插入本头部，
/// 服务端（Velocity / Paper 等，需自行开启 `proxy_protocol`）便能拿到玩家真实
/// IP。服务端未开启时会把这些字节当作协议数据，导致玩家无法进入，故默认关闭。
class ProxyProtocolV2 {
  ProxyProtocolV2._();

  /// 12 字节固定签名。
  static const List<int> signature = [
    0x0D, 0x0A, 0x0D, 0x0A, 0x00, 0x0D,
    0x0A, 0x51, 0x55, 0x49, 0x54, 0x0A,
  ];

  /// 构造一条 TCP 连接的 PROXY v2 头部。
  ///
  /// [src] / [srcPort] 为玩家真实来源，[dst] / [dstPort] 为玩家实际连上的
  /// 本地监听端点。源与目的地址族不一致（极少见）时按 IPv6 处理，IPv4 地址
  /// 会被映射为 `::ffff:a.b.c.d`。
  static Uint8List buildHeader({
    required InternetAddress src,
    required int srcPort,
    required InternetAddress dst,
    required int dstPort,
  }) {
    final isIPv4 = src.type == InternetAddressType.IPv4 &&
        dst.type == InternetAddressType.IPv4;
    final addressLength = isIPv4 ? 12 : 36;
    final header = Uint8List(16 + addressLength);
    header.setRange(0, 12, signature);
    header[12] = 0x21; // 版本 2（高 4 位） + PROXY 命令（低 4 位）
    header[13] = isIPv4 ? 0x11 : 0x21; // TCP over IPv4 / TCP over IPv6
    header[14] = (addressLength >> 8) & 0xFF;
    header[15] = addressLength & 0xFF;

    final addressSize = isIPv4 ? 4 : 16;
    var offset = 16;
    header.setRange(offset, offset + addressSize, _rawAddress(src, isIPv4));
    offset += addressSize;
    header.setRange(offset, offset + addressSize, _rawAddress(dst, isIPv4));
    offset += addressSize;
    header[offset++] = (srcPort >> 8) & 0xFF;
    header[offset++] = srcPort & 0xFF;
    header[offset++] = (dstPort >> 8) & 0xFF;
    header[offset] = dstPort & 0xFF;
    return header;
  }

  /// 取地址原始字节；IPv6 头部里的 IPv4 地址按 IPv4-mapped 形式补齐到 16 字节。
  static Uint8List _rawAddress(InternetAddress address, bool isIPv4) {
    final raw = address.rawAddress;
    if (isIPv4 || raw.length == 16) return raw;
    final mapped = Uint8List(16);
    mapped[10] = 0xFF;
    mapped[11] = 0xFF;
    mapped.setRange(12, 16, raw);
    return mapped;
  }
}
