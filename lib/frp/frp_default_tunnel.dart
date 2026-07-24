import '../config/network_store.dart';
import '../server/server_controller.dart';
import 'frp_config_builder.dart';
import 'frp_registry_store.dart';

/// 默认映射隧道解析：把 `defaultFrpTunnelId` 指向的已保存隧道变成可直接
/// 交给 frpc 的配置文件，供 [ServerController.defaultTunnelResolver] 在
/// 服务端启动时调用（frp 模块不反向依赖服务端模块的启动流程）。
class FrpDefaultTunnel {
  FrpDefaultTunnel._();

  /// 解析默认隧道并生成配置文件。
  ///
  /// 未设置默认隧道或条目已被删除时返回 null（调用方提示后跳过启动）；
  /// 配置生成失败（供应商 API 出错、未登录等）抛 [FrpApiException] 等异常。
  static Future<ResolvedDefaultTunnel?> resolve() async {
    final id = await NetworkStore.loadDefaultFrpTunnelId();
    if (id == null) return null;
    final tunnels = await FrpRegistryStore.load();
    for (final tunnel in tunnels) {
      if (tunnel.localId != id) continue;
      final config = await FrpConfigBuilder.build(tunnel);
      final file = await FrpRegistryStore.writeToml(id, config);
      return ResolvedDefaultTunnel(
        configPath: file.path,
        name: tunnel.name,
        sourceId: id,
      );
    }
    return null;
  }
}
