import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'icon_image.dart';

/// 「裁剪图标」页：把选来的图裁成 1:1、缩到 64×64、编码成 PNG 返回。
///
/// 排版与交互：
///
/// * `Scaffold(backgroundColor: Colors.black)` + 白色前景（**不跟主题**，与相册取景一致）
/// * 裁剪框 = `max(200, min(w,h) * 0.75)`，居中
/// * `_MaskPainter` 四块半透明遮罩 + 边框 + 四角标
/// * 拖动平移 + 双指缩放，`_clampPan` 保证图片始终盖住框
/// * 裁剪用 `dart:ui` 的 `drawImageRect` 一步做完（见 `icon_image.dart`）
/// * **只回字节**，写盘由调用方走 `instance.config.icon.save`（页面不碰 I/O）
///
/// 返回值：确认时 `pop(64×64 的 PNG 字节)`，取消 `pop(null)`。
class IconCropPage extends StatefulWidget {
  const IconCropPage({super.key, required this.imageBytes});

  /// 待裁剪的原始图片字节。
  final Uint8List imageBytes;

  @override
  State<IconCropPage> createState() => _IconCropPageState();
}

class _IconCropPageState extends State<IconCropPage> {
  DecodedImage? _decoded;
  String? _error;
  bool _saving = false;

  /// 裁剪框边长（`build` 里按布局算）。
  double _cropBox = 280;

  /// 上一次按哪个框长做过「适配缩放」—— 布局变了要重新适配一次，
  /// 否则图片可能盖不满框（裁出来会带黑边）。
  double? _fittedFor;

  /// 缩放：1 表示图片 1 像素对屏幕 1 逻辑像素。初始 = 短边恰好填满裁剪框。
  double _zoom = 1;
  Offset _pan = Offset.zero;

  Offset? _lastFocal;
  double _zoomAtGestureStart = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final decoded = await decodeImage(widget.imageBytes);
    if (!mounted) {
      decoded?.dispose();
      return;
    }
    setState(() {
      _decoded = decoded;
      if (decoded == null) _error = '无法解码图片';
    });
  }

  double get _minZoom {
    final decoded = _decoded;
    if (decoded == null) return 1;
    final shortSide = math.min(decoded.width, decoded.height).toDouble();
    return shortSide <= 0 ? 1 : _cropBox / shortSide;
  }

  double get _maxZoom => _minZoom * 5;

  /// 初始缩放：让图片短边恰好填满裁剪框。
  void _fitImage() {
    final decoded = _decoded;
    if (decoded == null) return;
    setState(() {
      _zoom = _minZoom;
      _pan = Offset.zero;
      _fittedFor = _cropBox;
    });
  }

  /// 限制偏移，保证图片始终盖住裁剪框（不然裁出来会露黑边）。
  void _clampPan() {
    final decoded = _decoded;
    if (decoded == null) return;
    final displayW = decoded.width * _zoom;
    final displayH = decoded.height * _zoom;
    final maxDx = math.max(0.0, (displayW - _cropBox) / 2);
    final maxDy = math.max(0.0, (displayH - _cropBox) / 2);
    _pan = Offset(
      _pan.dx.clamp(-maxDx, maxDx),
      _pan.dy.clamp(-maxDy, maxDy),
    );
  }

  // ── 手势 ──

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocal = details.focalPoint;
    _zoomAtGestureStart = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final last = _lastFocal ?? details.focalPoint;
    final delta = details.focalPoint - last;
    _lastFocal = details.focalPoint;
    setState(() {
      if (details.scale != 1) {
        _zoom = (_zoomAtGestureStart * details.scale).clamp(_minZoom, _maxZoom);
      }
      _pan += delta;
      _clampPan();
    });
  }

  void _onScaleEnd(ScaleEndDetails _) => _lastFocal = null;

  // ── 确认 ──

  /// 裁剪框在原图坐标里的位置（推导见 `icon_image.dart` 的 `iconSourceRect`）。
  ui.Rect get _sourceRect {
    final decoded = _decoded!;
    return iconSourceRect(
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      cropBox: _cropBox,
      zoom: _zoom,
      pan: _pan,
    );
  }

  Future<void> _confirm() async {
    final decoded = _decoded;
    if (decoded == null || _saving) return;
    setState(() => _saving = true);
    try {
      final png = await encodeIconPng(decoded.image, _sourceRect);
      if (mounted) Navigator.of(context).pop<Uint8List>(png);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('裁剪失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 裁剪页与相册取景一致：固定黑底白字，不跟明暗主题。
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('裁剪图标'),
        actions: [
          if (_decoded != null)
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
                    key: const Key('icon_crop_confirm'),
                    tooltip: '确认裁剪',
                    icon: const Icon(Icons.check, color: Colors.white),
                    onPressed: _confirm,
                  ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error case final message?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    final decoded = _decoded;
    if (decoded == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _cropBox = math.max(
          200.0,
          math.min(constraints.maxWidth, constraints.maxHeight) * 0.75,
        );
        // 布局变了（首次进来、窗口缩放）就重新适配一次缩放与居中。
        // 不这么做的话「图片盖不住裁剪框」，裁出来会带黑边。
        if (_fittedFor != _cropBox) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _fittedFor != _cropBox) _fitImage();
          });
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: _buildImageLayer(decoded, constraints),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MaskPainter(
                    cropBox: _cropBox,
                    canvasSize: constraints.biggest,
                  ),
                ),
              ),
            ),
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
                child: const Text(
                  '拖动调整位置，双指缩放',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 图片层：中心对齐裁剪框中心，按 `_zoom` 缩放、按 `_pan` 平移。
  Widget _buildImageLayer(DecodedImage decoded, BoxConstraints constraints) {
    final displayW = decoded.width * _zoom;
    final displayH = decoded.height * _zoom;
    final left = (constraints.maxWidth - displayW) / 2 + _pan.dx;
    final top = (constraints.maxHeight - displayH) / 2 + _pan.dy;

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
              decoded.bytes,
              width: displayW,
              height: displayH,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Center(
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

/// 遮罩：裁剪框外四块半透明黑，框内一圈白边 + 四个角标。
class _MaskPainter extends CustomPainter {
  const _MaskPainter({required this.cropBox, required this.canvasSize});

  final double cropBox;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final left = (size.width - cropBox) / 2;
    final top = (size.height - cropBox) / 2;
    final box = Rect.fromLTWH(left, top, cropBox, cropBox);

    final shade = Paint()..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), shade);
    canvas.drawRect(
      Rect.fromLTRB(0, top + cropBox, size.width, size.height),
      shade,
    );
    canvas.drawRect(Rect.fromLTRB(0, top, left, top + cropBox), shade);
    canvas.drawRect(
      Rect.fromLTRB(left + cropBox, top, size.width, top + cropBox),
      shade,
    );

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(box, border);

    // 四个角：加粗的直角，方便对齐
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const arm = 18.0;
    for (final (dx, dy) in const [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]) {
      final cx = left + dx * cropBox;
      final cy = top + dy * cropBox;
      final hx = dx == 0 ? 1.0 : -1.0;
      final vy = dy == 0 ? 1.0 : -1.0;
      canvas.drawLine(Offset(cx, cy), Offset(cx + hx * arm, cy), corner);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + vy * arm), corner);
    }
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.cropBox != cropBox || old.canvasSize != canvasSize;
}
