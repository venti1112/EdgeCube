import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../config/download_store.dart';
import '../i18n/i18n_service.dart';
import '../net/download_engine.dart';
import 'modpack/modpack_provider.dart';
import 'modpack/modpack_registry.dart';
import 'modpack/modpack_utils.dart';
import 'modrinth_service.dart';

export 'modpack/modpack_provider.dart'
    show ModpackFormat, ParsedModpack, ModpackFileEntry;
export 'modpack/modpack_utils.dart'
    show InvalidPathException, ModpackParseException;

/// 整合包中单个模组（文件）的下载状态。
enum ModDownloadStatus { pending, downloading, completed, failed, skipped }

/// 下载列表中单个任务的可观测快照（immutable）。
///
/// 由 [ModpackService.downloadServerFiles] 在任务状态变化或进度更新（节流）
/// 时通过 `onTaskUpdate` 回调发出整个列表快照，UI 据此渲染下载列表。
class ModDownloadTask {
  const ModDownloadTask({
    required this.fileName,
    required this.path,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes,
    this.error,
  });

  /// 文件名（basename）。
  final String fileName;

  /// 相对实例根目录的路径。
  final String path;

  final ModDownloadStatus status;

  /// 已下载字节数。
  final int receivedBytes;

  /// 总字节数；null 表示未知。
  final int? totalBytes;

  /// 失败原因（仅 [ModDownloadStatus.failed]）。
  final String? error;

  bool get hasTotal => totalBytes != null && totalBytes! > 0;

  /// 进度比例 0..1；未知总大小时为 -1。
  double get fraction => hasTotal ? receivedBytes / totalBytes! : -1;

  ModDownloadTask copyWith({
    ModDownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    String? error,
  }) => ModDownloadTask(
    fileName: fileName,
    path: path,
    status: status ?? this.status,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    // totalBytes 一旦确定不再置空（场景中不会从有值回退到无值）。
    totalBytes: totalBytes ?? this.totalBytes,
    error: error ?? this.error,
  );
}

/// 整合包解析与安装服务（薄封装）。
///
/// 格式探测/解析委托 [ModpackRegistry]（返回中立 [ParsedModpack]）；本类只
/// 保留跨格式通用的安装步骤（下载服务端文件、展开 overrides）。各格式解析逻辑
/// 见 `lib/mods/modpack/` 下的 provider。
class ModpackService {
  ModpackService._();

  /// 探测并解析整合包。返回 null 表示无可识别清单（普通 zip，调用方直接解压）。
  static Future<ParsedModpack?> detectAndParse(String archivePath) =>
      ModpackRegistry.detectAndParse(archivePath);

