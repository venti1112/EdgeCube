import '../connection/client.dart';
import 'models.dart';

/// STUN 打洞隧道的 RPC 接口。
///
/// 四个方法：
///
/// * `status` —— 状态总览（全局设置 + 每实例隧道行），读 daemon 内存快照，不联网；
/// * `settings.set` —— **patch 式**更新全局设置（只传要改的字段），daemon 落盘
///   并把在跑的隧道全部按新参数重建；
/// * `logs` / `logs.clear` —— 隧道日志（环形缓冲，最多 500 行）。
///
/// 隧道的开关 / PROXY / 目标端口覆盖**没有单独的方法**：开关与参数在实例设置里
/// （`instance.update` 的 `stun_*` 字段），daemon 跟着实例的启停自动建 / 拆。
class StunApi {
  const StunApi(this._client);

  final DaemonClient _client;

  /// 状态总览（全局设置 + 每实例隧道行），读 daemon 的缓存，不联网。
  Future<StunStatus> status() async =>
      StunStatus.fromJson(await _client.callObject('stun.status'));

  /// 更新全局设置（patch：只传要改的字段），返回更新后的总览。
  ///
  /// daemon 侧会 clamp 数值（保活 5-300 秒、并发 1-1024）并立即重建隧道 ——
  /// 界面别拿本地值猜，以返回的快照为准。
  Future<StunStatus> saveSettings({
    List<String>? servers,
    int? keepAliveSeconds,
    int? maxConnections,
    String? keepaliveHttp,
    bool? showConnectionLog,
  }) async => StunStatus.fromJson(
    await _client.callObject(
      'stun.settings.set',
      params: {
        'servers': ?servers,
        'keep_alive_seconds': ?keepAliveSeconds,
        'max_connections': ?maxConnections,
        'keepalive_http': ?keepaliveHttp,
        'show_connection_log': ?showConnectionLog,
      },
    ),
  );

  /// 隧道日志（旧 → 新，最多 500 行）。
  Future<StunLogs> logs() async =>
      StunLogs.fromJson(await _client.callObject('stun.logs'));

  /// 清空隧道日志；返回清掉的行数。
  Future<int> clearLogs() async {
    final json = await _client.callObject('stun.logs.clear');
    final cleared = json['cleared'];
    return cleared is num ? cleared.toInt() : 0;
  }
}
