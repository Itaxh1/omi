import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/providers/auth_provider.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

class AuthComponent extends StatefulWidget {
  final VoidCallback onSignIn;

  const AuthComponent({super.key, required this.onSignIn});

  @override
  State<AuthComponent> createState() => _AuthComponentState();
}

class _AuthComponentState extends State<AuthComponent> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final link = OmiType.fine.copyWith(
      color: OmiColors.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: OmiColors.faint,
    );
    // v3 Welcome: the mark, "Remember every conversation.", what Omi does, then Continue with Apple
    // and Google and the fine print. One screen: signing in is the first thing asked.
    return Consumer<AuthenticationProvider>(
      builder: (context, provider, child) {
        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 12, OmiSize.screenMargin, 0),
                sliver: SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // `.welcome`: the mark 116 pt down, the headline 35 pt under it.
                      const SizedBox(height: 104),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: OmiRingLogo(size: 40, mode: OmiRingMode.wave, loops: 2),
                      ),
                      const SizedBox(height: 35),
                      Semantics(
                        header: true,
                        child: Text(l10n.welcomeRememberTitle, style: OnboardingHeader.titleStyle),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.welcomeListensSubtitle, style: OnboardingHeader.bodyStyle),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: provider.loading ? const Center(child: OmiSpinner(size: OmiSpinnerSize.small)) : null,
                      ),
                      // A local_dev build can't finish Apple or Google sign-in, so it shows only its own.
                      if (!provider.isLocalDevProfile && (Platform.isIOS || Platform.isAndroid)) ...[
                        OmiButton(
                          key: const Key('auth_apple'),
                          label: l10n.continueWithApple,
                          expand: true,
                          onPressed: () {
                            OmiHaptics.selection();
                            provider.onAppleSignIn(widget.onSignIn);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (!provider.isLocalDevProfile)
                        OmiButton.secondary(
                          key: const Key('auth_google'),
                          label: l10n.continueWithGoogle,
                          expand: true,
                          onPressed: () {
                            OmiHaptics.selection();
                            provider.onGoogleSignIn(widget.onSignIn);
                          },
                        ),
                      // Local development sign-in. Only rendered for a local_dev build: community
                      // builds cannot complete a real OAuth flow. Never shown in a production build.
                      if (provider.isLocalDevProfile) ...[
                        OmiButton.tertiary(
                          label:
                              'Sign in (local dev)', // omi-ux-allow: hardcoded-text -- local_dev builds only, never shipped
                          expand: true,
                          onPressed: () {
                            OmiHaptics.selection();
                            provider.onLocalDevSignIn(widget.onSignIn);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: OmiType.fine.copyWith(color: OmiColors.faint),
                          children: [
                            TextSpan(text: l10n.byContinuingAgree),
                            TextSpan(
                              text: l10n.termsOfService,
                              style: link,
                              recognizer: TapGestureRecognizer()..onTap = provider.openTermsOfService,
                            ),
                            TextSpan(text: l10n.and),
                            TextSpan(
                              text: l10n.privacyPolicy,
                              style: link,
                              recognizer: TapGestureRecognizer()..onTap = provider.openPrivacyPolicy,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      // Inside the column: a sliver's trailing padding would sit past the screen.
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
