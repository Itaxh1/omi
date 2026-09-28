import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:provider/provider.dart';

import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/home/widgets/home_pull.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Home's top bar (v3 `.top`): 16 pt under the status bar, a 56 pt row on the page, no logo. A
/// plain-glass folder button on the left (Folders), the Listening label centred, and the reader's
/// initial on the right (You). Both circles are 50 pt and sit on the 22 pt gutter.
class HomeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeTopBar({
    super.key,
    required this.onOpenOmi,
    required this.onFolders,
    required this.onYou,
    this.pull,
    this.onPullAction,
    this.pulse,
  });

  /// The first-run ring around the mark ([HomeTeachRing]).
  final ValueListenable<int>? pulse;

  /// The Listening label opens Your Omi.
  final VoidCallback onOpenOmi;
  final VoidCallback onFolders;
  final VoidCallback onYou;

  /// How far a pull down on Home has gone; the label says what letting go will do.
  final ValueListenable<HomePullPhase>? pull;

  /// What a pull down does, offered to screen readers on the label.
  final VoidCallback? onPullAction;

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
              Expanded(
                child: Center(
                  child: HomeListeningLabel(onOpen: onOpenOmi, pull: pull, onPullAction: onPullAction, pulse: pulse),
                ),
              ),
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

/// The listening strip's three states on inner screens (unchanged in v8): capturing, muted by the
/// reader, or nothing listening.
enum ListeningLabelState { listening, muted, idle }

/// A pull on Home: not pulling, pulling but not far enough, far enough to act on release.
enum HomePullPhase { none, pulling, ready }

/// What Omi is doing, as the Listening label and Your Omi say it (v8.1).
enum HomeRecorderState {
  /// Audio is being captured.
  listening,

  /// The reader paused (muted) the capture.
  paused,

  /// Nothing is listening.
  off,

  /// A paired pendant, and Bluetooth is off.
  bluetoothOff,

  /// A paired pendant that is neither connected nor being reached.
  notFound,

  /// The pendant dropped and is being reached again.
  reconnecting,
}

/// The Listening label (v8.1): the Omi mark (36 pt) beside what Omi is doing and, under it, what to
/// do about it: Listening; Paused, "Pull down to resume"; Off, "Pull down to start"; Bluetooth off,
/// "Tap to fix"; Omi not found, "Tap for options"; Reconnecting, "Omi keeps recording". While the
/// page is pulled down it says "Pull to pause" and, once far enough, "Release to pause" with the
/// mark a little bigger. Tapping it opens Your Omi. A small red dot on the mark flags a problem.
class HomeListeningLabel extends StatelessWidget {
  const HomeListeningLabel({super.key, required this.onOpen, this.pull, this.onPullAction, this.pulse});

  final VoidCallback onOpen;
  final ValueListenable<HomePullPhase>? pull;
  final VoidCallback? onPullAction;

  /// Plays the teaching ring around the mark.
  final ValueListenable<int>? pulse;

  static const double markSize = 36;

