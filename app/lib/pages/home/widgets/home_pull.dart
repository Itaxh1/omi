import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home's two pulls (v8.6, v8.14). Pulled down from the top, the page follows the finger (fully to
/// 126 pt, then a quarter as far) and the Listening label says "Pull to pause", then "Release to
/// pause"; letting go past 126 pt acts ([onPullDown]). Pulled up from the bottom, the page rises up
/// to 46 pt while eight dots fill over 210 pt ([up]); letting go once they are full opens Your Omi
/// ([onPullUp]). Either way the page springs back (0.38 s). A tick of haptics marks the point where
/// letting go will act.
class HomePullGestures extends StatefulWidget {
  const HomePullGestures({
    super.key,
    required this.child,
    required this.down,
    required this.up,
    required this.onPullDown,
    required this.onPullUp,
  });

  final Widget child;

  /// How far the pull down has gone, for the label.
  final ValueNotifier<HomePullPhase> down;

  /// How far the pull up has gone, 0 to 1, for [HomePullUpHint].
  final ValueNotifier<double> up;

  final VoidCallback onPullDown;
  final VoidCallback onPullUp;

  /// Past this (points of finger travel), letting go of a pull down acts.
  static const double downThreshold = 126;

  /// The finger travel that fills the pull up's dots.
  static const double upDistance = 210;

  /// The page's travel for [finger] points pulled down: all of it to [downThreshold], then a
  /// quarter.
  static double easedDown(double finger) {
    final d = math.max(0.0, finger);
    return d < downThreshold ? d * 0.6 : downThreshold * 0.6 + (d - downThreshold) * 0.25;
  }

  @override
  State<HomePullGestures> createState() => _HomePullGesturesState();
}

enum _Pull { down, up }

class _HomePullGesturesState extends State<HomePullGestures> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);
  late final AnimationController _back;
  static const Curve _springBack = Cubic(0.34, 1.3, 0.64, 1);
  double _backFrom = 0;

  Offset? _start;
  _Pull? _mode;
  bool _atTop = true;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() => _offset.value = _backFrom * (1 - _springBack.transform(_back.value)));
  }

  @override
  void dispose() {
    _back.dispose();
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) _track(n.metrics);
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) _track(n.metrics);
    return false;
  }

  void _track(ScrollMetrics m) {
    _atTop = m.pixels <= m.minScrollExtent + 0.5;
    _atBottom = m.pixels >= m.maxScrollExtent - 60;
  }

  void _down(PointerDownEvent e) {
    if (_back.isAnimating) {
      _back.stop();
      _offset.value = 0;
    }
    _start = e.position;
    _mode = null;
  }

  void _move(PointerMoveEvent e) {
    final start = _start;
    if (start == null) return;
    final d = e.position - start;
    if (_mode == null) {
      final vertical = d.dy.abs() > d.dx.abs();
      if (d.dy > 8 && vertical && _atTop) {
        _mode = _Pull.down;
      } else if (d.dy < -10 && vertical && _atBottom) {
        _mode = _Pull.up;
      } else if (d.dx.abs() > 12 || d.dy.abs() > 24) {
        _start = null;
        return;
      } else {
        return;
      }
    }
    if (_mode == _Pull.down) {
      _offset.value = HomePullGestures.easedDown(d.dy);
      final phase = d.dy >= HomePullGestures.downThreshold ? HomePullPhase.ready : HomePullPhase.pulling;
      if (phase == HomePullPhase.ready && widget.down.value != HomePullPhase.ready) OmiHaptics.light();
      widget.down.value = phase;
    } else {
      final p = (-d.dy / HomePullGestures.upDistance).clamp(0.0, 1.0);
      if (p >= 1 && widget.up.value < 1) OmiHaptics.light();
      widget.up.value = p;
      _offset.value = -math.min(46.0, math.max(0.0, -d.dy) * 0.3);
    }
  }

  void _end({required bool cancelled}) {
    final mode = _mode;
    _start = null;
    _mode = null;
    if (mode == null) return;
    final fire = !cancelled && (mode == _Pull.down ? widget.down.value == HomePullPhase.ready : widget.up.value >= 1);
    widget.down.value = HomePullPhase.none;
    if (mode == _Pull.up) {
      // The dots fade with the hint, then empty.
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) widget.up.value = 0;
      });
    }
    _springBackFrom(_offset.value);
    if (!fire) return;
    // Pausing, resuming or starting listening is the firm one; opening Your Omi is a tap.
    mode == _Pull.down ? OmiHaptics.medium() : OmiHaptics.selection();
    if (mode == _Pull.down) {
      widget.onPullDown();
    } else {
      widget.onPullUp();
    }
  }

  void _springBackFrom(double from) {
    if (from == 0) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _offset.value = 0;
      return;
    }
    _backFrom = from;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (_) => _end(cancelled: false),
      onPointerCancel: (_) => _end(cancelled: true),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ValueListenableBuilder<double>(
            valueListenable: _offset,
            child: widget.child,
            builder: (context, offset, child) =>
                offset == 0 ? child! : Transform.translate(offset: Offset(0, offset), child: child),
          ),
        ),
      ),
    );
  }
}

