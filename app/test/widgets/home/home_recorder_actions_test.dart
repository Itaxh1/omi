import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/home/widgets/home_recorder_actions.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/utils/enums.dart';

class _Capture extends ChangeNotifier implements CaptureProvider {
  bool paused = false;
  bool fail = false;
  int actions = 0;
  @override
  String? get liveCaptureSource => 'phone';
  @override
  RecordingState get recordingState => paused ? RecordingState.pause : RecordingState.record;
  @override
  bool get isPhoneMicPaused => paused;
  @override
  bool get isPaused => paused;
  @override
  bool get isPhoneMicBatchRecording => false;
  @override
  bool get isStopping => false;
  @override
  bool get isCaptureStopped => false;
  @override
  Future<void> pauseCapture() async {
    if (fail) throw StateError('capture unavailable');
    actions++;
    paused = true;
  }

  @override
  Future<void> resumeCapture() async {
    if (fail) throw StateError('capture unavailable');
    actions++;
    paused = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call extends ChangeNotifier implements PhoneCallProvider {
  @override
  PhoneCallState callState = PhoneCallState.idle;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Capture capture;
  late _Call call;
  late BuildContext context;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    capture = _Capture();
    call = _Call();
  });
  tearDown(() {
    capture.dispose();
    call.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CaptureProvider>.value(value: capture),
        ChangeNotifierProvider<PhoneCallProvider>.value(value: call),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: Builder(builder: (value) {
          context = value;
          return const SizedBox.expand();
        })),
      ),
    ));
  }

  Future<void> dismiss(WidgetTester tester) async {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  testWidgets('pause and resume share three hints; later pulls still operate silently', (tester) async {
    await pump(tester);
    for (var i = 0; i < 6; i++) {
      await HomeRecorderActions.act(context);
      await tester.pumpAndSettle();
      if (i < 3) {
        expect(find.text(i.isEven ? 'Paused. Pull down again to undo.' : 'Listening again. Pull down again to undo.'),
            findsOneWidget);
      } else {
        expect(find.byType(SnackBar), findsNothing);
      }
      await dismiss(tester);
    }
    expect(capture.actions, 6);
    expect(capture.paused, isFalse);
  });

  testWidgets('three-display limit survives preferences reload and widget recreation', (tester) async {
    await pump(tester);
    for (var i = 0; i < 3; i++) {
      await HomeRecorderActions.act(context);
      await tester.pumpAndSettle();
      await dismiss(tester);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await SharedPreferencesUtil.reload();
    await SharedPreferencesUtil.init();
    await pump(tester);
    await HomeRecorderActions.act(context);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(capture.actions, 4);
  });

  testWidgets('failed actions keep their error alert and do not spend a teaching hint', (tester) async {
    await pump(tester);
    capture.fail = true;
    await HomeRecorderActions.act(context);
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizations.of(context).somethingWentWrong), findsOneWidget);
    await dismiss(tester);
    capture.fail = false;
    for (var i = 0; i < 3; i++) {
      await HomeRecorderActions.act(context);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await dismiss(tester);
    }
    capture.fail = true;
    await HomeRecorderActions.act(context);
    await tester.pumpAndSettle();
    expect(find.text(AppLocalizations.of(context).somethingWentWrong), findsOneWidget);
  });

  testWidgets('a pull during a phone call neither changes capture nor spends a hint', (tester) async {
    await pump(tester);
    call.callState = PhoneCallState.active;
    await HomeRecorderActions.act(context);
    await tester.pumpAndSettle();
    expect(capture.actions, 0);
    expect(find.byType(SnackBar), findsNothing);
    call.callState = PhoneCallState.idle;
    await HomeRecorderActions.act(context);
    await tester.pumpAndSettle();
    expect(find.text('Paused. Pull down again to undo.'), findsOneWidget);
  });
}
