import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/schema.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_todo_card.dart';
import 'package:omi/providers/action_items_provider.dart';

import '../../support/local_day.dart';

ActionItemWithMetadata _task(String id, String text, {DateTime? due}) =>
    ActionItemWithMetadata(id: id, description: text, completed: false, dueAt: due);

Future<({List<String> opened, AppLocalizations l10n})> _pump(WidgetTester tester, List<ActionItemWithMetadata> tasks) async {
  final opened = <String>[];
  final provider = ActionItemsProvider(
    getActionItems: ({
      int limit = 100,
      int offset = 0,
      bool? completed,
      String? conversationId,
      DateTime? startDate,
      DateTime? endDate,
      DateTime? dueStartDate,
      DateTime? dueEndDate,
    }) async =>
        ActionItemsResponse(actionItems: tasks),
  );
  addTearDown(provider.dispose);
  await tester.runAsync(provider.ensureLoaded);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<ActionItemsProvider>.value(
        value: provider,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(22),
            child: HomeTodoCard(onOpen: () => opened.add('todo')),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (opened: opened, l10n: AppLocalizations.of(tester.element(find.byType(HomeTodoCard))));
}

/// Home's To-do card (v3): the most overdue task, a red count badge for what is late or due today.
void main() {
  final now = localCalendarDay(2026, 8, 12, 15);
  final today = DateTime(now.year, now.month, now.day);

  group('what the card says', () {
    test('late tasks come most overdue first, with whole days late', () {
      final open = [
        _task('a', 'Call Sam back', due: today.subtract(const Duration(days: 2, hours: 3))),
        _task('b', 'Send the draft', due: today.subtract(const Duration(days: 1))),
        _task('c', 'Book the room', due: today.add(const Duration(hours: 17))),
        _task('d', 'Undated'),
      ];
      final late = HomeTodoCard.lateTasks(open, now: now);
      expect(late.map((t) => t.id), ['a', 'b']);
      expect(HomeTodoCard.daysLate(late.first, now: now), 3);
      expect(HomeTodoCard.daysLate(late.last, now: now), 1);
      expect(HomeTodoCard.dueToday(open, now: now).map((t) => t.id), ['c']);
    });
  });

  testWidgets('the most overdue task, and the badge counts late plus due today', (tester) async {
    final r = await _pump(tester, [
      _task('a', 'Call Sam back', due: today.subtract(const Duration(days: 2))),
      _task('b', 'Send the draft', due: today.subtract(const Duration(days: 1))),
      _task('c', 'Book the room', due: today.add(const Duration(hours: 17))),
      _task('d', 'Undated'),
    ]);
    // Days late are counted from the real today, so the text is checked by shape.
    final subtitle = tester.widget<Text>(find.byKey(const Key('home_todo_subtitle'))).data!;
    expect(subtitle, startsWith('Call Sam back'));
    expect(subtitle, endsWith('late'));
    expect(find.byKey(const Key('home_todo_badge')), findsOneWidget);
    expect(find.text(r.l10n.toDo), findsOneWidget);
  });

  testWidgets('nothing late: the next task due today; nothing due: the open count; no badge', (tester) async {
    final realToday = DateTime.now();
    final r = await _pump(tester, [
      _task('c', 'Book the room', due: DateTime(realToday.year, realToday.month, realToday.day, 23, 30)),
      _task('d', 'Undated'),
    ]);
    expect(find.text(r.l10n.todoDueToday('Book the room')), findsOneWidget);
    expect(find.byKey(const Key('home_todo_badge')), findsOneWidget);

    final r2 = await _pump(tester, [_task('d', 'Undated'), _task('e', 'Also undated')]);
    expect(find.text(r2.l10n.todoOpenCount(2)), findsOneWidget);
    expect(find.byKey(const Key('home_todo_badge')), findsNothing);

    final r3 = await _pump(tester, []);
    expect(find.text(r3.l10n.todoOpenCount(0)), findsOneWidget);
  });

  testWidgets('tapping the card opens the To-do list', (tester) async {
    final r = await _pump(tester, [_task('d', 'Undated')]);
    await tester.tap(find.byKey(const Key('home_todo_card')));
    expect(r.opened, ['todo']);
  });
}
