import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';

import '../../support/local_day.dart';

ServerConversation _conversation(String id, String title, DateTime at, {ConversationSource? source}) =>
    ServerConversation(
      id: id,
      createdAt: at,
      startedAt: at,
      structured: Structured(title, 'Overview', emoji: '🧠'),
      source: source,
    );

ConversationProvider _provider(List<ServerConversation> conversations) {
  final provider = ConversationProvider(isSignedIn: () => false);
  provider.conversations = conversations;
  final grouped = <DateTime, List<ServerConversation>>{};
  for (final c in conversations) {
    final at = c.startedAt!;
    grouped.putIfAbsent(DateTime(at.year, at.month, at.day), () => []).add(c);
  }
  provider.groupedConversations = grouped;
  return provider;
}

Future<void> _pump(WidgetTester tester, ConversationProvider provider, List<ServerConversation> rows,
    {bool today = true, double width = 390, double textScale = 1}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(textScale)),
        child: ChangeNotifierProvider.value(
          value: provider,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
              child: HomeHeardToday(conversations: rows, today: today, onAll: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Home's "Heard today" (v3): today's three, one line each, with a shared title size.
void main() {
  // Afternoon local, far from midnight, so "today" is stable in every timezone.
  final now = localCalendarDay(2026, 8, 12, 15);
  final yesterday = now.subtract(const Duration(days: 1));

  test('pick takes today\'s conversations, newest first, up to three', () {
    final provider = _provider([
      for (var i = 0; i < 7; i++) _conversation('t$i', 'Today $i', now.subtract(Duration(minutes: 10 * i))),
      _conversation('y', 'Yesterday', yesterday),
    ]);
    final picked = HomeHeardToday.pick(provider, now: now);
    expect(picked.map((c) => c.id), ['t0', 't1', 't2']);
    expect(HomeHeardToday.isToday(picked.first, now: now), isTrue);
  });

  test('pick falls back to the latest three when nothing was heard today', () {
    final provider = _provider([
      _conversation('y1', 'Yesterday 1', yesterday),
      _conversation('y2', 'Yesterday 2', yesterday.subtract(const Duration(hours: 1))),
      _conversation('old', 'Older', yesterday.subtract(const Duration(days: 3))),
    ]);
    final picked = HomeHeardToday.pick(provider, now: now);
    expect(picked.map((c) => c.id), ['y1', 'y2', 'old']);
    expect(HomeHeardToday.isToday(picked.first, now: now), isFalse);
  });

  testWidgets('the label, the all link and one row per conversation with its device tile', (tester) async {
    final rows = [
      _conversation('c1', 'Ship the widgets without waiting for chat', now, source: ConversationSource.omi),
      _conversation('c2', 'Quick check of the iPhone mic', now.subtract(const Duration(hours: 1)),
          source: ConversationSource.phone),
      _conversation('c3', 'Dan\'s idea for a baseline model', now.subtract(const Duration(hours: 2)),
          source: ConversationSource.apple_watch),
    ];
    await _pump(tester, _provider(rows), rows);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeHeardToday)));

    expect(find.text(l10n.heardToday), findsOneWidget);
    expect(find.byKey(const Key('home_heard_all')), findsOneWidget);
    for (final c in rows) {
      expect(find.byKey(ValueKey('home_heard_${c.id}')), findsOneWidget);
      expect(find.text(c.structured.title), findsOneWidget);
    }
    expect(find.byType(OmiDeviceTile), findsNWidgets(3));
    final glyphs = tester.widgetList<OmiGlyph>(find.byType(OmiGlyph)).map((g) => g.asset).toList();
    expect(glyphs, containsAll([OmiGlyphs.deviceOmi, OmiGlyphs.devicePhone, OmiGlyphs.deviceWatch]));
    // No dividers between rows.
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('when the rows are not today\'s the label says Latest', (tester) async {
    final rows = [_conversation('y', 'Yesterday', yesterday)];
    await _pump(tester, _provider(rows), rows, today: false);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeHeardToday)));
    expect(find.text(l10n.latest), findsOneWidget);
    expect(find.text(l10n.heardToday), findsNothing);
  });

  testWidgets('titles share one size: 16.5 when they all fit, smaller (never under 14.5) when one is long',
      (tester) async {
    final short = [
      _conversation('a', 'Standup', now),
      _conversation('b', 'Pricing review', now.subtract(const Duration(hours: 1))),
    ];
    await _pump(tester, _provider(short), short);
    double sizeOf(String title) => tester.widget<Text>(find.text(title)).style!.fontSize!;
    expect(sizeOf('Standup'), HomeHeardToday.maxTitle);
    expect(sizeOf('Pricing review'), HomeHeardToday.maxTitle);

    final long = [
      _conversation('a', 'Standup', now),
      _conversation('b', 'A very long title about the landlord, the boiler and Thursday', now),
    ];
    await _pump(tester, _provider(long), long);
    final fitted = sizeOf('Standup');
    expect(fitted, lessThan(HomeHeardToday.maxTitle));
    expect(fitted, greaterThanOrEqualTo(HomeHeardToday.minTitle));
    expect(sizeOf('A very long title about the landlord, the boiler and Thursday'), fitted,
        reason: 'every row uses the shared size');
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      if (text.data == long[1].structured.title) expect(text.maxLines, 1);
    }
  });

  testWidgets('a title that never fits keeps 14.5 and ends in an ellipsis', (tester) async {
    final title = ('Word ' * 40).trim();
    final rows = [_conversation('a', title, now)];
    await _pump(tester, _provider(rows), rows, width: 320, textScale: 1.3);
    final text = tester.widget<Text>(find.text(title));
    expect(text.style!.fontSize, HomeHeardToday.minTitle);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
