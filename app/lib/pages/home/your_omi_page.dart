import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/pages/conversations/open_conversation.dart';
import 'package:omi/pages/conversations/widgets/live_capture_card.dart';
import 'package:omi/pages/conversations/widgets/processing_capture.dart';
import 'package:omi/pages/devices/devices_screen.dart';
import 'package:omi/pages/devices/light_legend_page.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart' show OmiDeviceTile;
import 'package:omi/pages/home/widgets/home_recorder_actions.dart';
import 'package:omi/pages/home/widgets/home_top_bar.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/services/devices/bluetooth_readiness.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/other/temp.dart';
import 'package:omi/widgets/capture_sources.dart';

/// Opens Your Omi, unrolling down from the Listening label.
Future<void> openYourOmi(BuildContext context) {
  return Navigator.of(context).push(omiUnrollRoute<void>(builder: (_) => const YourOmiPage()));
}

/// Your Omi (v8.4–v8.16 `#omisc`): the recording itself. The Omi mark over a large clock, what Omi
/// is doing, and the device it records from; a warning when something needs fixing and the sync
/// line; the last few lines of what is being said (tap for the full transcript); then Pause (or
/// Resume, or Start) and Stop in a glass dock. Stop writes the conversation up right there
/// ("Writing up your notes", then "Notes ready · Open").
class YourOmiPage extends StatefulWidget {
  const YourOmiPage({super.key});

  @override
  State<YourOmiPage> createState() => _YourOmiPageState();
}

enum _Notes { writing, ready }

class _YourOmiPageState extends State<YourOmiPage> {
  Timer? _clock;

  // After Stop: the conversations there were before, and where the write-up is.
  Set<String>? _knownIds;
  _Notes? _notes;
  ServerConversation? _written;
  Timer? _notesTimeout;
  Timer? _notesSettle;
  Timer? _notesHide;
  ConversationProvider? _conversations;

  @override
  void initState() {
    super.initState();
    // The clock counts seconds.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _notesTimeout?.cancel();
    _notesSettle?.cancel();
    _notesHide?.cancel();
    _conversations?.removeListener(_checkNotes);
    super.dispose();
  }

  void _stop(LiveCaptureCard card) {
    final onFinish = card.onFinish;
    if (onFinish == null) return;
    final capture = context.read<CaptureProvider>();
    final heard = capture.segments.isNotEmpty || capture.photos.isNotEmpty;
    final conversations = context.read<ConversationProvider>();
    _knownIds = {
      for (final c in conversations.conversations) c.id,
      for (final c in conversations.processingConversations) c.id,
    };
    onFinish();
    OmiFeedback.info(context, context.l10n.stoppedV3);
    if (!heard) return;
    setState(() {
      _notes = _Notes.writing;
      _written = null;
    });
    _conversations?.removeListener(_checkNotes);
    _conversations = conversations..addListener(_checkNotes);
    _notesTimeout?.cancel();
    _notesTimeout = Timer(const Duration(seconds: 90), _hideNotes);
  }

  bool get _notesInFlight =>
      _conversations?.processingConversations.any((c) => !(_knownIds?.contains(c.id) ?? true)) ?? false;

  void _checkNotes() {
    if (!mounted || _notes != _Notes.writing) return;
    final known = _knownIds ?? const {};
    ServerConversation? found;
    for (final c in _conversations!.conversations) {
      if (!known.contains(c.id)) {
        found = c;
        break;
      }
    }
    if (found != null && !found.discarded && found.status == ConversationStatus.completed) {
      _notesSettle?.cancel();
      OmiHaptics.success();
      setState(() {
        _notes = _Notes.ready;
        _written = found;
      });
      _notesHide?.cancel();
      _notesHide = Timer(const Duration(seconds: 12), _hideNotes);
      return;
    }
    if (found != null && found.discarded) return _hideNotes();
    if (found != null || _notesInFlight) {
      _notesSettle?.cancel();
      _notesSettle = null;
      return;
    }
    _notesSettle ??= Timer(const Duration(seconds: 3), () {
      _notesSettle = null;
      if (mounted && _notes == _Notes.writing && !_notesInFlight) _hideNotes();
    });
  }

