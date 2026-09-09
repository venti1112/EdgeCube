import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for PlayersApi
void main() {
  final instance = EdgecubeApiClient().getPlayersApi();

  group(PlayersApi, () {
    // 获取玩家管理聚合快照(在线玩家 + 白名单/封禁/IP封禁/OP 名单)
    //
    // 返回当前实例的在线玩家名与四类名单快照,以及实例运行状态 (前端据此决定仅运行时才允许的增删操作)。 
    //
    //Future<PlayerSnapshot> getInstancePlayers(String instanceId) async
    test('test getInstancePlayers', () async {
      // TODO
    });

  });
}
