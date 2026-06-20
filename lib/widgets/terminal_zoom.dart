import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../config/terminal_store.dart';

/// 可缩放终端视图：在 [TerminalView] 外包一层双指捏合缩放。
///
/// 用 [Listener] 手动追踪指针，而非 [GestureDetector] / ScaleGestureRecognizer——后者在
/// 单指时也会贪婪地参与手势竞技场，抢走 xterm 的点击/长按选择与内层滚动；[Listener] 只
/// 监听原始指针事件、不参与竞技场，因此不破坏终端原有交互。仅当屏幕上恰好有两个手指时，
/// 按双指间距的相对变化缩放字号；缩放过程中在终端中央短暂显示当前字号，模仿正式终端软件。
class ZoomableTerminal extends StatefulWidget {
  const ZoomableTerminal({
    super.key,
    required this.terminal,
    required this.fontSize,
    required this.onFontSizeChanged,
    this.onFontSizeChangeEnd,
    this.padding = const EdgeInsets.all(8),
  });

  final Terminal terminal;

  /// 当前字号（由父级 State 持有，缩放时通过 [onFontSizeChanged] 回写）。
  final double fontSize;

  /// 捏合过程中实时回调新字号（已 clamp 到合法范围）。
  final ValueChanged<double> onFontSizeChanged;

  /// 一次捏合结束（手指减少到少于两指）时回调，供父级持久化最终字号。
  final VoidCallback? onFontSizeChangeEnd;

  final EdgeInsets padding;

  @override
  State<ZoomableTerminal> createState() => _ZoomableTerminalState();
}

class _ZoomableTerminalState extends State<ZoomableTerminal> {
  /// 当前按在屏幕上的指针：pointer id -> 最近位置。
  final Map<int, Offset> _pointers = {};

  /// 双指捏合开始时的基准间距与基准字号；为 null 表示当前未在捏合。
  double? _baseDistance;
  double? _baseFontSize;

  /// 是否正在显示缩放提示浮层。
  bool _showOverlay = false;

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) _beginPinch();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2 && _baseDistance != null) _updatePinch();
  }

  void _onPointerEnd(PointerEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers.remove(event.pointer);
    if (_pointers.length < 2 && _baseDistance != null) _endPinch();
  }

  void _beginPinch() {
    _baseDistance = _currentDistance();
    _baseFontSize = widget.fontSize;
    setState(() => _showOverlay = true);
  }

  void _updatePinch() {
    final base = _baseDistance!;
    if (base <= 0) return;
    final scale = _currentDistance() / base;
    final newSize = (_baseFontSize! * scale).clamp(
      kMinTerminalFontSize,
      kMaxTerminalFontSize,
    );
    if (newSize != widget.fontSize) widget.onFontSizeChanged(newSize);
  }

  void _endPinch() {
    _baseDistance = null;
    _baseFontSize = null;
    setState(() => _showOverlay = false);
    // 父级 _fontSize 已被 onFontSizeChanged 同步更新，这里只通知它落盘。
    widget.onFontSizeChangeEnd?.call();
  }

  double _currentDistance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TerminalView(
            widget.terminal,
            theme: TerminalThemes.defaultTheme,
            textStyle: TerminalStyle(fontSize: widget.fontSize),
            padding: widget.padding,
            // 不自动抢焦点（页面常驻 IndexedStack）；点击终端再唤起键盘。
            autofocus: false,
          ),
          // 捏合时的字号提示浮层；不拦截指针，结束后淡出。
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: _ZoomBadge(fontSize: widget.fontSize),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 缩放中显示在终端中央的字号徽标。
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.format_size, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            fontSize.toStringAsFixed(0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏字号控制按钮：弹出菜单含「放大 / 缩小 / 重置」，并显示当前字号。
///
/// 与 [ZoomableTerminal] 的捏合手势共用同一套范围常量与回调；按钮以 1 为步进做精确微调，
/// 捏合则用于快速缩放。
class TerminalZoomButton extends StatelessWidget {
  const TerminalZoomButton({
    super.key,
    required this.fontSize,
    required this.onChanged,
  });

  final double fontSize;

  /// 回调新字号（已 clamp 到合法范围）。
  final ValueChanged<double> onChanged;

  static const double _step = 1.0;

  void _change(double delta) {
    // 先朝缩放方向把当前字号取整，再步进，使「放大/缩小」总落到整数字号
    // （捏合可能产生小数字号，按钮在此基础上规整为整数步进）。
    final base = delta > 0 ? fontSize.floorToDouble() : fontSize.ceilToDouble();
    final v = (base + delta).clamp(
      kMinTerminalFontSize,
      kMaxTerminalFontSize,
    );
    if (v != fontSize) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final canEnlarge = fontSize < kMaxTerminalFontSize;
    final canShrink = fontSize > kMinTerminalFontSize;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.format_size),
      tooltip: '调整字号',
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text('当前字号：${fontSize.toStringAsFixed(0)}'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          enabled: canEnlarge,
          onTap: () => _change(_step),
          child: const _MenuRow(icon: Icons.zoom_in, label: '放大'),
        ),
        PopupMenuItem<void>(
          enabled: canShrink,
          onTap: () => _change(-_step),
          child: const _MenuRow(icon: Icons.zoom_out, label: '缩小'),
        ),
        PopupMenuItem<void>(
          onTap: () => onChanged(kDefaultTerminalFontSize),
          child: const _MenuRow(icon: Icons.restart_alt, label: '重置'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
