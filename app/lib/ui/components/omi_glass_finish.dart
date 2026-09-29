import 'package:flutter/material.dart';

/// A still, neutral reflection following the actual capsule/circle contour.
/// Paints behind the label and never changes layout, colour tokens or gestures.
class OmiGlassFinish extends StatelessWidget {
  const OmiGlassFinish({super.key, required this.radius, required this.child, required this.light});

  final BorderRadius radius;
  final Widget child;
  final bool light;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _GlassReflection(radius, light),
        child: child,
      );
}

class _GlassReflection extends CustomPainter {
  const _GlassReflection(this.radius, this.light);

  final BorderRadius radius;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final shape = radius.toRRect(bounds.deflate(0.7));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: light ? 0.34 : 0.10),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: light ? 0.08 : 0.025),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: light ? 0.95 : 0.42),
            Colors.white.withValues(alpha: light ? 0.25 : 0.06),
            Colors.white.withValues(alpha: light ? 0.65 : 0.22),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlassReflection oldDelegate) => radius != oldDelegate.radius || light != oldDelegate.light;

  @override
  bool hitTest(Offset position) => false;
}
