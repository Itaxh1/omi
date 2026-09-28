import 'package:flutter/material.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/open_conversation.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Home's "Heard today" (v3): a 13 pt section label with an underlined "all" link, then up to three
/// conversation rows with no dividers (three, so the To-do card and the Ask bar sit in the same
/// place on every iPhone). Each row is a 42 pt tile holding the device's icon only, the title on
/// one line, and the time under it.
///
/// The titles share one font size: it starts at 16.5 and steps down by 0.25 until every title
/// fits its line, never below 14.5, then the longest ones end in an ellipsis.
class HomeHeardToday extends StatelessWidget {
  const HomeHeardToday({super.key, required this.conversations, required this.onAll, this.today = true});

  /// Up to three, newest first ([pick]).
  final List<ServerConversation> conversations;

  /// Opens All conversations.
  final VoidCallback onAll;

  /// Whether [conversations] are today's; otherwise the label says Latest.
  final bool today;

  static const int limit = 3;
  static const double tile = 42;
  static const double gap = 12;
  static const double maxTitle = 16.5;
  static const double minTitle = 14.5;
  static const double titleStep = 0.25;

  /// The label block: 22 pt above the label, 10 below it (v3 `h2` and `#convs`).
  static const double labelTop = 22;
  static const double labelBottom = 10;

  /// Today's conversations, newest first, up to [limit]; when there are none today, the latest
  /// [limit] instead (the label then says Latest, see [isToday]).
  static List<ServerConversation> pick(ConversationProvider provider,
      {int limit = HomeHeardToday.limit, DateTime? now}) {
    final all = _newestFirst(provider);
    final todays = all.where((c) => isToday(c, now: now)).take(limit).toList();
    return todays.isNotEmpty ? todays : all.take(limit).toList();
  }

  /// Whether [conversation] started on the local calendar day of [now].
  static bool isToday(ServerConversation conversation, {DateTime? now}) {
    final at = (conversation.startedAt ?? conversation.createdAt).toLocal();
    final n = now ?? DateTime.now();
    return at.year == n.year && at.month == n.month && at.day == n.day;
  }

  static List<ServerConversation> _newestFirst(ConversationProvider provider) {
    final dates = provider.groupedConversations.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates)
        ...(provider.groupedConversations[date] ?? const <ServerConversation>[]).where((c) => !c.discarded),
    ];
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
        OmiSectionLabel(
          title: today ? l10n.heardToday : l10n.latest,
          action: l10n.all.toLowerCase(),
          actionKey: const Key('home_heard_all'),
          onAction: onAll,
          top: labelTop,
          bottom: labelBottom,
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
    final at = (c.startedAt ?? c.createdAt).toLocal();
    final title = HomeHeardToday._title(context, c);
    final scaler = MediaQuery.textScalerOf(context);
    // The grid shares the tile's height between the two lines: the title sits in the upper half,
    // the time in the lower, 1 pt apart at the least.
    final lines = scaler.scale(titleSize) * 1.15 + scaler.scale(13) * 1.15;
    final between = 1 + ((HomeHeardToday.tile - lines - 1) / 2).clamp(0.0, 20.0);
    return Semantics(
      button: true,
      label: title,
      hint: context.l10n.openConversation,
      excludeSemantics: true,
      child: OmiPressable(
        key: ValueKey('home_heard_${c.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => openConversationDetail(context, c, index: index),
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
                    Text(OmiDateFormat.of(context).time(at), maxLines: 1, style: HomeHeardToday.timeStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
