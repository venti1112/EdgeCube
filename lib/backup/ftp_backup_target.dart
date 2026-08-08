import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import 'backup_target.dart';

/// FTP 远程备份目标（支持 FTP / FTPES / FTPS）。
///
/// 封装 `ftpconnect` 的 [FTPConnect]。FTP 会话是状态化的（操作作用于
/// 「当前目录」），因此每次操作都建立独立连接：连接 → 逐段导航到
/// `remotePath/instanceId` → 执行 → 断开。上传前强制切换为二进制传输，
/// 并使用 LIST 命令列目录以兼容大多数服务器。
class FtpBackupTarget implements BackupTarget {
  FtpBackupTarget({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.securityType,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final SecurityType securityType;

  /// 在单个已连接会话中执行 [action]，结束后始终断开连接。
  Future<T> _withConnection<T>(Future<T> Function(FTPConnect ftp) action) async {
    final ftp = FTPConnect(
      host,
      port: port,
      user: username,
      pass: password,
      securityType: securityType,
    );
    // LIST 命令兼容性最好（MLSD 并非所有服务器都支持）。
    ftp.listCommand = ListCommand.list;
    final connected = await ftp.connect();
    if (!connected) {
      throw StateError('FTP 连接失败：$host:$port');
    }
    try {
      return await action(ftp);
    } finally {
      try {
        await ftp.disconnect();
      } catch (_) {}
    }
  }

  /// 解析远程目录的分段（去掉开头/结尾的 /）。
  List<String> get _remoteSegments => remotePath
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();

  /// 逐段导航到 `remotePath/instanceId`，不存在的目录自动创建。
  Future<void> _navigateTo(FTPConnect ftp, String instanceId) async {
    final segments = [..._remoteSegments, instanceId];
    for (final segment in segments) {
      var ok = await ftp.changeDirectory(segment);
      if (!ok) {
        ok = await ftp.makeDirectory(segment);
        if (ok) {
          ok = await ftp.changeDirectory(segment);
        }
      }
      if (!ok) {
        throw StateError('FTP 目录不可用或无法创建：$segment');
      }
    }
  }

  /// 拼接远程路径（用于展示与判断）。
  String remoteFilePath(String instanceId, String fileName) {
    final base = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return p.posix.join(base, instanceId, fileName);
  }

  String remoteDirPath(String instanceId) => p.posix.join(
        remotePath.startsWith('/') ? remotePath : '/$remotePath',
        instanceId,
      );

  @override
  Future<bool> testConnection() async {
    try {
      await _withConnection((ftp) async {
        // 连通性与登录验证：目录不存在会在后续 ensureDir/upload 时自动创建。
        await ftp.listDirectoryContent();
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureDir(String instanceId) async {
    await _withConnection((ftp) => _navigateTo(ftp, instanceId));
  }

  @override
  Future<void> upload(
    File localFile,
    String instanceId,
    String fileName,
  ) async {
    await _withConnection((ftp) async {
      await _navigateTo(ftp, instanceId);
      // zip 二进制数据必须用二进制模式传输，否则会被损坏。
      await ftp.setTransferType(TransferType.binary);
      final ok = await ftp.uploadFile(localFile, sRemoteName: fileName);
      if (!ok) {
        throw StateError('FTP 上传失败：$fileName');
      }
    });
  }

  @override
  Future<List<String>> listFiles(String instanceId) async {
    try {
      return await _withConnection((ftp) async {
        await _navigateTo(ftp, instanceId);
        final entries = await ftp.listDirectoryContent();
        return entries
            .where((e) => e.name.endsWith('.zip'))
            .map((e) => e.name)
            .toList();
      });
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> delete(String instanceId, String fileName) async {
    await _withConnection((ftp) async {
      await _navigateTo(ftp, instanceId);
      final ok = await ftp.deleteFile(fileName);
      if (!ok) {
        throw StateError('FTP 删除失败：$fileName');
      }
    });
  }
}