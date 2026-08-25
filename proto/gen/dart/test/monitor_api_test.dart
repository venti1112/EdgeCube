import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for MonitorApi
void main() {
  final instance = EdgecubeApiClient().getMonitorApi();

  group(MonitorApi, () {
    // 系统监控快照(实时曲线走 WS monitor/stats)
    //
    //Future<MonitorSnapshot> getMonitorSnapshot() async
    test('test getMonitorSnapshot', () async {
      // TODO
    });

  });
}
