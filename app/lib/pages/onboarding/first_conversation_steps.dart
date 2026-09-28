import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversation_detail/conversation_summary_selection.dart';
import 'package:omi/pages/conversation_detail/widgets/conversation_todos.dart';
import 'package:omi/pages/conversation_detail/widgets/summary_v3.dart';
import 'package:omi/pages/onboarding/widgets/onboarding_card.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';

/// "Say a few words." (v3 `first`): Omi listens for real, on this phone or on the pendant, with a
/// running clock, and the words it hears appear one by one. Done (ready once something was heard)
/// ends this first conversation so Omi writes it up. If nothing is heard for a while, "Skip for
/// now" appears.
class OnboardingFirstWordsStep extends StatefulWidget {
  const OnboardingFirstWordsStep({
    super.key,
    required this.wearable,
    required this.onDone,
    required this.onSkip,
    this.onFinishing,
    this.quietFor = const Duration(seconds: 12),
  });

  /// Just before Done ends the recording (the flow notes which conversations already exist).
  final VoidCallback? onFinishing;

  /// The pendant is listening (it already is, since it paired); otherwise this phone starts.
  final bool wearable;

  /// Done: the conversation is being written up.
  final VoidCallback onDone;
  final VoidCallback onSkip;

  /// How long nothing may be heard before "Skip for now" shows.
  final Duration quietFor;

  @override
  State<OnboardingFirstWordsStep> createState() => _OnboardingFirstWordsStepState();
}

class _OnboardingFirstWordsStepState extends State<OnboardingFirstWordsStep> {
  late final CaptureProvider _capture = context.read<CaptureProvider>();
  Timer? _clock;

  /// Half-seconds since the step opened (the clock beside "Listening").
  int _ticks = 0;

  /// Words the pendant heard before this step (while pairing) stay out of the live words.
  int _baseline = 0;
  bool _startedPhone = false;
  bool _failed = false;
  bool _finishing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _baseline = widget.wearable ? _capture.segments.length : 0;
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _ticks++);
    });
    if (!widget.wearable) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startPhone()));
  }

  Future<void> _startPhone() async {
    if (_capture.liveCaptureSource == 'phone') return;
    try {
      await _capture.streamRecording();
      _startedPhone = true;
    } catch (e) {
      Logger.debug('Onboarding first recording did not start: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    // Leaving without Done (Back) stops the phone rather than recording on behind the flow.
    if (_startedPhone && !_finished) unawaited(_capture.stopStreamRecording().then((_) {}, onError: (_) {}));
    super.dispose();
  }

  List<String> _words(CaptureProvider capture) {
    final segments = capture.segments;
    final from = segments.length < _baseline ? 0 : _baseline;
    return segments
        .skip(from)
        .map((s) => s.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  Future<void> _done() async {
    if (_finishing) return;
    OmiHaptics.selection();
    setState(() => _finishing = true);
    widget.onFinishing?.call();
    try {
      await _capture.finishCapture();
      _finished = true;
    } catch (e) {
      Logger.debug('Onboarding first recording did not finish: $e');
    }
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capture = context.watch<CaptureProvider>();
    final words = _words(capture);
    final elapsed = Duration(milliseconds: 500 * _ticks);
    final quiet = words.isEmpty && (_failed || elapsed >= widget.quietFor);
    final listening = widget.wearable || capture.recordingState == RecordingState.record || _startedPhone;
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          if (widget.wearable) const OnboardingBluetoothBanner(),
          OnboardingHeader(title: l10n.sayAFewWords, subtitle: l10n.tryRemindSam),
          const SizedBox(height: 36),
          if (listening || !_failed)
            OnboardingListeningRow(
              key: const Key('onboarding_first_listening'),
              label: widget.wearable ? l10n.listeningOnYourOmi : l10n.listeningOnThisPhone,
              detail: OmiDuration.offset(elapsed.inSeconds),
            ),
          // `.oblive`'s 14 pt, from the row's line box.
          const SizedBox(height: 12),
          // `.oblive`: the words at 26/500, each fading in as it arrives.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 83),
            child: Semantics(
              liveRegion: true,
              label: words.join(' '),
              excludeSemantics: true,
              child: Wrap(
                key: const Key('onboarding_first_words'),
                children: [
                  for (final (i, word) in words.indexed) _FadeInWord(key: ValueKey('w$i-$word'), word: '$word '),
                ],
              ),
            ),
          ),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_first_done'),
            label: l10n.done,
            expand: true,
            isLoading: _finishing,
            onPressed: words.isEmpty || _finishing ? null : _done,
          ),
          if (quiet)
            OnboardingLink(
              key: const Key('onboarding_first_skip'),
              label: l10n.skipForNowV3,
              onTap: widget.onSkip,
            ),
        ],
      ),
    );
  }
}

