import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for UploadInitRequest
void main() {
  final instance = UploadInitRequestBuilder();
  // TODO add properties to the builder and call build()

  group(UploadInitRequest, () {
    // String instanceId
    test('to test the property `instanceId`', () async {
      // TODO
    });

    // 目标目录(相对实例 cwd)
    // String path
    test('to test the property `path`', () async {
      // TODO
    });

    // String fileName
    test('to test the property `fileName`', () async {
      // TODO
    });

    // int sizeBytes
    test('to test the property `sizeBytes`', () async {
      // TODO
    });

    // 可选,complete 时校验
    // String sha256
    test('to test the property `sha256`', () async {
      // TODO
    });

    // 完成自动解压(服务端整合包场景)
    // bool autoExtract (default value: false)
    test('to test the property `autoExtract`', () async {
      // TODO
    });

  });
}
