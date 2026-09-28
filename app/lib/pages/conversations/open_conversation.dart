import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversation_detail/page.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/analytics/product_telemetry.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// Opens [conversation] (v3 rows on Home, All conversations and a folder), as the list did: a
/// locked conversation opens the plan page instead (or nothing when there is no plan to offer);
/// otherwise the tap is recorded after the frame (as a search result while a search is showing)
/// and the conversation is pushed.
Future<void> openConversationDetail(BuildContext context, ServerConversation conversation, {int index = 0}) async {
  if (conversation.isLocked) {
    if (!context.read<UsageProvider>().showSubscriptionUI) return;
    PlatformManager.instance.analytics.paywallOpened('Conversation List Item');
    await routeToPage(context, const UsagePage(showUpgradeDialog: true));
    return;
  }
  OmiHaptics.selection();
  final provider = context.read<ConversationProvider>();
  final searchQuery = provider.previousQuery;
  final hours = DateTime.now().difference(conversation.createdAt).inHours;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.onConversationTap(conversation.id);
    unawaited(SchedulerBinding.instance.scheduleTask<void>(() {
      if (searchQuery.isNotEmpty) {
        ProductTelemetry.instance.value(
          ProductValue.searchResultOpened,
          surface: ProductSurface.conversations,
          objectId: RecordReference.fromId(conversation.id),
        );
        PlatformManager.instance.analytics.conversationOpenedFromSearch(
          conversation: conversation,
          searchQuery: searchQuery,
          conversationIndexInResults: index,
        );
      } else {
        PlatformManager.instance.analytics.conversationListItemClickedWithTimeDifference(
          conversation: conversation,
          conversationIndex: index,
          hoursSinceConversation: hours,
        );
      }
    }, Priority.idle));
  });
  await routeToPage(context, ConversationDetailPage(conversation: conversation));
}
