import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/services/bridges/android_live_update_bridge.dart';

/// On an Android device or emulator: a live recording shows as a Live Update (the promoted ongoing
/// notification, with its status bar chip on Android 16), and its Stop button comes back to the
/// capture owner. The host drives the notification with adb while this waits:
///
///   flutter test -d emulator-5554 --flavor dev integration_test/android_live_update_test.dart
///   # when "LIVE_UPDATE_POSTED" prints: expand the shade and tap Stop (see the session notes)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a recording is a Live Update, and Stop on it reaches the recording', (tester) async {
    if (!Platform.isAndroid) return;
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    final bridge = AndroidLiveUpdateBridge(l10n: () => lookupAppLocalizations(const Locale('en')));
    final tapped = Completer<Map<String, Object?>>();
    await bridge.start((request) async {
      if (!tapped.isCompleted) tapped.complete(request);
      return {};
    });
    final started = DateTime.now().subtract(const Duration(minutes: 2, seconds: 5));
    await bridge.publish({
      'recordingId': 'emulator-check',
      'conversationRevision': 1,
      'active': true,
      'status': 'listening',
      'source': 'phone',
      'batch': false,
      'startedAt': started.millisecondsSinceEpoch / 1000,
      'elapsed': 125,
      'paused': false,
      'canPause': true,
      'canFinish': true,
      'busy': false,
      'actionFailed': false,
      'metered': false,
      'voice': false,
      'levels': const <int>[],
      'levelsEnd': 0,
    });
    // ignore: avoid_print
    print('LIVE_UPDATE_POSTED');

    final request = await tapped.future.timeout(const Duration(seconds: 120));
    expect(request['action'], 'finish');
    expect(request['recordingId'], 'emulator-check');
    expect(request['conversationRevision'], 1);
    await bridge.close();
  });
}
