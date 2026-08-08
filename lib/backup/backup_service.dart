import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/backup_store.dart';
import '../files/archive_service.dart';
import '../instance/instance_controller.dart';
import 'backup_manifest.dart';
import 'backup_target.dart';

final _log = Logger('BackupService');

/// 增量备份中记录已删除文件清单的元数据文件名（打入 zip 内）。
const String kDeletedManifestName = '__deleted.json';

/// 单次备份运行的结果汇总。
class BackupResult {
  const BackupResult({
    this.total = 0,
    this.backed = 0,
    this.skipped = 0,
    this.failed = 0,
    this.error,
  });

  /// 本次处理的实例总数。
  final int total;

  /// 产生了备份文件的实例数。
  final int backed;

  /// 因无变更而跳过的实例数（仅增量模式）。
  final int skipped;

  /// 备份失败的实例数。
  final int failed;

  /// 整体错误信息（如无可用目标等）。
  final String? error;

  bool get isSuccess => failed == 0 && error == null;
}

/// 核心备份引擎：遍历勾选实例，执行完整/增量备份并上传到目标。
///
/// 无 UI 依赖，由 [BackupController] 调用。
class BackupService {
  BackupService(this._instanceController);

  final InstanceController _instanceController;

  /// 执行一次备份。
  ///
  /// [targets] 为已启用的备份目标列表；[onInstanceProgress] 回调
  /// (当前序号, 总数, 实例名) 用于 UI 进度展示。
  Future<BackupResult> runBackup({
    required List<BackupTarget> targets,
    required BackupMode mode,
    required int retentionSets,
    void Function(int current, int total, String instanceName)?
        onInstanceProgress,
  }) async {
    if (targets.isEmpty) {
      return const BackupResult(error: 'no_target');
    }

    final selectedIds = await BackupStore.loadSelectedInstanceIds();
    // 只备份仍存在的实例（用户可能已删除某些实例）。
    final available = _instanceController.instances;
    final toBackup = available.where((s) => selectedIds.contains(s.id)).toList();

    if (toBackup.isEmpty) {
      return const BackupResult(error: 'no_instance');
    }

    var backed = 0;
    var skipped = 0;
    var failed = 0;
    final total = toBackup.length;

    for (var i = 0; i < toBackup.length; i++) {
      final summary = toBackup[i];
      onInstanceProgress?.call(i + 1, total, summary.name);
      try {
        final result = await _backupInstance(
          summary.id,
          summary.name,
          targets,
          mode,
          retentionSets,
        );
        if (result == _InstanceBackupResult.backed) {
          backed++;
        } else if (result == _InstanceBackupResult.skipped) {
          skipped++;
        }
      } catch (e, s) {
        _log.warning('备份实例 ${summary.name} 失败', e, s);
        failed++;
      }
    }

    return BackupResult(
      total: total,
      backed: backed,
      skipped: skipped,
      failed: failed,
    );
  }

  // ── 单实例备份 ─────────────────────────────────────────────

  Future<_InstanceBackupResult> _backupInstance(
    String instanceId,
    String instanceName,
    List<BackupTarget> targets,
    BackupMode mode,
    int retentionSets,
  ) async {
    final dir = await _instanceController.directoryForId(instanceId);
    if (!await dir.exists()) {
      _log.warning('实例目录不存在，跳过：$instanceId');
      return _InstanceBackupResult.skipped;
    }

    final manifest = await BackupManifest.load(instanceId);

    // 决定本次备份类型：增量次数达到保留组数后强制全量，开启新备份组。
    final forceFull = mode == BackupMode.full ||
        manifest.isEmpty ||
        manifest.incrementalCount >= retentionSets;
    final isFull = forceFull;

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sanitized = _sanitizeName(instanceName, instanceId);
    final typeTag = isFull ? 'full' : 'incr';
    final fileName = '${sanitized}_${typeTag}_$ts.zip';
    final zipPath = p.join(tempDir.path, fileName);

    Map<String, FileEntry>? currentScan;

    if (isFull) {
      // 完整备份：直接压缩整个实例目录。
      await ArchiveService.compress([dir.path], zipPath);
      currentScan = await BackupManifest.scanDirectory(dir);
    } else {
      // 增量备份：扫描 + 对比清单，仅打包变更文件。
      currentScan = await BackupManifest.scanDirectory(dir);
      final changeSet = manifest.diff(currentScan);
      if (changeSet.isEmpty) {
        // 无变更，跳过。
        try {
          await File(zipPath).delete();
        } catch (_) {}
        return _InstanceBackupResult.skipped;
      }
      // 把变更文件复制到临时暂存目录，保留相对路径，再压缩。
      final stagingDir = Directory(p.join(tempDir.path, 'backup_staging_$ts'));
      await _buildStagingDir(dir, stagingDir, changeSet);
      await ArchiveService.compress([stagingDir.path], zipPath);
      // 清理暂存目录。
      await _tryDelete(stagingDir);
    }

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      return _InstanceBackupResult.skipped;
    }

