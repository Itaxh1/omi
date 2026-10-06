import 'package:flutter/material.dart';

import 'package:omi/backend/schema/message.dart';
import 'package:omi/pages/chat/widgets/files_handler_widget.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'package:omi/widgets/text_selection_controls.dart';

/// The user's message: their words in a solid round pill at the right, black in light and a lifted
/// grey in dark, so a question reads apart from Omi's white answer card. Quoted context sits inside
/// the pill above the words.
class HumanMessage extends StatelessWidget {
  final ServerMessage message;
  final Function(String)? onAskOmi;

  const HumanMessage({super.key, required this.message, this.onAskOmi});

  /// The pill's fill: the accent in light; in dark the accent is white, so a lifted grey instead.
  static Color get fill => OmiColors.active == OmiPalette.dark ? OmiColors.surface3 : OmiColors.accent;

  /// The words on [fill].
  static Color get ink => OmiColors.active == OmiPalette.dark ? OmiColors.textPrimary : OmiColors.onAccent;

  @override
  Widget build(BuildContext context) {
    String text = message.text.decodeString;
    String? contextText;
    String messageText = text;

    final contextRegex = RegExp(r'^Context: "([\s\S]+?)"\n\n');
    final match = contextRegex.firstMatch(text);

    if (match != null) {
      contextText = match.group(1);
      messageText = text.substring(match.end);
    }

    final ink = HumanMessage.ink;
    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FilesHandlerWidget(message: message),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              Container(
                key: const Key('chat_user_message'),
                decoration: BoxDecoration(color: fill, borderRadius: OmiRadius.xlAll),
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (contextText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsetsDirectional.only(start: OmiSpacing.xs),
                          decoration: BoxDecoration(
                            border: BorderDirectional(start: BorderSide(color: ink.withValues(alpha: 0.72), width: 2)),
                          ),
                          child: Text(
                            contextText.length > 50 ? '${contextText.substring(0, 50)}…' : contextText,
                            style: OmiType.footnote.copyWith(color: ink.withValues(alpha: 0.72)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    SelectableText(
                      messageText.trimRight(),
                      style: OmiType.body.copyWith(color: ink, height: 1.35),
                      contextMenuBuilder: (context, editableTextState) {
                        return omiSelectionMenuBuilder(context, editableTextState, (text) {
                          onAskOmi?.call(text);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
