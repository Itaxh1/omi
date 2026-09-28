import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversation_detail/conversation_detail_provider.dart';
import 'package:omi/pages/conversations/widgets/move_to_folder_sheet.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// Moves [conversation] to a folder through the shared sheet and updates the
/// page immediately. Used by the folder chip and the ⋯ menu.
Future<void> showConversationFolderSheet(
  BuildContext context,
  ServerConversation conversation, {
  required String source,
}) async {
  OmiHaptics.selection();
  final currentFolderId = conversation.folderId;
  PlatformManager.instance.analytics.conversationDetailFolderChipClicked(
    conversationId: conversation.id,
    currentFolderId: currentFolderId,
  );
  final folderProvider = Provider.of<FolderProvider>(context, listen: false);
  if (folderProvider.folders.isEmpty) {
    await folderProvider.loadFolders();
  }
  if (!context.mounted) return;
  final newFolderId = await showMoveToFolderSheet(
    context,
    conversationId: conversation.id,
    currentFolderId: currentFolderId,
  );
  // Update locally at once for instant feedback.
  if (newFolderId != null && context.mounted) {
    context.read<ConversationDetailProvider>().updateFolderIdLocally(newFolderId);
    PlatformManager.instance.analytics.conversationMovedToFolder(
      conversationId: conversation.id,
      fromFolderId: currentFolderId,
      toFolderId: newFolderId,
      source: source,
    );
  }
}
