import 'dart:math' as math;

import 'package:flutter/material.dart';

class SnowfallOverlay extends StatefulWidget {
  const SnowfallOverlay({super.key});

  @override
  State<SnowfallOverlay> createState() => _SnowfallOverlayState();
}

class _SnowfallOverlayState extends State<SnowfallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Snowflake> _flakes;

  @override
  void initState() {
    super.initState();
    final random = math.Random(20261221);
    _flakes = List.generate(86, (_) => _Snowflake.random(random));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _SnowfallPainter(
                flakes: _flakes,
                progress: _controller.value,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _Snowflake {
  const _Snowflake({
    required this.xSeed,
    required this.ySeed,
    required this.radius,
    required this.speed,
    required this.drift,
    required this.phase,
    required this.opacity,
    required this.rotation,
  });

  factory _Snowflake.random(math.Random random) {
    final near = random.nextDouble();
    return _Snowflake(
      xSeed: random.nextDouble(),
      ySeed: random.nextDouble(),
      radius: 2.2 + near * 5.4,
      speed: 34 + near * 66,
      drift: 10 + random.nextDouble() * 28,
      phase: random.nextDouble() * math.pi * 2,
      opacity: 0.34 + near * 0.5,
      rotation: (random.nextDouble() - 0.5) * math.pi * 2,
    );
  }

  final double xSeed;
  final double ySeed;
  final double radius;
  final double speed;
  final double drift;
  final double phase;
  final double opacity;
  final double rotation;
}

class _SnowfallPainter extends CustomPainter {
  const _SnowfallPainter({required this.flakes, required this.progress});

  final List<_Snowflake> flakes;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const cycleSeconds = 24.0;
    final elapsed = progress * cycleSeconds;
    final fallArea = size.height + 48;

    for (final flake in flakes) {
      final y =
          (flake.ySeed * fallArea + elapsed * flake.speed) % fallArea - 24;
      final wave = math.sin(progress * math.pi * 2 + flake.phase);
      final x = (flake.xSeed * size.width + wave * flake.drift) % size.width;
      final center = Offset(x < 0 ? x + size.width : x, y);
      final alpha = flake.opacity.clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(flake.rotation + progress * math.pi * 0.8);

      paint
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = (flake.radius * 0.16).clamp(0.7, 1.35);
      fillPaint.color = Colors.white.withValues(alpha: alpha * 0.9);

      _drawSnowCrystal(canvas, paint, fillPaint, flake.radius);
      canvas.restore();
    }
  }

  void _drawSnowCrystal(
    Canvas canvas,
    Paint paint,
    Paint fillPaint,
    double radius,
  ) {
    canvas.drawCircle(Offset.zero, radius * 0.14, fillPaint);

    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final tip = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      canvas.drawLine(Offset.zero, tip, paint);

      final branchBase = Offset(
        math.cos(angle) * radius * 0.58,
        math.sin(angle) * radius * 0.58,
      );
      final branchLength = radius * 0.32;
      final leftAngle = angle - math.pi / 5;
      final rightAngle = angle + math.pi / 5;
      canvas.drawLine(
        branchBase,
        branchBase +
            Offset(
              math.cos(leftAngle) * branchLength,
              math.sin(leftAngle) * branchLength,
            ),
        paint,
      );
      canvas.drawLine(
        branchBase,
        branchBase +
            Offset(
              math.cos(rightAngle) * branchLength,
              math.sin(rightAngle) * branchLength,
            ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SnowfallPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.flakes != flakes;
  }
}
