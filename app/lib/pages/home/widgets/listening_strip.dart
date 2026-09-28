import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/devices/devices_screen.dart';
import 'package:omi/pages/home/your_omi_page.dart';
import 'package:omi/pages/home/widgets/phone_capture.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/widgets/capture_sources.dart';

/// The listening strip (v3 §4.3) at the bottom of every pushed screen, in place of Home's label:
/// `● Listening · syncing 12 min ▮▮▯ ⌃` on near-black. Tapping it opens a black panel above it with
/// the pause button, "Recording from …" and Change, and the sync line while recordings come off
/// the pendant. Use it as a screen's `bottomNavigationBar`.
class ListeningStrip extends StatelessWidget {
  const ListeningStrip({super.key});

  /// The strip's own height, above the home indicator.
  static const double height = 46;

  /// Whether the capture providers the strip reads are above [context]. The app always has them;
  /// hermetic fixtures embed a page without them, and the page then shows no strip (the same idiom
  /// as device settings and the pending-transcriptions banner).
  static bool _available(BuildContext context) {
    try {
      Provider.of<CaptureProvider>(context, listen: false);
      Provider.of<DeviceProvider>(context, listen: false);
      Provider.of<SyncProvider>(context, listen: false);
      Provider.of<PhoneCallProvider>(context, listen: false);
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => _available(context) ? const _Strip() : const SizedBox.shrink();
}

class _Strip extends StatefulWidget {
  const _Strip();

  @override
  State<_Strip> createState() => _ListeningStripState();
}

class _ListeningStripState extends State<_Strip> {
  bool _open = false;

  /// `#111` in White, `#1F1F21` in Black; the panel is black.
  static const Color _stripWhite = Color(0xFF111111); // omi-ux-allow: color-literal -- the design's strip in White
  static const Color _stripBlack = Color(0xFF1F1F21); // omi-ux-allow: color-literal -- the design's strip in Black
  static Color get _stripColor => OmiColors.isLight ? _stripWhite : _stripBlack;
  static const Color _panelColor = Color(0xFF000000); // omi-ux-allow: color-literal -- the design's panel
  static const Color _white = Color(0xFFFFFFFF); // omi-ux-allow: color-literal -- words on the strip
  static const Color _dim = Color(0xA8FFFFFF); // omi-ux-allow: color-literal -- the strip's 66 % white

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final call = context.select<PhoneCallProvider, PhoneCallState>((p) => p.callState);
    final state =
        context.select<CaptureProvider, ListeningLabelState>((c) => HomeListeningLabel.simpleStateOf(c, call));
    final sync = context.watch<SyncProvider>();
    final syncing = sync.isSyncing;
    final syncMinutes = (sync.missingWalsInSeconds / 60).ceil();
    final word = switch (state) {
      ListeningLabelState.listening => l10n.listening,
      ListeningLabelState.muted => l10n.muted,
      ListeningLabelState.idle => l10n.notListeningTitle,
    };
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: OmiMotion.of(context).standard,
          curve: OmiMotion.springCurve,
          alignment: Alignment.bottomCenter,
          child: _open ? _panel(context, state, sync) : const SizedBox(width: double.infinity),
        ),
        Semantics(
          button: true,
          expanded: _open,
          label: syncing ? '$word, ${l10n.stripSyncing(syncMinutes)}' : word,
          excludeSemantics: true,
          onTap: _toggle,
          child: GestureDetector(
            key: const Key('listening_strip'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Container(
              color: _stripColor,
              padding: EdgeInsets.fromLTRB(OmiSize.screenMargin, 0, OmiSize.screenMargin, bottom),
              child: SizedBox(
                height: ListeningStrip.height,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state == ListeningLabelState.listening ? _white : _white.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: word, style: const TextStyle(fontWeight: FontWeight.w600, color: _white)),
                          if (syncing)
                            TextSpan(text: ' · ${l10n.stripSyncing(syncMinutes)}', style: const TextStyle(color: _dim)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OmiType.detail.copyWith(height: 1.2, color: _white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Level(live: state == ListeningLabelState.listening),
                    const SizedBox(width: 10),
                    OmiGlyph(_open ? OmiGlyphs.chevronDown : OmiGlyphs.chevronUp,
                        size: 14, color: _white.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _toggle() {
    OmiHaptics.selection();
    setState(() => _open = !_open);
  }

  Widget _panel(BuildContext context, ListeningLabelState state, SyncProvider sync) {
    final l10n = context.l10n;
    final capture = context.read<CaptureProvider>();
    final (deviceName, battery, connected) = context.select<DeviceProvider, (String?, int, bool)>(
      (d) => (d.pairedDevice?.name, d.batteryLevel, d.connectedDevice != null),
    );
    final source = capture.liveCaptureSource;
    final phone = source == null || source == 'phone' || (!connected && state == ListeningLabelState.idle);
    final name = phone
        ? (Platform.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone)
        : ((deviceName ?? '').trim().isNotEmpty ? deviceName!.trim() : CaptureSources.label(context, source));
    final showBattery = !phone && connected && battery >= 0;
    final progress = sync.walsSyncedProgress.clamp(0.0, 1.0);
    final syncMinutes = (sync.missingWalsInSeconds / 60).ceil();
    const small = TextStyle(color: _dim);
    // v8.19 `.qsrc`: 15 on a 20 pt line.
    final text = OmiType.subhead.copyWith(height: 20 / 15, letterSpacing: -0.1, color: _white);
    // v8.19: a tap anywhere on the panel (but Pause and Change) opens Your Omi.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        OmiHaptics.selection();
        setState(() => _open = false);
        unawaited(openYourOmi(context));
      },
      child: Container(
        key: const Key('listening_strip_panel'),
        color: _panelColor,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  _PanelButton(
                    state: state,
                    onPressed: () => _playPause(context, state),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${l10n.recordingFrom} ', style: small),
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (showBattery) TextSpan(text: ' · $battery%', style: small),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.change,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const Key('listening_strip_change'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => routeToPage(context, const DevicesScreen()),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 0, 10),
                        child: Text(
                          l10n.change,
                          style: text.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: _white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (sync.isSyncing)
              Padding(
                // `.qsync`: under the words, past the 40 pt button and its 12 pt gap.
                padding: const EdgeInsets.fromLTRB(52, 0, 0, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              for (final (i, part) in l10n.syncingFrom('\u0001').split('\u0001').indexed) ...[
                                if (i > 0)
                                  TextSpan(
                                      text: name, style: const TextStyle(fontWeight: FontWeight.w600, color: _white)),
                                TextSpan(text: part, style: small),
                              ],
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OmiType.footnote.copyWith(height: 1.4, color: _dim),
                          ),
                        ),
                        Text(l10n.minutesLeft(syncMinutes), style: OmiType.footnote.copyWith(height: 1.4, color: _dim)),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: _white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(_white),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pause mutes what is recording, play unmutes it; with nothing listening it starts (a stopped
  /// wearable wakes, else this phone records).
  Future<void> _playPause(BuildContext context, ListeningLabelState state) async {
    final capture = context.read<CaptureProvider>();
    OmiHaptics.medium();
    try {
      switch (state) {
        case ListeningLabelState.listening:
          await capture.pauseCapture();
        case ListeningLabelState.muted:
          await capture.resumeCapture();
        case ListeningLabelState.idle:
          final stopped = capture.isCaptureStopped && capture.havingRecordingDevice;
          if (!context.mounted) return;
          if (stopped) {
            await IdleCaptureCard.startWearable(context);
          } else {
            await PhoneCapture.start(context);
          }
      }
      PlatformManager.instance.analytics.recordingMuteToggled(
        isMuted: capture.isPaused,
        recordingType: capture.liveCaptureSource == 'phone' ? 'phone_mic' : 'device',
      );
    } catch (_) {
      if (context.mounted) OmiFeedback.error(context, context.l10n.somethingWentWrong);
    }
  }
}

/// The 36 pt white play/pause circle in the panel.
class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.state, required this.onPressed});

  final ListeningLabelState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final playing = state == ListeningLabelState.listening;
    return Semantics(
      button: true,
      label: playing ? l10n.mute : (state == ListeningLabelState.muted ? l10n.unmute : l10n.start),
      excludeSemantics: true,
      child: OmiPressable(
        key: const Key('listening_strip_play'),
        onTap: onPressed,
        child: Container(
          // v8.19 `.qp`: 40 pt with a 15 pt glyph.
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: _ListeningStripState._white),
          child: OmiGlyph(playing ? OmiGlyphs.pauseFill : OmiGlyphs.playFill,
              size: 15, color: const Color(0xFF111111)), // omi-ux-allow: color-literal -- the glyph on the white circle
        ),
      ),
    );
  }
}

/// Three small bars (`.lvl`): tall, tall, short while listening; flat and dim otherwise.
class _Level extends StatelessWidget {
  const _Level({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    const heights = [10.3, 10.3, 4.2];
    return ExcludeSemantics(
      child: SizedBox(
        width: 13,
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final (i, h) in heights.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 3,
                height: live ? h : math.min(h, 3),
                decoration: BoxDecoration(
                  color: _ListeningStripState._white.withValues(alpha: live ? 1 : 0.4),
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
