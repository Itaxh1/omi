import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/phone_call.dart';
import 'package:omi/pages/devices/pair_device_sheet.dart';
import 'package:omi/pages/devices/light_legend_page.dart';
import 'package:omi/pages/home/device.dart';
import 'package:omi/pages/home/firmware_update.dart';
import 'package:omi/pages/home/omiglass_ota_update.dart';
import 'package:omi/pages/home/widgets/phone_capture.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/pages/home/widgets/idle_capture_card.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/pages/settings/device/device_control_sheets.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/phone_call_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/device.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/firmware_update_build_policy.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_service.dart';

/// Devices (v3 `devs`): a Bluetooth warning when it is off, the device in use (its photo, name,
/// state, "What the light means" and Pause), "Record from" with each source, the pendant's button,
/// firmware, the sync line, Add a device, and the devices Omi also works with.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final devices = context.watch<DeviceProvider>();
    final capture = context.watch<CaptureProvider>();
    final sync = context.watch<SyncProvider>();
    final call = context.select<PhoneCallProvider, PhoneCallState>((p) => p.callState);
    final paired = devices.pairedDevice;
    final hasPaired = paired != null && paired.id.isNotEmpty;
    final state = HomeListeningLabel.simpleStateOf(capture, call);
    final phoneLive = capture.liveCaptureSource == 'phone' ||
        capture.recordingState == RecordingState.record ||
        capture.isPhoneMicPaused;
    final deviceLive = hasPaired && devices.isConnected && !phoneLive && state != ListeningLabelState.idle;
    final btOff = BluetoothReadiness.instance.state == BluetoothAdapterState.off;

    String status() {
      if (!hasPaired) return l10n.microphone;
      if (devices.isConnecting) return l10n.deviceConnecting;
      if (!devices.isConnected) return l10n.disconnected;
      final battery = devices.batteryLevel;
      return battery > 0 ? '${l10n.connected} · $battery%' : l10n.connected;
    }

    final phoneName = PlatformService.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone;
    final name = hasPaired ? paired.name : phoneName;
    final pairedPhoto = !hasPaired
        ? null
        : paired.type.name == 'omi'
            ? OmiOrb(size: 64, live: deviceLive)
            : Image.asset(DeviceUtils.getDeviceImageFromBtDevice(paired), fit: BoxFit.contain);
    final muted = state == ListeningLabelState.muted;
    String pairedDetail() {
      if (deviceLive) return muted ? l10n.paused : l10n.recordingNow;
      final kind = paired!.type.name == 'omi' ? l10n.pendantKind : null;
      final tail = devices.isConnected
          ? (devices.batteryLevel > 0 ? '${devices.batteryLevel}%' : l10n.connected.toLowerCase())
          : l10n.notConnectedV3.toLowerCase();
      return kind == null ? tail : '$kind · $tail';
    }

    return Scaffold(
      backgroundColor: OmiColors.surface0,
      // v8.17: the header's bulb is What the light means.
      appBar: OmiScreenHeader(
        title: l10n.devices,
        trailing: hasPaired
            ? OmiRingButton.glass(
                key: const Key('devices_lights'),
                glyph: OmiGlyphs.bulb,
                label: l10n.whatTheLightMeans,
                onPressed: () => showLightLegend(context),
              )
            : null,
      ),
      bottomNavigationBar: const ListeningStrip(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 4, OmiSize.screenMargin, 20),
        children: [
          if (btOff && hasPaired) ...[
            _BluetoothOff(onTurnOn: () => BluetoothReadiness.instance.ensureReady(BluetoothUse.connection)),
            const SizedBox(height: 18),
          ],
          // `.dcard`: the device in use in an outlined card, its photo, name and state.
          Semantics(
            button: hasPaired,
            child: GestureDetector(
              key: const Key('devices_current'),
              behavior: HitTestBehavior.opaque,
              onTap: hasPaired ? () => routeToPage(context, const ConnectedDevice()) : null,
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OmiColors.palette.isLight
                      ? OmiColors.surface0
                      : Color.alphaBlend(OmiColors.textPrimary.withValues(alpha: 0.06), OmiColors.surface0),
                  borderRadius: const BorderRadius.all(Radius.circular(24)),
                  border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 64,
                      child: pairedPhoto ??
                          Center(child: OmiGlyph(OmiGlyphs.devicePhone, size: 40, color: OmiColors.cement)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OmiType.answer
                                  .copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.35)),
                          const SizedBox(height: 2),
                          Text(status(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OmiType.cardSubtitle.copyWith(height: 1.35, color: OmiColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          OmiSectionLabel(
            title: l10n.recordFrom,
            // The rows below: the pendant and this phone.
            detail: hasPaired ? l10n.pairedCountV3(2) : null,
            top: 26,
          ),
          if (hasPaired)
            _SourceRow(
              key: const Key('devices_paired_device'),
              name: paired.name,
              detail: pairedDetail(),
              visual: SizedBox.square(dimension: 40, child: pairedPhoto),
              selected: deviceLive || (!phoneLive && devices.isConnected),
              onTap: () {
                if (phoneLive && devices.isConnected) {
                  unawaited(IdleCaptureCard.startWearable(context));
                } else {
                  routeToPage(context, const ConnectedDevice());
                }
              },
            ),
          _SourceRow(
            key: const Key('devices_this_phone'),
            name: phoneName,
            detail: phoneLive ? (muted ? l10n.paused : l10n.recordingNow) : l10n.builtInMicV3,
            visual: OmiGlyph(OmiGlyphs.devicePhone, size: 22, color: OmiColors.textPrimary),
            selected: phoneLive || !hasPaired,
            onTap: phoneLive ? null : () => PhoneCapture.start(context),
          ),
          if (hasPaired) ...[
            OmiSectionLabel(title: l10n.buttonSectionV3, top: 26),
            const _DoubleTapRow(),
            OmiSectionLabel(title: l10n.firmware, top: 26),
            _FirmwareRow(devices: devices),
          ],
          if (sync.isSyncing)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                l10n.syncingMinutesFrom((sync.missingWalsInSeconds / 60).ceil(), hasPaired ? paired.name : 'Omi'),
                style: OmiType.subhead.copyWith(height: 1.6, color: OmiColors.textSecondary),
              ),
            ),
          // `.dv2add`: a + tile and the words, as a row.
          Semantics(
            button: true,
            label: l10n.addADevice,
            excludeSemantics: true,
            child: OmiPressable(
              key: const Key('devices_add'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(PairDeviceSheet.show(context)),
              child: Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 10),
                child: Row(
                  children: [
                    _DeviceTile(child: OmiGlyph(OmiGlyphs.plusLine, size: 20, color: OmiColors.textPrimary)),
                    const SizedBox(width: 14),
                    Text(l10n.addADevice, style: OmiType.askBar.copyWith(height: 1.4)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              l10n.alsoWorksWith,
              style: OmiType.detail.copyWith(height: 1.6, color: OmiColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// The double-tap action in words, as device settings says it.
  static String doubleTapLabel(BuildContext context, int action) => switch (action) {
        1 => context.l10n.deviceOnboardingMuteUnmute,
        2 => context.l10n.starConversation,
        _ => context.l10n.endConversation,
      };
}

/// "Bluetooth is off" (`.btw`): what it means and Turn on.
class _BluetoothOff extends StatelessWidget {
  const _BluetoothOff({required this.onTurnOn});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const Key('devices_bluetooth_off'),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: OmiColors.textPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: OmiGlyph(OmiGlyphs.bluetooth, size: 18, color: OmiColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.bluetoothIsOff, style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 2),
                Text(l10n.bluetoothOffExplainer,
                    style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _PillButton(label: l10n.turnOn, filled: true, onPressed: onTurnOn),
          ),
        ],
      ),
    );
  }
}

/// A 34 pt pill (`.da`, `#btOn`): outlined, or ink with paper words.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed, this.filled = false});

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: OmiPressable(
        onTap: onPressed,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? OmiColors.accent : null,
            borderRadius: OmiRadius.pillAll,
            border: filled ? null : Border.all(color: OmiColors.textPrimary),
          ),
          child: Text(
            label,
            style: OmiType.detail.copyWith(
              fontWeight: FontWeight.w600,
              color: filled ? OmiColors.onAccent : OmiColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A source (v8.17 `.drow.dv2`): a 44 pt tile with the device's photo or glyph, the name at
/// 16.5/500 (600 when current) over its state at 13 pt, and a check on the one in use.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.name,
    required this.detail,
    required this.visual,
    required this.selected,
    this.onTap,
  });

  final String name;
  final String detail;
  final Widget visual;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$name, $detail',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                OmiHaptics.selection();
                onTap!();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Row(
            children: [
              _DeviceTile(child: visual),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OmiType.askBar
                            .copyWith(height: 1.4, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OmiGlyph(OmiGlyphs.tick, size: 19, color: OmiColors.textPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 44 pt tile of a device row (`.dt`): paper, a 12 % outline, 14 pt corners.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OmiColors.palette.isLight
            ? OmiColors.surface0
            : Color.alphaBlend(OmiColors.textPrimary.withValues(alpha: 0.06), OmiColors.surface0),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

/// A setting row (`.row`): the name at 17/500 and its value on the right in 13 pt.
class _ValueRow extends StatelessWidget {
  const _ValueRow({super.key, required this.title, required this.value, required this.onTap});

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$title, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                OmiHaptics.selection();
                onTap!();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Row(
            children: [
              Expanded(child: Text(title, style: OmiType.body.copyWith(fontWeight: FontWeight.w500, height: 1.3))),
              const SizedBox(width: 14),
              Text(value, style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary)),
              // `#dtap .tm::after`: a quiet ›.
              if (onTap != null) Text('  ›', style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pendant's double tap (`#dtap`): what it does, and the sheet to change it.
class _DoubleTapRow extends StatefulWidget {
  const _DoubleTapRow();

  @override
  State<_DoubleTapRow> createState() => _DoubleTapRowState();
}

class _DoubleTapRowState extends State<_DoubleTapRow> {
  @override
  Widget build(BuildContext context) {
    final prefs = SharedPreferencesUtil();
    return _ValueRow(
      key: const Key('devices_double_tap'),
      title: context.l10n.doubleTapV3,
      value: DevicesScreen.doubleTapLabel(context, prefs.doubleTapAction),
      onTap: () async {
        final action = await showDoubleTapActionSheet(context, current: prefs.doubleTapAction);
        if (action != null && mounted) setState(() => prefs.doubleTapAction = action);
      },
    );
  }
}

/// Firmware (`.fw`): up to date, or "Update ready · Version 2.2.0" with Update.
class _FirmwareRow extends StatelessWidget {
  const _FirmwareRow({required this.devices});

  final DeviceProvider devices;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ready = devices.havingNewFirmware;
    if (!ready) {
      return _ValueRow(
        key: const Key('devices_firmware_status'),
        title: l10n.upToDate,
        value: l10n.firmwareVersionLine(devices.currentFirmwareVersion),
        onTap: null,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ready ? l10n.updateReady : l10n.upToDate,
                    style: OmiType.callout.copyWith(fontWeight: FontWeight.w500, height: 1.3)),
                const SizedBox(height: 2),
                Text(
                  l10n.firmwareVersionLine(ready ? devices.latestFirmwareVersion : devices.currentFirmwareVersion),
                  style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary),
                ),
              ],
            ),
          ),
          if (ready)
            _PillButton(
              filled: true,
              label: l10n.update,
              onPressed: () {
                final glass = FirmwareUpdateBuildPolicy.current.isOpenGlassDevice(devices.connectedDevice);
                routeToPage(
                  context,
                  glass
                      ? OmiGlassOtaUpdate(
                          device: devices.pairedDevice, latestFirmwareDetails: devices.latestOmiGlassFirmwareDetails)
                      : FirmwareUpdate(device: devices.pairedDevice),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// A radio ring (`.r`): 20 pt, ink outline; selected, a 10 pt ink dot inside.
class OmiRadioRing extends StatelessWidget {
  const OmiRadioRing({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: OmiColors.textPrimary, width: 1.5)),
      child: selected
          ? Container(
              width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: OmiColors.textPrimary))
          : null,
    );
  }
}
