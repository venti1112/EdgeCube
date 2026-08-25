import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for RuntimesApi
void main() {
  final instance = EdgecubeApiClient().getRuntimesApi();

  group(RuntimesApi, () {
    // 卸载运行时
    //
    //Future deleteRuntime(String runtimeId) async
    test('test deleteRuntime', () async {
      // TODO
    });

    // 可安装版本清单(官方源)
    //
    // 拉取对应官方渠道的可用版本(java: Adoptium API;php: 权威预编译源;frpc: GitHub Releases)。
    //
    //Future<RuntimeCatalog> getRuntimeCatalog(RuntimeType type) async
    test('test getRuntimeCatalog', () async {
      // TODO
    });

    // 安装运行时(官方源下载,进度走 WS download/progress)
    //
    //Future<JobAccepted> installRuntime(RuntimeInstallRequest runtimeInstallRequest) async
    test('test installRuntime', () async {
      // TODO
    });

    // 已安装运行时列表
    //
    //Future<BuiltList<RuntimeInfo>> listRuntimes() async
    test('test listRuntimes', () async {
      // TODO
    });

  });
}
