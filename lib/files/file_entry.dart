import 'dart:io';

/// 目录中的一个条目（文件、子目录或符号链接）的展示信息。
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.isLink = false,
    this.linkTarget,
  });

  final String path;
  final String name;

  /// 是否为目录。对符号链接而言，表示其**目标**是否为目录，
  /// 以便在浏览器中对「指向目录的链接」允许进入。
  final bool isDirectory;

  /// 是否为符号链接。
  final bool isLink;

  /// 符号链接的原始目标字符串（可能是相对路径）；非链接或读取失败时为 null。
  final String? linkTarget;

  /// 文件字节数；目录为 0。
  final int size;
  final DateTime modified;

  bool get isFile => !isDirectory;
}

/// 把一个 [FileSystemEntity] 读成 [FileEntry]，读取失败时回退到零值。
///
/// 目录枚举应以 `followLinks: false` 进行，符号链接会作为 [Link] 传入：
/// 此处跟随链接判定其目标类型（决定 [FileEntry.isDirectory]，便于进入指向目录的
/// 链接），并记录 [FileEntry.isLink] 与原始目标，供 UI 标识与安全的文件操作使用。
FileEntry entryFromEntity(FileSystemEntity entity, String name) {
  final isLink = entity is Link;
  bool isDir;
  String? linkTarget;
  if (isLink) {
    // 跟随链接判定目标类型；断链（目标不存在）回退为非目录。
    isDir =
        FileSystemEntity.typeSync(entity.path, followLinks: true) ==
        FileSystemEntityType.directory;
    try {
      linkTarget = entity.targetSync();
    } on FileSystemException {
      // 读取链接目标失败（极少见），保持 null。
    }
  } else {
    isDir = entity is Directory;
  }
  int size = 0;
  DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
  try {
    // statSync 跟随链接：对链接取其目标的大小/时间；断链会抛异常并回退。
    final stat = entity.statSync();
    modified = stat.modified;
    if (!isDir) size = stat.size;
  } on FileSystemException {
    // 条目可能在枚举与 stat 之间消失，或为断链，保持回退值。
  }
  return FileEntry(
    path: entity.path,
    name: name,
    isDirectory: isDir,
    isLink: isLink,
    linkTarget: linkTarget,
    size: size,
    modified: modified,
  );
}
