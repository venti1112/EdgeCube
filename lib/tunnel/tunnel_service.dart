import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 与原生 tunnel 通道对接：启动/停止 frpc 内网穿透进程、接收日志与状态。
///
/// 对应 [MainActivity] 中注册的：
///  - MethodChannel `com.venti1112.edgecube/tunnel`
///  - EventChannel  `com.venti1112.edgecube/tunnel_events`
///
/// 隧道生命周期由 [ServerController] 管理，随服务端启停而启停。
class TunnelService {
  static const MethodChannel _method = MethodChannel(
    'com.venti1112.edgecube/tunnel',
  );
  static const EventChannel _events = EventChannel(
    'com.venti1112.edgecube/tunnel_events',
  );

  /// 当前设备架构是否内置了 frpc（assets 中有对应 bin 包）。
  Future<bool> isFrpcAvailable() async =>
      await _method.invokeMethod<bool>('isFrpcAvailable') ?? false;

  /// frpc 引擎是否已解压就位。
  Future<bool> isFrpcReady() async =>
      await _method.invokeMethod<bool>('isFrpcReady') ?? false;

  /// 当前是否有 frpc 进程在运行。
  Future<bool> isRunning() async =>
      await _method.invokeMethod<bool>('isRunning') ?? false;

  /// 启动 frpc。首次运行含解压，可能耗时数秒。
  Future<void> start({
    required String configPath,
    required String name,
    String? runtimeId,
  }) =>
      _method.invokeMethod('start', {
        'configPath': configPath,
        'name': name,
        'runtimeId': runtimeId,
      });

  /// 优雅停止（SIGTERM，触发 frpc GracefulClose）。
  Future<void> stop() => _method.invokeMethod('stop');

  /// 强制结束（SIGKILL）。
  Future<void> forceStop() => _method.invokeMethod('forceStop');

  /// 清空日志缓冲（与界面清屏同步）。
  ///
  /// 同时清空 Dart 侧静态缓存 [_logBuffer] 与原生侧 `logBuffer`，确保清屏后
  /// 新订阅者不会收到已清空的历史日志回放。
  Future<void> clearLog() {
    _logBuffer.clear();
    return _method.invokeMethod('clearLog');
  }

  /// 生成并写入 frpc 配置到应用私有目录，返回配置文件绝对路径。
  ///
  /// 写入 getApplicationSupportDirectory()（Android 上即 filesDir），与原生侧
  /// 解压 frpc 引擎的 runtimes/ 目录同级。
  Future<String> writeConfig(
    FrpcConfig config, {
    String fileName = 'frpc.toml',
  }) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(config.toToml(), flush: true);
    return file.path;
  }

  /// 将原始 TOML 文本写入应用私有目录的 frpc.toml，返回绝对路径。
  ///
  /// 供「直接编辑配置文件」使用：用户编辑的自定义内容不经 [FrpcConfig] 结构化
  /// 校验，原样写入并交由 frpc 解析。
  Future<String> writeRawConfig(
    String toml, {
    String fileName = 'frpc.toml',
  }) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(toml, flush: true);
    return file.path;
  }

  /// 便捷方法：写入配置后立即启动。
  Future<void> startWithConfig(
    FrpcConfig config, {
    String name = 'frpc',
  }) async {
    final path = await writeConfig(config);
    await start(configPath: path, name: name);
  }

  // —— 事件广播与缓存 ——
  //
  // 所有 TunnelService 实例共享同一个原生 EventChannel 订阅，避免多页面各自
  // 订阅导致 EventChannel sink 互相覆盖（后订阅者覆盖先订阅者，取消订阅时
  // 把 sink 置 null，使先订阅者收不到后续事件——曾导致 frpc 异常退出时
  // ServerController 状态卡在"FRP 连接中"）。
  static StreamController<TunnelEvent>? _broadcastController;
  static StreamSubscription<dynamic>? _rawSub;
  static final List<String> _logBuffer = [];
  static TunnelStateEvent? _lastState;
  static const int _maxLogBuffer = 2000;

  /// 原生事件流（日志 / 状态）。
  ///
  /// 返回的 stream 为每个订阅者独立回放历史日志与最后状态，随后转发实时事件。
  Stream<TunnelEvent> events() {
    _ensureBroadcast();
    final broadcast = _broadcastController!.stream;
    late StreamController<TunnelEvent> replay;
    StreamSubscription<TunnelEvent>? sub;
    replay = StreamController<TunnelEvent>(
      onListen: () {
        // 先回放缓存的历史日志与最后状态
        for (final line in _logBuffer) {
          replay.add(TunnelLogEvent(line));
        }
        final state = _lastState;
        if (state != null) replay.add(state);
        // 再订阅广播流接收后续实时事件
        sub = broadcast.listen(
          replay.add,
          onError: replay.addError,
          onDone: replay.close,
        );
      },
      onCancel: () {
        sub?.cancel();
      },
    );
    return replay.stream;
  }

  static void _ensureBroadcast() {
    if (_broadcastController != null) return;
    _broadcastController = StreamController<TunnelEvent>.broadcast(
      onListen: _startRawSub,
      onCancel: _stopRawSub,
    );
  }

  static void _startRawSub() {
    if (_rawSub != null) return;
    _rawSub = _events.receiveBroadcastStream().map(_parseEvent).listen(
      (event) {
        if (event is TunnelLogEvent) {
          _logBuffer.add(event.line);
          if (_logBuffer.length > _maxLogBuffer) {
            _logBuffer.removeRange(0, _logBuffer.length - _maxLogBuffer);
          }
        } else if (event is TunnelStateEvent) {
          _lastState = event;
        }
        _broadcastController?.add(event);
      },
      onError: (e) => _broadcastController?.addError(e),
    );
  }

  static void _stopRawSub() {
    _rawSub?.cancel();
    _rawSub = null;
  }

  static TunnelEvent _parseEvent(dynamic e) {
    final map = (e as Map).cast<String, dynamic>();
    switch (map['type']) {
      case 'log':
        return TunnelLogEvent(map['line'] as String? ?? '');
      case 'state':
        return TunnelStateEvent(
          status: map['status'] as String?,
          name: map['name'] as String?,
          exitCode: map['exitCode'] as int?,
        );
      default:
        return TunnelLogEvent(e.toString());
    }
  }
}

