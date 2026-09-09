import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for ServerDownloadInfo
void main() {
  final instance = ServerDownloadInfoBuilder();
  // TODO add properties to the builder and call build()

  group(ServerDownloadInfo, () {
    // 服务端直链(http/https)
    // String url
    test('to test the property `url`', () async {
      // TODO
    });

    // 建议落盘文件名(写入实例工作目录;创建实例时可经 InstanceConfig.fileName 覆盖)
    // String fileName
    test('to test the property `fileName`', () async {
      // TODO
    });

    // 校验值,\"sha1:<hex>\" 或 \"sha256:<hex>\"(daemon 下载完成后强校验, 与 InstanceConfig.checksum 同构;无校验值的源返回 null) 
    // String checksum
    test('to test the property `checksum`', () async {
      // TODO
    });

    // 可选,源不提供时为 null
    // int sizeBytes
    test('to test the property `sizeBytes`', () async {
      // TODO
    });

  });
}
