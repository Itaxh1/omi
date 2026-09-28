import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/pages/conversations/open_conversation.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Which conversations [AllConversationsPage] lists.
sealed class ConversationScope {
  const ConversationScope();
}

/// Every conversation.
class AllScope extends ConversationScope {
  const AllScope();
}

/// One folder's conversations (the server filters).
class FolderScope extends ConversationScope {
  const FolderScope(this.id, this.name);
  final String id;
  final String name;
}

/// Conversations in no folder (filtered from the loaded list).
class UnfiledScope extends ConversationScope {
  const UnfiledScope();
}

/// All conversations (v3 `convsAll`): a search pill, then day groups (Today, Yesterday, then the
/// date), each row the time and the title, hairlines between rows. A folder from the sidebar opens
/// the same screen for that folder.
class AllConversationsPage extends StatefulWidget {
  const AllConversationsPage({super.key, this.scope = const AllScope()});

  final ConversationScope scope;

  @override
  State<AllConversationsPage> createState() => _AllConversationsPageState();
}

class _AllConversationsPageState extends State<AllConversationsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  late final ConversationProvider _provider = context.read<ConversationProvider>();
  bool _setFolder = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final scope = widget.scope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scope is FolderScope) {
        _setFolder = true;
        unawaited(_provider.filterByFolder(scope.id));
      } else if (_provider.selectedFolderId != null) {
        _setFolder = true;
        unawaited(_provider.filterByFolder(null));
      } else if (_provider.conversations.isEmpty) {
        unawaited(_provider.getInitialConversations());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    // Leave the shared list as Home expects it: no search, no folder.
    if (_provider.previousQuery.isNotEmpty) unawaited(_provider.searchConversations(''));
    if (_setFolder && _provider.selectedFolderId != null) unawaited(_provider.filterByFolder(null));
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 400) return;
    if (_provider.hasActiveSearch) {
      unawaited(_provider.searchMoreConversations());
    } else if (_provider.hasMoreConversations && !_provider.isLoadingConversations) {
      unawaited(_provider.getMoreConversationsFromServer());
    }
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_provider.searchConversations(value.trim()));
    });
  }

  String _title(BuildContext context) => switch (widget.scope) {
        FolderScope(:final name) => name,
        UnfiledScope() => context.l10n.notInAFolder,
        AllScope() => context.l10n.conversations,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(title: _title(context)),
      bottomNavigationBar: const ListeningStrip(),
      body: Consumer<ConversationProvider>(
        builder: (context, provider, _) {
          final groups = _groups(provider);
          final loading = provider.isLoadingConversations || provider.isFetchingConversations;
          return RefreshIndicator(
            onRefresh: provider.getInitialConversations,
            color: OmiColors.onAccent,
            backgroundColor: OmiColors.accent,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 6, OmiSize.screenMargin, 0),
                  sliver: SliverToBoxAdapter(
                    child: OmiSearchPill(
                      controller: _search,
                      fieldKey: const Key('conversations_search'),
                      hint: l10n.searchConversations,
                      onChanged: _onQuery,
                    ),
                  ),
                ),
                if (groups.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: loading
                          ? const OmiSpinner()
                          : Padding(
                              padding: const EdgeInsets.all(OmiSize.screenMargin),
                              child: Text(
                                provider.hasActiveSearch ? l10n.noResultsFound : l10n.noConversationsYet,
                                textAlign: TextAlign.center,
                                style: OmiType.subhead.copyWith(color: OmiColors.textSecondary),
                              ),
                            ),
                    ),
                  ),
                for (final entry in groups)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: OmiSize.screenMargin),
                    sliver: SliverList.list(
                      children: [
                        OmiSectionLabel(
                          title: OmiDateFormat.of(context).dayTitle(entry.$1),
                          top: 24,
                          bottom: 6,
                        ),
                        for (final (j, c) in entry.$2.indexed) ConversationTimeRow(conversation: c, index: j),
                      ],
                    ),
                  ),
                if (groups.isNotEmpty && (provider.isLoadingConversations && provider.hasMoreConversations))
                  const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.all(OmiSpacing.lg), child: Center(child: OmiSpinner())),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: OmiSpacing.xl)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Day groups, newest first, without discarded conversations; [UnfiledScope] keeps the ones in
  /// no folder.
  List<(DateTime, List<ServerConversation>)> _groups(ConversationProvider provider) {
    final unfiled = widget.scope is UnfiledScope;
    final days = provider.groupedConversations.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        if ((provider.groupedConversations[day] ?? const <ServerConversation>[])
                .where((c) => !c.discarded && (!unfiled || c.folderId == null))
                .toList()
            case final list when list.isNotEmpty)
          (day, list),
    ];
  }
}

/// One conversation in a day group (`#convsAll .row`): the time in a narrow column, the title
/// beside it (17/500, wrapping), a hairline under it.
class ConversationTimeRow extends StatelessWidget {
  const ConversationTimeRow({super.key, required this.conversation, this.index = 0});

  final ServerConversation conversation;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final title = c.structured.title.trim().isEmpty ? context.l10n.untitledConversation : c.structured.title.trim();
    final at = (c.startedAt ?? c.createdAt).toLocal();
    final dates = OmiDateFormat.of(context);
    // "12:40" fits 42 pt; a 12-hour clock needs room for the period.
    final timeWidth = dates.use24HourFormat || !dates.time(at).contains(RegExp('[A-Za-z]')) ? 42.0 : 58.0;
    return Semantics(
      button: true,
      label: '${dates.time(at)}, $title',
      excludeSemantics: true,
      child: OmiPressable(
        key: ValueKey('conversation_row_${c.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => openConversationDetail(context, c, index: index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: timeWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    dates.time(at),
                    maxLines: 1,
                    style: OmiType.footnote.copyWith(
                      color: OmiColors.textSecondary,
                      height: 1.4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: OmiType.body.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
