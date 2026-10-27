import '../connection/client.dart';
import 'models.dart';

/// 映射隧道的 RPC 接口：把 daemon 的 `frp.*` 方法包成普通的 Dart 调用。
///
/// **登录不在这里**：发起授权（`frp.login.start`）、轮询、把令牌写进
/// `auth.json` 全在 daemon 侧跑；本层只是「发一次 RPC / 读一次状态」。
/// 授权进度靠订阅 `frp.login` 事件（见 `providers.dart` 的 `kFrpLoginTopic`）。
///
/// 一切错误都以 [DaemonException] 抛出，`code` 是稳定字符串
/// （`frp_api_error` / `frp_unauthorized` / `frp_network_error` / …），
/// UI 按 code 分支（`models.dart` 的 [describeFrpError] / [isFrpTokenInvalid]），
/// 不要匹配 message。
class FrpApi {
  const FrpApi(this._client);

  final DaemonClient _client;

  /// 平台清单（含登录方式）。
  Future<List<FrpProvider>> providers() async {
    final raw = await _client.callObject('frp.providers');
    return _list(raw['providers'], FrpProvider.fromJson);
  }

  /// 某平台的登录态。`verify` 为真时 daemon 会联网复核令牌
  /// （失败会顺手清掉本地令牌，返回未登录）。
  Future<FrpAccountStatus> account(
    String provider, {
    bool verify = false,
  }) async {
    final raw = await _client.callObject(
      'frp.account',
      params: {'provider': provider, if (verify) 'verify': true},
    );
    return FrpAccountStatus.fromJson(raw);
  }

  /// 发起浏览器授权：返回授权地址（daemon 已经开始轮询）。
  Future<FrpLoginSession> loginStart(String provider) async {
    final raw = await _client.callObject(
      'frp.login.start',
      params: {'provider': provider},
    );
    return FrpLoginSession.fromJson(raw);
  }

  /// 当前授权进度（重新进页面时用它接上正在跑的会话）。
  Future<FrpLoginSession> loginStatus(String provider) async {
    final raw = await _client.callObject(
      'frp.login.status',
      params: {'provider': provider},
    );
    return FrpLoginSession.fromJson(raw);
  }

  /// 取消授权（daemon 停掉轮询并作废会话）。
  Future<void> loginCancel(String provider) =>
      _client.callObject('frp.login.cancel', params: {'provider': provider});

  /// 用粘贴的访问令牌登录（Sakura / ME Frp）。
  Future<FrpAccount> loginWithToken(String provider, String token) async {
    final raw = await _client.callObject(
      'frp.login.token',
      params: {'provider': provider, 'token': token},
    );
    final account = raw['account'];
    if (account is! Map) {
      throw DaemonException('internal', '登录返回里缺少 account 字段：$raw');
    }
    return FrpAccount.fromJson(account.cast<String, dynamic>());
  }

  /// 退出登录（清本地令牌）。
  Future<void> logout(String provider) =>
      _client.callObject('frp.logout', params: {'provider': provider});

  /// 平台侧隧道列表。
  Future<List<FrpRemoteTunnel>> remoteTunnels(String provider) async {
    final raw = await _client.callObject(
      'frp.remote.tunnels',
      params: {'provider': provider},
    );
    return _list(raw['tunnels'], FrpRemoteTunnel.fromJson);
  }

  /// 平台侧节点列表。
  Future<List<FrpNode>> remoteNodes(String provider) async {
    final raw = await _client.callObject(
      'frp.remote.nodes',
      params: {'provider': provider},
    );
    return _list(raw['nodes'], FrpNode.fromJson);
  }

  /// 在平台上创建隧道。节点由 daemon 按 [nodeId] 从平台列表里取，
  /// 前端只发表单字段。
  ///
  /// 两个端口留空就发 `null`（缺省）：校验在 daemon 侧统一做，
  /// 不通过时回的是「请完整填写隧道名称与端口」。
  Future<void> createRemoteTunnel({
    required String provider,
    required String nodeId,
    required String name,
    required String type,
    required String localIp,
    int? localPort,
    int? remotePort,
  }) => _client.callObject(
    'frp.remote.create',
    params: {
      'provider': provider,
      'node_id': nodeId,
      'name': name,
      'type': type,
      'local_ip': localIp,
      'local_port': ?localPort,
      'remote_port': ?remotePort,
    },
  );

