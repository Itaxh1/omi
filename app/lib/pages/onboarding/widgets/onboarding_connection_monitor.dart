import 'dart:async';

import 'package:flutter/material.dart';

import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';

/// Keeps Bluetooth guidance available throughout sign-in and onboarding, including
/// when returning from Settings. Observation never requests permission or blocks
/// phone-only recording. iOS radio power remains under the user's control.
class OnboardingConnectionMonitor extends StatefulWidget {
  const OnboardingConnectionMonitor({super.key, required this.child, this.showBanner = true, this.readiness});

  final Widget child;
  final bool showBanner;
  final BluetoothReadiness? readiness;

  @override
  State<OnboardingConnectionMonitor> createState() => _OnboardingConnectionMonitorState();
}

class _OnboardingConnectionMonitorState extends State<OnboardingConnectionMonitor> with WidgetsBindingObserver {
  late final BluetoothReadiness _readiness = widget.readiness ?? BluetoothReadiness.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readiness.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readiness.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _readiness,
        builder: (context, _) => Column(
          children: [
            if (widget.showBanner && OnboardingBluetoothBanner.isOff(_readiness.state))
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 8, OmiSize.screenMargin, 0),
                  child: OnboardingBluetoothBanner(
                    show: true,
                    onTurnOn: () => _readiness.requestGuidance(BluetoothUse.connection),
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      );
}
