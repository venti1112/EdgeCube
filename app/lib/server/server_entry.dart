import 'dart:math';

/// 服务器类型:本地(同机 daemon,免密登录)/ 远程(密码登录)
enum ServerType { local, remote }

/// 服务器条目(不可变状态,持久化到 just_storage)。
///
/// 本地服务器由 APP 自动发现添加(启动时检测到 daemon 数据目录的
/// `local.key` 即代表同机存在 daemon,走 `/auth/local-login` 免密);
/// 远程服务器由用户手动添加,使用用户名密码登录。
class ServerEntry {
  const ServerEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    this.username,
  });

  /// 唯一标识,本地服务器固定为 [localId]
  final String id;

  final String name;

  final ServerType type;

  /// daemon 监听地址(本地固定 127.0.0.1)
  final String host;

  /// daemon 监听端口(默认 8760)
  final int port;

  /// 远程登录用户名(仅远程服务器使用)
  final String? username;

  /// 本地服务器固定 id
  static const localId = 'local';

  /// 默认本地服务器条目(127.0.0.1:8760)
  static ServerEntry defaultLocal() => const ServerEntry(
        id: localId,
        name: '本地服务器',
        type: ServerType.local,
        host: '127.0.0.1',
        port: 8760,
      );

  /// 本地默认端口(与 daemon 默认监听一致,openapi servers.url)
  static const defaultPort = 8760;

  /// 生成简单随机 id(避免额外依赖 uuid)
  static String newId() =>
      's-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
      '${Random().nextInt(0xFFFFFF).toRadixString(16)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
      };

  factory ServerEntry.fromJson(Map<String, dynamic> json) => ServerEntry(
        id: json['id'] as String,
        name: json['name'] as String? ?? _defaultName(json),
        type: ServerType.values.asNameMap()[json['type'] as String?] ??
            ServerType.remote,
        host: json['host'] as String? ?? '127.0.0.1',
        port: (json['port'] as num?)?.toInt() ?? defaultPort,
        username: json['username'] as String?,
      );

  static String _defaultName(Map<String, dynamic> json) =>
      json['type'] == 'local' ? '本地服务器' : '未命名服务器';

  ServerEntry copyWith({
    String? name,
    ServerType? type,
    String? host,
    int? port,
    String? username,
  }) =>
      ServerEntry(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
      );
}