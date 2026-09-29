import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/pages/home/widgets/phone_capture.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// What Home's pull down and Your Omi's first button do (v8.6): pause while listening, resume
/// while paused, otherwise start (a stopped wearable wakes; else this phone records). The first
/// three successful actions teach the reader that another pull undoes the change.
abstract final class HomeRecorderActions {
  static const _pullHintCountKey = 'homePullUndoHintCount';
  static const _pullHintLimit = 3;

  /// Pause and resume share one teaching budget, persisted across app launches.
  /// Only successful actions that can display the hint consume an appearance.
  static void _showPullHint(BuildContext context, String message) {
    if (!context.mounted || ScaffoldMessenger.maybeOf(context) == null) return;
    final prefs = SharedPreferencesUtil();
    final shown = prefs.getInt(_pullHintCountKey).clamp(0, _pullHintLimit);
    if (shown >= _pullHintLimit) return;
    OmiFeedback.info(context, message);
    // SharedPreferences updates its in-memory value synchronously. A failed
    // disk write must not turn a successful capture action into an error alert.
    unawaited(prefs.saveInt(_pullHintCountKey, shown + 1).catchError((_) => false));
  }

  /// The label's state, read once (no rebuild).
  static HomeRecorderState read(BuildContext context) {
    final device = context.read<DeviceProvider?>();
    final paired = (device?.pairedDevice?.id ?? '').isNotEmpty;
    return HomeListeningLabel.stateOf(
      call: context.read<PhoneCallProvider>().callState,
      capture: context.read<CaptureProvider>(),
      paired: paired,
      connected: device?.isConnected ?? false,
      connecting: device?.isConnecting ?? false,
      bluetoothOff: BluetoothReadiness.instance.state == BluetoothAdapterState.off,
    );
  }

  static bool _onCall(BuildContext context) {
    final call = context.read<PhoneCallProvider>().callState;
    return call == PhoneCallState.active || call == PhoneCallState.connecting || call == PhoneCallState.ringing;
  }

  /// Start listening: the wearable the reader stopped, or else this phone (without opening the
  /// live page).
  static Future<void> start(BuildContext context) async {
    final capture = context.read<CaptureProvider>();
    final stoppedWearable =
        (capture.isCaptureStopped || (capture.isStopping && (capture.liveCaptureSource ?? 'phone') != 'phone')) &&
            capture.havingRecordingDevice;
    if (stoppedWearable) {
      await IdleCaptureCard.startWearable(context);
    } else {
      await PhoneCapture.start(context, openLive: false);
    }
  }

  /// The pull's action, with its toast ("Paused. Pull down again to undo.").
  static Future<void> act(BuildContext context) async {
    if (_onCall(context)) return;
    final l10n = context.l10n;
    final capture = context.read<CaptureProvider>();
    final state = read(context);
    try {
      switch (state) {
        case HomeRecorderState.listening:
          await capture.pauseCapture();
          if (context.mounted) _showPullHint(context, l10n.pausedPullToUndo);
        case HomeRecorderState.paused:
          await capture.resumeCapture();
          if (context.mounted) _showPullHint(context, l10n.listeningAgainPullToUndo);
        case HomeRecorderState.reconnecting:
          // The pendant keeps recording while it reconnects: nothing to start or stop.
          return;
        case HomeRecorderState.off:
        case HomeRecorderState.bluetoothOff:
        case HomeRecorderState.notFound:
          await start(context);
          if (context.mounted && read(context) == HomeRecorderState.listening) {
            _showPullHint(context, l10n.listeningAgainPullToUndo);
          }
      }
    } catch (_) {
      if (context.mounted) OmiFeedback.error(context, l10n.somethingWentWrong);
    }
  }
}
