import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/network_store.dart';
import '../server/runtime_service.dart';
import '../server/server_controller.dart';
import '../tunnel/tunnel_service.dart';
import 'frp_config_builder.dart';
import 'frp_models.dart';
import 'frp_registry_store.dart';

/// 「映射隧道」功能的状态控制器：已保存隧道注册表 + 独立隧道运行状态。
///
/// 不直接持有 frpc 进程——进程唯一属主是 [ServerController]（frpc 全局
/// 单进程），本控制器通过 [ServerController.runStandaloneTunnel] /
/// [ServerController.stopStandaloneTunnel] 发起运行，通过
/// [TunnelService.events] 订阅状态。登录态由各页面按需读
/// FrpTokenStore，不在此缓存。
class FrpController extends ChangeNotifier {
  FrpController({required ServerController server, TunnelService? tunnel})
    // ignore: prefer_initializing_formals
    : _server = server,
      _tunnel = tunnel ?? TunnelService() {
    _sub = _tunnel.events().listen(_onTunnelEvent);
  }

  final ServerController _server;
  final TunnelService _tunnel;
  late final StreamSubscription<TunnelEvent> _sub;

  List<SavedFrpTunnel> _tunnels = [];
  bool _loaded = false;

  /// 正在运行的隧道 localId（进程退出后清空）。
  String? _runningLocalId;

  /// 正在启动（拼配置 / 拉进程）中的隧道 localId。
  String? _startingLocalId;

  /// frpc 是否已真正连上 frps（"login to server success"）。
  bool _connected = false;

  List<SavedFrpTunnel> get tunnels => List.unmodifiable(_tunnels);
  String? get runningLocalId => _runningLocalId;
  String? get startingLocalId => _startingLocalId;
  bool get isConnected => _connected;

  /// frpc 进程被服务端自动隧道占用时为 true（映射隧道页应提示互斥）。
  bool get occupiedByAutoTunnel =>
      _server.isTunnelActive && !_server.isStandaloneTunnel;

  /// 随服务端自动运行的默认隧道 localId；非自动隧道运行时为 null。
  String? get autoRunningLocalId =>
      occupiedByAutoTunnel ? _server.autoTunnelSourceId : null;

  /// 自动隧道是否已真正连上 frps。
  bool get autoConnected => occupiedByAutoTunnel && _server.isTunnelRunning;

  /// 加载注册表（首次进入页面时调用）。
  Future<void> init() async {
    if (_loaded) return;
    await reload();
    _loaded = true;
  }

  Future<void> reload() async {
    _tunnels = await FrpRegistryStore.load();
    notifyListeners();
  }

  Future<void> saveTunnel(SavedFrpTunnel tunnel) async {
    await FrpRegistryStore.upsert(tunnel);
    await reload();
  }

  Future<void> removeTunnel(String localId) async {
    if (_runningLocalId == localId) stop();
    // 删除的是默认隧道时清除设置，避免悬空引用。
    if (await NetworkStore.loadDefaultFrpTunnelId() == localId) {
      await NetworkStore.saveDefaultFrpTunnelId(null);
    }
    await FrpRegistryStore.remove(localId);
    await reload();
  }

  /// 启动指定隧道：生成配置 → 写入独立配置文件 → 交给 ServerController。
  ///
  /// 抛出：[FrpApiException]（API/登录失败）、[StateError]（frpc 进程被
  /// 占用，message 为 'auto-active'/'standalone-active'）、其它原生异常。
  Future<void> run(SavedFrpTunnel tunnel) async {
    if (_startingLocalId != null) return;
    _startingLocalId = tunnel.localId;
    notifyListeners();
    try {
      final config = await FrpConfigBuilder.build(tunnel);
      // 每条隧道独立的 TOML（config/frp/toml/<localId>.toml），
      // 启动时直接把该路径传给 frpc，不再复制到 files 目录。
      final file = await FrpRegistryStore.writeToml(tunnel.localId, config);
      final runtimeId = await NetworkStore.loadFrpcRuntimeId();
      final runtimes = await const RuntimeService().installedFrpcRuntimes();
      if (runtimes.isEmpty) {
        throw const FrpApiException('frpc-runtime-missing');
      }
      final validRuntimeId = runtimes.any((r) => r.id == runtimeId)
          ? runtimeId
          : runtimes.first.id;
      await _server.runStandaloneTunnel(
        configPath: file.path,
        name: tunnel.name,
        runtimeId: validRuntimeId,
      );
      _runningLocalId = tunnel.localId;
    } finally {
      _startingLocalId = null;
      notifyListeners();
    }
  }

  /// 停止当前独立隧道。
  void stop() {
    _server.stopStandaloneTunnel();
    _runningLocalId = null;
    _connected = false;
    notifyListeners();
  }

  /// 停止随服务端自动运行的默认隧道（运行页开关对自动隧道关闭时调用）。
  void stopAutoTunnel() {
    _server.disableTunnelNow();
  }

  void _onTunnelEvent(TunnelEvent event) {
    if (event is! TunnelStateEvent) return;
    if (event.status == 'running') {
      if (_runningLocalId != null && !_connected) {
        _connected = true;
      }
      // 自动隧道（默认隧道）状态也经由本控制器透出，一律通知。
      notifyListeners();
      return;
    }
    if (event.status == null && event.exitCode != null) {
      // 进程退出（无论何种原因），复位运行状态。
      _runningLocalId = null;
      _connected = false;
      notifyListeners();
      return;
    }
    // preparing / starting 等中间状态：通知以刷新自动隧道运行标识。
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
