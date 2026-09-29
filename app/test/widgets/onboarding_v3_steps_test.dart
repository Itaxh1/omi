/// The v3 onboarding flows' own steps (Omi v8 mock `ob*`): the pendant's setup (turn it on,
/// Bluetooth, pair, the button), the first real recording and its write-up, and reading three
/// lines so Omi learns the reader's voice.
library;

import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/onboarding/first_conversation_steps.dart';
import 'package:omi/pages/onboarding/guided_voice_controller.dart';
import 'package:omi/pages/onboarding/pendant_steps.dart';
import 'package:omi/pages/onboarding/voice_steps.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/services/services.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';

class _Onboarding extends OnboardingProvider {
  int bluetoothAsked = 0;
  int scans = 0;
  BtDevice? tapped;

  @override
  Future askForBluetoothPermissions() async => bluetoothAsked++;

  @override
  Future<void> scanDevices({required VoidCallback onShowDialog, VoidCallback? onShowLocationDialog}) async => scans++;

  @override
  void cancelActiveScan() {}

  @override
  Future<void> handleTap({required BtDevice device, required bool isFromOnboarding, VoidCallback? goNext}) async {
    tapped = device;
    connectingToDeviceId = device.id;
    notifyListeners();
  }

  void pairedNow() {
    connectingToDeviceId = null;
    isConnected = true;
    notifyListeners();
  }
}

class _Capture extends CaptureProvider {
  int started = 0;
  int finished = 0;
  int stopped = 0;
  String? source;
  Completer<void>? finishBarrier;
  bool failStart = false;

  @override
  String? get liveCaptureSource => source;

  @override
  Future streamRecording({bool resumeCapture = true}) async {
    started++;
    if (failStart) throw StateError('Microphone unavailable');
    source = 'phone';
    recordingState = RecordingState.record;
    notifyListeners();
  }

  @override
  Future<void> finishCapture() async {
    finished++;
    await finishBarrier?.future;
  }

  @override
  Future<bool> stopStreamRecording({String reason = 'user_stopped', bool resumeHandedOffPendant = true}) async {
    stopped++;
    return true;
  }

  void hear(String text) {
    segments = [
      ...segments,
      TranscriptSegment(
        id: 's${segments.length}',
        text: text,
        speaker: 'SPEAKER_00',
        isUser: true,
        personId: null,
        start: 0,
        end: 1,
        translations: const [],
      ),
    ];
    notifyListeners();
  }
}

class _Conversations extends ConversationProvider {
  final toggled = <(String, String, bool)>[];
  void inFlight(String id) {
    processingConversations = [
      ServerConversation(
        id: id,
        createdAt: DateTime.now(),
        structured: Structured('', ''),
        status: ConversationStatus.processing,
      ),
    ];
    notifyListeners();
  }

  void arrive(ServerConversation conversation) {
    processingConversations = [];
    conversations = [conversation, ...conversations];
    notifyListeners();
  }

  @override
  Future<void> updateGlobalActionItemState(ServerConversation conversation, String description, bool value) async {
    toggled.add((conversation.id, description, value));
    conversation.structured.actionItems.firstWhere((item) => item.description == description).completed = value;
    notifyListeners();
  }
}

class _VoiceIO implements GuidedVoiceIO {
  void Function(Uint8List)? onAudio;
  VoidCallback? onInterrupted;
  int enrolled = 0;
  int closed = 0;
  bool enrollResult = true;
  bool failStart = false;

