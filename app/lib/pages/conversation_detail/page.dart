import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_provider_utilities/flutter_provider_utilities.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omi/backend/http/api/conversations.dart';
import 'package:omi/backend/http/api/messages.dart' show ChatPageContext;
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/pages/chat/page.dart';
import 'package:omi/pages/conversations/conversation_actions.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/pages/conversations/conversation_action_analytics.dart';
import 'package:omi/utils/analytics/analytics_manager.dart';
import 'package:omi/utils/analytics/product_telemetry.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'conversation_detail_provider.dart';
import 'conversation_summary_selection.dart';
import 'maps_util.dart';
import 'share.dart';
import 'test_prompts.dart';
import 'transcript_page.dart';
import 'widgets/conversation_folder_sheet.dart';
import 'widgets/share_to_contacts_sheet.dart';
import 'widgets/summary_v3.dart';

/// Whether the menu shows developer tools (Copy conversation ID, Test prompt): debug builds, or
/// Developer Settings → Conversation Developer Tools (`devModeEnabled`).
@visibleForTesting
bool conversationDetailShowsDeveloperTools() => kDebugMode || SharedPreferencesUtil().devModeEnabled;

/// The conversation's two tabs (v3).
enum ConversationView { summary, todos }

/// A conversation (v3 `conv`): the back ring and "⋯" on top; the title, a chip with when and how
/// long and a chip with its folder; Summary and To-dos tabs. "⋯" holds View transcript, Move to
/// folder, Share link, Copy summary, Ask Omi about this, Open in Maps and Delete conversation.
class ConversationDetailPage extends StatefulWidget {
  final ServerConversation conversation;

  /// Kept for existing callers; it no longer changes navigation (back always pops).
  final bool isFromOnboarding;
  final bool openShareToContactsOnLoad;

  /// Kept for existing callers (search deep links): v3 has no transcript tab, so an index of 0
  /// opens the transcript screen on top.
  final int? initialTabIndex;
  final double? initialSeekStart;
  final double? initialSeekEnd;

  const ConversationDetailPage({
    super.key,
    this.isFromOnboarding = false,
    required this.conversation,
    this.openShareToContactsOnLoad = false,
    this.initialTabIndex,
    this.initialSeekStart,
    this.initialSeekEnd,
  });

  @override
  State<ConversationDetailPage> createState() => ConversationDetailPageState();
}

class ConversationDetailPageState extends State<ConversationDetailPage> {
  ConversationView _view = ConversationView.summary;
  bool _providerInitialized = false;
  bool _resultViewedRecorded = false;
  final GlobalKey _moreKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<ConversationDetailProvider>();
      final conversationProvider = context.read<ConversationProvider>();
      final identityEpoch = AnalyticsManager.identityEpoch;

