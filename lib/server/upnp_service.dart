import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:port_forwarder/port_forwarder.dart';

import 'server_properties.dart';

/// UPnP / NAT-PMP 端口映射服务。
///
/// 在服务端启动后自动将 server-port 映射到公网，停止时解除映射。
/// 基于 `port_forwarder` 包实现，支持 UPnP、NAT-PMP 和 NAT-PCP 协议。
class UpnpService {
  /// 当前已发现的路由网关（懒加载）。
  Gateway? _gateway;

  /// 当前已映射的端口（用于停止时解除映射）。
  int? _mappedPort;

  /// 是否已有网关发现任务正在进行。
  bool _discovering = false;

  /// 发现网关并映射 TCP 端口。
  ///
  /// [workingDir] 为实例目录路径，用于读取 server.properties 获取端口号。
  /// 成功时返回实际映射的端口号，失败返回 null。
  Future<int?> openPort(String workingDir) async {
    try {
      final port = await _readPort(workingDir);
      if (port == null) return null;

      await _ensureGateway();
      if (_gateway == null) return null;

      await _gateway!.openPort(
        protocol: PortType.tcp,
        externalPort: port,
        portDescription: 'EdgeCube MC Server',
      );
      _mappedPort = port;
      return port;
    } catch (_) {
      return null;
    }
  }

  /// 解除当前端口映射。
  Future<void> closePort() async {
    final port = _mappedPort;
    if (port == null || _gateway == null) return;
    try {
      await _gateway!.closePort(
        protocol: PortType.tcp,
        externalPort: port,
      );
    } catch (_) {
      // 静默处理：路由器可能已重启或映射已过期。
    } finally {
      _mappedPort = null;
    }
  }

  /// 尝试获取路由器的公网 IP 地址。
  Future<String?> getExternalIp() async {
    try {
      await _ensureGateway();
      if (_gateway == null) return null;
      final addr = await _gateway!.externalAddress;
      return addr.address;
    } catch (_) {
      return null;
    }
  }

  // —— 内部方法 ——

  Future<void> _ensureGateway() async {
    if (_gateway != null || _discovering) return;
    _discovering = true;
    try {
      _gateway = await Gateway.discover();
    } finally {
      _discovering = false;
    }
  }

  /// 从实例目录的 server.properties 读取 server-port。
  Future<int?> _readPort(String workingDir) async {
    try {
      final file = File(p.join(workingDir, 'server.properties'));
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final props = ServerProperties.parse(content);
      return props.getInt('server-port') ?? 25565;
    } catch (_) {
      return 25565;
    }
  }
}
