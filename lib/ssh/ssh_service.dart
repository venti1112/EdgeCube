import 'package:flutter/services.dart';

/// SSH 服务的平台通道封装。
///
/// 实际 SSH 服务器在 Android 原生侧运行（见 `SshServerManager.kt`），基于 Apache MINA SSHD，
/// 同一服务器同时提供 SFTP 文件访问与 SSH 终端（shell 通道桥接到自带 PTY），共用端口、
/// 账号与主机密钥，供外部设备（电脑、手机）通过 `sftp` / `ssh` 客户端访问。
class SshService {
  SshService._();

  static const _channel = MethodChannel('com.venti1112.edgecube/ssh');

  /// 启动 SSH 服务。
  ///
  /// [rootDir] 为 SFTP 根目录与 SSH 终端初始工作目录（通常是当前实例的工作目录）；
  /// [port] 监听端口；[username]/[password] 登录凭据（强制设置）；
  /// [writable] 是否允许 SFTP 写入（仅作用于 SFTP）；
  /// [sftpEnabled]/[shellEnabled] 分别控制 SFTP 与 SSH 终端是否启用（至少其一为真）；
  /// [ipv6] 是否启用 IPv6（双栈）监听（关闭时仅 IPv4）。
  static Future<void> start({
    required String rootDir,
    required int port,
    required String username,
    required String password,
    required bool writable,
    required bool sftpEnabled,
    required bool shellEnabled,
    required bool ipv6,
  }) async {
    await _channel.invokeMethod<void>('start', {
      'rootDir': rootDir,
      'port': port,
      'username': username,
      'password': password,
      'writable': writable,
      'sftpEnabled': sftpEnabled,
      'shellEnabled': shellEnabled,
      'ipv6': ipv6,
    });
  }

  /// 停止 SSH 服务。
  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  /// 查询 SSH 服务是否正在运行。
  static Future<bool> isRunning() async {
    final running = await _channel.invokeMethod<bool>('isRunning');
    return running ?? false;
  }

  /// 获取 SSH 主机密钥的 SHA-256 指纹（OpenSSH 形式 `SHA256:...`），供首次连接核对。
  /// 主机密钥尚不存在时原生侧会先生成；失败返回 null。
  static Future<String?> hostKeyFingerprint() async {
    return _channel.invokeMethod<String>('hostKeyFingerprint');
  }
}
