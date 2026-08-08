import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config_store.dart';

/// 单个文件的清单条目：记录 size 与最后修改时间，用于增量变更检测。
class FileEntry {
  const FileEntry({required this.size, required this.mtime});

  final int size;
  final int mtime;

  Map<String, dynamic> toJson() => {'size': size, 'mtime': mtime};

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      size: json['size'] as int? ?? 0,
      mtime: json['mtime'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FileEntry && other.size == size && other.mtime == mtime;

  @override
  int get hashCode => Object.hash(size, mtime);
}

/// 增量备份对比结果：新增/修改的文件与已删除的文件。
class BackupChangeSet {
  const BackupChangeSet({this.addedOrModified = const [], this.deleted = const []});

  final List<String> addedOrModified;
  final List<String> deleted;

  bool get isEmpty => addedOrModified.isEmpty && deleted.isEmpty;
}

/// 实例的备份文件清单。
///
/// 记录上次备份时各文件（相对路径）的 size/mtime，用于增量备份时检测变更。
/// 存储于 `config/backup_manifests/<instanceId>.json`。
class BackupManifest {
  BackupManifest({
    required this.instanceId,
    required this.baseBackupTime,
    required this.incrementalCount,
    required Map<String, FileEntry> files,
  }) : files = Map.unmodifiable(files);

  final String instanceId;
  final int baseBackupTime;
  final int incrementalCount;
  final Map<String, FileEntry> files;

  /// 构造空清单（用于强制完整备份）。
  factory BackupManifest.empty(String instanceId) {
    return BackupManifest(
      instanceId: instanceId,
      baseBackupTime: 0,
      incrementalCount: 0,
      files: const {},
    );
  }

  bool get isEmpty => files.isEmpty && baseBackupTime == 0;

  /// 对比当前扫描结果与清单，返回变更集。
  BackupChangeSet diff(Map<String, FileEntry> current) {
    final added = <String>[];
    final deleted = <String>[];

    for (final entry in current.entries) {
      final old = files[entry.key];
      if (old == null || old != entry.value) {
        added.add(entry.key);
      }
    }
    for (final key in files.keys) {
      if (!current.containsKey(key)) {
        deleted.add(key);
      }
    }

    return BackupChangeSet(addedOrModified: added, deleted: deleted);
  }

  /// 返回以 [current] 为新状态、[baseBackupTime] 与 [incrementalCount] 递增后的清单。
  BackupManifest withIncremental(Map<String, FileEntry> current) {
    return BackupManifest(
      instanceId: instanceId,
      baseBackupTime: baseBackupTime,
      incrementalCount: incrementalCount + 1,
      files: current,
    );
  }

  /// 返回以 [current] 为新状态、重置为新完整备份基底的清单。
  BackupManifest withFull(Map<String, FileEntry> current, int backupTime) {
    return BackupManifest(
      instanceId: instanceId,
      baseBackupTime: backupTime,
      incrementalCount: 0,
      files: current,
    );
  }

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'baseBackupTime': baseBackupTime,
        'incrementalCount': incrementalCount,
        'files': {for (final e in files.entries) e.key: e.value.toJson()},
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['files'];
    final files = <String, FileEntry>{};
    if (filesRaw is Map) {
      for (final entry in filesRaw.entries) {
        final key = entry.key.toString();
        if (entry.value is Map<String, dynamic>) {
          files[key] = FileEntry.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }
    return BackupManifest(
      instanceId: json['instanceId'] as String? ?? '',
      baseBackupTime: json['baseBackupTime'] as int? ?? 0,
      incrementalCount: json['incrementalCount'] as int? ?? 0,
      files: files,
    );
  }

  // ── 持久化 ────────────────────────────────────────────────

  static Future<File> _manifestFile(String instanceId) async {
    final dir = await _manifestDir();
    return File(p.join(dir.path, '$instanceId.json'));
  }

  static Future<Directory> _manifestDir() async {
    final configDir = await ConfigStore.configDir();
    final dir = Directory(p.join(configDir.path, 'backup_manifests'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 加载实例清单；文件缺失或损坏时返回空清单（触发完整备份）。
  static Future<BackupManifest> load(String instanceId) async {
    try {
      final file = await _manifestFile(instanceId);
      if (!await file.exists()) return BackupManifest.empty(instanceId);
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return BackupManifest.empty(instanceId);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return BackupManifest.empty(instanceId);
      }
      return BackupManifest.fromJson(decoded);
    } catch (_) {
      return BackupManifest.empty(instanceId);
    }
  }

  /// 原子写入实例清单。
  static Future<void> save(BackupManifest manifest) async {
    final file = await _manifestFile(manifest.instanceId);
    await ConfigStore.writeJsonFile(file, manifest.toJson());
  }

  /// 删除实例清单文件，使下次备份强制为全量备份。
  static Future<void> delete(String instanceId) async {
    try {
      final file = await _manifestFile(instanceId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ── 目录扫描 ──────────────────────────────────────────────

  /// 递归扫描目录，返回相对路径 → [FileEntry] 映射。
  ///
  /// 跳过隐藏文件（`.` 开头）与符号链接。
  static Future<Map<String, FileEntry>> scanDirectory(Directory dir) async {
    final result = <String, FileEntry>{};
    if (!await dir.exists()) return result;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      try {
        final stat = await entity.stat();
        if (stat.type == FileSystemEntityType.link) continue;
        final relative = p.relative(entity.path, from: dir.path);
        result[relative] = FileEntry(
          size: stat.size,
          mtime: stat.modified.millisecondsSinceEpoch,
        );
      } catch (_) {
        // 单个文件 stat 失败跳过，不影响整体扫描
      }
    }
    return result;
  }
}
