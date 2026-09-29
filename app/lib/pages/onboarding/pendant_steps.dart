import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/pages/devices/light_legend_page.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/providers/onboarding_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Pendant setup, step 1 of 3 (v3 `power`): "Turn on your Omi", the pendant photo with a ring
/// pulsing where to press, and what the light says. Tapping the photo practises the press: the LED
/// turns red and "It's on" is ready. "The light didn't come on" explains charging.
class OnboardingPowerStep extends StatefulWidget {
  const OnboardingPowerStep({super.key, required this.onOn});

  final VoidCallback onOn;

  @override
  State<OnboardingPowerStep> createState() => _OnboardingPowerStepState();
}

enum _Power { waiting, on, noLight }

class _OnboardingPowerStepState extends State<OnboardingPowerStep> {
  _Power _state = _Power.waiting;
  bool _on = false;
  bool _pressed = false;

  void _press() {
    OmiHaptics.medium();
    setState(() {
      _pressed = true;
      _on = true;
      _state = _Power.on;
    });
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  /// "It's on." in the ink, then the rest in the secondary ink (`.obstate b`).
  static TextSpan _boldLead(String text) {
    final end = RegExp(r'[.。।!]\s*').firstMatch(text)?.end;
    if (end == null || end >= text.length) return TextSpan(text: text);
    return TextSpan(children: [
      TextSpan(
        text: text.substring(0, end),
        style: TextStyle(color: OmiColors.textPrimary, fontWeight: FontWeight.w600),
      ),
      TextSpan(text: text.substring(end)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = switch (_state) {
      _Power.waiting => TextSpan(text: l10n.tapPictureToTry),
      _Power.on => _boldLead(l10n.itsOnRedMeans),
      _Power.noLight => TextSpan(text: l10n.mayNeedCharging),
    };
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          OnboardingKicker(l10n.obStepYourOmi(1)),
          OnboardingHeader(title: l10n.turnOnYourOmi, subtitle: l10n.pressButtonOnce),
          // `.pend2`: 26 pt above, 8 below, centred.
          const SizedBox(height: 26),
          Center(
            child: Semantics(
              button: true,
              label: l10n.pressButtonOnce,
              child: GestureDetector(
                key: const Key('onboarding_power_pendant'),
                behavior: HitTestBehavior.opaque,
                onTap: _press,
                child: OmiPendantPhoto(
                  led: switch (_state) {
                    _Power.waiting => OmiPendantLed.off,
                    _Power.on => OmiPendantLed.red,
                    _Power.noLight => OmiPendantLed.greenBlink,
                  },
                  hint: _state == _Power.waiting,
                  pressed: _pressed,
                ),
              ),
            ),
          ),
          // `.obstate`'s 6 pt collapses into the picture's 8.
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              liveRegion: true,
              child: Text.rich(
                state,
                key: const Key('onboarding_power_state'),
                textAlign: TextAlign.center,
                style: OmiType.subhead.copyWith(height: 1.4, color: OmiColors.textSecondary),
              ),
            ),
          ),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_power_on'),
            label: l10n.itsOnV3,
            expand: true,
            onPressed: _on
                ? () {
                    OmiHaptics.selection();
                    widget.onOn();
                  }
                : null,
          ),
          OnboardingLink(
            key: const Key('onboarding_power_no_light'),
            label: l10n.lightDidntComeOn,
            onTap: () => setState(() => _state = _Power.noLight),
          ),
        ],
      ),
    );
  }
}

/// Turn on Bluetooth (v3 `perm`, pendant path): the Bluetooth glyph in its ring, why, then Allow
/// Bluetooth (the system prompt) or Not now. Either way the next step looks for the pendant; while
/// Bluetooth is off it waits under the "Bluetooth is off" banner.
class OnboardingBluetoothStep extends StatelessWidget {
  const OnboardingBluetoothStep({super.key, required this.onNext});

  /// Moves on, with whether Allow Bluetooth (not Not now) was tapped.
  final ValueChanged<bool> onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          const SizedBox(height: 26),
          const OnboardingIconRing(glyph: OmiGlyphs.bluetoothLine),
          const SizedBox(height: 30),
          OnboardingHeader(title: l10n.turnOnBluetoothV3, subtitle: l10n.bluetoothOnlyThing),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_bluetooth_allow'),
            label: l10n.connectStepAllowBluetooth,
            expand: true,
            onPressed: () async {
              OmiHaptics.selection();
              try {
                await context.read<OnboardingProvider>().askForBluetoothPermissions();
              } catch (_) {
                // The next step shows the banner while Bluetooth is off or not allowed.
              }
              onNext(true);
            },
          ),
          OnboardingLink(
            key: const Key('onboarding_bluetooth_not_now'),
            label: l10n.notNowV3,
            onTap: () => onNext(false),
          ),
        ],
      ),
    );
  }
}

