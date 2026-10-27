import '../connection/client.dart';
import 'models.dart';

/// 运行环境接口：把 daemon 的 `runtime.*` 方法包成普通的 Dart 调用。
///
/// 错误都以 [DaemonException] 抛出，`code` 是稳定字符串，UI 按 code 分支
/// （见 [describeRuntimeError]），不要匹配 message。
class RuntimeApi {
  const RuntimeApi(this._client);

  final DaemonClient _client;

  /// 厂商 / 包类型表 + 本机平台。
  Future<RuntimeCatalog> catalog() async =>
      RuntimeCatalog.fromJson(await _client.callObject('runtime.catalog'));

  /// 某个厂商与包类型下可装的版本（新的在前）。
  ///
  /// [all] 默认 `false` = **只要最新那个**（一次上游请求就够）。点了「历史版本」
  /// 再传 `true` 拉完整列表 —— frp 的清单走 GitHub API，未认证只有 60 次/小时，
  /// 所以默认值必须是「最省」的那个。
  Future<RuntimeVersions> versions({
    String? provider,
    String? packageType,
    bool all = false,
  }) async {
    final result = await _client.callObject(
      'runtime.versions',
      params: {
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (packageType != null && packageType.isNotEmpty)
          'package_type': packageType,
        if (all) 'all': true,
      },
    );
    return RuntimeVersions.fromJson(result);
  }

  /// 全部环境（含正在装与失败的）。
  Future<RuntimeEnvList> list() async =>
      RuntimeEnvList.fromJson(await _client.callObject('runtime.list'));

  /// 删掉一个环境（元数据 + 目录 + 下载暂存）。
  ///
  /// 在途的安装也会被叫停 —— daemon 那边「删元数据就是取消」。
  Future<void> delete(String id) async {
    await _client.callObject('runtime.delete', params: {'id': id});
  }
}

/// 把运行环境的异常翻成给用户看的一句话。
///
/// 关键在区分「你选的装不了」（可以换个版本）与「网络 / 上游挂了」（可以重试）
/// 与「daemon 该升级了」（上游改了接口）。认不出的码退回 message 本身。
String describeRuntimeError(Object error) {
  if (error is! DaemonException) return '$error';
  return switch (error.code) {
    'runtime_unavailable' => '守护进程还没就绪（或下载队列没起来），稍后再试',
    'runtime_unsupported_host' => '这台机器没有对应的 Zulu 构建，装不了',
    'runtime_provider_not_found' =>
      '没有这个厂商（daemon 版本可能不一致）',
    'runtime_package_type_not_found' => '没有这个包类型',
    'runtime_version_required' => '请先选择一个 Java 大版本',
    'runtime_version_not_found' => '这个版本拿不到（可能已被上游下架），换一个试试',
    'runtime_not_found' => '环境不存在（可能已被删除）',
    'runtime_busy' => '这个环境正在安装中，等它结束再试',
    'runtime_upstream_error' => '上游连不上（网络问题，可重试）',
    'runtime_parse_error' => '上游改了接口，需要升级 daemon',
    'runtime_save_failed' => '写盘失败（磁盘满了？权限不够？）',
    _ => error.message,
  };
}
