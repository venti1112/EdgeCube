import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for HealthApi
void main() {
  final instance = EdgecubeApiClient().getHealthApi();

  group(HealthApi, () {
    // 健康检查(未配对可访问)
    //
    //Future<HealthResponse> getHealth() async
    test('test getHealth', () async {
      // TODO
    });

  });
}
