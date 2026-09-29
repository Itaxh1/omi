import 'dart:async';

import 'package:omi/backend/preferences.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/voice_recorder_provider.dart';
import 'package:omi/utils/logger.dart';

/// Dictation borrows the phone microphone without ending its conversation. The
/// coordinator releases it on pause; MicArbiter still enforces exclusive access.
Future<void> startChatDictation(
  VoiceRecorderProvider voice,
  CaptureProvider? capture, {
  required bool Function() canStart,
}) async {
  if (voice.isActive || !canStart()) return;
  final borrowPhone = capture != null && capture.liveCaptureSource == 'phone' && !capture.isPaused;
  if (!borrowPhone) {
    await voice.startRecording();
    return;
  }

  final session = capture.activeCaptureSessionId;
  await capture.pauseCapture();
  final revision = SharedPreferencesUtil().capturePolicy.revision;
  if (!capture.isPhoneMicPaused) throw StateError('Conversation microphone did not pause');

  Future<void> restore() async {
    // A user stop, source change, new session or another mute decision wins.
    if (capture.liveCaptureSource != 'phone' ||
        !capture.isPhoneMicPaused ||
        capture.activeCaptureSessionId != session ||
        SharedPreferencesUtil().capturePolicy.revision != revision) {
      return;
    }
    try {
      await capture.resumeCapture();
    } catch (error) {
      Logger.warning('Could not resume phone capture after chat dictation: $error');
    }
  }

  if (!canStart()) {
    await restore();
    return;
  }

  var released = false;
  void changed() {
    if (voice.isRecording || released) return;
    released = true;
    voice.removeListener(changed);
    // processRecording announces transcribing before synchronously stopping the
    // mic. Resume on the next microtask, after that stop releases the arbiter.
    scheduleMicrotask(() => unawaited(restore()));
  }

  voice.addListener(changed);
  try {
    await voice.startRecording();
  } catch (_) {
    voice.removeListener(changed);
    if (!released) await restore();
    rethrow;
  } finally {
    changed();
  }
}
