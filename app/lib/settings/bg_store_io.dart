import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 将所选背景图片复制到应用支持目录(仅保留一张,覆盖旧的),返回持久化路径
Future<String> persistBackgroundImage(PlatformFile file) async {
  final dir = await getApplicationSupportDirectory();
  final bgDir = Directory('${dir.path}${Platform.pathSeparator}background');
  await bgDir.create(recursive: true);
  // 清理旧背景,目录内只保留当前一张
  await for (final entity in bgDir.list()) {
    await entity.delete();
  }
  final ext = (file.extension == null || file.extension!.isEmpty)
      ? 'png'
      : file.extension!;
  final dest = File('${bgDir.path}${Platform.pathSeparator}bg.$ext');
  if (file.path != null) {
    await File(file.path!).copy(dest.path);
  } else {
    await dest.writeAsBytes(file.bytes!);
  }
  return dest.path;
}
