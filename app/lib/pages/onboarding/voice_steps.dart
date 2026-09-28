import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/pages/onboarding/guided_voice_controller.dart';
import 'package:omi/pages/onboarding/guided_voice_io.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';

/// "Teach Omi your voice" (v3 `voice`): the waveform in its ring, why, then Start or "Do this
/// later".
class OnboardingVoiceIntroStep extends StatelessWidget {
  const OnboardingVoiceIntroStep({super.key, required this.onStart, required this.onLater});

  final VoidCallback onStart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          const SizedBox(height: 26),
          const OnboardingIconRing(glyph: OmiGlyphs.waveform),
          const SizedBox(height: 30),
          OnboardingHeader(title: l10n.teachOmiYourVoice, subtitle: l10n.teachVoiceBody),
        ],
        footer: [
          OmiButton(
            key: const Key('speech_profile_start'),
            label: l10n.start,
            expand: true,
            onPressed: () {
              OmiHaptics.selection();
              onStart();
            },
          ),
          OnboardingLink(key: const Key('onboarding_voice_later'), label: l10n.doThisLater, onTap: onLater),
        ],
      ),
    );
  }
}

/// "Read this out loud" (v3 `read`): three short lines, one at a time, with a bar for each and
/// "Listening" under them. A line is done once the reader has spoken for a moment and paused (or
/// after [lineCap] with some speech); after the third, the flow moves on and the recording is
/// saved as the reader's voice in the background ([onEnrolled] reports how that went).
class OnboardingVoiceReadStep extends StatefulWidget {
  const OnboardingVoiceReadStep({
    super.key,
    required this.onDone,
    this.onEnrolled,
    this.io,
    this.lineCap = const Duration(seconds: 9),
  });

  /// Called after the third line, and on Skip.
  final VoidCallback onDone;

  /// Whether the voice was saved; called after [onDone], once the upload finishes.
  final ValueChanged<bool>? onEnrolled;

  /// The microphone and the upload; tests pass a fake.
  final GuidedVoiceIO? io;
  final Duration lineCap;

  @override
  State<OnboardingVoiceReadStep> createState() => _OnboardingVoiceReadStepState();
}

class _OnboardingVoiceReadStepState extends State<OnboardingVoiceReadStep> {
  late final GuidedVoiceIO _io = widget.io ?? DeviceGuidedVoiceIO();
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  Future<void> Function()? _resumeCapture;
  int _line = 0;
  double _lineMs = 0;
  double _voicedMs = 0;
  double _silentMs = 0;
  bool _ended = false;

  /// The upload needs at least five seconds of speech (16 kHz, 16-bit mono: 32 000 bytes a second).
  static const int _minBytes = 5 * 32000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_begin()));
  }

  Future<void> _begin() async {
    try {
      // The pendant would record the reading as a conversation: it rests while the phone listens.
      if (widget.io == null) {
        final capture = context.read<CaptureProvider>();
        if (capture.recordingState == RecordingState.deviceRecord) {
          final device = capture.recordingDevice;
          _resumeCapture = () => capture.streamDeviceRecording(device: device);
          await capture.stopStreamDeviceRecording();
        }
      }
      await _io.prepare();
      if (_ended) return;
      await _io.start(_onAudio, () {});
    } catch (e) {
      Logger.debug('Onboarding voice reading did not start: $e');
      if (mounted && !_ended) OmiFeedback.error(context, context.l10n.voiceNotSavedV3);
      _leave(save: false);
    }
  }

  void _onAudio(Uint8List bytes) {
    if (_ended || bytes.length < 2) return;
    _pcm.add(bytes);
    final ms = bytes.length / 32;
    final data = ByteData.sublistView(bytes);
    double sum = 0;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little);
      sum += sample * sample;
    }
    final rms = math.sqrt(sum / (bytes.length ~/ 2));
    _lineMs += ms;
    if (rms > 220) {
      _voicedMs += ms;
      _silentMs = 0;
    } else if (_voicedMs > 0) {
      _silentMs += ms;
    }
    final spoke = _voicedMs >= 1200 && _silentMs >= 700;
    final capped = _lineMs >= widget.lineCap.inMilliseconds && _voicedMs >= 400;
    if (!spoke && !capped) return;
    if (_line < 2) {
      _lineMs = _voicedMs = _silentMs = 0;
      OmiHaptics.light();
      if (mounted) setState(() => _line++);
    } else {
      _leave(save: true);
    }
  }

  void _leave({required bool save}) {
    if (_ended) return;
    _ended = true;
    final audio = _pcm.takeBytes();
    final resume = _resumeCapture;
    final onEnrolled = widget.onEnrolled;
    unawaited(() async {
      try {
        await _io.stop();
        if (save && audio.length >= _minBytes) {
          var saved = false;
          try {
            saved = await _io.enroll(Uint8List.sublistView(audio, 0, math.min(audio.length, 180 * 32000)));
          } catch (e) {
            Logger.debug('Onboarding voice upload failed: $e');
          }
          onEnrolled?.call(saved);
        } else if (save) {
          onEnrolled?.call(false);
        }
      } finally {
        await _io.close();
        if (resume != null) {
          try {
            await resume();
          } catch (e) {
            Logger.debug('Onboarding voice: the pendant did not resume: $e');
          }
        }
      }
    }());
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    // Back (or anything else) that leaves mid-reading stops the microphone and saves nothing.
    if (!_ended) {
      _ended = true;
      final resume = _resumeCapture;
      unawaited(() async {
        await _io.stop();
        await _io.close();
        if (resume != null) await resume().then((_) {}, onError: (_) {});
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lines = [l10n.voiceLineOne, l10n.voiceLineTwo, l10n.voiceLineThree];
    final reduced = OmiMotion.of(context).standard == Duration.zero;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          OnboardingKicker(l10n.readThisOutLoud),
          const SizedBox(height: 22),
          // `.obread`: the line at 28/600, rising in as each one comes up.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: AnimatedSwitcher(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 450),
              switchInCurve: const Cubic(0.2, 0.8, 0.2, 1),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous.map((p) => Offstage(child: p)), if (current != null) current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) =>
                      Transform.translate(offset: Offset(0, 10 * (1 - animation.value)), child: child),
                ),
              ),
              child: Semantics(
                key: ValueKey(_line),
                liveRegion: true,
                child: Text(
                  lines[_line],
                  key: const Key('onboarding_read_line'),
                  style: OmiType.title1.copyWith(fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.56),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // `.obdots`: a 22 pt bar per line, the read ones in ink.
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: OmiMotion.of(context).standard,
                    width: 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= _line ? OmiColors.textPrimary : OmiColors.outline,
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          OnboardingListeningRow(label: l10n.listening),
        ],
        footer: [
          OnboardingLink(
            key: const Key('speech_profile_skip_intro'),
            label: l10n.skip,
            onTap: () => _leave(save: false),
          ),
        ],
      ),
    );
  }
}
