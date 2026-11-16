import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.showRibbon = false,
  });
  final Widget child;
  final bool showRibbon;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(painter: _Backdrop(_drift, widget.showRibbon)),
      ),
      widget.child,
    ],
  );
}

class _Backdrop extends CustomPainter {
  _Backdrop(this.drift, this.ribbon) : super(repaint: drift);
  final Animation<double> drift;
  final bool ribbon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(EdenDarkColors.background, BlendMode.src);
    final wave = math.sin(drift.value * 2 * math.pi);
    final radius = math.max(size.shortestSide * .82, size.longestSide * .36);
    for (final (center, color, opacity) in [
      (
        Offset(size.width * (.91 + wave * .035), size.height * .08),
        EdenDarkColors.accent,
        ribbon ? .16 : .06,
      ),
      (
        Offset(size.width * (.07 - wave * .035), size.height * .91),
        EdenDarkColors.maroon,
        ribbon ? .22 : .08,
      ),
    ]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    final dots = <Offset>[
      for (double y = 8; y < size.height; y += 16)
        for (double x = 8; x < size.width; x += 16) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = EdenDarkColors.grain
        ..strokeWidth = 1.4,
    );
    if (ribbon) {
      final line = Path()
        ..moveTo(-24, size.height * .78)
        ..cubicTo(
          size.width * .36,
          size.height * .48,
          size.width * .72,
          size.height * .8,
          size.width + 24,
          size.height * .38,
        );
      canvas.drawPath(
        line,
        Paint()
          ..color = EdenDarkColors.accent.withValues(alpha: .09)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) =>
      ribbon != oldDelegate.ribbon || drift != oldDelegate.drift;
}
