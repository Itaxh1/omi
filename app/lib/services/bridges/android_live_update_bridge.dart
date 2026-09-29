import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/services/capture/capture_system_surface.dart';
import 'package:omi/ui/format/speaker_names.dart';

/// Android's recording surface, the counterpart of [LiveActivityBridge]: each capture snapshot
/// becomes a Live Update (the promoted ongoing notification, with a status bar chip on Android 16)
/// drawn by `CaptureLiveUpdate.kt`. Its words travel with the snapshot, already in the app's
/// language; its Pause, Resume and Stop come back as `action`, like the Lock Screen's buttons.
class AndroidLiveUpdateBridge implements CaptureSystemSurfaceSink {
  AndroidLiveUpdateBridge({MethodChannel? channel, SharedPreferencesUtil? preferences, AppLocalizations Function()? l10n})
      : channel = channel ?? const MethodChannel(channelName),
        preferences = preferences ?? SharedPreferencesUtil(),
        _l10n = l10n ?? SpeakerNames.contextFreeL10n;

  static const channelName = 'com.omi.android/liveUpdate';
  static AndroidLiveUpdateBridge? _current;
  final String _ownerId = const Uuid().v4();
  final MethodChannel channel;
  final SharedPreferencesUtil preferences;
  final AppLocalizations Function() _l10n;

  @override
  Future<void> start(Future<Map<String, Object?>> Function(Map<String, Object?>) action) async {
    _current = this;
    channel.setMethodCallHandler((call) async {
      if (!identical(_current, this)) throw StateError('Capture owner changed');
      if (call.method != 'action' || call.arguments is! Map) throw MissingPluginException();
      return action(Map<String, Object?>.from(call.arguments as Map));
    });
    await channel.invokeMethod<void>('ready', _ownerId);
  }

  @override
  Future<void> publish(Map<String, Object?> snapshot) => channel.invokeMethod<void>('publish', {
        ...snapshot,
        // The notification draws the clock itself; levels only animate the iOS strip.
        'levels': const <int>[],
        'ownerId': _ownerId,
        'enabled': preferences.showCaptureLiveActivity,
        'labels': labels(snapshot, _l10n()),
      });

  @override
  Future<void> close() async {
    if (!identical(_current, this)) return;
    _current = null;
    channel.setMethodCallHandler(null);
    await channel.invokeMethod<void>('detach', _ownerId);
  }

  /// The notification's words for [snapshot]: what Omi is doing (the title), where the audio comes
  /// from, the buttons, and the status bar chip's word while the clock is stopped.
  static Map<String, String?> labels(Map<String, Object?> snapshot, AppLocalizations l10n) {
    final status = snapshot['status'];
    final phone = snapshot['source'] == 'phone';
    final title = switch (status) {
      'paused' || 'interrupted' => l10n.paused,
      'connecting' => l10n.deviceConnecting,
      'reconnecting' => l10n.reconnecting,
      'recording' => l10n.recordingNow,
      _ => l10n.listening,
    };
    return {
      'title': title,
      'text': phone ? l10n.memoryThisPhone : l10n.omiAppName,
      'pause': l10n.pause,
      'resume': l10n.resume,
      'stop': l10n.stop,
      'chip': status == 'paused' || status == 'interrupted' ? l10n.paused : null,
      'channel': l10n.yourOmi,
    };
  }
}
