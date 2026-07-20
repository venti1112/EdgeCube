import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../i18n/i18n_service.dart';

/// 整合包解析/安装的共享工具：归档探测、overrides 展开、路径穿越防护。
class ModpackUtils {
  ModpackUtils._();

  /// 在归档中定位签名文件条目（优先根目录，其次任意层级）。
  /// 返回命中条目，供调用方读取内容或推导 baseFolder。
  static ArchiveFile? findEntry(Archive archive, String fileName) {
    ArchiveFile? fallback;
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name == fileName) return f;
      if (f.name.endsWith('/$fileName')) fallback ??= f;
    }
    return fallback;
  }

  /// 由签名条目名推导包裹前缀（baseFolder）。根目录返回空串，
  /// 单层子目录包裹（如 "pack/manifest.json"）返回 "pack/"。
  static String baseFolderOf(ArchiveFile entry, String fileName) {
    if (entry.name == fileName) return '';
    return entry.name.substring(0, entry.name.length - fileName.length);
  }

  /// 归档是否包含指定签名文件（用于 provider.matches）。
  static bool hasEntry(Archive archive, String fileName) =>
      findEntry(archive, fileName) != null;

  /// 展开整合包 override 目录到 [destDir]，平铺保留相对结构。
  /// [prefixes] 为归档内前缀（已含 baseFolder）。返回展开文件数。
  static Future<int> extractOverrides(
    Archive archive,
    Directory destDir,
    List<String> prefixes,
  ) async {
    var count = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      String? rel;
      for (final prefix in prefixes) {
        if (file.name.startsWith(prefix) && file.name.length > prefix.length) {
          rel = file.name.substring(prefix.length);
          break;
        }
      }
      if (rel == null) continue;
      rel = safeRelativePath(rel, destDir);
      final targetPath = p.join(destDir.path, rel);
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await File(targetPath).writeAsBytes(file.content as List<int>);
      count++;
    }
    return count;
  }

  /// 规范化相对路径并防止路径穿越（不允许逃逸出 [destDir]）。
  static String safeRelativePath(String rel, Directory destDir) {
    final normalized = p.normalize(rel).replaceAll('\\', '/');
    if (p.isAbsolute(normalized) ||
        normalized.startsWith('..') ||
        normalized.contains(':')) {
      throw InvalidPathException(
        tr('modpack.invalidPath', {'path': normalized}),
      );
    }
    final resolved = p.normalize(p.join(destDir.path, normalized));
    if (!p.isWithin(destDir.path, resolved)) {
      throw InvalidPathException(tr('modpack.pathEscape'));
    }
    return normalized;
  }
}

/// 整合包路径非法异常。
class InvalidPathException implements Exception {
  final String message;
  const InvalidPathException(this.message);
  @override
  String toString() => message;
}

/// 整合包无法解析异常（如 CurseForge 但 CF 源不可用）。
class ModpackParseException implements Exception {
  final String message;
  const ModpackParseException(this.message);
  @override
  String toString() => message;
}
