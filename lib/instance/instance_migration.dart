import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/storage_permission.dart';
import 'instance_store.dart';

class InstanceMigrationResult {
  const InstanceMigrationResult({
    required this.migrated,
    required this.skipped,
    required this.failed,
    required this.sourcePath,
    required this.targetPath,
    this.error,
  });

  final int migrated;
  final int skipped;
  final int failed;
  final String sourcePath;
  final String targetPath;
  final Object? error;

  bool get hasWork => migrated > 0 || skipped > 0 || failed > 0;
  bool get success => failed == 0 && error == null;
}

class InstanceMigration {
  InstanceMigration._();

  static const int autoMigrateMaxBuild = 6;

  static bool shouldAutoMigrateFrom(String? lastVersion) {
    final build = _buildNumberFromVersion(lastVersion);
    return build != null && build <= autoMigrateMaxBuild;
  }

  static Future<InstanceMigrationResult> migrateLegacyInstances({
    void Function(int processed, int total)? onProgress,
  }) async {
    final source = await legacyPrivateInstancesRoot();
    final target = await defaultInstancesRoot();
    if (p.equals(p.normalize(source.path), p.normalize(target.path))) {
      return InstanceMigrationResult(
        migrated: 0,
        skipped: 0,
        failed: 0,
        sourcePath: source.path,
        targetPath: target.path,
      );
    }
    if (!await source.exists()) {
      return InstanceMigrationResult(
        migrated: 0,
        skipped: 0,
        failed: 0,
        sourcePath: source.path,
        targetPath: target.path,
      );
    }
    final entries = await source.list(followLinks: false).toList();
    if (entries.isEmpty) {
      return InstanceMigrationResult(
        migrated: 0,
        skipped: 0,
        failed: 0,
        sourcePath: source.path,
        targetPath: target.path,
      );
    }
    if (Platform.isAndroid && !await StoragePermission.isGranted()) {
      return InstanceMigrationResult(
        migrated: 0,
        skipped: 0,
        failed: entries.length,
        sourcePath: source.path,
        targetPath: target.path,
        error: const FileSystemException('Storage permission denied'),
      );
    }

    var migrated = 0;
    var skipped = 0;
    var failed = 0;
    Object? firstError;
    await target.create(recursive: true);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final dest = p.join(target.path, p.basename(entry.path));
      try {
        final changed = await _migrateEntry(entry, dest);
        if (changed) {
          migrated++;
        } else {
          skipped++;
        }
      } catch (error) {
        failed++;
        firstError ??= error;
      } finally {
        onProgress?.call(i + 1, entries.length);
      }
    }

    if (failed == 0 && skipped == 0) {
      await _deleteEmptyDirectory(source);
    }

    return InstanceMigrationResult(
      migrated: migrated,
      skipped: skipped,
      failed: failed,
      sourcePath: source.path,
      targetPath: target.path,
      error: firstError,
    );
  }

  static int? _buildNumberFromVersion(String? version) {
    if (version == null || version.isEmpty) return null;
    final plus = version.lastIndexOf('+');
    if (plus < 0 || plus == version.length - 1) return null;
    return int.tryParse(version.substring(plus + 1));
  }

  static Future<bool> _migrateEntry(
    FileSystemEntity source,
    String destPath,
  ) async {
    final sourceType = FileSystemEntity.typeSync(source.path);
    final destType = FileSystemEntity.typeSync(destPath);
    if (destType == FileSystemEntityType.notFound) {
      try {
        await source.rename(destPath);
        return true;
      } on FileSystemException {
        await _copyEntityToFinal(source.path, destPath);
        await source.delete(recursive: true);
        return true;
      }
    }

    if (sourceType == FileSystemEntityType.directory &&
        destType == FileSystemEntityType.directory) {
      await _mergeDirectory(Directory(source.path), Directory(destPath));
      await source.delete(recursive: true);
      return true;
    }
    if (sourceType == FileSystemEntityType.file &&
        destType == FileSystemEntityType.file) {
      if (await File(source.path).length() != await File(destPath).length()) {
        await _copyEntityToFinal(source.path, destPath, replace: true);
      }
      await source.delete();
      return true;
    }
    return false;
  }

  static Future<void> _copyEntity(String sourcePath, String targetPath) async {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).create(recursive: true);
      await for (final child in Directory(
        sourcePath,
      ).list(followLinks: false)) {
        await _copyEntity(
          child.path,
          p.join(targetPath, p.basename(child.path)),
        );
      }
    } else if (type == FileSystemEntityType.file) {
      await File(sourcePath).copy(targetPath);
    }
  }

  static Future<void> _copyEntityToFinal(
    String sourcePath,
    String targetPath, {
    bool replace = false,
  }) async {
    final tempPath = _tempPathFor(targetPath);
    await _deleteIfCreated(tempPath);
    await _copyEntity(sourcePath, tempPath);
    if (replace) await _deleteIfCreated(targetPath);
    await _renameEntity(tempPath, targetPath);
  }

  static Future<void> _renameEntity(String sourcePath, String targetPath) {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      return Directory(sourcePath).rename(targetPath).then((_) {});
    }
    return File(sourcePath).rename(targetPath).then((_) {});
  }

  static Future<void> _mergeDirectory(
    Directory source,
    Directory target,
  ) async {
    await target.create(recursive: true);
    await for (final child in source.list(followLinks: false)) {
      final destPath = p.join(target.path, p.basename(child.path));
      final sourceType = FileSystemEntity.typeSync(child.path);
      final destType = FileSystemEntity.typeSync(destPath);
      if (destType == FileSystemEntityType.notFound) {
        await _copyEntityToFinal(child.path, destPath);
        await child.delete(recursive: true);
        continue;
      }
      if (sourceType == FileSystemEntityType.directory &&
          destType == FileSystemEntityType.directory) {
        await _mergeDirectory(Directory(child.path), Directory(destPath));
        await child.delete(recursive: true);
      } else if (sourceType == FileSystemEntityType.file &&
          destType == FileSystemEntityType.file &&
          await File(child.path).length() != await File(destPath).length()) {
        await _copyEntityToFinal(child.path, destPath, replace: true);
        await child.delete();
      } else if (sourceType == FileSystemEntityType.file &&
          destType == FileSystemEntityType.file) {
        await child.delete();
      }
    }
  }

  static String _tempPathFor(String targetPath) {
    return p.join(
      p.dirname(targetPath),
      '.${p.basename(targetPath)}.migrating',
    );
  }

  static Future<void> _deleteIfCreated(String path) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  static Future<void> _deleteEmptyDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    final entries = await dir.list(followLinks: false).take(1).toList();
    if (entries.isEmpty) await dir.delete();
  }
}
