import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// MCP 服务的运行时封装。
///
/// 与 FTP（在 Android 原生侧运行）不同，MCP 服务基于纯 Dart 的
/// [`mcp_dart`](https://pub.dev/packages/mcp_dart) 包，运行在 Flutter 的
/// Dart isolate 内：[StreamableMcpServer] 内部用 `dart:io HttpServer` 监听端口、
/// 管理会话、处理 CORS 与鉴权，外部 AI Agent 经 `http://<手机IP>:<端口>/mcp`
/// （Streamable HTTP）连接。
class McpService {
  StreamableMcpServer? _server;
  bool _running = false;

  /// MCP 服务是否正在监听。
  bool get isRunning => _running;

  /// 启动 MCP 服务。
  ///
  /// [port] 监听端口；[token] 访问令牌（为空则不鉴权）；[serverFactory] 为每个
  /// 会话创建一个已注册工具的 [McpServer]。
  ///
  /// [ipv6] 为 true 时绑定 IPv6 通配地址 `::`（在 Android 上为双栈，IPv4/IPv6 均可达）；
  /// 否则绑定 `0.0.0.0`（仅 IPv4）。关闭 DNS 重绑定保护，因为客户端会以任意局域网/
  /// 公网 IP 连接（默认开启会因 Host 头不在白名单而返回 403），访问安全由 Bearer
  /// Token 保证。
  Future<void> start({
    required int port,
    required String token,
    required bool ipv6Enabled,
    required McpServer Function(String sessionId) serverFactory,
  }) async {
    if (_running) return;
    final expected = token.isEmpty ? null : 'Bearer $token';
    final server = StreamableMcpServer(
      serverFactory: serverFactory,
      host: ipv6Enabled ? '::' : '0.0.0.0',
      port: port,
      path: '/mcp',
      enableDnsRebindingProtection: false,
      authenticator: expected == null
          ? null
          : (dynamic request) =>
                (request as HttpRequest)
                    .headers
                    .value(HttpHeaders.authorizationHeader) ==
                expected,
    );
    await server.start();
    _server = server;
    _running = true;
  }

  /// 停止 MCP 服务并关闭所有会话。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _running = false;
    if (server != null) {
      await server.stop();
    }
  }
}
