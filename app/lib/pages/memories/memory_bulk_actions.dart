import 'package:flutter/material.dart';

import 'package:omi/backend/schema/memory.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// The end of the Memories list: make every memory private (or public again when all of them
/// already are) and delete them all. Each says what happened only once the server accepted it.
class MemoryBulkActions extends StatelessWidget {
  const MemoryBulkActions({super.key, required this.provider});

  final MemoriesProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final anyPublic = provider.memories.any((m) => !m.deleted && m.visibility != MemoryVisibility.private);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        children: [
          _Link(
            key: Key(anyPublic ? 'memories_make_private' : 'memories_make_public'),
            label: anyPublic ? l10n.makeAllPrivate : l10n.makeAllPublic,
            onTap: () => setAllMemoriesVisibility(context, provider, private: anyPublic),
          ),
          _Link(
            key: const Key('memories_delete_all'),
            label: l10n.deleteAllMemories,
            onTap: () => confirmDeleteAllMemories(context, provider),
          ),
        ],
      ),
    );
  }
}

/// Makes every memory private (or public), then says so, or that it did not work.
Future<void> setAllMemoriesVisibility(BuildContext context, MemoriesProvider provider, {required bool private}) async {
  OmiHaptics.selection();
  final updated = await provider.updateAllMemoriesVisibility(private);
  if (!context.mounted) return;
  final l10n = context.l10n;
  if (updated) {
    OmiFeedback.confirm(context, private ? l10n.allMemoriesPrivateResult : l10n.allMemoriesPublicResult);
  } else {
    OmiFeedback.error(context, l10n.somethingWentWrong);
  }
}

/// Deletes every memory after a confirmation, since it cannot be undone (docs/ux-contract.md §4).
Future<void> confirmDeleteAllMemories(BuildContext context, MemoriesProvider provider) async {
  final l10n = context.l10n;
  if (provider.memories.isEmpty) {
    OmiFeedback.info(context, l10n.noMemoriesToDelete);
    return;
  }
  final confirmed = await showOmiConfirm(
    context,
    title: l10n.clearMemoryTitle,
    message: l10n.clearMemoryMessage,
    confirmLabel: l10n.clearMemoryButton,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final cleared = await provider.deleteAllMemories();
  if (!context.mounted) return;
  if (cleared) {
    OmiFeedback.confirm(context, context.l10n.memoryClearedSuccess);
  } else {
    OmiFeedback.error(context, context.l10n.somethingWentWrong);
  }
}

/// A quiet underlined link at 15 pt, 44 pt tall.
class _Link extends StatelessWidget {
  const _Link({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: OmiSize.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: OmiType.subhead.copyWith(
                  color: OmiColors.textSecondary,
                  height: 1.4,
                  decoration: TextDecoration.underline,
                  decorationColor: OmiColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
