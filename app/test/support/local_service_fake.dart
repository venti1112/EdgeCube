import 'dart:async';

import 'package:edgecube_app/local_service/platform.dart';

/// 测试用的本地服务平台:状态与日志都由用例手动推进。
class FakeLocalServicePlatform implements LocalServicePlatform {
  FakeLocalServicePlatform({this.supported = true, LocalServiceStatus? initial})
    : _status = initial ?? const LocalServiceStatus();

  bool supported;
  LocalServiceStatus _status;
  final _events = StreamController<LocalServiceEvent>.broadcast();

  final List<String> lines = [];
  int startCalls = 0;
  int stopCalls = 0;
  int clearLogsCalls = 0;

  LocalServiceStatus get current => _status;

  void _emitStatus(LocalServiceStatus status) {
    _status = status;
    _events.add(LocalServiceStatusEvent(status));
  }

  void log(String line) {
    lines.add(line);
    _events.add(LocalServiceLogEvent(line));
  }

  /// 模拟 rootfs 解压完成、daemon 就绪。
  void finishStart({
    String host = '127.0.0.1',
    int port = 41001,
    String token = 'local-token',
    String version = '2.0.0',
  }) {
    _emitStatus(
      LocalServiceStatus(
        phase: LocalServicePhase.running,
        host: host,
        port: port,
        wsPath: '/ws',
        token: token,
        pid: 1234,
        version: version,
        rootfsVersion: 'bookworm-minbase-r1',
        prepared: true,
      ),
    );
  }

  void fail(String message) {
    _emitStatus(
      LocalServiceStatus(phase: LocalServicePhase.failed, message: message),
    );
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<LocalServiceStatus> status() async => _status;

  @override
  Future<LocalServiceStatus> start() async {
    startCalls++;
    final status = LocalServiceStatus(
      phase: LocalServicePhase.preparing,
      message: '正在准备本地环境…',
      prepared: _status.prepared,
      rootfsVersion: _status.rootfsVersion,
    );
    _emitStatus(status);
    return status;
  }

  @override
  Future<LocalServiceStatus> stop() async {
    stopCalls++;
    final status = const LocalServiceStatus(phase: LocalServicePhase.stopped);
    _emitStatus(status);
    return status;
  }

  @override
  Future<List<String>> logs() async => List<String>.of(lines);

  @override
  Future<void> clearLogs() async {
    clearLogsCalls++;
    lines.clear();
  }

  @override
  Stream<LocalServiceEvent> get events => _events.stream;

  Future<void> dispose() => _events.close();
}
