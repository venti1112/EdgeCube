import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for RunStatus
void main() {
  final instance = RunStatusBuilder();
  // TODO add properties to the builder and call build()

  group(RunStatus, () {
    // InstanceStatus status
    test('to test the property `status`', () async {
      // TODO
    });

    // 真实游戏进程 PID(PTY 握手获得)
    // int pid
    test('to test the property `pid`', () async {
      // TODO
    });

    // 上次退出码
    // int exitCode
    test('to test the property `exitCode`', () async {
      // TODO
    });

    // int serverPort
    test('to test the property `serverPort`', () async {
      // TODO
    });

    // bool onlineMode
    test('to test the property `onlineMode`', () async {
      // TODO
    });

    // 当前在线玩家名
    // BuiltList<String> onlinePlayers
    test('to test the property `onlinePlayers`', () async {
      // TODO
    });

    // 当前日志行序号(供 /log?since= 续拉)
    // int logSeq
    test('to test the property `logSeq`', () async {
      // TODO
    });

  });
}
