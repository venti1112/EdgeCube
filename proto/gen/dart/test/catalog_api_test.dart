import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for CatalogApi
void main() {
  final instance = EdgecubeApiClient().getCatalogApi();

  group(CatalogApi, () {
    // 服务端下载信息(直链 + 校验值 + 落盘文件名)
    //
    // 按选择组装修订下载信息(URL、可选校验值、建议文件名)。 - 简单类型:type + version - hasLoader 类型(如 fabric):type + mcVersion + loaderVersion,   组装 meta.fabricmc.net 的 server/jar 直链 - bungeecord:只传 type,取最新构建直链 校验值格式 \"sha1:<hex>\" 或 \"sha256:<hex>\",与创建实例时 InstanceConfig.checksum 同构(daemon 下载完成后强校验)。 
    //
    //Future<ServerDownloadInfo> getCatalogDownloadInfo(String type, { String version, String mcVersion, String loaderVersion }) async
    test('test getCatalogDownloadInfo', () async {
      // TODO
    });

    // 加载器版本列表(hasLoader 类型独有)
    //
    // 返回指定 Minecraft 版本的可用加载器版本(降序)。 目前仅 fabric 为 hasLoader 类型,数据源 meta.fabricmc.net。 
    //
    //Future<BuiltList<String>> listCatalogLoaders(String type, String mcVersion) async
    test('test listCatalogLoaders', () async {
      // TODO
    });

    // 版本列表(按服务端类型)
    //
    // 返回该类型可选版本号(降序,最新在前)。 - hasLoader 类型(如 fabric):本体无独立版本 → 返回 Minecraft 版本列表,   加载器版本由 /catalog/loaders 另行查询 - bungeecord:无版本概念,返回空数组 - pocketmine / powernukkitx:版本号附带对应客户端/mcbe 版本,见   ServerVersion 的 meta 字段(可选) 
    //
    //Future<BuiltList<ServerVersion>> listCatalogVersions(String type) async
    test('test listCatalogVersions', () async {
      // TODO
    });

    // 可用服务端类型列表(分类/是否带加载器/默认文件名)
    //
    // 静态定义(编译期),随 daemon 发布版本演进。结构: - 分类:vanilla / plugin / mod / proxy / bedrock(与 V1 分类树一致) - type:原版/插件/代理/基岩端直接用;'bungeecord' 无版本选择,直接下载最新构建 - hasLoader:true 时(todo: fabric)需走 /catalog/loaders 选择加载器版本 - fileName:该类型服务端默认落盘文件名(可被 /catalog/download-info 结果覆盖) 
    //
    //Future<BuiltList<ServerTypeInfo>> listServerTypes() async
    test('test listServerTypes', () async {
      // TODO
    });

  });
}
