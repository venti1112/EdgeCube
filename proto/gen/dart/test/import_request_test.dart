import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ImportRequest
void main() {
  final instance = ImportRequestBuilder();
  // TODO add properties to the builder and call build()

  group(ImportRequest, () {
    // 归档所在实例 id(先经 /fs/upload-* 上传到该实例 cwd)
    // String sourceInstanceId
    test('to test the property `sourceInstanceId`', () async {
      // TODO
    });

    // 导出归档在其 cwd 内的相对路径(先经 /fs/upload-* 上传)
    // String archivePath
    test('to test the property `archivePath`', () async {
      // TODO
    });

  });
}
