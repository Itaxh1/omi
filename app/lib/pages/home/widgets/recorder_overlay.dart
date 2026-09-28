import 'package:flutter/material.dart';

import 'package:omi/pages/conversations/widgets/processing_capture.dart';
import 'package:omi/pages/home/widgets/recorder_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// The recorder card over Home (v3 §4.2): it rises from the bottom, just above the Ask bar, with
/// 14 pt side insets, when the Listening label opens it. A tap anywhere outside closes it and is
/// swallowed, so the row underneath never opens. The card itself is the capture widget in its
/// recorder dress: live rows while something records, the idle card (Start) otherwise.
class RecorderCardOverlay extends StatelessWidget {
  const RecorderCardOverlay({super.key, required this.open});

  final ValueNotifier<bool> open;

  static const double sideInset = 14;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: open,
      builder: (context, isOpen, _) {
        if (!isOpen) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: ModalBarrier(
                key: const Key('recorder_barrier'),
                color: Colors.transparent,
                dismissible: true,
                semanticsLabel: context.l10n.close,
                onDismiss: () => open.value = false,
              ),
            ),
            Positioned(
              left: sideInset,
              right: sideInset,
              bottom: askBarBottomOffset(context) + kAskBarHeight + sideInset,
              child: const _Rise(
                child: ConversationCaptureWidget(showsCall: true, recorder: true, idle: RecorderIdleCard()),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The card's entrance: from 18 pt lower at 97 %, with a slight spring.
class _Rise extends StatelessWidget {
  const _Rise({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: OmiMotion.of(context).emphasized,
      curve: OmiMotion.springCurve,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: Transform.scale(scale: 0.97 + 0.03 * t, alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    );
  }
}
