import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home's one bottom control (v3): a 60 pt capsule pinned above the home indicator, ink in White
/// and paper in Black, with "Ask anything" on the left and a round mic on the right. Tapping it
/// opens chat, the mic opens chat listening, and holding it opens Memories.
class HomeAskBar extends StatelessWidget {
  const HomeAskBar({super.key, required this.onOpen, required this.onVoice, this.onHold});

  final VoidCallback onOpen;
  final VoidCallback onVoice;
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
        child: GestureDetector(
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
          child: Container(
            height: kAskBarHeight,
            decoration: BoxDecoration(
              color: OmiColors.accent,
              borderRadius: OmiRadius.pillAll,
              // `.askw`: 0 12px 28px, a soft shadow.
              boxShadow: [BoxShadow(color: OmiColors.shadowSoft, offset: const Offset(0, 12), blurRadius: 28)],
            ),
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.askAnything,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OmiType.callout.copyWith(color: OmiColors.onAccent, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: OmiSpacing.sm),
                _MicButton(onTap: onVoice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Talk to Omi: a 44 pt ring on the bar.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = OmiColors.onAccent;
    return Semantics(
      button: true,
      label: context.l10n.voiceMode,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        key: const Key('home_ask_mic'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink.withValues(alpha: 0.5), width: 1.5),
          ),
          alignment: Alignment.center,
          child: OmiGlyph(OmiGlyphs.mic, size: 20, color: ink),
        ),
      ),
    );
  }
}
