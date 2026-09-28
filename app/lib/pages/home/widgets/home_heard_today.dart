import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversation_detail/page.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// Home's "Heard today" (v3): a 13 pt section label with an underlined "all" link, then up to five
/// conversation rows with no dividers. Each row is a 42 pt tile holding the device's icon only,
/// the title on one line, and the time under it.
///
/// The titles share one font size: it starts at 16.5 and steps down by 0.25 until every title
/// fits its line, never below 14.5, then the longest ones end in an ellipsis.
class HomeHeardToday extends StatelessWidget {
  const HomeHeardToday({super.key, required this.conversations, required this.onAll, this.today = true});

  /// Up to five, newest first ([pick]).
  final List<ServerConversation> conversations;

  /// Opens All conversations.
  final VoidCallback onAll;

  /// Whether [conversations] are today's; otherwise the label says Latest.
  final bool today;

  static const int limit = 5;
  static const double tile = 42;
  static const double gap = 12;
  static const double maxTitle = 16.5;
  static const double minTitle = 14.5;
  static const double titleStep = 0.25;

  /// Today's conversations, newest first, up to [limit]; when there are none today, the latest
  /// [limit] instead (the label then says Latest, see [isToday]).
  static List<ServerConversation> pick(ConversationProvider provider, {int limit = HomeHeardToday.limit, DateTime? now}) {
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
    return [for (final date in dates) ...provider.groupedConversations[date] ?? const <ServerConversation>[]];
  }

  /// The one title size at which every title in [titles] fits [width] on one line, from [maxTitle]
  /// down to [minTitle] in steps of [titleStep].
  static double fitTitles(List<String> titles, double width, TextScaler scaler, TextDirection direction) {
    var size = maxTitle;
    while (size > minTitle) {
      final fits = titles.every((title) {
        final painter = TextPainter(
          text: TextSpan(text: title, style: _titleStyle(size)),
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

  static TextStyle _titleStyle(double size) =>
      OmiType.subhead.copyWith(fontSize: size, fontWeight: FontWeight.w500, height: 1.15);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(title: today ? l10n.heardToday : l10n.latest, action: l10n.all.toLowerCase(), onAction: onAll),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth - HomeHeardToday.tile - HomeHeardToday.gap;
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
          },
        ),
      ],
    );
  }

  static String _title(BuildContext context, ServerConversation c) {
    final title = c.structured.title.trim();
    return title.isEmpty ? context.l10n.untitledConversation : title;
  }
}

/// A 13 pt/600 label in the secondary ink, with an underlined link on the right.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.action, required this.onAction});

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final style = OmiType.footnote.copyWith(color: OmiColors.textSecondary, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: style))),
          Semantics(
            button: true,
            label: action,
            excludeSemantics: true,
            onTap: onAction,
            child: OmiPressable(
              onTap: () {
                OmiHaptics.selection();
                onAction();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: OmiSize.minTap, minWidth: OmiSize.minTap),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    action,
                    key: const Key('home_heard_all'),
                    style: style.copyWith(decoration: TextDecoration.underline, decorationColor: OmiColors.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    return Semantics(
      button: true,
      label: title,
      hint: context.l10n.openConversation,
      excludeSemantics: true,
      child: OmiPressable(
        key: ValueKey('home_heard_${c.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
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
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: HomeHeardToday._titleStyle(titleSize)),
                    const SizedBox(height: 1),
                    Text(
                      OmiDateFormat.of(context).time(at),
                      maxLines: 1,
                      style: OmiType.footnote.copyWith(
                        color: OmiColors.textSecondary,
                        height: 1.15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    OmiHaptics.selection();
    final provider = context.read<ConversationProvider>();
    final hours = DateTime.now().difference(conversation.createdAt).inHours;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.onConversationTap(conversation.id);
      unawaited(SchedulerBinding.instance.scheduleTask<void>(() {
        PlatformManager.instance.analytics.conversationListItemClickedWithTimeDifference(
          conversation: conversation,
          conversationIndex: index,
          hoursSinceConversation: hours,
        );
      }, Priority.idle));
    });
    routeToPage(context, ConversationDetailPage(conversation: conversation));
  }
}

/// The 42 pt icon tile (v3): warm-white fill, a hairline, and a cement-grey glyph. Device icons in
/// the Heard today rows and the recorder card, the to-do mark on the To-do card.
class OmiDeviceTile extends StatelessWidget {
  const OmiDeviceTile({super.key, required this.icon, this.size = HomeHeardToday.tile, this.glyph = 26});

  /// An [OmiGlyphs] path.
  final String icon;
  final double size;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OmiColors.tone,
        borderRadius: OmiRadius.tileAll,
        border: Border.all(color: OmiColors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: OmiGlyph(icon, size: glyph, color: OmiColors.cement),
    );
  }
}
