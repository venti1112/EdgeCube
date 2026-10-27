import '../connection/client.dart';
import 'models.dart';

/// 路由器端口映射（UPnP）的 RPC 接口。
///
/// 只有两个方法，且**都只是读**：
///
/// * `status` —— 缓存快照，不联网（进页面就调它）；
/// * `probe` —— 立即重新发现网关（「重新探测」按钮），失败会落进
///   `gateway.error` 而不是抛异常。
///
/// 映射本身的增删**没有单独的方法**：开关与参数在实例设置里（`instance.update`
/// 的 `upnp_*` 字段），daemon 跟着实例的启停自动加 / 撤。
class UpnpApi {
  const UpnpApi(this._client);

  final DaemonClient _client;

  /// 状态总览（网关 + 每实例映射行），读 daemon 的缓存，不联网。
  Future<UpnpStatus> status() async =>
      UpnpStatus.fromJson(await _client.callObject('upnp.status'));

  /// 重新探测网关并重试失败的映射；返回探测后的最新总览。
  ///
  /// 网络环境差时可能等上几秒（发现超时）。
  Future<UpnpStatus> probe() async =>
      UpnpStatus.fromJson(await _client.callObject('upnp.probe'));
}
