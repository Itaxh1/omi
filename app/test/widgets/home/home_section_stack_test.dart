import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/pages/home/widgets/home_section_stack.dart';

/// Home without a tab bar: Today is the screen, and a section slides in over it.
class _Harness extends StatefulWidget {
  const _Harness({required this.backs});

  final List<int> backs;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;

  /// Shows [section] (0 is Today), as See All or Back would.
  void go(int section) => setState(() => index = section);

  @override
  Widget build(BuildContext context) {
    Widget page(String name) => Center(
          child: TextButton(key: Key('tap_$name'), onPressed: () {}, child: Text(name)),
        );
    return MaterialApp(
      home: Scaffold(
        body: HomeSectionStack(
          selectedIndex: index,
          pages: [page('Today'), page('Conversations'), page('To do'), page('Apps')],
          onBack: () {
            widget.backs.add(index);
            setState(() => index = 0);
          },
        ),
      ),
    );
  }
}

Future<_HarnessState> _pump(WidgetTester tester, List<int> backs) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_Harness(backs: backs));
  return tester.state<_HarnessState>(find.byType(_Harness));
}

/// Where the section page is drawn: the slide moves the page inside it, not itself.
Rect _layer(WidgetTester tester) => tester.getRect(
      find.descendant(of: find.byKey(const Key('home_section_layer')), matching: find.byType(DecoratedBox)).first,
    );

void main() {
  testWidgets('Today alone: the sections wait off screen and taps reach Today', (tester) async {
    await _pump(tester, []);

    expect(_layer(tester).left, greaterThanOrEqualTo(390));
    expect(find.byKey(const Key('tap_Today')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('tap_Conversations')).hitTestable(), findsNothing);
  });

  testWidgets('See All slides the section in over Today, which stops taking taps', (tester) async {
    final harness = await _pump(tester, []);

    harness.go(1);
    await tester.pumpAndSettle();

    expect(_layer(tester).left, 0);
    expect(find.byKey(const Key('tap_Conversations')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('tap_Today')).hitTestable(), findsNothing);
  });

  testWidgets('a swipe in from the leading edge goes back to Today', (tester) async {
    final backs = <int>[];
    final harness = await _pump(tester, backs);
    harness.go(2);
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(5, 400), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(backs, [2]);
    expect(find.byKey(const Key('tap_Today')).hitTestable(), findsOneWidget);
  });

  testWidgets('going back keeps the section on screen while it slides out', (tester) async {
    final harness = await _pump(tester, []);
    harness.go(3);
    await tester.pumpAndSettle();

    harness.go(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Apps'), findsOneWidget, reason: 'the section shown is the one leaving, not the first');
    expect(_layer(tester).left, greaterThan(0));
    expect(_layer(tester).left, lessThan(390));
    await tester.pumpAndSettle();
  });

  testWidgets('each section keeps its state across visits', (tester) async {
    final harness = await _pump(tester, []);
    harness.go(1);
    await tester.pumpAndSettle();
    final first = tester.state(find.byKey(const Key('tap_Conversations')));

    harness.go(0);
    await tester.pumpAndSettle();
    harness.go(1);
    await tester.pumpAndSettle();

    expect(identical(tester.state(find.byKey(const Key('tap_Conversations'))), first), isTrue);
  });
}
