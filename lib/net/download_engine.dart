import 'dart:async';
import 'dart:io';

import 'package:downloadx/downloadx.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../online/cloud_headers.dart';
import 'download_exceptions.dart';
import 'download_hash.dart';

/// 统一下载进度快照。
///
/// [percent] 语义在 downloadx 内部为 0..100 且可空，这里统一用 [fraction]
/// （0..1，未知为 -1）对齐项目既有的进度约定，并额外携带速度与剩余时间。
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    this.speedBytesPerSec = 0,
    this.etaMs,
  });

  /// 已下载字节数。
  final int receivedBytes;

  /// 总字节数；null 表示未知（服务器未返回 Content-Length）。
  final int? totalBytes;

  /// 当前聚合下载速度（字节/秒）。
  final double speedBytesPerSec;

  /// 预计剩余毫秒；null 表示未知。
  final int? etaMs;

  /// 是否已知总大小。
  bool get hasTotal => totalBytes != null && totalBytes! > 0;

  /// 进度比例 0..1；未知总大小时为 -1（对齐既有 `progress = -1` 约定）。
  double get fraction => hasTotal ? receivedBytes / totalBytes! : -1;
}

/// 全局统一下载引擎（单例）。
///
/// 基于 [downloadx](https://pub.dev/packages/downloadx) 做分片并行下载、断点续传、
/// 分片级重试与全局 UA/并发管理，对上层暴露命令式的 [Future] API，可近乎
/// drop-in 替换项目中原有的 `openWrite + 流式` 下载函数。
///
/// 关键设计：
/// - downloadx 始终在**内部缓存目录**（与其 `.part`/meta 同卷）内完成下载，
///   引擎再把产物搬运到最终 [destPath]，天然规避实例目录可能在外置卷导致的
///   跨卷 `rename`（EXDEV）失败。
/// - 事件流经 [Completer] 桥接回 Future；`isCancelled` 轮询回调经 [Timer]
///   桥接到 `download` 的取消。
/// - downloadx 无内容校验，完成后由引擎在 isolate 中算 sha1/sha256。
class DownloadEngine {
  DownloadEngine._();

  /// 全局单例。
  static final DownloadEngine instance = DownloadEngine._();

  /// 软件日志（文件 + logcat），记录下载开始/完成/失败。
  static final Logger _log = Logger('DownloadEngine');

  DownloadX? _manager;
  Future<void>? _initFuture;
  Directory? _cacheRoot;
  int _seq = 0;

  /// 懒初始化全局 manager（并发安全：多次调用共享同一 Future）。
  Future<void> ensureInitialized() => _initFuture ??= _init();

  Future<void> _init() async {
    final tmp = await getTemporaryDirectory();
    final root = Directory(p.join(tmp.path, 'downloadx'));
    await root.create(recursive: true);
    _cacheRoot = root;

    Map<String, String> headers;
    try {
      headers = await CloudHeaders.base();
    } catch (_) {
      headers = {'User-Agent': 'EdgeCube'};
    }

    _manager = await createDownloadX(
      DownloadXConfig(
        targetPath: root.path,
        cachePath: root.path,
        maxParallel: 3,
        targetChunkCount: 4,
        minChunkSize: 1024 * 1024,
        headers: headers,
        journal: false,
      ),
    );

    await _clearOrphans();
  }

