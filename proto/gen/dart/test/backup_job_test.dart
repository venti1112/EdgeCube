import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for BackupJob
void main() {
  final instance = BackupJobBuilder();
  // TODO add properties to the builder and call build()

  group(BackupJob, () {
    // String id
    test('to test the property `id`', () async {
      // TODO
    });

    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // 备份哪个实例
    // String instanceId
    test('to test the property `instanceId`', () async {
      // TODO
    });

    // 定时表达式(如 \"0 4 * * *\");null 为仅手动
    // String scheduleCron
    test('to test the property `scheduleCron`', () async {
      // TODO
    });

    // 备份目标;空为仅本地
    // BuiltList<String> targetIds
    test('to test the property `targetIds`', () async {
      // TODO
    });

    // bool enabled (default value: true)
    test('to test the property `enabled`', () async {
      // TODO
    });

    // 保留最近 N 份
    // int maxKeep (default value: 10)
    test('to test the property `maxKeep`', () async {
      // TODO
    });

    // 相对 cwd 的附加目录;空为整个工作目录
    // BuiltList<String> includeDirs
    test('to test the property `includeDirs`', () async {
      // TODO
    });

    // DateTime lastRunAt
    test('to test the property `lastRunAt`', () async {
      // TODO
    });

    // String lastResult
    test('to test the property `lastResult`', () async {
      // TODO
    });

  });
}
