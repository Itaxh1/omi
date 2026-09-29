import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_provider_utilities/flutter_provider_utilities.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:omi/backend/http/api/conversations.dart';
import 'package:omi/backend/http/api/messages.dart' show ChatPageContext;
import 'package:omi/backend/http/api/users.dart'
    show
        MobileFeedbackKind,
        MobileFeedbackReason,
        MobileFeedbackReceipt,
        MobileFeedbackTargetKind,
        submitMobileFeedback;
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/chat/page.dart';
import 'package:omi/pages/conversations/conversation_actions.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/services/siri_integration.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/pages/conversations/conversation_action_analytics.dart';
import 'package:omi/utils/analytics/analytics_manager.dart';
import 'package:omi/utils/analytics/product_telemetry.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/utils/platform/platform_manager.dart';
import 'package:omi/pages/chat/open_ask.dart';
import 'conversation_detail_provider.dart';
import 'conversation_summary_selection.dart';
import 'maps_util.dart';
import 'share.dart';
import 'test_prompts.dart';
import 'transcript_page.dart';
import 'widgets/conversation_folder_sheet.dart';
import 'widgets/conversation_todos.dart';
import 'widgets/feedback_sheet.dart';
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
  final GlobalKey _shareKey = GlobalKey();

  /// Editing the summary in place (v8.18), and the lines being edited.
  SummaryDraft? _draft;

  void _startEditing(ConversationDetailProvider provider) {
    final content = provider.getSummarySelection().content.trim();
    if (content.isEmpty) return;
    _draft?.dispose();
    setState(() {
      _view = ConversationView.summary;
      _draft = SummaryDraft(content);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _draft?.focusFirst());
  }

  void _stopEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    final draft = _draft;
    setState(() => _draft = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => draft?.dispose());
  }

  Future<void> _saveEditing(ConversationDetailProvider provider) async {
    final draft = _draft;
    if (draft == null) return;
    final markdown = draft.toMarkdown();
    final selection = provider.getSummarySelection();
    _stopEditing();
    if (markdown.isEmpty || markdown == selection.content.trim()) return;
    await provider.saveEditingSummarySelection(selection, markdown);
    if (!mounted) return;
    OmiHaptics.success();
    OmiFeedback.confirm(context, context.l10n.summarySaved);
  }

  @override
  void dispose() {
    unawaited(SiriIntegration.instance.setCurrentScreen("", null));
    _draft?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(
        SiriIntegration.instance.setCurrentScreen("/conversation/${widget.conversation.id}", widget.conversation.id));
    unawaited(SiriIntegration.instance.donateUiAction('conversation', widget.conversation.id));
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
    // v8.18 order: edit, ask, copy, transcript | folder | maps | delete (Share is in the header).
    final canEdit = provider.getSummarySelection().canEdit(conversation) &&
        provider.getSummarySelection().content.trim().isNotEmpty;
    final choice = await showOmiPopoverMenu<String>(context, entries: [
      if (canEdit)
        OmiMenuEntry(
            value: 'edit_summary', label: l10n.editSummaryV3, glyph: OmiGlyphs.pencil, key: const Key('menu_edit')),
      OmiMenuEntry(
        value: 'ask_omi',
        label: l10n.askOmiAboutThis,
        icon: OmiRingLogo(size: 18, color: OmiColors.cement),
      ),
      OmiMenuEntry(value: 'copy_summary', label: l10n.copySummaryV3, glyph: OmiGlyphs.copyLine),
      OmiMenuEntry(
          value: 'view_transcript',
          label: l10n.viewTranscriptV3,
          glyph: OmiGlyphs.lines,
          key: const Key('menu_transcript')),
      OmiMenuEntry(
          value: 'move_to_folder', label: l10n.moveToFolderV3, glyph: OmiGlyphs.folderLine, dividerBefore: true),
      if (hasPlace)
        OmiMenuEntry(
          value: 'open_in_maps',
          label: l10n.openInMaps,
          detail: (place!.address ?? '').trim().isEmpty ? null : place.address!.trim(),
          glyph: OmiGlyphs.pinLine,
          dividerBefore: true,
        ),
      OmiMenuEntry(
        value: 'give_feedback',
        label: l10n.feedbackGiveFeedback,
        glyph: OmiGlyphs.bubbles,
        dividerBefore: !hasPlace,
        key: const Key('menu_feedback'),
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
      case 'edit_summary':
        _startEditing(provider);
      case 'view_transcript':
        unawaited(routeToPage(context, ConversationTranscriptPage(provider: provider)));
      case 'move_to_folder':
        await showConversationFolderSheet(context, conversation, source: 'detail_page_menu');
      case 'share':
        await _share(provider);
      case 'copy_summary':
        OmiClipboard.copy(context, ConversationSummarySelection.select(conversation).content, what: l10n.summary);
      case 'ask_omi':
        openAsk(
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
      case 'give_feedback':
        unawaited(showFeedbackReasonSheet(
          context,
          title: l10n.feedbackGiveFeedback,
          population: FeedbackReasonPopulation.summary,
          onSubmit: (value, reason) => unawaited(_sendFeedback(conversation.id, value, reason)),
        ));
      case 'delete':
        OmiHaptics.medium();
        if (!await confirmConversationDelete(context) || !mounted) return;
        final listContext = Navigator.of(context).context;
        Navigator.pop(context, {'deleted': true});
        if (listContext.mounted) unawaited(deleteConversationsWithUndo(listContext, [conversation]));
    }
  }

  /// Give feedback: the summary was good, or what was wrong with it (`mobile_feedback.v1`).
  Future<void> _sendFeedback(String id, int value, MobileFeedbackReason? reason) async {
    MobileFeedbackReceipt? receipt;
    try {
      receipt = await submitMobileFeedback(
        kind: MobileFeedbackKind.summaryHelpfulness,
        targetKind: MobileFeedbackTargetKind.conversation,
        targetId: id,
        value: value,
        reason: reason,
      );
    } catch (_) {
      receipt = null;
    }
    if (!mounted) return;
    if (receipt == null) {
      OmiFeedback.error(context, context.l10n.somethingWentWrong);
    } else {
      OmiFeedback.confirm(context, context.l10n.thanksForYourFeedback);
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
      final box = (_shareKey.currentContext ?? _moreKey.currentContext)?.findRenderObject() as RenderBox?;
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
        // v8.18: Share beside ⋯.
        appBar: OmiScreenHeader(
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KeyedSubtree(
                key: _shareKey,
                child: OmiRingButton.glass(
                  key: const Key('conversation_share'),
                  glyph: OmiGlyphs.shareLine,
                  label: l10n.share,
                  onPressed: () {
                    trackConversationAction(ConversationActionAction.share, ConversationActionSurface.overflow);
                    _share(provider);
                  },
                ),
              ),
              const SizedBox(width: 10),
              KeyedSubtree(
                key: _moreKey,
                child: OmiRingButton.glass(
                  key: const Key('conversation_more'),
                  glyph: OmiGlyphs.more,
                  label: l10n.moreOptions,
                  onPressed: () => _openMenu(provider),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const ListeningStrip(),
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(OmiSize.screenMargin, 14, OmiSize.screenMargin, _draft == null ? 20 : 130),
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
                        value: ConversationView.todos,
                        label: l10n.todosTab,
                        count: todos.isEmpty ? null : todos.length),
                  ],
                  selected: _view,
                  onChanged: (view) => setState(() => _view = view),
                ),
                const SizedBox(height: 4),
                if (_view == ConversationView.summary && _draft != null)
                  SummaryV3Editor(draft: _draft!)
                else if (_view == ConversationView.summary)
                  _Summary(conversation: conversation, provider: provider)
                else
                  ConversationTodos(conversation: conversation, todos: todos),
              ],
            ),
            if (_draft != null)
              // `.edbar`: 60 pt above the listening strip.
              Positioned(
                left: 14,
                right: 14,
                bottom: 60,
                child: SummaryEditBar(
                  label: l10n.editingSummary,
                  cancel: l10n.cancel,
                  save: l10n.save,
                  onCancel: _stopEditing,
                  onSave: () => _saveEditing(provider),
                ),
              ),
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
