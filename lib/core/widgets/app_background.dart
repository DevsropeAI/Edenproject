import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum MainBackdrop { home, orders, support, profile }

class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.showRibbon = false,
    this.mainBackdrop,
  });
  final Widget child;
  final bool showRibbon;
  final MainBackdrop? mainBackdrop;

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
        child: CustomPaint(
          painter: _Backdrop(_drift, widget.showRibbon, widget.mainBackdrop),
        ),
      ),
      widget.child,
    ],
  );
}

class _Backdrop extends CustomPainter {
  _Backdrop(this.drift, this.ribbon, this.mainBackdrop) : super(repaint: drift);
  final Animation<double> drift;
  final bool ribbon;
  final MainBackdrop? mainBackdrop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(EdenDarkColors.background, BlendMode.src);
    final wave = math.sin(drift.value * 2 * math.pi);
    final radius = math.max(size.shortestSide * .82, size.longestSide * .36);
    final (accent, maroon) = switch (mainBackdrop) {
      MainBackdrop.home => (const Offset(.94, .14), const Offset(.09, .83)),
      MainBackdrop.orders => (const Offset(.05, .32), const Offset(.86, .93)),
      MainBackdrop.support => (const Offset(.88, .55), const Offset(.15, .94)),
      MainBackdrop.profile => (const Offset(.50, .06), const Offset(.96, .87)),
      null => (const Offset(.91, .08), const Offset(.07, .91)),
    };
    Offset position(Offset anchor, double drift) =>
        Offset(size.width * (anchor.dx + drift), size.height * anchor.dy);
    for (final (center, color, opacity) in [
      (
        position(accent, wave * .035),
        EdenDarkColors.accent,
        mainBackdrop != null ? .23 : (ribbon ? .16 : .06),
      ),
      (
        position(maroon, -wave * .035),
        EdenDarkColors.maroon,
        mainBackdrop != null ? .31 : (ribbon ? .22 : .08),
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
    if (ribbon || mainBackdrop != null) {
      final (start, first, second, end) = switch (mainBackdrop) {
        MainBackdrop.orders => (.24, .63, .33, .72),
        MainBackdrop.support => (.87, .50, .30, .52),
        MainBackdrop.profile => (.42, .74, .67, .88),
        _ => (.78, .48, .80, .38),
      };
      final line = Path()
        ..moveTo(-24, size.height * start)
        ..cubicTo(
          size.width * .36,
          size.height * first,
          size.width * .72,
          size.height * second,
          size.width + 24,
          size.height * end,
        );
      canvas.drawPath(
        line,
        Paint()
          ..color = EdenDarkColors.accent.withValues(
            alpha: mainBackdrop == null ? .09 : .13,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) =>
      ribbon != oldDelegate.ribbon ||
      mainBackdrop != oldDelegate.mainBackdrop ||
      drift != oldDelegate.drift;
}