      provider.setCachedConversation(widget.conversation);
      _providerInitialized = true;
      final located = conversationProvider.getConversationDateAndIndex(widget.conversation);
      if (located != null) {
        provider.updateConversation(widget.conversation.id, located.$1);
      } else {
        provider.selectedDate = conversationLocalDayKey(widget.conversation.startedAt ?? widget.conversation.createdAt);
      }
      await provider.initConversation();
      if (!mounted) return;
      _recordResultViewed(provider, identityEpoch);
      if (provider.conversation.appResults.isEmpty &&
          conversationProvider.getConversationDateAndIndexById(provider.conversation.id) != null) {
        // Fill in app results the list omitted, after the first usable frame.
        final id = provider.conversation.id;
        unawaited(conversationProvider.updateSearchedConvoDetails(id).catchError((_) {}).then((_) {
          if (mounted && provider.conversationOrNull?.id == id) provider.updateConversation(id, provider.selectedDate);
        }));
      }
      if (widget.initialTabIndex == 0 && mounted) {
        unawaited(routeToPage(context, ConversationTranscriptPage(provider: provider)));
      }
      if (widget.openShareToContactsOnLoad && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted) showShareToContactsBottomSheet(context, provider.conversation);
      }
    });
  }

  void _recordResultViewed(ConversationDetailProvider provider, int identityEpoch) {
    if (_resultViewedRecorded || identityEpoch != AnalyticsManager.identityEpoch) return;
    final conversation = provider.conversationOrNull;
    if (conversation == null || conversation.id != widget.conversation.id) return;
    if (provider.getSummarySelection().content.trim().isEmpty) return;
    _resultViewedRecorded = true;
    ProductTelemetry.instance.value(
      ProductValue.resultViewed,
      surface: ProductSurface.conversationDetail,
      objectId: RecordReference.fromId(conversation.id),
    );
  }

  /// The ⋯ menu's choices as conversation actions (the same names the menu reported before v3).
  static const _menuActions = {
    'move_to_folder': ConversationActionAction.moveFolder,
    'share': ConversationActionAction.share,
    'copy_summary': ConversationActionAction.copySummary,
    'ask_omi': ConversationActionAction.askOmi,
    'copy_conversation_id': ConversationActionAction.copyConversationId,
    'test_prompt': ConversationActionAction.testPrompt,
    'delete': ConversationActionAction.delete,
  };

  Future<void> _openMenu(ConversationDetailProvider provider) async {
    final l10n = context.l10n;
    final conversation = provider.conversation;
    final place = conversation.geolocation;
    final hasPlace = place?.latitude != null && place?.longitude != null;
    PlatformManager.instance.analytics.conversationThreeDotsMenuOpened(conversationId: conversation.id);
    final dev = conversationDetailShowsDeveloperTools();
    final choice = await showOmiPopoverMenu<String>(context, entries: [
      OmiMenuEntry(
          value: 'view_transcript',
          label: l10n.viewTranscriptV3,
          glyph: OmiGlyphs.lines,
          key: const Key('menu_transcript')),
      OmiMenuEntry(value: 'move_to_folder', label: l10n.moveToFolderV3, glyph: OmiGlyphs.folderLine),
      OmiMenuEntry(value: 'share', label: l10n.shareLink, glyph: OmiGlyphs.shareLine),
      OmiMenuEntry(value: 'copy_summary', label: l10n.copySummaryV3, glyph: OmiGlyphs.copyLine),
      OmiMenuEntry(
        value: 'ask_omi',
        label: l10n.askOmiAboutThis,
        icon: OmiRingLogo(size: 18, color: OmiColors.textPrimary),
      ),
      if (hasPlace)
        OmiMenuEntry(
          value: 'open_in_maps',
          label:
              (place!.address ?? '').trim().isEmpty ? l10n.openInMaps : '${l10n.openInMaps} · ${place.address!.trim()}',
          glyph: OmiGlyphs.pinLine,
        ),
      if (dev) ...[
        OmiMenuEntry(
            value: 'copy_conversation_id',
            label: l10n.copyConversationId,
            glyph: OmiGlyphs.copyLine,
            dividerBefore: true),
        OmiMenuEntry(value: 'test_prompt', label: l10n.testPrompt, glyph: OmiGlyphs.lines),
      ],
      OmiMenuEntry(
        value: 'delete',
        label: l10n.deleteConversationV3,
        glyph: OmiGlyphs.trashLine,
        strong: true,
        dividerBefore: true,
        key: const Key('menu_delete'),
      ),
    ]);
    if (choice == null || !mounted) return;
    PlatformManager.instance.analytics.conversationThreeDotsMenuActionSelected(
      conversationId: conversation.id,
      action: choice,
    );
    final tracked = _menuActions[choice];
    if (tracked != null) trackConversationAction(tracked, ConversationActionSurface.overflow);
    switch (choice) {
      case 'view_transcript':
        unawaited(routeToPage(context, ConversationTranscriptPage(provider: provider)));
      case 'move_to_folder':
        await showConversationFolderSheet(context, conversation, source: 'detail_page_menu');
      case 'share':
        await _share(provider);
      case 'copy_summary':
        OmiClipboard.copy(context, ConversationSummarySelection.select(conversation).content, what: l10n.summary);
      case 'ask_omi':
        routeToPage(
          context,
          ChatPage(
            initialChatContext:
                ChatPageContext(type: 'conversation', id: conversation.id, title: conversation.structured.title),
          ),
        );
      case 'open_in_maps':
        MapsUtil.launchMap(place!.latitude!, place.longitude!);
      case 'copy_conversation_id':
        OmiClipboard.copy(context, conversation.id);
      case 'test_prompt':
        routeToPage(context, TestPromptsPage(conversation: conversation));
      case 'delete':
        OmiHaptics.medium();
        if (!await confirmConversationDelete(context) || !mounted) return;
        final listContext = Navigator.of(context).context;
        Navigator.pop(context, {'deleted': true});
        if (listContext.mounted) unawaited(deleteConversationsWithUndo(listContext, [conversation]));
    }
  }

  /// Share link: a private conversation becomes link-visible for the sheet and goes back to private
  /// if the sheet is dismissed without sharing.
  Future<void> _share(ConversationDetailProvider provider) async {
    final conversation = provider.conversation;
    final wasPrivate = conversation.visibility != ConversationVisibility.shared;
    try {
      if (wasPrivate) {
        final shared = await setConversationVisibility(conversation.id);
        if (!mounted) return;
        if (!shared) {
          OmiFeedback.error(context, context.l10n.conversationUrlNotShared);
          return;
        }
        provider.updateVisibilityLocally(ConversationVisibility.shared);
      }
      final box = _moreKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      final outcome = await shareConversationLink(conversation, sharePositionOrigin: origin);
      if (wasPrivate && outcome.status == ShareResultStatus.dismissed) {
        final reverted =
            await setConversationVisibility(conversation.id, visibility: ConversationVisibility.private_.value);
        if (reverted && mounted) provider.updateVisibilityLocally(ConversationVisibility.private_);
      }
    } catch (e) {
      Logger.debug('Failed to share conversation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConversationDetailProvider>();
    final conversation = provider.conversationOrNull;
    if (conversation == null) {
      if (_providerInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        });
      }
      return Scaffold(backgroundColor: OmiColors.surface0);
    }
    final l10n = context.l10n;
    final todos = conversation.structured.actionItems.where((i) => !i.deleted).toList();
    return MessageListener<ConversationDetailProvider>(
      showError: (error) {
        if (error == 'REPROCESS_FAILED') OmiFeedback.error(context, l10n.errorProcessingConversation);
      },
      showInfo: (_) {},
      child: Scaffold(
        backgroundColor: OmiColors.surface0,
        appBar: OmiScreenHeader(
          trailing: KeyedSubtree(
            key: _moreKey,
            child: OmiRingButton(
              key: const Key('conversation_more'),
              glyph: OmiGlyphs.more,
              label: l10n.moreOptions,
              onPressed: () => _openMenu(provider),
            ),
          ),
        ),
        bottomNavigationBar: const ListeningStrip(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 14, OmiSize.screenMargin, 20),
          children: [
            Semantics(
              header: true,
              child: Text(
                conversation.structured.title.trim().isEmpty
                    ? l10n.untitledConversation
                    : conversation.structured.title.trim(),
                key: const Key('conversation_title'),
                style: ConversationTitleStyle.style,
              ),
            ),
            const SizedBox(height: 12),
            _Chips(conversation: conversation),
            const SizedBox(height: 22),
            OmiTextTabs<ConversationView>(
              tabs: [
                OmiTextTab(value: ConversationView.summary, label: l10n.summary),
                OmiTextTab(
                    value: ConversationView.todos, label: l10n.todosTab, count: todos.isEmpty ? null : todos.length),
              ],
              selected: _view,
              onChanged: (view) => setState(() => _view = view),
            ),
            const SizedBox(height: 4),
            if (_view == ConversationView.summary)
              _Summary(conversation: conversation, provider: provider)
            else
              _Todos(conversation: conversation, todos: todos),
          ],
        ),
      ),
    );
  }
}

