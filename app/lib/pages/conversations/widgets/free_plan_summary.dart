import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// The day the free plan's minutes come back. Usage counts by calendar month, so it is the first
/// of next month.
DateTime freePlanMinutesResetDay(DateTime now) => DateTime(now.year, now.month + 1, 1);

/// Whether the newest day on Home should open with [SummariesPausedRow]: one of its conversations
/// was kept without a summary because the free plan's minutes are used up.
bool showsSummariesPausedRow(List<ServerConversation> newestDay) =>
    newestDay.any((conversation) => conversation.summaryUnavailableOnFreePlan);

/// The plan page with the upgrade sheet open, as a locked row opens it. Does nothing where the app
/// hides subscriptions.
Future<void> openUnlimitedPlan(BuildContext context, {required String source}) async {
  if (!context.read<UsageProvider>().showSubscriptionUI) return;
  PlatformManager.instance.analytics.paywallOpened(source);
  await routeToPage(context, const UsagePage(showUpgradeDialog: true));
}

/// The first row of the newest day on Home when its conversations are kept without summaries:
/// says why and when the free minutes come back, and opens the plan.
class SummariesPausedRow extends StatelessWidget {
  const SummariesPausedRow({super.key, this.now});

  /// Today, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final resetDay = OmiDateFormat.of(context).day(freePlanMinutesResetDay(now ?? DateTime.now()));
    final canUpgrade = context.select<UsageProvider, bool>((usage) => usage.showSubscriptionUI);
    return Padding(
      padding: const EdgeInsets.only(top: OmiSpacing.xs, left: OmiSpacing.md, right: OmiSpacing.md),
      child: Material(
        color: OmiColors.surface1,
        borderRadius: OmiRadius.xlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('summaries_paused_row'),
          onTap: canUpgrade ? () => openUnlimitedPlan(context, source: 'Summaries Paused Row') : null,
          child: Padding(
            // The conversation row's own inset and tile, so the two read as one list.
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: OmiSpacing.xxl + OmiSpacing.xxs,
                  height: OmiSpacing.xxl + OmiSpacing.xxs,
                  decoration: BoxDecoration(color: OmiColors.surface2, borderRadius: OmiRadius.mdAll),
                  alignment: Alignment.center,
                  child: Icon(Icons.notes_rounded, color: OmiColors.textSecondary),
                ),
                const SizedBox(width: OmiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.summariesPaused,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.freeMinutesBackOn(resetDay),
                        style: OmiType.footnote.copyWith(color: OmiColors.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (canUpgrade) Icon(Icons.chevron_right_rounded, color: OmiColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
