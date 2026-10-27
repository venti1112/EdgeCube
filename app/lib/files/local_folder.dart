import 'dart:async';

/// 从用户本机挑出来的待上传条目（`导入文件夹` 用）。
///
/// 目录也是一条（[LocalUpload.dir]）：空目录没有字节，但要在服务端建出来 ——
/// 否则导入一个「只有空子目录」的模板文件夹会什么都不剩。
class LocalUpload {
  const LocalUpload.file({
    required this.relativePath,
    required this.length,
    required this.read,
  }) : isDir = false;

  const LocalUpload.dir({required this.relativePath})
    : isDir = true,
      length = 0,
      read = _noBytes;

  /// 相对所选文件夹的路径（`/` 分隔，`mods/a.jar`）。
  final String relativePath;
  final bool isDir;
  final int length;

  /// 打开一条字节流（可以重复调用，重试时要用）。
  final Stream<List<int>> Function() read;

  /// 最后一段（`mods/a.jar` → `a.jar`）。
  String get name => _at < 0 ? relativePath : relativePath.substring(_at + 1);

  /// 所在目录（`mods/a.jar` → `mods`；顶层条目 → 空串）。
  String get dir => _at < 0 ? '' : relativePath.substring(0, _at);

  int get _at => relativePath.lastIndexOf('/');

  static Stream<List<int>> _noBytes() => const Stream.empty();
}

/// 一次「导入文件夹」：所选文件夹的名字 + 里面的条目。
class LocalFolderPick {
  const LocalFolderPick({required this.name, required this.items});

  /// 所选文件夹的名字 —— 在实例目录下建同名文件夹（复制语义）。
  final String name;

  /// 相对所选文件夹的条目，父目录一定排在子项前面（建目录时用得上）。
  final List<LocalUpload> items;
}
