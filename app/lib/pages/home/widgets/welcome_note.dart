import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';

/// A local welcome from the developers, kept separate from recorded memories.
/// Available immediately, even before a first recording finishes processing.
class WelcomeNoteTile extends StatelessWidget {
  const WelcomeNoteTile({super.key});

  static String get preferenceKey => 'onboarding/welcomeNote/${SharedPreferencesUtil().uid}';

  @override
  Widget build(BuildContext context) => OmiCard(
        key: const Key('home_welcome_note'),
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(omiPageRoute(builder: (_) => const WelcomeNotePage())),
        semanticLabel: context.l10n.welcomeToOmi,
        child: Row(
          children: [
            const Icon(Icons.waving_hand_outlined, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Text(context.l10n.welcomeToOmi, style: OmiType.subhead)),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      );
}

class WelcomeNotePage extends StatelessWidget {
  const WelcomeNotePage({super.key});

  Future<void> _openCommunity(BuildContext context) async {
    try {
      if (await launchUrl(Uri.parse('https://discord.omi.me'), mode: LaunchMode.externalApplication)) return;
    } catch (error) {
      Logger.warning('Could not open the Omi community: $error');
    }
    if (context.mounted) OmiFeedback.info(context, context.l10n.somethingWentWrong);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: OmiColors.surface0,
        appBar: OmiAppBar(title: Text(context.l10n.welcomeToOmi)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(OmiSize.screenMargin),
            children: [
              Text(context.l10n.welcomeNoteBody, style: OmiType.body.copyWith(height: 1.5)),
              const SizedBox(height: 24),
              OmiButton.secondary(
                key: const Key('welcome_note_discord'),
                label: context.l10n.joinCommunity,
                onPressed: () => _openCommunity(context),
              ),
            ],
          ),
        ),
      );
}
