import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// web 端将所选背景图片字节转为 dataURL 存储(受浏览器本地存储容量限制)
Future<String> persistBackgroundImage(PlatformFile file) async {
  final ext = file.extension?.toLowerCase();
  final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
  final bytes = file.bytes ?? Uint8List(0);
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