/// One heard word (`.oblive span`): fades in over 0.35 s.
class _FadeInWord extends StatefulWidget {
  const _FadeInWord({super.key, required this.word});

  final String word;

  @override
  State<_FadeInWord> createState() => _FadeInWordState();
}

class _FadeInWordState extends State<_FadeInWord> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _in.value = 1;
    } else if (_in.value == 0 && !_in.isAnimating) {
      _in.forward();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _in, child: Text(widget.word, style: OmiType.liveWords));
  }
}

enum _Result { waiting, ready, stillWriting, tooShort }

/// "Your first conversation" (v3 `result`): "Omi is writing it up…" until the conversation Done
/// ended comes back processed, then its title, "Just now · 6 s · this phone", the summary, its
/// to-dos and a line on where conversations live. A recording too short to write up, or one that
/// takes longer than [timeout], says so and moves on.
class OnboardingFirstResultStep extends StatefulWidget {
  const OnboardingFirstResultStep({
    super.key,
    required this.knownIds,
    required this.wearable,
    required this.onContinue,
    this.timeout = const Duration(seconds: 60),
    this.settle = const Duration(milliseconds: 1500),
  });

  /// Conversations that existed before Done: the new one is the one not in here.
  final Set<String> knownIds;
  final bool wearable;
  final VoidCallback onContinue;
  final Duration timeout;

  /// How long nothing in flight must last before it counts as too short (processing hands the
  /// conversation from the in-flight list to the list in two steps).
  final Duration settle;

  @override
  State<OnboardingFirstResultStep> createState() => _OnboardingFirstResultStepState();
}

