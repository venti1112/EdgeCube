import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// 渲染本地图片背景(native),加载失败回退纯色
Widget buildBackgroundImage(String src, Color fallback) {
  return Image.file(
    File(src),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => ColoredBox(color: fallback),
  );
}
