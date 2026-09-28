import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/providers/auth_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// The data-and-AI consent step. Agree continues; "Use a Different Account" signs out and goes
/// back to sign-in, so someone on the wrong account (or who does not consent) is never stuck here.
class AiConsentWidget extends StatefulWidget {
  final VoidCallback onAgree;
  final FutureOr<void> Function() onUseDifferentAccount;

  const AiConsentWidget({super.key, required this.onAgree, required this.onUseDifferentAccount});

  @override
  State<AiConsentWidget> createState() => _AiConsentWidgetState();
}

class _AiConsentWidgetState extends State<AiConsentWidget> {
  final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer();
  final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    final provider = context.read<AuthenticationProvider>();
    _privacyRecognizer.onTap = provider.openPrivacyPolicy;
    _termsRecognizer.onTap = provider.openTermsOfService;
  }

  @override
  void dispose() {
    _privacyRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // v3 "Three things to know": numbered, then I agree and the privacy policy.
    return OnboardingStep(
      card: OnboardingCard(
        crossAxisAlignment: CrossAxisAlignment.start,
        content: [
          OnboardingHeader(title: l10n.consentThreeThings),
          const SizedBox(height: 12),
          _ConsentRow(number: 1, title: l10n.consentChooseTitle, body: l10n.consentChooseBody),
          _ConsentRow(number: 2, title: l10n.consentAiTitle, body: l10n.consentProcessorsBody),
          _ConsentRow(number: 3, title: l10n.consentDeleteTitle, body: l10n.consentControlBody, last: true),
        ],
        footer: [
          OmiButton(
            key: const Key('ai_consent_agree'),
            label: l10n.iAgree,
            expand: true,
            onPressed: () {
              OmiHaptics.selection();
              widget.onAgree();
            },
          ),
          OnboardingLink(label: l10n.readThePrivacyPolicy, onTap: _privacyRecognizer.onTap!),
        ],
      ),
    );
  }
}

/// One of the three things (`.obrow`): its number in the faint ink, the point at 17/600 and what it
/// means at 15 pt; a hairline under it.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.number, required this.title, required this.body, this.last = false});

  final int number;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: OmiColors.divider))),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text('$number',
                    style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, color: OmiColors.faint)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: OmiType.body.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                  const SizedBox(height: 3),
                  Text(body, style: OmiType.subhead.copyWith(color: OmiColors.textSecondary, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
