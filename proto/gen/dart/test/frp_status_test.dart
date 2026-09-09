import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for FrpStatus
void main() {
  final instance = FrpStatusBuilder();
  // TODO add properties to the builder and call build()

  group(FrpStatus, () {
    // bool running
    test('to test the property `running`', () async {
      // TODO
    });

    // 运行中的隧道(未运行时缺省)
    // String tunnelId
    test('to test the property `tunnelId`', () async {
      // TODO
    });

    // 本次启动时间(未运行时缺省)
    // DateTime startedAt
    test('to test the property `startedAt`', () async {
      // TODO
    });

    // 未运行时的上次退出码(无记录时缺省)
    // int exitCode
    test('to test the property `exitCode`', () async {
      // TODO
    });

  });
}
