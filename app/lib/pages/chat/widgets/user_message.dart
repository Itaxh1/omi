import 'package:flutter/material.dart';

import 'package:omi/backend/schema/message.dart';
import 'package:omi/pages/chat/widgets/files_handler_widget.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'package:omi/widgets/text_selection_controls.dart';

class HumanMessage extends StatelessWidget {
  final ServerMessage message;
  final Function(String)? onAskOmi;

  const HumanMessage({super.key, required this.message, this.onAskOmi});

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
      padding: const EdgeInsetsDirectional.only(start: 24),
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
              // v3 Ask (`.me`): the reader's words in an ink-outlined bubble on the trailing side, its
              // tail corner tucked in, at most 85 % of the width.
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
                decoration: BoxDecoration(
                  border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(18),
                    topEnd: Radius.circular(18),
                    bottomStart: Radius.circular(18),
                    bottomEnd: Radius.circular(4),
                  ).resolve(Directionality.of(context)),
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
