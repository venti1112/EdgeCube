import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n_service.dart';
import '../net/download_engine.dart';
import '../net/mod_mirror.dart';
import 'modpack/modpack_provider.dart';
import 'modpack/modpack_registry.dart';
import 'modpack/modpack_utils.dart';
import 'modrinth_service.dart';

export 'modpack/modpack_provider.dart'
    show ModpackFormat, ParsedModpack, ModpackFileEntry;
export 'modpack/modpack_utils.dart'
    show InvalidPathException, ModpackParseException;

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
  /// [onProgress] 回调 (current, total, currentFileName)。
  /// [isCancelled] 返回 true 时中断并删除当前不完整文件。
  /// 已存在且大小匹配的文件会被跳过，便于失败重试。
  /// 镜像开启时各文件的下载 URL 会追加镜像候选（多源顺序回退）。
  static Future<void> downloadServerFiles(
    ParsedModpack modpack,
    Directory destDir, {
    void Function(int current, int total, String currentFile)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final serverFiles = modpack.serverFiles;
    final total = serverFiles.length;
    for (var i = 0; i < serverFiles.length; i++) {
      if (isCancelled?.call() == true) return;
      final file = serverFiles[i];
      final relPath = ModpackUtils.safeRelativePath(file.path, destDir);
      final targetPath = p.join(destDir.path, relPath);
      final targetFile = File(targetPath);

      // 跳过已存在且大小匹配的文件。
      if (await targetFile.exists() &&
          file.fileSize != null &&
          (await targetFile.length()) == file.fileSize) {
        onProgress?.call(i + 1, total, p.basename(targetPath));
        continue;
      }

      await Directory(p.dirname(targetPath)).create(recursive: true);

      if (file.downloads.isEmpty) {
        onProgress?.call(i + 1, total, p.basename(targetPath));
        continue;
      }

      // 追加镜像候选后多源顺序回退。
      final urls = await ModMirror.expandDownloads(file.downloads);
      await DownloadEngine.instance.downloadToFileMultiSource(
        urls,
        targetPath,
        isCancelled: isCancelled,
      );

      // 哈希校验（可选）。
      if (file.sha1 != null && file.sha1!.isNotEmpty) {
        final actual = await ModrinthService.computeSha1(targetPath);
        if (actual != file.sha1) {
          try {
            await targetFile.delete();
          } catch (_) {}
          throw Exception(
            tr('modpack.hashMismatch', {
              'fileName': p.basename(targetPath),
              'expected': file.sha1!,
              'actual': actual,
            }),
          );
        }
      }

      onProgress?.call(i + 1, total, p.basename(targetPath));
    }
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
