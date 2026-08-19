import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for SshApi
void main() {
  final instance = EdgecubeApiClient().getSshApi();

  group(SshApi, () {
    // SSH 服务状态与配置
    //
    //Future<SshStatus> getSshStatus() async
    test('test getSshStatus', () async {
      // TODO
    });

    // 更新 SSH 配置(启用/端口/账号/根目录)
    //
    //Future<SshStatus> updateSshConfig(SshConfig sshConfig) async
    test('test updateSshConfig', () async {
      // TODO
    });

  });
}
