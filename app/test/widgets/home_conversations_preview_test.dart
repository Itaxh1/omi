import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/conversations/widgets/conversation_list_item.dart';
import 'package:omi/pages/home/home_content.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

import '../support/local_day.dart';

void main() {
  for (final scenario in [
    (name: 'compact phone', size: const Size(390, 667), scale: 1.0, inset: 34.0, above: 64.0, count: 4),
    (name: 'tall phone', size: const Size(430, 932), scale: 1.0, inset: 34.0, above: 64.0, count: 5),
    (name: 'landscape phone', size: const Size(932, 430), scale: 1.0, inset: 0.0, above: 64.0, count: 4),
    (name: 'large text', size: const Size(430, 932), scale: 2.0, inset: 34.0, above: 64.0, count: 4),
    (name: 'tasks and recaps above', size: const Size(430, 932), scale: 1.0, inset: 34.0, above: 314.0, count: 4),
    (name: 'small bottom inset', size: const Size(390, 900), scale: 1.0, inset: 0.0, above: 64.0, count: 5),
    (name: 'large bottom inset', size: const Size(390, 900), scale: 1.0, inset: 80.0, above: 64.0, count: 4),
  ]) {
    testWidgets('home preview shows ${scenario.count} newest filtered conversations on ${scenario.name}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      tester.view.padding = FakeViewPadding(top: 59, bottom: scenario.inset);
      tester.view.viewPadding = FakeViewPadding(top: 59, bottom: scenario.inset);
      addTearDown(tester.view.reset);
      final provider = ConversationProvider(isSignedIn: () => false);
      addTearDown(provider.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // Stay away from midnight so grouping is stable in every timezone.
      final today = localCalendarDay(2026, 8, 12, 15);
      final yesterday = today.subtract(const Duration(days: 1));
      final conversations = [
        _conversation('newest', 'Newest', today),
        _conversation('middle', 'Middle', today.subtract(const Duration(hours: 1))),
        _conversation('yesterday', 'Yesterday', yesterday),
        _conversation('fourth', 'Fourth', yesterday.subtract(const Duration(days: 1))),
        _conversation('fifth', 'Fifth', yesterday.subtract(const Duration(days: 2))),
        _conversation('oldest', 'Oldest', yesterday.subtract(const Duration(days: 3))),
      ];
      provider.conversations = conversations;
      provider.groupedConversations = {
        DateTime(yesterday.year, yesterday.month, yesterday.day): conversations.sublist(2),
        DateTime(today.year, today.month, today.day): conversations.sublist(0, 2),
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: ChangeNotifierProvider.value(
            value: provider,
            child: Scaffold(
              appBar: AppBar(),
              body: Builder(
                builder: (context) => CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: scenario.above)),
                    HomeConversationsPreview(conversationProvider: provider),
                    SliverToBoxAdapter(child: SizedBox(height: homeChatBarClearance(context))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final seen = <String>{};
      void observePreview() {
        seen.addAll(
            tester.widgetList<ConversationListItem>(find.byType(ConversationListItem)).map((w) => w.conversation.id));
        expect(tester.widget<SliverList>(find.byType(SliverList)).delegate.estimatedChildCount, scenario.count);
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Newest'), findsOneWidget);
      observePreview();
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      observePreview();
      expect(find.text(scenario.count == 5 ? 'Fifth' : 'Fourth'), findsOneWidget);
      expect(find.text('Oldest'), findsNothing);
      expect(seen, conversations.take(scenario.count).map((c) => c.id).toSet());
    });
  }
}

ServerConversation _conversation(String id, String title, DateTime createdAt) {
  return ServerConversation(
    id: id,
    createdAt: createdAt,
    structured: Structured(title, 'Overview', emoji: '🧠'),
  );
}
