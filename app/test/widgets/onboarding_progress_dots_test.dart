import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/onboarding/wrapper.dart';

void main() {
  testWidgets('progress dots count only real steps and speak "Step N of M"', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OnboardingProgressDots(current: 1, total: 6)),
    ));

    expect(find.bySemanticsLabel('Step 2 of 6'), findsOneWidget);
    // One dot per step: no placeholder pages inflate the count.
    expect(
      find.descendant(of: find.byType(OnboardingProgressDots), matching: find.byType(AnimatedContainer)),
      findsNWidgets(6),
    );
    handle.dispose();
  });

  test('six bars (v3): consent, the name, how you record, setting it up, the first conversation, the voice', () {
    expect(OnboardingProgressStepsForTest.barCount, 6);
    int? bar(int page) => OnboardingProgressStepsForTest.barIndex(page);
    expect(bar(OnboardingWrapper.consentPage), 0);
    expect(bar(OnboardingWrapper.namePage), 1);
    expect(bar(OnboardingWrapper.pickDevicePage), 2);
    // The pendant's four steps and the phone's microphone fill the same bar.
    for (final page in [
      OnboardingWrapper.powerPage,
      OnboardingWrapper.bluetoothPage,
      OnboardingWrapper.scanPage,
      OnboardingWrapper.buttonsPage,
      OnboardingWrapper.permissionsPage,
    ]) {
      expect(bar(page), 3);
    }
    expect(bar(OnboardingWrapper.firstPage), 4);
    expect(bar(OnboardingWrapper.resultPage), 4);
    expect(bar(OnboardingWrapper.voicePage), 5);
    expect(bar(OnboardingWrapper.readPage), isNull);
    expect(bar(OnboardingWrapper.completePage), isNull);
  });

  test('back shows on every step but the first conversation, and alone over the lines to read', () {
    bool back(int page) => OnboardingProgressStepsForTest.showsBack(page);
    expect(back(OnboardingWrapper.consentPage), isTrue);
    expect(back(OnboardingWrapper.scanPage), isTrue);
    expect(back(OnboardingWrapper.firstPage), isTrue);
    expect(back(OnboardingWrapper.resultPage), isFalse);
    expect(back(OnboardingWrapper.readPage), isTrue);
    expect(back(OnboardingWrapper.completePage), isFalse);
    expect(OnboardingProgressStepsForTest.steps,
        [OnboardingWrapper.namePage, OnboardingWrapper.pickDevicePage, OnboardingWrapper.voicePage]);
  });
}
