import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 服务端图标的边长。**Minecraft 的硬要求**（daemon 侧也会校验，见
/// `daemon/src/module/builtin/instance/config.rs` 的 `check_icon`）。
const int kIconSide = 64;

/// 解码一份图片字节；解不开返回 `null`（当作「这不是一张能用的图」）。
///
/// 用 `dart:ui` 自己的解码器，**不引图片库**：Flutter 已经在用 skia 解码图片了，
/// 再拉一个纯 Dart 的解码器进来只是多一份要维护的东西（而 `image` 那种纯 Dart
/// 实现在 Web 上还慢一截）。
///
/// 顺带把原始尺寸拿出来 —— 裁剪页要用它算「图片恰好盖住裁剪框」的初始缩放。
class DecodedImage {
  const DecodedImage(this.bytes, this.image);

  /// 原始字节（画到界面上直接用 `Image.memory`，不用再编码一趟）。
  final Uint8List bytes;

  /// 解出来的图，裁剪时喂给 `Canvas.drawImageRect`。
  final ui.Image image;

  int get width => image.width;
  int get height => image.height;

  void dispose() => image.dispose();
}

/// 解码；失败（不是图片、格式不支持）返回 `null`。
Future<DecodedImage?> decodeImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return DecodedImage(bytes, frame.image);
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// 裁剪框落在原图坐标里的哪一块。
///
/// 界面上的变换是「图片按 `zoom` 缩放、居中、再按 `pan` 平移，裁剪框固定在屏幕
/// 正中」（见 `icon_crop_page.dart` 的 `_buildImageLayer`）。图上一点 `p` 落到屏幕
/// 的 `(screen - display)/2 + pan + p*zoom`，裁剪框左边在屏幕的
/// `(screen - cropBox)/2`；两者相减解出：
///
/// ```text
/// left = (imgW - (cropBox + 2*pan.dx) / zoom) / 2
/// side = cropBox / zoom
/// ```
///
/// 单独拎成纯函数是为了能直接对着算 —— 这块搞错了界面看不出来（图片照样显示），
/// 只有裁出来的图会偏，是最难靠肉眼发现的一类 bug。
///
/// 结果会夹进图内：浮点误差可能把它推出去一点点，那会让 `drawImageRect` 采到
/// 图像外的透明像素，图标边上就多一圈黑边/白边。
ui.Rect iconSourceRect({
  required int imageWidth,
  required int imageHeight,
  required double cropBox,
  required double zoom,
  required ui.Offset pan,
}) {
  final side = cropBox / zoom;
  final left = (imageWidth - (cropBox + 2 * pan.dx) / zoom) / 2;
  final top = (imageHeight - (cropBox + 2 * pan.dy) / zoom) / 2;
  final maxLeft = math.max(0.0, imageWidth - side);
  final maxTop = math.max(0.0, imageHeight - side);
  return ui.Rect.fromLTWH(
    left.clamp(0.0, maxLeft).toDouble(),
    top.clamp(0.0, maxTop).toDouble(),
    side,
    side,
  );
}

/// 把 [source] 的 [srcRect] 那块裁出来、缩到 64×64，编码成 PNG。
///
/// **一步做完**：`drawImageRect` 把「裁剪」与「缩放」合成一次带插值的绘制，
/// 插值用 `FilterQuality.high`：图标只有 64×64，缩小时的锯齿在那点像素上很显眼。
Future<Uint8List> encodeIconPng(ui.Image source, ui.Rect srcRect) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    srcRect,
    ui.Rect.fromLTWH(0, 0, kIconSide.toDouble(), kIconSide.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );

  final picture = recorder.endRecording();
  try {
    final scaled = await picture.toImage(kIconSide, kIconSide);
    try {
      final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG 编码失败');
      }
      return data.buffer.asUint8List();
    } finally {
      scaled.dispose();
    }
  } finally {
    picture.dispose();
  }
}
