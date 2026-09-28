import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// A Home section heading (v2 Main): the title in 20pt semibold and, trailing, a 15pt semibold
/// link ("See All", "All Tasks") that switches to the section's tab.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(OmiSpacing.xxs, 0, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: OmiType.title3))),
          if (actionLabel != null && onAction != null)
            Semantics(
              button: true,
              label: actionLabel,
              excludeSemantics: true,
              onTap: onAction,
              child: OmiPressable(
                onTap: () {
                  OmiHaptics.selection();
                  onAction!();
                },
                // The label is 20pt tall; the touch target is 44pt.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: OmiSize.minTap, minWidth: OmiSize.minTap),
                  child: Padding(
                    padding: const EdgeInsets.only(left: OmiSpacing.xs, right: OmiSpacing.xxs),
                    child: Center(
                      widthFactor: 1,
                      child: Text(actionLabel!, style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600)),
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

/// "This week" (v2 Main): minutes captured per day, Monday to Sunday. Past days with audio are
/// strong-fill bars scaled to the busiest day, today is white, days still to come are a stub.
///
/// Built from the conversations already loaded; shown only when they reach back to the start of
/// the week, so the totals are never partial.
class HomeThisWeek extends StatelessWidget {
  const HomeThisWeek({super.key});

  /// The last week counted from the whole list. The loaded list follows the Conversations tab's
  /// filters (Starred, a folder, a device, a date, a search) — counting it then showed a filtered
  /// sliver as the week (39 s instead of 3 h 18 m) until the filter was cleared.
  static ({DateTime weekStart, List<int> seconds})? _lastWeek;

  @visibleForTesting
  static void resetForTest() => _lastWeek = null;

  /// Seconds captured each day of the week starting [weekStart], or null when the loaded list cannot
  /// say: it is filtered, or does not reach back to Monday yet.
  static List<int>? countWeek(ConversationProvider provider, DateTime weekStart) {
    final filtered = provider.showStarredOnly ||
        provider.selectedFolderId != null ||
        provider.sourceFilter != ConversationSourceFilter.all ||
        provider.selectedStartDate != null ||
        provider.hasActiveSearch;
    if (filtered) return null;
    final conversations = provider.conversations.where((c) => !c.discarded).toList();
    if (conversations.isEmpty) return null;
    final oldest =
        conversations.map((c) => (c.startedAt ?? c.createdAt).toLocal()).reduce((a, b) => a.isBefore(b) ? a : b);
    final complete = oldest.isBefore(weekStart) || !provider.hasMoreConversations;
    if (!complete) return null;
    final seconds = List<int>.filled(7, 0);
    for (final c in conversations) {
      final start = (c.startedAt ?? c.createdAt).toLocal();
      if (start.isBefore(weekStart)) continue;
      final day = DateTime(start.year, start.month, start.day).difference(weekStart).inDays;
      if (day < 0 || day > 6) continue;
      seconds[day] += c.getDurationInSeconds();
    }
    return seconds;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final weekStart = today.subtract(Duration(days: today.weekday - DateTime.monday));
        final counted = countWeek(provider, weekStart);
        if (counted != null) _lastWeek = (weekStart: weekStart, seconds: counted);
        final last = _lastWeek;
        // While the list is filtered, the week last counted from the whole list (this week's only).
        final seconds = counted ?? (last != null && last.weekStart == weekStart ? last.seconds : null);
        if (seconds == null) return const SizedBox.shrink();
        final total = seconds.fold<int>(0, (a, b) => a + b);
        if (total == 0) return const SizedBox.shrink();
        final todayIndex = today.difference(weekStart).inDays;
        final locale = Localizations.localeOf(context).toString();

        return Padding(
          padding: const EdgeInsets.only(top: 22),
          child: OmiCard(
            key: const Key('home_this_week'),
            padding: const EdgeInsets.fromLTRB(18, OmiSpacing.md, 18, OmiSpacing.md),
            child: _WeekChart(seconds: seconds, weekStart: weekStart, todayIndex: todayIndex, locale: locale),
          ),
        );
      },
    );
  }
}

/// The week's bars and what they add up to; tapping a day shows that day's time (IMG_1168), and
/// tapping it again goes back to the week.
class _WeekChart extends StatefulWidget {
  const _WeekChart({required this.seconds, required this.weekStart, required this.todayIndex, required this.locale});

  final List<int> seconds;
  final DateTime weekStart;
  final int todayIndex;
  final String locale;

  @override
  State<_WeekChart> createState() => _WeekChartState();
}

class _WeekChartState extends State<_WeekChart> {
  int? _selected;

  @override
  void didUpdateWidget(_WeekChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weekStart != widget.weekStart) _selected = null;
  }

  void _toggle(int day) {
    OmiHaptics.selection();
    setState(() => _selected = _selected == day ? null : day);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final seconds = widget.seconds;
    final total = seconds.fold<int>(0, (a, b) => a + b);
    final peak = seconds.reduce(math.max);
    final selected = _selected;
    final dayName =
        selected == null ? null : DateFormat.EEEE(widget.locale).format(widget.weekStart.add(Duration(days: selected)));
    final captured = selected == null
        ? l10n.capturedDuration(OmiDuration.compact(total, l10n))
        : '$dayName · ${l10n.capturedDuration(OmiDuration.compact(seconds[selected], l10n))}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label:
              '${l10n.thisWeek}, ${selected == null ? l10n.capturedDuration(OmiDuration.long(total, l10n)) : '$dayName, ${l10n.capturedDuration(OmiDuration.long(seconds[selected], l10n))}'}',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(l10n.thisWeek, style: OmiType.headline)),
              Flexible(
                child: Text(
                  captured,
                  key: const Key('home_this_week_captured'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: OmiType.footnote.copyWith(
                    color: OmiColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          // The tallest bar (52) and the day letter under it, at the reader's text size.
          height: 52 + 6 + _DayBar.letterHeight(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: i <= widget.todayIndex,
                    selected: i == selected,
                    label:
                        '${DateFormat.EEEE(widget.locale).format(widget.weekStart.add(Duration(days: i)))}, ${l10n.capturedDuration(OmiDuration.long(seconds[i], l10n))}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: Key('home_this_week_day_$i'),
                      behavior: HitTestBehavior.opaque,
                      // Days still to come have nothing to show.
                      onTap: i <= widget.todayIndex ? () => _toggle(i) : null,
                      child: _DayBar(
                        letter: DateFormat.EEEEE(widget.locale).format(widget.weekStart.add(Duration(days: i))),
                        fraction: peak == 0 ? 0 : seconds[i] / peak,
                        // The chosen day takes today's highlight while it is chosen.
                        isToday: selected == null ? i == widget.todayIndex : i == selected,
                        isFuture: i > widget.todayIndex,
                        index: i,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.letter,
    required this.fraction,
    required this.isToday,
    required this.isFuture,
    required this.index,
  });

  final String letter;
  final double fraction;
  final bool isToday;
  final bool isFuture;
  final int index;

  static TextStyle get _letterStyle => OmiType.caption1.copyWith(fontWeight: FontWeight.w600);

  /// The day letter's height at the reader's text size (a fixed 74 pt row cut it at 1.3x).
  static double letterHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _letterStyle),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final height = isFuture ? 4.0 : math.max(4.0, 52 * fraction);
    final color = isToday
        ? OmiColors.textPrimary
        : isFuture || fraction == 0
            ? OmiColors.surface2
            : OmiColors.surface4;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Bars rise in one after another (v2 `rise`, 50 ms apart).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0, end: 1),
          duration: Duration(milliseconds: 550 + index * 50),
          curve: Interval(index * 50 / (550 + index * 50), 1, curve: OmiMotion.springCurve),
          builder: (context, t, _) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - t)),
              child: Container(
                height: height,
                constraints: const BoxConstraints(maxWidth: 26),
                decoration: BoxDecoration(color: color, borderRadius: OmiRadius.smAll),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          letter,
          style: _letterStyle.copyWith(color: isToday ? OmiColors.textPrimary : OmiColors.textTertiary),
        ),
      ],
    );
  }
}
