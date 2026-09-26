import 'package:flutter/material.dart';

import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Ask before the first question (v4 Ask hello): at the foot of the page, the Omi mark, what you
/// can ask and where answers come from, then suggestions as a two-column grid of cards. Starters
/// stay editable in the composer; choosing one never sends a message.
class ChatStarters extends StatelessWidget {
  final bool hasExistingData;
  final bool isConnected;
  final ValueChanged<String> onSelected;

  const ChatStarters({super.key, required this.hasExistingData, required this.isConnected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return Center(child: Text(context.l10n.noInternetConnection, textAlign: TextAlign.center));
    }
    final l10n = context.l10n;
    // Rev 3 Ask: with something heard, questions about it; before that, what Omi can do.
    final prompts = hasExistingData
        ? [
            ('today', l10n.askStarterToday, Icons.bolt_rounded),
            ('open', l10n.askStarterOpen, Icons.checklist_rounded),
            ('people', l10n.askStarterPeople, Icons.people_alt_outlined),
            ('improve', l10n.chatStarterPrompt('improve'), Icons.trending_up_rounded),
          ]
        : [
            ('capabilities', l10n.chatStarterPrompt('capabilities'), Icons.auto_awesome_outlined),
            ('goal', l10n.chatStarterPrompt('goal'), Icons.flag_outlined),
          ];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, OmiSpacing.md, 18, OmiSpacing.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - OmiSpacing.md * 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OmiRingLogo(size: 40, mode: OmiRingMode.orbit, loops: 1),
              const SizedBox(height: 18),
              Semantics(
                header: true,
                child: OmiBalancedText(
                  l10n.askEmptyTitle,
                  style: OmiType.title1.copyWith(fontSize: 30, height: 35 / 30, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: OmiSpacing.xs),
              OmiBalancedText(
                l10n.askEmptySubtitle,
                style: OmiType.subhead.copyWith(color: OmiColors.textSecondary, height: 21 / 15),
              ),
              const SizedBox(height: 18),
              for (var row = 0; row < prompts.length; row += 2) ...[
                if (row > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < 2; column++) ...[
                        if (column > 0) const SizedBox(width: 10),
                        Expanded(
                          child: row + column < prompts.length
                              ? _SuggestionCard(
                                  key: ValueKey('chat_starter_${prompts[row + column].$1}'),
                                  label: prompts[row + column].$2,
                                  icon: prompts[row + column].$3,
                                  onTap: () => onSelected(prompts[row + column].$2),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A question to start with (v4 Ask suggestion): a card with its icon on a tile and the question.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: OmiPressable(
        onTap: () {
          OmiHaptics.selection();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: OmiColors.surface1,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(color: OmiColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: OmiColors.surface2,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                child: Icon(icon, size: 17, color: OmiColors.textPrimary),
              ),
              const SizedBox(height: OmiSpacing.sm),
              Text(label, style: OmiType.subhead.copyWith(fontWeight: FontWeight.w600, height: 20 / 15)),
            ],
          ),
        ),
      ),
    );
  }
}