  /// 删除平台上的隧道。
  Future<void> deleteRemoteTunnel(String provider, String remoteTunnelId) =>
      _client.callObject(
        'frp.remote.delete',
        params: {'provider': provider, 'remote_tunnel_id': remoteTunnelId},
      );

  /// 本地已保存的隧道。
  Future<List<FrpSavedTunnel>> tunnels() async {
    final raw = await _client.callObject('frp.tunnels.list');
    return _list(raw['tunnels'], FrpSavedTunnel.fromJson);
  }

  /// 保存 / 更新一条隧道（新建时 daemon 生成 localId）。
  ///
  /// 自定义隧道保存时 daemon 会顺手把 TOML 写盘，生成失败只在
  /// [FrpTunnelSaveResult.configError] 里带一句原因，不影响保存本身。
  Future<FrpTunnelSaveResult> saveTunnel(FrpTunnelInput input) async {
    final raw = await _client.callObject(
      'frp.tunnels.save',
      params: input.json,
    );
    return FrpTunnelSaveResult.fromJson(raw);
  }

  /// 生成 / 读取某条隧道的 frpc 配置。
  ///
  /// [refresh] 为真时强制重新生成（平台侧改动过隧道后用）。
  Future<FrpTunnelConfig> tunnelConfig(
    String localId, {
    bool refresh = false,
  }) async {
    final raw = await _client.callObject(
      'frp.tunnels.config',
      params: {'local_id': localId, if (refresh) 'refresh': true},
    );
    return FrpTunnelConfig.fromJson(raw);
  }

  /// 删除本地隧道（元数据 + 生成的配置一并删）。
  Future<void> removeTunnel(String localId) =>
      _client.callObject('frp.tunnels.remove', params: {'local_id': localId});

  // ── FRP 实例的运行（一条隧道配置 = 一个可独立运行的实例）──

  /// 能拿来跑隧道的 frpc 运行环境 + 当前生效的那个。
  Future<FrpcRuntimeList> runtimes() async {
    final raw = await _client.callObject('frp.runtimes');
    return FrpcRuntimeList.fromJson(raw);
  }

  /// 记下跑隧道用哪个 frpc 运行环境（`null` / 空 = 回到「用第一个装好的」）。
  Future<void> saveFrpcRuntime(String? runtimeId) async {
    await _client.callObject(
      'frp.settings.save',
      params: {'frpc_runtime_id': runtimeId},
    );
  }

  /// 所有 FRP 实例的运行态（**不含日志** —— 列表页只需要状态）。
  Future<List<FrpRun>> runs() async {
    final raw = await _client.callObject('frp.run.list');
    return _list(raw['runs'], FrpRun.fromJson);
  }

  /// 单条隧道（一个 FRP 实例）的运行态，**含日志**（运行页用）。
  /// 还没有任何记录时返回 `null`。
  Future<FrpRun?> run(String localId) async {
    final raw = await _client.callObject(
      'frp.run.get',
      params: {'local_id': localId},
    );
    final run = raw['run'];
    return run is Map ? FrpRun.fromJson(run.cast<String, dynamic>()) : null;
  }

  /// 启动一条隧道。**已经在跑就是幂等的**（daemon 那边回现状，不会起第二个）。
  Future<void> startRun(String localId) =>
      _client.callObject('frp.run.start', params: {'local_id': localId});

  /// 停一条隧道（幂等）。
  Future<void> stopRun(String localId) =>
      _client.callObject('frp.run.stop', params: {'local_id': localId});

  /// 清空某条隧道的运行日志。
  Future<void> clearRunLog(String localId) =>
      _client.callObject('frp.run.clear_log', params: {'local_id': localId});

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) parse(item.cast<String, dynamic>()),
    ];
  }
}
