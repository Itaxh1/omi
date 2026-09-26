import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:omi/ui/ui.dart';

// Home has no tab bar (v2.1, the v4 design): its one bottom control is the floating Ask bar
// (`pages/home/widgets/home_ask_bar.dart`). These give the room scrolled pages keep under it, so
// their last rows can scroll clear of it.

/// The Ask bar's full height (v4 Home: 62 pt).
const double kAskBarHeight = 62;

/// The home indicator's inset, or nothing on phones without one.
double bottomNavBarReservedInset(BuildContext context) => MediaQuery.viewPaddingOf(context).bottom;

/// From the bottom of the screen to the Ask bar's bottom edge: just above the home indicator, or
/// the page margin on phones without one.
double askBarBottomOffset(BuildContext context) =>
    math.max(bottomNavBarReservedInset(context) + OmiSpacing.xxs, OmiSize.screenMargin);

/// Room scrolled content keeps under the Ask bar.
double bottomNavBarClearance(BuildContext context) => askBarBottomOffset(context) + kAskBarHeight + OmiSpacing.lg;

/// Home keeps the same room under its last section.
double homeChatBarClearance(BuildContext context) => bottomNavBarClearance(context);