  /// The strip's state from the capture and call providers, with the capture card's test.
  static ListeningLabelState simpleStateOf(CaptureProvider capture, PhoneCallState call) {
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

  /// Something Your Omi explains: transcription is down for good, or the OS holds the mic.
  static bool hasProblem(CaptureProvider capture) =>
      capture.terminalTranscriptionFailure != null ||
      capture.isCallActive ||
      capture.recordingState == RecordingState.interrupted;

  /// The phone is the one capturing (a pendant problem then doesn't stop anything).
  static bool _phoneCapturing(CaptureProvider capture) =>
      capture.liveCaptureSource == 'phone' ||
      capture.recordingState == RecordingState.record ||
      capture.recordingState == RecordingState.initialising ||
      capture.isPhoneMicPaused ||
      capture.isPhoneMicBatchRecording;

  /// The state from the call, capture, device and Bluetooth, in the order the design ranks them.
  static HomeRecorderState stateOf({
    required PhoneCallState call,
    required CaptureProvider capture,
    required bool paired,
    required bool connected,
    required bool connecting,
    required bool bluetoothOff,
  }) {
    final onCall = call == PhoneCallState.active || call == PhoneCallState.connecting || call == PhoneCallState.ringing;
    if (onCall) return HomeRecorderState.listening;
    final phone = _phoneCapturing(capture);
    if (paired && bluetoothOff && !phone) return HomeRecorderState.bluetoothOff;
    if (paired && connecting && !connected && !phone) return HomeRecorderState.reconnecting;
    if (IdleCaptureCard.isCapturing(capture)) {
      return isMuted(capture) ? HomeRecorderState.paused : HomeRecorderState.listening;
    }
    if (paired && !connected) return HomeRecorderState.notFound;
    return HomeRecorderState.off;
  }

  /// [stateOf] read from the providers under [context], rebuilding when any of them changes.
  static HomeRecorderState watch(BuildContext context) {
    final call = context.select<PhoneCallProvider, PhoneCallState>((p) => p.callState);
    final (paired, connected, connecting) = context.select<DeviceProvider?, (bool, bool, bool)>((d) {
      final hasPaired = (d?.pairedDevice?.id ?? '').isNotEmpty;
      return (hasPaired, d?.isConnected ?? false, d?.isConnecting ?? false);
    });
    final bluetoothOff = BluetoothReadiness.instance.state == BluetoothAdapterState.off;
    return context.select<CaptureProvider, HomeRecorderState>((c) => stateOf(
          call: call,
          capture: c,
          paired: paired,
          connected: connected,
          connecting: connecting,
          bluetoothOff: bluetoothOff,
        ));
  }

  /// The label's two lines: what Omi is doing, and what to do about it.
  static (String, String?) wordsFor(AppLocalizations l10n, HomeRecorderState state) => switch (state) {
        HomeRecorderState.listening => (l10n.listening, null),
        HomeRecorderState.paused => (l10n.paused, l10n.pullDownToResume),
        HomeRecorderState.off => (l10n.off, l10n.pullDownToStart),
        HomeRecorderState.bluetoothOff => (l10n.bluetoothOffV3, l10n.tapToFix),
        HomeRecorderState.notFound => (l10n.omiNotFound, l10n.tapForOptions),
        HomeRecorderState.reconnecting => (l10n.reconnectingV3, l10n.omiKeepsRecording),
      };

  /// What pulling Home down says: pause while listening, resume while paused, otherwise record.
  static String pullWords(AppLocalizations l10n, HomeRecorderState state, {required bool ready}) =>
      switch (state) {
        HomeRecorderState.listening => ready ? l10n.releaseToPause : l10n.pullToPause,
        HomeRecorderState.paused => ready ? l10n.releaseToResume : l10n.pullToResume,
        _ => ready ? l10n.releaseToRecord : l10n.pullToRecord,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Bluetooth switching off (with a pendant paired) changes the label at once.
      listenable: BluetoothReadiness.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final state = watch(context);
    final captureProblem = context.select<CaptureProvider, bool>(hasProblem);
    final syncing = context.select<SyncProvider?, bool>((s) => s?.isSyncing ?? false);
    final alert = captureProblem ||
        state == HomeRecorderState.bluetoothOff ||
        state == HomeRecorderState.notFound ||
        state == HomeRecorderState.reconnecting;
    // `.rng.syn` / `.rng.wait`: the mark turns slowly while recordings come off the pendant and
    // quickly, dimmed, while it reconnects.
    final turn = state == HomeRecorderState.reconnecting
        ? OmiRingTurn.reconnect
        : syncing
            ? OmiRingTurn.sync
            : OmiRingTurn.none;
    final (title, hint) = wordsFor(l10n, state);
    final markColor = state == HomeRecorderState.off ? OmiColors.textTertiary : OmiColors.textPrimary;
    final phases = pull ?? const _NoPull();
    return ValueListenableBuilder<HomePullPhase>(
      valueListenable: phases,
      builder: (context, phase, _) {
        final pulling = phase != HomePullPhase.none;
        final ready = phase == HomePullPhase.ready;
        final bigTitle = pulling ? pullWords(l10n, state, ready: ready) : title;
        final small = pulling ? null : hint;
        final titleStyle = OmiType.lead.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: pulling && !ready ? OmiColors.textSecondary : OmiColors.textPrimary,
        );
        return Semantics(
          button: true,
          label: hint == null ? title : '$title, $hint',
          hint: l10n.yourOmi,
          excludeSemantics: true,
          onTap: onOpen,
          customSemanticsActions: onPullAction == null
              ? null
              : {
                  CustomSemanticsAction(
                    label: switch (state) {
                      HomeRecorderState.listening => l10n.pause,
                      HomeRecorderState.paused => l10n.resume,
                      _ => l10n.start,
                    },
                  ): onPullAction!,
                },
          child: OmiPressable(
            key: const Key('home_listening_label'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              OmiHaptics.selection();
              onOpen();
            },
            // `.rbtn`: 54 pt tall, 12 pt in from each side.
            child: SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: ready ? 1.2 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: markSize,
                        height: markSize,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (pulse != null)
                              Positioned(
                                left: -5,
                                top: -5,
                                child: HomeTeachRing(trigger: pulse!, size: markSize + 10),
                              ),
                            OmiRingLogo(
                              key: const Key('home_listening_mark'),
                              size: markSize,
                              color: markColor,
                              mode: state == HomeRecorderState.listening ? OmiRingMode.wave : OmiRingMode.still,
                              turn: turn,
                            ),
                            if (alert)
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
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bigTitle,
                            key: const Key('home_listening_word'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          if (small != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                small,
                                key: const Key('home_listening_hint'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OmiType.fine.copyWith(
                                  fontWeight: FontWeight.w500,
                                  height: 1.1,
                                  color: OmiColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// No pull in progress (the label outside Home).
class _NoPull extends ValueListenable<HomePullPhase> {
  const _NoPull();

  @override
  HomePullPhase get value => HomePullPhase.none;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
