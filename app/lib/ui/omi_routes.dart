import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:omi/ui/omi_sheet_depth.dart';

/// A page route that keeps the platform's own transition and back gesture: a
/// [CupertinoPageRoute] on iOS (edge-swipe back works) and a [MaterialPageRoute] elsewhere.
///
/// Pushing a page: call `routeToPage(context, page)` (utils/other/temp.dart), which picks the same
/// routes. Use [omiPageRoute] only where code needs a [Route] object — `pushReplacement`,
/// `pushAndRemoveUntil`, a route returned from a navigator callback.
///
/// Never build a `PageRouteBuilder` for a push: it has no iOS back-swipe. Custom transitions are
/// only for modals that carry an explicit `OmiCloseButton`. Set [fullscreenDialog] for a
/// full-screen modal (slides up, has no back swipe, and its header uses a close X, not a back
/// chevron). The page recedes behind any bottom sheet opened over it ([OmiSheetRecede]).
Route<T> omiPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
  bool maintainState = true,
}) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return CupertinoPageRoute<T>(
        builder: (context) => OmiSheetRecede(child: builder(context)),
        settings: settings,
        fullscreenDialog: fullscreenDialog,
        maintainState: maintainState,
      );
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return MaterialPageRoute<T>(
        builder: (context) => OmiSheetRecede(child: builder(context)),
        settings: settings,
        fullscreenDialog: fullscreenDialog,
        maintainState: maintainState,
      );
  }
}

/// Ask (v3 `#chat`): a full-screen modal that rises from the bottom over 0.42 s on the design's
/// sheet curve, cubic-bezier(.32,.72,0,1), and falls back when its close ring pops it. It carries
/// its own close control, so it has no back swipe (see [omiPageRoute]). Under Reduce Motion it
/// fades.
Route<T> omiAskRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) {
  const curve = Cubic(0.32, 0.72, 0, 1);
  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (context, _, __) => OmiSheetRecede(child: builder(context)),
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return FadeTransition(opacity: animation, child: child);
      }
      final rise = CurvedAnimation(parent: animation, curve: curve, reverseCurve: curve.flipped);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1.05), end: Offset.zero).animate(rise),
        child: child,
      );
    },
  );
}

/// The full live transcript (v8.16 `.osfull`): fades in over 0.22 s while it settles 0.8 % upward,
/// and fades out over 0.18 s. Under Reduce Motion it only fades.
Route<T> omiFadeUpRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final fade = FadeTransition(opacity: animation, child: child);
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return fade;
      return SlideTransition(
        position: Tween(begin: const Offset(0, 0.008), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: fade,
      );
    },
  );
}

/// Your Omi (v8.4 `#omisc`): the screen unrolls down from the Listening label over 0.46 s on the
/// sheet spring. It is revealed from the top edge down (its lower corners rounded by 40 pt while it
/// moves), comes down from 14 pt higher and fades in over the first 0.12 s. Under Reduce Motion it
/// only fades.
Route<T> omiUnrollRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) {
  const curve = Cubic(0.32, 0.72, 0, 1);
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 460),
    reverseTransitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return FadeTransition(opacity: animation, child: child);
      }
      final unroll = CurvedAnimation(parent: animation, curve: curve, reverseCurve: curve.flipped);
      final fade = CurvedAnimation(parent: animation, curve: const Interval(0, 0.26));
      return AnimatedBuilder(
        animation: unroll,
        child: child,
        builder: (context, child) {
          final t = unroll.value.clamp(0.0, 1.0);
          return FadeTransition(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(0, -14 * (1 - t)),
              child: ClipPath(clipper: _UnrollClipper(t), child: child),
            ),
          );
        },
      );
    },
  );
}

/// The part of the page shown [t] of the way through the unroll: from the top down, the lower
/// corners rounded until it is fully open.
class _UnrollClipper extends CustomClipper<Path> {
  const _UnrollClipper(this.t);

  final double t;

  @override
  Path getClip(Size size) {
    if (t >= 1) return Path()..addRect(Offset.zero & size);
    final radius = Radius.circular(40 * (1 - t));
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, size.height * t),
        bottomLeft: radius,
        bottomRight: radius,
      ));
  }

  @override
  bool shouldReclip(_UnrollClipper old) => old.t != t;
}
