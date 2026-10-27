import '../connection/client.dart';
import 'models.dart';

/// 下载队列接口：把 daemon 的 `download.*` 方法包成普通的 Dart 调用。
///
/// 错误都以 [DaemonException] 抛出，`code` 是稳定字符串
/// （`download_target_exists` / `download_path_invalid` / …），
/// UI 按 code 分支，不要匹配 message —— 见 [describeDownloadError]。
class DownloadApi {
  const DownloadApi(this._client);

  final DaemonClient _client;

  /// 提交一个下载任务。
  ///
  /// [path] 是**相对实例根目录**的目录（`''` = 实例根），[filename] 不给的话
  /// daemon 会从 URL 末段取名。[checksum] 只带一个值 —— daemon 那边
  /// 「同时给多个校验值」是直接拒绝的，这里从类型上就不给出错的余地。
  Future<DownloadTask> add({
    required String url,
    required String instanceId,
    String path = '',
    String? filename,
    DownloadChecksum? checksum,
  }) async {
    final params = <String, dynamic>{
      'url': url,
      'instance_id': instanceId,
      'path': path,
    };
    if (filename != null && filename.trim().isNotEmpty) {
      params['filename'] = filename.trim();
    }
    if (checksum != null) {
      params[_checksumParam(checksum.algorithm)] = checksum.value;
    }

    final result = await _client.callObject('download.add', params: params);
    return _taskOf(result);
  }

  /// 按任务 ID 查状态（快照）。
  Future<DownloadTask> status(String id) async {
    final result = await _client.callObject(
      'download.status',
      params: {'id': id},
    );
    return _taskOf(result);
  }

  /// 全部任务（daemon 固定成最新提交在前）+ 汇总速率。
  Future<DownloadList> list() async {
    final result = await _client.callObject('download.list');
    return DownloadList.fromJson(result);
  }

  /// `mcserver.plan` 给的 `algorithm` 就是这里的参数名；认不出来说明两边版本不一致，
  /// 与其让 daemon 以「不认识的字段」拒绝，不如在这儿说清楚。
  static String _checksumParam(String algorithm) {
    const known = {'md5', 'sha256', 'sha1'};
    if (!known.contains(algorithm)) {
      throw DaemonException(
        'invalid_params',
        'daemon 给了不认识的校验算法 `$algorithm`（本端支持 ${known.join(' / ')}）',
      );
    }
    return algorithm;
  }

  static DownloadTask _taskOf(Map<String, dynamic> result) {
    final task = result['task'];
    if (task is Map) return DownloadTask.fromJson(task.cast<String, dynamic>());
    throw DaemonException('internal', '返回里缺少 `task` 字段：$result');
  }
}

/// 把下载相关的异常翻成给用户看的一句话。
///
/// 提交阶段的失败都有明确的错误码；**真正的下载失败**（连不上、404、校验不过）
/// 不在这里 —— 那是异步的，体现在任务对象的 `state` 与 `error` 上。
String describeDownloadError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'download_instance_not_found' => '实例不存在（可能已被删除）',
      'download_task_not_found' => '找不到这个下载任务',
      'download_url_invalid' => '下载地址不合法：${error.message}',
      'download_path_invalid' => '保存路径不合法：${error.message}',
      'download_filename_invalid' => '文件名不合法：${error.message}',
      'download_filename_missing' => '这个地址看不出文件名，请手动指定一个',
      'download_checksum_invalid' => '校验值不合法：${error.message}',
      'download_target_exists' => '目标文件已存在，先删掉它或换个名字',
      'download_save_failed' => '创建保存目录失败：${error.message}',
      'download_engine_unavailable' => '下载队列还没就绪（daemon 可能正在启动或关闭）',
      'download_failed' => '提交下载失败：${error.message}',
      _ => error.message,
    };
  }
  return '$error';
}

/// 把任务失败的原因翻成给用户看的一句话。
String describeDownloadFailure(DownloadFailure failure) {
  if (failure.isChecksumMismatch) {
    // daemon 在校验失败时会把文件删掉，所以这里要明确告诉用户「重下」是唯一出路
    return '校验失败：文件已被丢弃，请重新下载';
  }
  return failure.message.isEmpty ? '下载失败' : failure.message;
}
