import 'package:flutter/services.dart';

/// 与原生 server 通道对接：启动/停止服务端 JVM、发送命令、接收日志与状态。
///
/// 对应 [MainActivity] 中注册的：
///  - MethodChannel `com.venti1112.edgecube/server`
///  - EventChannel  `com.venti1112.edgecube/server_events`
class ServerService {
  static const MethodChannel _method =
      MethodChannel('com.venti1112.edgecube/server');
  static const EventChannel _events =
      EventChannel('com.venti1112.edgecube/server_events');

  /// 当前设备架构下可用的 JRE 版本（如 ['jre8','jre17','jre21','jre25']）。
  Future<List<String>> availableVersions() async {
    final list =
        await _method.invokeMethod<List<dynamic>>('availableVersions');
    return list?.cast<String>() ?? const [];
  }

  /// 指定版本的 JRE 是否已解压就位。
  Future<bool> isRuntimeReady(String version) async {
    final ready = await _method
        .invokeMethod<bool>('isRuntimeReady', {'version': version});
    return ready ?? false;
  }

  /// 当前是否有服务端进程在运行。
  Future<bool> isRunning() async {
    final running = await _method.invokeMethod<bool>('isRunning');
    return running ?? false;
  }

  /// 正在运行的实例 id；无则 null。
  Future<String?> activeInstanceId() =>
      _method.invokeMethod<String>('activeInstanceId');

  /// 启动服务端。含首次 JRE 解压，可能耗时数秒到数十秒。
  Future<void> start({
    required String instanceId,
    required String instanceName,
    required String workingDir,
    required String version,
    required List<String> jvmArgs,
    required List<String> programArgs,
  }) {
    return _method.invokeMethod('start', {
      'instanceId': instanceId,
      'instanceName': instanceName,
      'workingDir': workingDir,
      'version': version,
      'jvmArgs': jvmArgs,
      'programArgs': programArgs,
    });
  }

  /// 向服务端 stdin 写入一行命令。
  Future<void> sendCommand(String line) =>
      _method.invokeMethod('sendCommand', {'line': line});

  /// 优雅停止（发送 stop 命令）。
  Future<void> stop() => _method.invokeMethod('stop');

  /// 强制结束进程。
  Future<void> forceStop() => _method.invokeMethod('forceStop');

  /// 清空原生侧日志缓冲（与界面清屏同步，避免重连后又被回放）。
  Future<void> clearLog() => _method.invokeMethod('clearLog');

  /// 原生事件流（日志 / 状态）。
  Stream<ServerEvent> events() {
    return _events.receiveBroadcastStream().map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      switch (map['type']) {
        case 'log':
          return ServerLogEvent(map['line'] as String? ?? '');
        case 'state':
          return ServerStateEvent(
            running: map['running'] as bool? ?? false,
            instanceId: map['instanceId'] as String?,
            instanceName: map['instanceName'] as String?,
            exitCode: map['exitCode'] as int?,
          );
        default:
          return ServerLogEvent(e.toString());
      }
    });
  }
}

/// 原生回传的事件。
sealed class ServerEvent {
  const ServerEvent();
}

/// 一行服务端输出（stdout/stderr 已合并）。
class ServerLogEvent extends ServerEvent {
  const ServerLogEvent(this.line);

  final String line;
}

/// 进程状态变化（也用于界面重连时的状态回放）。
class ServerStateEvent extends ServerEvent {
  const ServerStateEvent({
    required this.running,
    this.instanceId,
    this.instanceName,
    this.exitCode,
  });

  final bool running;
  final String? instanceId;
  final String? instanceName;
  final int? exitCode;
}