/// frpc 客户端配置（最小可用集，覆盖 MC 服务器穿透的典型场景）。
///
/// 生成 frp v0.52+ 的 TOML 格式。Java 版 MC 用 tcp，基岩版（PocketMine 等）用 udp。
class FrpcConfig {
  /// frps 服务器地址。
  final String serverAddr;

  /// frps 服务器端口。
  final int serverPort;

  /// 鉴权 token（与 frps 端一致）；为空则不启用。
  final String? authToken;

  /// 代理名称（在同一 frps 下需唯一）。
  final String proxyName;

  /// 代理类型：tcp / udp。
  final String proxyType;

  /// 本地服务地址。
  final String localIp;

  /// 本地服务端口（MC 服务端监听端口，如 25565）。
  final int localPort;

  /// 远程暴露端口（公网通过 serverAddr:remotePort 访问）。
  final int remotePort;

  /// 日志级别：trace / debug / info / warn / error。
  final String logLevel;

  const FrpcConfig({
    required this.serverAddr,
    this.serverPort = 7000,
    this.authToken,
    this.proxyName = 'minecraft',
    this.proxyType = 'tcp',
    this.localIp = '127.0.0.1',
    required this.localPort,
    required this.remotePort,
    this.logLevel = 'info',
  });

  /// 以新的 [localPort] 生成副本。
  FrpcConfig copyWith({int? localPort}) => FrpcConfig(
    serverAddr: serverAddr,
    serverPort: serverPort,
    authToken: authToken,
    proxyName: proxyName,
    proxyType: proxyType,
    localIp: localIp,
    localPort: localPort ?? this.localPort,
    remotePort: remotePort,
    logLevel: logLevel,
  );

  /// 序列化为 frpc 的 TOML 配置。log.to=console 确保日志输出到 stdout，
  /// 由原生侧的进程读取并回传到界面。
  String toToml() {
    final buffer = StringBuffer();
    buffer.writeln('serverAddr = ${_q(serverAddr)}');
    buffer.writeln('serverPort = $serverPort');
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      buffer.writeln('auth.token = ${_q(token)}');
    }
    buffer.writeln('log.to = "console"');
    buffer.writeln('log.level = ${_q(logLevel)}');
    buffer.writeln();
    buffer.writeln('[[proxies]]');
    buffer.writeln('name = ${_q(proxyName)}');
    buffer.writeln('type = ${_q(proxyType)}');
    buffer.writeln('localIP = ${_q(localIp)}');
    buffer.writeln('localPort = $localPort');
    buffer.writeln('remotePort = $remotePort');
    return buffer.toString();
  }

  /// 用于本地持久化的可序列化映射。
  Map<String, dynamic> toJsonMap() => {
    'serverAddr': serverAddr,
    'serverPort': serverPort,
    'authToken': authToken,
    'proxyName': proxyName,
    'proxyType': proxyType,
    'remotePort': remotePort,
  };

  /// 从持久化映射还原配置。[localPort] 为占位值（默认 25565），
  /// 实际运行时由 [ServerController] 按 server-port 注入。
  factory FrpcConfig.fromJsonMap(Map<String, dynamic> m) => FrpcConfig(
    serverAddr: m['serverAddr'] as String? ?? '',
    serverPort: (m['serverPort'] as int?) ?? 7000,
    authToken: m['authToken'] as String?,
    proxyName: (m['proxyName'] as String?) ?? 'minecraft',
    proxyType: (m['proxyType'] as String?) ?? 'tcp',
    localPort: 25565,
    remotePort: (m['remotePort'] as int?) ?? 25565,
  );

  /// TOML 基本字符串转义。
  static String _q(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

/// 原生回传的隧道事件。
sealed class TunnelEvent {
  const TunnelEvent();
}

/// 一行 frpc 输出（stdout/stderr 已合并）。
class TunnelLogEvent extends TunnelEvent {
  const TunnelLogEvent(this.line);

  final String line;
}

/// 进程状态变化（也用于界面重连时的状态回放）。
///
/// [status] 为 `null` 表示已停止；非空时为 `preparing` / `starting` / `running`。
class TunnelStateEvent extends TunnelEvent {
  const TunnelStateEvent({required this.status, this.name, this.exitCode});

  final String? status;
  final String? name;
  final int? exitCode;
}
