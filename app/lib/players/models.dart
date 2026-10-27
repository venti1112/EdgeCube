/// 玩家管理的模型：名单条目。
///
/// 数据来自 daemon 的 `instance.players.*`（它去读实例目录下的名单文件，
/// JSON 优先、纯文本兜底）：字段名是 daemon 折平别名之后的线上格式 —— PNX 的
/// `expireDate` / `creationDate` 在那边已经并进 `expires` / `created`，
/// 纯文本名单的其余字段是空串。解析入口在 [`PlayersApi`]。
///
/// **在线玩家不在这里** —— 那是 daemon 从控制台输出里解析的状态，
/// 见 `providers.dart` 的 `onlinePlayersProvider`。
library;

/// 白名单 / OP 名单里的一条。
class NamedEntry {
  const NamedEntry({required this.name, required this.uuid});

  final String name;
  final String uuid;

  factory NamedEntry.fromJson(Map<String, dynamic> json) => NamedEntry(
    name: json['name'] as String? ?? '',
    uuid: json['uuid'] as String? ?? '',
  );
}

/// 封禁名单（`banned-players.json`）里的一条。
///
/// 纯文本回退（`banned-players.txt`，每行一个名字）时其余字段都是空串。
class BanEntry {
  const BanEntry({
    required this.name,
    required this.uuid,
    required this.reason,
    required this.source,
    required this.expires,
    required this.created,
  });

  final String name;
  final String uuid;
  final String reason;
  final String source;
  final String expires;
  final String created;

  factory BanEntry.fromJson(Map<String, dynamic> json) => BanEntry(
    name: json['name'] as String? ?? '',
    uuid: json['uuid'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    source: json['source'] as String? ?? '',
    expires: json['expires'] as String? ?? '',
    created: json['created'] as String? ?? '',
  );
}

/// IP 封禁名单（`banned-ips.json`）里的一条。
///
/// 纯文本回退（`banned-ips.txt`，每行一个 IP）时其余字段都是空串。
class IpBanEntry {
  const IpBanEntry({
    required this.ip,
    required this.reason,
    required this.source,
    required this.expires,
    required this.created,
  });

  final String ip;
  final String reason;
  final String source;
  final String expires;
  final String created;

  factory IpBanEntry.fromJson(Map<String, dynamic> json) => IpBanEntry(
    ip: json['ip'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    source: json['source'] as String? ?? '',
    expires: json['expires'] as String? ?? '',
    created: json['created'] as String? ?? '',
  );
}
