import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for JobAccepted
void main() {
  final instance = JobAcceptedBuilder();
  // TODO add properties to the builder and call build()

  group(JobAccepted, () {
    // 异步任务 id(= Task.id;状态/进度经 WS `task/progress` 推送,可用 GET /tasks/{jobId} 查询)
    // String jobId
    test('to test the property `jobId`', () async {
      // TODO
    });

  });
}
