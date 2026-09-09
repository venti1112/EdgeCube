import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ServerCoreUpdateRequest
void main() {
  final instance = ServerCoreUpdateRequestBuilder();
  // TODO add properties to the builder and call build()

  group(ServerCoreUpdateRequest, () {
    // 目标核心 jar 下载地址(通常来自 GET core-update/check 的 downloadUrl)
    // String downloadUrl
    test('to test the property `downloadUrl`', () async {
      // TODO
    });

    // 下载校验值(sha256 hex 或 \"sha1:<hex>\";为空不做校验)
    // String sha256
    test('to test the property `sha256`', () async {
      // TODO
    });

    // 落盘文件名替换(缺省为检测到的当前核心 jar 名,如 server.jar)
    // String fileName
    test('to test the property `fileName`', () async {
      // TODO
    });

  });
}
