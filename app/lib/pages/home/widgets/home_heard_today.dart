import 'package:flutter/material.dart';

import 'package:omi/pages/conversations/widgets/swipe_to_delete.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/open_conversation.dart';
import 'package:omi/pages/home/widgets/welcome_note.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Home's conversations: five rows on a roomy screen, three on smaller screens
/// or at larger text sizes. Each row is a 42 pt tile holding the device's icon, the title on
/// one line, and the time under it.
///
/// The titles share one font size: it starts at 16.5 and steps down by 0.25 until every title
/// fits its line, never below 14.5, then the longest ones end in an ellipsis.
class HomeHeardToday extends StatelessWidget {
  const HomeHeardToday({
    super.key,
    required this.conversations,
    required this.onAll,
    this.today = true,
    this.coach = false,
    this.showWelcome = false,
  });

  /// Newest first ([pick]), bounded by [limitFor].
  final List<ServerConversation> conversations;

  /// Opens All conversations.
  final VoidCallback onAll;

  /// Whether [conversations] are today's (kept for callers; v8 always says Conversations).
  final bool today;

  /// Shows the first day's line under the label ("Omi is listening. Your first notes appear here…").
  final bool coach;
  final bool showWelcome;

  /// `.coach`: at most 32ch of its 14 pt.
  static double _coachWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: OmiType.detail),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width * 32;
    painter.dispose();
    return width;
  }

  static const int limit = 3;
  static int limitFor(MediaQueryData media) {
    final availableHeight = media.size.height - media.padding.vertical - media.viewInsets.bottom;
    return media.size.width >= 360 && availableHeight / media.textScaler.scale(1) >= 740 ? 5 : 3;
  }

  static const double tile = 42;
  static const double gap = 12;
  static const double maxTitle = 16.5;
  static const double minTitle = 14.5;
  static const double titleStep = 0.25;

  /// The label block: 22 pt above the label, 10 below it (v3 `h2` and `#convs`).
  static const double labelTop = 22;
  static const double labelBottom = 10;

  /// The latest conversations across days, up to [limit]. Fill spare rows with
  /// earlier notes when there are fewer than [limit] today.
  static List<ServerConversation> pick(ConversationProvider provider, {int limit = HomeHeardToday.limit}) {
    return _newestFirst(provider).take(limit).toList();
  }

  /// Whether [conversation] started on the local calendar day of [now].
  static bool isToday(ServerConversation conversation, {DateTime? now}) {
    final at = (conversation.startedAt ?? conversation.createdAt).toLocal();
    final n = now ?? DateTime.now();
    return at.year == n.year && at.month == n.month && at.day == n.day;
  }

  static List<ServerConversation> _newestFirst(ConversationProvider provider) {
    final dates = provider.groupedConversations.keys.toList()..sort((a, b) => b.compareTo(a));
    final byId = <String, ServerConversation>{
      for (final c in provider.processingConversations)
        if (!c.discarded) c.id: c,
      for (final date in dates)
        for (final c in provider.groupedConversations[date] ?? const <ServerConversation>[])
          if (!c.discarded) c.id: c,
    };
    return byId.values.toList()..sort((a, b) => (b.startedAt ?? b.createdAt).compareTo(a.startedAt ?? a.createdAt));
  }

  /// The one title size at which every title in [titles] fits [width] on one line, from [maxTitle]
  /// down to [minTitle] in steps of [titleStep].
  static double fitTitles(List<String> titles, double width, TextScaler scaler, TextDirection direction) {
    var size = maxTitle;
    while (size > minTitle) {
      final fits = titles.every((title) {
        final painter = TextPainter(
          text: TextSpan(text: title, style: titleStyle(size)),
          maxLines: 1,
          textScaler: scaler,
          textDirection: direction,
        )..layout(maxWidth: width);
        final ok = !painter.didExceedMaxLines;
        painter.dispose();
        return ok;
      });
      if (fits) return size;
      size -= titleStep;
    }
    return minTitle;
  }

  /// `#convs .tx b`: 500, line height 1.15, −.015em.
  static TextStyle titleStyle(double size) => OmiType.subhead.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.15,
        letterSpacing: -0.015 * size,
      );

  /// `#convs .tx .when`: 13 pt, +.01em, tabular, in the secondary ink.
  static TextStyle get timeStyle => OmiType.footnote.copyWith(
        color: OmiColors.textSecondary,
        height: 1.15,
        letterSpacing: 0.13,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v8: "Conversations · See all".
        OmiSectionLabel(
          title: l10n.conversations,
          action: l10n.seeAllV3,
          actionKey: const Key('home_heard_all'),
          onAction: onAll,
          top: labelTop,
          bottom: labelBottom,
        ),
        if (showWelcome) const WelcomeNoteTile(),
        // `.coach` (v8.1): the first day, while Omi listens and nothing is written up yet.
        if (coach)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _coachWidth(context)),
                child: Text(
                  l10n.coachFirstNotes,
                  key: const Key('home_coach'),
                  style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary),
                ),
              ),
            ),
          ),
        // The rows span Home's margins, so the title width comes from the screen. (A LayoutBuilder
        // here would break Home's fill-the-screen sliver, which measures its content's intrinsic
        // height.)
        Builder(builder: (context) {
          final width =
              MediaQuery.sizeOf(context).width - 2 * OmiSize.screenMargin - HomeHeardToday.tile - HomeHeardToday.gap;
          final size = fitTitles(
            [for (final c in conversations) _title(context, c)],
            width,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in conversations.indexed) _HeardRow(conversation: c, index: i, titleSize: size),
            ],
          );
        }),
      ],
    );
  }

  static String _title(BuildContext context, ServerConversation c) {
    final title = c.structured.title.trim();
    if (c.status != ConversationStatus.completed && title.isEmpty) return context.l10n.transcribing;
    return title.isEmpty ? context.l10n.untitledConversation : title;
  }
}

