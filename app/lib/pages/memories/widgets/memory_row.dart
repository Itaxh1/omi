import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/http/api/memories.dart';
import 'package:omi/backend/schema/memory.dart';
import 'package:omi/pages/memories/widgets/memory_delete_undo.dart';
import 'package:omi/pages/memories/widgets/memory_edit_sheet.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/widgets/extensions/string.dart';

/// One memory (v3 `.mitem`): the words at 17 on a 1.4 line, when it was learned under them, a
/// hairline below. Tapping edits it; a row that cannot be edited (past knowledge) opens read-only.
/// A locked memory is blurred and opens the plan page. Knowledge-ledger rows also carry their
/// review controls: Right / Wrong, Don't use / Allow use, and Undo for a replaced fact.
class MemoryRow extends StatelessWidget {
  const MemoryRow({super.key, required this.memory, required this.provider, this.onEdit});

  final Memory memory;
  final MemoriesProvider provider;

  /// Opens the editor; the quick edit sheet by default.
  final VoidCallback? onEdit;

  /// When Omi learned [memory] (v3 `.mitem small`): "Today, 12:40", "Yesterday, 9:05", "Last
  /// Thursday", then the date; "Today, from the 12:40 conversation" when the conversation it came
  /// from is loaded.
  static String when(BuildContext context, Memory memory, {DateTime? now}) {
    final l10n = context.l10n;
    final format = OmiDateFormat.of(context);
    final at = memory.createdAt.toLocal();
    final n = now ?? DateTime.now();
    final days = DateTime(n.year, n.month, n.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    final String day;
    if (days <= 0) {
      day = l10n.today;
    } else if (days == 1) {
      day = l10n.yesterday;
    } else if (days < 7) {
      return l10n.lastWeekday(DateFormat.EEEE(format.localeName).format(at));
    } else {
      return (at.year == n.year ? DateFormat.MMMd(format.localeName) : DateFormat.yMMMd(format.localeName)).format(at);
    }
    final id = memory.conversationId;
    final conversations = context.read<ConversationProvider?>();
    final source = id == null ? null : conversations?.conversations.where((c) => c.id == id).firstOrNull;
    if (source != null) {
      return l10n.memoryFromConversation(day, format.time((source.startedAt ?? source.createdAt).toLocal()));
    }
    return l10n.dayAtTime(day, format.time(at));
  }

  void _open(BuildContext context) {
    if (memory.isLocked) {
      if (!context.read<UsageProvider>().showSubscriptionUI) {
        // No upgrade to offer: still let the reader open what is visible.
        showMemoryQuickEditSheet(context, memory, provider, readOnly: true);
        return;
      }
      PlatformManager.instance.analytics.paywallOpened('Memory');
      routeToPage(context, const UsagePage(showUpgradeDialog: true));
      return;
    }
    PlatformManager.instance.analytics.memoryListItemClicked(memory);
    if (!memoryIsEditable(memory)) {
      showMemoryQuickEditSheet(context, memory, provider, readOnly: true);
      return;
    }
    (onEdit ?? () => showMemoryQuickEditSheet(context, memory, provider))();
  }

  @override
  Widget build(BuildContext context) {
    final body = memory.isLedgerPlaybook ? (memory.ledgerBody ?? '').trim() : '';
    Widget words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(memory.content.decodeString.trim(), style: OmiType.body.copyWith(height: 1.4)),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(body, style: OmiType.subhead.copyWith(height: 1.4, color: OmiColors.textSecondary)),
        ],
      ],
    );
    if (memory.isLocked) {
      words = ExcludeSemantics(
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: words),
      );
    }
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: memory.isLocked ? context.l10n.upgradeToUnlimited : null,
            child: InkWell(
              key: ValueKey('memory_${memory.id}'),
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.only(top: 13, bottom: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: words),
                    const SizedBox(height: 3),
                    Text(
                      MemoryRow.when(context, memory),
                      style: OmiType.footnote.copyWith(height: 1.4, color: OmiColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!memory.isLocked) _LedgerControls(memory: memory, provider: provider),
        ],
      ),
    );
  }
}

