import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/mcp_store.dart';
import '../instance/instance_controller.dart';
import '../server/server_controller.dart';
import '../server/system_monitor_controller.dart';
import '../shell/shell_service.dart';
import 'mcp_service.dart';
import 'mcp_tools.dart';

/// MCP 服务的全局生命周期与配置管理器。
///
/// 持有 MCP 运行状态与配置，负责启动/停止 MCP 服务，并把应用的各控制器
/// （[ServerController]/[InstanceController]/[SystemMonitorController]）注入到
/// 工具实现中，使 AI Agent 能读取数据与操作服务。
///
/// 由 [main] 创建。与 FTP（在原生侧运行、可跨进程查询状态）不同，MCP 运行于
/// Dart isolate 内、无原生持久化，故 [init] 时若上次为开启状态会主动重新启动。
class McpController extends ChangeNotifier {
  McpController({
    required this.serverController,
    required this.instanceController,
    required this.systemMonitorController,
    McpService? service,
  }) : _service = service ?? McpService();

  final ServerController serverController;
  final InstanceController instanceController;
  final SystemMonitorController systemMonitorController;
  final McpService _service;

  /// 一次性 shell 命令执行（供 MCP shell 工具），与交互终端互不影响。
  final ShellService _shell = ShellService();

  /// MCP shell 工具的会话状态（持久 cwd），供 shell_cd/run_shell 跨调用共享。
  final McpShellSession _shellSession = McpShellSession();

  McpConfig _config = const McpConfig();
  bool _running = false;
  String? _lastError;

  /// 当前 MCP 配置。
  McpConfig get config => _config;

  /// MCP 服务是否正在监听。
  bool get isRunning => _running;

  /// 最近一次启动失败的错误信息（成功后清空）。
  String? get lastError => _lastError;

  /// 初始化：加载持久化配置；若无令牌则生成一个；若上次为开启状态则自动恢复监听。
  Future<void> init() async {
    _config = await McpStore.load();
    if (_config.token.isEmpty) {
      _config = _config.copyWith(token: McpStore.generateToken());
      await McpStore.save(_config);
    }
    if (_config.enabled) {
      await _startInternal();
    }
    notifyListeners();
  }

  /// 开启/关闭 MCP 服务。
  Future<void> setEnabled(bool value) async {
    if (value == _running) return;
    if (value) {
      await _startInternal();
      // 启动失败时不持久化为开启，避免下次启动反复失败。
      if (!_running) {
        notifyListeners();
        return;
      }
    } else {
      await _stopInternal();
    }
    _config = _config.copyWith(enabled: value);
    await McpStore.save(_config);
    notifyListeners();
  }

  /// 应用新配置。若 MCP 正在运行则以新配置重启。
  Future<void> applyConfig(McpConfig config) async {
    final wasRunning = _running;
    if (wasRunning) {
      await _stopInternal();
    }
    _config = config;
    await McpStore.save(_config);
    if (wasRunning) {
      await _startInternal();
    }
    notifyListeners();
  }

  /// 重新生成访问令牌。运行中会以新令牌重启服务。
  Future<void> regenerateToken() async {
    await applyConfig(_config.copyWith(token: McpStore.generateToken()));
  }

  Future<void> _startInternal() async {
    try {
      await _service.start(
        port: _config.port,
        token: _config.token,
        serverFactory: (sessionId) => buildMcpServer(
          server: serverController,
          instances: instanceController,
          monitor: systemMonitorController,
          shell: _shell,
          shellSession: _shellSession,
          allowControl: _config.allowControl,
          allowShell: _config.allowShell,
        ),
      );
      _running = true;
      _lastError = null;
    } catch (e) {
      _running = false;
      _lastError = '$e';
    }
  }

  Future<void> _stopInternal() async {
    await _service.stop();
    _running = false;
  }

  @override
  void dispose() {
    // 退出时尽力关闭监听，释放端口。
    unawaited(_service.stop());
    super.dispose();
  }
}
