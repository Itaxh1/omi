import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/conversations/widgets/live_capture_card.dart';
import 'package:omi/pages/devices/add_device_page.dart';
import 'package:omi/pages/home/widgets/battery_info_widget.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/pages/settings/settings_destinations.dart';
import 'package:omi/pages/settings/settings_search_index.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/widgets/capture_sources.dart';

/// At a large text size the row's words need the whole width: the buttons move under them.
bool _stackControls(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 12;

/// Home's "Now" row (v5): the live card's inputs drawn as one row, about a third of the card's
/// height. The pendant's photo (lit while audio is captured), the state over "source · time", then
/// Mute (Unmute once muted) and Stop as 44 pt icon buttons; under them, one line of the latest
/// words. A call shows a chevron instead: the call page owns its controls. Tapping the row opens
/// the Live page, which `ConversationCaptureWidget` handles as it does for the card.
class CaptureNowRow extends StatelessWidget {
  const CaptureNowRow({super.key, required this.card});

  /// The same inputs the full card draws.
  final LiveCaptureCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = card;
    final isCall = c.source == LiveCaptureCard.callSource;
    final sourceName = isCall
        ? l10n.captureSourceCall
        : c.source == 'phone'
            ? l10n.phone
            : CaptureSources.label(context, c.source);
    final problem = c.explanation != null;
    final Widget thumb = !isCall && c.source != 'phone'
        ? Hero(tag: kLiveOrbHeroTag, child: OmiOrb(size: 44, live: c.live))
        : _SourceMark(icon: isCall ? Icons.call_rounded : CaptureSources.icon(c.source), live: c.live);
    final subtitle = [
      sourceName,
      if (c.detail != null) c.detail!,
      if (c.elapsed != null) LiveCaptureCard.formatElapsed(c.elapsed!),
    ].join(' · ');
    Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (problem) ...[
              ExcludeSemantics(child: Icon(Icons.warning_amber_rounded, size: 16, color: OmiColors.warning)),
              const SizedBox(width: OmiSpacing.xxs),
            ],
            // Long states (in a long language) take a second line.
            Flexible(child: Text(c.status, maxLines: 2, overflow: TextOverflow.ellipsis, style: OmiType.headline)),
            if (c.live) ...[
              const SizedBox(width: OmiSpacing.xs),
              // The listening wave in miniature, beside the state.
              const SizedBox(width: 26, child: OmiListeningWave(key: Key('capture_now_meter'), height: 12)),
            ],
          ],
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OmiType.footnote.copyWith(
            color: OmiColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    if (problem) {
      text = Semantics(
        button: true,
        hint: l10n.learnMore,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => LiveCaptureCard.showDetails(context, title: c.status, explanation: c.explanation!),
          child: text,
        ),
      );
    }
    final controls = <Widget>[
      if (!isCall && c.onPauseToggle != null)
        OmiIconButton.filled(
          key: const Key('capture_now_mute'),
          icon: Icon(c.paused ? Icons.mic_rounded : Icons.mic_off_rounded),
          label: c.paused ? l10n.unmute : l10n.mute,
          fillColor: OmiColors.surface3,
          onPressed: c.onPauseToggle,
        ),
      if (!isCall && c.onFinish != null)
        OmiIconButton.filled(
          key: const Key('capture_now_stop'),
          icon: const Icon(Icons.stop_rounded),
          label: l10n.stop,
          fillColor: OmiColors.accent,
          color: OmiColors.onAccent,
          onPressed: c.onFinish,
        ),
    ];
    final stack = controls.isNotEmpty && _stackControls(context);
    final line = c.lastLine?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExcludeSemantics(child: thumb),
            const SizedBox(width: OmiSpacing.sm),
            Expanded(child: text),
            const SizedBox(width: OmiSpacing.xs),
            if (controls.isEmpty)
              OmiGlyph(OmiGlyphs.chevronRight, size: 14, color: OmiColors.textTertiary)
            else if (!stack)
              ...controls,
          ],
        ),
        if (c.showsTranscript) ...[
          const SizedBox(height: OmiSpacing.xs),
          // Nothing heard yet: say where the words will go, never an empty band.
          Text(
            line.isEmpty ? l10n.connectStepTestHint : '…$line',
            key: const Key('capture_now_line'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OmiType.footnote.copyWith(color: line.isEmpty ? OmiColors.textTertiary : OmiColors.textSecondary),
          ),
        ],
        if (c.note != null) ...[
          const SizedBox(height: OmiSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(CaptureSources.icon('omi'), size: 14, color: OmiColors.textTertiary),
              ),
              const SizedBox(width: OmiSpacing.xs),
              Flexible(
                child: OmiBalancedText(
                  c.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.footnote.copyWith(color: OmiColors.textTertiary),
                ),
              ),
            ],
          ),
        ],
        if (stack) ...[
          const SizedBox(height: OmiSpacing.xs),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
        ],
      ],
    );
  }
}

