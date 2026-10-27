import '../connection/client.dart';
import 'models.dart';

/// 在线页给玩家打标签用的三张名字集合（都小写，按名字忽略大小写匹配）。
typedef PlayerContextSets = ({
  Set<String> whitelist,
  Set<String> ops,
  Set<String> bans,
});

/// 玩家名单的读写：名单内容由 daemon 读盘（`instance.players.*`），
/// 命令由 daemon 写进控制台（`instance.console.write`）。
///
/// 为什么不在 App 里读文件、也不在 App 里解析日志：
///
/// * 名单文件在 daemon 那台机器上，App 只是隔着一根 WS；
/// * 同一个文件有**两套**读取规则（标签页那份 JSON 优先，打标签那份要
///   JSON 非空才算数），只放一处实现才不会两边走偏 —— 那处就是 daemon；
/// * 在线玩家是从服务端输出里认出来的**状态**，只有 daemon 拿得到从头到尾、
///   一条不漏的输出流，见 `providers.dart` 的 `onlinePlayersProvider`。
class PlayersApi {
  const PlayersApi(this._client, this.id);

  final DaemonClient _client;
  final String id;

  /// 白名单（`whitelist.json` → `white-list.txt`）。
  Future<List<NamedEntry>> whitelist() => _entries(
    'instance.players.whitelist',
    NamedEntry.fromJson,
  );

  /// OP 名单（`ops.json` → `ops.txt`）。
  Future<List<NamedEntry>> ops() =>
      _entries('instance.players.ops', NamedEntry.fromJson);

  /// 封禁名单（`banned-players.json` → `banned-players.txt`）。
  Future<List<BanEntry>> bans() =>
      _entries('instance.players.bans', BanEntry.fromJson);

  /// IP 封禁名单（`banned-ips.json` → `banned-ips.txt`）。
  Future<List<IpBanEntry>> ipBans() =>
      _entries('instance.players.ip_bans', IpBanEntry.fromJson);

  /// 在线页的三张名字集合（给在线玩家打「白名单 / 已封禁 / OP」标签）。
  Future<PlayerContextSets> contextSets() async => (
    whitelist: (await _names('instance.players.whitelist')).toSet(),
    ops: (await _names('instance.players.ops')).toSet(),
    bans: (await _names('instance.players.bans')).toSet(),
  );

  /// 往控制台写一段输入。
  ///
  /// 就是控制台里的「敲键」：**命令与行尾由调用方拼好**（`'$cmd$lineEnding'`），
  /// 这里原样写进 PTY。本页只发命令、不订输出，所以不连 `/pty/{id}`
  /// —— 那条连接会把整个控制台输出也拉过来，而这里一个字都不需要。
  Future<void> consoleWrite(String data) async {
    await _client.callObject(
      'instance.console.write',
      params: {'id': id, 'data': data},
    );
  }

  /// 一个名单的标签页视图。
  Future<List<T>> _entries<T>(
    String method,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await _call(method);
    final entries = raw['entries'];
    if (entries is! List) return const [];
    return [
      for (final entry in entries)
        if (entry is Map) parse(entry.cast<String, dynamic>()),
    ];
  }

  /// 一个名单的打标签视图（小写名字；回退规则由 daemon 算好）。
  Future<List<String>> _names(String method) async {
    final raw = await _call(method);
    final names = raw['names'];
    if (names is! List) return const [];
    return [
      for (final name in names)
        if (name is String) name,
    ];
  }

  Future<Map<String, dynamic>> _call(String method) =>
      _client.callObject(method, params: {'id': id});
}