/// The title of a conversation and its transcript (`h1.cvh`): 30/600 at −.025em, 1.12 line.
abstract final class ConversationTitleStyle {
  static TextStyle get style => OmiType.pageTitle;
}

/// When and how long; the folder (tap to move it).
class _Chips extends StatelessWidget {
  const _Chips({required this.conversation});

  final ServerConversation conversation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final start = (conversation.startedAt ?? conversation.createdAt).toLocal();
    final end = conversation.finishedAt?.toLocal();
    final dates = OmiDateFormat.of(context);
    final minutes = end == null ? null : (end.difference(start).inSeconds / 60).ceil();
    final when = [
      '${dates.dayHeader(start)} ${dates.time(start)}',
      if (minutes != null && minutes > 0) l10n.minutesShortV3(minutes),
    ].join(' · ');
    final folders = context.watch<FolderProvider>().folders;
    String? folder;
    for (final f in folders) {
      if (f.id == conversation.folderId) folder = f.name;
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OmiPillChip(label: when, glyph: OmiGlyphs.calendar),
        OmiPillChip(
          key: const Key('conversation_folder_chip'),
          label: folder ?? l10n.noFolderV3,
          glyph: OmiGlyphs.folderLine,
          semanticHint: l10n.moveToFolderV3,
          onTap: () => showConversationFolderSheet(context, conversation, source: 'detail_page_sheet'),
        ),
      ],
    );
  }
}

