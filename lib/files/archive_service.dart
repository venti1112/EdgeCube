import 'dart:io';

import 'package:flutter/services.dart';

/// 归档解压的平台通道封装。
///
/// 实际解压在 Android 原生侧完成（见 `ArchiveExtractor.kt`），统一支持
/// zip / tar / tar.gz / tar.xz / tar.bz2 / tar.zst / tar.lz4 / 7z / rar，
/// 以及单文件压缩流 xz / gz / bz2 / zst / lz4。
class ArchiveService {
  ArchiveService._();

  static const _channel = MethodChannel('com.venti1112.edgecube/archive');

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
