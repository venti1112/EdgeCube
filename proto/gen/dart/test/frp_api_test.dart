import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for FrpApi
void main() {
  final instance = EdgecubeApiClient().getFrpApi();

  group(FrpApi, () {
    // 创建隧道
    //
    //Future<TunnelInfo> createFrpTunnel(TunnelInput tunnelInput) async
    test('test createFrpTunnel', () async {
      // TODO
    });

    // 删除隧道
    //
    //Future deleteFrpTunnel(String tunnelId) async
    test('test deleteFrpTunnel', () async {
      // TODO
    });

    // frpc 日志(最近 tail 行)
    //
    //Future<BuiltList<String>> getFrpLogs({ int tail }) async
    test('test getFrpLogs', () async {
      // TODO
    });

    // frpc 运行状态
    //
    //Future<FrpStatus> getFrpStatus() async
    test('test getFrpStatus', () async {
      // TODO
    });

    // 隧道详情
    //
    //Future<TunnelInfo> getFrpTunnel(String tunnelId) async
    test('test getFrpTunnel', () async {
      // TODO
    });

    // 隧道列表
    //
    // 隧道列表(不含运行状态,运行状态见 GET /frp/status)
    //
    //Future<BuiltList<TunnelInfo>> listFrpTunnels() async
    test('test listFrpTunnels', () async {
      // TODO
    });

    // 启动 frpc(全局唯一)
    //
    // 渲染指定隧道的 TOML 并启动全局唯一的 frpc 进程;已有 frpc 运行 → 409 frpc_busy;未安装 frpc 运行时 → 409 frpc_runtime_missing。 
    //
    //Future startFrpc(StartFrpcRequest startFrpcRequest) async
    test('test startFrpc', () async {
      // TODO
    });

    // 停止 frpc
    //
    //Future stopFrpc() async
    test('test stopFrpc', () async {
      // TODO
    });

    // 更新隧道(全量替换)
    //
    //Future<TunnelInfo> updateFrpTunnel(String tunnelId, TunnelInput tunnelInput) async
    test('test updateFrpTunnel', () async {
      // TODO
    });

  });
}
