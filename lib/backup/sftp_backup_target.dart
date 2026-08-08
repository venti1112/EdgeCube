import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'backup_target.dart';

/// SFTP 远程备份目标（SSH 文件传输协议）。
///
/// 使用 `dartssh2` 自带的 [SftpClient]。每次操作都建立独立 SSH 连接执行
/// 后关闭，避免连接泄漏。
///
/// 主机密钥采用「首次信任（TOFU）」策略：已记录在 [trustedHostKeys] 的
/// 指纹必须匹配，否则连接失败；未知指纹会调用 [onUnknownHostKey] 询问
/// 用户是否信任（SSH 通常约定指纹显示为 `SHA256:...`）。
class SftpBackupTarget implements BackupTarget {
  SftpBackupTarget({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remotePath,
    this.trustedHostKeys = const {},
    this.onUnknownHostKey,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;

  /// key: `host:port`，value: 已信任的 `SHA256:...` 指纹。
  final Map<String, String> trustedHostKeys;

  /// 遇到未信任主机密钥时的回调（用于弹窗确认）。返回 true 表示信任并连接。
  final Future<bool> Function(String fingerprint)? onUnknownHostKey;

  String get _hostKeyKey => '$host:$port';

  /// 校验主机密钥：已信任则比对；未知则询问用户。
  Future<bool> _verifyHostKey(String type, Uint8List fingerprintBytes) async {
    final fingerprint = utf8.decode(fingerprintBytes, allowMalformed: true);
    final saved = trustedHostKeys[_hostKeyKey];
    if (saved != null) {
      return saved == fingerprint;
    }
    // 首次连接：交给调用方（如设置页）弹窗确认。
    return await onUnknownHostKey?.call(fingerprint) ?? false;
  }

  /// 建立 SSH 连接并返回已认证的客户端；失败时抛出异常。
  Future<SSHClient> _openClient() async {
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      onVerifyHostKey: _verifyHostKey,
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  /// 在独立连接中执行 [action]，结束后关闭连接。
  Future<T> _withSsh<T>(Future<T> Function(SftpClient sftp) action) async {
    final client = await _openClient();
    final sftp = await client.sftp();
    try {
      return await action(sftp);
    } finally {
      try {
        await sftp.close();
      } catch (_) {}
      client.close();
    }
  }

  /// 拼接远程路径。
  String _remoteFilePath(String instanceId, String fileName) {
    final base = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return p.posix.join(base, instanceId, fileName);
  }

  String _remoteDirPath(String instanceId) {
    final base = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return p.posix.join(base, instanceId);
  }

  String _remoteRootPath() {
    return remotePath.startsWith('/') ? remotePath : '/$remotePath';
  }

  /// 逐段创建目录（sftp 的 mkdir 只创建单层）。
  Future<void> _mkdirAll(SftpClient sftp, String path) async {
    final builder = StringBuffer('/');
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      builder.write(segment);
      final dir = builder.toString();
      try {
        await sftp.stat(dir);
      } catch (_) {
        try {
          await sftp.mkdir(dir);
        } catch (_) {
          // 可能为并发创建或权限问题，留给后续操作报错。
        }
      }
      builder.write('/');
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      await _withSsh((sftp) async {
        try {
          await sftp.listdir(_remoteRootPath());
        } catch (_) {
          // 远程目录可能尚不存在，备份时会自动创建。
          await sftp.listdir('/');
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureDir(String instanceId) async {
    await _withSsh((sftp) => _mkdirAll(sftp, _remoteDirPath(instanceId)));
  }

  @override
  Future<void> upload(
    File localFile,
    String instanceId,
    String fileName,
  ) async {
    await _withSsh((sftp) async {
      await _mkdirAll(sftp, _remoteDirPath(instanceId));
      final remote = await sftp.open(
        _remoteFilePath(instanceId, fileName),
        mode: SftpFileOpenMode.write,
      );
      try {
        final writer = remote.write(localFile.openRead().cast<Uint8List>());
        await writer.done;
        await remote.close();
      } catch (e) {
        try {
          await remote.close();
        } catch (_) {}
        rethrow;
      }
    });
  }

  @override
  Future<List<String>> listFiles(String instanceId) async {
    try {
      return await _withSsh((sftp) async {
        final names = await sftp.listdir(_remoteDirPath(instanceId));
        return names
            .map((e) => e.filename)
            .where((n) => n.endsWith('.zip'))
            .toList();
      });
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> delete(String instanceId, String fileName) async {
    await _withSsh(
      (sftp) => sftp.remove(_remoteFilePath(instanceId, fileName)),
    );
  }
}