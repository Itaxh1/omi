import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:collection/collection.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:uuid/uuid.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:omi/backend/http/api/messages.dart';
import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/app.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/message.dart';
import 'package:omi/pages/chat/chat_scroll_policy.dart';
import 'package:omi/pages/chat/widgets/ai_message.dart';
import 'package:omi/pages/chat/widgets/jump_to_latest_button.dart';
import 'package:omi/pages/settings/widgets/plans_sheet.dart';
import 'package:omi/pages/chat/widgets/user_message.dart';
import 'package:omi/pages/chat/widgets/voice_recorder_widget.dart';
import 'package:omi/pages/settings/integrations_page.dart';
import 'package:omi/providers/app_provider.dart';
import 'package:omi/providers/connectivity_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/integration_provider.dart';
import 'package:omi/providers/message_provider.dart';
import 'package:omi/pages/chat/widgets/chat_starters.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/providers/voice_recorder_provider.dart';
import 'package:omi/services/integrations/apple_health_service.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/pages/chat/past_chats_page.dart';
import 'package:omi/pages/chat/widgets/chat_apps_drawer.dart' show ChatAppAvatar;
import 'package:omi/pages/chat/widgets/chat_composer_parts.dart';
import 'package:omi/ui/ui.dart';

class ChatPage extends StatefulWidget {
  final bool isPivotBottom;
  final String? autoMessage;
  final bool autoStartVoice;
  final ChatPageContext? initialChatContext;

  /// A question the user typed before Chat opened (the dock's Ask field); sent as theirs once the
  /// thread has loaded.
  final String? initialQuestion;

  /// Opens on the current thread (a chat app's page, a chat link) instead of a fresh Ask (v3: each
  /// Ask starts fresh, with the earlier chats in Past chats).
  final bool continueThread;

