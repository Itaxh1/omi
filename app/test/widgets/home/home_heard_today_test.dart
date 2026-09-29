import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/pages/home/widgets/welcome_note.dart';
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
    {bool today = true, double width = 390, double textScale = 1, bool welcome = false}) async {
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
              child: HomeHeardToday(conversations: rows, today: today, showWelcome: welcome, onAll: () {}),
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

  test('roomy phones show five conversations; small screens and large text show three', () {
    final provider = _provider([
      for (var i = 0; i < 7; i++) _conversation('t$i', 'Today $i', now.subtract(Duration(minutes: i))),
    ]);
    addTearDown(provider.dispose);
    for (final (media, expected) in [
      (const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(top: 47, bottom: 34)), 5),
      (const MediaQueryData(size: Size(375, 667), padding: EdgeInsets.only(top: 20)), 3),
      (const MediaQueryData(size: Size(320, 844)), 3),
      (const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(1.5)), 3),
    ]) {
      final rows = HomeHeardToday.pick(provider, limit: HomeHeardToday.limitFor(media));
      expect(rows.length, expected);
      expect(rows.first.id, 't0');
      expect(rows.last.id, 't${expected - 1}');
    }
  });

  testWidgets('processing note is visible, cannot open or swipe away, then becomes ready', (tester) async {
    final pending = _conversation('pending', '', now)..status = ConversationStatus.processing;
    final provider = _provider([])..processingConversations = [pending];
    final rows = HomeHeardToday.pick(provider);
    expect(rows.map((c) => c.id), ['pending']);
    await _pump(tester, provider, rows);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeHeardToday)));
    expect(find.text(l10n.transcribing), findsOneWidget);
    expect(find.text('Omi is writing it up…'), findsOneWidget);
    final row = tester.widget<OmiPressable>(find.byKey(const Key('home_heard_pending')));
    expect(row.onTap, isNull);
    expect(find.byKey(const Key('home_swipe_pending')), findsNothing);
    final ready = _conversation('pending', 'My first note', now);
    provider.groupedConversations = {
      now: [ready]
    };
    final completed = HomeHeardToday.pick(provider);
    expect(completed.length, 1, reason: 'stale processing rows must not duplicate completed notes');
    await _pump(tester, provider, completed);
    expect(find.text('My first note'), findsOneWidget);
    expect(tester.widget<OmiPressable>(find.byKey(const Key('home_heard_pending'))).onTap, isNotNull);
  });

  testWidgets('first-day welcome opens without any recorded notes and offers Discord', (tester) async {
    await _pump(tester, _provider([]), [], welcome: true);
    await tester.tap(find.byKey(const Key('home_welcome_note')));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeNotePage), findsOneWidget);
    expect(find.textContaining('The Omi developers'), findsOneWidget);
    expect(find.byKey(const Key('welcome_note_discord')), findsOneWidget);
  });

  test('pick takes today\'s conversations, newest first, up to three', () {
    final provider = _provider([
      for (var i = 0; i < 7; i++) _conversation('t$i', 'Today $i', now.subtract(Duration(minutes: 10 * i))),
      _conversation('y', 'Yesterday', yesterday),
    ]);
    final picked = HomeHeardToday.pick(provider);
    expect(picked.map((c) => c.id), ['t0', 't1', 't2']);
    expect(HomeHeardToday.isToday(picked.first, now: now), isTrue);
  });

  test('pick falls back to the latest three when nothing was heard today', () {
    final provider = _provider([
      _conversation('y1', 'Yesterday 1', yesterday),
      _conversation('y2', 'Yesterday 2', yesterday.subtract(const Duration(hours: 1))),
      _conversation('old', 'Older', yesterday.subtract(const Duration(days: 3))),
    ]);
    final picked = HomeHeardToday.pick(provider);
    expect(picked.map((c) => c.id), ['y1', 'y2', 'old']);
    expect(HomeHeardToday.isToday(picked.first, now: now), isFalse);
  });

  test('five available rows are filled with earlier notes when only one is from today', () {
    final provider = _provider([
      _conversation('today', 'Today', now),
      for (var i = 0; i < 5; i++) _conversation('old$i', 'Earlier $i', yesterday.subtract(Duration(minutes: i))),
    ]);
    addTearDown(provider.dispose);
    expect(HomeHeardToday.pick(provider, limit: 5).map((c) => c.id), ['today', 'old0', 'old1', 'old2', 'old3']);
  });

  testWidgets('Conversations, See all and one row per conversation with its device tile', (tester) async {
    final rows = [
      _conversation('c1', 'Ship the widgets without waiting for chat', now, source: ConversationSource.omi),
      _conversation('c2', 'Quick check of the iPhone mic', now.subtract(const Duration(hours: 1)),
          source: ConversationSource.phone),
      _conversation('c3', 'Dan\'s idea for a baseline model', now.subtract(const Duration(hours: 2)),
          source: ConversationSource.apple_watch),
    ];
    await _pump(tester, _provider(rows), rows);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeHeardToday)));

    expect(find.text(l10n.conversations), findsOneWidget);
    expect(find.text(l10n.seeAllV3), findsOneWidget);
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

  testWidgets('v8 says Conversations whether or not the rows are today\'s', (tester) async {
    final rows = [_conversation('y', 'Yesterday', yesterday)];
    await _pump(tester, _provider(rows), rows, today: false);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeHeardToday)));
    expect(find.text(l10n.conversations), findsOneWidget);
    expect(find.text(l10n.latest), findsNothing);
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
