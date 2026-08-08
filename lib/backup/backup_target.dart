import 'dart:io';

import 'package:path/path.dart' as p;

/// 备份目标的抽象接口。
///
/// 本地目录与 WebDav 远程目录各提供一个实现，使 [BackupService] 无需关心
/// 底层是文件复制还是网络上传。
abstract class BackupTarget {
  /// 测试连通性（如目录可写 / WebDav 可达）。成功返回 true。
  Future<bool> testConnection();

  /// 确保该实例的备份子目录存在。
  Future<void> ensureDir(String instanceId);

  /// 上传/复制本地文件 [localFile] 到该实例目录下，命名为 [fileName]。
  Future<void> upload(File localFile, String instanceId, String fileName);

  /// 列出该实例目录下已有的备份文件名。
  Future<List<String>> listFiles(String instanceId);

  /// 删除该实例目录下的指定备份文件。
  Future<void> delete(String instanceId, String fileName);
}

/// 本地目录备份目标。
///
/// 在用户选择的本地目录下按实例 id 分子目录存放备份 zip。
class LocalBackupTarget implements BackupTarget {
  LocalBackupTarget(this.basePath);

  final String basePath;

  Directory _instanceDir(String instanceId) =>
      Directory(p.join(basePath, instanceId));

  @override
  Future<bool> testConnection() async {
    try {
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureDir(String instanceId) async {
    final dir = _instanceDir(instanceId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> upload(
    File localFile,
    String instanceId,
    String fileName,
  ) async {
    final dest = File(p.join(basePath, instanceId, fileName));
    await localFile.copy(dest.path);
  }

  @override
  Future<List<String>> listFiles(String instanceId) async {
    final dir = _instanceDir(instanceId);
    if (!await dir.exists()) return [];
    final names = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.zip')) {
        names.add(p.basename(entity.path));
      }
    }
    return names;
  }

  @override
  Future<void> delete(String instanceId, String fileName) async {
    final file = File(p.join(basePath, instanceId, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
