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

    // 同 LoginRequest.deviceId,复用已有设备记录
    // String deviceId
    test('to test the property `deviceId`', () async {
      // TODO
    });

    // String deviceName
    test('to test the property `deviceName`', () async {
      // TODO
    });

    // DeviceType deviceType
    test('to test the property `deviceType`', () async {
      // TODO
    });

  });
}
