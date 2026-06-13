import 'dart:async';

import 'package:flutter/foundation.dart';

import 'server_service.dart';

/// 匹配 Minecraft 服务端日志中玩家加入/离开的正则（兼容英文与中文输出）。
///
/// 捕获组 1 均为玩家名：英文匹配 `Name[/ip] logged in` / `Name left the game`，
/// 中文匹配 Nukkit 等服务端的 `Name 加入了游戏` / `Name 退出了游戏`。
final _reJoin = RegExp(r'(\w{1,16})(?:\[/[\d.:]+\] logged in| 加入了游戏)');
final _reLeave = RegExp(r'(\w{1,16})(?: left the game| 退出了游戏)');
final _reListResp = RegExp(r'online(?:\s*:\s*|\s+)(.*)');


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

  /// 解析指定实例是否启用兼容模式。兼容模式下，原生上报的「启动中」会被直接
  /// 视为「运行中」，从而跳过「启动中」标签。由外层（main）注入，读取实例配置。
  bool Function(String instanceId)? compatModeResolver;

  /// 日志环形缓冲上限，超出丢弃最旧的行。
  static const int _maxLogLines = 5000;

  ServerStatus _status = ServerStatus.stopped;
  String? _instanceId;
  String? _instanceName;
  int? _lastExitCode;
  final List<String> _log = [];
  final Set<String> _onlinePlayers = {};

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
  Set<String> get onlinePlayers => Set.unmodifiable(_onlinePlayers);

  /// 是否正有某个“其它”实例在运行（用于禁用对当前实例的启动）。
  bool isOtherRunning(String instanceId) =>
      _status != ServerStatus.stopped && _instanceId != instanceId;

  /// 当前实例是否就是正在运行/启动中的那个。
  bool isActive(String instanceId) => _instanceId == instanceId;

  /// 启动服务端。[runtime] 为 `'java'` 或 `'php'`：
  /// Java 版 [jvmArgs] 如 `['-Xmx1024M']`、[programArgs] 如 `['-jar','server.jar','nogui']`；
  /// PHP 版 [jvmArgs] 为空、[programArgs] 即 `['PocketMine-MP.phar']`。
  Future<void> start({
    required String instanceId,
    required String instanceName,
    required String workingDir,
    required String version,
    required String runtime,
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
        runtime: runtime,
        jvmArgs: jvmArgs,
        programArgs: programArgs,
      );
      // 兜底：若 state 事件尚未把状态推进到 starting/running。
      // 兼容模式下跳过「启动中」，直接视为「运行中」。
      if (_status == ServerStatus.preparing) {
        _status = _compatFor(instanceId)
            ? ServerStatus.running
            : ServerStatus.starting;
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

  /// 发送一行控制台命令（启动中、运行中、停止中均有效，便于排查异常）。
  Future<void> sendCommand(String line) async {
    final cmd = line.trim();
    if (cmd.isEmpty) return;
    if (_status != ServerStatus.starting &&
        _status != ServerStatus.running &&
        _status != ServerStatus.stopping) {
      return;
    }
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

  /// 当前设备架构下可用的 PHP 运行时（不支持的架构返回空）。
  Future<List<String>> availablePhpRuntimes() => _service.availablePhpRuntimes();

  void _onEvent(ServerEvent event) {
    switch (event) {
      case ServerLogEvent(:final line):
        _appendLine(line);
        _parsePlayerEvent(line);
        notifyListeners();
      case ServerStateEvent(
          :final status,
          :final instanceId,
          :final instanceName,
          :final exitCode
        ):
        if (status != null) {
          // 界面重建后，从原生回放中恢复当前正在运行的实例。
          if (instanceId != null) _instanceId = instanceId;
          if (instanceName != null) _instanceName = instanceName;
          // 兼容模式下「启动中」直接当作「运行中」，跳过「启动中」标签；
          // 应用被回收后重连时的状态回放同样适用。
          final compat = _compatFor(_instanceId);
          // 进程存活，根据 status 字符串映射到对应状态。
          _status = switch (status) {
            'preparing' => ServerStatus.preparing,
            'starting'  => compat ? ServerStatus.running : ServerStatus.starting,
            'running'   => ServerStatus.running,
            _           => compat ? ServerStatus.running : ServerStatus.starting,
          };
        } else {
          _status = ServerStatus.stopped;
          _lastExitCode = exitCode;
          _onlinePlayers.clear();
          // exitCode 为空表示这是回放的“当前无运行”状态，并非真正退出，不打日志。
          if (exitCode != null) {
            _appendLine('[EdgeCube] 服务端已退出（退出码 $exitCode）');
          }
        }
        notifyListeners();
    }
  }

  /// 解析日志中的玩家加入/离开/list 响应，维护在线玩家集合。
  void _parsePlayerEvent(String line) {
    final joinMatch = _reJoin.firstMatch(line);
    if (joinMatch != null) {
      _onlinePlayers.add(joinMatch.group(1)!);
      return;
    }
    final leaveMatch = _reLeave.firstMatch(line);
    if (leaveMatch != null) {
      _onlinePlayers.remove(leaveMatch.group(1)!);
      return;
    }
    // 解析 list 命令响应：There are X of Y players online: name1, name2
    final listMatch = _reListResp.firstMatch(line);
    if (listMatch != null) {
      final names = listMatch.group(1)!.trim();
      if (names.isNotEmpty) {
        _onlinePlayers
          ..clear()
          ..addAll(names.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
      } else {
        _onlinePlayers.clear();
      }
    }
  }

  /// 指定实例是否启用兼容模式（未注入解析器或实例为空时返回 false）。
  bool _compatFor(String? instanceId) =>
      instanceId != null && (compatModeResolver?.call(instanceId) ?? false);

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
