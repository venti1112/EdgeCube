import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../i18n/locale_scope.dart';

/// 图片裁剪页面：将导入的图片裁剪为 1:1 并缩放至 64×64，保存为 PNG。
///
/// [imagePath] 为待裁剪图片的绝对路径；[outputPath] 为保存目标路径。
/// 用户确认裁剪后返回 `true`，取消返回 `null`。
class ServerIconCropPage extends StatefulWidget {
  const ServerIconCropPage({
    super.key,
    required this.imagePath,
    required this.outputPath,
  });

  final String imagePath;
  final String outputPath;

  @override
  State<ServerIconCropPage> createState() => _ServerIconCropPageState();
}

class _ServerIconCropPageState extends State<ServerIconCropPage> {
  // 原始图片字节与尺寸
  Uint8List? _imageBytes;
  int _imageWidth = 0;
  int _imageHeight = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // 裁剪框在屏幕上的尺寸（LayoutBuilder 中动态计算）
  double _cropBoxSize = 280;

  // 图片在裁剪框内的显示缩放（相对裁剪框）
  double _zoom = 1.0;
  // 图片偏移（像素，屏幕坐标）
  Offset _pan = Offset.zero;

  // 手势追踪
  Offset? _lastFocal;
  double _zoomAtGestureStart = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() {
          _loading = false;
          _error = context.tr('serverIcon.decodeFailed');
        });
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageWidth = decoded.width;
        _imageHeight = decoded.height;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitImage());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = context.tr('serverIcon.loadFailed', {'error': e.toString()});
      });
    }
  }

  /// 初始缩放：让图片短边恰好填满裁剪框。
  void _fitImage() {
    if (_imageWidth == 0 || _imageHeight == 0 || !mounted) return;
    final shortSide = math.min(_imageWidth, _imageHeight).toDouble();
    _zoom = _cropBoxSize / shortSide;
    _pan = Offset.zero;
    setState(() {});
  }

  double get _minZoom {
    if (_imageWidth == 0 || _imageHeight == 0) return 1.0;
    final shortSide = math.min(_imageWidth, _imageHeight).toDouble();
    return _cropBoxSize / shortSide;
  }

  double get _maxZoom => _minZoom * 5;

  /// 限制偏移，确保图片始终覆盖裁剪框。
  void _clampPan() {
    final displayW = _imageWidth * _zoom;
    final displayH = _imageHeight * _zoom;
    final maxDx = math.max(0.0, (displayW - _cropBoxSize) / 2);
    final maxDy = math.max(0.0, (displayH - _cropBoxSize) / 2);
    _pan = Offset(_pan.dx.clamp(-maxDx, maxDx), _pan.dy.clamp(-maxDy, maxDy));
  }

  // —— 手势 ——

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.focalPoint;
    _zoomAtGestureStart = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final delta = d.focalPoint - (_lastFocal ?? d.focalPoint);
    _lastFocal = d.focalPoint;
    setState(() {
      if (d.scale != 1.0) {
        _zoom = (_zoomAtGestureStart * d.scale).clamp(_minZoom, _maxZoom);
      }
      _pan += delta;
      _clampPan();
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _lastFocal = null;
  }

  // —— 确认裁剪 ——

  Future<void> _confirmCrop() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('无法解码图片');

      // 裁剪框在原图坐标中的尺寸
      final cropInImage = _cropBoxSize / _zoom;
      // 裁剪框中心在原图坐标中的位置
      final cx = _imageWidth / 2.0 - _pan.dx / _zoom;
      final cy = _imageHeight / 2.0 - _pan.dy / _zoom;
      final half = cropInImage / 2.0;

      final x = (cx - half).round().clamp(0, _imageWidth);
      final y = (cy - half).round().clamp(0, _imageHeight);
      final w = cropInImage.round().clamp(1, _imageWidth - x);
      final h = cropInImage.round().clamp(1, _imageHeight - y);

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final resized = img.copyResize(
        cropped,
        width: 64,
        height: 64,
        interpolation: img.Interpolation.linear,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(resized));
      await File(widget.outputPath).writeAsBytes(pngBytes, flush: true);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('serverIcon.saveFailed', {'error': e.toString()}),
            ),
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  // —— 构建 UI ——

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.tr('serverIcon.cropIcon')),
        actions: [
          if (!_loading && _error == null)
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.check),
                    tooltip: context.tr('serverIcon.confirmCrop'),
                    onPressed: _confirmCrop,
                  ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _cropBoxSize = math.max(
          200.0,
          math.min(constraints.maxWidth, constraints.maxHeight) * 0.75,
        );
        return Stack(
          children: [
            // 图片层：手势 + 图片
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: _buildImageLayer(constraints),
              ),
            ),
            // 遮罩层：四个半透明矩形围住裁剪框
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MaskPainter(
                    cropBoxSize: _cropBoxSize,
                    canvasSize: constraints.biggest,
                  ),
                ),
              ),
            ),
            // 底部提示
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  context.tr('serverIcon.dragAndPinchHint'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构建图片显示层：将图片中心对齐裁剪框中心，支持缩放和平移。
  Widget _buildImageLayer(BoxConstraints constraints) {
    final screenW = constraints.maxWidth;
    final screenH = constraints.maxHeight;
    final displayW = _imageWidth * _zoom;
    final displayH = _imageHeight * _zoom;

    // 图片左上角在屏幕上的位置：居中 + 偏移
    final left = (screenW - displayW) / 2 + _pan.dx;
    final top = (screenH - displayH) / 2 + _pan.dy;

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            top: top,
            width: displayW,
            height: displayH,
            child: Image.memory(
              _imageBytes!,
              width: displayW,
              height: displayH,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, e, s) => const Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// —— 遮罩画笔：四个半透明矩形 + 裁剪框边框 + 角标 ——

class _MaskPainter extends CustomPainter {
  _MaskPainter({required this.cropBoxSize, required this.canvasSize});

  final double cropBoxSize;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    final half = cropBoxSize / 2;

    final cropRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: cropBoxSize,
      height: cropBoxSize,
    );

    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // 上方
    canvas.drawRect(
      Rect.fromLTRB(0, 0, canvasSize.width, cy - half),
      maskPaint,
    );
    // 下方
    canvas.drawRect(
      Rect.fromLTRB(0, cy + half, canvasSize.width, canvasSize.height),
      maskPaint,
    );
    // 左侧
    canvas.drawRect(
      Rect.fromLTRB(0, cy - half, cx - half, cy + half),
      maskPaint,
    );
    // 右侧
    canvas.drawRect(
      Rect.fromLTRB(cx + half, cy - half, canvasSize.width, cy + half),
      maskPaint,
    );

    // 裁剪框白色边框
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(cropRect, borderPaint);

    // 四角 L 形角标
    const cornerLen = 24.0;
    const cornerW = 3.5;
    final cp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerW
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      cropRect.topLeft,
      cropRect.topLeft + const Offset(cornerLen, 0),
      cp,
    );
    canvas.drawLine(
      cropRect.topLeft,
      cropRect.topLeft + const Offset(0, cornerLen),
      cp,
    );

    canvas.drawLine(
      cropRect.topRight,
      cropRect.topRight + const Offset(-cornerLen, 0),
      cp,
    );
    canvas.drawLine(
      cropRect.topRight,
      cropRect.topRight + const Offset(0, cornerLen),
      cp,
    );

    canvas.drawLine(
      cropRect.bottomLeft,
      cropRect.bottomLeft + const Offset(cornerLen, 0),
      cp,
    );
    canvas.drawLine(
      cropRect.bottomLeft,
      cropRect.bottomLeft + const Offset(0, -cornerLen),
      cp,
    );

    canvas.drawLine(
      cropRect.bottomRight,
      cropRect.bottomRight + const Offset(-cornerLen, 0),
      cp,
    );
    canvas.drawLine(
      cropRect.bottomRight,
      cropRect.bottomRight + const Offset(0, -cornerLen),
      cp,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.cropBoxSize != cropBoxSize || old.canvasSize != canvasSize;
}