/// The pull up's hint (v8.14 `.pullup`), just above the Ask bar: eight dots in a ring that fill as
/// the pull goes, over "Pull up for Your Omi", then "Release to open" with a small pop. Invisible
/// until the pull starts.
class HomePullUpHint extends StatelessWidget {
  const HomePullUpHint({super.key, required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.only(bottom: askBarBottomOffset(context) + kAskBarHeight + 14),
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, p, _) {
            final ready = p >= 1;
            final lit = (p * 8 + 0.0001).floor();
            return Opacity(
              opacity: math.min(1, p * 3),
              child: Column(
                key: const Key('home_pull_up'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    key: ValueKey(ready),
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: ready ? 300 : 0),
                    builder: (context, t, child) =>
                        Transform.scale(scale: ready ? 1 + 0.15 * math.sin(t * math.pi) : 1, child: child),
                    child: SizedBox.square(
                      dimension: 40,
                      child: CustomPaint(painter: _DotsPainter(lit: lit, color: OmiColors.textPrimary)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ready ? l10n.releaseToOpen : l10n.pullUpForYourOmi,
                    style: OmiType.cardSubtitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ready ? OmiColors.textPrimary : OmiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Eight dots on a ring (`.pud`), the first [lit] in full ink and the rest at 14 %.
class _DotsPainter extends CustomPainter {
  const _DotsPainter({required this.lit, required this.color});

  final int lit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = size.width * 0.36;
    final r = size.width * 0.08;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final p = c + Offset(math.sin(a) * ring, -math.cos(a) * ring);
      canvas.drawCircle(p, r, Paint()..color = color.withValues(alpha: i < lit ? 1 : 0.14));
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.lit != lit || old.color != color;
}

/// The first-run teaching (v8.1) and its bookkeeping: the tip under the Listening label shows once;
/// on the third open, if the reader has never tapped the mark, the ring pulses once more.
abstract final class HomeTeach {
  static const String _taught = 'home/omiTaught';
  static const String _tapped = 'home/omiTapped';
  static const String _nudged = 'home/omiNudged';
  static const String _opens = 'home/omiOpens';

  static bool get taught => SharedPreferencesUtil().getBool(_taught);

  static void markTaught() => SharedPreferencesUtil().saveBool(_taught, true);

  static void markTapped() => SharedPreferencesUtil().saveBool(_tapped, true);

  /// Counts this open and says what to show: the tip (never taught), a single nudge pulse (third
  /// open, never tapped, never nudged), or nothing.
  static ({bool tip, bool nudge}) onHomeOpened() {
    final prefs = SharedPreferencesUtil();
    final opens = prefs.getInt(_opens) + 1;
    prefs.saveInt(_opens, opens);
    if (!taught) return (tip: true, nudge: false);
    if (opens >= 3 && !prefs.getBool(_tapped) && !prefs.getBool(_nudged)) {
      prefs.saveBool(_nudged, true);
      return (tip: false, nudge: true);
    }
    return (tip: false, nudge: false);
  }
}

/// The tip (`.tip`): an ink card under the Listening label with a small arrow, "This is Omi." and
/// what the moving dots mean, and Got it. It drops in 6 pt over 0.35 s.
class HomeTeachTip extends StatelessWidget {
  const HomeTeachTip({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = math.min(300.0, MediaQuery.sizeOf(context).width - 40);
    final paper = OmiColors.surface0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: OmiMotion.of(context).standard == Duration.zero ? Duration.zero : const Duration(milliseconds: 350),
      curve: const Cubic(0.2, 0.8, 0.2, 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -6 * (1 - t)), child: child),
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The arrow pointing up at the label.
              Positioned(
                top: -6,
                left: width / 2 - 6,
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: OmiColors.accent,
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
              Container(
                key: const Key('home_teach_tip'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: OmiColors.accent,
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), offset: const Offset(0, 12), blurRadius: 30)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.thisIsOmi,
                        style: OmiType.callout.copyWith(fontWeight: FontWeight.w700, height: 1.4, color: paper)),
                    const SizedBox(height: 2),
                    Text(l10n.teachTipBody, style: OmiType.detail.copyWith(height: 1.4, color: paper)),
                    const SizedBox(height: 10),
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        key: const Key('home_teach_got_it'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          OmiHaptics.selection();
                          onDone();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: paper,
                              borderRadius: const BorderRadius.all(Radius.circular(18)),
                            ),
                            child: Center(
                              widthFactor: 1,
                              child: Text(l10n.gotItV3,
                                  style: OmiType.detail
                                      .copyWith(fontWeight: FontWeight.w600, color: OmiColors.textPrimary)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ring that pulses out from the mark (`.tring`): 2 pt of ink from 80 % to 160 % while fading
/// from half to nothing, 1.4 s a pulse, [times] times, whenever [trigger] changes.
class HomeTeachRing extends StatefulWidget {
  const HomeTeachRing({super.key, required this.trigger, required this.size});

  /// A new value plays the pulses: the count is how many.
  final ValueListenable<int> trigger;
  final double size;

  @override
  State<HomeTeachRing> createState() => _HomeTeachRingState();
}

class _HomeTeachRingState extends State<HomeTeachRing> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  int _left = 0;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_play);
    _pulse.addStatusListener((status) {
      if (status == AnimationStatus.completed && --_left > 0) _pulse.forward(from: 0);
    });
  }

  void _play() {
    final times = widget.trigger.value;
    if (times <= 0 || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    _left = times;
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_play);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          if (!_pulse.isAnimating) return SizedBox.square(dimension: widget.size);
          final t = Curves.easeOut.transform(_pulse.value);
          return Opacity(
            opacity: 0.5 * (1 - t),
            child: Transform.scale(
              scale: 0.8 + 0.8 * t,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: OmiColors.textPrimary, width: 2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