  /// 下载整合包中服务端需要的文件到 [destDir]，保持相对路径结构。
  ///
  /// - [onProgress] 回调 (current, total, currentFileName)，用于整体进度。
  /// - [onTaskUpdate] 回调整个任务列表快照，用于渲染下载列表；状态变更立即回调，
  ///   进度更新按每任务 200ms 节流回调。
  /// - [isCancelled] 返回 true 时中断并删除当前不完整文件。
  ///
  /// 并发数取自 [DownloadStore.maxParallel]（与 DownloadEngine 的 maxParallel
  /// 对齐，经由 downloadx 管理器原生 `maxParallel` 队列并发执行）。
  /// 已存在且大小匹配的文件会被跳过，便于失败重试。
  /// 任一文件失败即停止派发新任务并取消在途下载，抛出首个错误。
  static Future<void> downloadServerFiles(
    ParsedModpack modpack,
    Directory destDir, {
    void Function(int current, int total, String currentFile)? onProgress,
    void Function(List<ModDownloadTask> tasks)? onTaskUpdate,
    bool Function()? isCancelled,
  }) async {
    final serverFiles = modpack.serverFiles;
    final total = serverFiles.length;
    if (total == 0) return;

    final concurrency = await DownloadStore.loadMaxParallel();

    // 预处理：构建任务列表与可观测状态快照，跳过已存在/无 URL 的文件标记为 skipped。
    final tasks = <_ModTask>[];
    final states = <ModDownloadTask>[];
    var completed = 0;

    void emitStates() => onTaskUpdate?.call(List.unmodifiable(states));

    for (final file in serverFiles) {
      if (isCancelled?.call() == true) return;
      final relPath = ModpackUtils.safeRelativePath(file.path, destDir);
      final targetPath = p.join(destDir.path, relPath);
      final targetFile = File(targetPath);
      final fileName = p.basename(targetPath);

      if (await targetFile.exists() &&
          file.fileSize != null &&
          (await targetFile.length()) == file.fileSize) {
        completed++;
        states.add(ModDownloadTask(
          fileName: fileName,
          path: relPath,
          status: ModDownloadStatus.skipped,
          receivedBytes: file.fileSize ?? 0,
          totalBytes: file.fileSize,
        ));
        continue;
      }

      await Directory(p.dirname(targetPath)).create(recursive: true);

      if (file.downloads.isEmpty) {
        completed++;
        states.add(ModDownloadTask(
          fileName: fileName,
          path: relPath,
          status: ModDownloadStatus.skipped,
          totalBytes: file.fileSize,
        ));
        continue;
      }

      final stateIndex = states.length;
      states.add(ModDownloadTask(
        fileName: fileName,
        path: relPath,
        status: ModDownloadStatus.pending,
        totalBytes: file.fileSize,
      ));
      tasks.add(_ModTask(file, targetPath, targetFile, stateIndex));
    }
    onProgress?.call(completed, total, '');
    emitStates();

    if (tasks.isEmpty) return;

    // fail-fast：任一文件失败即停止派发新任务，并取消在途下载。
    var failed = false;
    Object? firstError;
    var nextIndex = 0;

    // 内部取消 = 外部取消 或 已失败。
    bool internalCancelled() => failed || (isCancelled?.call() ?? false);

    void patchState(int idx, {ModDownloadStatus? status, int? receivedBytes,
        int? totalBytes, String? error}) {
      final cur = states[idx];
      if (status == cur.status &&
          receivedBytes == null &&
          totalBytes == null &&
          error == null) {
        return;
      }
      states[idx] = cur.copyWith(
        status: status,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        error: error,
      );
      emitStates();
    }

    Future<void> worker() async {
      while (true) {
        if (internalCancelled()) return;
        final i = nextIndex++;
        if (i >= tasks.length) return;
        final task = tasks[i];

        patchState(task.stateIndex, status: ModDownloadStatus.downloading);

        // 进度节流：每任务至多 200ms 回调一次，避免高频进度淹没 UI。
        var lastEmitMs = 0;
        try {
          await DownloadEngine.instance.downloadToFileMultiSource(
            task.file.downloads,
            task.targetPath,
            isCancelled: internalCancelled,
            onProgress: (progress) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - lastEmitMs < 200) return;
              lastEmitMs = now;
              patchState(
                task.stateIndex,
                status: ModDownloadStatus.downloading,
                receivedBytes: progress.receivedBytes,
                totalBytes: progress.totalBytes,
              );
            },
          );

          // 哈希校验（可选）。
          if (task.file.sha1 != null && task.file.sha1!.isNotEmpty) {
            final actual = await ModrinthService.computeSha1(task.targetPath);
            if (actual != task.file.sha1) {
              try {
                await task.targetFile.delete();
              } catch (_) {}
              throw Exception(
                tr('modpack.hashMismatch', {
                  'fileName': p.basename(task.targetPath),
                  'expected': task.file.sha1!,
                  'actual': actual,
                }),
              );
            }
          }
        } catch (e) {
          if (!failed) {
            failed = true;
            firstError = e;
          }
          patchState(
            task.stateIndex,
            status: ModDownloadStatus.failed,
            error: '$e',
          );
          return;
        }

        // 期间已有失败：不计入进度。
        if (failed) return;
        final size = task.file.fileSize;
        patchState(
          task.stateIndex,
          status: ModDownloadStatus.completed,
          receivedBytes: size,
          totalBytes: size,
        );
        completed++;
        onProgress?.call(completed, total, p.basename(task.targetPath));
      }
    }

    final workerCount = concurrency.clamp(1, tasks.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));

    if (failed) throw firstError ?? Exception('modpack download failed');
  }

  /// 展开整合包的 override 目录到 [destDir]（平铺保留相对结构）。
  static Future<int> extractOverrides(
    String archivePath,
    ParsedModpack modpack,
    Directory destDir,
  ) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return ModpackUtils.extractOverrides(
      archive,
      destDir,
      modpack.overridePrefixes,
    );
  }
}

/// 并发下载用的单个模组任务。
class _ModTask {
  _ModTask(this.file, this.targetPath, this.targetFile, this.stateIndex);

  final ModpackFileEntry file;
  final String targetPath;
  final File targetFile;

  /// 在 [downloadServerFiles] 的 `states` 列表中对应的索引，用于回写状态。
  final int stateIndex;
}