/// The Summary tab: the summary, or what is happening instead (summarizing, nothing to summarize).
class _Summary extends StatelessWidget {
  const _Summary({required this.conversation, required this.provider});

  final ServerConversation conversation;
  final ConversationDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = provider.getSummarySelection().content.trim();
    if (content.isNotEmpty) return SummaryV3(markdown: content);
    final processing =
        conversation.status == ConversationStatus.processing || conversation.status == ConversationStatus.in_progress;
    final hasTranscript = conversation.transcriptSegments.any((s) => s.text.trim().isNotEmpty);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            processing ? l10n.summarizingConversation.replaceAll('\n', ' ') : l10n.noSummaryYet,
            style: OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.textSecondary),
          ),
          if (hasTranscript)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OmiPillChip(
                key: const Key('conversation_show_transcript'),
                label: l10n.viewTranscriptV3,
                glyph: OmiGlyphs.lines,
                onTap: () => routeToPage(context, ConversationTranscriptPage(provider: provider)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The To-dos tab (`#cvTodo`): the conversation's to-dos, a ring and the words.
class _Todos extends StatefulWidget {
  const _Todos({required this.conversation, required this.todos});

  final ServerConversation conversation;
  final List<ActionItem> todos;

  @override
  State<_Todos> createState() => _TodosState();
}

class _TodosState extends State<_Todos> {
  final Map<String, bool> _pending = {};

  Future<void> _toggle(ActionItem item, bool value) async {
    setState(() => _pending[item.description] = value);
    try {
      await context
          .read<ConversationProvider>()
          .updateGlobalActionItemState(widget.conversation, item.description, value);
      final index = widget.conversation.structured.actionItems.indexWhere((i) => i.description == item.description);
      if (index != -1) {
        if (value) {
          PlatformManager.instance.analytics.checkedActionItem(widget.conversation, index);
        } else {
          PlatformManager.instance.analytics.uncheckedActionItem(widget.conversation, index);
        }
      }
    } catch (e) {
      Logger.debug('Error updating to-do: $e');
      if (mounted) OmiFeedback.error(context, context.l10n.failedToUpdateActionItem);
    } finally {
      if (mounted) setState(() => _pending.remove(item.description));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.todos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(l10n.noTodosInConversation,
            style: OmiType.body.copyWith(fontWeight: FontWeight.w400, height: 1.5, color: OmiColors.textSecondary)),
      );
    }
    return Column(
      children: [
        for (final item in widget.todos)
          Container(
            key: ValueKey('conversation_todo_${item.description.hashCode}'),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(-12, 2),
                  child: OmiCheckRing(
                    done: _pending[item.description] ?? item.completed,
                    semanticLabel:
                        (_pending[item.description] ?? item.completed) ? l10n.markIncomplete : l10n.markComplete,
                    onChanged: (value) => _toggle(item, value),
                  ),
                ),
                Expanded(
                  child: Transform.translate(
                    offset: const Offset(-10, 0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        item.description.trim(),
                        style: OmiType.body.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color:
                              (_pending[item.description] ?? item.completed) ? OmiColors.faint : OmiColors.textPrimary,
                          decoration:
                              (_pending[item.description] ?? item.completed) ? TextDecoration.lineThrough : null,
                          decorationColor: OmiColors.faint,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