/// The knowledge-ledger controls under a row, when the row has any.
class _LedgerControls extends StatelessWidget {
  const _LedgerControls({required this.memory, required this.provider});

  final Memory memory;
  final MemoriesProvider provider;

  static bool _canReview(Memory memory) =>
      memory.isKnowledgeLedger &&
      memory.invalidAt == null &&
      (memory.supersededBy == null || memory.supersededBy!.trim().isEmpty);

  static bool _canSetUse(Memory memory) {
    if (memory.deleted || memory.invalidAt != null) return false;
    if ((memory.supersededBy ?? '').trim().isNotEmpty) return false;
    if (memory.ledgerStatus != null && memory.ledgerStatus != 'active') return false;
    if (memory.isKnowledgeLedger && !memory.isCurrentKnowledgeLedgerRow) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final review = _canReview(memory);
    final use = provider.memoryBeliefEnabled && _canSetUse(memory);
    final revert = provider.canRevertSupersededFact(memory);
    if (!review && !use && !revert) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListenableBuilder(
        listenable: provider,
        builder: (context, _) => Row(
          children: [
            if (review) ...[
              _review(context, accepted: true),
              _review(context, accepted: false),
            ],
            if (use) _use(context),
            if (revert) _revert(context),
          ],
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, Future<bool> Function() action) async {
    OmiHaptics.selection();
    final persisted = await action();
    if (!persisted && context.mounted) OmiFeedback.error(context, context.l10n.somethingWentWrong);
  }

  Widget _review(BuildContext context, {required bool accepted}) {
    final selected = memory.userReview == accepted;
    return IconButton(
      key: Key('memory_review_${accepted ? 'accept' : 'reject'}_${memory.id}'),
      onPressed: selected ? null : () => _report(context, () => provider.reviewMemory(memory, accepted)),
      tooltip: accepted ? context.l10n.memoryReviewRight : context.l10n.memoryReviewWrong,
      icon: Icon(
        accepted ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
        size: 17,
        color: selected ? OmiColors.textPrimary : OmiColors.faint,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: OmiSize.minTap, minHeight: OmiSize.minTap),
    );
  }

  Widget _use(BuildContext context) {
    final suppressed = memory.memoryUseSuppressed == true;
    final inFlight = provider.isApplyingMemoryUse(memory.id);
    // Allow use clears a suppression; the backend's separate `useful` rating never backs it.
    final action = suppressed ? MemoryUseAction.allow : MemoryUseAction.suppress;
    final label = suppressed ? context.l10n.memoryAllowUse : context.l10n.memoryDontUse;
    return Semantics(
      container: true,
      button: true,
      label: label,
      enabled: !inFlight,
      child: TextButton(
        key: Key('memory_use_${action.apiValue}_${memory.id}'),
        onPressed: inFlight ? null : () => _report(context, () => provider.setMemoryUse(memory, action)),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, OmiSize.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: inFlight
            ? const OmiSpinner(size: OmiSpinnerSize.small)
            : Text(label, style: OmiType.footnote.copyWith(color: OmiColors.textSecondary)),
      ),
    );
  }

  Widget _revert(BuildContext context) {
    final inFlight = provider.isRevertingMemory(memory.id);
    return Semantics(
      container: true,
      label: context.l10n.undo,
      button: true,
      enabled: !inFlight,
      child: IconButton(
        key: Key('memory_revert_superseded_fact_${memory.id}'),
        onPressed: inFlight ? null : () => _report(context, () => provider.revertSupersededFact(memory)),
        tooltip: context.l10n.undo,
        icon: inFlight
            ? const OmiSpinner(size: OmiSpinnerSize.small)
            : Icon(Icons.restore, size: 18, color: OmiColors.textPrimary),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}