  /// 清理上次会话遗留的孤儿文件（崩溃残留的 `.part`/meta/产物）。
  ///
  /// one-shot 下载不需要跨会话续传，`createDownloadX` 恢复的任务一律清除。
  Future<void> _clearOrphans() async {
    try {
      await _manager?.clear();
    } catch (_) {}
    final root = _cacheRoot;
    if (root == null) return;
    try {
      await for (final entity in root.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  String _nextId() => 'ec${DateTime.now().microsecondsSinceEpoch}x${_seq++}';

  /// 下载单个文件到 [destPath]（完整路径）。
  ///
  /// - [onProgress]：进度回调，携带速度/剩余时间/已下载/总大小。
  /// - [isCancelled]：轮询式取消，返回 true 时中断并清理。
  /// - [headers]：本次下载附加请求头（与全局 UA 合并）。
  /// - [sha1]/[sha256]：若提供，下载完成后校验，不匹配则删文件抛
  ///   [DownloadHashMismatch]。
  /// - [expectedSize]：无哈希时的兜底大小校验。
  ///
  /// 失败时抛 [DownloadHttpError] / [DownloadHashMismatch] / [DownloadCancelled]
  /// / [DownloadFailed]。
  Future<void> downloadToFile(
    String url,
    String destPath, {
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
    Map<String, String>? headers,
    String? sha1,
    String? sha256,
    int? expectedSize,
  }) async {
    await ensureInitialized();
    final manager = _manager!;
    final root = _cacheRoot!;

    if (isCancelled?.call() == true) throw const DownloadCancelled();
    _log.info('Download start: $url -> $destPath');

    final id = _nextId();
    final producedName = '$id.out';
    final producedPath = p.join(root.path, producedName);

    final download = await manager.addUrl(
      url,
      DownloadOptions(
        id: id,
        filename: producedName,
        targetPath: root.path,
        headers: headers,
      ),
    );

    final completer = Completer<void>();
    final disposers = <void Function()>[];
    Timer? cancelTimer;

    void cleanup() {
      for (final dispose in disposers) {
        dispose();
      }
      cancelTimer?.cancel();
    }

    final speedSamples = <(int receivedBytes, DateTime time)>[];
    disposers.add(
      download.emitter.onType<ProgressEvent>((e) {
        if (completer.isCompleted) return;

        final now = DateTime.now();
        speedSamples.add((e.downloadedBytes, now));
        final cutoff = now.subtract(const Duration(seconds: 3));
        speedSamples.removeWhere((s) => s.$2.isBefore(cutoff));

        double speed;
        int? etaMs;
        if (speedSamples.length >= 2) {
          final dt = speedSamples.last.$2
              .difference(speedSamples.first.$2)
              .inMilliseconds;
          final dBytes = speedSamples.last.$1 - speedSamples.first.$1;
          if (dt > 0 && dBytes > 0) {
            speed = dBytes * 1000.0 / dt;
            if (e.totalBytes != null && e.totalBytes! > 0) {
              final remaining = e.totalBytes! - e.downloadedBytes;
              if (remaining > 0) {
                etaMs = (remaining / speed * 1000).round();
              }
            }
          } else {
            speed = 0;
          }
        } else {
          speed = 0;
        }

        onProgress?.call(
          DownloadProgress(
            receivedBytes: e.downloadedBytes,
            totalBytes: e.totalBytes,
            speedBytesPerSec: speed,
            etaMs: etaMs,
          ),
        );
      }),
    );

    disposers.add(
      download.emitter.onType<CompletedEvent>((e) {
        if (!completer.isCompleted) completer.complete();
      }),
    );

    // 携带 error 对象的事件优先（可映射 HTTP 状态码）。
    disposers.add(
      download.emitter.onType<ErrorEvent>((e) {
        if (!e.fatal || completer.isCompleted) return;
        final err = e.error;
        completer.completeError(
          err is HttpStatusError
              ? DownloadHttpError(err.status)
              : DownloadFailed(err),
        );
      }),
    );

    // 兜底：部分失败路径（分片重试耗尽）只 setState 不 emit ErrorEvent。
    // 用 microtask 延迟，给同步的 ErrorEvent 先完成的机会（保留状态码映射）。
    disposers.add(
      download.emitter.onType<StateChangeEvent>((e) {
        if (e.current == DownloadState.cancelled) {
          if (!completer.isCompleted) {
            completer.completeError(const DownloadCancelled());
          }
        } else if (e.current == DownloadState.error) {
          Future.microtask(() {
            if (!completer.isCompleted) {
              completer.completeError(
                DownloadFailed(download.meta.errorMessage ?? 'download error'),
              );
            }
          });
        }
      }),
    );

    if (isCancelled != null) {
      cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (completer.isCompleted) return;
        if (isCancelled()) {
          completer.completeError(const DownloadCancelled());
        }
      });
    }

    try {
      await manager.start(id); // 遵守 maxParallel 队列，仅触发不等完成
      await completer.future; // 等 CompletedEvent / 失败 / 取消
      cleanup();

      await _verifyHash(producedPath, sha1: sha1, sha256: sha256);
      if (sha1 == null && sha256 == null && expectedSize != null) {
        await _verifySize(producedPath, expectedSize);
      }

      await _moveTo(producedPath, destPath);
      try {
        _log.info(
          'Download complete: $url -> $destPath '
          '(${await File(destPath).length()} bytes)',
        );
      } catch (_) {}
    } catch (e) {
      _log.warning('Download failed: $url -> $destPath', e);
      cleanup();
      await _safeDelete(producedPath);
      rethrow;
    } finally {
      cleanup();
      // 统一清理：取消/失败时 cancel 并删 part/meta；成功时删残留 meta。
      try {
        await manager.clear(id);
      } catch (_) {}
      await _safeDelete(producedPath);
    }
  }

  /// 多源顺序回退下载：逐个尝试 [urls]，任一成功（含校验通过）即返回；
  /// 取消不再重试。全部失败时抛最后一个错误。
  Future<void> downloadToFileMultiSource(
    List<String> urls,
    String destPath, {
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
    Map<String, String>? headers,
    String? sha1,
    String? sha256,
    int? expectedSize,
  }) async {
    final sources = urls.where((u) => u.isNotEmpty).toList();
    if (sources.isEmpty) {
      throw ArgumentError('downloadToFileMultiSource: no urls');
    }
    Object? lastError;
    for (final url in sources) {
      if (isCancelled?.call() == true) throw const DownloadCancelled();
      try {
        await downloadToFile(
          url,
          destPath,
          onProgress: onProgress,
          isCancelled: isCancelled,
          headers: headers,
          sha1: sha1,
          sha256: sha256,
          expectedSize: expectedSize,
        );
        return;
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        _log.warning('Source failed, trying next: $url', e);
        lastError = e;
      }
    }
    throw lastError ?? const DownloadFailed('all sources failed');
  }

  Future<void> _verifyHash(String path, {String? sha1, String? sha256}) async {
    if (sha1 != null) {
      final actual = await computeFileSha1(path);
      if (actual.toLowerCase() != sha1.toLowerCase()) {
        await _safeDelete(path);
        throw DownloadHashMismatch(expected: sha1, actual: actual);
      }
    } else if (sha256 != null) {
      final actual = await computeFileSha256(path);
      if (actual.toLowerCase() != sha256.toLowerCase()) {
        await _safeDelete(path);
        throw DownloadHashMismatch(expected: sha256, actual: actual);
      }
    }
  }

  Future<void> _verifySize(String path, int expectedSize) async {
    final actual = await File(path).length();
    if (actual != expectedSize) {
      await _safeDelete(path);
      throw DownloadFailed(
        'size mismatch: expected $expectedSize, found $actual',
      );
    }
  }

  /// 把内部产物搬运到最终路径，处理跨卷（EXDEV）：先尝试同卷 `rename`，
  /// 失败则 `copy` + `delete`。
  Future<void> _moveTo(String from, String to) async {
    final dir = Directory(p.dirname(to));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dst = File(to);
    if (await dst.exists()) {
      try {
        await dst.delete();
      } catch (_) {}
    }
    final src = File(from);
    try {
      await src.rename(to);
    } on FileSystemException {
      await src.copy(to);
      try {
        await src.delete();
      } catch (_) {}
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
