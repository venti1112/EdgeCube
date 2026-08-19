import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for ConfigApi
void main() {
  final instance = EdgecubeApiClient().getConfigApi();

  group(ConfigApi, () {
    // 读取设置项
    //
    //Future<ConfigEntry> getConfigEntry(String key) async
    test('test getConfigEntry', () async {
      // TODO
    });

    // 写入设置项
    //
    //Future<ConfigEntry> updateConfigEntry(String key, ConfigEntry configEntry) async
    test('test updateConfigEntry', () async {
      // TODO
    });

  });
}
