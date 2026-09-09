import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for LoginRequest
void main() {
  final instance = LoginRequestBuilder();
  // TODO add properties to the builder and call build()

  group(LoginRequest, () {
    // String username
    test('to test the property `username`', () async {
      // TODO
    });

    // String password
    test('to test the property `password`', () async {
      // TODO
    });

    // 客户端持久化的设备标识(uuid)。存在该设备记录时复用并轮换 token, 不会产生新设备;缺省时新建设备记录。 
    // String deviceId
    test('to test the property `deviceId`', () async {
      // TODO
    });

    // 设备显示名(如 \"我的手机\" / \"办公室电脑\")
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
