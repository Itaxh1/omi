// First-run onboarding (v3): Welcome, Three things to know, the name, How will you record, the
// microphone, You're set, the progress bars, and the device connect and search pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/pages/onboarding/auth.dart';
import 'package:omi/pages/onboarding/complete_screen.dart';
import 'package:omi/pages/onboarding/find_device/page.dart';
import 'package:omi/pages/capture/connect.dart';
import 'package:omi/pages/onboarding/wrapper.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';

import '../harness.dart';

/// One v3 step inside the wrapper: the back ring and the five progress bars over the step.
Future<void> _step(AuditRun a, int page, String action) async {
  await a.pump(OnboardingWrapper(initialPage: page), scaffold: false, providers: [
    ChangeNotifierProvider<HomeProvider>(create: (_) => _NoSpeakerCheckHomeProvider()),
  ]);
  await a.shot(action);
}

final onboardingScenarios = <AuditScenario>[
  AuditScenario(
    id: 'onboarding-welcome',
    title: 'Welcome (v3): the mark, what Omi does, Apple and Google',
    page: 'lib/pages/onboarding/auth.dart (AuthComponent)',
    state: 'Signed out; first launch',
    run: (a) async {
      await a.pump(AuthComponent(onSignIn: () {}));
      await a.shot('Welcome: Continue with Apple, Continue with Google and the fine print');
    },
  ),
  AuditScenario(
    id: 'onboarding-ai-consent',
    title: 'Three things to know (consent)',
    page: 'lib/pages/onboarding/wrapper.dart (OnboardingWrapper → AiConsentWidget)',
    state: 'Signed-in fixture account that has not yet agreed',
    run: (a) => _step(a, OnboardingWrapper.consentPage, 'Three things to know: I agree and the privacy policy'),
  ),
  AuditScenario(
    id: 'onboarding-name',
    title: 'What should Omi call you?',
    page: 'lib/pages/onboarding/wrapper.dart (OnboardingWrapper → NameWidget)',
    state: 'Signed-in fixture account with no given name',
    run: (a) => _step(a, OnboardingWrapper.namePage, 'The name step'),
  ),
  AuditScenario(
    id: 'onboarding-pick-device',
    title: 'How will you record?',
    page: 'lib/pages/onboarding/wrapper.dart (OnboardingWrapper → OnboardingPickDeviceStep)',
    state: 'Signed in, consent given; nothing paired',
    run: (a) => _step(a, OnboardingWrapper.pickDevicePage, 'The device question: an Omi, or just this phone'),
  ),
  AuditScenario(
    id: 'onboarding-permissions',
    title: 'Allow the microphone',
    page: 'lib/pages/onboarding/wrapper.dart (OnboardingWrapper → PermissionsWidget)',
    state: 'Signed in; the microphone not asked yet',
    run: (a) => _step(a, OnboardingWrapper.permissionsPage, 'The microphone step'),
  ),
  AuditScenario(
    id: 'onboarding-complete',
    title: "You're set",
    page: 'lib/pages/onboarding/complete_screen.dart (OnboardingCompleteScreen)',
    state: 'Every onboarding step done',
    run: (a) async {
      // A value provider: the page reads it for the permission rows, and the audit must not dispose
      // it (its dispose reaches for the capture services).
      await a.pump(OnboardingCompleteScreen(onComplete: () {}), providers: [
        ChangeNotifierProvider<OnboardingProvider>.value(value: _NoDevicesOnboardingProvider()),
      ]);
      await a.shot("You're set: the mark, what happens next, the permission rows and Open Omi");
    },
  ),
  AuditScenario(
    id: 'onboarding-progress-dots',
    title: 'Onboarding progress bars',
    page: 'lib/pages/onboarding/wrapper.dart (OnboardingProgressDots)',
    state: 'Step 2 of 5',
    run: (a) async {
      await a.pump(const Center(child: OnboardingProgressDots(current: 1, total: 5)));
      await a.shot('Progress bars on step 2 of 5');
    },
  ),
  AuditScenario(
    id: 'onboarding-connect',
    title: 'Connect in onboarding: three steps, Continue and Set up later',
    page: 'lib/pages/capture/connect.dart (ConnectDevicePage)',
    state: 'OnboardingProvider reporting a connected device with Bluetooth allowed; no words heard yet',
    run: (a) async {
      await a.pump(ConnectDevicePage(onDone: () {}), providers: [
        ChangeNotifierProvider<OnboardingProvider>.value(value: _ConnectedOnboardingProvider()),
        ChangeNotifierProvider<HomeProvider>(create: (_) => _NoSpeakerCheckHomeProvider()),
      ]);
      await a.shot('Connected: steps 1 and 2 ticked, the live test waiting for words');
    },
  ),
  AuditScenario(
    id: 'onboarding-find-devices-none',
    title: 'Find devices: nothing found',
    page: 'lib/pages/onboarding/find_device/page.dart (FindDevicesPage)',
    state:
        'OnboardingProvider with no discovered devices and pairing instructions enabled; BLE scan and speaker-profile check are no-ops',
    run: (a) async {
      await a.pump(FindDevicesPage(goNext: () {}, includeSkip: true, isFromOnboarding: true), providers: [
        ChangeNotifierProvider<OnboardingProvider>.value(value: _NoDevicesOnboardingProvider()),
        ChangeNotifierProvider<HomeProvider>(create: (_) => _NoSpeakerCheckHomeProvider()),
      ]);
      await a.shot("The can't-find-your-device state");
    },
  ),
];

/// deviceList and enableInstructions are plain fields; only the BLE scan needs replacing.
class _NoDevicesOnboardingProvider extends OnboardingProvider {
  _NoDevicesOnboardingProvider() {
    deviceList = [];
    enableInstructions = true;
  }
  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async {}
}

/// The page asks HomeProvider for the speaker profile, which reports to analytics through an
/// uninitialised Env; the answer does not change this screen.
class _ConnectedOnboardingProvider extends OnboardingProvider {
  _ConnectedOnboardingProvider() {
    deviceList = [];
    isConnected = true;
    hasBluetoothPermission = true;
  }
  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async {}
}

class _NoSpeakerCheckHomeProvider extends HomeProvider {
  @override
  Future setupHasSpeakerProfile() async {}
}