    // 上传/复制到所有目标。
    var successCount = 0;
    for (final target in targets) {
      try {
        await target.ensureDir(instanceId);
        await target.upload(zipFile, instanceId, fileName);
        successCount++;
      } catch (e, s) {
        _log.warning('上传到目标失败（$instanceId / $fileName）', e, s);
      }
    }

    // 清理临时 zip。
    await _tryDelete(zipFile);

    // 至少一个目标成功才更新清单。
    if (successCount > 0) {
      final newManifest = isFull
          ? manifest.withFull(currentScan, ts)
          : manifest.withIncremental(currentScan);
      await BackupManifest.save(newManifest);
      // 执行保留策略。
      for (final target in targets) {
        await _applyRetention(target, instanceId, retentionSets);
      }
      return _InstanceBackupResult.backed;
    }

    return _InstanceBackupResult.failed;
  }

  /// 把变更文件复制到暂存目录，保留相对路径，并写入 `__deleted.json`。
  Future<void> _buildStagingDir(
    Directory sourceDir,
    Directory stagingDir,
    BackupChangeSet changeSet,
  ) async {
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }

    for (final relative in changeSet.addedOrModified) {
      final src = File(p.join(sourceDir.path, relative));
      final dest = File(p.join(stagingDir.path, relative));
      await dest.parent.create(recursive: true);
      try {
        await src.copy(dest.path);
      } catch (e) {
        _log.warning('复制变更文件失败：$relative', e);
      }
    }

    // 写入已删除文件清单。
    if (changeSet.deleted.isNotEmpty) {
      final deletedFile = File(p.join(stagingDir.path, kDeletedManifestName));
      await deletedFile.writeAsString(
        jsonEncode({'deleted': changeSet.deleted}),
      );
    }
  }

  // ── 保留策略 ──────────────────────────────────────────────

  /// 按备份组（1 个 full + 其后续 incr）保留最近 [retentionSets] 组，
  /// 删除更旧的组。
  Future<void> _applyRetention(
    BackupTarget target,
    String instanceId,
    int retentionSets,
  ) async {
    try {
      final files = await target.listFiles(instanceId);
      if (files.length <= retentionSets) return;

      // 解析文件名，提取类型与时间戳。
      final parsed = <_ParsedBackup>[];
      for (final name in files) {
        final parsedItem = _parseBackupName(name);
        if (parsedItem != null) parsed.add(parsedItem);
      }
      // 按时间戳升序排列（最旧在前）。
      parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // 分组：遇到 full 开始新组，incr 归入当前组。
      final groups = <List<_ParsedBackup>>[];
      for (final b in parsed) {
        if (b.isFull || groups.isEmpty) {
          groups.add([b]);
        } else {
          groups.last.add(b);
        }
      }

      // 保留最近 retentionSets 组，删除更旧的。
      if (groups.length <= retentionSets) return;
      final toDelete = groups.length - retentionSets;
      for (var i = 0; i < toDelete; i++) {
        for (final b in groups[i]) {
          try {
            await target.delete(instanceId, b.fileName);
          } catch (e) {
            _log.warning('删除旧备份失败：${b.fileName}', e);
          }
        }
      }
    } catch (e) {
      _log.warning('保留策略执行失败（$instanceId）', e);
    }
  }

  // ── 工具方法 ──────────────────────────────────────────────

  String _sanitizeName(String name, String fallbackId) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? fallbackId : cleaned;
  }

  _ParsedBackup? _parseBackupName(String fileName) {
    final match = RegExp(r'_(full|incr)_(\d+)\.zip$').firstMatch(fileName);
    if (match == null) return null;
    final type = match.group(1)!;
    final ts = int.tryParse(match.group(2)!);
    if (ts == null) return null;
    return _ParsedBackup(
      fileName: fileName,
      isFull: type == 'full',
      timestamp: ts,
    );
  }

  Future<void> _tryDelete(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// 单实例备份的内部结果。
enum _InstanceBackupResult { backed, skipped, failed }

/// 解析后的备份文件名信息。
class _ParsedBackup {
  const _ParsedBackup({
    required this.fileName,
    required this.isFull,
    required this.timestamp,
  });

  final String fileName;
  final bool isFull;
  final int timestamp;
}