  @override
  bool get livePreview => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> start(void Function(Uint8List) onAudio, VoidCallback onInterrupted) async {
    if (failStart) throw StateError('Microphone unavailable');
    this.onAudio = onAudio;
    this.onInterrupted = onInterrupted;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<String> transcribe(Uint8List pcm) async => '';

  @override
  Future<bool> enroll(Uint8List pcm) async {
    enrolled = pcm.length;
    return enrollResult;
  }

  @override
  Future<bool> remember(String text) async => true;

  @override
  Future<bool> saveGoal(String text, String idempotencyKey) async => true;

  @override
  Future<void> close() async => closed++;

  /// [ms] of 16 kHz mono audio, loud (speech) or near silence.
  void feed(int ms, {required bool loud}) {
    final samples = 16 * ms;
    final data = ByteData(samples * 2);
    for (var i = 0; i < samples; i++) {
      data.setInt16(i * 2, loud ? (i.isEven ? 2000 : -2000) : 10, Endian.little);
    }
    onAudio!(data.buffer.asUint8List());
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await ServiceManager.init();
    } catch (_) {}
  });

  setUp(() async {
    BluetoothReadiness.instance.onNativeStateChangedForTesting('on');
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  Widget app(
    Widget child, {
    OnboardingProvider? onboarding,
    CaptureProvider? capture,
    ConversationProvider? conversations,
    DeviceProvider? device,
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding ?? _Onboarding()),
          ChangeNotifierProvider<CaptureProvider>.value(value: capture ?? _Capture()),
          ChangeNotifierProvider<ConversationProvider>.value(value: conversations ?? _Conversations()),
          ChangeNotifierProvider<DeviceProvider>.value(value: device ?? (DeviceProvider()..isConnected = true)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: Scaffold(body: child),
        ),
      );

  group('Turn on your Omi', () {
    testWidgets('It’s on waits for the press on the picture; the light turns red', (tester) async {
      var on = 0;
      await tester.pumpWidget(app(OnboardingPowerStep(onOn: () => on++)));
      expect(find.text('Step 1 of 3 · Your Omi'), findsOneWidget);
      expect(find.text('Tap the picture to try it.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_power_on')));
      expect(on, 0, reason: 'disabled until the button was pressed');

      await tester.tap(find.byKey(const Key('onboarding_power_pendant')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Red means it isn’t paired yet'), findsOneWidget);
      final photo = tester.widget<OmiPendantPhoto>(find.byType(OmiPendantPhoto));
      expect(photo.led, OmiPendantLed.red);

      await tester.tap(find.byKey(const Key('onboarding_power_on')));
      expect(on, 1);
    });

    testWidgets('The light didn’t come on explains charging', (tester) async {
      await tester.pumpWidget(app(OnboardingPowerStep(onOn: () {})));
      await tester.tap(find.byKey(const Key('onboarding_power_no_light')));
      await tester.pump();
      expect(find.textContaining('It may need charging'), findsOneWidget);
      expect(tester.widget<OmiPendantPhoto>(find.byType(OmiPendantPhoto)).led, OmiPendantLed.greenBlink);
    });
  });

  testWidgets('Turn on Bluetooth asks the system, and Not now moves on too', (tester) async {
    final onboarding = _Onboarding();
    final next = <bool>[];
    await tester.pumpWidget(app(OnboardingBluetoothStep(onNext: next.add), onboarding: onboarding));
    expect(find.text('Turn on Bluetooth'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_bluetooth_allow')));
    await tester.pump();
    expect(onboarding.bluetoothAsked, 1);
    expect(next, [true]);
    await tester.tap(find.byKey(const Key('onboarding_bluetooth_not_now')));
    expect(next, [true, false]);
  });

  group('Looking for your Omi', () {
    testWidgets('scans, lists each pendant nearby with Pair, then says Paired', (tester) async {
      final onboarding = _Onboarding();
      var phone = 0;
      await tester.pumpWidget(app(
        OnboardingScanStep(onPaired: () {}, onUsePhone: () => phone++),
        onboarding: onboarding,
      ));
      await tester.pump();
      expect(onboarding.scans, 1);
      expect(find.text('Looking for your Omi'), findsOneWidget);

      onboarding
        ..deviceList = [BtDevice(id: '6C:2A:9E:11:A3:F2', name: 'Omi', type: DeviceType.omi, rssi: -50)]
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Omi pendant'), findsOneWidget);
      expect(find.text('A3F2 · nearby'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_pair')));
      await tester.pump();
      expect(onboarding.tapped?.id, '6C:2A:9E:11:A3:F2');
      expect(find.text('Pairing…'), findsOneWidget);

      onboarding.pairedNow();
      await tester.pump();
      expect(find.text('Paired'), findsOneWidget);
      expect(find.textContaining('solid blue'), findsOneWidget);
      expect(tester.widget<OmiPendantPhoto>(find.byType(OmiPendantPhoto)).led, OmiPendantLed.blue);

      await tester.tap(find.byKey(const Key('onboarding_use_phone_instead')));
      expect(phone, 1);
    });

    testWidgets('after Not now it waits for Bluetooth without asking, until Turn on', (tester) async {
      final onboarding = _Onboarding();
      await tester.pumpWidget(app(
        OnboardingScanStep(bluetoothDeclined: true, onPaired: () {}, onUsePhone: () {}),
        onboarding: onboarding,
      ));
      await tester.pump();
      expect(onboarding.scans, 0);
      expect(onboarding.bluetoothAsked, 0);
      expect(find.text('Waiting for Bluetooth'), findsOneWidget);
      expect(find.text('Bluetooth is off'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_bluetooth_turn_on')));
      await tester.pump();
      expect(onboarding.bluetoothAsked, 1);
      expect(onboarding.scans, 1);
      expect(find.text('Looking for your Omi'), findsOneWidget);
    });

    test('the short id is the last four letters or digits', () {
      expect(OnboardingScanStep.shortId('6C:2A:9E:11:A3:F2'), 'A3F2');
      expect(OnboardingScanStep.shortId('1b3f'), '1B3F');
    });
  });

  testWidgets('One button, three moves, then what the light means', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = 0;
    await tester.pumpWidget(app(OnboardingButtonsStep(onDone: () => done++)));
    expect(find.text('One button, three moves'), findsOneWidget);
    expect(find.text('Tap once'), findsOneWidget);
    expect(find.text('Tap twice'), findsOneWidget);
    expect(find.text('Hold for 3 seconds'), findsOneWidget);
    expect(find.text('What the light means'), findsOneWidget);
    expect(find.text('Solid blue'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_buttons_got_it')));
    expect(done, 1);
  });

  group('Say a few words', () {
    testWidgets('a dead pendant stops claiming to listen and offers phone capture immediately', (tester) async {
      final capture = _Capture()..source = 'omi';
      final device = DeviceProvider()..isConnected = true;
      var switched = 0;
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(wearable: true, onDone: () {}, onSkip: () {}, onUsePhone: () => switched++),
        capture: capture,
        device: device,
      ));
      expect(find.text('Listening on your Omi'), findsOneWidget);
      device.setIsConnected(false);
      await tester.pump();
      expect(find.text('Listening on your Omi'), findsNothing);
      expect(find.byKey(const Key('onboarding_first_use_phone')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_first_skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_first_use_phone')));
      await tester.pump();
      expect(capture.started, 1);
      expect(switched, 1);
      expect(find.text('Listening on this phone'), findsOneWidget);
      capture.hear('A first note');
      await tester.pump();
      expect(find.text('note '), findsOneWidget);
    });

    testWidgets('a refused phone fallback leaves retry, Settings and skip available', (tester) async {
      final capture = _Capture()..failStart = true;
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(wearable: true, onDone: () {}, onSkip: () {}),
        capture: capture,
        device: DeviceProvider(),
      ));
      await tester.tap(find.byKey(const Key('onboarding_first_use_phone')));
      await tester.pump();
      expect(find.text('Listening on this phone'), findsNothing);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_first_skip')), findsOneWidget);
    });

    testWidgets('Done advances after twelve seconds even when finalization never returns', (tester) async {
      final barrier = Completer<void>();
      final capture = _Capture()..finishBarrier = barrier;
      var done = 0;
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(wearable: false, onDone: () => done++, onSkip: () {}),
        capture: capture,
      ));
      await tester.pump();
      capture.hear('Keep these words');
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding_first_done')));
      await tester.pump(const Duration(seconds: 11));
      expect(done, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
      barrier.complete();
      await tester.pump();
      expect(done, 1);
    });
    testWidgets('this phone listens; the words show; Done ends the recording', (tester) async {
      final capture = _Capture();
      final order = <String>[];
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(
          wearable: false,
          onFinishing: () => order.add('noted'),
          onDone: () => order.add('done'),
          onSkip: () {},
        ),
        capture: capture,
      ));
      await tester.pump();
      expect(capture.started, 1);
      expect(find.text('Listening on this phone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_first_done')));
      expect(order, isEmpty, reason: 'Done waits for words');

      capture.hear('Remind me to call Sam tomorrow.');
      await tester.pump();
      expect(find.text('Remind '), findsOneWidget);
      expect(find.text('tomorrow. '), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_first_done')));
      await tester.pump();
      expect(capture.finished, 1);
      expect(order, ['noted', 'done']);
    });

    testWidgets('the pendant listens already; words heard while pairing stay out', (tester) async {
      final capture = _Capture()
        ..source = 'omi'
        ..hear('pairing chatter');
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(wearable: true, onDone: () {}, onSkip: () {}),
        capture: capture,
      ));
      await tester.pump();
      expect(capture.started, 0);
      expect(find.text('Listening on your Omi'), findsOneWidget);
      expect(find.text('chatter '), findsNothing);
      capture.hear('hello');
      await tester.pump();
      expect(find.text('hello '), findsOneWidget);
    });

    testWidgets('nothing heard for a while offers Skip for now', (tester) async {
      var skipped = 0;
      await tester.pumpWidget(app(
        OnboardingFirstWordsStep(
          wearable: false,
          quietFor: const Duration(seconds: 2),
          onDone: () {},
          onSkip: () => skipped++,
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('onboarding_first_skip')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const Key('onboarding_first_skip')));
      expect(skipped, 1);
    });
  });

  group('Your first conversation', () {
    ServerConversation written({bool discarded = false, Structured? structured}) => ServerConversation(
          id: 'first',
          createdAt: DateTime.now(),
          startedAt: DateTime.now().subtract(const Duration(seconds: 6)),
          finishedAt: DateTime.now(),
          discarded: discarded,
          structured: structured ??
              (Structured('Call Sam tomorrow', 'You want to call Sam tomorrow.')
                ..actionItems = [ActionItem('Call Sam')]),
        );

    testWidgets('writes it up, then shows the title, the summary and its to-dos', (tester) async {
      final conversations = _Conversations()..inFlight('processing');
      var next = 0;
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(knownIds: const {}, wearable: false, onContinue: () => next++),
        conversations: conversations,
      ));
      await tester.pump();
      expect(find.text('Omi is writing it up…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_result_continue')));
      expect(next, 0);

      conversations.arrive(written());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Your first conversation'), findsOneWidget);
      expect(find.text('Call Sam tomorrow'), findsOneWidget);
      expect(find.textContaining('Just now'), findsOneWidget);
      expect(find.textContaining('this phone'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('To do from this'), findsOneWidget);
      expect(find.text('Call Sam'), findsOneWidget);
      await tester.tap(find.byType(OmiCheckRing));
      await tester.pump();
      expect(conversations.toggled, [('first', 'Call Sam', true)]);
      await tester.tap(find.byKey(const Key('onboarding_result_continue')));
      expect(next, 1);
    });

    testWidgets('arbitrary reminder content comes from processing; ordinary speech creates no demo task',
        (tester) async {
      final conversations = _Conversations();
      final result = written(
          structured: Structured('Buy groceries', 'Pick up oat milk this evening.')
            ..actionItems = [ActionItem('Buy oat milk')]);
      conversations.arrive(result);
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(knownIds: const {}, wearable: false, onContinue: () {}),
        conversations: conversations,
      ));
      await tester.pump();
      expect(find.text('Buy oat milk'), findsOneWidget);
      expect(find.text('Call Sam'), findsNothing);
      final plain = _Conversations()
        ..arrive(written(structured: Structured('A first note', 'I enjoyed my walk today.')));
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(
            key: const Key('ordinary_speech'), knownIds: const {}, wearable: false, onContinue: () {}),
        conversations: plain,
      ));
      await tester.pump();
      expect(find.text('A first note'), findsOneWidget);
      expect(find.byType(OmiCheckRing), findsNothing);
      expect(find.text('Call Sam'), findsNothing);
    });

    testWidgets('missing upload stays pending; only a discarded result is too short', (tester) async {
      final conversations = _Conversations();
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(
          knownIds: const {},
          wearable: true,
          onContinue: () {},
          settle: const Duration(milliseconds: 300),
        ),
        conversations: conversations,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('too short'), findsNothing);
      expect(find.byKey(const ValueKey('still')), findsOneWidget);

      final discarded = _Conversations();
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(
            key: const Key('discarded_result'), knownIds: const {}, wearable: true, onContinue: () {}),
        conversations: discarded,
      ));
      discarded.arrive(written(discarded: true));
      await tester.pump();
      expect(find.textContaining('too short'), findsOneWidget);
    });

    testWidgets('one that takes too long is left to Home', (tester) async {
      final conversations = _Conversations()..inFlight('processing');
      await tester.pumpWidget(app(
        OnboardingFirstResultStep(
          knownIds: const {},
          wearable: false,
          onContinue: () {},
          timeout: const Duration(seconds: 2),
        ),
        conversations: conversations,
      ));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('still writing it up'), findsOneWidget);
    });
  });

  group('Teach Omi your voice', () {
    testWidgets('microphone interruption exits reading without saving a partial voice profile', (tester) async {
      final io = _VoiceIO();
      var done = 0;
      await tester.pumpWidget(app(OnboardingVoiceReadStep(io: io, onDone: () => done++)));
      await tester.pump();
      io.feed(1000, loud: true);
      io.onInterrupted!();
      await tester.pump();
      expect(done, 1);
      expect(io.enrolled, 0);
      expect(io.closed, 1);
    });

    testWidgets('microphone start failure leaves onboarding available and saves no voice', (tester) async {
      final io = _VoiceIO()..failStart = true;
      var done = 0;
      await tester.pumpWidget(app(OnboardingVoiceReadStep(io: io, onDone: () => done++)));
      await tester.pump();
      expect(done, 1);
      expect(io.enrolled, 0);
      expect(io.closed, 1);
    });

    testWidgets('rejected voice enrollment reports failure while completing the three-line flow', (tester) async {
      final io = _VoiceIO()..enrollResult = false;
      var done = 0;
      bool? enrolled;
      await tester
          .pumpWidget(app(OnboardingVoiceReadStep(io: io, onDone: () => done++, onEnrolled: (ok) => enrolled = ok)));
      await tester.pump();
      for (var line = 0; line < 3; line++) {
        io
          ..feed(2000, loud: true)
          ..feed(800, loud: false);
        await tester.pump();
      }
      expect(done, 1);
      expect(enrolled, isFalse);
      expect(io.closed, 1);
    });

    testWidgets('Start or Do this later', (tester) async {
      var started = 0;
      var later = 0;
      await tester.pumpWidget(app(OnboardingVoiceIntroStep(onStart: () => started++, onLater: () => later++)));
      expect(find.text('Teach Omi your voice'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speech_profile_start')));
      await tester.tap(find.byKey(const Key('onboarding_voice_later')));
      expect((started, later), (1, 1));
    });

    testWidgets('each line moves on once it was read; the three are saved as the voice', (tester) async {
      final io = _VoiceIO();
      var done = 0;
      bool? enrolled;
      await tester
          .pumpWidget(app(OnboardingVoiceReadStep(io: io, onDone: () => done++, onEnrolled: (ok) => enrolled = ok)));
      await tester.pump();
      expect(find.text('Read this out loud'), findsOneWidget);
      expect(find.text('The quick brown fox jumps over the lazy dog.'), findsOneWidget);

      for (var line = 0; line < 3; line++) {
        io
          ..feed(2000, loud: true)
          ..feed(800, loud: false);
        await tester.pump();
        if (line < 2) {
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byKey(const Key('onboarding_read_line')), findsOneWidget);
        }
      }
      expect(find.text('Remind me to send the deck on Friday.'), findsOneWidget);
      expect(done, 1);
      await tester.pump();
      expect(io.enrolled, greaterThanOrEqualTo(5 * 32000));
      expect(enrolled, isTrue);
      expect(io.closed, 1);
    });

    testWidgets('Skip saves nothing', (tester) async {
      final io = _VoiceIO();
      var done = 0;
      bool? enrolled;
      await tester
          .pumpWidget(app(OnboardingVoiceReadStep(io: io, onDone: () => done++, onEnrolled: (ok) => enrolled = ok)));
      await tester.pump();
      io.feed(1000, loud: true);
      await tester.tap(find.byKey(const Key('speech_profile_skip_intro')));
      await tester.pump();
      expect(done, 1);
      expect(io.enrolled, 0);
      expect(enrolled, isNull);
    });
  });
}
