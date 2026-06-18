import '../tunnel/tunnel_service.dart';
import 'config_store.dart';

/// 网络映射配置（UPnP 开关、FRP 隧道开关与 frpc 配置）的本地持久化。
///
/// 全部存于 `config/network.json`，取代旧版散落在 SharedPreferences 中的
/// `upnp_enabled` / `tunnel_enabled` / `frpc_config` 三个键。
class NetworkStore {
  NetworkStore._();

  static const String _fileName = 'network.json';
  static const String _upnpKey = 'upnpEnabled';
  static const String _tunnelKey = 'tunnelEnabled';
  static const String _frpcKey = 'frpc';

  static Future<bool> loadUpnpEnabled() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_upnpKey] as bool? ?? false;
  }

  static Future<void> saveUpnpEnabled(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_upnpKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  static Future<bool> loadTunnelEnabled() async {
    final m = await ConfigStore.readConfig(_fileName);
    return m[_tunnelKey] as bool? ?? false;
  }

  static Future<void> saveTunnelEnabled(bool value) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_tunnelKey] = value;
    await ConfigStore.writeConfig(_fileName, m);
  }

  /// 读取已保存的 frpc 配置；未保存过返回 null。
  static Future<FrpcConfig?> loadFrpc() async {
    final m = await ConfigStore.readConfig(_fileName);
    final frpc = m[_frpcKey];
    if (frpc is! Map<String, dynamic>) return null;
    return FrpcConfig.fromJsonMap(frpc);
  }

  static Future<void> saveFrpc(FrpcConfig config) async {
    final m = await ConfigStore.readConfig(_fileName);
    m[_frpcKey] = config.toJsonMap();
    await ConfigStore.writeConfig(_fileName, m);
  }
}
