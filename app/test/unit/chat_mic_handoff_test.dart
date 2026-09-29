import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/chat/chat_mic_handoff.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/voice_recorder_provider.dart';

class _Phone extends CaptureProvider {
  bool paused = false;
  String source = 'phone';
  int pauses = 0;
  int resumes = 0;
  @override
  String? get liveCaptureSource => source;
  @override
  String? get activeCaptureSessionId => 'same-conversation';
  @override
  bool get isPaused => paused;
  @override
  bool get isPhoneMicPaused => paused;
  @override
  Future<void> pauseCapture() async {
    paused = true;
    pauses++;
  }

  @override
  Future<void> resumeCapture() async {
    paused = false;
    resumes++;
  }
}

class _Voice extends VoiceRecorderProvider {
  _Voice(this.phone, {this.refuse = false});
  final _Phone phone;
  final bool refuse;
  bool recording = false;
  @override
  bool get isActive => recording;
  @override
  bool get isRecording => recording;
  @override
  Future<void> startRecording() async {
    expect(phone.paused || phone.source != 'phone', isTrue, reason: 'conversation releases the mic first');
    recording = !refuse;
    notifyListeners();
  }

  void transcribe() {
    recording = false;
    notifyListeners();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test('dictation pauses phone capture and resumes the same conversation when transcribing', () async {
    final phone = _Phone();
    final voice = _Voice(phone);
    await startChatDictation(voice, phone, canStart: () => true);
    expect(phone.pauses, 1);
    expect(phone.resumes, 0);
    voice.transcribe();
    await Future<void>.delayed(Duration.zero);
    expect(phone.resumes, 1);
    voice.transcribe();
    await Future<void>.delayed(Duration.zero);
    expect(phone.resumes, 1);
  });

  test('a denied dictation start resumes the phone', () async {
    final phone = _Phone();
    await startChatDictation(_Voice(phone, refuse: true), phone, canStart: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(phone.resumes, 1);
  });

  test('a source change while dictating wins over automatic resume', () async {
    final phone = _Phone();
    final voice = _Voice(phone);
    await startChatDictation(voice, phone, canStart: () => true);
    phone.source = 'omi';
    voice.transcribe();
    await Future<void>.delayed(Duration.zero);
    expect(phone.resumes, 0);
  });

  test('an already paused phone stays paused after dictation', () async {
    final phone = _Phone()..paused = true;
    final voice = _Voice(phone);
    await startChatDictation(voice, phone, canStart: () => true);
    voice.transcribe();
    await Future<void>.delayed(Duration.zero);
    expect(phone.pauses, 0);
    expect(phone.resumes, 0);
  });
}
