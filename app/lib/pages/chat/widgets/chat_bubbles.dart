import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';

// The two shapes a chat turn takes: the user's solid pill (see `user_message.dart`) and Omi's
// answer card, a white card with a hairline and a soft shadow, the way Home's glass controls sit
// on the canvas. Cards inside an answer (a task, a chart, a failed reply) stay white and take a
// warm hairline instead of a fill, so the answer reads as one surface.

/// The warm hairline around a card that sits inside an answer card.
BorderSide chatInnerCardSide() => BorderSide(color: OmiColors.deviceTileInk.withValues(alpha: 0.28));

/// Omi's answer: a round white card with a hairline edge and a small lift.
class ChatAnswerCard extends StatelessWidget {
  const ChatAnswerCard({super.key, required this.child, this.padding = contentPadding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Room for 17 pt text to sit inside the 24 pt corners.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(horizontal: 17, vertical: 13);

  /// The card's look, shared with the starters and the failed-reply box so they match.
  static BoxDecoration decoration() => BoxDecoration(
        color: OmiColors.surface1,
        borderRadius: OmiRadius.xlAll,
        border: Border.all(color: OmiColors.glassEdge),
        boxShadow: OmiGlass.shadows,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The card stops short of the trailing edge, as the user's pill stops short of the leading one.
      padding: const EdgeInsetsDirectional.only(end: OmiSpacing.xl),
      child: Container(
        key: const Key('chat_answer_card'),
        width: double.infinity,
        decoration: decoration(),
        padding: padding,
        child: child,
      ),
    );
  }
}
