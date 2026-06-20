import 'dart:io';

/// 本机网络地址检测工具，供 FTP / MCP 页面展示对外可访问的地址。
///
/// 同时提供 IPv4 与「稳定」IPv6 检测：
/// - IPv4 取首个非回环地址（局域网地址）。
/// - 稳定 IPv6 优先解析 Linux/Android 的 `/proc/net/if_inet6`，按地址标志位
///   排除会定期轮换的临时隐私地址（IFA_F_TEMPORARY），从而给出固定可用的全局
///   地址；该文件不可读（非 Linux 平台等）时回退到 [NetworkInterface] 启发式。
class NetworkAddress {
  NetworkAddress._();

  /// 本机首个非回环 IPv4 地址（局域网地址）；无则返回 null。
  static Future<String?> detectIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        // 跳过回环接口。
        if (iface.name == 'lo' || iface.name == 'lo0') continue;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // 网络权限问题或接口不可用。
    }
    return null;
  }

  /// 本机「稳定」的全局 IPv6 地址（压缩规范格式，不含 %scope）；无则返回 null。
  ///
  /// 主路径解析 `/proc/net/if_inet6`，仅取 scope 为 global 且未标记
  /// 临时/废弃/试探/DAD 失败的地址，优先永久（PERMANENT）地址；文件不可读时
  /// 回退到 [NetworkInterface]（无法区分临时/永久，仅作兜底）。
  static Future<String?> detectStableIPv6() async {
    final fromProc = await _stableIPv6FromProc();
    if (fromProc != null) return fromProc;
    return _globalIPv6FromInterfaces();
  }

  // —— /proc/net/if_inet6 主路径 ——

  // IFA_F_* 地址标志位（见 Linux include/uapi/linux/if_addr.h）。
  static const int _ifaTemporary = 0x01; // 临时隐私地址，会定期轮换
  static const int _ifaDadFailed = 0x08; // 重复地址检测失败
  static const int _ifaDeprecated = 0x20; // 已废弃，不应再作源地址
  static const int _ifaTentative = 0x40; // 试探中（DAD 未完成），暂不可用
  static const int _ifaPermanent = 0x80; // 永久地址（手动或 EUI-64 稳定地址）
  // 不稳定/不可用标志集合：命中其一即排除。
  static const int _unstableMask =
      _ifaTemporary | _ifaDadFailed | _ifaDeprecated | _ifaTentative;

  static Future<String?> _stableIPv6FromProc() async {
    final List<String> lines;
    try {
      lines = await File('/proc/net/if_inet6').readAsLines();
    } catch (_) {
      return null; // 非 Linux/Android 或不可读：交由回退路径处理。
    }

    String? firstCandidate;
    for (final line in lines) {
      // 字段：<32hex 地址> <if_index> <prefix_len> <scope> <flags> <设备名>
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 5) continue;
      final hex = parts[0];
      if (hex.length != 32) continue;

      final scope = int.tryParse(parts[3], radix: 16);
      final flags = int.tryParse(parts[4], radix: 16);
      if (scope == null || flags == null) continue;

      // 仅全局地址（scope 0x00）；排除临时/废弃/试探/DAD 失败。
      if (scope != 0x00) continue;
      if (flags & _unstableMask != 0) continue;

      final addr = _formatHexV6(hex);
      if (addr == null) continue;

      // 优先永久地址；否则记录首个候选，继续寻找永久地址。
      if (flags & _ifaPermanent != 0) return addr;
      firstCandidate ??= addr;
    }
    return firstCandidate;
  }

  /// 把 32 个十六进制字符（无冒号）转为压缩规范的 IPv6 字符串；非法则返回 null。
  static String? _formatHexV6(String hex32) {
    final groups = <String>[];
    for (var i = 0; i < 32; i += 4) {
      groups.add(hex32.substring(i, i + 4));
    }
    final parsed = InternetAddress.tryParse(groups.join(':'));
    if (parsed == null || parsed.type != InternetAddressType.IPv6) return null;
    return parsed.address; // 输出压缩形式（如 2001:db8::1）。
  }

  // —— NetworkInterface 回退路径 ——

  static Future<String?> _globalIPv6FromInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // 排除回环、链路本地（fe80::）、组播；保留全局/唯一本地地址。
          if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) {
            continue;
          }
          return addr.address;
        }
      }
    } catch (_) {
      // 网络权限问题或接口不可用。
    }
    return null;
  }
}
