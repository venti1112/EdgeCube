import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 归档压缩/解压的平台通道封装。
///
/// 实际解压在 Android 原生侧完成（见 `ArchiveExtractor.kt`），统一支持
/// zip / tar / tar.gz / tar.xz / tar.bz2 / tar.zst / tar.lz4 / 7z / rar，
/// 以及单文件压缩流 xz / gz / bz2 / zst / lz4。
/// 压缩目前统一创建 zip 文件。
class ArchiveService {
  ArchiveService._();

  static const _channel = MethodChannel('com.venti1112.edgecube/archive');
  static const _eventChannel = EventChannel('com.venti1112.edgecube/archive_events');

  static StreamSubscription<dynamic>? _eventSub;

  /// 解压 [archivePath] 到 [destDir]（目标目录必须已存在）。
  /// 返回解压出的文件数量。
  ///
  /// 原生侧已做路径穿越防护，跳过任何逃逸出 [destDir] 的条目。
  static Future<int> extract(String archivePath, String destDir) async {
    final count = await _channel.invokeMethod<int>('extract', {
      'archivePath': archivePath,
      'destDir': destDir,
    });
    return count ?? 0;
  }

  /// 解压并报告进度。返回解压出的文件数量。
  ///
  /// [onProgress] 回调参数为 (current, total)；
  /// 当 total 为 -1 时表示格式不支持预知总条目数（tar/7z/rar）。
  static Future<int> extractWithProgress(
    String archivePath,
    String destDir, {
    void Function(int current, int total)? onProgress,
  }) async {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final current = event['current'] as int? ?? 0;
        final total = event['total'] as int? ?? -1;
        onProgress?.call(current, total);
      }
    });

    try {
      final count = await _channel.invokeMethod<int>('extract', {
        'archivePath': archivePath,
        'destDir': destDir,
      });
      return count ?? 0;
    } finally {
      await _eventSub?.cancel();
      _eventSub = null;
    }
  }

  /// 把 [sourcePaths] 压缩为 [archivePath] 指向的 zip 文件。
  /// 返回写入归档的文件数量。
  static Future<int> compress(
    List<String> sourcePaths,
    String archivePath,
  ) async {
    final count = await _channel.invokeMethod<int>('compress', {
      'sourcePaths': sourcePaths,
      'archivePath': archivePath,
    });
    return count ?? 0;
  }

  /// 解压归档到 [destDir] 下以归档文件名（去扩展名）命名的子文件夹中
  /// （重名时由调用方先确保唯一）。返回创建的子文件夹路径。
  static Future<String> extractToSubfolder(
    String archivePath,
    Directory destDir,
    String subfolderName,
  ) async {
    final targetPath = '${destDir.path}/$subfolderName';
    await Directory(targetPath).create(recursive: true);
    await extract(archivePath, targetPath);
    return targetPath;
  }
}
