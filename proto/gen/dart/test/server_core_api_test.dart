import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for ServerCoreApi
void main() {
  final instance = EdgecubeApiClient().getServerCoreApi();

  group(ServerCoreApi, () {
    // 检查服务端核心是否有新版本(Paper 系)
    //
    // daemon 代理 PaperMC 官方 API:对 java 实例按其启动命令中的核心 jar (server.jar/paper-*.jar 等)与版本目录推导当前服务端,若为 Paper 系 (Paper/Purpur/Spigot/CraftBukkit 由版本目录识别,识别不了按最新版判断) 则返回最新版本/构建/下载地址与当前版本对比结果。非 java 实例或不支持 更新来源时返回 `source: unknown / supported: false`。 
    //
    //Future<ServerCoreUpdateCheck> checkServerCoreUpdate(String instanceId) async
    test('test checkServerCoreUpdate', () async {
      // TODO
    });

    // 更新服务端核心(jar 替换,Paper 系)
    //
    // 按检查结果下载最新核心 jar 并替换现有 jar(旧 jar 重命名为 `.disabled`)。 实例必须处于 Stopped;任务进度经 GET /tasks/{jobId} 轮询,完成后 GET /instances/{instanceId}/core-update/check 的 currentVersion 即更新。 
    //
    //Future<JobAccepted> updateServerCore(String instanceId, ServerCoreUpdateRequest serverCoreUpdateRequest) async
    test('test updateServerCore', () async {
      // TODO
    });

  });
}
