import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ServerTypeInfo
void main() {
  final instance = ServerTypeInfoBuilder();
  // TODO add properties to the builder and call build()

  group(ServerTypeInfo, () {
    // 类型 id,如 vanilla / paper / spigot / craftbukkit / purpur / leaf / leaves / velocity / bungeecord / fabric / pocketmine / powernukkitx / allay
    // String type
    test('to test the property `type`', () async {
      // TODO
    });

    // String category
    test('to test the property `category`', () async {
      // TODO
    });

    // true 时版本页选择 MC 版本后需经 /catalog/loaders 选加载器版本(目前仅 fabric)
    // bool hasLoader (default value: false)
    test('to test the property `hasLoader`', () async {
      // TODO
    });

    // 该类型默认落盘文件名(如 server.jar / bungeecord.jar / PocketMine-MP.phar);下载信息可覆盖
    // String fileName
    test('to test the property `fileName`', () async {
      // TODO
    });

  });
}