/// Pendant setup, step 2 of 3 (v3 `scan`): "Looking for your Omi" over the pendant with its red
/// light and rings rippling out; each pendant found nearby gets a row with Pair. Once paired the
/// light turns blue, the title says Paired, and the flow moves on by itself. "Use this phone
/// instead" leaves pendant setup.
class OnboardingScanStep extends StatefulWidget {
  const OnboardingScanStep({
    super.key,
    required this.onPaired,
    required this.onUsePhone,
    this.bluetoothDeclined = false,
  });

  /// Not now on the Bluetooth step: nothing asks for Bluetooth here until Turn on is tapped; the
  /// step waits under the banner.
  final bool bluetoothDeclined;

  /// Called once the pendant is paired and settled (about two seconds after the light turns blue).
  final VoidCallback onPaired;
  final VoidCallback onUsePhone;

  /// The short id under a found pendant (`A3F2 · nearby`): the last four letters or digits of its
  /// address, upper case.
  static String shortId(String id) {
    final plain = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return plain.length <= 4 ? plain : plain.substring(plain.length - 4);
  }

  @override
  State<OnboardingScanStep> createState() => _OnboardingScanStepState();
}

class _OnboardingScanStepState extends State<OnboardingScanStep> {
  OnboardingProvider? _provider;
  BluetoothAdapterState _bluetooth = BluetoothReadiness.instance.state;

  /// Already paired when the step opened (back from the button guide): Continue moves on.
  bool _alreadyPaired = false;

  /// Bluetooth was declined and not turned on since: wait, don't ask.
  late bool _waitingForTurnOn =
      widget.bluetoothDeclined && !(context.read<OnboardingProvider>().hasBluetoothPermission);

  @override
  void initState() {
    super.initState();
    _provider = context.read<OnboardingProvider>();
    _alreadyPaired = _provider!.isConnected;
    BluetoothReadiness.instance.addListener(_onBluetoothChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_alreadyPaired && !_waitingForTurnOn) unawaited(_scan());
    });
  }

  /// Turn on after Not now: the system prompt, then the search.
  Future<void> _turnOn() async {
    OmiHaptics.selection();
    try {
      await _provider?.askForBluetoothPermissions();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _waitingForTurnOn = false);
    unawaited(_scan());
  }

  void _onBluetoothChanged() {
    final next = BluetoothReadiness.instance.state;
    final wasOn = _bluetooth == BluetoothAdapterState.on;
    _bluetooth = next;
    if (!mounted) return;
    setState(() {});
    if (next == BluetoothAdapterState.on && !wasOn && !_waitingForTurnOn && !(_provider?.isConnected ?? false)) {
      _provider?.cancelActiveScan();
      unawaited(_scan());
    } else if (next == BluetoothAdapterState.off) {
      _provider?.cancelActiveScan();
    }
  }

  /// A missing permission goes through the one global Bluetooth prompt, as Find devices does.
  Future<void> _scan() async {
    void guidance() {
      if (mounted) unawaited(BluetoothReadiness.instance.ensureReady(BluetoothUse.discovery));
    }

    await _provider?.scanDevices(onShowDialog: guidance, onShowLocationDialog: guidance);
  }

  @override
  void dispose() {
    BluetoothReadiness.instance.removeListener(_onBluetoothChanged);
    if (!(_provider?.isConnected ?? false)) _provider?.cancelActiveScan();
    super.dispose();
  }

  void _pair(BtDevice device) {
    OmiHaptics.selection();
    unawaited(_provider!.handleTap(
      device: device,
      isFromOnboarding: true,
      goNext: () {
        if (!mounted) return;
        OmiHaptics.success();
        widget.onPaired();
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.watch<OnboardingProvider>();
    final paired = provider.isConnected;
    final off = _waitingForTurnOn || OnboardingBluetoothBanner.isOff(_bluetooth);
    final found = paired || off ? const <BtDevice>[] : provider.deviceList;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          OnboardingBluetoothBanner(show: _waitingForTurnOn, onTurnOn: _waitingForTurnOn ? _turnOn : null),
          OnboardingKicker(l10n.obStepYourOmi(2)),
          Semantics(
            liveRegion: true,
            child: OnboardingHeader(
              key: const Key('onboarding_scan_title'),
              title: paired
                  ? l10n.pairedV3
                  : off
                      ? l10n.waitingForBluetooth
                      : l10n.lookingForYourOmi,
              subtitle: paired ? l10n.lightSolidBlueNow : l10n.keepItClose,
            ),
          ),
          // The picture sits 44 pt under the words (its own 26 pt collapses into that).
          const SizedBox(height: 44),
          Center(
            child: OmiPendantPhoto(
              led: paired ? OmiPendantLed.blue : OmiPendantLed.red,
              ripples: !paired && !off,
            ),
          ),
          // `.found` sits 30 pt under the picture (the picture's 8 pt collapses into it).
          SizedBox(height: found.isNotEmpty ? 30 : 8),
          for (final (i, device) in found.indexed)
            PendantFoundRow(
              key: ValueKey('onboarding_found_${device.id}'),
              device: device,
              first: i == 0,
              pairing: provider.connectingToDeviceId == device.id,
              busy: provider.connectingToDeviceId != null,
              onPair: () => _pair(device),
            ),
        ],
        footer: [
          if (_alreadyPaired && paired)
            OmiButton(
              key: const Key('onboarding_scan_continue'),
              label: l10n.continueButton,
              expand: true,
              onPressed: widget.onPaired,
            ),
          OnboardingLink(
            key: const Key('onboarding_use_phone_instead'),
            label: l10n.useThisPhoneInstead,
            onTap: widget.onUsePhone,
          ),
        ],
      ),
    );
  }
}

