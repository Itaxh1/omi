import 'package:flutter/material.dart';

import 'package:omi/pages/conversation_detail/conversation_detail_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// After a speaker is named, the summary regenerates by itself a few seconds later. If that didn't
/// go through, this pill ("Update summary with new names") lets the reader try again; it turns
/// while the summary is being written. Hidden otherwise.
class SpeakerSummaryAction extends StatelessWidget {
  const SpeakerSummaryAction({super.key, required this.provider});

  final ConversationDetailProvider provider;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: provider,
        builder: (context, _) {
          if (!provider.offerSpeakerSummaryRefresh) return const SizedBox.shrink();
          final busy = provider.loadingReprocessConversation;
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Flexible(
                  child: OmiPillChip(
                    key: const ValueKey('speaker-summary-refresh'),
                    label: context.l10n.updateSummaryWithNewNames,
                    glyph: OmiGlyphs.lines,
                    onTap: busy
                        ? null
                        : () {
                            OmiHaptics.selection();
                            provider.reprocessConversation();
                          },
                  ),
                ),
                if (busy) ...[
                  const SizedBox(width: 10),
                  const OmiSpinner(size: OmiSpinnerSize.small),
                ],
              ],
            ),
          );
        },
      );
}
