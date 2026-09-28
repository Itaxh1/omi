import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/backend/schema/message_event.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';

/// Only what the label reads.
class _Capture extends ChangeNotifier implements CaptureProvider {
  _Capture({
    this.source,
    this.recording = RecordingState.stop,
    this.paused = false,
    this.phonePaused = false,
    this.stopped = false,
    this.hasDevice = false,
    this.micHeld = false,
  });

  final String? source;
  final RecordingState recording;
  final bool paused;
  final bool phonePaused;
  final bool stopped;
  final bool hasDevice;
  final bool micHeld;

  @override
  String? get liveCaptureSource => source;
  @override
  RecordingState get recordingState => recording;
  @override
  bool get isPaused => paused;
  @override
  bool get isPhoneMicPaused => phonePaused;
  @override
  bool get isCaptureStopped => stopped;
  @override
  bool get isStopping => false;
  @override
  bool get havingRecordingDevice => hasDevice;
  @override
  bool get isPhoneMicBatchRecording => false;
  @override
  bool get offlineMuted => false;
  @override
  MessageServiceStatusEvent? get terminalTranscriptionFailure => null;
  @override
  bool get isCallActive => micHeld;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call extends ChangeNotifier implements PhoneCallProvider {
  _Call(this.state);
  final PhoneCallState state;
  @override
  PhoneCallState get callState => state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ValueNotifier<bool>> _pump(WidgetTester tester, _Capture capture, {PhoneCallState call = PhoneCallState.idle}) async {
  final open = ValueNotifier(false);
  addTearDown(open.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CaptureProvider>.value(value: capture),
          ChangeNotifierProvider<PhoneCallProvider>.value(value: _Call(call)),
        ],
        child: Scaffold(body: Center(child: HomeListeningLabel(recorderOpen: open))),
      ),
    ),
  );
  await tester.pump();
  return open;
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(HomeListeningLabel)));

/// The Listening label (v3): the mark and the word while listening, dots alone while muted, dots
/// and Start while nothing listens; a tap toggles the recorder card.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test('state: listening, muted, idle, and a call counts as listening', () {
    final live = _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true);
    expect(HomeListeningLabel.stateOf(live, PhoneCallState.idle), ListeningLabelState.listening);
    final muted = _Capture(source: 'omi', recording: RecordingState.pause, paused: true, hasDevice: true);
    expect(HomeListeningLabel.stateOf(muted, PhoneCallState.idle), ListeningLabelState.muted);
    final phoneMuted = _Capture(source: 'phone', recording: RecordingState.record, phonePaused: true);
    expect(HomeListeningLabel.stateOf(phoneMuted, PhoneCallState.idle), ListeningLabelState.muted);
    final idle = _Capture();
    expect(HomeListeningLabel.stateOf(idle, PhoneCallState.idle), ListeningLabelState.idle);
    final stopped = _Capture(stopped: true, paused: true, hasDevice: true);
    expect(HomeListeningLabel.stateOf(stopped, PhoneCallState.idle), ListeningLabelState.idle);
    expect(HomeListeningLabel.stateOf(idle, PhoneCallState.active), ListeningLabelState.listening);
  });

  testWidgets('listening: the waving mark and the word; a tap opens the recorder card', (tester) async {
    final open = await _pump(tester, _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true));
    final l10n = _l10n(tester);
    expect(find.text(l10n.listening), findsOneWidget);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).mode, OmiRingMode.wave);
    expect(find.byKey(const Key('home_listening_alert')), findsNothing);

    await tester.tap(find.byKey(const Key('home_listening_label')));
    expect(open.value, isTrue);
    await tester.pump();
    await tester.tap(find.byKey(const Key('home_listening_label')));
    expect(open.value, isFalse);
  });

  testWidgets('muted: the dots stay and the word goes; the screen reader still hears Muted', (tester) async {
    await _pump(tester, _Capture(source: 'omi', recording: RecordingState.pause, paused: true, hasDevice: true));
    final l10n = _l10n(tester);
    expect(find.byKey(const Key('home_listening_word')), findsNothing);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).mode, OmiRingMode.still);
    expect(find.bySemanticsLabel(l10n.muted), findsOneWidget);
  });

  testWidgets('idle: dimmed dots and Start', (tester) async {
    await _pump(tester, _Capture());
    final l10n = _l10n(tester);
    expect(find.text(l10n.start), findsOneWidget);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).color, OmiColors.textTertiary);
  });

  testWidgets('a problem the card explains shows the red dot on the mark', (tester) async {
    await _pump(tester, _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true, micHeld: true));
    expect(find.byKey(const Key('home_listening_alert')), findsOneWidget);
  });
}