/// A pendant found nearby (`.found`): its name at 17/600 over "A3F2 · nearby", and Pair. Also the
/// rows of Devices → Add a device.
class PendantFoundRow extends StatelessWidget {
  const PendantFoundRow({
    super.key,
    required this.device,
    required this.first,
    required this.pairing,
    required this.busy,
    required this.onPair,
  });

  final BtDevice device;
  final bool first;
  final bool pairing;
  final bool busy;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = device.type == DeviceType.omi ? l10n.omiPendantName : device.name;
    final detail = l10n.nearbyDevice(OnboardingScanStep.shortId(device.id));
    final line = BorderSide(color: OmiColors.divider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border(top: first ? line : BorderSide.none, bottom: line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 2),
                Text(detail, style: OmiType.detail.copyWith(color: OmiColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Semantics(
            button: true,
            enabled: !busy,
            label: '${pairing ? l10n.pairingV3 : l10n.pairV3}, $name',
            excludeSemantics: true,
            child: GestureDetector(
              key: const Key('onboarding_pair'),
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onPair,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Container(
                  height: 38,
                  constraints: const BoxConstraints(minWidth: 76),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: OmiColors.accent,
                    borderRadius: const BorderRadius.all(Radius.circular(19)),
                  ),
                  child: Text(
                    pairing ? l10n.pairingV3 : l10n.pairV3,
                    style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600, height: 1, color: OmiColors.onAccent),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pendant setup, step 3 of 3 (v3 `buttons`): the button's three moves (tap once, tap twice, hold
/// three seconds), then "What the light means", then Got it.
class OnboardingButtonsStep extends StatelessWidget {
  const OnboardingButtonsStep({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final moves = [
      ('1×', l10n.tapOnceV3, l10n.tapOnceBody),
      ('2×', l10n.tapTwiceV3, l10n.tapTwiceBody),
      ('3s', l10n.holdThreeSeconds, l10n.holdThreeSecondsBody),
    ];
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          const OnboardingBluetoothBanner(),
          OnboardingKicker(l10n.obStepYourOmi(3)),
          OnboardingHeader(title: l10n.oneButtonThreeMoves),
          // The title's 12 pt (the list's own 10 collapses into it).
          const SizedBox(height: 12),
          for (final (i, move) in moves.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == moves.length - 1 ? null : Border(bottom: BorderSide(color: OmiColors.divider)),
              ),
              child: Row(
                children: [
                  // `.btn-g`: a 40 pt ring with the move in it.
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        move.$1,
                        style: OmiType.caption1.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.24, height: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(move.$2, style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                        const SizedBox(height: 1),
                        Text(move.$3, style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          OmiSectionLabel(title: l10n.whatTheLightMeans, top: 26, bottom: 5),
          const LightLegendList(),
        ],
        footer: [
          OmiButton(key: const Key('onboarding_buttons_got_it'), label: l10n.gotItV3, expand: true, onPressed: onDone),
        ],
      ),
    );
  }
}
