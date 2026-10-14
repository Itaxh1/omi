// Audit reproductions (2026-10-01, main 8c8aff1b39). Each test asserts what
// main does TODAY, so a passing test confirms the bug exists. Local only; not
// for upstream.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/http/api/conversations.dart' show SyncUploadHttpException;
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/services/capture/recording_lifecycle_telemetry.dart';
import 'package:omi/services/wals/local_wal_sync.dart';
import 'package:omi/services/wals/sync_rate_limiter.dart';
import 'package:omi/services/wals/sync_upload_gate.dart';
import 'package:omi/services/wals/wal.dart';
import 'package:omi/services/wals/wal_interfaces.dart';
import 'package:omi/utils/wal_file_manager.dart';

class _Listener implements IWalSyncListener {
  @override
  void onWalUpdated() {}

  @override
  void onWalSynced(Wal wal, {ServerConversation? conversation}) {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    tempDir = await Directory.systemTemp.createTemp('audit_repro_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => call.method == 'getApplicationDocumentsDirectory' ? tempDir.path : null,
    );
    await WalFileManager.init();
    SyncRateLimiter.instance.clear();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    SyncRateLimiter.instance.clear();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('BUG upload loop when no sign-in token is available', () {
    test('every waiting recording is retried on every pass with no limit', () async {
      var uploads = 0;
      final sync = LocalWalSyncImpl(
        _Listener(),
        uploadGate: SyncUploadGate(
          limiter: SyncRateLimiter.instance,
          uploader: (files,
              {onUploadProgress,
              conversationId,
              captureEvidence,
              recordingSessionId,
              audioStartSeconds,
              audioEndSeconds,
              claimLiveCapture = false,
              geolocation}) async {
            uploads++;
            // What shared.dart returns when no token can be obtained: a synthetic 401.
            throw const SyncUploadHttpException(401, 'Upload authentication failed');
          },
          fairUseStatusLoader: () async => {'stage': 'none'},
        ),
      );

      const recordings = 5;
      final wals = <Wal>[];
      for (var i = 0; i < recordings; i++) {
        final name = 'auth_$i.bin';
        await File('${tempDir.path}/$name').writeAsBytes([1, 2, 3, 4]);
        wals.add(Wal(
          timerStart: 20000 + i * 100,
          codec: BleAudioCodec.opus,
          seconds: 60,
          status: WalStatus.miss,
          storage: WalStorage.disk,
          device: 'omi',
          filePath: name,
          recordingSessionId: 'session-$i',
        ));
      }
      sync.testWals = wals;

      await sync.syncAll();
      final firstPass = uploads;
      // Drain until the per-recording budget (walMaxAutoRetries) is spent.
      for (var pass = 0; pass < walMaxAutoRetries + 2; pass++) {
        await sync.syncAll();
      }
      final beforeReconnect = uploads;
      final rearmed = await sync.resetExhaustedAutoRetries(); // what sync_provider.dart:485 calls on reconnect
      await sync.syncAll();
      final afterReconnect = uploads - beforeReconnect;

      // ignore: avoid_print
      print('AUDIT upload loop: first pass=$firstPass, until budget spent=$beforeReconnect, '
          're-armed on reconnect=$rearmed, uploads after one reconnect=$afterReconnect');

      expect(firstPass, recordings, reason: 'one pass does not stop at the first auth failure');
      expect(beforeReconnect, recordings * (walMaxAutoRetries + 3),
          reason: 'auth failures never spend the retry budget: every pass retries every recording');
      expect(wals.every((w) => w.retryCount == 0), isTrue, reason: 'retryCount is never incremented for 401');
      expect(rearmed, 0, reason: 'nothing is ever exhausted, so there is nothing to re-arm');
      expect(afterReconnect, recordings);
      expect(wals.every((w) => w.status == WalStatus.miss), isTrue, reason: 'recordings stay stuck on the phone');
    });
  });

  group('BUG short conversations are never hidden by default', () {
    test('threshold defaults to 0 seconds, so the "hide short" filter removes nothing', () {
      final prefs = SharedPreferencesUtil();
      expect(prefs.showShortConversations, isFalse, reason: 'the filter is on');
      expect(prefs.shortConversationThreshold, 0, reason: 'but its threshold is 0 s');
    });
  });

  group('BUG socket counters in Recording Completed telemetry', () {
    test('a connection observed before the recording ID exists is never counted', () {
      final events = <String, Map<String, dynamic>>{};
      final telemetry = RecordingLifecycleTelemetry(
        emitter: (name, props) => events[name] = props,
        identityEpoch: () => 1,
      );
      telemetry.observeConnected(); // socket connected first
      telemetry.prepare(source: 'pendant_live');
      telemetry.markStarted();
      telemetry.complete();
      expect(events[RecordingLifecycleTelemetry.completedEvent]?['socket_connection_count'], 0);
    });
  });
}
