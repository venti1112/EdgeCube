import 'config_store.dart';

/// FTP 文件管理服务的配置，持久化到 `config/ftp.json`。
///
/// 字段：
/// - [enabled]：是否启用（独立于服务器进程，用户手动开关）；
/// - [port]：监听端口，默认 2121；
/// - [username]：登录用户名，空表示匿名访问；
/// - [password]：登录密码（匿名访问时忽略）；
/// - [writable]：是否允许写入（上传/删除/重命名）。
class FtpConfig {
  const FtpConfig({
    this.enabled = false,
    this.port = 2121,
    this.username = '',
    this.password = '',
    this.writable = true,
  });

  final bool enabled;
  final int port;
  final String username;
  final String password;
  final bool writable;

  /// 是否为匿名访问（用户名为空）。
  bool get isAnonymous => username.isEmpty;

  FtpConfig copyWith({
    bool? enabled,
    int? port,
    String? username,
    String? password,
    bool? writable,
  }) => FtpConfig(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    writable: writable ?? this.writable,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'username': username,
    'password': password,
    'writable': writable,
  };

  factory FtpConfig.fromJson(Map<String, dynamic> json) => FtpConfig(
    enabled: json['enabled'] as bool? ?? false,
    port: (json['port'] as int?) ?? 2121,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    writable: json['writable'] as bool? ?? true,
  );
}

/// FTP 配置的本地持久化读写，存于 `config/ftp.json`。
class FtpStore {
  FtpStore._();

  static const String _fileName = 'ftp.json';

  /// 读取已保存的 FTP 配置；未保存过返回默认配置。
  static Future<FtpConfig> load() async {
    final m = await ConfigStore.readConfig(_fileName);
    if (m.isEmpty) return const FtpConfig();
    return FtpConfig.fromJson(m);
  }

  /// 持久化 FTP 配置。
  static Future<void> save(FtpConfig config) async {
    await ConfigStore.writeConfig(_fileName, config.toJson());
  }
}