  void _hideNotes() {
    _conversations?.removeListener(_checkNotes);
    _notesTimeout?.cancel();
    _notesHide?.cancel();
    if (!mounted) return;
    setState(() {
      _notes = null;
      _written = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // `#omisc .sh`: 19 pt under the status bar, 22 pt in; back, the title, the light legend.
            Padding(
              padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 19, OmiSize.screenMargin, 0),
              child: SizedBox(
                height: 50,
                child: Row(
                  children: [
                    OmiRingButton.glass(
                      key: const Key('your_omi_back'),
                      glyph: OmiGlyphs.back,
                      label: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.yourOmi,
                          textAlign: TextAlign.center,
                          style:
                              OmiType.headline.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.34, height: 1.4),
                        ),
                      ),
                    ),
                    OmiRingButton.glass(
                      key: const Key('your_omi_lights'),
                      glyph: OmiGlyphs.bulb,
                      label: l10n.whatTheLightMeans,
                      onPressed: () => showLightLegend(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, bottom + 14),
                child: ConversationCaptureWidget(
                  showsCall: true,
                  present: (card) => _YourOmiBody(
                    card: card,
                    notes: _notes,
                    written: _written,
                    onStop: card == null ? null : () => _stop(card),
                    onOpenWritten: () {
                      final written = _written;
                      _hideNotes();
                      if (written != null) openConversationDetail(context, written);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything under the header, from one state of the capture ([card] is null while nothing
/// records).
class _YourOmiBody extends StatelessWidget {
  const _YourOmiBody({
    required this.card,
    required this.notes,
    required this.written,
    required this.onStop,
    required this.onOpenWritten,
  });

  final LiveCaptureCard? card;
  final _Notes? notes;
  final ServerConversation? written;
  final VoidCallback? onStop;
  final VoidCallback onOpenWritten;

  /// `08:04`: minutes and seconds, both two digits; hours in front once there are any.
  static String clock(Duration? elapsed) {
    final total = math.max(0, elapsed?.inSeconds ?? 0);
    final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = HomeListeningLabel.watch(context);
    final c = card;
    final live = c != null && c.live && state == HomeRecorderState.listening;
    final phone = c?.source == 'phone';
    final status = switch (state) {
      HomeRecorderState.listening => phone ? l10n.listeningOnThisPhone : l10n.listening,
      HomeRecorderState.paused => l10n.paused,
      HomeRecorderState.off => l10n.off,
      HomeRecorderState.bluetoothOff => l10n.bluetoothOffV3,
      HomeRecorderState.notFound => l10n.omiNotFound,
      HomeRecorderState.reconnecting => l10n.reconnectingV3,
    };
    final device = _DeviceInfo.of(context, card: c, state: state);
    final warnings = <Widget>[
      if (state == HomeRecorderState.bluetoothOff)
        _Warning(
          key: const Key('your_omi_bluetooth_off'),
          text: l10n.turnOnBluetoothToKeep(device.name),
          action: l10n.turnOn,
          onAction: () => BluetoothReadiness.instance.ensureReady(BluetoothUse.connection),
        )
      else if (device.battery != null && device.battery! >= 0 && device.battery! <= 10)
        _Warning(key: const Key('your_omi_low_battery'), text: l10n.deviceLowBattery(device.name, device.battery!))
      else if (c?.explanation != null)
        _Warning(key: const Key('your_omi_warning'), text: c!.explanation!),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // `.osbody`: a quarter of the screen's body, never under 150 pt.
        final transcriptHeight = math.max(150.0, constraints.maxHeight * 0.26);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Hero(state: state, live: live, elapsed: c?.elapsed, status: status, device: device),
            ),
            for (final w in warnings) ...[w, const SizedBox(height: 14)],
            _SyncLine(disconnected: device.wearable && !device.connected, deviceName: device.name),
            SizedBox(
              height: transcriptHeight,
              child: _TranscriptCard(
                showsTranscript: c != null && c.showsTranscript && c.source != LiveCaptureCard.callSource,
                notes: notes,
                written: written,
                onOpenWritten: onOpenWritten,
              ),
            ),
            const SizedBox(height: 14),
            Center(child: _Dock(card: c, state: state, onStop: onStop)),
            const SizedBox(height: 14),
            Text(
              l10n.onlyYouSeeRecordings,
              textAlign: TextAlign.center,
              style: OmiType.fine.copyWith(color: OmiColors.textSecondary, height: 1.45),
            ),
          ],
        );
      },
    );
  }
}

/// The device Your Omi records from: its name, picture, battery and whether it is connected.
class _DeviceInfo {
  const _DeviceInfo({
    required this.name,
    required this.visual,
    required this.wearable,
    required this.connected,
    this.battery,
  });

  final String name;
  final Widget visual;
  final bool wearable;
  final bool connected;
  final int? battery;

  static _DeviceInfo of(BuildContext context, {required LiveCaptureCard? card, required HomeRecorderState state}) {
    final l10n = context.l10n;
    final (pairedName, pairedType, connected, battery) =
        context.select<DeviceProvider, (String?, DeviceType?, bool, int)>((d) => (
              d.pairedDevice?.name,
              d.pairedDevice?.type,
              d.connectedDevice != null,
              d.connectedDevice == null ? -1 : d.batteryLevel,
            ));
    final phoneName = Platform.isIOS ? l10n.memoryThisIphone : l10n.memoryThisPhone;
    final source = card?.source;
    final usesPhone = source == 'phone' || (source == null && (pairedName ?? '').trim().isEmpty);
    if (usesPhone) {
      return _DeviceInfo(
        name: phoneName,
        visual: const OmiDeviceTile(icon: OmiGlyphs.devicePhone, size: 24, glyph: 15, radius: 7),
        wearable: false,
        connected: true,
      );
    }
    final name = (pairedName ?? '').trim().isNotEmpty
        ? pairedName!.trim()
        : CaptureSources.label(context, source ?? 'omi');
    final omi = pairedType == null || pairedType == DeviceType.omi;
    return _DeviceInfo(
      name: name,
      visual: omi
          ? OmiOrb(size: 24, live: connected)
          : OmiDeviceTile(icon: OmiGlyphs.forSource(source ?? 'omi'), size: 24, glyph: 15, radius: 7),
      wearable: true,
      connected: connected,
      battery: connected && battery >= 0 ? battery : null,
    );
  }
}

/// `.os4hero`: the mark (88 pt, growing in as the screen opens), the clock, what Omi is doing and
/// the device, centred in the room above the transcript.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.state,
    required this.live,
    required this.elapsed,
    required this.status,
    required this.device,
  });

  final HomeRecorderState state;
  final bool live;
  final Duration? elapsed;
  final String status;
  final _DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final syncing = context.select<SyncProvider?, bool>((s) => s?.isSyncing ?? false);
    final turn = state == HomeRecorderState.reconnecting
        ? OmiRingTurn.reconnect
        : syncing
            ? OmiRingTurn.sync
            : OmiRingTurn.none;
    final dim = state == HomeRecorderState.off;
    final detail = device.connected || !device.wearable
        ? (device.battery == null ? null : '${device.battery}%')
        : l10n.notConnectedV3;
    return Center(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `#osRng`: from 60 % to full size with a small overshoot as the screen unrolls.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: OmiMotion.of(context).standard == Duration.zero
                  ? Duration.zero
                  : const Duration(milliseconds: 580),
              curve: const Interval(0.14, 1, curve: Cubic(0.34, 1.4, 0.64, 1)),
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: OmiRingLogo(
                key: const Key('your_omi_mark'),
                size: 88,
                color: dim ? OmiColors.textTertiary : OmiColors.textPrimary,
                mode: live ? OmiRingMode.wave : OmiRingMode.still,
                turn: turn,
              ),
            ),
            const SizedBox(height: 18),
            AnimatedOpacity(
              opacity: live ? 1 : 0.35,
              duration: const Duration(milliseconds: 300),
              child: Text(
                _YourOmiBody.clock(elapsed),
                key: const Key('your_omi_clock'),
                style: OmiType.liveClock,
              ),
            ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                status,
                key: const Key('your_omi_status'),
                style: OmiType.subhead.copyWith(fontWeight: FontWeight.w500, color: OmiColors.textSecondary),
              ),
            ),
            const SizedBox(height: 14),
            // `.osdv`: the device, which opens Devices.
            Semantics(
              button: true,
              label: [device.name, if (detail != null) detail].join(', '),
              hint: l10n.switchDevice,
              excludeSemantics: true,
              child: OmiPressable(
                key: const Key('your_omi_device'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  OmiHaptics.selection();
                  routeToPage(context, const DevicesScreen());
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: OmiColors.surface0,
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(dimension: 24, child: ExcludeSemantics(child: device.visual)),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OmiType.cardSubtitle.copyWith(fontWeight: FontWeight.w500, height: 1.4)),
                      ),
                      if (detail != null) ...[
                        const SizedBox(width: 7),
                        Text(detail,
                            style: OmiType.cardSubtitle.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                      ],
                      const SizedBox(width: 7),
                      OmiGlyph(OmiGlyphs.chevronDown, size: 14, color: OmiColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A problem Your Omi explains (`.oswarn`): red words on a pale red card, with an action.
class _Warning extends StatelessWidget {
  const _Warning({super.key, required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final style = OmiType.callout.copyWith(color: OmiColors.danger, height: 1.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: OmiColors.dangerSurface, borderRadius: const BorderRadius.all(Radius.circular(14))),
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (action != null && onAction != null) ...[
            const SizedBox(width: 12),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  OmiHaptics.selection();
                  onAction!();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: OmiSize.minTap),
                  child: Center(
                    child: Text(
                      action!,
                      style: style.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: OmiColors.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The sync line (`.ossync`): while recordings come off the pendant, "Syncing to your phone · 11 min
/// left" over a 3 pt bar; while it is away, how much it holds for later.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.disconnected, required this.deviceName});

  final bool disconnected;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sync = context.watch<SyncProvider?>();
    if (sync == null) return const SizedBox.shrink();
    final line = OmiType.subhead.copyWith(height: 1.4, color: OmiColors.ink80);
    if (disconnected) {
      final minutes = (sync.missingWalsInSeconds / 60).round();
      if (minutes < 1) return const SizedBox.shrink();
      final text = l10n.minutesSavedOnDevice(minutes, deviceName);
      final lead = l10n.minutesShortV3(minutes);
      final bold = text.startsWith(lead);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text.rich(
          key: const Key('your_omi_saved'),
          TextSpan(children: [
            if (bold) TextSpan(text: lead, style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: bold ? text.substring(lead.length) : text),
          ]),
          style: line,
        ),
      );
    }
    if (!(sync.isSyncing || sync.isFetchingConversations)) return const SizedBox.shrink();
    final progress = sync.walsSyncedProgress.clamp(0.0, 1.0);
    final done = sync.isFetchingConversations || progress >= 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        key: const Key('your_omi_sync'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(done ? l10n.pendantRecordingsSynced : l10n.syncingToYourPhone,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
              ),
              if (!done) Text(l10n.minutesLeft((sync.missingWalsInSeconds / 60).ceil()), style: line),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: OmiColors.textPrimary.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(OmiColors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the live transcript: who said it and what, consecutive words of one speaker joined.
class _Line {
  const _Line(this.speaker, this.initial, this.isUser, this.text);

  final String speaker;
  final String initial;
  final bool isUser;
  final String text;

  static List<_Line> of(BuildContext context, List<TranscriptSegment> segments) {
    final people = context.watch<PeopleProvider?>()?.people ?? SharedPreferencesUtil().cachedPeople;
    final names = SpeakerNames.forSegments(segments, people: people, l10n: context.l10n);
    final lines = <_Line>[];
    TranscriptSegment? previous;
    for (final segment in segments) {
      final text = segment.text.trim();
      if (text.isEmpty) continue;
      final name = names.forSegment(segment);
      final same = previous != null &&
          previous.isUser == segment.isUser &&
          previous.speakerId == segment.speakerId &&
          previous.personId == segment.personId;
      if (same && lines.isNotEmpty) {
        final last = lines.removeLast();
        lines.add(_Line(last.speaker, last.initial, last.isUser, '${last.text} $text'));
      } else {
        final initial = name.characters.isEmpty ? '?' : name.characters.first.toUpperCase();
        lines.add(_Line(name, initial, segment.isUser, text));
      }
      previous = segment;
    }
    return lines;
  }
}

/// `.osbody`: the last lines of what is being said, the newest in ink and the rest greyed, each by
/// the speaker's initial (yours filled). It follows the newest words unless scrolled back ("New
/// words ↓" returns). Tapping it opens the full transcript. After Stop it shows the write-up.
class _TranscriptCard extends StatefulWidget {
  const _TranscriptCard({
    required this.showsTranscript,
    required this.notes,
    required this.written,
    required this.onOpenWritten,
  });

  final bool showsTranscript;
  final _Notes? notes;
  final ServerConversation? written;
  final VoidCallback onOpenWritten;

  @override
  State<_TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<_TranscriptCard> {
  final ScrollController _scroll = ScrollController();
  bool _stick = true;
  bool _newBelow = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final near = _scroll.position.maxScrollExtent - _scroll.position.pixels < 24;
      if (near != _stick || (near && _newBelow)) {
        setState(() {
          _stick = near;
          if (near) _newBelow = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int count) {
    if (count == _lastCount) return;
    final grew = count > _lastCount;
    _lastCount = count;
    if (!grew) return;
    if (_stick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } else if (!_newBelow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _newBelow = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final segments = widget.showsTranscript ? context.watch<CaptureProvider>().segments : const <TranscriptSegment>[];
    final lines = _Line.of(context, segments);
    _follow(lines.length);
    final notes = widget.notes;
    Widget body;
    if (notes != null) {
      body = _NotesState(notes: notes, written: widget.written, onOpen: widget.onOpenWritten);
    } else if (lines.isEmpty) {
      body = Align(
        alignment: AlignmentDirectional.bottomStart,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.wordsShowUpHere, style: OmiType.transcriptLine.copyWith(color: OmiColors.faint)),
        ),
      );
    } else {
      body = Stack(
        children: [
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.transparent, Colors.black],
              stops: [0, math.min(1, 40 / math.max(1, rect.height))],
            ).createShader(rect),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 30)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, line) in lines.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _LineRow(line: line, newest: i == lines.length - 1),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_newBelow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: _JumpPill(
                  onTap: () {
                    setState(() {
                      _stick = true;
                      _newBelow = false;
                    });
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  },
                ),
              ),
            ),
        ],
      );
    }
    return Semantics(
      button: lines.isNotEmpty && notes == null,
      hint: lines.isNotEmpty && notes == null ? l10n.liveTranscriptV3 : null,
      child: GestureDetector(
        key: const Key('your_omi_transcript'),
        behavior: HitTestBehavior.opaque,
        onTap: lines.isEmpty || notes != null
            ? null
            : () {
                OmiHaptics.selection();
                Navigator.of(context).push(omiFadeUpRoute(builder: (_) => const _LiveTranscriptPage()));
              },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: OmiColors.palette.isLight ? OmiColors.surface0 : OmiColors.textPrimary.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.10)),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// A transcript line in the card: the speaker's initial in a 24 pt circle, then the words.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.newest});

  final _Line line;
  final bool newest;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${line.speaker}: ${line.text}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: line.isUser ? OmiColors.textPrimary : OmiColors.surface0,
              border: Border.all(
                color: line.isUser ? OmiColors.textPrimary : OmiColors.textPrimary.withValues(alpha: 0.09),
              ),
            ),
            child: Text(
              line.initial,
              style: OmiType.initial.copyWith(color: line.isUser ? OmiColors.surface0 : OmiColors.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.text,
              style: OmiType.transcriptLine.copyWith(color: newest ? OmiColors.textPrimary : OmiColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "New words ↓" (`.osjump`): an ink pill that returns to the newest words.
class _JumpPill extends StatelessWidget {
  const _JumpPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const Key('your_omi_new_words'),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: OmiColors.accent,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), offset: const Offset(0, 6), blurRadius: 16)],
          ),
          child: Text('${context.l10n.newWords} ↓',
              style: OmiType.footnote.copyWith(fontWeight: FontWeight.w600, color: OmiColors.onAccent)),
        ),
      ),
    );
  }
}

/// After Stop (`.osproc`): "Writing up your notes" with a spinner and a filling bar, then "Notes
/// ready" with the conversation's title and Open.
class _NotesState extends StatelessWidget {
  const _NotesState({required this.notes, required this.written, required this.onOpen});

  final _Notes notes;
  final ServerConversation? written;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final small = OmiType.cardSubtitle.copyWith(color: OmiColors.textSecondary, height: 1.4);
    final big = OmiType.transcriptLine.copyWith(fontWeight: FontWeight.w600, height: 1.35);
    final reduced = OmiMotion.of(context).standard == Duration.zero;
    if (notes == _Notes.writing) {
      return Padding(
        key: const Key('your_omi_writing'),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 22, height: 22, child: OmiSpinner(size: OmiSpinnerSize.small)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.writingUpNotes, style: big),
                      Text(l10n.summaryTodosAbout30s, style: small),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // `.osbar`: fills over 3.3 s, then waits full.
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 3300),
                curve: Curves.easeOut,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: OmiColors.divider,
                  valueColor: AlwaysStoppedAnimation(OmiColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final title = (written?.structured.title ?? '').trim();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Semantics(
          button: true,
          label: '${l10n.notesReady}, $title',
          excludeSemantics: true,
          onTap: onOpen,
          child: GestureDetector(
            key: const Key('your_omi_notes_ready'),
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: OmiColors.tone,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                border: Border.all(color: OmiColors.textPrimary.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: OmiColors.accent),
                    child: OmiGlyph(OmiGlyphs.tick, size: 13, color: OmiColors.onAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.notesReady, style: big),
                        if (title.isNotEmpty) Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: OmiColors.accent,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Text(l10n.open,
                        style: OmiType.detail.copyWith(fontWeight: FontWeight.w600, color: OmiColors.onAccent)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.os4dock`: Pause (or Resume, or Start) in ink and Stop, each 132 × 54, in a glass capsule.
class _Dock extends StatelessWidget {
  const _Dock({required this.card, required this.state, required this.onStop});

  final LiveCaptureCard? card;
  final HomeRecorderState state;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = card;
    final paused = c != null && c.paused;
    final recording = c != null && (state == HomeRecorderState.listening || state == HomeRecorderState.paused);
    final (label, glyph) = recording
        ? (paused ? (l10n.resume, OmiGlyphs.playFill) : (l10n.pause, OmiGlyphs.pauseFill))
        : (l10n.start, OmiGlyphs.playFill);
    final VoidCallback? primary = recording
        ? c.onPauseToggle
        : state == HomeRecorderState.reconnecting
            ? null
            : () => HomeRecorderActions.start(context);
    return OmiLiquidGlass(
      borderRadius: const BorderRadius.all(Radius.circular(40)),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              key: const Key('your_omi_primary'),
              label: label,
              glyph: glyph,
              filled: true,
              onPressed: primary,
            ),
            const SizedBox(width: 8),
            _DockButton(
              key: const Key('your_omi_stop'),
              label: l10n.stop,
              glyph: OmiGlyphs.stopFill,
              filled: false,
              onPressed: recording && c.onFinish != null ? onStop : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.label,
    required this.glyph,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final String glyph;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = filled ? OmiColors.onAccent : OmiColors.textPrimary;
    final fill = filled
        ? OmiColors.accent
        : Color.alphaBlend(OmiColors.textPrimary.withValues(alpha: 0.06), OmiColors.surface0);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.35 : 1,
        child: OmiPressable(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed == null
              ? null
              : () {
                  OmiHaptics.medium();
                  onPressed!();
                },
          child: Container(
            width: 132,
            height: 54,
            decoration: BoxDecoration(color: fill, borderRadius: const BorderRadius.all(Radius.circular(27))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OmiGlyph(glyph, size: filled ? 18 : 16, color: ink),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, color: ink, height: 1.2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full-screen live transcript (v8.16 `.osfull`): "Live transcript" over "● Listening · 08:14",
/// every line large with its speaker's name above it, the newest in ink, following the newest words
/// unless scrolled back.
class _LiveTranscriptPage extends StatefulWidget {
  const _LiveTranscriptPage();

  @override
  State<_LiveTranscriptPage> createState() => _LiveTranscriptPageState();
}

class _LiveTranscriptPageState extends State<_LiveTranscriptPage> {
  final ScrollController _scroll = ScrollController();
  Timer? _clock;
  bool _stick = true;
  bool _newBelow = false;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final near = _scroll.position.maxScrollExtent - _scroll.position.pixels < 30;
      if (near != _stick || (near && _newBelow)) {
        setState(() {
          _stick = near;
          if (near) _newBelow = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capture = context.watch<CaptureProvider>();
    final lines = _Line.of(context, capture.segments);
    if (lines.length != _lastCount) {
      final first = _lastCount < 0;
      _lastCount = lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (first || _stick) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        } else {
          setState(() => _newBelow = true);
        }
      });
    }
    final state = HomeListeningLabel.watch(context);
    final word = switch (state) {
      HomeRecorderState.listening => l10n.listening,
      HomeRecorderState.paused => l10n.paused,
      _ => l10n.off,
    };
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 16, OmiSize.screenMargin, 12),
              child: Row(
                children: [
                  OmiRingButton.glass(
                    key: const Key('live_transcript_back'),
                    glyph: OmiGlyphs.back,
                    label: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Semantics(
                          header: true,
                          child: Text(l10n.liveTranscriptV3,
                              style: OmiType.headline.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _BlinkDot(live: state == HomeRecorderState.listening),
                            const SizedBox(width: 6),
                            Text(
                              '$word · ${_YourOmiBody.clock(capture.captureElapsed)}',
                              style: OmiType.footnote.copyWith(
                                color: OmiColors.textSecondary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 50),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.transparent, Colors.black],
                      stops: [0, math.min(1, 40 / math.max(1, rect.height))],
                    ).createShader(rect),
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
                      children: [
                        if (lines.isEmpty)
                          Text(l10n.wordsShowUpHere, style: OmiType.transcriptLarge.copyWith(color: OmiColors.faint)),
                        for (final (i, line) in lines.indexed) ...[
                          if (i > 0) const SizedBox(height: 22),
                          Semantics(
                            label: '${line.speaker}: ${line.text}',
                            excludeSemantics: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.speaker,
                                  style: OmiType.fine.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.25,
                                    color: i == lines.length - 1 ? OmiColors.textSecondary : OmiColors.faint,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  line.text,
                                  style: OmiType.transcriptLarge.copyWith(
                                    color: i == lines.length - 1 ? OmiColors.textPrimary : OmiColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_newBelow)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: Center(
                        child: _JumpPill(
                          onTap: () {
                            setState(() {
                              _stick = true;
                              _newBelow = false;
                            });
                            _scroll.jumpTo(_scroll.position.maxScrollExtent);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.osdot`: 7 pt of ink that dims and returns every 1.6 s while listening.
class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.live});

  final bool live;

  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_BlinkDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.live && !still) {
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) =>
          Opacity(opacity: 1 - 0.75 * math.sin(_blink.value * math.pi), child: child),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: OmiColors.textPrimary),
      ),
    );
  }
}
