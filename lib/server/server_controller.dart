import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'server_properties.dart';
import 'server_service.dart';
import 'upnp_service.dart';
import '../tunnel/tunnel_service.dart';

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
  ServerController({ServerService? service, UpnpService? upnp, TunnelService? tunnel})
      : _service = service ?? ServerService(),
        _upnp = upnp ?? UpnpService(),
        _tunnel = tunnel ?? TunnelService() {
    _sub = _service.events().listen(_onEvent);
  }

  final ServerService _service;
  final UpnpService _upnp;
  final TunnelService _tunnel;
  late final StreamSubscription<ServerEvent> _sub;

  /// 解析指定实例是否启用兼容模式。兼容模式下，原生上报的「启动中」会被直接
  /// 视为「运行中」，从而跳过「启动中」标签。由外层（main）注入，读取实例配置。
  bool Function(String instanceId)? compatModeResolver;

  /// 解析当前是否启用了 UPnP 端口映射。由外层（main）注入，读取 SharedPreferences。
  Future<bool> Function()? upnpEnabledResolver;

  /// 解析当前是否启用了 FRP 隧道。由外层（main）注入，读取 SharedPreferences。
  Future<bool> Function()? tunnelEnabledResolver;

  /// 日志环形缓冲上限，超出丢弃最旧的行。
  static const int _maxLogLines = 5000;

  ServerStatus _status = ServerStatus.stopped;
  String? _instanceId;
  String? _instanceName;
  String? _workingDir;
  int? _lastExitCode;
  final List<String> _log = [];
  final Set<String> _onlinePlayers = {};

  // —— UPnP / FRP 即时状态标志 ——
  bool _upnpActive = false;
  bool _tunnelActive = false;
  bool _restartingTunnel = false;

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
    _workingDir = workingDir;
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
        if (_status == ServerStatus.running) {
          _triggerUpnp();
          _triggerTunnel();
        }
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
          // 服务端进入运行态后触发 UPnP 端口映射和 FRP 隧道。
          if (_status == ServerStatus.running) {
            if (!_upnpActive) _triggerUpnp();
            if (!_tunnelActive) _triggerTunnel();
          }
        } else {
          _status = ServerStatus.stopped;
          _lastExitCode = exitCode;
          _onlinePlayers.clear();
          if (_upnpActive) _stopUpnp();
          if (_tunnelActive && !_restartingTunnel) _stopTunnel();
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

  /// 触发 UPnP 端口映射（服务端进入运行态时调用）。
  void _triggerUpnp() {
    final resolver = upnpEnabledResolver;
    if (resolver == null) return;
    resolver().then((enabled) {
      if (enabled) _startUpnp();
    });
  }

  /// 启动 UPnP 端口映射。
  void _startUpnp() {
    final dir = _workingDir;
    if (dir == null || _upnpActive) return;
    _upnpActive = true;
    _upnp.openPort(dir).then((port) {
      if (port != null) {
        _appendLine('[EdgeCube] 路由器端口映射成功：$port');
        notifyListeners();
      }
    });
  }

  /// 解除 UPnP 端口映射。
  void _stopUpnp() {
    if (!_upnpActive) return;
    _upnpActive = false;
    _upnp.closePort().then((_) {
      // 静默处理，不影响主流程。
    });
  }

  /// 启动 FRP 隧道（服务端进入运行态时调用）。
  void _triggerTunnel() {
    final resolver = tunnelEnabledResolver;
    if (resolver == null) return;
    resolver().then((enabled) {
      if (enabled) _startTunnelWithConfig(null);
    });
  }

  /// 使用指定配置启动 FRP 隧道（config 为 null 时从 SharedPreferences 读取）。
  void _startTunnelWithConfig(FrpcConfig? config) {
    final dir = _workingDir;
    if (dir == null || _tunnelActive) return;
    _tunnelActive = true;
    _doStartTunnel(config, dir);
  }

  Future<void> _doStartTunnel(FrpcConfig? config, String dir) async {
    try {
      FrpcConfig finalConfig;
      if (config != null) {
        finalConfig = config;
      } else {
        // 从 SharedPreferences 读取（服务器启动时的路径）。
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('frpc_config');
        if (raw == null) {
          _appendLine('[EdgeCube] FRP 隧道未配置，跳过启动');
          _tunnelActive = false;
          return;
        }
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final serverAddr = m['serverAddr'] as String? ?? '';
        if (serverAddr.isEmpty) {
          _appendLine('[EdgeCube] FRP 服务器地址未填写，跳过启动');
          _tunnelActive = false;
          return;
        }
        finalConfig = FrpcConfig(
          serverAddr: serverAddr,
          serverPort: (m['serverPort'] as int?) ?? 7000,
          authToken: m['authToken'] as String?,
          proxyName: (m['proxyName'] as String?) ?? 'minecraft',
          proxyType: (m['proxyType'] as String?) ?? 'tcp',
          localPort: 25565,
          remotePort: (m['remotePort'] as int?) ?? 25565,
        );
      }
      // 注入实际 localPort。
      int localPort = finalConfig.localPort;
      final propsFile = File(p.join(dir, 'server.properties'));
      if (await propsFile.exists()) {
        final props = ServerProperties.parse(await propsFile.readAsString());
        localPort = props.getInt('server-port') ?? 25565;
      }
      finalConfig = finalConfig.copyWith(localPort: localPort);
      if (_status != ServerStatus.running) {
        _tunnelActive = false;
        return;
      }
      final path = await _tunnel.writeConfig(finalConfig);
      await _tunnel.start(configPath: path, name: finalConfig.proxyName);
      _appendLine('[EdgeCube] FRP 隧道已启动（本地端口 $localPort）');
      notifyListeners();
    } catch (e) {
      _appendLine('[EdgeCube] FRP 隧道启动失败：$e');
      _tunnelActive = false;
    }
  }

  /// 停止 FRP 隧道。
  void _stopTunnel() {
    if (!_tunnelActive) return;
    _tunnelActive = false;
    _tunnel.stop().then((_) {
      // 静默处理，不影响主流程。
    });
  }

  // —— 即时生效公共接口 ——

  /// 立即启用 UPnP（用户在 UI 中打开开关时调用）。
  void enableUpnpNow() {
    if (_upnpActive || _status != ServerStatus.running) return;
    _startUpnp();
  }

  /// 立即停用 UPnP（用户在 UI 中关闭开关时调用）。
  void disableUpnpNow() {
    if (!_upnpActive) return;
    _stopUpnp();
  }

  /// 立即启用 FRP 隧道（用户在 UI 中打开开关时调用）。
  /// [config] 可选，传入当前 UI 配置；为 null 时从 SharedPreferences 读取。
  void enableTunnelNow([FrpcConfig? config]) {
    if (_tunnelActive || _status != ServerStatus.running) return;
    _startTunnelWithConfig(config);
  }

  /// 立即停用 FRP 隧道（用户在 UI 中关闭开关时调用）。
  void disableTunnelNow() {
    if (!_tunnelActive) return;
    _stopTunnel();
  }

  /// 以指定配置重启 FRP 隧道（用户在运行中修改配置后调用）。
  Future<void> applyTunnelConfig(FrpcConfig config) async {
    if (!_tunnelActive || _status != ServerStatus.running) return;
    _restartingTunnel = true;
    await _tunnel.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    if (_status == ServerStatus.running && _workingDir != null) {
      _doStartTunnel(config, _workingDir!);
    }
    _restartingTunnel = false;
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
