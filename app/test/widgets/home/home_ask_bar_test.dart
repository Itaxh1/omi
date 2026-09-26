import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_ask_bar.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/bottom_nav_bar.dart';

Future<({List<String> calls, ValueNotifier<bool> compact})> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final calls = <String>[];
  final compact = ValueNotifier(false);
  addTearDown(compact.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion, viewPadding: padding, padding: padding),
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
                onVoice: () => calls.add('voice'),
                onHold: () => calls.add('hold'),
                compact: compact,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return (calls: calls, compact: compact);
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(HomeAskBar)));

void main() {
  testWidgets('tapping the bar opens chat, the mic opens it listening, holding opens Memories', (tester) async {
    final bar = await _pump(tester);

    await tester.tap(find.text(_l10n(tester).askAnything));
    await tester.tap(find.byKey(const Key('home_ask_mic')));
    await tester.longPress(find.byKey(const Key('home_ask_bar')));

    expect(bar.calls, ['open', 'voice', 'hold']);
  });

  testWidgets('an example question shows under "Ask anything" and changes every few seconds', (tester) async {
    await _pump(tester);
    final l10n = _l10n(tester);

    expect(find.text(l10n.askTryHint(l10n.askStarterOpen)), findsOneWidget);
    await tester.pump(HomeAskBar.exampleEvery);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.askTryHint(l10n.askStarterToday)), findsOneWidget);
  });

  testWidgets('under Reduce Motion the example stays put', (tester) async {
    await _pump(tester, reduceMotion: true);
    final l10n = _l10n(tester);

    await tester.pump(HomeAskBar.exampleEvery * 2);
    expect(find.text(l10n.askTryHint(l10n.askStarterOpen)), findsOneWidget);
  });

  testWidgets('scrolling down to read narrows it and drops the example and the mic', (tester) async {
    final bar = await _pump(tester);
    final l10n = _l10n(tester);
    final wide = tester.getSize(find.byKey(const Key('home_ask_bar')));

    bar.compact.value = true;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_ask_mic')), findsNothing);
    expect(find.text(l10n.askTryHint(l10n.askStarterOpen)), findsNothing);
    expect(find.text(l10n.askAnything), findsOneWidget);
    final narrow = tester.getSize(find.byKey(const Key('home_ask_bar')));
    expect(narrow.width, lessThan(wide.width));
    expect(narrow.height, lessThan(wide.height));
  });

  testWidgets('it sits just above the home indicator, and pages keep room under it', (tester) async {
    await _pump(tester, padding: const EdgeInsets.only(bottom: 34));
    final context = tester.element(find.byType(HomeAskBar));
    final screen = tester.getSize(find.byType(Scaffold));
    final bar = tester.getRect(find.byKey(const Key('home_ask_bar')));

    expect(screen.height - bar.bottom, askBarBottomOffset(context));
    expect(askBarBottomOffset(context), 34 + OmiSpacing.xxs);
    expect(bottomNavBarClearance(context), greaterThan(screen.height - bar.top));
  });

  testWidgets('without a home indicator it keeps the page margin', (tester) async {
    await _pump(tester);
    expect(askBarBottomOffset(tester.element(find.byType(HomeAskBar))), OmiSize.screenMargin);
  });
}
