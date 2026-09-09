import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ModMetadataEntry
void main() {
  final instance = ModMetadataEntryBuilder();
  // TODO add properties to the builder and call build()

  group(ModMetadataEntry, () {
    // 相对实例 cwd 的路径
    // String path
    test('to test the property `path`', () async {
      // TODO
    });

    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // int sizeBytes
    test('to test the property `sizeBytes`', () async {
      // TODO
    });

    // 文件 SHA1(小写 hex),供更新检查(Modrinth version_files)与图标查询
    // String sha1
    test('to test the property `sha1`', () async {
      // TODO
    });

    // 图标 URL(后端经 Modrinth 查询,尽力而为;失败/不可得为 null)
    // String iconUrl
    test('to test the property `iconUrl`', () async {
      // TODO
    });

    // 未识别/未解析时为 null
    // ModMetadata metadata
    test('to test the property `metadata`', () async {
      // TODO
    });

  });
}
