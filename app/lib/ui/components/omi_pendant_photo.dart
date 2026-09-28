import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:omi/gen/assets.gen.dart';
import 'package:omi/ui/omi_tokens.dart';

/// What the pendant's LED shows (the design's `data-led`).
enum OmiPendantLed {
  /// Unlit: the LED is a faint white point.
  off,

  /// On, not paired yet.
  red,

  /// On and connected.
  blue,

  /// Charging: blinks green.
  greenBlink,
}

/// The pendant photo with its LED drawn over it (v3 `.pend2`): the device from above, a 9 pt LED
/// at its centre that glows in the state's colour, the pulsing ring that shows where to press
/// ([hint]), and the rings that ripple out while searching ([ripples]). Pressing scales it by
/// 0.97 ([pressed]).
class OmiPendantPhoto extends StatefulWidget {
  const OmiPendantPhoto({
    super.key,
    this.size = 180,
    this.led = OmiPendantLed.off,
    this.hint = false,
    this.ripples = false,
    this.pressed = false,
  });

  final double size;
  final OmiPendantLed led;
  final bool hint;
  final bool ripples;
  final bool pressed;

  // The LED's own colours, as the design draws them.
  static const Color _red = Color(0xFFFF6259);
  static const Color _redGlow = Color(0xFFFF5046);
  static const Color _blue = Color(0xFF7FB0FF);
  static const Color _blueGlow = Color(0xFF5A96FF);
  static const Color _green = Color(0xFF6BE39A);
  static const Color _greenGlow = Color(0xFF50DC8C);

  @override
  State<OmiPendantPhoto> createState() => _OmiPendantPhotoState();
}

class _OmiPendantPhotoState extends State<OmiPendantPhoto> with TickerProviderStateMixin {
  // `pressHint` 2 s, `ping` 2.4 s (three rings 0.8 s apart), `ledBlink` 1.6 s.
  late final AnimationController _hint = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  late final AnimationController _ripple =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(OmiPendantPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _run(AnimationController controller, bool on) {
    if (on && !_still) {
      if (!controller.isAnimating) controller.repeat();
    } else {
      controller
        ..stop()
        ..value = 0;
    }
  }

  void _sync() {
    _run(_hint, widget.hint);
    _run(_ripple, widget.ripples);
    _run(_blink, widget.led == OmiPendantLed.greenBlink);
  }

  @override
  void dispose() {
    _hint.dispose();
    _ripple.dispose();
    _blink.dispose();
    super.dispose();
  }

  /// `pressHint`: 0 % transparent at 1.25×, 25–45 % at 0.9 opacity and 0.8×, 70 % gone at 1.1×.
  static (double, double) _hintAt(double t) {
    double lerp(double a, double b, double f) => a + (b - a) * f;
    if (t < 0.25) {
      final f = Curves.easeOut.transform(t / 0.25);
      return (lerp(0, 0.9, f), lerp(1.25, 0.8, f));
    }
    if (t < 0.45) return (0.9, 0.8);
    if (t < 0.7) {
      final f = Curves.easeOut.transform((t - 0.45) / 0.25);
      return (lerp(0.9, 0, f), lerp(0.8, 1.1, f));
    }
    return (0, 1.1);
  }

  Widget _led() {
    final (Color? core, Color? glow) = switch (widget.led) {
      OmiPendantLed.off => (null, null),
      OmiPendantLed.red => (OmiPendantPhoto._red, OmiPendantPhoto._redGlow),
      OmiPendantLed.blue => (OmiPendantPhoto._blue, OmiPendantPhoto._blueGlow),
      OmiPendantLed.greenBlink => (OmiPendantPhoto._green, OmiPendantPhoto._greenGlow),
    };
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: core ?? const Color(0x59FFFFFF),
        boxShadow: glow == null
            ? const []
            : [
                BoxShadow(color: glow.withValues(alpha: 0.62), blurRadius: 10, spreadRadius: 4),
                BoxShadow(color: glow.withValues(alpha: 0.24), blurRadius: 34, spreadRadius: 14),
              ],
      ),
    );
    if (widget.led != OmiPendantLed.greenBlink) return dot;
    return AnimatedBuilder(
      animation: _blink,
      child: dot,
      // `ledBlink`: down to 0.15 halfway, back up.
      builder: (context, child) =>
          Opacity(opacity: 1 - 0.85 * math.sin(_blink.value * math.pi).clamp(0.0, 1.0), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: s,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.ripples)
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: -18,
                  top: -18,
                  right: -18,
                  bottom: -18,
                  child: AnimatedBuilder(
                    animation: _ripple,
                    builder: (context, _) {
                      // Each ring starts 0.8 s after the one before; none shows before its start.
                      final elapsed = _ripple.lastElapsedDuration?.inMilliseconds ?? 0;
                      if (elapsed < i * 800) return const SizedBox.shrink();
                      final t = (_ripple.value - i / 3) % 1;
                      final eased = Curves.easeOut.transform(t);
                      return Opacity(
                        opacity: 0.8 * (1 - eased),
                        child: Transform.scale(
                          scale: 0.1 + 0.9 * eased,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            AnimatedScale(
              scale: widget.pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              child: Image.asset(
                Assets.images.omiWithoutRopeTurnedOff.path,
                width: s,
                height: s,
                fit: BoxFit.contain,
                cacheWidth: (s * MediaQuery.devicePixelRatioOf(context)).round(),
                gaplessPlayback: true,
              ),
            ),
            _led(),
            if (widget.hint)
              AnimatedBuilder(
                animation: _hint,
                builder: (context, _) {
                  final (opacity, scale) = _hintAt(_hint.value);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xD9FFFFFF), width: 2),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
