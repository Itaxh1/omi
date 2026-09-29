import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/devices/add_device_page.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/pages/onboarding/pendant_steps.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/onboarding_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/widgets/connection_guide_sheet.dart';

/// Devices → Add a device (v8 `perm` then `pair`): one sheet whose title follows the steps.
/// Bluetooth off or not allowed first asks for it ("Turn on Bluetooth"); then "Looking for your
/// pendant" turns the mark while it searches, "Found one" lists what is nearby with Pair,
/// "Pairing…" holds on, and "Paired" says "Your pendant's connected" with Start recording. Nothing
/// found after a while offers Scan again and How to pair; Other devices keeps the full list
/// (glasses, watches, this phone).
abstract final class PairDeviceSheet {
  static Future<void> show(BuildContext context) {
    return showOmiModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      color: () => OmiColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: OmiRadius.sheetTopFor(Theme.of(context).platform)),
      builder: (_) => _PairFlow(hostContext: context),
    );
  }
}

enum _Step { bluetooth, looking, found, pairing, paired }

class _PairFlow extends StatefulWidget {
  const _PairFlow({required this.hostContext});

  /// Devices, where Other devices and Start recording continue once the sheet closes.
  final BuildContext hostContext;

  @override
  State<_PairFlow> createState() => _PairFlowState();
}

