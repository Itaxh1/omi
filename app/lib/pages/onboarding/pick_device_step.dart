import 'package:flutter/material.dart';

import 'package:omi/pages/capture/connect.dart';
import 'package:omi/pages/devices/devices_screen.dart' show OmiRadioRing;
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_service.dart';

/// How will you record? (v3 `source`): "I have an Omi" (pendant, Omi Glass or Apple Watch) or "Just
/// this phone for now", and a link for other wearables. With a wearable, Continue opens the connect
/// flow (turn it on, find it, pair it) and onboarding moves on once it is paired and tested, or set
/// up later; with the phone it moves on straight away. Backing out of the connect flow returns here.
class OnboardingPickDeviceStep extends StatefulWidget {
  const OnboardingPickDeviceStep({super.key, required this.goNext});

  final VoidCallback goNext;

  @override
  State<OnboardingPickDeviceStep> createState() => _OnboardingPickDeviceStepState();
}

class _OnboardingPickDeviceStepState extends State<OnboardingPickDeviceStep> {
  bool _wearable = false;

  Future<void> _connect() async {
    OmiHaptics.selection();
    final advance = await Navigator.of(context).push<bool>(
      omiPageRoute(
        builder: (routeContext) => ConnectDevicePage(onDone: () => Navigator.of(routeContext).pop(true)),
      ),
    );
    if (advance == true) widget.goNext();
  }

  void _continue() {
    if (_wearable) {
      _connect();
    } else {
      OmiHaptics.selection();
      widget.goNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          OnboardingHeader(title: l10n.howWillYouRecord, subtitle: l10n.addOrSwitchDevicesAnyTime),
          const SizedBox(height: 2),
          _Option(
            key: const Key('onboarding_have_omi'),
            title: l10n.iHaveAnOmi,
            detail: l10n.iHaveAnOmiDetail,
            selected: _wearable,
            onTap: () => setState(() => _wearable = true),
          ),
          _Option(
            key: const Key('onboarding_use_phone'),
            title: l10n.justThisPhoneForNow,
            detail: PlatformService.isIOS ? l10n.useTheIphoneMicrophone : l10n.useThePhoneMicrophone,
            selected: !_wearable,
            onTap: () => setState(() => _wearable = false),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OnboardingLink(label: l10n.iUseAnotherDevice, onTap: _connect),
          ),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_pick_continue'),
            label: l10n.continueButton,
            expand: true,
            onPressed: _continue,
          ),
        ],
      ),
    );
  }
}

/// A choice (`.obopt`): a radio ring, the choice at 17/600 over what it means; outlined in ink
/// when chosen.
class _Option extends StatelessWidget {
  const _Option({super.key, required this.title, required this.detail, required this.selected, required this.onTap});

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$title, $detail',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            OmiHaptics.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(color: selected ? OmiColors.textPrimary : OmiColors.outline, width: 1.5),
            ),
            child: Row(
              children: [
                OmiRadioRing(selected: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
                      const SizedBox(height: 2),
                      Text(detail, style: OmiType.detail.copyWith(color: OmiColors.textSecondary, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
