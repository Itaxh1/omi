import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/home/widgets/welcome_note.dart';
import 'package:omi/pages/conversations/widgets/capture_recovery_banner.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/pages/home/widgets/home_todo_card.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

/// Home (v8, the Omi v8 kit): under the top bar, a two-hour phrase as the headline,
/// "Conversations" with up to three rows (and, on the first day while Omi listens, a line saying
/// where the notes will appear), then the To-do card in the warm lower zone. What is listening
/// lives in the top bar's label and Your Omi, which it opens; pulling the page down pauses or
/// starts, pulling up from the bottom opens Your Omi ([HomePullGestures]). There is no pull to
/// refresh: the page follows the conversations as they change.
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
        final heard = HomeHeardToday.pick(convoProvider, limit: HomeHeardToday.limitFor(MediaQuery.of(context)));
        final heardToday = heard.isNotEmpty && HomeHeardToday.isToday(heard.first);
        // The To-do card sits in the warm zone at the same height above the Ask bar on every phone;
        // when the page is taller than the screen (the first day) it follows the content instead.
        final underCard = askBarBottomOffset(context) + kAskBarHeight + HomeTone.cardAboveAsk;
        final listening = HomeListeningLabel.watch(context) == HomeRecorderState.listening;
        // `.coach`: the first day, while Omi listens and at most one conversation is written up.
        final coach = settled && listening && count <= 1;
        final welcome = settled &&
            (count == 0 ||
                (count < HomeHeardToday.limit && SharedPreferencesUtil().getBool(WelcomeNoteTile.preferenceKey)));
        return CustomScrollView(
          controller: _scrollController,
          // Clamped: pulling past the top or bottom moves the page by hand (HomePullGestures).
          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The first day is Home as every day (v3 `setData('first')`): the headline, what
                  // Omi heard (the first conversation) and the To-do card.
                  _buildHeadline(context),
                  const CaptureRecoveryBanner(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (heard.isNotEmpty || coach || welcome)
                          HomeHeardToday(
                            conversations: heard,
                            today: heardToday,
                            coach: coach,
                            showWelcome: welcome,
                            onAll: () => context.read<HomeProvider>().setIndex(1),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: HomeTone.cardBelowRows),
                  const Spacer(),
                  if (settled)
                    Padding(
                      // `.todo1`: 4 pt wider than the page on each side, as wide as the Ask bar (the
                      // card keeps its own inset for the badge).
                      padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin - 4 - HomeTodoCard.inset),
                      child: HomeTodoCard(onOpen: () => context.read<HomeProvider>().setIndex(2)),
                    ),
                  SizedBox(height: underCard),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  int _nonDiscardedConversationCount(ConversationProvider provider) {
    return provider.conversations.where((c) => !c.discarded).length;
  }

  /// The headline (v3 `h1.lede`): a two-to-three-word phrase for the hour, changing every two
  /// hours, 34/600 at −.03em on a 1.15 line, 44 pt under the top bar. Never a date.
  Widget _buildHeadline(BuildContext context) {
    final greeting = HomeGreeting.forHour(context.l10n, DateTime.now().hour);
    return Padding(
      padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 44, OmiSize.screenMargin, 0),
      child: Semantics(
        header: true,
        child: Text(
          greeting,
          key: const Key('home_headline'),
          style: OmiType.largeTitle.copyWith(height: 1.15),
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
  /// The least room between the last row and the To-do card (`#todos`: 40 pt margin, 36 padding).
  static const double cardBelowRows = 76;

  /// From the To-do card's bottom edge to the Ask bar's top (the design at 390 × 844: 109 pt).
  static const double cardAboveAsk = 109;

  static LinearGradient gradient() {
    if (!OmiColors.isLight) {
      return const LinearGradient(colors: [Colors.black, Colors.black]);
    }
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
