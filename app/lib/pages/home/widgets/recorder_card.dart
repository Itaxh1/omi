import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/pages/conversations/widgets/live_capture_card.dart';
import 'package:omi/pages/devices/devices_screen.dart';
import 'package:omi/pages/home/widgets/phone_capture.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/capture_sources.dart';

/// The recorder card's shell (v3 §4.2): the 3D grey glass ([OmiGlassCard], 28 pt corners) with a
/// footer shared by the live and idle cards: the sync line while recordings come off the pendant,
/// and the full-width "Switch device ›" row, which opens Devices.
class RecorderShell extends StatelessWidget {
  const RecorderShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OmiGlassCard(
      radius: OmiRadius.cardLarge,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [child, const _RecorderFooter()],
      ),
    );
  }
}

/// The sync line (while recordings come off the pendant) and "Switch device ›".
class _RecorderFooter extends StatelessWidget {
  const _RecorderFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer<SyncProvider>(
          builder: (context, sync, _) {
            if (!(sync.isSyncing || sync.isFetchingConversations)) return const SizedBox.shrink();
            final progress = sync.walsSyncedProgress.clamp(0.0, 1.0);
            final done = sync.isFetchingConversations || progress >= 1;
            final line = OmiType.detail.copyWith(height: 1.4, color: OmiColors.ink80);
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                key: const Key('recorder_sync'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(done ? l10n.pendantRecordingsSynced : l10n.syncingToYourPhone,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
                      ),
                      if (!done) Text(l10n.minutesLeft((sync.missingWalsInSeconds / 60).ceil()), style: line),
                    ],
                  ),
                  if (!done) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: OmiColors.divider,
                        valueColor: AlwaysStoppedAnimation(OmiColors.textPrimary),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Divider(height: 1, thickness: 1, color: OmiColors.divider),
        RecorderRow(
          key: const Key('recorder_switch_device'),
          label: l10n.switchDevice,
          chevron: true,
          onTap: () => routeToPage(context, const DevicesScreen()),
        ),
      ],
    );
  }
}

/// A full-width text row in the recorder card (17/500, 44 pt tall), with an optional "›".
class RecorderRow extends StatelessWidget {
  const RecorderRow({super.key, required this.label, required this.onTap, this.chevron = false});

  final String label;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: OmiPressable(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: OmiSize.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OmiType.subhead.copyWith(fontWeight: FontWeight.w500, height: 1.4)),
                ),
                if (chevron) Text('›', style: OmiType.title3.copyWith(color: OmiColors.faint, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The recorder card's live rows (v3 §4.2), drawn from the same inputs as the capture card: the
/// device's photo (or the phone's tile), its name over "Listening · 8 min · 🔋45%", and the 48 pt
/// Mute/Unmute button; then a warning the card explains and a note. Tapping the card opens the live
/// page, which ends the conversation (Stop).
class RecorderCard extends StatelessWidget {
  const RecorderCard({super.key, required this.card});

  final LiveCaptureCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = card;
    final isCall = c.source == LiveCaptureCard.callSource;
    final isPhone = c.source == 'phone';
    final wearable = !isCall && !isPhone;
    final (deviceName, battery) = context.select<DeviceProvider, (String?, int)>(
      (d) => (d.pairedDevice?.name, d.connectedDevice == null ? -1 : d.batteryLevel),
    );
    final name = isCall
        ? l10n.captureSourceCall
        : isPhone
            ? (Platform.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone)
            : (deviceName ?? '').trim().isNotEmpty
                ? deviceName!.trim()
                : CaptureSources.label(context, c.source);
    final parts = [
      c.status,
      if (c.detail != null) c.detail!,
      // `.rstat`: "8 min" (the first minute still counts its seconds).
      if (c.elapsed != null)
        c.elapsed!.inMinutes < 1
            ? LiveCaptureCard.formatElapsed(c.elapsed!)
            : l10n.minutesShortV3(c.elapsed!.inMinutes),
    ];
    final showBattery = wearable && battery >= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecorderDeviceRow(
          key: const Key('recorder_device_row'),
          visual: wearable
              ? OmiOrb(size: 46, live: c.live)
              : const OmiDeviceTile(icon: OmiGlyphs.devicePhone, size: 46, glyph: 26),
          name: name,
          detail: Row(
            children: [
              Flexible(
                child: Text(
                  parts.join(' · '),
                  key: const Key('recorder_status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _detailStyle,
                ),
              ),
              if (showBattery) ...[
                Text(' · ', style: _detailStyle),
                BatteryGlyph(level: battery),
                const SizedBox(width: 3),
                Text('$battery%', key: const Key('recorder_battery'), style: _detailStyle),
              ],
            ],
          ),
          action: !isCall && c.onPauseToggle != null
              ? OmiIconButton.filled(
                  key: const Key('recorder_mute'),
                  icon: OmiGlyph(c.paused ? OmiGlyphs.playFill : OmiGlyphs.pauseFill, size: 18),
                  label: c.paused ? l10n.unmute : l10n.mute,
                  fillColor: OmiColors.accent,
                  color: OmiColors.onAccent,
                  diameter: 48,
                  onPressed: c.onPauseToggle,
                )
              : null,
        ),
        if (c.explanation != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              button: true,
              hint: l10n.learnMore,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => LiveCaptureCard.showDetails(context, title: c.status, explanation: c.explanation!),
                child: Container(
                  key: const Key('recorder_warning'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: OmiColors.dangerSurface, borderRadius: OmiRadius.tileAll),
                  child: Text(
                    c.explanation!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: OmiType.footnote.copyWith(color: OmiColors.danger, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ),
        if (c.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OmiBalancedText(
              c.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OmiType.footnote.copyWith(color: OmiColors.textSecondary),
            ),
          ),
      ],
    );
  }

  static TextStyle get _detailStyle => OmiType.cardSubtitle.copyWith(
        color: OmiColors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Row 1 of the recorder card: the device's visual, its name over a detail line, and an action.
class RecorderDeviceRow extends StatelessWidget {
  const RecorderDeviceRow({super.key, required this.visual, required this.name, required this.detail, this.action});

  final Widget visual;
  final String name;
  final Widget detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ExcludeSemantics(child: visual),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.body.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.17, height: 1.4)),
              const SizedBox(height: 2),
              detail,
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 10), action!],
      ],
    );
  }
}

