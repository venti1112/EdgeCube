import '../connection/client.dart';
import 'models.dart';

/// 工作流任务接口：把 daemon 的 `task.*` 方法包成普通的 Dart 调用。
///
/// 这是**页面提交多步操作的统一入口** —— 「创建实例并下载服务端」与
/// 「下载并安装运行环境」都走 [submit]，不再由前端自己串好几步
/// （那样中途失败会留下一堆半成品，还得前端自己收拾）。
///
/// 错误都以 [DaemonException] 抛出，`code` 是稳定字符串
/// （`task_invalid_params` / `task_flow_not_found` / `task_not_found` / …），
/// UI 按 code 分支，不要匹配 message —— 见 [describeTaskError]。
class TaskApi {
  const TaskApi(this._client);

  final DaemonClient _client;

  /// 提交一个工作流任务，返回**刚提交时**的任务对象（通常已是 `running`，
  /// 并发额度满了则是 `queued`）。随后的进展靠 `task.state` /
  /// `task.progress` 事件，或 [get] 拉快照。
  ///
  /// 参数不合法会在这一调用里就被拒（`task_invalid_params`），**不会**拿到
  /// 任务 id —— 所以页面的「重试」不必先清理上一次的残局。
  Future<TaskView> submit(String flow, [Map<String, dynamic> params = const {}]) async {
    final result = await _client.callObject(
      'task.submit',
      params: {'flow': flow, 'params': params},
    );
    return _taskOf(result);
  }

  /// 按 id 拉一次任务快照。
  Future<TaskView> get(String id) async {
    final result = await _client.callObject('task.get', params: {'id': id});
    return TaskView.fromJson(result);
  }

  /// 全部任务（daemon 固定成最新提交在前）。
  Future<TaskList> list() async {
    final result = await _client.callObject('task.list');
    return TaskList.fromJson(result);
  }

  /// 取消任务（幂等；已终态的原样返回）。
  ///
  /// 注意 **取消不触发回滚**：已完成的那几步会留着（例如已经建好的实例
  /// 不会自动删掉），这与「失败必须收拾干净」是两种语义。
  Future<TaskView> cancel(String id) async {
    final result = await _client.callObject('task.cancel', params: {'id': id});
    return _taskOf(result);
  }

  /// 已注册的工作流清单。
  Future<List<FlowSummary>> flows() async {
    final result = await _client.callObject('task.flows');
    final flows = result['flows'];
    if (flows is! List) return const [];
    return flows
        .whereType<Map>()
        .map((flow) => FlowSummary.fromJson(flow.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// daemon 的 `task.*` 直接把任务对象平铺在 result 里（不是套一层 `task`）。
  static TaskView _taskOf(Map<String, dynamic> result) {
    if (result.containsKey('id')) return TaskView.fromJson(result);
    throw DaemonException('internal', '返回里缺少任务对象：$result');
  }
}

/// 把任务相关的异常翻成给用户看的一句话。
///
/// 认不出的码退回 message 本身 —— daemon 的 message 本来就是给人看的。
String describeTaskError(DaemonException error) => switch (error.code) {
  'task_invalid_params' || 'invalid_params' => error.message,
  'task_flow_not_found' => '这个功能需要更新守护进程（它不认识 `$kFlowHint` 这条工作流）',
  'task_not_found' => '这个任务已经不在了（守护进程可能重启过）',
  'task_engine_error' => '任务执行出错：${error.message}',
  'unavailable' => '任务系统没起来：${error.message}',
  _ => error.message,
};

/// 认不出工作流时提示用的一句话 —— 保持短，别把内部名字拼进去。
const String kFlowHint = '这条流程';

/// 步骤失败原因里带的**稳定错误码前缀**（`instance_name_taken：已存在…`）。
///
/// daemon 的步骤错误是字符串（szal 只认字符串），所以靠前缀保留「按码分支」
/// 的能力。认不出前缀就返回空串。
String stepErrorCode(String? error) {
  final text = error?.trim() ?? '';
  if (text.isEmpty) return '';
  final separator = text.indexOf('：');
  if (separator <= 0) return '';
  final head = text.substring(0, separator);
  // 错误码只由小写字母、数字与下划线组成；不是这个形状就别当码
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(head) ? head : '';
}

/// 去掉错误里的码前缀，只留给人看的那半句。
String stepErrorText(String? error) {
  final text = error?.trim() ?? '';
  if (text.isEmpty) return '未知错误';
  final code = stepErrorCode(text);
  if (code.isEmpty) return text;
  return text.substring(code.length + 1).trim();
}
