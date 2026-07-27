import 'config_store.dart';

/// STUN 隧道配置，持久化到 `config/stun.json`。
///
/// 字段：
/// - [enabled]：是否启用（随服务器自动启停）；
/// - [localPort]：要暴露的本地端口；null 表示跟随服务端实际监听端口；
/// - [proxyProtocol]：转发前是否发送 PROXY protocol v2 头（服务端需支持，
///   开启后服务端才能看到玩家真实 IP 而非 127.0.0.1）；
/// - [showConnectionLog]：是否把每条入站连接的建立/断开写进隧道日志；
/// - [maxConnections]：并发转发连接数上限，超出的入站连接直接拒绝；
/// - [keepAliveSeconds]：保活探测间隔（同时用于公网地址变化检测）；
/// - [servers]：自定义 STUN 服务器列表；为空表示使用内置列表。
class StunConfig {
  const StunConfig({
    this.enabled = false,
    this.localPort,
    this.proxyProtocol = false,
    this.showConnectionLog = true,
    this.maxConnections = 128,
    this.keepAliveSeconds = 20,
    this.servers = const [],
  });

  final bool enabled;
  final int? localPort;
  final bool proxyProtocol;
  final bool showConnectionLog;
  final int maxConnections;
  final int keepAliveSeconds;
  final List<String> servers;

  StunConfig copyWith({
    bool? enabled,
    int? localPort,
    bool clearLocalPort = false,
    bool? proxyProtocol,
    bool? showConnectionLog,
    int? maxConnections,
    int? keepAliveSeconds,
    List<String>? servers,
  }) => StunConfig(
    enabled: enabled ?? this.enabled,
    localPort: clearLocalPort ? null : (localPort ?? this.localPort),
    proxyProtocol: proxyProtocol ?? this.proxyProtocol,
    showConnectionLog: showConnectionLog ?? this.showConnectionLog,
    maxConnections: maxConnections ?? this.maxConnections,
    keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
    servers: servers ?? this.servers,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (localPort != null) 'localPort': localPort,
    'proxyProtocol': proxyProtocol,
    'showConnectionLog': showConnectionLog,
    'maxConnections': maxConnections,
    'keepAliveSeconds': keepAliveSeconds,
    if (servers.isNotEmpty) 'servers': servers,
  };

  factory StunConfig.fromJson(Map<String, dynamic> json) {
    final port = json['localPort'];
    final servers = json['servers'];
    return StunConfig(
      enabled: json['enabled'] as bool? ?? false,
      localPort: (port is int && port > 0 && port < 65536) ? port : null,
      proxyProtocol: json['proxyProtocol'] as bool? ?? false,
      showConnectionLog: json['showConnectionLog'] as bool? ?? true,
      maxConnections: _clamp(json['maxConnections'] as int?, 128, 1, 1024),
      keepAliveSeconds: _clamp(json['keepAliveSeconds'] as int?, 20, 5, 300),
      servers: servers is List
          ? servers.whereType<String>().where((s) => s.isNotEmpty).toList()
          : const [],
    );
  }

  static int _clamp(int? value, int fallback, int min, int max) {
    if (value == null) return fallback;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

/// STUN 隧道配置的本地持久化读写，存于 `config/stun.json`。
class StunStore {
  StunStore._();

  static const String _fileName = 'stun.json';

  /// 读取已保存的 STUN 配置；未保存过返回默认配置。
  static Future<StunConfig> load() async {
    final configMap = await ConfigStore.readConfig(_fileName);
    if (configMap.isEmpty) return const StunConfig();
    return StunConfig.fromJson(configMap);
  }

  /// 持久化 STUN 配置。
  static Future<void> save(StunConfig config) async {
    await ConfigStore.writeConfig(_fileName, config.toJson());
  }
}
