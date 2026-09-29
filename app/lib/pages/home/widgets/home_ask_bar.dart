import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home's one bottom control (v8.2): a 56 pt liquid-glass capsule pinned 16 pt above the home
/// indicator, "Ask anything" centred at 16.5/500 in ink. Tapping it opens Ask; holding it opens
/// Memories. The mic is gone (v8.1): Ask is typed.
class HomeAskBar extends StatelessWidget {
  const HomeAskBar({super.key, required this.onOpen, this.onHold});

  final VoidCallback onOpen;
  final VoidCallback? onHold;

  /// The bar's side inset (the design: 18 pt).
  static const double sideInset = 18;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideInset, 0, sideInset, askBarBottomOffset(context)),
      child: Semantics(
        button: true,
        label: l10n.askAnything,
        onTap: onOpen,
        onLongPress: onHold,
        excludeSemantics: true,
        child: OmiPressable(
          key: const Key('home_ask_bar'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            OmiHaptics.selection();
            onOpen();
          },
          onLongPress: onHold == null
              ? null
              : () {
                  OmiHaptics.medium();
                  onHold!();
                },
          child: SizedBox(
            height: kAskBarHeight,
            child: OmiLiquidGlass(
              polished: true,
              borderRadius: const BorderRadius.all(Radius.circular(30)),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.askAnything,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OmiType.askBar.copyWith(color: OmiColors.textPrimary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
