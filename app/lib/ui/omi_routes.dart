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
