import 'package:flutter/services.dart';

/// 与原生 server 通道对接：启动/停止服务端 JVM、发送命令、接收日志与状态。
///
/// 对应 [MainActivity] 中注册的：
///  - MethodChannel `com.venti1112.edgecube/server`
///  - EventChannel  `com.venti1112.edgecube/server_events`
class ServerService {
  static const MethodChannel _method = MethodChannel(
    'com.venti1112.edgecube/server',
  );
  static const EventChannel _events = EventChannel(
    'com.venti1112.edgecube/server_events',
  );

  /// 当前设备架构下可用的 JRE 版本（如 ['jre17','jre21','jre25']）。
  Future<List<String>> availableVersions() async {
    final list = await _method.invokeMethod<List<dynamic>>('availableVersions');
    return list?.cast<String>() ?? const [];
  }

  /// 当前设备架构下可用的 PHP 运行时（如 ['php8.2']）；不支持的架构返回空。
  Future<List<String>> availablePhpRuntimes() async {
    final list = await _method.invokeMethod<List<dynamic>>(
      'availablePhpRuntimes',
    );
    return list?.cast<String>() ?? const [];
  }

  /// 指定版本的 JRE 是否已解压就位。
  Future<bool> isRuntimeReady(String version) async {
    final ready = await _method.invokeMethod<bool>('isRuntimeReady', {
      'version': version,
    });
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

  /// 启动服务端。含首次运行时解压，可能耗时数秒到数十秒。
  Future<void> start({
    required String instanceId,
    required String instanceName,
    required String workingDir,
    required String version,
    required String runtime,
    required List<String> jvmArgs,
    required List<String> programArgs,
  }) {
    return _method.invokeMethod('start', {
      'instanceId': instanceId,
      'instanceName': instanceName,
      'workingDir': workingDir,
      'version': version,
      'runtime': runtime,
      'jvmArgs': jvmArgs,
      'programArgs': programArgs,
    });
  }

  /// 向服务端 stdin 写入一行命令（自动补换行，供程序化发送使用）。
  Future<void> sendCommand(String line) =>
      _method.invokeMethod('sendCommand', {'line': line});

  /// 向服务端 PTY 写入原始按键字节（来自 xterm 终端的直接输入）。
  Future<void> writeInput(Uint8List bytes) =>
      _method.invokeMethod('writeInput', {'bytes': bytes});

  /// 同步终端窗口尺寸到 PTY（字符行列 + 单元像素），连接的程序据此重排。
  Future<void> resize({
    required int cols,
    required int rows,
    int cellWidth = 0,
    int cellHeight = 0,
  }) => _method.invokeMethod('resize', {
    'cols': cols,
    'rows': rows,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
  });

  /// 优雅停止（发送 stop 命令）。
  Future<void> stop() => _method.invokeMethod('stop');

  /// 强制结束进程。
  Future<void> forceStop() => _method.invokeMethod('forceStop');

  /// 开关 PTY 回显（命令行编辑模式关闭，原始终端模式开启）。
  Future<void> setEcho(bool echo) =>
      _method.invokeMethod('setEcho', {'echo': echo});

  /// 清空原生侧日志缓冲（与界面清屏同步，避免重连后又被回放）。
  Future<void> clearLog() => _method.invokeMethod('clearLog');

  /// 原生事件流（日志 / 状态）。
  Stream<ServerEvent> events() {
    return _events.receiveBroadcastStream().map((dynamic e) {
      final map = (e as Map).cast<String, dynamic>();
      switch (map['type']) {
        case 'log':
          return ServerLogEvent(map['line'] as String? ?? '');
        case 'term':
          return ServerTermEvent((map['bytes'] as Uint8List?) ?? Uint8List(0));
        case 'state':
          return ServerStateEvent(
            status: map['status'] as String?,
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

/// 一行服务端输出（已去 ANSI 的纯文本，供状态识别/玩家解析/复制日志）。
class ServerLogEvent extends ServerEvent {
  const ServerLogEvent(this.line);

  final String line;
}

/// 一段原始终端字节（含 ANSI/控制序列），交给 xterm 终端渲染。
class ServerTermEvent extends ServerEvent {
  const ServerTermEvent(this.bytes);

  final Uint8List bytes;
}

/// 进程状态变化（也用于界面重连时的状态回放）。
///
/// [status] 为 `null` 表示已停止；非空时为 `preparing` / `starting` / `running`。
class ServerStateEvent extends ServerEvent {
  const ServerStateEvent({
    required this.status,
    this.instanceId,
    this.instanceName,
    this.exitCode,
  });

  /// 进程状态字符串；null 表示已停止。
  final String? status;
  final String? instanceId;
  final String? instanceName;
  final int? exitCode;
}
