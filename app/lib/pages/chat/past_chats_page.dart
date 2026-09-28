import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/app.dart';
import 'package:omi/backend/schema/chat_session.dart';
import 'package:omi/providers/message_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Past chats (v3 `chist`): "New chat · Start fresh", the chat apps the reader has added, then every
/// earlier chat with Omi, newest first, with when it was. Tapping one opens it; holding one offers
/// to delete it.
class PastChatsPage extends StatefulWidget {
  const PastChatsPage({super.key, required this.onNewChat, required this.onOpen, required this.onPickApp});

  /// Starts a fresh chat (the page closes first).
  final VoidCallback onNewChat;

  /// Opens a past chat (the page closes first).
  final ValueChanged<ChatSessionSummary> onOpen;

  /// Chats with an added app instead of Omi (the page closes first).
  final ValueChanged<App> onPickApp;

  /// When a chat was (the design's `.hist small`): "Today, 13:10", "Yesterday", a weekday this
  /// week, "Last Thursday" the week before, then the date.
  static String when(BuildContext context, DateTime at, {DateTime? now}) {
    final l10n = context.l10n;
    final format = OmiDateFormat.of(context);
    final n = now ?? DateTime.now();
    final days = DateTime(n.year, n.month, n.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    final weekday = DateFormat.EEEE(format.localeName).format(at);
    if (days <= 0) return l10n.dayAtTime(l10n.today, format.time(at));
    if (days == 1) return l10n.yesterday;
    if (days < 7) return weekday;
    if (days < 14) return l10n.lastWeekday(weekday);
    return (at.year == n.year ? DateFormat.MMMd(format.localeName) : DateFormat.yMMMd(format.localeName)).format(at);
  }

  /// What a chat is called: its title, else the start of its last message, else "New chat".
  static String titleOf(BuildContext context, ChatSessionSummary session) {
    if (session.hasTitle) return session.title.trim();
    final preview = (session.preview ?? '').trim().split('\n').first;
    return preview.isNotEmpty ? preview : context.l10n.newChatV3;
  }

  @override
  State<PastChatsPage> createState() => _PastChatsPageState();
}

class _PastChatsPageState extends State<PastChatsPage> {
  List<ChatSessionSummary>? _sessions;
  int _revision = -1;

  Future<void> _load() async {
    final provider = context.read<MessageProvider>();
    _revision = provider.chatSessionsRevision;
    final sessions = await provider.loadChatSessions();
    // Chats nothing was said in yet stay out of the list.
    if (!mounted) return;
    setState(() {
      _sessions =
          sessions.where((s) => s.messageCount > 0 || s.hasTitle || (s.preview ?? '').trim().isNotEmpty).toList();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<MessageProvider>().chatSessionsRevision;
    if (revision != _revision) unawaited(_load());
  }

  void _close(VoidCallback then) {
    OmiHaptics.selection();
    Navigator.of(context).pop();
    then();
  }

  Future<void> _delete(ChatSessionSummary session) async {
    final l10n = context.l10n;
    OmiHaptics.medium();
    final confirmed = await showOmiConfirm(
      context,
      title: l10n.deleteChatQuestion,
      message: l10n.deleteChatMessage,
      confirmLabel: l10n.deleteChatV3,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _sessions?.removeWhere((s) => s.id == session.id));
    final deleted = await context.read<MessageProvider>().deleteChatSession(session.id);
    if (!deleted && mounted) {
      OmiFeedback.error(context, l10n.somethingWentWrong);
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final apps = context.select<MessageProvider, List<App>>((p) => p.chatApps);
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(title: l10n.pastChats),
      body: RefreshIndicator(
        onRefresh: _load,
        color: OmiColors.onAccent,
        backgroundColor: OmiColors.accent,
        child: ListView(
          key: const Key('past_chats'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 6, OmiSize.screenMargin, 24),
          children: [
            _HistRow(
              key: const Key('past_chats_new'),
              title: l10n.newChatV3,
              detail: l10n.startFresh,
              onTap: () => _close(widget.onNewChat),
            ),
            if (apps.isNotEmpty) ...[
              OmiSectionLabel(title: l10n.appsAskWith, top: 26, bottom: 2),
              for (final app in apps)
                _HistRow(
                  key: ValueKey('past_chats_app_${app.id}'),
                  title: app.getName(),
                  detail: app.description.trim().split('\n').first,
                  onTap: () => _close(() => widget.onPickApp(app)),
                ),
              const SizedBox(height: 14),
            ],
            if (sessions == null)
              const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: OmiSpinner()))
            else if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(l10n.noPastChats,
                    style: OmiType.callout.copyWith(height: 1.45, color: OmiColors.textSecondary)),
              )
            else
              for (final session in sessions)
                _HistRow(
                  key: ValueKey('past_chat_${session.id}'),
                  title: PastChatsPage.titleOf(context, session),
                  detail: PastChatsPage.when(context, session.updatedAt),
                  onTap: () => _close(() => widget.onOpen(session)),
                  onLongPress: () => _delete(session),
                ),
          ],
        ),
      ),
    );
  }
}

/// A row of Past chats (`.hist`): the name at 17/500 over a 13 pt line, a hairline under it.
class _HistRow extends StatelessWidget {
  const _HistRow({super.key, required this.title, required this.detail, required this.onTap, this.onLongPress});

  final String title;
  final String detail;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $detail',
      excludeSemantics: true,
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `.hist`: the name on a 23.8 pt line, the detail in a 22.4 pt line box under it.
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.body.copyWith(fontWeight: FontWeight.w500, height: 1.4)),
              const SizedBox(height: 3),
              Text(detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.footnote.copyWith(height: 1.49, color: OmiColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
