import 'package:flutter/material.dart';

import 'package:omi/backend/schema/message.dart';
import 'package:omi/pages/chat/widgets/files_handler_widget.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'package:omi/widgets/text_selection_controls.dart';

/// The user's message (Omi v8 `.me`): their words in an ink outline at the right, the corner
/// nearest the composer squared off, so a question reads apart from Omi's unboxed answer.
class HumanMessage extends StatelessWidget {
  final ServerMessage message;
  final Function(String)? onAskOmi;

  const HumanMessage({super.key, required this.message, this.onAskOmi});

  /// The squared-off corner, nearest the composer.
  static const Radius _tailCorner = Radius.circular(4);

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

    return Padding(
      padding: const EdgeInsets.only(left: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FilesHandlerWidget(message: message),
          if (contextText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0, right: 4.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.symmetric(horizontal: OmiSpacing.sm, vertical: OmiSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.subdirectory_arrow_right, size: 14, color: OmiColors.textTertiary),
                    const SizedBox(width: OmiSpacing.xs),
                    Flexible(
                      child: Text(
                        contextText.length > 50 ? '${contextText.substring(0, 50)}…' : contextText,
                        style: OmiType.footnote.copyWith(color: OmiColors.textTertiary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              Container(
                key: const Key('chat_user_message'),
                decoration: BoxDecoration(
                  border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(OmiRadius.lg),
                    topRight: Radius.circular(OmiRadius.lg),
                    bottomLeft: Radius.circular(OmiRadius.lg),
                    bottomRight: _tailCorner,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: SelectableText(
                  messageText.trimRight(),
                  style: OmiType.callout.copyWith(height: 1.4),
                  contextMenuBuilder: (context, editableTextState) {
                    return omiSelectionMenuBuilder(context, editableTextState, (text) {
                      onAskOmi?.call(text);
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