/// The recorder card while nothing listens (v3, Flutter's idle state): the device's lights-off
/// photo (or the phone's tile), "Not listening · Ready", and a 48 pt Start (play) button, which
/// wakes a connected wearable the reader stopped, else records with this phone.
class RecorderIdleCard extends StatelessWidget {
  const RecorderIdleCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final paired = context.select<DeviceProvider, String?>((d) => d.pairedDevice?.name);
    final stoppedSource = context.select<CaptureProvider, String?>(
      (c) => (c.isCaptureStopped || (c.isStopping && (c.liveCaptureSource ?? 'phone') != 'phone')) &&
              c.havingRecordingDevice
          ? (c.liveCaptureSource ?? 'omi')
          : null,
    );
    final wearable = stoppedSource != null;
    final name = wearable
        ? ((paired ?? '').trim().isNotEmpty ? paired!.trim() : CaptureSources.label(context, stoppedSource))
        : (Platform.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone);
    return RecorderShell(
      key: const Key('recorder_idle'),
      child: RecorderDeviceRow(
        visual: wearable
            ? const OmiOrb(size: 46, live: false)
            : const OmiDeviceTile(icon: OmiGlyphs.devicePhone, size: 46, glyph: 26),
        name: name,
        detail: Text(
          '${l10n.notListeningTitle} · ${l10n.deviceReady}',
          key: const Key('recorder_idle_status'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OmiType.footnote.copyWith(color: OmiColors.textSecondary),
        ),
        action: OmiIconButton.filled(
          key: const Key('recorder_start'),
          icon: const OmiGlyph(OmiGlyphs.playFill, size: 18),
          label: l10n.start,
          fillColor: OmiColors.accent,
          color: OmiColors.onAccent,
          diameter: 48,
          onPressed: () => wearable ? IdleCaptureCard.startWearable(context) : PhoneCapture.start(context),
        ),
      ),
    );
  }
}

/// A small battery outline that fills to [level] (0–100), in the detail line's ink.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({super.key, required this.level, this.color});

  final int level;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size(17, 9),
        painter: _BatteryPainter(level: level.clamp(0, 100) / 100, color: color ?? OmiColors.textSecondary),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final fill = Paint()..color = color;
    final body = Rect.fromLTWH(0.55, 0.55, size.width - 3, size.height - 1.1);
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(2)), stroke);
    // The nub.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 1.6, size.height * 0.3, 1.6, size.height * 0.4),
        const Radius.circular(0.8),
      ),
      fill,
    );
    final inner = body.deflate(1.6);
    if (level > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(inner.left, inner.top, inner.width * level, inner.height), const Radius.circular(1)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) => old.level != level || old.color != color;
}
