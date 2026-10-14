// Transcription audit reproductions (2026-10-01, main 44606772ef). Each test
// asserts what main does TODAY, so a passing test confirms the bug exists.
// Local only; not for upstream.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/models/stt_response_schema.dart';
import 'package:omi/models/stt_result.dart';
import 'package:omi/services/sockets/composite_transcription_socket.dart';
import 'package:omi/services/sockets/on_device_whisper_provider.dart';
import 'package:omi/services/sockets/pure_polling.dart';
import 'package:omi/services/sockets/pure_socket.dart';
import 'package:omi/services/sockets/transcription_polling_service.dart';

/// Stands in for the Omi backend socket the composite forwards text to.
class _BackendSocket implements IPureSocket {
  final sent = <dynamic>[];
  PureSocketStatus _status = PureSocketStatus.notConnected;

  @override
  PureSocketStatus get status => _status;
  @override
  Future<bool> connect() async {
    _status = PureSocketStatus.connected;
    return true;
  }

  @override
  Future disconnect() async => _status = PureSocketStatus.disconnected;
  @override
  Future stop() async => _status = PureSocketStatus.disconnected;
  @override
  void send(dynamic message) => sent.add(message);
  @override
  void setListener(IPureSocketListener listener) {}
  @override
  void onMessage(dynamic message) {}
  @override
  void onConnected() {}
  @override
  void onClosed() {}
  @override
  void onError(Object err, StackTrace trace) {}

  List<String> get forwardedText => [
        for (final m in sent)
          if (m is String && m.contains('suggested_transcript'))
            for (final s in (jsonDecode(m)['segments'] as List)) s['text'] as String,
      ];
}

class _Listener implements IPureSocketListener {
  final messages = <dynamic>[];
  @override
  void onConnected() {}
  @override
  void onMessage(dynamic message) => messages.add(message);
  @override
  void onClosed([int? closeCode]) {}
  @override
  void onError(Object err, StackTrace trace) {}
}

/// Returns scripted results, one per transcribe() call, like an on-device or
/// cloud recognizer would for consecutive 5-second chunks.
class _ScriptedStt implements ISttProvider {
  final List<SttTranscriptionResult? Function(double offset)> script;
  var calls = 0;
  _ScriptedStt(this.script);

  @override
  Future<SttTranscriptionResult?> transcribe(Uint8List audioData, {double audioOffsetSeconds = 0}) async =>
      script[calls++](audioOffsetSeconds);

  @override
  void dispose() {}
}

AudioPollingConfig _manualFlush() =>
    const AudioPollingConfig(bufferDuration: Duration(hours: 1), minBufferSizeBytes: 1);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  group('BUG last words lost when a custom / on-device recording stops', () {
    test('text recognized during stop() never reaches the backend', () async {
      final stt = _ScriptedStt([
        (o) => SttTranscriptionResult(segments: [SttSegment(text: 'first sentence', start: o, end: o + 5)]),
        (o) => SttTranscriptionResult(segments: [SttSegment(text: 'last words', start: o, end: o + 3)]),
      ]);
      final primary = PurePollingSocket(config: _manualFlush(), sttProvider: stt);
      final backend = _BackendSocket();
      final composite = CompositeTranscriptionSocket(primarySocket: primary, secondarySocket: backend);
      composite.setListener(_Listener());

      await composite.connect();
      composite.send(Uint8List(160));
      await primary.flushNow(); // a normal mid-recording flush
      composite.send(Uint8List(160)); // the user's last sentence, still buffered
      await composite.stop(); // user taps stop

      // ignore: avoid_print
      print('AUDIT stop: recognized ${stt.calls} chunks, backend got ${backend.forwardedText}');
      expect(stt.calls, 2, reason: 'stop() does transcribe the buffered tail');
      expect(backend.forwardedText, ['first sentence'], reason: 'but the tail is dropped: composite is already "disconnected"');
    });
  });

  group('BUG on-device / cloud polling timestamps drift earlier', () {
    test('silence and trailing pauses are cut out of the timeline', () async {
      // Three 5 s chunks: speech ending at 2 s, a silent chunk, then speech 0.5 s in.
      final stt = _ScriptedStt([
        (o) => SttTranscriptionResult(segments: [SttSegment(text: 'hello', start: o + 0.5, end: o + 2.0)]),
        (o) => null,
        (o) => SttTranscriptionResult(segments: [SttSegment(text: 'again', start: o + 0.5, end: o + 1.5)]),
      ]);
      final socket = PurePollingSocket(config: _manualFlush(), sttProvider: stt);
      final listener = _Listener();
      socket.setListener(listener);
      await socket.connect();
      for (var chunk = 0; chunk < 3; chunk++) {
        socket.send(Uint8List(160)); // 5 s of audio each
        await socket.flushNow();
      }
      await socket.stop();

      final segments = [for (final m in listener.messages) ...(jsonDecode(m as String) as List)];
      final again = segments.firstWhere((s) => s['text'] == 'again');
      // ignore: avoid_print
      print('AUDIT drift: "again" spoken at 10.5 s, stamped at ${again['start']} s');
      expect(again['start'], 2.5, reason: 'real position is 10.5 s; 8 s of timeline vanished in 3 chunks');
    });
  });

  group('BUG transcription errors silently discard audio', () {
    test('a cloud STT HTTP error (bad key, rate limit) drops the chunk instead of buffering it', () async {
      final provider = SchemaBasedSttProvider(
        apiUrl: 'https://stt.example/transcribe',
        schema: SttResponseSchema.openAI,
        requestBodyType: SttRequestBodyType.rawBinary,
        client: MockClient((_) async => http.Response('{"error":"invalid api key"}', 401)),
      );
      final socket = PurePollingSocket(config: _manualFlush(), sttProvider: provider);
      socket.setListener(_Listener());
      await socket.connect();
      socket.send(Uint8List(32000)); // 1 s of speech
      await socket.flushNow();

      // ignore: avoid_print
      print('AUDIT http 401: buffered=${socket.bufferedBytes} bytes, isBuffering=${socket.isBuffering}');
      expect(socket.bufferedBytes, 0, reason: 'audio is gone');
      expect(socket.isBuffering, isFalse, reason: 'and the UI is never told transcription is failing');
      await socket.stop();
    });

    test('an Android Whisper failure (missing model) drops every chunk the same way', () async {
      final provider = OnDeviceWhisperProvider(modelPath: '/nonexistent/ggml-base.bin');
      final socket = PurePollingSocket(config: _manualFlush(), sttProvider: provider);
      socket.setListener(_Listener());
      await socket.connect();
      socket.send(Uint8List(32000));
      await socket.flushNow();

      expect(socket.bufferedBytes, 0);
      expect(socket.isBuffering, isFalse);
      await socket.stop();
    });
  });
}
