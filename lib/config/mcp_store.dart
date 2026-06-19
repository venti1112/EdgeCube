import 'dart:math';

import 'config_store.dart';

/// MCP 服务的配置，持久化到 `config/mcp.json`。
///
/// 字段：
/// - [enabled]：是否启用（独立于服务器进程，用户手动开关）；
/// - [port]：监听端口，默认 8765；
/// - [token]：访问令牌（Bearer Token），客户端需在 `Authorization` 头携带；
///   为空表示不鉴权（不推荐）；
/// - [allowControl]：是否允许控制类操作（启动/停止服务端、发送命令、切换实例）。
///   关闭后仅暴露只读工具。
/// - [allowShell]：是否允许 Shell 命令执行工具（高风险：AI 可执行任意命令）。默认关闭。
class McpConfig {
  const McpConfig({
    this.enabled = false,
    this.port = 8765,
    this.token = '',
    this.allowControl = true,
    this.allowShell = false,
  });

  final bool enabled;
  final int port;
  final String token;
  final bool allowControl;
  final bool allowShell;

  McpConfig copyWith({
    bool? enabled,
    int? port,
    String? token,
    bool? allowControl,
    bool? allowShell,
  }) => McpConfig(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    token: token ?? this.token,
    allowControl: allowControl ?? this.allowControl,
    allowShell: allowShell ?? this.allowShell,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'token': token,
    'allowControl': allowControl,
    'allowShell': allowShell,
  };

  factory McpConfig.fromJson(Map<String, dynamic> json) => McpConfig(
    enabled: json['enabled'] as bool? ?? false,
    port: (json['port'] as int?) ?? 8765,
    token: json['token'] as String? ?? '',
    allowControl: json['allowControl'] as bool? ?? true,
    allowShell: json['allowShell'] as bool? ?? false,
  );
}

/// MCP 配置的本地持久化读写，存于 `config/mcp.json`。
class McpStore {
  McpStore._();

  static const String _fileName = 'mcp.json';

  static final Random _random = Random.secure();

  /// 读取已保存的 MCP 配置；未保存过返回默认配置。
  static Future<McpConfig> load() async {
    final m = await ConfigStore.readConfig(_fileName);
    if (m.isEmpty) return const McpConfig();
    return McpConfig.fromJson(m);
  }

  /// 持久化 MCP 配置。
  static Future<void> save(McpConfig config) async {
    await ConfigStore.writeConfig(_fileName, config.toJson());
  }

  /// 生成 32 字符的随机十六进制访问令牌。
  static String generateToken() {
    const chars = '0123456789abcdef';
    return List.generate(
      32,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }
}
