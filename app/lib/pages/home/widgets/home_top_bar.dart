import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Home's top bar (v3 `.top`): 16 pt under the status bar, a 56 pt row on the page, no logo. A
/// plain-glass folder button on the left (Folders), the Listening label centred, and the reader's
/// initial on the right (You). Both circles are 50 pt and sit on the 22 pt gutter.
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeTopBar({super.key, required this.recorderOpen, required this.onFolders, required this.onYou});

  /// Whether the recorder card is up; the Listening label toggles it.
  final ValueNotifier<bool> recorderOpen;
  final VoidCallback onFolders;
  final VoidCallback onYou;

  static const double gap = 16;
  static const double row = 56;
  static const double buttonSize = 50;

  @override
  Size get preferredSize => const Size.fromHeight(gap + row);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = SharedPreferencesUtil().givenName.trim();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, gap, OmiSize.screenMargin, 0),
        child: SizedBox(
          height: row,
          child: Row(
            children: [
              OmiPlainGlassButton(
                key: const Key('home_folders_button'),
                label: l10n.conversations,
                onPressed: onFolders,
                child: OmiGlyph(OmiGlyphs.folder, size: 23, color: OmiColors.textPrimary),
              ),
              Expanded(child: Center(child: HomeListeningLabel(recorderOpen: recorderOpen))),
              OmiPlainGlassButton(
                key: const Key('home_you_button'),
                label: l10n.you,
                onPressed: onYou,
                child: name.isEmpty
                    ? OmiGlyph(OmiGlyphs.person, size: 21, color: OmiColors.textPrimary)
                    : Text(
                        name.characters.first.toUpperCase(),
                        style: OmiType.lead.copyWith(fontWeight: FontWeight.w700, height: 1),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the Listening label shows.
enum ListeningLabelState {
  /// Audio is being captured: the mark waves, the word Listening beside it.
  listening,

  /// The reader muted the capture: the dots stay, the word goes (the design's Paused).
  muted,

  /// Nothing is listening: the dots, dimmed, and Start.
  idle,
}

/// The Listening label (v3): the Omi mark visualiser (36 pt) and "Listening" at 18/600 while audio
/// is captured; only the dots while muted; the dimmed dots and Start while nothing listens.
/// Tapping it toggles the recorder card. A small red dot on the mark flags a problem the card
/// explains (transcription down, the microphone held by a call).
class HomeListeningLabel extends StatelessWidget {
  const HomeListeningLabel({super.key, required this.recorderOpen});

  final ValueNotifier<bool> recorderOpen;

  static const double markSize = 36;

  /// The label's state from the capture and call providers, with the same "is anything capturing"
  /// test the capture card uses.
  static ListeningLabelState stateOf(CaptureProvider capture, PhoneCallState call) {
    final onCall = call == PhoneCallState.active || call == PhoneCallState.connecting || call == PhoneCallState.ringing;
    if (onCall) return ListeningLabelState.listening;
    if (!IdleCaptureCard.isCapturing(capture)) return ListeningLabelState.idle;
    return isMuted(capture) ? ListeningLabelState.muted : ListeningLabelState.listening;
  }

  /// The capture card's Muted: a device capture paused by the reader, or the phone's mic muted.
  static bool isMuted(CaptureProvider capture) {
    final source = capture.liveCaptureSource;
    if (source != null && source != 'phone') {
      return (capture.isPaused && capture.recordingState == RecordingState.pause) ||
          (SharedPreferencesUtil().batchModeEnabled && capture.offlineMuted);
    }
    return capture.isPhoneMicPaused || capture.isPaused || (capture.isPhoneMicBatchRecording && capture.offlineMuted);
  }

  /// Something the recorder card explains: transcription is down for good, or the OS holds the mic.
  static bool hasProblem(CaptureProvider capture) =>
      capture.terminalTranscriptionFailure != null ||
      capture.isCallActive ||
      capture.recordingState == RecordingState.interrupted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final call = context.select<PhoneCallProvider, PhoneCallState>((p) => p.callState);
    final (state, problem) = context.select<CaptureProvider, (ListeningLabelState, bool)>(
      (c) => (stateOf(c, call), hasProblem(c)),
    );
    final word = switch (state) {
      ListeningLabelState.listening => l10n.listening,
      ListeningLabelState.muted => null,
      ListeningLabelState.idle => l10n.start,
    };
    final name = switch (state) {
      ListeningLabelState.listening => l10n.listening,
      ListeningLabelState.muted => l10n.muted,
      ListeningLabelState.idle => l10n.notListeningTitle,
    };
    final markColor = state == ListeningLabelState.idle ? OmiColors.textTertiary : OmiColors.textPrimary;
    return ValueListenableBuilder<bool>(
      valueListenable: recorderOpen,
      builder: (context, open, _) => Semantics(
        button: true,
        toggled: open,
        label: name,
        excludeSemantics: true,
        onTap: () => recorderOpen.value = !open,
        child: OmiPressable(
          key: const Key('home_listening_label'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            OmiHaptics.selection();
            recorderOpen.value = !open;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmiSpacing.sm, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: markSize,
                  height: markSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      OmiRingLogo(
                        size: markSize,
                        color: markColor,
                        mode: state == ListeningLabelState.listening ? OmiRingMode.wave : OmiRingMode.still,
                      ),
                      if (problem)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: Container(
                            key: const Key('home_listening_alert'),
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: OmiColors.danger,
                              shape: BoxShape.circle,
                              border: Border.all(color: OmiColors.surface0, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (word != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    word,
                    key: const Key('home_listening_word'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OmiType.lead.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
