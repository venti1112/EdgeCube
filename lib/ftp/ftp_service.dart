import 'package:flutter/services.dart';

/// FTP 文件管理服务的平台通道封装。
///
/// 实际 FTP 服务器在 Android 原生侧运行（见 `FtpServerManager.kt`），
/// 将指定根目录通过 FTP 协议对外开放，供外部设备（电脑、手机）访问。
class FtpService {
  FtpService._();

  static const _channel = MethodChannel('com.venti1112.edgecube/ftp');

  /// 启动 FTP 服务。
  ///
  /// [rootDir] 为 FTP 根目录（通常是当前实例的工作目录）；
  /// [port] 监听端口；[username]/[password] 登录凭据（用户名为空启用匿名）；
  /// [writable] 是否允许写入；[ipv6] 是否启用 IPv6（双栈）监听（关闭时仅 IPv4）。
  static Future<void> start({
    required String rootDir,
    required int port,
    required String username,
    required String password,
    required bool writable,
    required bool ipv6Enabled,
  }) async {
    await _channel.invokeMethod<void>('start', {
      'rootDir': rootDir,
      'port': port,
      'username': username,
      'password': password,
      'writable': writable,
      'ipv6Enabled': ipv6Enabled,
    });
  }

  /// 停止 FTP 服务。
  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  /// 查询 FTP 服务是否正在运行。
  static Future<bool> isRunning() async {
    final running = await _channel.invokeMethod<bool>('isRunning');
    return running ?? false;
  }
}
