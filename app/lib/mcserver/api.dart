import '../connection/client.dart';
import 'models.dart';

/// 服务端目录接口：版本列表与下载地址都在 daemon 那边取，本端只发 RPC。
///
/// 为什么不让 App 自己去打上游：每个客户端各打一遍、家宽出口还不一定通，
/// 而 daemon 可以「一处出网、一处缓存」（版本列表在它那边缓存 5 分钟）。
class McserverApi {
  const McserverApi(this._client);

  final DaemonClient _client;

  /// 分类 + 类型表（含文件名、建议启动命令、可用的校验算法）。
  Future<ServerCatalog> types() async {
    final result = await _client.callObject('mcserver.types');
    return ServerCatalog.fromJson(result);
  }

  /// 某个类型的版本列表（新版本在前）。
  Future<List<String>> versions(String type) async {
    final result = await _client.callObject(
      'mcserver.versions',
      params: {'type': type},
    );
    return _strings(result['versions']);
  }

  /// 某个 Minecraft 版本下可用的加载器版本（目前只有 Fabric）。
  Future<List<String>> loaders({
    required String type,
    required String mcVersion,
  }) async {
    final result = await _client.callObject(
      'mcserver.loaders',
      params: {'type': type, 'mc_version': mcVersion},
    );
    return _strings(result['loaders']);
  }

  /// 把「类型 + 版本（+ 加载器版本）」解析成下载地址、校验值与建议启动命令。
  ///
  /// 这一步**只回答「下什么」**：不建实例、不提交下载 —— 那是后面两步的事。
  Future<ServerPlan> plan({
    required String type,
    String? version,
    String? loaderVersion,
  }) async {
    final params = <String, dynamic>{'type': type};
    if (version != null && version.isNotEmpty) params['version'] = version;
    if (loaderVersion != null && loaderVersion.isNotEmpty) {
      params['loader_version'] = loaderVersion;
    }

    final result = await _client.callObject('mcserver.plan', params: params);
    return ServerPlan.fromJson(result);
  }

  static List<String> _strings(Object? raw) => [
    if (raw is List)
      for (final item in raw)
        if (item is String) item,
  ];
}

/// 把服务端目录的异常翻成给用户看的一句话。
///
/// 关键在于区分「你选错了」（可以回上一页重选）和「网络不通 / 上游挂了」
/// （可以重试）以及「daemon 该升级了」（上游改了接口）。
String describeMcserverError(Object error) {
  if (error is DaemonException) {
    return switch (error.code) {
      'mcserver_type_not_found' => '这个服务端类型不支持（daemon 版本可能不一致）',
      'mcserver_not_found' => '这个版本拿不到（可能已被上游下架），换个版本试试',
      'mcserver_version_required' => '请先选择一个版本',
      'mcserver_loader_required' => '请先选择一个加载器版本',
      'mcserver_no_loaders' => '这个服务端不需要选加载器版本',
      'mcserver_upstream_error' => '连不上下载源（${error.message}），检查一下网络再重试',
      'mcserver_parse_error' => '下载源改了接口，需要升级 daemon：${error.message}',
      'mcserver_unavailable' => '服务端目录还没就绪（daemon 可能正在启动或关闭）',
      _ => error.message,
    };
  }
  return '$error';
}
