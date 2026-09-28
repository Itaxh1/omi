// First-run onboarding (v3): Welcome, Three things to know, the name, How will you record, the
// pendant's setup (turn it on, Bluetooth, pair, its button) or the microphone, Say a few words,
// your first conversation, Teach Omi your voice and the lines to read, You're set, the progress
// bars, and the device connect and search pages (Add a device).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/pages/onboarding/guided_voice_controller.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/utils/enums.dart';

import 'package:omi/pages/onboarding/auth.dart';
import 'package:omi/pages/onboarding/complete_screen.dart';
import 'package:omi/pages/onboarding/find_device/page.dart';
import 'package:omi/pages/capture/connect.dart';
import 'package:omi/pages/onboarding/wrapper.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';

import '../harness.dart';

/// One v3 step inside the wrapper: the back ring and the six progress bars over the step.
Future<void> _step(AuditRun a, int page, String action,
    {bool wearable = false, List<SingleChildWidget> providers = const [], String? step}) async {
  await a.pump(
    OnboardingWrapper(initialPage: page, initialWearable: wearable, voiceIO: _QuietVoice()),
    scaffold: false,
    providers: [
      ChangeNotifierProvider<HomeProvider>(create: (_) => _NoSpeakerCheckHomeProvider()),
      ...providers,
    ],
  );
  await a.shot(action, step: step);
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
    id: 'onboarding-power',
    title: 'Turn on your Omi (pendant 1 of 3)',
    page: 'lib/pages/onboarding/pendant_steps.dart (OnboardingPowerStep)',
    state: 'Pendant path; the picture not pressed yet, then pressed, then the light did not come on',
    run: (a) async {
      await _step(a, OnboardingWrapper.powerPage, 'The pendant with the ring showing where to press', wearable: true);
      await a.tap(find.byKey(const Key('onboarding_power_pendant')));
      await a.shot("Pressed: the light is red and It's on is ready", step: 'on');
      await a.tap(find.byKey(const Key('onboarding_power_no_light')));
      await a.shot('The light did not come on: it may need charging', step: 'no-light');
    },
  ),
  AuditScenario(
    id: 'onboarding-bluetooth',
    title: 'Turn on Bluetooth (pendant path)',
    page: 'lib/pages/onboarding/pendant_steps.dart (OnboardingBluetoothStep)',
    state: 'Pendant path; Bluetooth not asked yet',
    run: (a) => _step(a, OnboardingWrapper.bluetoothPage, 'Allow Bluetooth and Not now', wearable: true),
  ),
  AuditScenario(
    id: 'onboarding-scan',
    title: 'Looking for your Omi (pendant 2 of 3)',
    page: 'lib/pages/onboarding/pendant_steps.dart (OnboardingScanStep)',
    state: 'Pendant path; one pendant found nearby, then paired; then Bluetooth switched off',
    run: (a) async {
      final onboarding = _FoundOnboardingProvider();
      await _step(a, OnboardingWrapper.scanPage, 'A pendant found nearby with Pair',
          wearable: true, providers: [ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding)]);
      onboarding.pairedNow();
      await a.settle();
      await a.shot('Paired: the light is solid blue', step: 'paired');
      final onboardingOff = _FoundOnboardingProvider()..deviceList = [];
      BluetoothReadiness.instance.onNativeStateChangedForTesting('off');
      try {
        await _step(a, OnboardingWrapper.scanPage, 'Bluetooth off: the banner and Waiting for Bluetooth',
            wearable: true,
            providers: [ChangeNotifierProvider<OnboardingProvider>.value(value: onboardingOff)],
            step: 'bluetooth-off');
      } finally {
        BluetoothReadiness.instance.onNativeStateChangedForTesting('unknown');
      }
    },
  ),
  AuditScenario(
    id: 'onboarding-buttons',
    title: 'One button, three moves (pendant 3 of 3)',
    page: 'lib/pages/onboarding/pendant_steps.dart (OnboardingButtonsStep)',
    state: 'Pendant path; paired',
    run: (a) => _step(a, OnboardingWrapper.buttonsPage, 'The three moves and what the light means', wearable: true),
  ),
  AuditScenario(
    id: 'onboarding-first',
    title: 'Say a few words',
    page: 'lib/pages/onboarding/first_conversation_steps.dart (OnboardingFirstWordsStep)',
    state: 'Phone path; listening, the example sentence heard',
    run: (a) async {
      final capture = _HearingCapture();
      await _step(a, OnboardingWrapper.firstPage, 'Listening on this phone with the words heard',
          providers: [ChangeNotifierProvider<CaptureProvider>.value(value: capture)]);
    },
  ),
  AuditScenario(
    id: 'onboarding-result',
    title: 'Your first conversation',
    page: 'lib/pages/onboarding/first_conversation_steps.dart (OnboardingFirstResultStep)',
    state: 'Phone path; being written up, then written up with one to-do',
    run: (a) async {
      final conversations = _FirstConversationProvider();
      await _step(a, OnboardingWrapper.resultPage, 'Omi is writing it up',
          providers: [ChangeNotifierProvider<ConversationProvider>.value(value: conversations)]);
      conversations.arrive();
      await a.settle();
      await a.shot('Written up: the title, when, the summary and the to-do', step: 'ready');
    },
  ),
  AuditScenario(
    id: 'onboarding-voice',
    title: 'Teach Omi your voice',
    page: 'lib/pages/onboarding/voice_steps.dart (OnboardingVoiceIntroStep)',
    state: 'The voice not taught yet',
    run: (a) => _step(a, OnboardingWrapper.voicePage, 'Start and Do this later'),
  ),
  AuditScenario(
    id: 'onboarding-read',
    title: 'Read this out loud',
    page: 'lib/pages/onboarding/voice_steps.dart (OnboardingVoiceReadStep)',
    state: 'The first of three lines; the microphone quiet',
    run: (a) => _step(a, OnboardingWrapper.readPage, 'The first line to read, its bars and Listening'),
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
    state: 'Step 2 of 6',
    run: (a) async {
      await a.pump(const Center(child: OnboardingProgressDots(current: 1, total: 6)));
      await a.shot('Progress bars on step 2 of 6');
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

/// A pendant found nearby; pairing is a switch the scenario flips.
class _FoundOnboardingProvider extends OnboardingProvider {
  _FoundOnboardingProvider() {
    deviceList = [BtDevice(id: '6C:2A:9E:11:A3:F2', name: 'Omi', type: DeviceType.omi, rssi: -48)];
  }

  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async {}

  @override
  void cancelActiveScan() {}

  void pairedNow() {
    isConnected = true;
    notifyListeners();
  }
}

/// This phone listening, with the example sentence heard.
class _HearingCapture extends CaptureProvider {
  _HearingCapture() {
    recordingState = RecordingState.record;
    segments = [
      TranscriptSegment(
        id: 'first',
        text: 'Remind me to call Sam tomorrow.',
        speaker: 'SPEAKER_00',
        isUser: true,
        personId: null,
        start: 0,
        end: 3,
        translations: const [],
      ),
    ];
  }

  @override
  String? get liveCaptureSource => 'phone';

  @override
  Future streamRecording({bool resumeCapture = true}) async {}

  @override
  Future<bool> stopStreamRecording({String reason = 'user_stopped', bool resumeHandedOffPendant = true}) async => true;
}

/// The first conversation in flight, then written up.
class _FirstConversationProvider extends ConversationProvider {
  _FirstConversationProvider() : super(isSignedIn: () => true) {
    processingConversations = [
      ServerConversation(
        id: 'processing',
        createdAt: DateTime.now(),
        structured: Structured('', ''),
        status: ConversationStatus.processing,
      ),
    ];
  }

  void arrive() {
    processingConversations = [];
    conversations = [
      ServerConversation(
        id: 'first',
        createdAt: DateTime.now(),
        startedAt: DateTime.now().subtract(const Duration(seconds: 6)),
        finishedAt: DateTime.now(),
        structured: Structured('Call Sam tomorrow', '- You want to call Sam tomorrow.')
          ..actionItems = [ActionItem('Call Sam')],
      ),
    ];
    notifyListeners();
  }
}

/// A microphone that hears nothing, so the reading stays on its first line.
class _QuietVoice implements GuidedVoiceIO {
  @override
  bool get livePreview => false;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> start(void Function(Uint8List) onAudio, VoidCallback onInterrupted) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<String> transcribe(Uint8List pcm) async => '';
  @override
  Future<bool> enroll(Uint8List pcm) async => false;
  @override
  Future<bool> remember(String text) async => false;
  @override
  Future<bool> saveGoal(String text, String idempotencyKey) async => false;
  @override
  Future<void> close() async {}
}
