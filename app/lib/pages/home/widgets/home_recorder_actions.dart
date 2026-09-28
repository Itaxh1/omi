import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

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
/// while paused, otherwise start (a stopped wearable wakes; else this phone records). Each says what
/// happened in a toast Home can undo with the same pull.
abstract final class HomeRecorderActions {
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
          if (context.mounted) OmiFeedback.info(context, l10n.pausedPullToUndo);
        case HomeRecorderState.paused:
          await capture.resumeCapture();
          if (context.mounted) OmiFeedback.info(context, l10n.listeningAgainPullToUndo);
        case HomeRecorderState.reconnecting:
          // The pendant keeps recording while it reconnects: nothing to start or stop.
          return;
        case HomeRecorderState.off:
        case HomeRecorderState.bluetoothOff:
        case HomeRecorderState.notFound:
          await start(context);
          if (context.mounted && read(context) == HomeRecorderState.listening) {
            OmiFeedback.info(context, l10n.listeningAgainPullToUndo);
          }
      }
    } catch (_) {
      if (context.mounted) OmiFeedback.error(context, l10n.somethingWentWrong);
    }
  }
}
