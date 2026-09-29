import 'package:flutter_test/flutter_test.dart';
import 'package:omi/services/devices/battery_alert_policy.dart';

void main() {
  test('a 5% warning follows the earlier low-battery warning, once per discharge', () {
    final policy = BatteryAlertPolicy();
    bool read(int level, {bool charging = false}) =>
        policy.shouldAlert(deviceId: 'pendant', level: level, charging: charging);
    expect(read(20), isFalse);
    expect(read(19), isTrue);
    expect(read(6), isFalse);
    expect(read(5), isTrue);
    expect(read(4), isFalse);
    expect(read(6), isFalse);
    expect(read(5), isFalse);
    expect(read(30, charging: true), isFalse);
    expect(read(5), isTrue);
  });

  test('already critical on connection alerts; invalid readings and charging do not', () {
    final policy = BatteryAlertPolicy();
    expect(policy.shouldAlert(deviceId: 'a', level: -1, charging: false), isFalse);
    expect(policy.shouldAlert(deviceId: 'a', level: 1, charging: false), isTrue);
    expect(policy.shouldAlert(deviceId: 'a', level: 1, charging: false), isFalse);
    expect(policy.shouldAlert(deviceId: 'b', level: 2, charging: false), isTrue);
    expect(policy.shouldAlert(deviceId: 'b', level: 3, charging: true), isFalse);
  });

  test('critical crossing bypasses the 5-point UI throttle', () {
    expect(BatteryAlertPolicy.crossedThreshold(6, 5), isTrue);
    expect(BatteryAlertPolicy.crossedThreshold(5, 6), isTrue);
    expect(BatteryAlertPolicy.crossedThreshold(5, 4), isFalse);
  });
}
