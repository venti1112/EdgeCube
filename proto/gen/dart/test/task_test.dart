import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';

// tests for Task
void main() {
  final instance = TaskBuilder();
  // TODO add properties to the builder and call build()

  group(Task, () {
    // 任务 id(= JobAccepted.jobId)
    // String id
    test('to test the property `id`', () async {
      // TODO
    });

    // TaskKind kind
    test('to test the property `kind`', () async {
      // TODO
    });

    // 用户可读展示标题(如「模组名 v1.2」,download_single_file 等使用);无时为 null
    // String displayName
    test('to test the property `displayName`', () async {
      // TODO
    });

    // 关联实例;全局任务(下载运行时等)为 null
    // String instanceId
    test('to test the property `instanceId`', () async {
      // TODO
    });

    // TaskStatus status
    test('to test the property `status`', () async {
      // TODO
    });

    // 执行阶段描述(如 start 的 launching / 下载的 fetching);无阶段概念时为 null
    // String phase
    test('to test the property `phase`', () async {
      // TODO
    });

    // TaskProgress progress
    test('to test the property `progress`', () async {
      // TODO
    });

    // TaskError error
    test('to test the property `error`', () async {
      // TODO
    });

    // DateTime createdAt
    test('to test the property `createdAt`', () async {
      // TODO
    });

    // DateTime startedAt
    test('to test the property `startedAt`', () async {
      // TODO
    });

    // DateTime finishedAt
    test('to test the property `finishedAt`', () async {
      // TODO
    });

  });
}
