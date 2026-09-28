import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/home/home_content.dart' show HomeGreeting;
import 'package:omi/providers/conversation_provider.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Ask before the first question (v3 `.hello2`): "Morning, Alex." over how many conversations
/// Omi heard today (the number counts up), then "What do you want to know?".
class AskHello extends StatelessWidget {
  const AskHello({super.key, required this.isConnected});

  final bool isConnected;

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
    final greeting = HomeGreeting.forHour(l10n, now.hour);
    final big = OmiType.title1.copyWith(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.7, height: 1.2);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 32, OmiSize.screenMargin, OmiSpacing.md),
      child: Column(
        key: const Key('ask_hello'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(name.isEmpty ? '$greeting.' : '${l10n.greetingWithName(greeting, name)}.', style: big),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: today.toDouble()),
            duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? Duration.zero
                : const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(l10n.conversationsTodayCount(value.round()), style: big),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.whatDoYouWantToKnow,
            style: OmiType.title3.copyWith(
                fontWeight: FontWeight.w500, letterSpacing: -0.2, height: 1.2, color: OmiColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The questions to start with (v3 `.chips`): a row of pills above the composer. Choosing one puts
/// it in the composer; it is never sent on its own.
class AskSuggestions extends StatelessWidget {
  const AskSuggestions({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prompts = [l10n.askSuggestDecide, l10n.askSuggestOwe, l10n.askSuggestNotice];
    // A scrolling row that grows with the text size (the pills stay whole at 200 %).
    return SingleChildScrollView(
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
    );
  }
}
