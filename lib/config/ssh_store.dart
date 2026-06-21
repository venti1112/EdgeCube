import 'config_store.dart';

/// SSH 服务的配置，持久化到 `config/ssh.json`。
///
/// 同一 SSH 服务器同时提供 SFTP（文件传输）与 SSH 终端（命令行），共用端口、账号与
/// 主机密钥；两项能力各由开关独立控制。
///
/// 字段：
/// - [port]：监听端口，默认 2222（<1024 在非 root 设备无法绑定）；
/// - [username]/[password]：登录凭据，强制设置（不允许匿名）；
/// - [writable]：是否允许 SFTP 写入（上传/删除/重命名）；仅作用于 SFTP，不限制 SSH 终端；
/// - [sftpEnabled]：是否启用 SFTP 文件访问；
/// - [shellEnabled]：是否启用 SSH 终端；
/// - [ipv6Enabled]：是否启用 IPv6（双栈）监听，独立开关；关闭时仅监听 IPv4。
class SshConfig {
  const SshConfig({
    this.port = 2222,
    this.username = '',
    this.password = '',
    this.writable = true,
    this.sftpEnabled = false,
    this.shellEnabled = false,
    this.ipv6Enabled = false,
  });

  final int port;
  final String username;
  final String password;
  final bool writable;
  final bool sftpEnabled;
  final bool shellEnabled;
  final bool ipv6Enabled;

  /// 账号是否已完整设置（用户名与密码均非空）。SSH 服务强制账号密码登录。
  bool get hasCredentials => username.isNotEmpty && password.isNotEmpty;

  SshConfig copyWith({
    int? port,
    String? username,
    String? password,
    bool? writable,
    bool? sftpEnabled,
    bool? shellEnabled,
    bool? ipv6Enabled,
  }) => SshConfig(
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    writable: writable ?? this.writable,
    sftpEnabled: sftpEnabled ?? this.sftpEnabled,
    shellEnabled: shellEnabled ?? this.shellEnabled,
    ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
  );

  Map<String, dynamic> toJson() => {
    'port': port,
    'username': username,
    'password': password,
    'writable': writable,
    'sftpEnabled': sftpEnabled,
    'shellEnabled': shellEnabled,
    'ipv6Enabled': ipv6Enabled,
  };

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
    port: (json['port'] as int?) ?? 2222,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    writable: json['writable'] as bool? ?? true,
    sftpEnabled: json['sftpEnabled'] as bool? ?? false,
    shellEnabled: json['shellEnabled'] as bool? ?? false,
    ipv6Enabled: json['ipv6Enabled'] as bool? ?? false,
  );
}

/// SSH 配置的本地持久化读写，存于 `config/ssh.json`。
class SshStore {
  SshStore._();

  static const String _fileName = 'ssh.json';

  /// 读取已保存的 SSH 配置；未保存过返回默认配置。
  static Future<SshConfig> load() async {
    final m = await ConfigStore.readConfig(_fileName);
    if (m.isEmpty) return const SshConfig();
    return SshConfig.fromJson(m);
  }

  /// 持久化 SSH 配置。
  static Future<void> save(SshConfig config) async {
    await ConfigStore.writeConfig(_fileName, config.toJson());
  }
}
