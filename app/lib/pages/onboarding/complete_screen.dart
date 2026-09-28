import 'package:flutter/material.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/pages/onboarding/permissions/onboarding_permissions_panel.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/ui/ui.dart';

import 'package:omi/utils/l10n_extensions.dart';

class OnboardingCompleteScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingCompleteScreen({super.key, required this.onComplete});

  @override
  State<OnboardingCompleteScreen> createState() => _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends State<OnboardingCompleteScreen> with SingleTickerProviderStateMixin {
  // v2 entrance: content rises 12pt and fades in (a plain fade under Reduce Motion).
  late final AnimationController _entrance =
      AnimationController(duration: const Duration(milliseconds: 620), vsync: this);
  late final Animation<double> _fade = CurvedAnimation(parent: _entrance, curve: OmiMotion.springCurve);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = SharedPreferencesUtil().givenName.trim();
    // v3 `done`: the mark, "You're set, Alex.", what happens now, the background note, Open Omi.
    return ColoredBox(
      color: OmiColors.surface0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 12, OmiSize.screenMargin, 20),
          child: AnimatedBuilder(
            animation: _fade,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(offset: Offset(0, 12 * (1 - _fade.value)), child: child),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // As Welcome: the mark 116 pt down, the headline 35 pt under it.
                        const SizedBox(height: 104),
                        const OmiRingLogo(size: 40, mode: OmiRingMode.wave),
                        const SizedBox(height: 35),
                        Semantics(
                          header: true,
                          child: Text(
                            name.isEmpty ? l10n.youreSet : l10n.youreSetName(name),
                            style: OnboardingHeader.titleStyle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(l10n.youreSetBody, style: OnboardingHeader.bodyStyle),
                        const SizedBox(height: 22),
                        // `.fwwarn`: a quiet note with a rule on its left.
                        Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration:
                              BoxDecoration(border: Border(left: BorderSide(color: OmiColors.textPrimary, width: 1.5))),
                          child: Text(l10n.keepAppRunningNote,
                              style: OmiType.detail.copyWith(height: 1.45, color: OmiColors.ink80)),
                        ),
                        // What the design leaves out: notifications, places and (Android) running in
                        // the background, each with why and its own Allow. Open Omi never prompts
                        // (docs/ux-contract.md §15); Settings → Permissions has the same rows.
                        const SizedBox(height: 26),
                        const OnboardingPermissionsPanel(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OmiButton(
                  key: const Key('onboarding_complete_start'),
                  label: l10n.openOmi,
                  expand: true,
                  onPressed: () {
                    OmiHaptics.success();
                    widget.onComplete();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