class _PairFlowState extends State<_PairFlow> {
  late final OnboardingProvider _provider = context.read<OnboardingProvider>();
  BluetoothAdapterState _bluetooth = BluetoothReadiness.instance.state;
  bool _askedBluetooth = false;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    BluetoothReadiness.instance.addListener(_onBluetoothChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_bluetoothOff) unawaited(_scan());
    });
  }

  @override
  void dispose() {
    BluetoothReadiness.instance.removeListener(_onBluetoothChanged);
    if (!_paired) _provider.cancelActiveScan();
    super.dispose();
  }

  bool get _bluetoothOff => OnboardingBluetoothBanner.isOff(_bluetooth);

  void _onBluetoothChanged() {
    final next = BluetoothReadiness.instance.state;
    final wasOff = _bluetoothOff;
    _bluetooth = next;
    if (!mounted) return;
    setState(() {});
    if (wasOff && !_bluetoothOff && !_paired) {
      _provider.cancelActiveScan();
      unawaited(_scan());
    } else if (_bluetoothOff) {
      _provider.cancelActiveScan();
    }
  }

  /// A missing permission goes through the app's one Bluetooth prompt, as Find devices does.
  Future<void> _scan() async {
    void guidance() {
      if (mounted) unawaited(BluetoothReadiness.instance.ensureReady(BluetoothUse.discovery));
    }

    _provider.enableInstructions = false;
    await _provider.scanDevices(onShowDialog: guidance, onShowLocationDialog: guidance);
  }

  Future<void> _allowBluetooth() async {
    OmiHaptics.selection();
    setState(() => _askedBluetooth = true);
    try {
      await _provider.askForBluetoothPermissions();
    } catch (_) {
      // Still off: the step stays, and Bluetooth coming on moves it along.
    }
    if (mounted && !_bluetoothOff) unawaited(_scan());
  }

  void _pair(BtDevice device) {
    OmiHaptics.selection();
    unawaited(_provider.handleTap(
      device: device,
      isFromOnboarding: false,
      goNext: () {
        if (!mounted) return;
        OmiHaptics.success();
        setState(() => _paired = true);
      },
    ));
  }

  void _close() => Navigator.of(context).maybePop();

  /// Start recording: the sheet closes and the pendant records, unless it already is.
  Future<void> _startRecording() async {
    OmiHaptics.selection();
    final host = widget.hostContext;
    final capture = host.read<CaptureProvider>();
    final recording = capture.recordingState == RecordingState.deviceRecord && !capture.isPaused;
    Navigator.of(context).pop();
    if (!recording && host.mounted) await IdleCaptureCard.startWearable(host);
  }

  void _otherDevices() {
    OmiHaptics.selection();
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (host.mounted) routeToPage(host, const AddDevicePage());
  }

  _Step _step(OnboardingProvider provider) {
    if (_paired) return _Step.paired;
    if (_bluetoothOff) return _Step.bluetooth;
    if (provider.connectingToDeviceId != null) return _Step.pairing;
    if (provider.deviceList.isNotEmpty) return _Step.found;
    return _Step.looking;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.watch<OnboardingProvider>();
    final step = _step(provider);
    final title = switch (step) {
      _Step.bluetooth => null,
      _Step.looking => l10n.lookingForYourPendant,
      _Step.found => l10n.foundPendants(provider.deviceList.length),
      _Step.pairing => l10n.pairingV3,
      _Step.paired => l10n.pairedV3,
    };
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: OmiSheetScaffold(
        title: title,
        closeLabel: step == _Step.paired ? null : l10n.cancel,
        onClose: _close,
        padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
        child: AnimatedSwitcher(
          duration: OmiMotion.of(context).standard,
          child: KeyedSubtree(
            key: ValueKey(step),
            child: switch (step) {
              _Step.bluetooth => _bluetoothStep(l10n),
              _Step.paired => _pairedStep(l10n, provider),
              _ => _searchStep(l10n, provider, step),
            },
          ),
        ),
      ),
    );
  }

  /// `perm`: the Bluetooth glyph in its ring, why, Allow Bluetooth and Not now.
  Widget _bluetoothStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const OnboardingIconRing(glyph: OmiGlyphs.bluetoothLine),
        const SizedBox(height: 30),
        OnboardingHeader(title: l10n.turnOnBluetoothV3, subtitle: l10n.bluetoothOnlyThing),
        const Spacer(),
        OmiButton(
          key: const Key('pair_allow_bluetooth'),
          label: l10n.connectStepAllowBluetooth,
          expand: true,
          onPressed: _askedBluetooth ? () => BluetoothReadiness.instance.ensureReady(BluetoothUse.discovery) : _allowBluetooth,
        ),
        OnboardingLink(key: const Key('pair_not_now'), label: l10n.notNowV3, onTap: _close),
        const SizedBox(height: 12),
      ],
    );
  }

  /// `pair`: the mark (turning while it looks or pairs), the words under it, the pendants found,
  /// and, when nothing turns up, Scan again and How to pair.
  Widget _searchStep(AppLocalizations l10n, OnboardingProvider provider, _Step step) {
    final busy = step == _Step.pairing || step == _Step.looking;
    final nothing = step == _Step.looking && provider.enableInstructions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 34),
        Center(
          child: OmiRingLogo(
            key: const Key('pair_mark'),
            size: 96,
            mode: busy && !nothing ? OmiRingMode.chase : OmiRingMode.still,
          ),
        ),
        const SizedBox(height: 26),
        if (step != _Step.found)
          Semantics(
            liveRegion: true,
            child: Text(
              nothing
                  ? l10n.cantFindDeviceHint
                  : step == _Step.pairing
                      ? l10n.holdOn
                      : l10n.holdPendantClose,
              textAlign: TextAlign.center,
              style: OmiType.subhead.copyWith(height: 1.45, color: OmiColors.textSecondary),
            ),
          ),
        if (step == _Step.found || step == _Step.pairing) ...[
          const SizedBox(height: 22),
          for (final (i, device) in provider.deviceList.indexed)
            PendantFoundRow(
              key: ValueKey('pair_found_${device.id}'),
              device: device,
              first: i == 0,
              pairing: provider.connectingToDeviceId == device.id,
              busy: provider.connectingToDeviceId != null,
              onPair: () => _pair(device),
            ),
        ],
        if (nothing) ...[
          const SizedBox(height: 22),
          OmiButton(
            key: const Key('pair_scan_again'),
            label: l10n.scanAgainV3,
            expand: true,
            onPressed: () {
              OmiHaptics.selection();
              _provider.cancelActiveScan();
              unawaited(_scan());
            },
          ),
          const SizedBox(height: 8),
          OmiButton.secondary(
            key: const Key('pair_how_to'),
            label: l10n.howToPairV3,
            expand: true,
            onPressed: () => ConnectionGuideSheet.show(context),
          ),
        ],
        const Spacer(),
        if (step != _Step.pairing)
          OnboardingLink(key: const Key('pair_other_devices'), label: l10n.otherDevicesV3, onTap: _otherDevices),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Paired: the pendant with its light blue, "Your pendant's connected", its name and charge, and
  /// Start recording.
  Widget _pairedStep(AppLocalizations l10n, OnboardingProvider provider) {
    final name = provider.deviceName.trim().isEmpty ? l10n.omiPendantName : provider.deviceName.trim();
    final battery = provider.batteryPercentage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const Center(child: OmiPendantPhoto(led: OmiPendantLed.blue, size: 140)),
        const SizedBox(height: 26),
        OnboardingHeader(
          title: l10n.pendantConnected,
          subtitle: battery >= 0 ? l10n.pendantConnectedBody(name, battery) : l10n.pendantConnectedBodyNoBattery(name),
        ),
        const Spacer(),
        OmiButton(
          key: const Key('pair_start_recording'),
          label: l10n.startRecordingV3,
          expand: true,
          onPressed: () => unawaited(_startRecording()),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
