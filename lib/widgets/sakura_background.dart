import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A soft cherry-blossom (sakura) backdrop: a blossoming branch in the top-right
/// corner with a handful of petals drifting slowly down the screen.
///
/// Deliberately low-contrast so it reads as a texture behind the content rather
/// than competing with it. Sits behind the four main tabs (see [HomeShell]); the
/// readers are never covered by it.
class SakuraBackground extends StatefulWidget {
  const SakuraBackground({super.key});

  @override
  State<SakuraBackground> createState() => _SakuraBackgroundState();
}

class _SakuraBackgroundState extends State<SakuraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Petal> _petals;

  @override
  void initState() {
    super.initState();
    // One slow loop; each petal falls at its own multiple of it.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    // A fixed seed keeps the drift stable across rebuilds.
    final rng = math.Random(7);
    _petals = List.generate(16, (_) {
      return _Petal(
        x: rng.nextDouble(),
        phase: rng.nextDouble(),
        fallSpeed: 0.6 + rng.nextDouble() * 0.9,
        swayFreq: 1.5 + rng.nextDouble() * 2.5,
        sway: 12 + rng.nextDouble() * 26,
        size: 7 + rng.nextDouble() * 7,
        spin: 0.6 + rng.nextDouble() * 1.6,
        depth: 0.35 + rng.nextDouble() * 0.65,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final petalColor = dark ? const Color(0xFFF7A8C4) : const Color(0xFFE86A92);
    final branchColor = dark ? const Color(0xFF7C6472) : const Color(0xFF6E4B45);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _SakuraPainter(
            progress: _controller.value,
            petals: _petals,
            background: scheme.surface,
            petalColor: petalColor,
            branchColor: branchColor,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// A single drifting petal's fixed characteristics; its position is a function
/// of the shared animation progress.
class _Petal {
  const _Petal({
    required this.x,
    required this.phase,
    required this.fallSpeed,
    required this.swayFreq,
    required this.sway,
    required this.size,
    required this.spin,
    required this.depth,
  });

  final double x; // base horizontal position, 0..1
  final double phase; // start offset, 0..1
  final double fallSpeed; // vertical cycles per loop
  final double swayFreq; // horizontal wobbles per fall
  final double sway; // horizontal sway amplitude, px
  final double size; // petal length, px
  final double spin; // rotations per loop
  final double depth; // 0..1, scales size and opacity for a sense of distance
}

class _SakuraPainter extends CustomPainter {
  _SakuraPainter({
    required this.progress,
    required this.petals,
    required this.background,
    required this.petalColor,
    required this.branchColor,
  });

  final double progress;
  final List<_Petal> petals;
  final Color background;
  final Color petalColor;
  final Color branchColor;

  @override
  void paint(Canvas canvas, Size size) {
    // The backdrop paints its own base colour so the host scaffolds can be
    // transparent and let it show through.
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    _paintBranch(canvas, size);
    _paintPetals(canvas, size);
  }

  // ------------------------------------------------------------------ branch

  void _paintBranch(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // A branch reaching in from the top-right corner, arcing down and left.
    final branch = Path()
      ..moveTo(w + 12, -12)
      ..cubicTo(w * 0.82, h * 0.03, w * 0.74, h * 0.10, w * 0.62, h * 0.14)
      ..cubicTo(w * 0.50, h * 0.18, w * 0.42, h * 0.20, w * 0.30, h * 0.19);

    canvas.drawPath(
      branch,
      Paint()
        ..color = branchColor.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );

    // Two twigs off the main branch.
    final twigA = Path()
      ..moveTo(w * 0.74, h * 0.10)
      ..cubicTo(w * 0.78, h * 0.15, w * 0.80, h * 0.19, w * 0.79, h * 0.24);
    final twigB = Path()
      ..moveTo(w * 0.50, h * 0.18)
      ..cubicTo(w * 0.49, h * 0.23, w * 0.47, h * 0.27, w * 0.50, h * 0.31);

    final twigPaint = Paint()
      ..color = branchColor.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(twigA, twigPaint)
      ..drawPath(twigB, twigPaint);

    // Blossom clusters at the branch tips and a few nodes.
    final nodes = <Offset>[
      Offset(w * 0.30, h * 0.19),
      Offset(w * 0.62, h * 0.14),
      Offset(w * 0.79, h * 0.24),
      Offset(w * 0.50, h * 0.31),
      Offset(w * 0.86, h * 0.07),
      Offset(w * 0.45, h * 0.16),
    ];
    for (var i = 0; i < nodes.length; i++) {
      _paintBlossom(canvas, nodes[i], 10 + (i.isEven ? 2.0 : 0.0), 0.22);
    }
    // A couple of buds.
    for (final o in [Offset(w * 0.70, h * 0.075), Offset(w * 0.37, h * 0.175)]) {
      canvas.drawCircle(
        o,
        3,
        Paint()..color = petalColor.withValues(alpha: 0.20),
      );
    }
  }

  /// A five-petal blossom centred at [c].
  void _paintBlossom(Canvas canvas, Offset c, double r, double alpha) {
    final petal = Paint()..color = petalColor.withValues(alpha: alpha);
    for (var i = 0; i < 5; i++) {
      final a = (i / 5) * math.pi * 2 - math.pi / 2;
      final pc = c + Offset(math.cos(a), math.sin(a)) * (r * 0.42);
      canvas.drawCircle(pc, r * 0.42, petal);
    }
    canvas.drawCircle(
      c,
      r * 0.24,
      Paint()..color = petalColor.withValues(alpha: alpha * 1.6),
    );
  }

  // ------------------------------------------------------------------ petals

  void _paintPetals(Canvas canvas, Size size) {
    for (final p in petals) {
      // Vertical progress wraps through a little past the edges so petals fade
      // in above the top and out below the bottom.
      final t = (progress * p.fallSpeed + p.phase) % 1.0;
      final y = t * (size.height + 60) - 30;
      final x = p.x * size.width +
          math.sin(t * math.pi * 2 * p.swayFreq + p.phase * 6.28) * p.sway;
      final angle = progress * math.pi * 2 * p.spin + p.phase * 6.28;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      final len = p.size * p.depth;
      canvas.drawPath(
        _petalPath(len),
        Paint()..color = petalColor.withValues(alpha: 0.10 + p.depth * 0.10),
      );
      canvas.restore();
    }
  }

  /// A small petal shape (a lens with a soft notch at the tip), centred on the
  /// origin, pointing up.
  Path _petalPath(double len) {
    final wide = len * 0.62;
    return Path()
      ..moveTo(0, -len / 2)
      ..quadraticBezierTo(wide, -len * 0.1, wide * 0.5, len / 2)
      ..quadraticBezierTo(0, len * 0.32, -wide * 0.5, len / 2)
      ..quadraticBezierTo(-wide, -len * 0.1, 0, -len / 2)
      ..close();
  }

  @override
  bool shouldRepaint(_SakuraPainter old) =>
      old.progress != progress ||
      old.background != background ||
      old.petalColor != petalColor;
}
