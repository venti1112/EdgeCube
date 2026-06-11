import 'dart:async';

import 'package:flutter/foundation.dart';

import 'server_service.dart';

/// 服务端进程的运行状态。
///
/// - [stopped]：进程未运行。
/// - [preparing]：正在解压 JRE 运行时。
/// - [starting]：JVM 已启动，服务端正在初始化（尚未输出 Done）。
/// - [running]：服务端初始化完成，可接受玩家连接。
/// - [stopping]：已发送 stop 命令，等待进程退出。
enum ServerStatus { stopped, preparing, starting, running, stopping }

/// 管理服务端进程的运行状态与日志缓冲，并把 UI 操作转发到 [ServerService]。
///
/// 单活动进程模型：同一时刻只跟踪一个正在运行的服务端，[runningInstanceId]
/// 标识它属于哪个实例。日志为所有页面共享，故本控制器置于全局 Scope。
class ServerController extends ChangeNotifier {
  ServerController({ServerService? service})
      : _service = service ?? ServerService() {
    _sub = _service.events().listen(_onEvent);
  }

  final ServerService _service;
  late final StreamSubscription<ServerEvent> _sub;

  /// 日志环形缓冲上限，超出丢弃最旧的行。
  static const int _maxLogLines = 5000;

  ServerStatus _status = ServerStatus.stopped;
  String? _instanceId;
  String? _instanceName;
  int? _lastExitCode;
  final List<String> _log = [];

  ServerStatus get status => _status;
  bool get isRunning => _status == ServerStatus.running;
  bool get isBusy =>
      _status == ServerStatus.preparing ||
      _status == ServerStatus.starting ||
      _status == ServerStatus.stopping;
  String? get runningInstanceId => _instanceId;
  String? get runningInstanceName => _instanceName;
  int? get lastExitCode => _lastExitCode;
  List<String> get log => List.unmodifiable(_log);

  /// 是否正有某个“其它”实例在运行（用于禁用对当前实例的启动）。
  bool isOtherRunning(String instanceId) =>
      _status != ServerStatus.stopped && _instanceId != instanceId;

  /// 当前实例是否就是正在运行/启动中的那个。
  bool isActive(String instanceId) => _instanceId == instanceId;

  /// 启动服务端。[jvmArgs] 如 `['-Xmx1024M']`，[programArgs] 如 `['-jar','server.jar','nogui']`。
  Future<void> start({
    required String instanceId,
    required String instanceName,
    required String workingDir,
    required String version,
    required List<String> jvmArgs,
    required List<String> programArgs,
  }) async {
    if (_status != ServerStatus.stopped) return;
    _instanceId = instanceId;
    _instanceName = instanceName;
    _lastExitCode = null;
    _status = ServerStatus.preparing;
    _appendLine('[EdgeCube] 启动 $instanceName …');
    notifyListeners();
    try {
      await _service.start(
        instanceId: instanceId,
        instanceName: instanceName,
        workingDir: workingDir,
        version: version,
        jvmArgs: jvmArgs,
        programArgs: programArgs,
      );
      // 兜底：若 state 事件尚未把状态推进到 starting/running。
      if (_status == ServerStatus.preparing) {
        _status = ServerStatus.starting;
        notifyListeners();
      }
    } catch (e) {
      _appendLine('[EdgeCube] 启动失败：$e');
      _status = ServerStatus.stopped;
      _instanceId = null;
      _instanceName = null;
      notifyListeners();
    }
  }

  /// 优雅停止（向服务端发送 stop 命令）。
  Future<void> stop() async {
    if (_status != ServerStatus.running) return;
    _status = ServerStatus.stopping;
    _appendLine('[EdgeCube] 正在停止（已发送 stop 命令）…');
    notifyListeners();
    await _service.stop();
  }

  /// 强制结束进程。
  Future<void> forceStop() async {
    if (_status == ServerStatus.stopped) return;
    _appendLine('[EdgeCube] 强制结束进程…');
    await _service.forceStop();
  }

  /// 发送一行控制台命令（仅运行中有效）。
  Future<void> sendCommand(String line) async {
    final cmd = line.trim();
    if (cmd.isEmpty || _status != ServerStatus.running) return;
    _appendLine('> $cmd');
    notifyListeners();
    await _service.sendCommand(cmd);
  }

  void clearLog() {
    _log.clear();
    _service.clearLog();
    notifyListeners();
  }

  /// 当前设备架构下可用的 JRE 版本。
  Future<List<String>> availableVersions() => _service.availableVersions();

  void _onEvent(ServerEvent event) {
    switch (event) {
      case ServerLogEvent(:final line):
        _appendLine(line);
        notifyListeners();
      case ServerStateEvent(
          :final status,
          :final instanceId,
          :final instanceName,
          :final exitCode
        ):
        if (status != null) {
          // 进程存活，根据 status 字符串映射到对应状态。
          _status = switch (status) {
            'preparing' => ServerStatus.preparing,
            'starting'  => ServerStatus.starting,
            'running'   => ServerStatus.running,
            _           => ServerStatus.starting,
          };
          // 界面重建后，从原生回放中恢复当前正在运行的实例。
          if (instanceId != null) _instanceId = instanceId;
          if (instanceName != null) _instanceName = instanceName;
        } else {
          _status = ServerStatus.stopped;
          _lastExitCode = exitCode;
          // exitCode 为空表示这是回放的“当前无运行”状态，并非真正退出，不打日志。
          if (exitCode != null) {
            _appendLine('[EdgeCube] 服务端已退出（退出码 $exitCode）');
          }
        }
        notifyListeners();
    }
  }

  void _appendLine(String line) {
    _log.add(line);
    if (_log.length > _maxLogLines) {
      _log.removeRange(0, _log.length - _maxLogLines);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
