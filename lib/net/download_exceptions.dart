/// 统一下载引擎抛出的异常类型。
///
/// 各下载调用点在外层 `catch` 后可将其翻译回原有的领域异常
/// （如 `HashMismatchException` / `DownloadHttpException` / `CancellationException`），
/// 以保持既有 UI 文案不变。
library;

/// HTTP 响应非 2xx（探测或分片请求返回错误状态码）。
class DownloadHttpError implements Exception {
  const DownloadHttpError(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'DownloadHttpError(HTTP $statusCode)';
}

/// 下载完成后内容哈希校验不匹配。
class DownloadHashMismatch implements Exception {
  const DownloadHashMismatch({this.expected, required this.actual});

  /// 期望哈希（调用方提供）。
  final String? expected;

  /// 实际计算出的哈希。
  final String actual;

  @override
  String toString() =>
      'DownloadHashMismatch(expected: $expected, actual: $actual)';
}

/// 下载被调用方取消。
class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'DownloadCancelled';
}

/// 其它下载失败（网络错误、分片重试耗尽、大小不匹配等）。
class DownloadFailed implements Exception {
  const DownloadFailed(this.cause);

  final Object cause;

  @override
  String toString() => 'DownloadFailed: $cause';
}
