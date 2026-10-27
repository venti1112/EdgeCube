import 'local_folder.dart';

/// 客户端本机目录的平台实现（Web 版）。
///
/// 浏览器只给文件句柄：拿不到本地路径，也就遍历不了目录 —— 所以
/// [folderImportSupported] 是 false，「导入文件夹」按钮不显示。
/// 单个文件（`导入文件`）照常，走 `PlatformFile.readAsByteStream()`。

bool folderImportSupported() => false;

/// 不会走到（按钮都隐藏了），留着是为了两个实现接口一致。
Future<LocalFolderPick?> pickLocalFolder() async => null;