/// The phone or a call in the pendant's place: its mark in a circle, with a live (or amber) dot.
class _SourceMark extends StatelessWidget {
  const _SourceMark({required this.icon, required this.live});

  final IconData icon;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: OmiColors.surface2, shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 20, color: OmiColors.textPrimary),
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: live ? OmiColors.live : OmiColors.warning, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's "Now" row while nothing listens (v5): the pendant's lights-off photo, "Not listening"
/// over "source · Ready", a devices button (add one, or open Devices when one is paired) and
/// Start. Hidden whenever the live row or a call is showing, like [IdleCaptureCard].
class IdleCaptureRow extends StatelessWidget {
  const IdleCaptureRow({super.key});

  @override
  Widget build(BuildContext context) {
    final callState = context.select<PhoneCallProvider, PhoneCallState>((p) => p.callState);
    final onCall = callState == PhoneCallState.active ||
        callState == PhoneCallState.connecting ||
        callState == PhoneCallState.ringing;
    final capturing = context.select<CaptureProvider, bool>(IdleCaptureCard.isCapturing);
    if (onCall || capturing) return const SizedBox.shrink();
    final paired = context.select<DeviceProvider, bool>((d) => (d.pairedDevice?.id ?? '').isNotEmpty);
    // A connected wearable the reader stopped (or is stopping): Start wakes it rather than the phone.
    final stoppedSource = context.select<CaptureProvider, String?>(
      (c) => (c.isCaptureStopped || (c.isStopping && (c.liveCaptureSource ?? 'phone') != 'phone')) &&
              c.havingRecordingDevice
          ? (c.liveCaptureSource ?? 'omi')
          : null,
    );
    final l10n = context.l10n;
    final source = stoppedSource == null
        ? (Platform.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone)
        : CaptureSources.label(context, stoppedSource);
    final controls = <Widget>[
      OmiIconButton.filled(
        key: const ValueKey('idle_capture_row_devices'),
        icon: Icon(paired ? Icons.tune_rounded : Icons.add_rounded),
        label: paired ? l10n.manageDevices : l10n.addADevice,
        fillColor: OmiColors.surface3,
        onPressed: () {
          OmiHaptics.selection();
          if (paired) {
            openSettingsDestination(context, SettingsDestination.deviceGroup);
          } else {
            routeToPage(context, const AddDevicePage());
          }
        },
      ),
      const SizedBox(width: OmiSpacing.xxs),
      _StartPill(
        key: const ValueKey('idle_capture_row_start'),
        label: l10n.start,
        onPressed: () => stoppedSource != null ? IdleCaptureCard.startWearable(context) : PhoneCapture.start(context),
      ),
    ];
    final stack = _stackControls(context);
    return Padding(
      key: const ValueKey('idle_capture_row'),
      padding: const EdgeInsets.fromLTRB(OmiSpacing.md, OmiSpacing.lg, OmiSpacing.md, OmiSpacing.sm),
      child: OmiCard(
        radius: OmiRadius.row,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const OmiOrb(size: 44, live: false),
                const SizedBox(width: OmiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.notListeningTitle,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: OmiType.headline),
                      Text(
                        '$source · ${l10n.deviceReady}',
                        key: const ValueKey('idle_capture_row_subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OmiType.footnote.copyWith(color: OmiColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!stack) ...[const SizedBox(width: OmiSpacing.xs), ...controls],
              ],
            ),
            if (stack) ...[
              const SizedBox(height: OmiSpacing.xs),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
            ],
          ],
        ),
      ),
    );
  }
}

/// Start as a 40 pt accent pill that fits its label.
class _StartPill extends StatelessWidget {
  const _StartPill({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: OmiPressable(
        onTap: onPressed,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: OmiColors.accent,
            borderRadius: OmiRadius.pillAll,
            boxShadow: [BoxShadow(color: OmiColors.shadowSoft, blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record_rounded, size: 12, color: OmiColors.onAccent),
              const SizedBox(width: OmiSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OmiType.headline.copyWith(color: OmiColors.onAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
