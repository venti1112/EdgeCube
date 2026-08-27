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

    // 发起本机免密登录挑战(一次性,短时效)
    //
    // 直连 daemon 的本机客户端免密登录: 返回一次性 challenge(5 分钟过期,使用后作废),客户端读取数据目录 `local.key`, 计算 `signature = lowercase(hex(HMAC-SHA256(localKey, challenge)))` 后提交 `/auth/local-login`。未登录设备无需鉴权(同 /auth/login)。 
    //
    //Future<LocalLoginChallenge> issueLocalLoginChallenge() async
    test('test issueLocalLoginChallenge', () async {
      // TODO
    });

    // 已登录设备列表
    //
    //Future<BuiltList<DeviceInfo>> listDevices() async
    test('test listDevices', () async {
      // TODO
    });

    // 本机免密登录,换取长期 token
    //
    // 提交 /auth/local-login/challenge 返回的 challenge 及对应 HMAC 签名。 签名验证通过即视为本机进程(持有 local.key),签发与 /auth/login 相同的长期 token。 challenge 一次性使用,重放返回 401。 
    //
    //Future<LoginResponse> localLogin(LocalLoginRequest localLoginRequest) async
    test('test localLogin', () async {
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
