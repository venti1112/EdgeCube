import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'local_folder.dart';

/// 客户端本机目录的平台实现（IO 版）：真去遍历目录。
///
/// 这是「客户端本机」的活，和 daemon 无关 —— daemon 在远端，只认上传上来的
/// 相对路径（见 `daemon/README.md` 的文件管理一节）。

/// 能否「导入文件夹」：要先能遍历本机目录。
///
/// Web 拿不到本地路径（浏览器的目录选择只给文件句柄），那边这个按钮不显示；
/// Android 的 SAF 也可能读不了所选目录，那时以错误提示收场。
bool folderImportSupported() => true;

/// 让用户挑一个本地文件夹，返回其中的文件与空目录；取消返回 `null`。
///
/// 符号链接一律跳过（不跟链，免得绕圈；daemon 侧也不跟）。
Future<LocalFolderPick?> pickLocalFolder() async {
  final root = await FilePicker.getDirectoryPath();
  if (root == null) return null;
  final rootDir = Directory(root);
  final items = <LocalUpload>[];

  // 广度优先：父目录先入列，服务端建目录时就不必再排序
  final pending = <(String, Directory)>[('', rootDir)];
  while (pending.isNotEmpty) {
    final (relative, dir) = pending.removeAt(0);
    for (final child in dir.listSync(followLinks: false)) {
      final name = _basename(child.path);
      final path = relative.isEmpty ? name : '$relative/$name';
      if (child is Directory) {
        items.add(LocalUpload.dir(relativePath: path));
        pending.add((path, child));
      } else if (child is File) {
        items.add(
          LocalUpload.file(
            relativePath: path,
            length: child.lengthSync(),
            read: child.openRead,
          ),
        );
      }
    }
  }
  final name = _basename(rootDir.path);
  if (name.isEmpty) {
    // 选中的是整个盘根（`/` 或 `C:\`）：没有可用的名字，也谈不上「导入一个文件夹」。
    // 别拿一个空名字去 `mkdir`（daemon 会回 invalid_params，用户看不到原因）。
    throw const FormatException('不能导入磁盘根目录');
  }
  return LocalFolderPick(name: name, items: items);
}

/// 取路径最后一段（两种分隔符都认，Windows 上会是 `\`）。
///
/// **先剪掉结尾的分隔符**：`getDirectoryPath()` 走 XDG 门户，给文件夹的 URI 常是
/// `file:///home/x/photos/` 这种**带尾斜杠**的，`toFilePath()` 会原样保留它 ——
/// 直接取最后一段就会得到空串，「导入文件夹」于是拿一个空名字去 daemon `mkdir`，
/// 报「名称不能为空」（真踩过）。`package:path` 的 `basename` 会吃掉尾斜杠，
/// 这里手写就得把这一步补上。
String _basename(String path) {
  var end = path.length;
  while (end > 0 && (path[end - 1] == '/' || path[end - 1] == '\\')) {
    end--;
  }
  final trimmed = path.substring(0, end);
  final at = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  return at < 0 ? trimmed : trimmed.substring(at + 1);
}
