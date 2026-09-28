import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/sync_provider.dart';
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
    this.hasDevice = false,
    this.micHeld = false,
  });

  final String? source;
  final RecordingState recording;
  final bool paused;
  final bool phonePaused;
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
  bool get isCaptureStopped => false;
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

class _Sync extends ChangeNotifier implements SyncProvider {
  _Sync(this.syncing);
  final bool syncing;
  @override
  bool get isSyncing => syncing;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices extends ChangeNotifier implements DeviceProvider {
  _Devices({this.connecting = false, this.connected = true});
  final bool connecting;
  final bool connected;
  @override
  BtDevice? get pairedDevice => BtDevice(id: 'd1', name: 'Omi', type: DeviceType.omi, rssi: -40);
  @override
  bool get isConnecting => connecting;
  @override
  bool get isConnected => connected && !connecting;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<String>> _pump(
  WidgetTester tester,
  _Capture capture, {
  PhoneCallState call = PhoneCallState.idle,
  SyncProvider? sync,
  DeviceProvider? devices,
  ValueListenable<HomePullPhase>? pull,
}) async {
  final opened = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CaptureProvider>.value(value: capture),
          ChangeNotifierProvider<PhoneCallProvider>.value(value: _Call(call)),
          if (sync != null) ChangeNotifierProvider<SyncProvider>.value(value: sync),
          if (devices != null) ChangeNotifierProvider<DeviceProvider>.value(value: devices),
        ],
        child: Scaffold(
          body: Center(child: HomeListeningLabel(onOpen: () => opened.add('omi'), pull: pull)),
        ),
      ),
    ),
  );
  await tester.pump();
  return opened;
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(HomeListeningLabel)));

HomeRecorderState _state(
  _Capture capture, {
  PhoneCallState call = PhoneCallState.idle,
  bool paired = false,
  bool connected = false,
  bool connecting = false,
  bool bluetoothOff = false,
}) =>
    HomeListeningLabel.stateOf(
      call: call,
      capture: capture,
      paired: paired,
      connected: connected,
      connecting: connecting,
      bluetoothOff: bluetoothOff,
    );

/// The Listening label (v8.1): what Omi is doing and what to do about it; the pull's words while
/// Home is pulled; a tap opens Your Omi.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test("states, in the design's order", () {
    final live = _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true);
    expect(_state(live, paired: true, connected: true), HomeRecorderState.listening);
    final muted = _Capture(source: 'omi', recording: RecordingState.pause, paused: true, hasDevice: true);
    expect(_state(muted, paired: true, connected: true), HomeRecorderState.paused);
    final phoneMuted = _Capture(source: 'phone', recording: RecordingState.record, phonePaused: true);
    expect(_state(phoneMuted), HomeRecorderState.paused);
    final idle = _Capture();
    expect(_state(idle), HomeRecorderState.off);
    expect(_state(idle, call: PhoneCallState.active), HomeRecorderState.listening);
    // A paired pendant: Bluetooth off, reconnecting, then not found.
    expect(_state(idle, paired: true, bluetoothOff: true), HomeRecorderState.bluetoothOff);
    expect(_state(idle, paired: true, connecting: true), HomeRecorderState.reconnecting);
    expect(_state(idle, paired: true), HomeRecorderState.notFound);
    // The phone recording carries on whatever the pendant is doing.
    final phone = _Capture(source: 'phone', recording: RecordingState.record);
    expect(_state(phone, paired: true, bluetoothOff: true), HomeRecorderState.listening);
  });

  testWidgets('listening: the waving mark and the word; a tap opens Your Omi', (tester) async {
    final opened =
        await _pump(tester, _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true));
    final l10n = _l10n(tester);
    expect(find.text(l10n.listening), findsOneWidget);
    expect(find.byKey(const Key('home_listening_hint')), findsNothing);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).mode, OmiRingMode.wave);
    expect(find.byKey(const Key('home_listening_alert')), findsNothing);

    await tester.tap(find.byKey(const Key('home_listening_label')));
    expect(opened, ['omi']);
  });

  testWidgets('paused and off say what a pull down does', (tester) async {
    await _pump(tester, _Capture(source: 'omi', recording: RecordingState.pause, paused: true, hasDevice: true));
    final l10n = _l10n(tester);
    expect(find.text(l10n.paused), findsOneWidget);
    expect(find.text(l10n.pullDownToResume), findsOneWidget);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).mode, OmiRingMode.still);

    await _pump(tester, _Capture());
    expect(find.text(l10n.off), findsOneWidget);
    expect(find.text(l10n.pullDownToStart), findsOneWidget);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).color, OmiColors.textTertiary);
  });

  testWidgets("a pendant that can't be reached says so, with the red dot", (tester) async {
    await _pump(tester, _Capture(), devices: _Devices(connected: false));
    final l10n = _l10n(tester);
    expect(find.text(l10n.omiNotFound), findsOneWidget);
    expect(find.text(l10n.tapForOptions), findsOneWidget);
    expect(find.byKey(const Key('home_listening_alert')), findsOneWidget);
  });

  testWidgets('while Home is pulled down it says what letting go will do', (tester) async {
    final pull = ValueNotifier(HomePullPhase.pulling);
    addTearDown(pull.dispose);
    await _pump(tester, _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true), pull: pull);
    final l10n = _l10n(tester);
    expect(find.text(l10n.pullToPause), findsOneWidget);
    pull.value = HomePullPhase.ready;
    await tester.pump();
    expect(find.text(l10n.releaseToPause), findsOneWidget);
    pull.value = HomePullPhase.none;
    await tester.pump();
    expect(find.text(l10n.listening), findsOneWidget);
  });

  testWidgets('syncing turns the mark slowly; reconnecting turns it fast and lights the dot', (tester) async {
    final live = _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true);
    await _pump(tester, live);
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).turn, OmiRingTurn.none);

    await _pump(tester, live, sync: _Sync(true), devices: _Devices());
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).turn, OmiRingTurn.sync);
    expect(find.byKey(const Key('home_listening_alert')), findsNothing);

    await _pump(tester, _Capture(), sync: _Sync(true), devices: _Devices(connecting: true));
    expect(tester.widget<OmiRingLogo>(find.byType(OmiRingLogo)).turn, OmiRingTurn.reconnect);
    expect(find.text(_l10n(tester).omiKeepsRecording), findsOneWidget);
    expect(find.byKey(const Key('home_listening_alert')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a problem Your Omi explains shows the red dot on the mark', (tester) async {
    await _pump(
        tester, _Capture(source: 'omi', recording: RecordingState.deviceRecord, hasDevice: true, micHeld: true));
    expect(find.byKey(const Key('home_listening_alert')), findsOneWidget);
  });
}
