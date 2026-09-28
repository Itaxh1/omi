import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Ask's opening motion (v3), on one 1.1 s timeline an [AnimationController] of that length drives:
/// the hello's lines rise one after another (0, 0.12 s, 0.5 s), the count ticks up from 0.25 s over
/// 0.65 s, the suggestions fade in from 0.35 s and the composer rises from 0.15 s.
abstract final class AskIntro {
  static const Duration length = Duration(milliseconds: 1100);

  /// The design's `rise` curve, cubic-bezier(.2,.8,.2,1).
  static const Curve rise = Cubic(0.2, 0.8, 0.2, 1);

  /// [begin] and [duration] in seconds on the timeline, as an [Interval] with [curve].
  static Interval at(double begin, double duration, {Curve curve = rise}) {
    const total = 1.1;
    return Interval(begin / total, math.min(1, (begin + duration) / total), curve: curve);
  }

  static final Interval line1 = at(0, 0.5);
  static final Interval line2 = at(0.12, 0.5);
  static final Interval ask = at(0.5, 0.5);
  static final Interval count = at(0.25, 0.65, curve: Curves.easeOutCubic);
  static final Interval suggestions = at(0.35, 0.5, curve: Curves.easeOut);
  static final Interval composer = at(0.15, 0.45);
}

/// Rises into place (`rise`: from 10 pt lower and transparent) along [interval] of [animation].
class AskRise extends StatelessWidget {
  const AskRise(
      {super.key, required this.animation, required this.interval, required this.child, this.fadeOnly = false});

  final Animation<double> animation;
  final Interval interval;
  final Widget child;

  /// Only fades (the suggestions' `fadeIn`).
  final bool fadeOnly;

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: animation, curve: interval);
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: fadeOnly ? child : Transform.translate(offset: Offset(0, 10 * (1 - t.value)), child: child),
      ),
    );
  }
}

/// Ask before the first question (v3 `.hello2`): "Morning, Alex." over how many conversations Omi
/// heard today, then "What do you want to know?" in the secondary ink. Each line rises in turn and
/// the number counts up from 0.
class AskHello extends StatelessWidget {
  const AskHello({super.key, required this.isConnected, required this.animation});

  final bool isConnected;
  final Animation<double> animation;

  /// The design's greeting word by the hour: Morning before noon, Afternoon before six, then
  /// Evening.
  static String greetingFor(BuildContext context, int hour) {
    final l10n = context.l10n;
    return hour < 12
        ? l10n.greetingMorning
        : hour < 18
            ? l10n.greetingAfternoon
            : l10n.greetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!isConnected) {
      return Center(child: Text(l10n.noInternetConnection, textAlign: TextAlign.center));
    }
    final now = DateTime.now();
    final today = context.select<ConversationProvider?, int>(
      (p) =>
          p?.conversations.where((c) {
            final at = (c.startedAt ?? c.createdAt).toLocal();
            return !c.discarded && at.year == now.year && at.month == now.month && at.day == now.day;
          }).length ??
          0,
    );
    final name = SharedPreferencesUtil().givenName.trim();
    final greeting = greetingFor(context, now.hour);
    final big = OmiType.title1.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.7, height: 1.2);
    final count = CurvedAnimation(parent: animation, curve: AskIntro.count);
    // Full width, so the hello starts on the gutter rather than centring in the page's column.
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 28, OmiSize.screenMargin, OmiSpacing.md),
        child: Column(
          key: const Key('ask_hello'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AskRise(
              animation: animation,
              interval: AskIntro.line1,
              child: Semantics(
                header: true,
                child: Text(name.isEmpty ? '$greeting.' : '${l10n.greetingWithName(greeting, name)}.', style: big),
              ),
            ),
            AskRise(
              animation: animation,
              interval: AskIntro.line2,
              child: AnimatedBuilder(
                animation: count,
                builder: (context, _) => Text(
                  l10n.conversationsTodayCount((today * count.value).round()),
                  style: big.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AskRise(
              animation: animation,
              interval: AskIntro.ask,
              child: Text(
                l10n.whatDoYouWantToKnow,
                style: OmiType.title3.copyWith(
                    fontWeight: FontWeight.w500, letterSpacing: -0.2, height: 1.2, color: OmiColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The questions to start with (v3 `.chips`): a row of pills above the composer that fade in after
/// the hello. Tapping one asks it straight away.
class AskSuggestions extends StatelessWidget {
  const AskSuggestions({super.key, required this.onSelected, required this.animation});

  final ValueChanged<String> onSelected;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prompts = [l10n.askSuggestDecide, l10n.askSuggestOwe, l10n.askSuggestNotice];
    // A scrolling row that grows with the text size (the pills stay whole at 200 %).
    return AskRise(
      animation: animation,
      interval: AskIntro.suggestions,
      fadeOnly: true,
      child: SingleChildScrollView(
        key: const Key('ask_suggestions'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: Row(
          children: [
            for (final (i, prompt) in prompts.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              OmiPillChip(key: ValueKey('ask_suggestion_$i'), label: prompt, onTap: () => onSelected(prompt)),
            ],
          ],
        ),
      ),
    );
  }
}
