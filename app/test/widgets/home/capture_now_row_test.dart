import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/conversations/widgets/live_capture_card.dart';
import 'package:omi/pages/home/widgets/capture_now_row.dart';
import 'package:omi/ui/ui.dart';

/// Home's Now row (v5): the live card's inputs as one row with icon buttons.
Future<AppLocalizations> _pump(WidgetTester tester, LiveCaptureCard card) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: CaptureNowRow(card: card)),
      ),
    ),
  );
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byType(CaptureNowRow)));
}

void main() {
  testWidgets('a listening pendant: the state, its time, Mute and Stop, and the latest words on one line',
      (tester) async {
    final taps = <String>[];
    final l10n = await _pump(
      tester,
      LiveCaptureCard(
        source: 'omi',
        status: 'Listening',
        elapsed: const Duration(minutes: 12, seconds: 4),
        lastLine: 'And let us keep the pendant flow exactly as it is.',
        onPauseToggle: () => taps.add('mute'),
        onFinish: () => taps.add('stop'),
      ),
    );

    expect(find.text('Listening'), findsOneWidget);
    expect(find.textContaining('12:04'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Hero && w.tag == kLiveOrbHeroTag), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('capture_now_line'))).maxLines, 1);
    expect(find.textContaining('keep the pendant flow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_now_mute')));
    await tester.tap(find.byKey(const Key('capture_now_stop')));
    expect(taps, ['mute', 'stop']);
    expect(find.bySemanticsLabel(l10n.mute), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.stop), findsOneWidget);
    // A third of the card: the whole row, words included, stays under 100 pt.
    expect(tester.getSize(find.byType(CaptureNowRow)).height, lessThan(100));
  });

  testWidgets('muted: the button reads Unmute and the pendant shows its lights-off photo', (tester) async {
    final l10n = await _pump(
      tester,
      LiveCaptureCard(source: 'omi', status: 'Muted', paused: true, onPauseToggle: () {}, onFinish: () {}),
    );

    expect(find.bySemanticsLabel(l10n.unmute), findsOneWidget);
    expect(tester.widget<OmiOrb>(find.byType(OmiOrb)).live, isFalse);
    expect(find.byKey(const Key('capture_now_meter')), findsNothing, reason: 'no wave while muted');
  });

  testWidgets('a call: no capture buttons, a chevron instead (the call page owns them)', (tester) async {
    await _pump(
      tester,
      const LiveCaptureCard(source: LiveCaptureCard.callSource, status: 'Listening', live: true),
    );

    expect(find.byKey(const Key('capture_now_mute')), findsNothing);
    expect(find.byKey(const Key('capture_now_stop')), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Hero && w.tag == kLiveOrbHeroTag), findsNothing);
  });

  testWidgets('a problem state carries the warning glyph and no transcript room when told so', (tester) async {
    await _pump(
      tester,
      const LiveCaptureCard(
        source: 'omi',
        status: 'Disconnected',
        explanation: 'The pendant lost its connection.',
        live: false,
        showsTranscript: false,
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byKey(const Key('capture_now_line')), findsNothing);
  });
}
