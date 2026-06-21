import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/precipitation_effect_mode.dart';

class PrecipitationOverlay extends StatefulWidget {
  const PrecipitationOverlay({super.key, required this.mode});

  final PrecipitationEffectMode mode;

  @override
  State<PrecipitationOverlay> createState() => _PrecipitationOverlayState();
}

class _PrecipitationOverlayState extends State<PrecipitationOverlay>
    with SingleTickerProviderStateMixin {
  late final List<_Particle> _particles;
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    final random = math.Random(20261221);
    _particles = List.generate(92, (_) => _Particle.random(random));
    _ticker = createTicker((elapsed) {
      setState(() => _elapsed = elapsed);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PrecipitationPainter(
            mode: widget.mode,
            particles: _particles,
            elapsedSeconds:
                _elapsed.inMicroseconds / Duration.microsecondsPerSecond,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.xSeed,
    required this.ySeed,
    required this.radius,
    required this.speed,
    required this.drift,
    required this.phase,
    required this.opacity,
    required this.rotation,
  });

  factory _Particle.random(math.Random random) {
    final near = random.nextDouble();
    return _Particle(
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

class _PrecipitationPainter extends CustomPainter {
  const _PrecipitationPainter({
    required this.mode,
    required this.particles,
    required this.elapsedSeconds,
  });

  final PrecipitationEffectMode mode;
  final List<_Particle> particles;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final strokePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    final fallArea = size.height + 56;

    for (final particle in particles) {
      final speed = _speedForMode(particle);
      final y =
          (particle.ySeed * fallArea + elapsedSeconds * speed) % fallArea - 28;
      final wave = math.sin(elapsedSeconds * 0.9 + particle.phase);
      final drift = mode == PrecipitationEffectMode.rain
          ? particle.drift * 0.18
          : particle.drift;
      final x = (particle.xSeed * size.width + wave * drift) % size.width;
      final center = Offset(x < 0 ? x + size.width : x, y);
      final alpha = particle.opacity.clamp(0.0, 1.0);

      switch (mode) {
        case PrecipitationEffectMode.snow:
          _paintSnow(canvas, strokePaint, fillPaint, particle, center, alpha);
        case PrecipitationEffectMode.rain:
          _paintRain(canvas, strokePaint, particle, center, alpha);
        case PrecipitationEffectMode.hail:
          _paintHail(canvas, fillPaint, particle, center, alpha);
      }
    }
  }

  double _speedForMode(_Particle particle) {
    return switch (mode) {
      PrecipitationEffectMode.snow => particle.speed,
      PrecipitationEffectMode.rain => particle.speed * 2.8,
      PrecipitationEffectMode.hail => particle.speed * 1.65,
    };
  }

  void _paintSnow(
    Canvas canvas,
    Paint strokePaint,
    Paint fillPaint,
    _Particle particle,
    Offset center,
    double alpha,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(particle.rotation + elapsedSeconds * math.pi * 0.08);

    strokePaint
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = (particle.radius * 0.16).clamp(0.7, 1.35);
    fillPaint.color = Colors.white.withValues(alpha: alpha * 0.9);

    _drawSnowCrystal(canvas, strokePaint, fillPaint, particle.radius);
    canvas.restore();
  }

  void _paintRain(
    Canvas canvas,
    Paint strokePaint,
    _Particle particle,
    Offset center,
    double alpha,
  ) {
    final length = particle.radius * 4.2 + 8;
    strokePaint
      ..color = const Color(0xFFE3F2FD).withValues(alpha: alpha * 0.72)
      ..strokeWidth = (particle.radius * 0.18).clamp(0.75, 1.45);
    canvas.drawLine(
      Offset(center.dx, center.dy - length * 0.5),
      Offset(center.dx, center.dy + length * 0.5),
      strokePaint,
    );
  }

  void _paintHail(
    Canvas canvas,
    Paint fillPaint,
    _Particle particle,
    Offset center,
    double alpha,
  ) {
    fillPaint.color = Colors.white.withValues(alpha: alpha * 0.86);
    canvas.drawCircle(
      center,
      (particle.radius * 0.58).clamp(1.7, 4.6),
      fillPaint,
    );
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
  bool shouldRepaint(_PrecipitationPainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.elapsedSeconds != elapsedSeconds ||
        oldDelegate.particles != particles;
  }
}
