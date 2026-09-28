import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_ask_bar.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

Future<List<String>> _pump(WidgetTester tester, {EdgeInsets padding = EdgeInsets.zero}) async {
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(viewPadding: padding, padding: padding),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HomeAskBar(
                onOpen: () => calls.add('open'),
                onHold: () => calls.add('hold'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(HomeAskBar)));

/// The Ask bar (v8.2): one 56 pt liquid-glass capsule pinned above the home indicator, no mic.
void main() {
  testWidgets('tapping the bar opens Ask, holding opens Memories', (tester) async {
    final calls = await _pump(tester);

    await tester.tap(find.text(_l10n(tester).askAnything));
    await tester.longPress(find.byKey(const Key('home_ask_bar')));

    expect(calls, ['open', 'hold']);
  });

  testWidgets('it is 56 pt tall, glass, with only "Ask anything" and no mic', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);

    expect(kAskBarHeight, 56);
    expect(tester.getSize(find.byKey(const Key('home_ask_bar'))).height, kAskBarHeight);
    expect(find.text(l10n.askAnything), findsOneWidget);
    expect(find.byKey(const Key('home_ask_mic')), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('home_ask_bar')), matching: find.byType(OmiLiquidGlass)),
        findsOneWidget);
  });

  testWidgets('it sits 16 pt above the home indicator, and pages keep room under it', (tester) async {
    await _pump(tester, padding: const EdgeInsets.only(bottom: 34));
    final context = tester.element(find.byType(HomeAskBar));
    final screen = tester.getSize(find.byType(Scaffold));
    final bar = tester.getRect(find.byKey(const Key('home_ask_bar')));

    expect(screen.height - bar.bottom, askBarBottomOffset(context));
    expect(askBarBottomOffset(context), 34 + OmiSpacing.md,
        reason: '50 pt from the bottom on an iPhone (`.ask` at safe + 16)');
    expect(bottomNavBarClearance(context), greaterThan(screen.height - bar.top));
  });

  testWidgets('without a home indicator it keeps 16 pt from the edge', (tester) async {
    await _pump(tester);
    expect(askBarBottomOffset(tester.element(find.byType(HomeAskBar))), OmiSpacing.md);
  });
}
