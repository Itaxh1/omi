import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/services/bridges/android_live_update_bridge.dart';

/// Android's Live Update gets the same capture snapshots as the iOS Live Activity, with its words
/// in the app's language, and sends Pause, Resume and Stop back to the capture owner.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AndroidLiveUpdateBridge.channelName);
  final calls = <MethodCall>[];
  final en = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('publishes the snapshot with its words, and only its current owner answers the buttons', () async {
    final old = AndroidLiveUpdateBridge(l10n: () => en);
    final bridge = AndroidLiveUpdateBridge(l10n: () => en);
    var oldActions = 0;
    final actions = <Map<String, Object?>>[];
    await old.start((_) async {
      oldActions++;
      return {};
    });
    await bridge.start((request) async {
      actions.add(request);
      return {'handled': true};
    });
    final owner = calls.last.arguments;
    await old.close();
    expect(calls.where((call) => call.method == 'detach'), isEmpty, reason: 'an old owner leaves the new one alone');

    await bridge.publish({
      'recordingId': 'r1',
      'status': 'listening',
      'source': 'pendant',
      'levels': [40, 50],
    });
    final published = calls.last.arguments as Map;
    expect(calls.last.method, 'publish');
    expect(published['ownerId'], owner);
    expect(published['enabled'], isTrue);
    expect(published['levels'], isEmpty, reason: 'the notification keeps its own clock; it draws no strip');
    expect(published['labels'], {
      'title': 'Listening',
      'text': 'Omi',
      'pause': 'Pause',
      'resume': 'Resume',
      'stop': 'Stop',
      'chip': null,
      'channel': 'Your Omi',
    });

    final reply = Completer<ByteData?>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
          const MethodCall('action', {'action': 'finish', 'recordingId': 'r1', 'conversationRevision': 3})),
      reply.complete,
    );
    expect(const StandardMethodCodec().decodeEnvelope((await reply.future)!), {'handled': true});
    expect(oldActions, 0);
    expect(actions.single, {'action': 'finish', 'recordingId': 'r1', 'conversationRevision': 3});

    await SharedPreferencesUtil().setShowCaptureLiveActivity(false);
    await bridge.publish({'recordingId': 'r1', 'status': 'listening', 'source': 'phone'});
    expect((calls.last.arguments as Map)['enabled'], isFalse, reason: 'the same setting as the Live Activity');

    await bridge.close();
    expect(calls.last.method, 'detach');
    expect(calls.last.arguments, owner);
  });

  test('a paused recording says Paused, and the status bar chip says it too', () {
    final paused = AndroidLiveUpdateBridge.labels({'status': 'paused', 'source': 'phone'}, en);
    expect(paused['title'], 'Paused');
    expect(paused['text'], 'This phone');
    expect(paused['chip'], 'Paused');
    expect(AndroidLiveUpdateBridge.labels({'status': 'reconnecting', 'source': 'pendant'}, en)['title'],
        en.reconnecting);
    expect(AndroidLiveUpdateBridge.labels({'status': 'recording', 'source': 'pendant'}, en)['title'], en.recordingNow);
    expect(AndroidLiveUpdateBridge.labels({'status': 'listening', 'source': 'pendant'}, en)['chip'], isNull,
        reason: 'while it records the chip shows the clock');
  });
}
