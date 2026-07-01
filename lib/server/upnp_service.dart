import 'package:port_forwarder/port_forwarder.dart';

/// UPnP / NAT-PMP 端口映射服务。
///
/// 在服务端启动后自动将 server-port 映射到公网，停止时解除映射。
/// 基于 `port_forwarder` 包实现，支持 UPnP、NAT-PMP 和 NAT-PCP 协议。
class UpnpService {
  /// 当前已发现的路由网关（懒加载）。
  Gateway? _gateway;

  /// 当前已映射的外网端口（用于停止时解除映射）。
  int? _mappedExternalPort;

  /// 当前已映射的协议（用于停止时解除映射）。
  PortType? _mappedProtocol;

  /// 当前已映射的外网端口号（映射成功后可获取）。
  int? get mappedPort => _mappedExternalPort;

  /// 是否已有网关发现任务正在进行。
  bool _discovering = false;

  /// 发现网关并映射端口。
  ///
  /// [internalPort] 内网端口（服务端实际监听端口）。
  /// [externalPort] 外网端口（路由器公网端口），为 null 时与内网端口相同。
  /// [protocol] 映射协议，TCP（Java 版）或 UDP（基岩版）。
  /// 成功时返回实际映射的外网端口号，失败返回 null。
  Future<int?> openPort({
    required int internalPort,
    int? externalPort,
    PortType protocol = PortType.tcp,
  }) async {
    try {
      final extPort = externalPort ?? internalPort;

      await _ensureGateway();
      if (_gateway == null) return null;

      await _gateway!.openPort(
        protocol: protocol,
        externalPort: extPort,
        internalPort: internalPort,
        portDescription: 'EdgeCube MC Server',
      );
      _mappedExternalPort = extPort;
      _mappedProtocol = protocol;
      return extPort;
    } catch (_) {
      return null;
    }
  }

  /// 解除当前端口映射。
  Future<void> closePort() async {
    final port = _mappedExternalPort;
    final protocol = _mappedProtocol;
    if (port == null || protocol == null || _gateway == null) return;
    try {
      await _gateway!.closePort(protocol: protocol, externalPort: port);
    } catch (_) {
      // 静默处理：路由器可能已重启或映射已过期。
    } finally {
      _mappedExternalPort = null;
      _mappedProtocol = null;
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
}
