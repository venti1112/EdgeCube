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
  ///
  /// [startupCommand] 可以留空（先建目录、稍后再配），但那样实例起不来 ——
  /// daemon 会在 `instance.status.warnings` 里提醒。
  Future<Instance> create({
    required String name,
    String? startupCommand,
    String? path,
  }) async {
    final params = <String, dynamic>{'name': name};
    if (startupCommand != null && startupCommand.trim().isNotEmpty) {
      params['startup_command'] = startupCommand.trim();
    }
    if (path != null && path.trim().isNotEmpty) {
      params['path'] = path.trim();
    }

    final result = await _client.callObject('instance.create', params: params);
    return Instance.fromJson(_objectField(result, 'instance'));
  }

  /// 读 EULA 状态（`eula.txt` 里有没有 `eula=true`）。
  ///
  /// 启动前要过的那一道。判断在 daemon：
  /// 文件在服务端机器上，而且判定口径（宽松的 `eula\s*=\s*true`）也只该有一份实现。
  Future<EulaStatus> eula(String id) async => EulaStatus.fromJson(
    await _client.callObject('instance.eula.get', params: {'id': id}),
  );

  /// 同意 EULA：让 daemon 往 `eula.txt` 写 `eula=true`（**没有就建**）。
  ///
  /// 内容由 daemon 定死，前端给不了 —— 与 `instance.config.save` 的
  /// 「文件名由封闭枚举算」是同一条约束。
  Future<void> acceptEula(String id) async {
    await _client.callObject('instance.eula.accept', params: {'id': id});
  }

  /// 修改元数据。
  ///
  /// [patch] 的语义由 daemon 定义：**给哪些字段就改哪些**，
  /// 显式传 `null`（或空串）表示清空该字段。
  /// 改实例元数据：只发要改的字段，`null` 表示清空。
  ///
  /// `id` 与补丁平铺在同一层（WS 的 `params` 里没有别的地方放它）——
  /// daemon 会把 `id` 当**寻址参数**而不是补丁字段，所以混在补丁里是安全的。
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

  // ── 进程 ────────────────────────────────────────────────────────────────

  /// 启动实例。
  Future<Map<String, dynamic>> start(String id) =>
      _client.callObject('instance.start', params: {'id': id});

  /// 优雅停止：把「停止命令」写进服务端控制台。
  Future<Map<String, dynamic>> stop(String id) =>
      _client.callObject('instance.stop', params: {'id': id});

  /// 重启（daemon 会等旧进程真的退下去再起，不会撞端口）。
  Future<Map<String, dynamic>> restart(String id) =>
      _client.callObject('instance.restart', params: {'id': id});

  /// 强制停止：直接杀进程组（可能丢数据）。
  Future<Map<String, dynamic>> kill(String id) =>
      _client.callObject('instance.kill', params: {'id': id});

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
      'instance_not_configured' => '还没配置启动命令，去「实例设置」里填一条',
      'instance_launch_incomplete' => '启动配置不完整，去「实例设置」里补齐',
      'instance_runtime_missing' => '运行环境不见了（可能被删了），去「实例设置」里重选一个',
      'instance_server_file_missing' => '实例目录里找不到选定的服务端 jar，去「文件」页确认一下',
      'instance_already_running' => '实例已经在运行了',
      'instance_not_running' => '实例没在运行',
      'instance_dir_missing' => '实例目录不存在，先把它找回来再启动',
      'instance_stop_command_missing' => '没有可用的停止命令，只能强制停止',
      'instance_stop_timeout' => '旧进程没能停下来，重启已放弃',
      'forbidden' => '这个目录不允许删除，已拒绝操作',
      _ => error.message,
    };
  }
  return '$error';
}
