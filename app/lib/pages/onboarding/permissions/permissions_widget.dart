import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Allow the microphone (v3 `perm`): the mic in an 84 pt ring, why Omi needs it, and Allow
/// microphone, which asks the system and moves on whatever the answer (docs/ux-contract.md §15).
/// Location and notifications are asked where they are used, not here.
class PermissionsWidget extends StatelessWidget {
  final VoidCallback goNext;

  /// The system prompt; tests replace it.
  final Future<void> Function()? requestMicrophone;

  const PermissionsWidget({super.key, required this.goNext, this.requestMicrophone});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          const SizedBox(height: 26),
          const OnboardingIconRing(glyph: OmiGlyphs.micLine),
          const SizedBox(height: 30),
          OnboardingHeader(title: l10n.allowTheMicrophone, subtitle: l10n.allowMicrophoneWhy),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_permissions_continue'),
            label: l10n.allowMicrophone,
            expand: true,
            onPressed: () async {
              OmiHaptics.selection();
              try {
                await (requestMicrophone ?? () => Permission.microphone.request())();
              } catch (_) {
                // Moves on either way: the phone asks again the first time it records.
              }
              goNext();
            },
          ),
        ],
      ),
    );
  }
}
