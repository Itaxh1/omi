import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_connection_monitor.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';

void main() {
  testWidgets('Bluetooth is checked on entry and resume without interrupting phone validation', (tester) async {
    var radio = 'off';
    final readiness = BluetoothReadiness(
      readState: () async => radio,
      permissionState: (_) async => null,
      observeBridge: false,
    );
    addTearDown(readiness.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
          body: OnboardingConnectionMonitor(
        readiness: readiness,
        child: const TextField(key: Key('phone_validation')),
      )),
    ));
    await tester.pump();
    expect(find.byKey(const Key('onboarding_bluetooth_off')), findsOneWidget);
    expect(readiness.guidance, isNull, reason: 'observation must not open a modal permission prompt');
    await tester.enterText(find.byKey(const Key('phone_validation')), '123456');
    await tester.tap(find.byKey(const Key('onboarding_bluetooth_turn_on')));
    await tester.pump();
    expect(readiness.guidance?.state, BluetoothAdapterState.off);
    readiness.dismissGuidance(readiness.guidance!.id);
    await tester.tap(find.byKey(const Key('onboarding_bluetooth_turn_on')));
    await tester.pump();
    expect(readiness.guidance, isNotNull, reason: 'a second deliberate tap can reopen guidance');
    radio = 'on';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('onboarding_bluetooth_off')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('phone_validation'))).controller, isNull);
    expect(find.text('123456'), findsOneWidget, reason: 'the current step retains its state');
    await tester.pumpWidget(const SizedBox());
  });
}
