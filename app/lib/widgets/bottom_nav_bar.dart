import 'package:flutter/widgets.dart';

import 'package:omi/ui/ui.dart';

// Home has no tab bar (v3): its one bottom control is the pinned Ask bar
// (`pages/home/widgets/home_ask_bar.dart`). These give the room scrolled pages keep under it, so
// their last rows can scroll clear of it.

/// The Ask bar's height (v3 Home: 60 pt).
const double kAskBarHeight = 56;

/// The home indicator's inset, or nothing on phones without one.
double bottomNavBarReservedInset(BuildContext context) => MediaQuery.viewPaddingOf(context).bottom;

/// From the bottom of the screen to the Ask bar's bottom edge: 16 pt above the home indicator
/// (v3 `.askw`: bottom calc(safe-area + 16px)), or 16 from the edge on phones without one.
double askBarBottomOffset(BuildContext context) => bottomNavBarReservedInset(context) + OmiSpacing.md;

/// Room scrolled content keeps under the Ask bar.
double bottomNavBarClearance(BuildContext context) => askBarBottomOffset(context) + kAskBarHeight + OmiSpacing.lg;

/// Home keeps the same room under its last section.
double homeChatBarClearance(BuildContext context) => bottomNavBarClearance(context);
