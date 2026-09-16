import '../connection/client.dart';
import 'models.dart';

/// 实例管理接口：把 daemon 的 `instance.*` 方法包成普通的 Dart 调用。
///
/// 一切错误都以 [`DaemonException`] 抛出，`code` 是稳定字符串
/// （`instance_name_taken` / `instance_not_found` / `invalid_params` / …），
/// UI 按 code 分支，不要匹配 message。
class InstanceApi {
  const InstanceApi(this._client);

  final DaemonClient _client;

  /// 实例列表。
  Future<InstanceList> list({bool withStatus = false}) async {
    final result = await _client.callObject(
      'instance.list',
      params: {if (withStatus) 'with_status': true},
    );
    return InstanceList.fromJson(result);
  }

  /// 单个实例的完整元数据。
  Future<Instance> get(String id) async {
    final result = await _client.callObject('instance.get', params: {'id': id});
    return Instance.fromJson(_objectField(result, 'instance'));
  }

  /// 单个实例的状态（磁盘视角）。
  Future<InstanceStatus> status(String id) async {
    final result = await _client.callObject(
      'instance.status',
      params: {'id': id},
    );
    return InstanceStatus.fromJson(_objectField(result, 'status'));
  }

  /// 新建实例。id 由 daemon 生成。
  Future<Instance> create({
    required String name,
    String runtime = kRuntimeJava,
    int? maxMemory,
    String? runtimeEnvId,
    String? serverFile,
  }) async {
    final params = <String, dynamic>{'name': name, 'runtime': runtime};
    if (maxMemory != null) params['max_memory'] = maxMemory;
    if (runtimeEnvId != null && runtimeEnvId.isNotEmpty) {
      params['runtime_env_id'] = runtimeEnvId;
    }
    if (serverFile != null && serverFile.isNotEmpty) {
      params['server_file'] = serverFile;
    }

    final result = await _client.callObject('instance.create', params: params);
    return Instance.fromJson(_objectField(result, 'instance'));
  }

  /// 修改元数据。
  ///
  /// [patch] 的语义由 daemon 定义：**给哪些字段就改哪些**，
  /// 显式传 `null`（或空串）表示清空该字段。
  Future<Instance> update(String id, Map<String, dynamic> patch) async {
    final result = await _client.callObject(
      'instance.update',
      params: {'id': id, ...patch},
    );
    return Instance.fromJson(_objectField(result, 'instance'));
  }

  /// 删除实例。
  ///
  /// [keepFiles] 为 `true` 时只把它移出列表，工作目录留在磁盘上。
  Future<void> delete(String id, {bool keepFiles = false}) async {
    await _client.callObject(
      'instance.delete',
      params: {'id': id, if (keepFiles) 'keep_files': true},
    );
  }

  /// 设置当前选中的实例；[id] 传 `null` 取消选中。
  Future<void> select(String? id) async {
    await _client.callObject('instance.select', params: {'id': id});
  }

  /// 重新扫描磁盘（外部改动过目录时用）。
  Future<Map<String, dynamic>> scan() => _client.callObject('instance.scan');

  static Map<String, dynamic> _objectField(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map) return value.cast<String, dynamic>();
    throw DaemonException('internal', '返回里缺少 `$key` 字段：$source');
  }
}

/// 把实例相关的异常翻成给用户看的一句话。
String describeInstanceError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'instance_name_taken' => '已存在同名实例，换个名字吧',
      'instance_not_found' => '实例不存在（可能已被删除）',
      'forbidden' => '这个目录不允许删除，已拒绝操作',
      _ => error.message,
    };
  }
  return '$error';
}
