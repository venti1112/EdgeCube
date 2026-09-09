import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for ModsApi
void main() {
  final instance = EdgecubeApiClient().getModsApi();

  group(ModsApi, () {
    // 游戏版本列表(筛选数据源,代理)
    //
    //Future<BuiltList<String>> modrinthGameVersions() async
    test('test modrinthGameVersions', () async {
      // TODO
    });

    // 项目版本列表(代理)
    //
    //Future<BuiltList<ModrinthVersion>> modrinthProjectVersions(String projectId, { String gameVersion, String loader }) async
    test('test modrinthProjectVersions', () async {
      // TODO
    });

    // 批量项目信息(图标/标题,代理)
    //
    //Future<BuiltList<ModrinthProject>> modrinthProjects(BuiltList<String> ids) async
    test('test modrinthProjects', () async {
      // TODO
    });

    // Modrinth 搜索(代理)
    //
    //Future<ModrinthSearchResponse> modrinthSearch(String query, { int offset, int limit, String gameVersion, String loader, String sort, String projectType }) async
    test('test modrinthSearch', () async {
      // TODO
    });

    // 按 SHA1 查版本(更新检查,代理)
    //
    //Future<BuiltMap<String, ModrinthVersion>> modrinthVersionFiles(ModrinthVersionFilesRequest modrinthVersionFilesRequest) async
    test('test modrinthVersionFiles', () async {
      // TODO
    });

    // Poggit 全量发布列表(带缓存,代理)
    //
    //Future<BuiltList<PoggitPlugin>> poggitPlugins() async
    test('test poggitPlugins', () async {
      // TODO
    });

  });
}
