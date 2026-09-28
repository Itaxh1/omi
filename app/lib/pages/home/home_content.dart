import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/widgets/capture_recovery_banner.dart';
import 'package:omi/pages/home/widgets/home_first_day.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/pages/home/widgets/home_todo_card.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home (v3, the Omi v8 kit): under the top bar, a two-hour phrase as the headline, "Heard today"
/// with up to five conversation rows, then the To-do card in the warm lower zone. What is
/// listening lives in the top bar's label and the recorder card it opens, not on the page. The
/// first day welcomes instead and adds Getting started and Good to know, so Home is never empty.
class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key});

  @override
  State<HomeContentPage> createState() => HomeContentPageState();
}

class HomeContentPageState extends State<HomeContentPage> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<ConversationProvider>(
      builder: (context, convoProvider, child) {
        final count = _nonDiscardedConversationCount(convoProvider);
        // While the first page is still loading an established account looks empty; wait before
        // showing first-day content so it never flashes.
        final settled = count > 0 || !(convoProvider.isLoadingConversations || convoProvider.isFetchingConversations);
        final firstDay = settled && count == 0;
        final heard = HomeHeardToday.pick(convoProvider);
        final heardToday = heard.isNotEmpty && HomeHeardToday.isToday(heard.first);
        return DecoratedBox(
          decoration: BoxDecoration(gradient: HomeTone.gradient()),
          child: RefreshIndicator(
            onRefresh: () async {
              OmiHaptics.medium();
              await convoProvider.getInitialConversations();
            },
            color: OmiColors.onAccent,
            backgroundColor: OmiColors.accent,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: firstDay ? const HomeFirstDayHeader() : _buildHeadline(context)),
                if (firstDay) const SliverToBoxAdapter(child: FirstDayListeningHero()),
                const SliverToBoxAdapter(child: CaptureRecoveryBanner()),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
                  sliver: SliverList.list(
                    children: [
                      // Until the first few conversations: the setup checklist (folds away when done).
                      if (settled && count < 3) HomeGettingStarted(conversationCount: count),
                      if (heard.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: HomeHeardToday(
                            conversations: heard,
                            today: heardToday,
                            onAll: () => context.read<HomeProvider>().setIndex(1),
                          ),
                        ),
                      if (settled)
                        Padding(
                          padding: const EdgeInsets.only(top: 36),
                          child: HomeTodoCard(onOpen: () => context.read<HomeProvider>().setIndex(2)),
                        ),
                    ],
                  ),
                ),
                if (settled && firstDay) const SliverToBoxAdapter(child: HomeGoodToKnow()),
                // Room under the last section for the pinned Ask bar.
                SliverToBoxAdapter(child: SizedBox(height: homeChatBarClearance(context))),
              ],
            ),
          ),
        );
      },
    );
  }

  int _nonDiscardedConversationCount(ConversationProvider provider) {
    return provider.conversations.where((c) => !c.discarded).length;
  }

  /// The headline (v3): a two-to-three-word phrase for the hour, changing every two hours, 34/600.
  /// Never a date.
  Widget _buildHeadline(BuildContext context) {
    final greeting = HomeGreeting.forHour(context.l10n, DateTime.now().hour);
    return Padding(
      // 44 pt under the top bar, as the design sets it.
      padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 36, OmiSize.screenMargin, 0),
      child: Semantics(
        header: true,
        child: Text(
          greeting,
          key: const Key('home_headline'),
          style: OmiType.largeTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Home's background (v3 `.home-bg`), fixed to the screen, not the scroll: the page colour for the
/// top 62 %, half warm by 72 %, fully warm white by 82 %.
abstract final class HomeTone {
  static LinearGradient gradient() {
    final paper = OmiColors.surface0;
    final tone = OmiColors.tone;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [paper, paper, Color.lerp(paper, tone, 0.5)!, tone],
      stops: const [0, 0.62, 0.72, 0.82],
    );
  }
}

/// Home's headline: something different every two hours, from Up late to Good night, two or three
/// words.
abstract final class HomeGreeting {
  static String forHour(AppLocalizations l10n, int hour) => switch ((hour % 24) ~/ 2) {
        0 => l10n.greetingUpLate,
        1 => l10n.greetingStillUp,
        2 => l10n.greetingEarlyStart,
        3 => l10n.greetingNewDay,
        4 => l10n.greetingMorning,
        5 => l10n.greetingBusyMorning,
        6 => l10n.greetingLunchtime,
        7 => l10n.greetingAfternoon,
        8 => l10n.greetingHomeStretch,
        9 => l10n.greetingEvening,
        10 => l10n.greetingWindingDown,
        _ => l10n.greetingGoodNight,
      };

  /// Whether [text] fits one line of [maxWidth] in [style] at the reader's text size.
  static bool fitsOneLine(String text, TextStyle style, double maxWidth, TextScaler scaler, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textScaler: scaler,
      textDirection: direction,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }
}

/// Non-discarded conversations, for tests and callers that count what Home shows.
extension HomeConversations on ConversationProvider {
  List<ServerConversation> get shownConversations => conversations.where((c) => !c.discarded).toList();
}
