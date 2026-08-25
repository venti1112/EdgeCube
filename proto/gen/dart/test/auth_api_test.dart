import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for AuthApi
void main() {
  final instance = EdgecubeApiClient().getAuthApi();

  group(AuthApi, () {
    // 修改密码
    //
    //Future changePassword(ChangePasswordRequest changePasswordRequest) async
    test('test changePassword', () async {
      // TODO
    });

    // 修改用户名
    //
    // 需提供当前密码进行二次验证。
    //
    //Future changeUsername(ChangeUsernameRequest changeUsernameRequest) async
    test('test changeUsername', () async {
      // TODO
    });

    // 已登录设备列表
    //
    //Future<BuiltList<DeviceInfo>> listDevices() async
    test('test listDevices', () async {
      // TODO
    });

    // 用户名密码登录,换取长期 token
    //
    // 使用用户名和密码登录。daemon 首次启动时生成随机凭证并打印到控制台; 未登录设备无需鉴权即可访问本端点(仅局域网可绑定)。 
    //
    //Future<LoginResponse> login(LoginRequest loginRequest) async
    test('test login', () async {
      // TODO
    });

    // 吊销指定设备的 token
    //
    //Future revokeDevice(String deviceId) async
    test('test revokeDevice', () async {
      // TODO
    });

  });
}
