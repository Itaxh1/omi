import 'package:omi/utils/platform/platform_manager.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/conversation_capturing/page.dart';
import 'package:omi/pages/phone_calls/phone_calls_page.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/pages/phone_calls/active_call_page.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/capture_sources.dart';

/// Recording with this phone (Today's Start listening, Recording from → This phone, Devices →
/// "Use this phone"). An Omi call opens instead; a wearable that is listening asks first (one
/// source records at a time); a phone recording that is already running is finished.
abstract final class PhoneCapture {
  static bool _callInProgress(BuildContext context) {
    final state = context.read<PhoneCallProvider>().callState;
    return state == PhoneCallState.connecting || state == PhoneCallState.ringing || state == PhoneCallState.active;
  }

  /// The pendant is recording (or paused) in realtime mode: explain, and let the user choose.
  /// A Transcribe Later pendant is excluded — its capture can't be taken over at all, so it
  /// falls through to the refusal feedback rather than offering a choice that would fail.
  static bool _pendantHasCapture(CaptureProvider capture) {
    final source = capture.liveCaptureSource;
    return source != null &&
        source != 'phone' &&
        !SharedPreferencesUtil().batchModeEnabled &&
        !capture.isPendantBatchRecording;
  }

  static void _showPendantListening(BuildContext context) {
    OmiHaptics.light();
    showOmiSheet<void>(
      context: context,
      title: context.l10n.pendantIsListeningTitle,
      builder: (sheetContext) => PendantListeningSheet(
        onRecordWithPhone: () {
          Navigator.pop(sheetContext);
          _startPhoneRecording(context);
        },
        onPhoneCall: () {
          Navigator.pop(sheetContext);
          if (context.mounted) routeToPage(context, const PhoneCallsPage());
        },
        onKeepPendant: () => Navigator.pop(sheetContext),
      ),
    );
  }

  static Future<void> start(BuildContext context) async {
    final captureProvider = context.read<CaptureProvider>();
    if (captureProvider.recordingState == RecordingState.initialising) return;
    // An Omi call owns the capture while it runs: open the call, never a recording.
    if (_callInProgress(context)) {
      routeToPage(context, const ActiveCallPage());
      return;
    }
    if (_pendantHasCapture(captureProvider) && !captureProvider.isPhoneMicPaused) {
      _showPendantListening(context);
      return;
    }
    await _startPhoneRecording(context);
  }

  static Future<void> _startPhoneRecording(BuildContext context) async {
    final captureProvider = context.read<CaptureProvider>();
    OmiHaptics.medium();
    if (captureProvider.recordingState == RecordingState.record || captureProvider.isPhoneMicPaused) {
      // A phone recording is running: finish it (processed, except Transcribe Later,
      // whose local file is finalized on stop), then any pendant it paused resumes.
      try {
        await captureProvider.finishCapture();
      } catch (_) {
        if (context.mounted) OmiFeedback.error(context, context.l10n.somethingWentWrong);
        return;
      }
      PlatformManager.instance.analytics.phoneMicRecordingStopped();
      return;
    }
    if (captureProvider.isPendantBatchRecording) {
      if (context.mounted) {
        OmiFeedback.info(context, context.l10n.phoneRecordingBlockedByPendantBatch);
      }
      return;
    }
    try {
      await captureProvider.streamRecording();
    } catch (_) {
      if (context.mounted) {
        OmiFeedback.error(context, context.l10n.somethingWentWrong);
      }
      return;
    }
    if (captureProvider.liveCaptureSource != 'phone') return;
    PlatformManager.instance.analytics.phoneMicRecordingStarted();
    // Phone-mic Transcribe Later (batch) has no live transcript — its surface is the
    // conversations-list batch card, so skip the capturing page (same as BLE batch).
    if (captureProvider.isPhoneMicBatchRecording) {
      if (SharedPreferencesUtil().phoneBatchAuto && context.mounted) {
        OmiFeedback.info(context, context.l10n.phoneMicOfflineFallbackMessage);
      }
      return;
    }
    if (context.mounted) {
      routeToPage(context, ConversationCapturingPage(topConversationId: captureProvider.topConversationId));
    }
  }
}

class _RecordOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RecordOption({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      excludeSemantics: true,
      child: Material(
        color: OmiColors.surface2,
        borderRadius: OmiRadius.lgAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            OmiHaptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: OmiSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: OmiColors.surface3),
                  child: Icon(icon, color: OmiColors.textPrimary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: OmiType.footnote.copyWith(color: OmiColors.textSecondary)),
                    ],
                  ),
                ),
                OmiGlyph(OmiGlyphs.chevronRight, size: 14, color: OmiColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small horizontal battery: outline, nub and a fill proportional to [level]. Neutral unless
/// [critical], when the fill is red.
class BatteryGlyph extends StatelessWidget {
  const BatteryGlyph({super.key, required this.level, required this.critical});

  final int level;
  final bool critical;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(20, 10), painter: _BatteryGlyphPainter(level.clamp(0, 100) / 100, critical));
}

class _BatteryGlyphPainter extends CustomPainter {
  _BatteryGlyphPainter(this.fraction, this.critical);
  final double fraction;
  final bool critical;

  @override
  void paint(Canvas canvas, Size size) {
    const nub = 2.0;
    final body = Rect.fromLTWH(0.5, 0.5, size.width - nub - 1.5, size.height - 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(2.5)),
      Paint()
        ..color = OmiColors.textSecondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(body.right + 0.5, size.height / 2 - 2, nub, 4), const Radius.circular(1)),
      Paint()..color = OmiColors.textSecondary,
    );
    final inner = body.deflate(1.75);
    if (fraction <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left, inner.top, inner.width * fraction, inner.height), const Radius.circular(1)),
      Paint()..color = critical ? OmiColors.danger : OmiColors.textPrimary,
    );
  }

  @override
  bool shouldRepaint(_BatteryGlyphPainter old) => old.fraction != fraction || old.critical != critical;
}

/// Shown when the phone record button is tapped while the pendant is recording: Omi records from
/// one source at a time, so the phone offers to take over (the pendant pauses and resumes after),
/// a call (the pendant pauses during it), or to leave the pendant as it is.
class PendantListeningSheet extends StatelessWidget {
  const PendantListeningSheet({
    super.key,
    required this.onRecordWithPhone,
    required this.onPhoneCall,
    required this.onKeepPendant,
  });

  final VoidCallback onRecordWithPhone;
  final VoidCallback onPhoneCall;
  final VoidCallback onKeepPendant;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: OmiSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.oneSourceAtATime, style: OmiType.subhead.copyWith(color: OmiColors.textSecondary)),
          const SizedBox(height: OmiSpacing.md),
          _RecordOption(
            icon: CaptureSources.icon('phone'),
            title: l10n.recordWithPhoneInstead,
            subtitle: l10n.pendantPausesUntilYouFinish,
            onTap: onRecordWithPhone,
          ),
          const SizedBox(height: 10),
          _RecordOption(
            icon: Icons.call_rounded,
            title: l10n.phoneCall,
            subtitle: l10n.pendantPausesDuringCall,
            onTap: onPhoneCall,
          ),
          const SizedBox(height: OmiSpacing.md),
          OmiButton.secondary(label: l10n.keepUsingPendant, onPressed: onKeepPendant),
        ],
      ),
    );
  }
}

/// The device in the pill: the Omi pendant is drawn (LED lit while connected); other devices use
/// their photo.
