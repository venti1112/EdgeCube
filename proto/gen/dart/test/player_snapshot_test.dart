import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for PlayerSnapshot
void main() {
  final instance = PlayerSnapshotBuilder();
  // TODO add properties to the builder and call build()

  group(PlayerSnapshot, () {
    // InstanceStatus instanceStatus
    test('to test the property `instanceStatus`', () async {
      // TODO
    });

    // 在线玩家名(daemon 解析控制台输出维护,按名排序)
    // BuiltList<String> online
    test('to test the property `online`', () async {
      // TODO
    });

    // BuiltList<PlayerNamedEntry> whitelist
    test('to test the property `whitelist`', () async {
      // TODO
    });

    // BuiltList<PlayerNamedEntry> ops
    test('to test the property `ops`', () async {
      // TODO
    });

    // BuiltList<PlayerBanEntry> bans
    test('to test the property `bans`', () async {
      // TODO
    });

    // BuiltList<PlayerIpBanEntry> banIps
    test('to test the property `banIps`', () async {
      // TODO
    });

  });
}