class _OnboardingFirstResultStepState extends State<OnboardingFirstResultStep> {
  late final ConversationProvider _conversations = context.read<ConversationProvider>();
  _Result _state = _Result.waiting;
  ServerConversation? _conversation;
  Timer? _timeout;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _conversations.addListener(_check);
    _timeout = Timer(widget.timeout, () {
      if (mounted && _state == _Result.waiting) setState(() => _state = _Result.stillWriting);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _conversations.removeListener(_check);
    _timeout?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  ServerConversation? _newest() {
    for (final c in _conversations.conversations) {
      if (!widget.knownIds.contains(c.id)) return c;
    }
    return null;
  }

  bool get _inFlight => _conversations.processingConversations.any((c) => !widget.knownIds.contains(c.id));

  void _check() {
    if (!mounted || _state == _Result.ready) return;
    final found = _newest();
    if (found != null && !found.discarded && found.status == ConversationStatus.completed) {
      _settle?.cancel();
      OmiHaptics.success();
      setState(() {
        _conversation = found;
        _state = _Result.ready;
      });
      return;
    }
    if (found != null && found.discarded) {
      _settle?.cancel();
      setState(() => _state = _Result.tooShort);
      return;
    }
    if (found != null || _inFlight) {
      _settle?.cancel();
      return;
    }
    // Nothing new and nothing in flight: wait a moment for the hand-over, then call it too short.
    _settle ??= Timer(widget.settle, () {
      _settle = null;
      if (!mounted || _state != _Result.waiting) return;
      if (_newest() == null && !_inFlight) setState(() => _state = _Result.tooShort);
    });
  }

  static TextStyle get _noteStyle => OmiType.subhead.copyWith(height: 1.45, color: OmiColors.textSecondary);

  String _length(BuildContext context, ServerConversation conversation) {
    final l10n = context.l10n;
    final seconds = conversation.getDurationInSeconds();
    if (seconds < 60) return l10n.timeCompactSecs(seconds < 1 ? 1 : seconds);
    return l10n.minutesShortV3((seconds / 60).round());
  }

  Widget _waiting(BuildContext context) {
    return Padding(
      key: const ValueKey('waiting'),
      padding: const EdgeInsets.only(top: 40),
      child: Row(
        children: [
          const OnboardingLiveDot(),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.l10n.omiWritingItUp,
              style: OmiType.callout.copyWith(color: OmiColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, Key key) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 40),
      child: Text(text, style: OnboardingHeader.bodyStyle),
    );
  }

  Widget _ready(BuildContext context, ServerConversation conversation) {
    final l10n = context.l10n;
    final summary = ConversationSummarySelection.select(conversation).content.trim();
    final todos = conversation.structured.actionItems.where((i) => !i.deleted).toList();
    final title = conversation.structured.title.trim();
    return Column(
      key: const ValueKey('ready'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingKicker(l10n.yourFirstConversation),
        OnboardingHeader(title: title.isEmpty ? l10n.untitledConversation : title),
        const SizedBox(height: 11),
        OmiPillChip(
          key: const Key('onboarding_result_chip'),
          label: l10n.justNowLength(
            _length(context, conversation),
            widget.wearable ? l10n.omiPendantName : l10n.sourceThisPhone,
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          // `.sum.obsum`: "Summary" over what was said.
          SummaryV3(markdown: summary.startsWith('#') ? summary : '## ${l10n.summary}\n$summary'),
        ],
        if (todos.isNotEmpty) ...[
          // `h2`'s 28 pt, less the last bullet's own room under it.
          OmiSectionLabel(title: l10n.toDoFromThis, top: 22, bottom: 6),
          ConversationTodos(conversation: conversation, todos: todos),
        ],
        const SizedBox(height: 22),
        // `.obp` at 15 pt: 32ch wide.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: OnboardingHeader.bodyMaxWidth(context, _noteStyle)),
          child: Text(l10n.everyConversationPage, style: _noteStyle),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conversation = _conversation;
    final body = switch (_state) {
      _Result.waiting => _waiting(context),
      _Result.ready => _ready(context, conversation!),
      _Result.stillWriting => _message(l10n.stillWritingItUp, const ValueKey('still')),
      _Result.tooShort => _message(l10n.notEnoughToWrite, const ValueKey('short')),
    };
    final motion = OmiMotion.of(context);
    return OnboardingStep(
      card: OnboardingCard(
        content: [
          if (widget.wearable) const OnboardingBluetoothBanner(),
          // `obIn`: the written-up page slides in 16 pt from the side as it fades in.
          AnimatedSwitcher(
            // 380 ms (`obIn`); none under Reduce Motion.
            duration: motion.standard == Duration.zero ? Duration.zero : const Duration(milliseconds: 380),
            switchInCurve: const Cubic(0.2, 0.8, 0.2, 1),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous.map((p) => Offstage(child: p)), if (current != null) current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) =>
                    Transform.translate(offset: Offset(16 * (1 - animation.value), 0), child: child),
              ),
            ),
            child: body,
          ),
        ],
        footer: [
          OmiButton(
            key: const Key('onboarding_result_continue'),
            label: l10n.continueButton,
            expand: true,
            onPressed: _state == _Result.waiting
                ? null
                : () {
                    OmiHaptics.selection();
                    widget.onContinue();
                  },
          ),
        ],
      ),
    );
  }
}
