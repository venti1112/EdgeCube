import 'package:material_ui/material_ui.dart';

/// 渲染 dataURL 图片背景(web),加载失败回退纯色
Widget buildBackgroundImage(String src, Color fallback) {
  return Image.network(
    src,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => ColoredBox(color: fallback),
  );
}
