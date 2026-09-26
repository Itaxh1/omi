import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home's one bottom control (v4, in place of the tab bar): "Ask anything" over an example
/// question that changes every few seconds, and the mic. Tapping it opens chat, the mic opens chat
/// listening, and holding it opens Memories. While the reader scrolls down to read it narrows and
/// drops the example and the mic ([compact]), so it covers less of the page.
class HomeAskBar extends StatefulWidget {
  const HomeAskBar({super.key, required this.onOpen, required this.onVoice, this.onHold, required this.compact});

  final VoidCallback onOpen;
  final VoidCallback onVoice;
  final VoidCallback? onHold;
  final ValueListenable<bool> compact;

  static const double compactHeight = 52;
  static const double maxWidth = 370;
  static const double compactWidth = 262;

  /// How long each example question shows.
  static const Duration exampleEvery = Duration(milliseconds: 3400);

  @override
  State<HomeAskBar> createState() => _HomeAskBarState();
}

class _HomeAskBarState extends State<HomeAskBar> {
  Timer? _timer;
  int _example = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One example stays put under Reduce Motion.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(HomeAskBar.exampleEvery, (_) {
        if (mounted) setState(() => _example++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final examples = [l10n.askStarterOpen, l10n.askStarterToday, l10n.askStarterPeople];
    final example = l10n.askTryHint(examples[_example % examples.length]);
    final motion = OmiMotion.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.compact,
      builder: (context, compact, _) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            OmiSize.screenMargin,
            0,
            OmiSize.screenMargin,
            askBarBottomOffset(context),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            // Only as tall as the bar, wherever it is placed.
            heightFactor: 1,
            child: AnimatedContainer(
              duration: motion.standard,
              curve: OmiMotion.springCurve,
              constraints: BoxConstraints(maxWidth: compact ? HomeAskBar.compactWidth : HomeAskBar.maxWidth),
              height: compact ? HomeAskBar.compactHeight : kAskBarHeight,
              child: Semantics(
                button: true,
                label: l10n.askAnything,
                onTap: widget.onOpen,
                onLongPress: widget.onHold,
                excludeSemantics: true,
                child: OmiGlass(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  child: GestureDetector(
                    key: const Key('home_ask_bar'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      OmiHaptics.selection();
                      widget.onOpen();
                    },
                    onLongPress: widget.onHold == null
                        ? null
                        : () {
                            OmiHaptics.medium();
                            widget.onHold!();
                          },
                    child: Padding(
                      padding: EdgeInsets.only(left: OmiSpacing.md, right: compact ? OmiSpacing.md : 7),
                      child: Row(
                        children: [
                          const OmiRingLogo(size: 24, mode: OmiRingMode.breathe, loops: 3),
                          const SizedBox(width: OmiSpacing.sm),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.askAnything,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                                ),
                                if (!compact)
                                  AnimatedSwitcher(
                                    duration: motion.quick,
                                    child: Text(
                                      example,
                                      key: ValueKey(example),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: OmiType.footnote.copyWith(
                                        color: OmiColors.textTertiary,
                                        fontWeight: FontWeight.w500,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: OmiSpacing.sm),
                            _MicButton(onTap: widget.onVoice),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Talk to Omi: a 46 pt lens with the mic.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: OmiDockLens(animate: false)),
              Icon(Icons.mic_none_rounded, size: 21, color: OmiColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
