import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for FtpApi
void main() {
  final instance = EdgecubeApiClient().getFtpApi();

  group(FtpApi, () {
    // FTP 服务状态与配置
    //
    //Future<FtpStatus> getFtpStatus() async
    test('test getFtpStatus', () async {
      // TODO
    });

    // 更新 FTP 配置(启用/端口/账号/根目录)
    //
    //Future<FtpStatus> updateFtpConfig(FtpConfig ftpConfig) async
    test('test updateFtpConfig', () async {
      // TODO
    });

  });
}
