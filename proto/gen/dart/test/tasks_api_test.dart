import 'package:test/test.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';


/// tests for TasksApi
void main() {
  final instance = EdgecubeApiClient().getTasksApi();

  group(TasksApi, () {
    // 取消任务
    //
    // queued 任务直接移除;running 任务置取消标志,由执行体尽快中断。 已结束(succeeded/failed/cancelled)任务不可取消,返回 409。 取消结果回显最终 Task(status=cancelled)。 
    //
    //Future<Task> cancelTask(String jobId) async
    test('test cancelTask', () async {
      // TODO
    });

    // 查询单个任务
    //
    // 返回任务详情;下载类任务运行时 progress 携带实时进度 (已下载/总大小/速度/预计剩余时间)。 
    //
    //Future<Task> getTask(String jobId) async
    test('test getTask', () async {
      // TODO
    });

    // 任务列表(进行中优先 + 最近完成)
    //
    // 进行中(queued/running)任务在前,其余按创建时间倒序。 可选按 instanceId / status 过滤。 
    //
    //Future<TaskList> listTasks({ String instanceId, TaskStatus status, int page, int pageSize }) async
    test('test listTasks', () async {
      // TODO
    });

  });
}
