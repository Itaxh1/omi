/// Home's pulls and first-run teaching (v8.6, v8.14, v8.1), and swipe to delete (v8.13).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/conversations/widgets/swipe_to_delete.dart';
import 'package:omi/pages/home/widgets/home_pull.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test('the page follows a pull down fully to 90 pt, then a quarter as far', () {
    expect(HomePullGestures.easedDown(50), 30);
    expect(HomePullGestures.easedDown(90), 54);
    expect(HomePullGestures.easedDown(130), 64);
    expect(HomePullGestures.easedDown(-10), 0);
  });

  group('pulls', () {
    late ValueNotifier<HomePullPhase> down;
    late ValueNotifier<double> up;
    late List<String> fired;

    Future<void> pump(WidgetTester tester) async {
      down = ValueNotifier(HomePullPhase.none);
      up = ValueNotifier(0);
      fired = [];
      addTearDown(down.dispose);
      addTearDown(up.dispose);
      await tester.pumpWidget(_app(HomePullGestures(
        down: down,
        up: up,
        onPullDown: () => fired.add('down'),
        onPullUp: () => fired.add('up'),
        child: const CustomScrollView(slivers: [SliverFillRemaining(child: SizedBox.expand())]),
      )));
    }

    testWidgets('down past 90 pt is ready, and letting go acts', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(down.value, HomePullPhase.pulling);
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(down.value, HomePullPhase.ready);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, ['down']);
      expect(down.value, HomePullPhase.none);
    });

    testWidgets('down short of 90 pt springs back and does nothing', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
    });

    testWidgets('up 150 pt fills the dots, and letting go opens Your Omi', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -55));
      await tester.pump();
      expect(up.value, closeTo(0.5, 0.01));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(up.value, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, ['up']);
      expect(up.value, 0);
    });

    testWidgets('a sideways drag is not a pull', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(40, 5));
      await gesture.moveBy(const Offset(0, 120));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
    });
  });

  test('the tip shows until taught; the third open nudges once if the mark was never tapped', () {
    expect(HomeTeach.onHomeOpened(), (tip: true, nudge: false));
    HomeTeach.markTaught();
    expect(HomeTeach.onHomeOpened(), (tip: false, nudge: false));
    expect(HomeTeach.onHomeOpened(), (tip: false, nudge: true));
    expect(HomeTeach.onHomeOpened(), (tip: false, nudge: false), reason: 'nudged once');
  });

  test('a reader who tapped the mark is not nudged', () {
    HomeTeach.markTaught();
    HomeTeach.markTapped();
    HomeTeach.onHomeOpened();
    HomeTeach.onHomeOpened();
    expect(HomeTeach.onHomeOpened(), (tip: false, nudge: false));
  });

  testWidgets('the tip reads This is Omi and Got it closes it', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(Center(child: HomeTeachTip(onDone: () => done++))));
    await tester.pumpAndSettle();
    expect(find.text('This is Omi.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home_teach_got_it')));
    expect(done, 1);
  });

  testWidgets('swiping a conversation left part way leaves Delete showing', (tester) async {
    final conversation =
        ServerConversation(id: 'c1', createdAt: DateTime(2026, 9, 28), structured: Structured('A', ''));
    var opened = 0;
    await tester.pumpWidget(_app(Column(children: [
      SwipeToDelete(
        conversation: conversation,
        child: GestureDetector(
          onTap: () => opened++,
          child: const SizedBox(height: 60, width: double.infinity, child: Text('Row')),
        ),
      ),
    ])));
    await tester.drag(find.text('Row'), const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    final offset = tester.getTopLeft(find.text('Row')).dx;
    expect(offset, lessThan(-80), reason: 'it stays open 96 pt');
    // A tap closes it rather than opening the conversation.
    await tester.tapAt(const Offset(200, 30));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.getTopLeft(find.text('Row')).dx, 0);
  });
}
