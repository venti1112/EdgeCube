import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for AuthApi
void main() {
  final instance = EdgecubeApiClient().getAuthApi();

  group(AuthApi, () {
    // 获取当前配对码
    //
    // 返回当前生效的 6 位配对码。配对码用于本地/局域网设备换取 token; 未配对设备无需鉴权即可访问本端点(仅局域网可绑定)。 
    //
    //Future<PairingCode> getPairingCode() async
    test('test getPairingCode', () async {
      // TODO
    });

    // 已配对设备列表
    //
    //Future<BuiltList<DeviceInfo>> listDevices() async
    test('test listDevices', () async {
      // TODO
    });

    // 对码配对,换取长期 token
    //
    //Future<PairResponse> pairDevice(PairRequest pairRequest) async
    test('test pairDevice', () async {
      // TODO
    });

    // 吊销指定设备的 token
    //
    //Future revokeDevice(String deviceId) async
    test('test revokeDevice', () async {
      // TODO
    });

    // 轮换配对码
    //
    // 使当前配对码失效并生成新码。
    //
    //Future<PairingCode> rotatePairingCode() async
    test('test rotatePairingCode', () async {
      // TODO
    });

  });
}
