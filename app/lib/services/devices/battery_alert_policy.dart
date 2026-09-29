/// One warning below 20% and a new warning at 5%, per discharge cycle.
/// Reconnection and noisy readings around 5% must not repeat the critical alert.
class BatteryAlertPolicy {
  String? _deviceId;
  bool _lowSent = false;
  bool _criticalSent = false;

  bool shouldAlert({required String deviceId, required int level, required bool charging}) {
    if (level < 0 || level > 100) return false;
    if (_deviceId != deviceId || charging || level >= 20) {
      _deviceId = deviceId;
      _lowSent = false;
      _criticalSent = false;
    }
    if (charging) return false;
    if (level <= 5 && !_criticalSent) {
      _criticalSent = true;
      _lowSent = true;
      return true;
    }
    if (level < 20 && !_lowSent) {
      _lowSent = true;
      return true;
    }
    return false;
  }

  static bool crossedThreshold(int previous, int current) =>
      (previous < 20) != (current < 20) || (previous <= 5) != (current <= 5);
}
