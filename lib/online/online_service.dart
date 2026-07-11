import 'dart:async';

/// 在线资源访问工具类。
///
/// 仅保留静态默认地址与并行请求工具方法，不持有任何状态、不生成设备标识。
/// 更新检查地址与运行环境下载地址的持久化配置由 [NetworkStore] 管理。
class OnlineService {
  OnlineService._();

  static const List<String> defaultUpdateCheckUrls = [
    'https://edgecube-files.ventichat.com/app/updates.json',
  ];

  static const List<String> defaultEcpkgCatalogUrls = [
    'https://edgecube-files.ventichat.com/ecpkg/list.json',
  ];

  /// 并行请求多个 URL，返回第一个有效结果。
  ///
  /// [urls] 请求地址列表
  /// [fetch] 对单个 URL 执行请求并返回结果
  /// [isValid] 判断结果是否有效（无效结果会被忽略）
  ///
  /// 所有 URL 均无效或请求失败时抛出异常。
  static Future<T> fetchFirstValid<T>(
    List<String> urls,
    Future<T> Function(String url) fetch,
    bool Function(T) isValid,
  ) async {
    if (urls.isEmpty) throw ArgumentError('urls must not be empty');
    if (urls.length == 1) {
      final result = await fetch(urls.first);
      if (!isValid(result)) throw Exception('Invalid data from ${urls.first}');
      return result;
    }

    final completer = Completer<T>();
    var failures = 0;

    for (final url in urls) {
      Future.microtask(() async {
        try {
          final result = await fetch(url);
          if (isValid(result) && !completer.isCompleted) {
            completer.complete(result);
            return;
          }
        } catch (_) {}
        if (!completer.isCompleted) {
          failures++;
          if (failures == urls.length) {
            completer.completeError(
              Exception('All URLs failed or returned invalid data'),
            );
          }
        }
      });
    }

    return completer.future;
  }
}
