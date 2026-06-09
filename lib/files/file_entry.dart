import 'dart:io';

/// 目录中的一个条目（文件或子目录）的展示信息。
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final bool isDirectory;

  /// 文件字节数；目录为 0。
  final int size;
  final DateTime modified;

  bool get isFile => !isDirectory;
}

/// 把一个 [FileSystemEntity] 读成 [FileEntry]，读取失败时回退到零值。
FileEntry entryFromEntity(FileSystemEntity entity, String name) {
  final isDir = entity is Directory;
  int size = 0;
  DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
  try {
    final stat = entity.statSync();
    modified = stat.modified;
    if (!isDir) size = stat.size;
  } on FileSystemException {
    // 条目可能在枚举与 stat 之间消失，保持回退值。
  }
  return FileEntry(
    path: entity.path,
    name: name,
    isDirectory: isDir,
    size: size,
    modified: modified,
  );
}
