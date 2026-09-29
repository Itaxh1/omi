import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/devices/pair_device_sheet.dart';
import 'package:omi/providers/onboarding_provider.dart';

/// Devices → Add a device (v8 `pair`): looking, found with Pair, pairing, then connected.
class _Onboarding extends OnboardingProvider {
  int scans = 0;
  BtDevice? tapped;
  VoidCallback? paired;

  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async => scans++;

  @override
  void cancelActiveScan() {}

  @override
  Future<void> handleTap({required BtDevice device, required bool isFromOnboarding, VoidCallback? goNext}) async {
    tapped = device;
    paired = goNext;
    connectingToDeviceId = device.id;
    notifyListeners();
  }

  void found(BtDevice device) {
    deviceList = [device];
    notifyListeners();
  }

  void finishPairing() {
    connectingToDeviceId = null;
    deviceName = 'Omi';
    batteryPercentage = 45;
    isConnected = true;
    notifyListeners();
    paired?.call();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  testWidgets('it looks, finds the pendant, pairs it and says it is connected', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final onboarding = _Onboarding();
    await tester.pumpWidget(ChangeNotifierProvider<OnboardingProvider>.value(
      value: onboarding,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => PairDeviceSheet.show(context), child: const Text('Add a device')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Add a device'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Looking for your pendant'), findsOneWidget);
    expect(find.text('Hold the pendant close. It should light up.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byKey(const Key('pair_other_devices')), findsOneWidget);
    expect(onboarding.scans, 1);

    final pendant = BtDevice(id: 'AA:BB:CC:DD:A3:F2', name: 'Omi', type: DeviceType.omi, rssi: -50);
    onboarding.found(pendant);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Found one'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_pair')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(onboarding.tapped, pendant);
    expect(find.text('Pairing…'), findsWidgets);
    expect(find.text('Hold on'), findsOneWidget);

    onboarding.finishPairing();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Paired'), findsOneWidget);
    expect(find.text('Your pendant’s connected'), findsOneWidget);
    expect(find.text('Omi, 45% battery. It’ll start recording when you say so.'), findsOneWidget);
    expect(find.byKey(const Key('pair_start_recording')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget, reason: 'nothing left to cancel');
  });
}
