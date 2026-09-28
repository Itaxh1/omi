import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/extensions/string.dart';
import 'conversation_detail_provider.dart';
import 'page.dart' show ConversationTitleStyle;
import 'speaker_naming.dart';

/// A conversation's transcript (v3 `trans`): the title, a chip "Transcript · 14 min · 2
/// speakers", then each turn: who spoke and when (an unnamed speaker is underlined; tap to name
/// them), and what they said. "⋯" holds Copy transcript, Name speakers and Back to summary.
class ConversationTranscriptPage extends StatelessWidget {
  const ConversationTranscriptPage({super.key, required this.provider});

  /// The conversation page's provider, so a name given here shows there too.
  final ConversationDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ConversationDetailProvider>.value(
      value: provider,
      child: const _TranscriptView(),
    );
  }
}

/// Consecutive segments of one speaker, shown as one turn.
class _Turn {
  _Turn(this.first);
  final TranscriptSegment first;
  final List<String> texts = [];
}

class _TranscriptView extends StatelessWidget {
  const _TranscriptView();

  List<_Turn> _turns(List<TranscriptSegment> segments) {
    final turns = <_Turn>[];
    for (final s in segments) {
      final text = s.text.trim();
      if (text.isEmpty) continue;
      final last = turns.isEmpty ? null : turns.last;
      if (last != null &&
          last.first.speakerId == s.speakerId &&
          last.first.isUser == s.isUser &&
          last.first.personId == s.personId) {
        last.texts.add(text);
      } else {
        turns.add(_Turn(s)..texts.add(text));
      }
    }
    return turns;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.watch<ConversationDetailProvider>();
    final conversation = provider.conversation;
    final segments = conversation.transcriptSegments;
    final people = context.watch<PeopleProvider?>()?.people ?? SharedPreferencesUtil().cachedPeople;
    final names = SpeakerNames.forSegments(
      segments,
      people: people,
      unresolved: conversation.speakerResolution?.status == 'unavailable',
      l10n: l10n,
    );
    final turns = _turns(segments);
    final speakers = {for (final s in segments) s.isUser ? -1 : s.speakerId}.length;
    final start = conversation.startedAt ?? conversation.createdAt;
    final end = conversation.finishedAt;
    final minutes = end == null ? null : (end.difference(start).inSeconds / 60).ceil();
    final facts = [
      l10n.transcript,
      if (minutes != null && minutes > 0) l10n.minutesShortV3(minutes),
      if (speakers > 0) l10n.speakerCount(speakers),
    ].join(' · ');
    final dates = OmiDateFormat.of(context);
    final unnamed = turns.where((t) => !t.first.isUser && t.first.personId == null).toList();
    final external = (conversation.externalIntegration?.text ?? '').decodeString.trim();

    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(
        trailing: OmiRingButton.glass(
          key: const Key('transcript_more'),
          glyph: OmiGlyphs.more,
          label: l10n.moreOptions,
          onPressed: () async {
            final choice = await showOmiPopoverMenu<String>(context, entries: [
              OmiMenuEntry(value: 'copy', label: l10n.copyTranscriptV3, glyph: OmiGlyphs.copyLine),
              if (unnamed.isNotEmpty)
                OmiMenuEntry(value: 'name', label: l10n.nameSpeakers, glyph: OmiGlyphs.personLine),
              OmiMenuEntry(value: 'summary', label: l10n.backToSummary, glyph: OmiGlyphs.lines),
            ]);
            if (!context.mounted || choice == null) return;
            switch (choice) {
              case 'copy':
                OmiClipboard.copy(context, conversation.getTranscript(generate: true), what: l10n.transcript);
              case 'name':
                final t = unnamed.first.first;
                nameTranscriptSpeaker(context, provider, segmentId: t.id, speakerId: t.speakerId);
              case 'summary':
                Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      bottomNavigationBar: const ListeningStrip(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 14, OmiSize.screenMargin, 20),
        children: [
          Semantics(
            header: true,
            child: Text(
              conversation.structured.title.trim().isEmpty
                  ? l10n.untitledConversation
                  : conversation.structured.title.trim(),
              style: ConversationTitleStyle.style,
            ),
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: OmiPillChip(label: facts, glyph: OmiGlyphs.lines)),
          const SizedBox(height: 26),
          if (turns.isEmpty)
            Text(
              external.isEmpty ? l10n.noTranscriptYet : external,
              style: OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.ink80),
            ),
          for (final (i, turn) in turns.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 20),
              child: _TurnView(
                name: names.forSegment(turn.first),
                time: dates.time(start.toLocal().add(Duration(milliseconds: (turn.first.start * 1000).round()))),
                text: turn.texts.join(' '),
                mine: turn.first.isUser,
                onName: turn.first.isUser
                    ? null
                    : () => nameTranscriptSpeaker(context, provider,
                        segmentId: turn.first.id, speakerId: turn.first.speakerId),
                unnamed: !turn.first.isUser && turn.first.personId == null,
              ),
            ),
        ],
      ),
    );
  }
}

/// One turn (`.tt`): who (13/600) and the time (11), then the words (17 pt on a 1.5 line). The
/// reader's own turns are in ink, the others in the 80 % ink.
class _TurnView extends StatelessWidget {
  const _TurnView({
    required this.name,
    required this.time,
    required this.text,
    required this.mine,
    required this.unnamed,
    this.onName,
  });

  final String name;
  final String time;
  final String text;
  final bool mine;
  final bool unnamed;
  final VoidCallback? onName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final who = OmiType.footnote.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: mine ? OmiColors.textPrimary : OmiColors.textSecondary,
    );
    Widget nameText = Text(
      name,
      style: unnamed
          ? who.copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: OmiColors.faint)
          : who,
    );
    if (onName != null) {
      nameText = Semantics(
        button: true,
        label: name,
        hint: l10n.nameSpeakers,
        excludeSemantics: true,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onName, child: nameText),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            nameText,
            const SizedBox(width: 8),
            Text(time,
                style: OmiType.caption.copyWith(
                  color: OmiColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        ),
        const SizedBox(height: 3),
        SelectableText(
          text,
          style: OmiType.body.copyWith(
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: mine ? OmiColors.textPrimary : OmiColors.ink80,
          ),
        ),
      ],
    );
  }
}