  const ChatPage({
    super.key,
    this.isPivotBottom = false,
    this.autoMessage,
    this.autoStartVoice = false,
    this.initialChatContext,
    this.initialQuestion,
    this.continueThread = false,
  });

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver, TickerProviderStateMixin {
  /// The opening motion: the hello's lines, the count, the suggestions and the composer ([AskIntro]).
  late final AnimationController _intro = AnimationController(vsync: this, duration: AskIntro.length);

  void _playIntro() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward(from: 0);
    }
  }

  TextEditingController textController = TextEditingController();
  late ScrollController scrollController;
  late FocusNode textFieldFocusNode;

  bool _isInitialLoad = true;
  bool _hasInitialScrolled = false;
  double _lastBottomInset = 0;
  MessageProvider? _messageProvider;

  ChatScrollMode _chatScrollMode = ChatScrollMode.followingBottom;
  bool _showLatestJump = false;
  Timer? _latestJumpIdleTimer;
  final List<Timer> _pendingScrollTimers = [];
  final List<Timer> _ownedLifecycleTimers = [];
  bool _isProgrammaticScroll = false;
  int _lastObservedMessageCount = 0;
  String? _lastObservedMessageId;
  int _lastObservedTextLength = 0;
  int _lastObservedContentBlockCount = 0;

  var prefs = SharedPreferencesUtil();
  late List<App> apps;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  String? _selectedContext;
  bool _quotaSheetShown = false;
  ChatPageContext? _chatScope;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    apps = prefs.appsList;
    scrollController = ScrollController();
    textFieldFocusNode = FocusNode();
    textController.addListener(() {
      setState(() {});
    });
    textFieldFocusNode.addListener(() {
      setState(() {});
      if (textFieldFocusNode.hasFocus) {
        // Keep the live edge visible when the keyboard opens only if the reader is following.
        _scheduleModeAwareScroll(delayMs: 300, animated: true);
      }
    });

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      var provider = context.read<MessageProvider>();
      _messageProvider = provider;
      // Listen for quota exceeded from any send path (text or voice)
      provider.addListener(_onMessageProviderChanged);
      if (widget.continueThread) {
        if (provider.messages.isEmpty) provider.refreshMessages();
        _intro.value = 1;
      } else {
        // v3: Ask opens fresh on Omi; the earlier chats are in Past chats.
        context.read<AppProvider>().setSelectedChatAppId(null);
        provider.startFreshChat();
        _playIntro();
      }
      // Fetch enabled chat apps
      provider.fetchChatApps();
      if (widget.initialChatContext != null) {
        setState(() => _chatScope = widget.initialChatContext);
      }
      // Sync Apple Health data if connected (ensures fresh data for health queries)
      _syncAppleHealthIfConnected();
      final question = widget.initialQuestion?.trim() ?? '';
      if (question.isNotEmpty && _isInitialLoad) {
        _runLater(const Duration(milliseconds: 400), () {
          if (mounted) _sendMessageUtil(question);
        });
      } else
      // Auto-start voice recording if requested (e.g., from home chat bar mic button)
      if (widget.autoStartVoice && _isInitialLoad) {
        _runLater(const Duration(milliseconds: 300), () {
          context.read<VoiceRecorderProvider>().startRecording();
        });
      } else if (_isInitialLoad) {
        // Auto-focus the text field only on initial load, not on app switches
        _runLater(const Duration(milliseconds: 300), () {
          final voiceRecorderProvider = context.read<VoiceRecorderProvider>();
          if (!voiceRecorderProvider.isActive && _isInitialLoad) {
            textFieldFocusNode.requestFocus();
          }
        });
      }
      // Handle auto-message from notification (e.g., daily reflection or goal advice)
      // This sends a message FROM Omi AI, not from the user
      if (widget.autoMessage != null && widget.autoMessage!.isNotEmpty && mounted) {
        // Wait for messages to load first, then add auto-message
        _runLater(const Duration(milliseconds: 800), () {
          final aiMessage = ServerMessage(
            const Uuid().v4(),
            DateTime.now(),
            widget.autoMessage!,
            MessageSender.ai,
            MessageType.text,
            null,
            false,
            [],
            [],
            [],
            askForNps: false,
          );
          context.read<MessageProvider>().addMessage(aiMessage);
          // Scroll after the message is added and rendered only while following.
          _scheduleModeAwareScroll(delayMs: 100);
        });
      }
    });
    super.initState();
  }

  void _onMessageProviderChanged() {
    final provider = context.read<MessageProvider>();
    if (mounted && provider.isChatQuotaExceeded && !_quotaSheetShown) {
      _quotaSheetShown = true;
      _showPlansSheetOnQuotaExceeded();
    } else if (!provider.isChatQuotaExceeded) {
      _quotaSheetShown = false;
    }
  }

  /// The keyboard shrinks the viewport after the initial jump to the bottom,
  /// which leaves the transcript parked mid-way (the list keeps its pixel offset
  /// while maxScrollExtent grows). Re-pin to the live edge on every inset change
  /// while the reader is following, so opening chat always lands on the last
  /// message regardless of keyboard animation timing.
  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final bottomInset = view.viewInsets.bottom / view.devicePixelRatio;
    if ((bottomInset - _lastBottomInset).abs() < 1) return;
    _lastBottomInset = bottomInset;
    if (_chatScrollMode != ChatScrollMode.followingBottom) return;
    _schedulePostFrameModeAwareScroll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageProvider?.removeListener(_onMessageProviderChanged);
    _cancelOwnedLifecycleTimers();
    _latestJumpIdleTimer?.cancel();
    _cancelPendingScrolls();
    textController.dispose();
    scrollController.dispose();
    textFieldFocusNode.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _runLater(Duration delay, VoidCallback callback) {
    late final Timer timer;
    timer = Timer(delay, () {
      _ownedLifecycleTimers.remove(timer);
      if (!mounted) return;
      callback();
    });
    _ownedLifecycleTimers.add(timer);
  }

  void _cancelOwnedLifecycleTimers() {
    for (final timer in _ownedLifecycleTimers) {
      timer.cancel();
    }
    _ownedLifecycleTimers.clear();
  }

  void _syncAppleHealthIfConnected() async {
    final appleHealthService = AppleHealthService();
    if (appleHealthService.isAvailable) {
      final integrationProvider = context.read<IntegrationProvider>();
      await integrationProvider.ensureLoaded();
      if (!mounted) return;
      if (integrationProvider.isAppConnected(IntegrationApp.appleHealth)) {
        debugPrint('🍎 [Apple Health] Starting auto-sync on chat open…');
        final success = await appleHealthService.syncHealthDataToBackend(days: 7);
        debugPrint('🍎 [Apple Health] Auto-sync ${success ? "completed" : "failed"}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer2<MessageProvider, ConnectivityProvider>(
      builder: (context, provider, connectivityProvider, child) {
        _observeMessagesForAutoScroll(provider);
        return Scaffold(
          key: scaffoldKey,
          appBar: _buildAppBar(context, provider),
          body: GestureDetector(
            onTap: () {
              // Hide keyboard when tapping outside textfield
              FocusScope.of(context).unfocus();
            },
            child: Column(
              children: [
                // Messages area - takes up remaining space
                Expanded(
                  child: provider.isLoadingMessages && (provider.messages.isEmpty || !provider.hasCachedMessages)
                      ? OmiLoadingState(label: provider.firstTimeLoadingText)
                      : provider.isClearingChat
                          ? OmiLoadingState(label: context.l10n.deletingMessages)
                          : (provider.messages.isEmpty)
                              ? AskHello(isConnected: connectivityProvider.isConnected, animation: _intro)
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        textSelectionTheme: TextSelectionThemeData(
                                          selectionColor: OmiColors.textPrimary.withValues(alpha: 0.3),
                                          selectionHandleColor: OmiColors.accent,
                                        ),
                                      ),
                                      // Tight width: under the Column's loose constraints this Stack
                                      // otherwise shrink-wraps to its only non-positioned child (the
                                      // jump-to-latest chip, ~100pt), and every message collapses to a
                                      // character-wide column whenever that chip is visible.
                                      child: SizedBox(
                                        width: constraints.maxWidth,
                                        child: Stack(
                                          alignment: Alignment.bottomCenter,
                                          children: [
                                            Positioned.fill(
                                              child: NotificationListener<ScrollNotification>(
                                                onNotification: _handleScrollNotification,
                                                child: ListView.builder(
                                                  shrinkWrap: false,
                                                  reverse: false,
                                                  controller: scrollController,
                                                  padding: const EdgeInsets.fromLTRB(
                                                    18,
                                                    16,
                                                    18,
                                                    ChatScrollPolicy.transcriptBottomPadding,
                                                  ),
                                                  itemCount: provider.messages.length,
                                                  itemBuilder: (context, chatIndex) {
                                                    if (!_hasInitialScrolled && provider.messages.isNotEmpty) {
                                                      _hasInitialScrolled = true;
                                                      _schedulePostFrameModeAwareScroll();
                                                    }

                                                    final message = provider.messages[chatIndex];
                                                    double topPadding =
                                                        chatIndex == provider.messages.length - 1 ? 8 : 16;
                                                    double bottomPadding = chatIndex == 0 ? 16 : 0;

                                                    final messageBody = message.sender == MessageSender.ai
                                                        ? AIMessage(
                                                            showTypingIndicator: provider.showTypingIndicator &&
                                                                chatIndex == provider.messages.length - 1,
                                                            showThinkingAfterText: provider.agentThinkingAfterText,
                                                            message: message,
                                                            sendMessage: _sendMessageUtil,
                                                            onAskOmi: (text) {
                                                              setState(() {
                                                                _selectedContext = text;
                                                              });
                                                              textFieldFocusNode.requestFocus();
                                                            },
                                                            displayOptions: provider.messages.length <= 1,
                                                            appSender: provider.messageSenderApp(message.appId),
                                                            updateConversation: (ServerConversation conversation) {
                                                              context.read<ConversationProvider>().updateConversation(
                                                                    conversation,
                                                                  );
                                                            },
                                                            setMessageNps: (int value, {String? reason}) =>
                                                                provider.setMessageNps(message, value, reason: reason),
                                                            replyFailed: provider.isReplyFailed(message),
                                                            onRetry: provider.canRetryReply(message)
                                                                ? () => _retryReply(message)
                                                                : null,
                                                          )
                                                        : HumanMessage(
                                                            message: message,
                                                            onAskOmi: (text) {
                                                              setState(() {
                                                                _selectedContext = text;
                                                              });
                                                              textFieldFocusNode.requestFocus();
                                                            },
                                                          );
                                                    return VisibilityDetector(
                                                      key: ValueKey('chat-result-visibility-${message.id}'),
                                                      onVisibilityChanged: (info) {
                                                        if (message.sender == MessageSender.ai &&
                                                            !message.isEmpty &&
                                                            info.visibleFraction > 0 &&
                                                            context.mounted) {
                                                          provider.markChatResultVisible(message.id);
                                                        }
                                                      },
                                                      child: Padding(
                                                        key: ValueKey(message.id),
                                                        padding:
                                                            EdgeInsets.only(bottom: bottomPadding, top: topPadding),
                                                        child: messageBody,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            if (_chatScrollMode == ChatScrollMode.freeScrolling && _showLatestJump)
                                              _buildJumpToLatestButton(),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
                // Send message area
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
                  ),
                  child: Consumer2<HomeProvider, VoiceRecorderProvider>(
                    builder: (context, home, voiceRecorderProvider, child) {
                      bool shouldShowSendButton(MessageProvider p) {
                        return !p.sendingMessage && !voiceRecorderProvider.isActive;
                      }

                      bool shouldShowMenuButton() {
                        return !voiceRecorderProvider.isActive;
                      }

                      return Column(
                        children: [
                          // v3: suggestions above the composer until the first question.
                          if (provider.messages.isEmpty &&
                              !provider.isLoadingMessages &&
                              connectivityProvider.isConnected)
                            AskSuggestions(
                              animation: _intro,
                              onSelected: (prompt) {
                                OmiHaptics.selection();
                                _sendMessageUtil(prompt);
                              },
                            ),
                          // Selected images display above the send bar
                          const ChatSelectedFilesStrip(),
                          if (!connectivityProvider.isConnected) const _OfflineHint(),
                          // Scope chip (#4515) — clears an active conversation scope (Ask about this)
                          Builder(
                            builder: (context) {
                              final scope = _chatScope;
                              final hasConversation = scope?.type == 'conversation' && (scope?.id?.isNotEmpty ?? false);
                              if (!hasConversation) return const SizedBox.shrink();
                              final l10n = context.l10n;
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _ComposerChip(
                                        label: l10n.chatScopeAbout(scope!.title ?? l10n.conversationTab),
                                        onRemove: () => setState(() => _chatScope = null),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          // Send bar (`.comp`), rising in with the hello.
                          AskRise(
                            animation: _intro,
                            interval: AskIntro.composer,
                            child: SafeArea(
                              bottom: false,
                              maintainBottomViewPadding: false,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 18,
                                  right: 18,
                                  // `.cmp`: 10 pt under the suggestions (their own gap), 16 above the home
                                  // indicator.
                                  top: 0,
                                  bottom: widget.isPivotBottom
                                      ? 6
                                      : (textFieldFocusNode.hasFocus &&
                                              (textController.text.length > 40 || textController.text.contains('\n'))
                                          ? 4
                                          : 16),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Placeholder for the floating LEFT button so the pill
                                        // sits at the right x-position. The actual button is
                                        // rendered as a Positioned overlay below so the pill's
                                        // shadow can't bleed onto it.
                                        if (voiceRecorderProvider.isActive ||
                                            (!voiceRecorderProvider.isActive && shouldShowMenuButton()))
                                          const SizedBox(width: 52),
                                        // CENTER pill — text field/waveform + right-side button stays inside.
                                        Expanded(
                                          child: Container(
                                            // v3 `.field`: 52 pt, a 1 pt ink outline (v8.1: no mic inside).
                                            constraints: const BoxConstraints(minHeight: 52),
                                            padding: const EdgeInsets.only(left: 16, right: 3, top: 3, bottom: 3),
                                            decoration: BoxDecoration(
                                              color: OmiColors.surface0,
                                              borderRadius: const BorderRadius.all(Radius.circular(26)),
                                              border: Border.all(color: OmiColors.textPrimary, width: 1.5),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      if (_selectedContext != null && !voiceRecorderProvider.isActive)
                                                        _SelectedTextChip(
                                                          text: _selectedContext!,
                                                          onRemove: () => setState(() => _selectedContext = null),
                                                        ),
                                                      voiceRecorderProvider.isActive
                                                          ? VoiceRecorderWidget(
                                                              onTranscriptReady: (transcript, autoSend) {
                                                                textController.text = transcript;
                                                                voiceRecorderProvider.close();
                                                                context
                                                                    .read<MessageProvider>()
                                                                    .setNextMessageOriginIsVoice(true);
                                                                if (autoSend && transcript.trim().isNotEmpty) {
                                                                  _sendMessageUtil(transcript.trim());
                                                                }
                                                              },
                                                              onClose: () {
                                                                voiceRecorderProvider.close();
                                                              },
                                                            )
                                                          : Theme(
                                                              data: Theme.of(context).copyWith(
                                                                textSelectionTheme: TextSelectionThemeData(
                                                                  selectionColor:
                                                                      OmiColors.textTertiary.withValues(alpha: 0.4),
                                                                  selectionHandleColor: OmiColors.textPrimary,
                                                                ),
                                                              ),
                                                              child: TextField(
                                                                key: const ValueKey('omi.chat.input'),
                                                                enabled: true,
                                                                controller: textController,
                                                                focusNode: textFieldFocusNode,
                                                                obscureText: false,
                                                                textAlign: TextAlign.start,
                                                                // y: -0.35 nudges glyphs up. Font line metrics
                                                                // place the visual baseline below the line box
                                                                // center, so plain `.center` reads slightly low.
                                                                textAlignVertical: const TextAlignVertical(y: -0.35),
                                                                decoration: InputDecoration(
                                                                  hintText: context.l10n.askAnything,
                                                                  hintStyle: OmiType.callout.copyWith(
                                                                    color: OmiColors.textTertiary,
                                                                  ),
                                                                  focusedBorder: InputBorder.none,
                                                                  enabledBorder: InputBorder.none,
                                                                  contentPadding: const EdgeInsets.symmetric(
                                                                    horizontal: 4,
                                                                    vertical: 10,
                                                                  ),
                                                                  isDense: true,
                                                                ),
                                                                minLines: 1,
                                                                maxLines: 10,
                                                                keyboardType: TextInputType.multiline,
                                                                textCapitalization: TextCapitalization.sentences,
                                                                style: OmiType.callout.copyWith(height: 1.2),
                                                              ),
                                                            ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Right-side button — stays INSIDE the pill.
                                                // Stop fills the draft; Send transcribes and sends.
                                                if (voiceRecorderProvider.state == VoiceRecorderState.recording)
                                                  ChatComposerRoundButton(
                                                    filled: true,
                                                    buttonKey: const ValueKey('omi.chat.voice.transcribe'),
                                                    icon: const Icon(Icons.stop),
                                                    label: context.l10n.stopRecording,
                                                    onPressed: () {
                                                      OmiHaptics.light();
                                                      voiceRecorderProvider.processRecording();
                                                    },
                                                  ),
                                                if (voiceRecorderProvider.state == VoiceRecorderState.recording)
                                                  ChatComposerRoundButton(
                                                    filled: true,
                                                    buttonKey: const ValueKey('omi.chat.voice.send'),
                                                    icon: const FaIcon(FontAwesomeIcons.arrowUp),
                                                    label: context.l10n.chatSendMessage,
                                                    onPressed: () {
                                                      OmiHaptics.medium();
                                                      voiceRecorderProvider.requestAutoSendOnNextTranscript();
                                                      voiceRecorderProvider.processRecording();
                                                    },
                                                  ),
                                                // v8.1: no mic in the field; Ask is typed.
                                              ],
                                            ),
                                          ),
                                        ),
                                        // v3 `#send`: a 52 pt ink circle beside the field.
                                        if (!voiceRecorderProvider.isActive) ...[
                                          const SizedBox(width: 8),
                                          ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: textController,
                                            builder: (context, value, child) {
                                              final canSend = value.text.trim().isNotEmpty &&
                                                  shouldShowSendButton(provider) &&
                                                  !provider.isUploadingFiles &&
                                                  connectivityProvider.isConnected;
                                              return ChatSendButton(
                                                buttonKey: const ValueKey('omi.chat.send'),
                                                label: context.l10n.chatSendMessage,
                                                onPressed: canSend
                                                    ? () {
                                                        OmiHaptics.medium();
                                                        final message = textController.text.trim();
                                                        if (message.isEmpty) return;
                                                        _sendMessageUtil(message);
                                                      }
                                                    : null,
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                    // LEFT button — Discard (voice) or Plus (idle). Rendered AFTER
                                    // the inner Row so it sits on top of the pill's shadow.
                                    if (voiceRecorderProvider.isActive)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(
                                          child: ChatComposerSideButton(
                                            key: const ValueKey('omi.chat.voice.discard'),
                                            icon: const Icon(Icons.close),
                                            label: context.l10n.chatDiscardRecording,
                                            onPressed: () {
                                              OmiHaptics.light();
                                              voiceRecorderProvider.discardRecording();
                                            },
                                          ),
                                        ),
                                      )
                                    else if (!voiceRecorderProvider.isActive && shouldShowMenuButton())
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(
                                          child: PullDownButton(
                                            itemBuilder: (context) => [
                                              PullDownMenuItem(
                                                title: context.l10n.takePhoto,
                                                iconWidget: const FaIcon(FontAwesomeIcons.camera, size: 16),
                                                onTap: () {
                                                  OmiHaptics.selection();
                                                  if (mounted) {
                                                    this.context.read<MessageProvider>().captureImage();
                                                  }
                                                },
                                              ),
                                              PullDownMenuItem(
                                                title: context.l10n.photoLibrary,
                                                iconWidget: const FaIcon(FontAwesomeIcons.images, size: 16),
                                                onTap: () {
                                                  OmiHaptics.selection();
                                                  if (mounted) {
                                                    this.context.read<MessageProvider>().selectImage();
                                                  }
                                                },
                                              ),
                                              PullDownMenuItem(
                                                title: context.l10n.chooseFile,
                                                iconWidget: const FaIcon(FontAwesomeIcons.folder, size: 16),
                                                onTap: () {
                                                  OmiHaptics.selection();
                                                  if (mounted) {
                                                    this.context.read<MessageProvider>().selectFile();
                                                  }
                                                },
                                              ),
                                            ],
                                            position: PullDownMenuPosition.automatic,
                                            buttonBuilder: (context, showMenu) => ChatComposerSideButton(
                                              icon: const OmiGlyph(OmiGlyphs.plusLine, size: 18),
                                              label: context.l10n.chatAddAttachment,
                                              onPressed: () async {
                                                OmiHaptics.light();
                                                if (provider.selectedFiles.length > 3) {
                                                  OmiFeedback.info(context, context.l10n.maxFilesLimit);
                                                  return;
                                                }
                                                if (textFieldFocusNode.hasFocus) {
                                                  FocusScope.of(context).unfocus();
                                                  await Future.delayed(const Duration(milliseconds: 280));
                                                  if (!context.mounted) return;
                                                }
                                                showMenu();
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // v2: Chat is a pushed page, so it shows no tab bar (back returns to the tab). The
                // composer keeps clear of the home indicator while the keyboard is down.
                if (!textFieldFocusNode.hasFocus) SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
              ],
            ),
          ),
        );
      },
    );
  }

  _sendMessageUtil(String text) async {
    var provider = context.read<MessageProvider>();
    // Guard against re-entry (rapid double-tap of send, voice→transcribeSuccess
    // race firing onTranscriptReady twice, etc.). Without this the chat could
    // submit the same text twice and the AI replies twice.
    if (provider.sendingMessage) return;
    String? currentContext = _selectedContext;
    setState(() {
      _selectedContext = null;
    });
    // Remove focus from text field
    FocusManager.instance.primaryFocus?.unfocus();
    if (currentContext != null) {
      text = 'Context: "$currentContext"\n\n$text';
    }

    provider.setSendingMessage(true);
    provider.addMessageLocally(text);
    textController.clear();

    _resumeFollowingAndScroll(delayMs: 300, animated: true);

    await provider.sendMessageStreamToServer(text, context: _chatScope);

    // Plans sheet is shown reactively via _onMessageProviderChanged listener

    provider.clearSelectedFiles();
    provider.setSendingMessage(false);
  }

  /// Sends the message behind a failed reply again (the reply's Try Again).
  Future<void> _retryReply(ServerMessage failed) async {
    final provider = context.read<MessageProvider>();
    if (provider.sendingMessage) return;
    provider.setSendingMessage(true);
    _resumeFollowingAndScroll(animated: true);
    await provider.retryFailedReply(failed);
  }

  void _showPlansSheetOnQuotaExceeded() {
    if (!mounted) return;
    // Refresh subscription data so the plans sheet is up-to-date
    context.read<UsageProvider>().fetchSubscription();
    showOmiSheet<void>(context: context, padding: EdgeInsets.zero, builder: (_) => const PlansSheet());
  }

  sendInitialAppMessage(App? app) async {
    // The provider outlives this page: release the composer even if the page closes mid-request.
    final provider = context.read<MessageProvider>();
    provider.setSendingMessage(true);
    _resumeFollowingAndScroll();
    try {
      final message = await getInitialAppMessage(app?.id);
      if (!mounted) return;
      provider.addMessage(message);
      _resumeFollowingAndScroll();
    } finally {
      provider.setSendingMessage(false);
    }
  }

  void _observeMessagesForAutoScroll(MessageProvider provider) {
    final messages = provider.messages;
    final count = messages.length;
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final lastId = lastMessage?.id;
    final textLength = lastMessage?.text.length ?? 0;
    final thinkingCount = lastMessage?.thinkings.length ?? 0;

    final addedMessages = count > _lastObservedMessageCount;
    final lastMessageChanged = lastId != _lastObservedMessageId;
    final streamedTextChanged = lastId == _lastObservedMessageId && textLength != _lastObservedTextLength;
    final streamedBlocksChanged = lastId == _lastObservedMessageId && thinkingCount != _lastObservedContentBlockCount;

    _lastObservedMessageCount = count;
    _lastObservedMessageId = lastId;
    _lastObservedTextLength = textLength;
    _lastObservedContentBlockCount = thinkingCount;

    if (count == 0) return;

    if (addedMessages && !_hasInitialScrolled) {
      _hasInitialScrolled = true;
      _schedulePostFrameModeAwareScroll();
      return;
    }

    if (_chatScrollMode == ChatScrollMode.followingBottom &&
        (addedMessages || lastMessageChanged || streamedTextChanged || streamedBlocksChanged)) {
      _scheduleModeAwareScroll(delayMs: 0, animated: streamedTextChanged || streamedBlocksChanged);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    final isUserScroll = notification is UserScrollNotification && notification.direction != ScrollDirection.idle;
    final isDragScroll = notification is ScrollUpdateNotification && notification.dragDetails != null;

    if (_isProgrammaticScroll && !isUserScroll && !isDragScroll) return false;

    final next = ChatScrollPolicy.nextMode(
      current: _chatScrollMode,
      isUserOrDragScroll: isUserScroll || isDragScroll,
      atLiveEdge: ChatScrollPolicy.atLiveEdge(notification.metrics),
    );
    if (next == null) {
      if (_chatScrollMode == ChatScrollMode.freeScrolling && (isUserScroll || isDragScroll)) {
        _showLatestJumpOnActivity();
      }
      return false;
    }

    _chatScrollMode = next;
    _cancelPendingScrolls();
    if (next == ChatScrollMode.freeScrolling) {
      _showLatestJumpOnActivity();
    } else {
      _latestJumpIdleTimer?.cancel();
      _showLatestJump = false;
    }
    if (mounted) setState(() {});
    return false;
  }

  void _showLatestJumpOnActivity() {
    _latestJumpIdleTimer?.cancel();
    if (!_showLatestJump) {
      _showLatestJump = true;
      if (mounted) setState(() {});
    }
    _latestJumpIdleTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _chatScrollMode != ChatScrollMode.freeScrolling) return;
      setState(() => _showLatestJump = false);
    });
  }

  Widget _buildJumpToLatestButton() {
    return ChatJumpToLatestButton(label: context.l10n.latest, onTap: () => _resumeFollowingAndScroll(animated: true));
  }

  void scrollToBottomOnSend() {
    _resumeFollowingAndScroll(animated: true);
  }

  void _resumeFollowingAndScroll({int delayMs = 0, bool animated = false}) {
    _cancelPendingScrolls();
    _latestJumpIdleTimer?.cancel();
    _showLatestJump = false;
    _chatScrollMode = ChatScrollMode.followingBottom;
    if (mounted) setState(() {});
    _scheduleModeAwareScroll(delayMs: delayMs, animated: animated, force: true);
  }

  void _schedulePostFrameModeAwareScroll({bool animated = false, bool force = false}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleModeAwareScroll(delayMs: 0, animated: animated, force: force);
    });
  }

  void _scheduleModeAwareScroll({int delayMs = 50, bool animated = false, bool force = false}) {
    final timer = Timer(Duration(milliseconds: delayMs), () {
      _pendingScrollTimers.removeWhere((candidate) => !candidate.isActive);
      if (!mounted) return;
      _scrollToBottom(animated: animated, force: force);
    });
    _pendingScrollTimers.add(timer);
  }

  void _cancelPendingScrolls() {
    for (final timer in _pendingScrollTimers) {
      timer.cancel();
    }
    _pendingScrollTimers.clear();
  }

  void scrollToBottom({bool animated = false}) {
    _scrollToBottom(animated: animated);
  }

  void _scrollToBottom({bool animated = false, bool force = false}) {
    if (!scrollController.hasClients) return;
    if (!force && _chatScrollMode != ChatScrollMode.followingBottom) return;

    final position = scrollController.position;
    final target = position.maxScrollExtent;
    final distance = (target - position.pixels).abs();
    if (distance <= 20) return;

    _isProgrammaticScroll = true;

    if (distance > 350 || !animated) {
      scrollController.jumpTo(target);
      _isProgrammaticScroll = false;
      return;
    }

    scrollController
        .animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut)
        .whenComplete(() => _isProgrammaticScroll = false);
  }

  void _selectApp(String appId, AppProvider appProvider) async {
    if (!mounted) return;

    // Mark that we're no longer on initial load to prevent auto-focus
    _isInitialLoad = false;

    // Store references before async operation
    final messageProvider = mounted ? context.read<MessageProvider>() : null;
    if (messageProvider == null) return;

    // Set the selected app
    appProvider.setSelectedChatAppId(appId);

    // Add a small delay to let the keyboard animation complete
    // This prevents the widget from being unmounted during the keyboard transition
    await Future.delayed(const Duration(milliseconds: 100));

    // Check if widget is still mounted after delay
    if (!mounted) return;

    // Perform async operation
    await messageProvider.refreshMessages(dropdownSelected: true);

    // Check if widget is still mounted before proceeding
    if (!mounted) return;

    // Get the selected app and send initial message if needed
    var app = appProvider.getSelectedApp();
    if (messageProvider.messages.isEmpty) {
      messageProvider.sendInitialAppMessage(app);
    }
  }

  /// Past chats: a fresh chat, a chat app, or an earlier chat.
  Future<void> _openPastChats() async {
    FocusScope.of(context).unfocus();
    OmiHaptics.selection();
    final appProvider = context.read<AppProvider>();
    final provider = context.read<MessageProvider>();
    await routeToPage(
      context,
      PastChatsPage(
        onNewChat: () {
          appProvider.setSelectedChatAppId(null);
          _chatScope = null;
          provider.startFreshChat();
          _playIntro();
        },
        onOpen: (session) {
          appProvider.setSelectedChatAppId(null);
          _intro.value = 1;
          _hasInitialScrolled = false;
          unawaited(provider.openChatSession(session));
        },
        onPickApp: (app) {
          _intro.value = 1;
          _selectApp(app.id, appProvider);
        },
      ),
    );
  }

  /// v3 Ask header (`#chat .sh`): a 38 pt close ring, the sheet's handle (or the chat app's name),
  /// and Past chats.
  PreferredSizeWidget _buildAppBar(BuildContext context, MessageProvider provider) {
    final l10n = context.l10n;
    return PreferredSize(
      preferredSize: Size.fromHeight(56 + (provider.isLoadingMessages ? 32 : 0)),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    OmiRingButton(
                      key: const Key('chat_close'),
                      glyph: OmiGlyphs.close,
                      glyphSize: 16,
                      size: 38,
                      label: MaterialLocalizations.of(context).closeButtonLabel,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Center(
                        child: Consumer<AppProvider>(
                          builder: (context, appProvider, child) {
                            final selectedApp =
                                provider.chatApps.firstWhereOrNull((app) => app.id == appProvider.selectedChatAppId);
                            if (selectedApp == null) {
                              return Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(color: OmiColors.outline, borderRadius: OmiRadius.pillAll),
                              );
                            }
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ChatAppAvatar(app: selectedApp),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 160),
                                  child: Text(selectedApp.getName(),
                                      style: OmiType.headline.copyWith(fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    OmiRingButton(
                      key: const Key('chat_history'),
                      glyph: OmiGlyphs.history,
                      size: 38,
                      label: l10n.pastChats,
                      onPressed: _openPastChats,
                    ),
                  ],
                ),
              ),
            ),
            if (provider.isLoadingMessages)
              SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const OmiSpinner(size: OmiSpinnerSize.small),
                    const SizedBox(width: OmiSpacing.xs),
                    Text(l10n.syncingMessages, style: OmiType.footnote.copyWith(color: OmiColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "You're offline" above the composer; Send is disabled until the connection returns.
class _OfflineHint extends StatelessWidget {
  const _OfflineHint();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(OmiSpacing.md, OmiSpacing.xs, OmiSpacing.md, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(child: Icon(Icons.cloud_off_rounded, size: 14, color: OmiColors.textTertiary)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.l10n.chatOfflineHint,
                style: OmiType.footnote.copyWith(color: OmiColors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small chip above or inside the composer with a remove control (the conversation scope).
class _ComposerChip extends StatelessWidget {
  const _ComposerChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: MaterialLocalizations.of(context).deleteButtonTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kOmiMinTapTarget),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: OmiSpacing.sm, vertical: 6),
              decoration: BoxDecoration(
                color: OmiColors.surface2,
                borderRadius: OmiRadius.lgAll,
                border: Border.all(color: OmiColors.textTertiary),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OmiType.footnote.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 14, color: OmiColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quoted text the next message asks about ("Ask Omi" on a selection), with a remove control.
class _SelectedTextChip extends StatelessWidget {
  const _SelectedTextChip({required this.text, required this.onRemove});

  final String text;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: OmiSpacing.xxs, left: 2),
      child: Container(
        decoration: BoxDecoration(color: OmiColors.surface2, borderRadius: OmiRadius.lgAll),
        padding: const EdgeInsets.only(left: OmiSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.subdirectory_arrow_right, size: 14, color: OmiColors.textSecondary),
            ),
            const SizedBox(width: OmiSpacing.xs),
            Flexible(
              child: Text(
                text,
                style: OmiType.subhead.copyWith(color: OmiColors.textSecondary, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            OmiIconButton(
              icon: const Icon(Icons.close, size: 16),
              label: context.l10n.chatRemoveSelectedText,
              color: OmiColors.textSecondary,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
