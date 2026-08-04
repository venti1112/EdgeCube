import 'frp_models.dart';
import 'frp_provider.dart';
import 'frp_token_store.dart';
import 'chmlfrp_api.dart';
import 'mefrp_api.dart';
import 'msl_frp_api.dart';
import 'openfrp_api.dart';
import 'sakura_frp_api.dart';

/// 把「已保存隧道」变成可交给上游 frpc 运行的配置文本。
///
/// 策略（方案A）：
///  - MSL Frp / ChmlFrp / ME Frp / SakuraFrp：API 直接返回成品配置
///    （toml / ini / text），原样使用；
///  - OpenFrp：官方客户端闭源，用节点地址 + frpc 用户 token + 隧道端口拼
///    标准 TOML（`user` + `auth.token`，代理名为 `user.name` 由 frps 端
///    补全）；
///  - custom：用户保存的 TOML 原样使用。
///
/// 统一追加 `log.to = "console"`，确保日志进原生侧的 stdout 读取线程。
class FrpConfigBuilder {
  FrpConfigBuilder._();

  /// 生成配置文本。抛 [FrpApiException] 表示 API 失败（含登录过期）。
  static Future<String> build(SavedFrpTunnel tunnel) async {
    switch (tunnel.provider) {
      case FrpProvider.custom:
        if (tunnel.customToml.isEmpty) {
          throw const FrpApiException('自定义配置为空');
        }
        return _ensureConsoleLog(tunnel.customToml);
      case FrpProvider.mslFrp:
        final token = await _requireToken(FrpProvider.mslFrp);
        return _ensureConsoleLog(
          await MslFrpApi.tunnelConfig(token, tunnel.remoteTunnelId),
        );
      case FrpProvider.chmlFrp:
        final token = await _requireToken(FrpProvider.chmlFrp);
        return _ensureConsoleLog(
          await ChmlFrpApi.tunnelConfig(
            token,
            node: tunnel.nodeName.isNotEmpty ? tunnel.nodeName : tunnel.nodeId,
            tunnelName: tunnel.name,
          ),
        );
      case FrpProvider.openFrp:
        return _buildOpenFrp(tunnel);
      case FrpProvider.meFrp:
        return _buildMeFrp(tunnel);
      case FrpProvider.sakuraFrp:
        return _buildSakuraFrp(tunnel);
    }
  }

  static Future<String> _requireToken(FrpProvider provider) async {
    final token = await FrpTokenStore.readToken(provider);
    if (token == null || token.isEmpty) {
      throw const FrpApiException('未登录，请先在供应商页面登录');
    }
    return token;
  }

  /// OpenFrp：getUserInfo.data.token 为 frpc 用户 token；节点地址从节点
  /// 列表按 nodeId 取 hostname。官方已确认兼容原版 frpc + token 认证。
  static Future<String> _buildOpenFrp(SavedFrpTunnel tunnel) async {
    final authToken = await _requireToken(FrpProvider.openFrp);
    final account = await OpenFrpApi.userInfo(authToken);
    final userToken = account.frpToken;
    if (userToken == null || userToken.isEmpty) {
      throw const FrpApiException('获取 OpenFrp 用户 token 失败');
    }
    final nodes = await OpenFrpApi.nodeList(authToken);
    final node = _findNode(nodes, tunnel.nodeId);
    return _standardToml(
      serverAddr: node.hostname,
      serverPort: node.serverPort,
      user: account.username,
      authToken: userToken,
      tunnel: tunnel,
    );
  }

  /// ME Frp：直接拉取官方成品 TOML 配置（与官方前端启动流程一致）。
  /// 返回的配置已含 serverAddr / serverPort / user / auth.token / remotePort
  /// 等全部启动所需信息，无需再依赖 /auth/node/list 取节点地址。
  static Future<String> _buildMeFrp(SavedFrpTunnel tunnel) async {
    final token = await _requireToken(FrpProvider.meFrp);
    return _ensureConsoleLog(
      await MeFrpApi.tunnelConfig(token, tunnel.remoteTunnelId),
    );
  }

  /// SakuraFrp：直接拉取官方成品配置（`POST /tunnel/config`，v4 API），
  /// 返回可被上游 frpc 直接加载的 TOML。
  static Future<String> _buildSakuraFrp(SavedFrpTunnel tunnel) async {
    final token = await _requireToken(FrpProvider.sakuraFrp);
    if (tunnel.remoteTunnelId.isEmpty) {
      throw const FrpApiException('该隧道未关联远端隧道 ID，无法拉取配置');
    }
    return _ensureConsoleLog(
      await SakuraFrpApi.tunnelConfig(token, tunnel.remoteTunnelId),
    );
  }

  static FrpNode _findNode(List<FrpNode> nodes, String nodeId) {
    for (final n in nodes) {
      if (n.id == nodeId) {
        if (n.hostname.isEmpty) {
          throw FrpApiException('节点 ${n.name} 未提供连接地址');
        }
        return n;
      }
    }
    throw FrpApiException('节点不存在或已下线（id=$nodeId）');
  }

  /// 标准 frp v0.52+ TOML。
  static String _standardToml({
    required String serverAddr,
    required int serverPort,
    required String? user,
    required String authToken,
    required SavedFrpTunnel tunnel,
  }) {
    final buffer = StringBuffer()
      ..writeln('serverAddr = ${_q(serverAddr)}')
      ..writeln('serverPort = $serverPort');
    if (user != null && user.isNotEmpty) {
      buffer.writeln('user = ${_q(user)}');
    }
    buffer
      ..writeln('auth.token = ${_q(authToken)}')
      ..writeln('log.to = "console"')
      ..writeln('log.level = "info"')
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln('name = ${_q(tunnel.name)}')
      ..writeln('type = ${_q(tunnel.type)}')
      ..writeln('localIP = ${_q(tunnel.localIp)}')
      ..writeln('localPort = ${tunnel.localPort}');
    final remotePort = tunnel.remotePort;
    if (remotePort != null) {
      buffer.writeln('remotePort = $remotePort');
    }
    return buffer.toString();
  }

  /// 成品配置若未指定日志输出，补 `log.to = "console"`（toml 顶层）。
  /// ini 配置（ChmlFrp）由上游 frpc 的 ini 兼容层解析，原样返回。
  static String _ensureConsoleLog(String config) {
    final isIni = config.trimLeft().startsWith('[');
    if (isIni) return config;
    if (config.contains('log.to')) return config;
    // 顶层字段须在第一个 [[proxies]] 之前插入。
    final index = config.indexOf('[[');
    if (index < 0) return '$config\nlog.to = "console"\n';
    return '${config.substring(0, index)}log.to = "console"\n'
        '${config.substring(index)}';
  }

  static String _q(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
