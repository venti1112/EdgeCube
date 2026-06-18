import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_service.dart';
import 'file_entry.dart';

/// 当目标位置已存在同名条目、且操作不允许覆盖时抛出。
class FileConflictException implements Exception {
  const FileConflictException(this.name);

  final String name;

  @override
  String toString() => '目标位置已存在同名文件：$name';
}

/// 当试图把目录移动/复制到它自身或其子目录时抛出。
class InvalidDestinationException implements Exception {
  const InvalidDestinationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 针对实例文件夹的纯文件系统操作。
///
/// 全部基于路径、不依赖任何原生插件，可直接单元测试。
class FileService {
  const FileService();

  /// 列出 [dir] 下的条目，目录在前、各自按名称（忽略大小写）排序。
  Future<List<FileEntry>> list(Directory dir) async {
    if (!await dir.exists()) return [];
    final entries = <FileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      entries.add(entryFromEntity(entity, p.basename(entity.path)));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// 在 [parent] 下新建子目录，返回创建的目录。
  Future<Directory> createDirectory(Directory parent, String name) async {
    final trimmed = name.trim();
    final target = Directory(p.join(parent.path, trimmed));
    if (await target.exists()) {
      throw FileConflictException(trimmed);
    }
    return target.create();
  }

  /// 在 [parent] 下新建一个空文件，返回创建的文件。
  /// 已存在同名文件或目录时抛 [FileConflictException]。
  Future<File> createFile(Directory parent, String name) async {
    final trimmed = name.trim();
    final target = File(p.join(parent.path, trimmed));
    if (await _exists(target.path)) {
      throw FileConflictException(trimmed);
    }
    await target.create();
    return target;
  }

  /// 删除文件或目录（目录递归删除）。
  Future<void> delete(String path) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  /// 同目录内重命名；目标名已存在时抛 [FileConflictException]。
  Future<void> rename(String path, String newName) async {
    final trimmed = newName.trim();
    final parent = p.dirname(path);
    final target = p.join(parent, trimmed);
    if (target == path) return;
    if (await _exists(target)) {
      throw FileConflictException(trimmed);
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).rename(target);
    } else {
      await File(path).rename(target);
    }
  }

  /// 把 [sourcePath] 复制到 [destDir]，重名时自动追加 ` (n)` 后缀。
  /// 返回新建条目的路径。
  Future<String> copy(String sourcePath, Directory destDir) async {
    _guardNotIntoSelf(sourcePath, destDir.path);
    final target = await _uniqueTarget(destDir.path, p.basename(sourcePath));
    await _copyEntity(sourcePath, target);
    return target;
  }

  /// 把 [sourcePath] 移动到 [destDir]；目标重名时抛 [FileConflictException]。
  /// 返回移动后条目的路径。
  Future<String> move(String sourcePath, Directory destDir) async {
    _guardNotIntoSelf(sourcePath, destDir.path);
    final target = p.join(destDir.path, p.basename(sourcePath));
    if (target == sourcePath) return sourcePath;
    if (await _exists(target)) {
      throw FileConflictException(p.basename(sourcePath));
    }
    final type = FileSystemEntity.typeSync(sourcePath);
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(target);
      } else {
        await File(sourcePath).rename(target);
      }
    } on FileSystemException {
      // 跨文件系统 rename 会失败，退化为「复制后删除」。
      await _copyEntity(sourcePath, target);
      await delete(sourcePath);
    }
    return target;
  }

  /// 导入：把外部文件 [sourcePath] 复制进 [destDir]，重名自动加后缀。
  Future<String> importFile(String sourcePath, Directory destDir) {
    return copy(sourcePath, destDir);
  }

  /// 导出：把 [sourcePath] 复制到外部目录 [destDirPath]，重名自动加后缀。
  Future<String> exportTo(String sourcePath, String destDirPath) async {
    final target = await _uniqueTarget(destDirPath, p.basename(sourcePath));
    await _copyEntity(sourcePath, target);
    return target;
  }

  /// 以 UTF-8 读取文本文件内容。
  ///
  /// 内容不是合法 UTF-8（例如二进制文件）时会抛出异常，交由调用方提示用户。
  Future<String> readText(String path) {
    return File(path).readAsString();
  }

  /// 以 UTF-8 将 [content] 覆盖写入文件，并在返回前刷新到磁盘。
  Future<void> writeText(String path, String content) async {
    await File(path).writeAsString(content, flush: true);
  }

  /// 解压归档：在 [destDir] 下创建以 [subfolderName] 命名的子文件夹（重名时
  /// 自动追加 ` (n)` 后缀），把 [archivePath] 的内容解压进去。返回创建的子文件夹路径。
  ///
  /// 支持格式与原生实现见 `ArchiveExtractor.kt`；路径穿越防护在原生侧完成。
  Future<String> extract(
    String archivePath,
    Directory destDir,
    String subfolderName,
  ) async {
    final targetPath = await _uniqueTarget(destDir.path, subfolderName);
    await Directory(targetPath).create(recursive: true);
    await ArchiveService.extract(archivePath, targetPath);
    return targetPath;
  }

  // —— 内部工具 ——

  Future<bool> _exists(String path) async =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// 防止把目录移动/复制到它自身或其子目录中。
  void _guardNotIntoSelf(String sourcePath, String destDirPath) {
    if (FileSystemEntity.typeSync(sourcePath) !=
        FileSystemEntityType.directory) {
      return;
    }
    final src = p.normalize(sourcePath);
    final dest = p.normalize(destDirPath);
    if (dest == src || p.isWithin(src, dest)) {
      throw const InvalidDestinationException('不能把文件夹移动或复制到它自身内部。');
    }
  }

  /// 在 [dirPath] 下为 [name] 求一个不冲突的目标路径，必要时追加 ` (n)`。
  Future<String> _uniqueTarget(String dirPath, String name) async {
    var candidate = p.join(dirPath, name);
    if (!await _exists(candidate)) return candidate;

    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    for (var i = 1;; i++) {
      candidate = p.join(dirPath, '$base ($i)$ext');
      if (!await _exists(candidate)) return candidate;
    }
  }

  /// 递归复制文件或目录到精确的 [targetPath]。
  Future<void> _copyEntity(String sourcePath, String targetPath) async {
    final type = FileSystemEntity.typeSync(sourcePath);
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).create(recursive: true);
      await for (final child
          in Directory(sourcePath).list(followLinks: false)) {
        await _copyEntity(
          child.path,
          p.join(targetPath, p.basename(child.path)),
        );
      }
    } else {
      await File(sourcePath).copy(targetPath);
    }
  }
}
