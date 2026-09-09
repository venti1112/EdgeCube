import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for FsWriteRequest
void main() {
  final instance = FsWriteRequestBuilder();
  // TODO add properties to the builder and call build()

  group(FsWriteRequest, () {
    // String instanceId
    test('to test the property `instanceId`', () async {
      // TODO
    });

    // 目标文件路径(相对实例 cwd),父目录须已存在
    // String path
    test('to test the property `path`', () async {
      // TODO
    });

    // UTF-8 文本内容(上限 16 MiB)
    // String content
    test('to test the property `content`', () async {
      // TODO
    });

  });
}
