import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for LocalLoginRequest
void main() {
  final instance = LocalLoginRequestBuilder();
  // TODO add properties to the builder and call build()

  group(LocalLoginRequest, () {
    // String challenge
    test('to test the property `challenge`', () async {
      // TODO
    });

    // lowercase(hex(HMAC-SHA256(localKey, challenge))),localKey 为 daemon 数据目录内 local.key 内容
    // String signature
    test('to test the property `signature`', () async {
      // TODO
    });

    // String deviceName
    test('to test the property `deviceName`', () async {
      // TODO
    });

  });
}