/// One conversation: the device tile, the title over its time.
class _HeardRow extends StatelessWidget {
  const _HeardRow({required this.conversation, required this.index, required this.titleSize});

  final ServerConversation conversation;
  final int index;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final ready = c.status == ConversationStatus.completed;
    final at = (c.startedAt ?? c.createdAt).toLocal();
    final title = HomeHeardToday._title(context, c);
    final scaler = MediaQuery.textScalerOf(context);
    // The grid shares the tile's height between the two lines: the title sits in the upper half,
    // the time in the lower, 1 pt apart at the least.
    final lines = scaler.scale(titleSize) * 1.15 + scaler.scale(13) * 1.15;
    final between = 1 + ((HomeHeardToday.tile - lines - 1) / 2).clamp(0.0, 20.0);
    // v8.13: swipe left to delete, with Undo.
    final row = Semantics(
      button: true,
      enabled: ready,
      label: title,
      hint: ready ? context.l10n.openConversation : context.l10n.omiWritingItUp,
      excludeSemantics: true,
      child: OmiPressable(
        key: ValueKey('home_heard_${c.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: ready ? () => openConversationDetail(context, c, index: index) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              OmiDeviceTile(icon: OmiGlyphs.forSource(c.source?.name)),
              const SizedBox(width: HomeHeardToday.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: HomeHeardToday.titleStyle(titleSize)),
                    SizedBox(height: between),
                    Text(ready ? OmiDateFormat.of(context).time(at) : context.l10n.omiWritingItUp,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: HomeHeardToday.timeStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!ready) return row;
    return SwipeToDelete(key: ValueKey('home_swipe_${c.id}'), conversation: c, child: row);
  }
}

/// The 42 pt icon tile (v3): warm-white fill (ink 8 % in Black), a hairline, 13 pt corners and a
/// cement-grey glyph. Device icons in the Heard today rows and the recorder card, the to-do mark on
/// the To-do card (12 pt corners there).
class OmiDeviceTile extends StatelessWidget {
  const OmiDeviceTile(
      {super.key, required this.icon, this.size = HomeHeardToday.tile, this.glyph = 25, this.radius = 13});

  /// An [OmiGlyphs] path.
  final String icon;
  final double size;
  final double glyph;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OmiColors.tile,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        border: Border.all(color: OmiColors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: OmiGlyph(icon, size: glyph, color: OmiColors.cement),
    );
  }
}
