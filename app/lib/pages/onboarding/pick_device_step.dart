import 'package:flutter/material.dart';

import 'package:omi/pages/devices/devices_screen.dart' show OmiRadioRing;
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_service.dart';

/// How will you record? (v3 `source`): "I have an Omi" (pendant, Omi Glass or Apple Watch) or "Just
/// this phone for now", and a link for other wearables, which picks the first. Continue says which
/// was picked: a wearable goes on to setting it up (turn it on, Bluetooth, pair, its button), the
/// phone to the microphone.
class OnboardingPickDeviceStep extends StatefulWidget {
  const OnboardingPickDeviceStep({super.key, required this.goNext, this.wearable = false});

  /// Continue, with whether a wearable was picked.
  final ValueChanged<bool> goNext;

  /// Picked when the step opens (back from the pendant steps keeps the choice).
  final bool wearable;

  @override
  State<OnboardingPickDeviceStep> createState() => _OnboardingPickDeviceStepState();
}

class _OnboardingPickDeviceStepState extends State<OnboardingPickDeviceStep> {
  late bool _wearable = widget.wearable;

  void _continue() {
    OmiHaptics.selection();
    widget.goNext(_wearable);
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
            child: OnboardingLink(
              key: const Key('onboarding_other_device'),
              label: l10n.iUseAnotherDevice,
              onTap: () {
                OmiHaptics.selection();
                setState(() => _wearable = true);
              },
            ),
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
