import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'modrinth_service.dart';

/// 下载任务状态。
enum DownloadTaskStatus { pending, downloading, completed, failed, cancelled }

/// 单个下载任务。
///
/// 参考 PCL-CE 的 DownloadTask，保存下载所需的全部信息，
/// 使其不依赖任何 BuildContext / Widget 生命周期。
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.destPath,
    required this.filename,
    required this.projectTitle,
    required this.versionName,
    this.iconUrl,
    this.replacePath,
    this.onComplete,
  });

  final String id;
  final String url;
  final String destPath;
  final String filename;
  final String projectTitle;
  final String versionName;
  final String? iconUrl;

  /// 更新模组时，要替换的旧文件路径。为 null 表示新增下载。
  final String? replacePath;

  /// 下载完成（无论成功失败）后回调，不持有 BuildContext。
  final VoidCallback? onComplete;

  DownloadTaskStatus status = DownloadTaskStatus.pending;
  double progress = 0; // 0~1，-1 表示未知大小
  String? error;
}

/// 全局后台下载队列（单例）。
///
/// 参考 PCL-CE 的 DownloadManager，任务依次执行，不依赖页面生命周期。
/// UI 通过 [addListener] / [removeListener]（ChangeNotifier）监听状态变化。
class DownloadQueue extends ChangeNotifier {
  DownloadQueue._();
  static final DownloadQueue instance = DownloadQueue._();

  final List<DownloadTask> _tasks = [];
  DownloadTask? _current;
  bool _processing = false;

  /// 取消标志，用于中断正在下载的任务。
  final Set<String> _cancelledIds = {};

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  DownloadTask? get current => _current;
  bool get isProcessing => _processing;

  int get pendingCount =>
      _tasks.where((t) => t.status == DownloadTaskStatus.pending).length;
  int get completedCount =>
      _tasks.where((t) => t.status == DownloadTaskStatus.completed).length;
  int get failedCount =>
      _tasks.where((t) => t.status == DownloadTaskStatus.failed).length;

  /// 是否有活跃任务（下载中或等待中）。
  bool get hasActiveTasks => _current != null || pendingCount > 0;

  /// 将任务加入队列，返回任务 ID。
  ///
  /// 如果已有相同目标路径的活跃任务（等待中/下载中）或已完成任务，
  /// 不会重复添加，返回已有任务 ID。
  String enqueue({
    required String url,
    required String destPath,
    required String filename,
    required String projectTitle,
    required String versionName,
    String? iconUrl,
    String? replacePath,
    VoidCallback? onComplete,
  }) {
    // 去重：已有相同 destPath 的活跃任务则跳过
    final existing = _tasks
        .where(
          (t) =>
              t.destPath == destPath &&
              (t.status == DownloadTaskStatus.pending ||
                  t.status == DownloadTaskStatus.downloading),
        )
        .firstOrNull;
    if (existing != null) return existing.id;

    // 去重：已完成且文件存在则跳过
    final completed = _tasks
        .where(
          (t) =>
              t.destPath == destPath &&
              t.status == DownloadTaskStatus.completed,
        )
        .firstOrNull;
    if (completed != null && File(destPath).existsSync()) {
      return completed.id;
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final task = DownloadTask(
      id: id,
      url: url,
      destPath: destPath,
      filename: filename,
      projectTitle: projectTitle,
      versionName: versionName,
      iconUrl: iconUrl,
      replacePath: replacePath,
      onComplete: onComplete,
    );
    _tasks.add(task);
    notifyListeners();
    _processNext();
    return id;
  }

  /// 取消指定任务。正在下载的任务会被中断并删除临时文件。
  void cancel(String taskId) {
    final task = _tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    if (task.status == DownloadTaskStatus.pending ||
        task.status == DownloadTaskStatus.downloading) {
      _cancelledIds.add(taskId);
      task.status = DownloadTaskStatus.cancelled;
      notifyListeners();
    }
  }

  /// 取消所有任务。
  void cancelAll() {
    for (final task in _tasks) {
      if (task.status == DownloadTaskStatus.pending ||
          task.status == DownloadTaskStatus.downloading) {
        _cancelledIds.add(task.id);
        task.status = DownloadTaskStatus.cancelled;
      }
    }
    notifyListeners();
  }

  /// 从列表中移除已结束的任务（完成/失败/取消）。
  void removeFinished() {
    _tasks.removeWhere(
      (t) =>
          t.status == DownloadTaskStatus.completed ||
          t.status == DownloadTaskStatus.failed ||
          t.status == DownloadTaskStatus.cancelled,
    );
    notifyListeners();
  }

  /// 移除单个任务（仅允许已结束的）。
  void remove(String taskId) {
    final task = _tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return;
    if (task.status == DownloadTaskStatus.pending ||
        task.status == DownloadTaskStatus.downloading) {
      return; // 进行中的不允许直接移除
    }
    _tasks.remove(task);
    notifyListeners();
  }

  Future<void> _processNext() async {
    if (_processing) return;
    _processing = true;

    while (true) {
      final task = _tasks
          .where((t) => t.status == DownloadTaskStatus.pending)
          .firstOrNull;
      if (task == null) break;

      _current = task;
      task.status = DownloadTaskStatus.downloading;
      task.progress = 0;
      task.error = null;
      notifyListeners();

      final isUpdate = task.replacePath != null;
      final downloadPath = isUpdate ? '${task.destPath}.dltmp' : task.destPath;

      try {
        await ModrinthService.downloadFile(
          task.url,
          downloadPath,
          onProgress: (received, total) {
            if (total != null && total > 0) {
              task.progress = received / total;
            } else {
              task.progress = -1;
            }
            notifyListeners();
          },
          isCancelled: () => _cancelledIds.contains(task.id),
        );

        // 下载被取消：清理临时文件
        if (_cancelledIds.contains(task.id)) {
          _cancelledIds.remove(task.id);
          try {
            await File(downloadPath).delete();
          } catch (_) {}
          notifyListeners();
          continue;
        }

        // 更新模组：替换旧文件
        if (isUpdate) {
          try {
            await File(task.replacePath!).delete();
          } catch (_) {}
          await File(downloadPath).rename(task.destPath);
        }

        task.status = DownloadTaskStatus.completed;
        task.progress = 1;
        notifyListeners();
      } catch (e) {
        if (_cancelledIds.contains(task.id)) {
          _cancelledIds.remove(task.id);
          try {
            await File(downloadPath).delete();
          } catch (_) {}
        } else {
          task.status = DownloadTaskStatus.failed;
          task.error = '$e';
        }
        notifyListeners();
      } finally {
        task.onComplete?.call();
      }
    }

    _current = null;
    _processing = false;
    notifyListeners();
  }
}
