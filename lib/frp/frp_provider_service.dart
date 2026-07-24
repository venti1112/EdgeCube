import 'frp_models.dart';
import 'frp_provider.dart';
import 'frp_token_store.dart';
import 'chmlfrp_api.dart';
import 'mefrp_api.dart';
import 'msl_frp_api.dart';
import 'openfrp_api.dart';
import 'sakura_frp_api.dart';

/// 供应商无关的统一门面：登录 / 用户信息 / 节点 / 隧道增删查。
///
/// UI 页面只依赖本类 + 模型，不直接接触各家 API 客户端。
class FrpProviderService {
  FrpProviderService._();

  /// 密码登录（仅 supportsPasswordLogin 的供应商），返回登录 token。
  static Future<String> loginWithPassword(
    FrpProvider provider,
    String account,
    String password, {
    String? twoFactorCode,
  }) {
    switch (provider) {
      case FrpProvider.meFrp:
        return MeFrpApi.login(account, password);
      default:
        throw const FrpApiException('该供应商仅支持 Token 登录');
    }
  }

  /// 发起浏览器授权登录（仅 supportsBrowserLogin 的供应商）。
  /// 返回授权页 URL 与轮询所需的会话状态。
  static Future<FrpBrowserLoginSession> createBrowserLogin(
    FrpProvider provider,
  ) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.createAppLogin();
      case FrpProvider.openFrp:
        return OpenFrpApi.createBrowserLogin();
      default:
        throw const FrpApiException('该供应商不支持浏览器登录');
    }
  }

  /// 轮询浏览器授权结果；未完成返回 null，完成返回登录 token。
  static Future<String?> pollBrowserLogin(
    FrpProvider provider,
    FrpBrowserLoginSession session,
  ) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.pollAppLogin(session);
      case FrpProvider.openFrp:
        return OpenFrpApi.pollBrowserLogin(session);
      default:
        throw const FrpApiException('该供应商不支持浏览器登录');
    }
  }

  /// 验证 token 并获取账号信息（token 无效抛 [FrpApiException]）。
  static Future<FrpAccount> userInfo(FrpProvider provider, String token) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.userInfo(token);
      case FrpProvider.openFrp:
        return OpenFrpApi.userInfo(token);
      case FrpProvider.sakuraFrp:
        return SakuraFrpApi.userInfo(token);
      case FrpProvider.chmlFrp:
        return ChmlFrpApi.userInfo(token);
      case FrpProvider.meFrp:
        return MeFrpApi.userInfo(token);
      case FrpProvider.custom:
        throw const FrpApiException('custom 无账号体系');
    }
  }

  /// 节点列表。
  static Future<List<FrpNode>> nodeList(FrpProvider provider, String token) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.nodeList(token);
      case FrpProvider.openFrp:
        return OpenFrpApi.nodeList(token);
      case FrpProvider.sakuraFrp:
        return _sakuraNodes(token);
      case FrpProvider.chmlFrp:
        return ChmlFrpApi.nodeList();
      case FrpProvider.meFrp:
        return MeFrpApi.nodeList(token);
      case FrpProvider.custom:
        throw const FrpApiException('custom 无节点列表');
    }
  }

  static Future<List<FrpNode>> _sakuraNodes(String token) async {
    final level = await SakuraFrpApi.userLevel(token);
    return SakuraFrpApi.nodeList(token, userLevel: level);
  }

  /// 远端隧道列表。
  static Future<List<FrpRemoteTunnel>> tunnelList(
    FrpProvider provider,
    String token,
  ) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.tunnelList(token);
      case FrpProvider.openFrp:
        return OpenFrpApi.proxyList(token);
      case FrpProvider.sakuraFrp:
        return SakuraFrpApi.tunnelList(token);
      case FrpProvider.chmlFrp:
        return ChmlFrpApi.tunnelList(token);
      case FrpProvider.meFrp:
        return MeFrpApi.proxyList(token);
      case FrpProvider.custom:
        throw const FrpApiException('custom 无远端隧道');
    }
  }

  /// 创建隧道。
  static Future<void> createTunnel(
    FrpProvider provider,
    String token, {
    required FrpNode node,
    required String name,
    required String type,
    required String localIp,
    required int localPort,
    required int remotePort,
  }) {
    final nodeIdInt = int.tryParse(node.id) ?? 0;
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.addTunnel(
          token,
          nodeId: nodeIdInt,
          name: name,
          type: type,
          localIp: localIp,
          localPort: localPort,
          remotePort: remotePort,
        );
      case FrpProvider.openFrp:
        return OpenFrpApi.newProxy(
          token,
          nodeId: nodeIdInt,
          name: name,
          type: type,
          localIp: localIp,
          localPort: localPort,
          remotePort: remotePort,
        );
      case FrpProvider.sakuraFrp:
        return SakuraFrpApi.createTunnel(
          token,
          node: nodeIdInt,
          name: name,
          type: type,
          localIp: localIp,
          localPort: localPort,
          remotePort: remotePort,
        );
      case FrpProvider.chmlFrp:
        return ChmlFrpApi.createTunnel(
          token,
          node: node.name,
          name: name,
          type: type,
          localIp: localIp,
          localPort: localPort,
          remotePort: remotePort,
        );
      case FrpProvider.meFrp:
        return MeFrpApi.createProxy(
          token,
          nodeId: nodeIdInt,
          name: name,
          type: type,
          localIp: localIp,
          localPort: localPort,
          remotePort: remotePort,
        );
      case FrpProvider.custom:
        throw const FrpApiException('custom 无远端创建');
    }
  }

  /// 删除远端隧道。
  static Future<void> deleteTunnel(
    FrpProvider provider,
    String token,
    String tunnelId,
  ) {
    switch (provider) {
      case FrpProvider.mslFrp:
        return MslFrpApi.deleteTunnel(token, tunnelId);
      case FrpProvider.openFrp:
        return OpenFrpApi.removeProxy(token, tunnelId);
      case FrpProvider.sakuraFrp:
        return SakuraFrpApi.deleteTunnel(token, tunnelId);
      case FrpProvider.chmlFrp:
        return ChmlFrpApi.deleteTunnel(token, tunnelId);
      case FrpProvider.meFrp:
        return MeFrpApi.deleteProxy(token, tunnelId);
      case FrpProvider.custom:
        throw const FrpApiException('custom 无远端删除');
    }
  }

  /// 读取已保存的登录 token；无则返回 null。
  static Future<String?> savedToken(FrpProvider provider) =>
      FrpTokenStore.readToken(provider);

  /// 保存登录 token。
  static Future<void> saveToken(FrpProvider provider, String token) =>
      FrpTokenStore.saveToken(provider, token);

  /// 退出登录（清除 token）。
  static Future<void> logout(FrpProvider provider) =>
      FrpTokenStore.deleteToken(provider);
}
