import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:webdav_client_plus/webdav_client_plus.dart';

import 'backup_target.dart';

/// WebDav 远程备份目标。
///
/// 封装 `webdav_client_plus`，按实例 id 在远程目录下分子目录存放备份 zip。
/// 密码为空时使用 noAuth 构造客户端。
class WebDavBackupTarget implements BackupTarget {
  WebDavBackupTarget({
    required this.url,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  final String url;
  final String username;
  final String password;
  final String remotePath;

  WebdavClient? _client;

  WebdavClient get client {
    var c = _client;
    if (c != null) return c;
    final trimmedUrl = url.endsWith('/') ? url : '$url/';
    c = password.isEmpty && username.isEmpty
        ? WebdavClient.noAuth(url: trimmedUrl)
        : WebdavClient.basicAuth(
            url: trimmedUrl,
            user: username,
            pwd: password,
          );
    // 设置超时，避免网络问题导致备份卡死。
    c.setConnectTimeout(15000);
    c.setSendTimeout(60000);
    c.setReceiveTimeout(60000);
    _client = c;
    return c;
  }

  /// 拼接远程路径：`remotePath/instanceId/fileName`，确保以 / 开头。
  String _remoteFilePath(String instanceId, String fileName) {
    final base = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return p.posix.join(base, instanceId, fileName);
  }

  String _remoteDirPath(String instanceId) {
    final base = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return p.posix.join(base, instanceId);
  }

  @override
  Future<bool> testConnection() async {
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureDir(String instanceId) async {
    await client.mkdirAll(_remoteDirPath(instanceId));
  }

  @override
  Future<void> upload(
    File localFile,
    String instanceId,
    String fileName,
  ) async {
    await client.writeFile(
      localFile.path,
      _remoteFilePath(instanceId, fileName),
    );
  }

  @override
  Future<List<String>> listFiles(String instanceId) async {
    try {
      final entries = await client.readDir(_remoteDirPath(instanceId));
      return entries
          .where((e) => !e.isDir && e.name.endsWith('.zip'))
          .map((e) => e.name)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> delete(String instanceId, String fileName) async {
    await client.remove(_remoteFilePath(instanceId, fileName));
  }
}
