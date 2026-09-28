import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/schema.dart';
import 'package:omi/pages/action_items/task_categorization.dart';
import 'package:omi/pages/action_items/widgets/action_item_form_sheet.dart';
import 'package:omi/pages/conversations/open_conversation.dart';
import 'package:omi/pages/home/widgets/listening_strip.dart';
import 'package:omi/providers/action_items_provider.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// The groups of the To-do list, in order.
enum TodoGroup { overdue, today, thisWeek, later, done }

/// The To-do list (v3 `todosAll`): Overdue, Today, This week, Later and Done. Each row is an
/// outline circle, the task (with a red "Late" or a grey "New" tag), when it is due, and a link back
/// to the conversation it came from. Ticking the circle strikes the task through and moves it to
/// Done; tapping the task edits it; + in the header adds one.
class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  /// Which group [task] belongs to on [now]'s day. Overdue and Today follow the app's bucket rule
  /// ([categoryForItem], pinned by `contracts/parity/task_due_buckets.json`: past due, or undated
  /// and older than a week); Tomorrow and dated tasks within the next six days read as This week;
  /// the rest, and undated ones, as Later.
  static TodoGroup groupOf(ActionItemWithMetadata task, {DateTime? now}) {
    if (task.completed) return TodoGroup.done;
    final n = now ?? DateTime.now();
    switch (categoryForItem(task, false, now: n)) {
      case TaskCategory.overdue:
        return TodoGroup.overdue;
      case TaskCategory.today:
        return TodoGroup.today;
      case TaskCategory.tomorrow:
        return TodoGroup.thisWeek;
      case TaskCategory.noDeadline:
        return TodoGroup.later;
      case TaskCategory.later:
        final due = task.dueAt!;
        return due.isBefore(DateTime(n.year, n.month, n.day + 7)) ? TodoGroup.thisWeek : TodoGroup.later;
    }
  }

  /// A task is new for a day after Omi made it.
  static bool isNew(ActionItemWithMetadata task, {DateTime? now}) {
    final created = task.createdAt;
    if (created == null || task.completed) return false;
    return (now ?? DateTime.now()).difference(created.toLocal()) < const Duration(hours: 24);
  }

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<ActionItemsProvider>().ensureLoaded());
    });
  }

  String _groupTitle(BuildContext context, TodoGroup group) {
    final l10n = context.l10n;
    return switch (group) {
      TodoGroup.overdue => l10n.overdue,
      TodoGroup.today => l10n.today,
      TodoGroup.thisWeek => l10n.thisWeek,
      TodoGroup.later => l10n.tasksLater,
      TodoGroup.done => l10n.done,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: OmiColors.surface0,
      appBar: OmiScreenHeader(
        title: l10n.toDo,
        trailing: OmiRingButton.glass(
          key: const Key('todo_add'),
          glyph: OmiGlyphs.plusLine,
          label: l10n.createActionItem,
          onPressed: () => showActionItemFormSheet(context),
        ),
      ),
      bottomNavigationBar: const ListeningStrip(),
      body: Consumer<ActionItemsProvider>(
        builder: (context, provider, _) {
          final now = DateTime.now();
          final groups = <TodoGroup, List<ActionItemWithMetadata>>{};
          for (final task in provider.actionItems) {
            groups.putIfAbsent(TodoListPage.groupOf(task, now: now), () => []).add(task);
          }
          for (final list in groups.values) {
            list.sort((a, b) {
              final ad = a.dueAt, bd = b.dueAt;
              if (ad == null && bd == null) return (b.createdAt ?? now).compareTo(a.createdAt ?? now);
              if (ad == null) return 1;
              if (bd == null) return -1;
              return ad.compareTo(bd);
            });
          }
          final done = groups[TodoGroup.done];
          if (done != null) {
            done.sort((a, b) => (b.completedAt ?? now).compareTo(a.completedAt ?? now));
            if (done.length > 20) groups[TodoGroup.done] = done.take(20).toList();
          }
          if (provider.actionItems.isEmpty) {
            return Center(
              child: provider.isLoading || !provider.hasLoaded
                  ? const OmiSpinner()
                  : Padding(
                      padding: const EdgeInsets.all(OmiSize.screenMargin),
                      child: Text(
                        l10n.tasksEmptyStateMessage,
                        textAlign: TextAlign.center,
                        style: OmiType.subhead.copyWith(color: OmiColors.textSecondary),
                      ),
                    ),
            );
          }
          return RefreshIndicator(
            onRefresh: provider.fetchActionItems,
            color: OmiColors.onAccent,
            backgroundColor: OmiColors.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(OmiSize.screenMargin, 0, OmiSize.screenMargin, OmiSpacing.xl),
              children: [
                for (final (i, group) in TodoGroup.values.where((g) => groups[g]?.isNotEmpty ?? false).indexed) ...[
                  OmiSectionLabel(title: _groupTitle(context, group), top: i == 0 ? 10 : 30, bottom: 6),
                  for (final task in groups[group]!)
                    TodoRow(key: ValueKey('todo_${task.id}'), task: task, group: group, now: now),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One task (`.trow`): the check ring, the words with their tag, when it is due, and "≡ the
/// conversation it came from".
class TodoRow extends StatelessWidget {
  const TodoRow({super.key, required this.task, required this.group, required this.now});

  final ActionItemWithMetadata task;
  final TodoGroup group;
  final DateTime now;

  String? _due(BuildContext context) {
    final due = task.dueAt?.toLocal();
    if (due == null || task.completed) return null;
    final l10n = context.l10n;
    final locale = OmiDateFormat.of(context).localeName;
    return switch (group) {
      TodoGroup.overdue => l10n.dueOn(DateFormat.EEEE(locale).format(due)),
      TodoGroup.today => l10n.today,
      TodoGroup.thisWeek => DateFormat.EEEE(locale).format(due),
      _ => DateFormat.MMMEd(locale).format(due),
    };
  }

  ServerConversation? _source(BuildContext context) {
    final id = task.conversationId;
    if (id == null) return null;
    for (final c in context.read<ConversationProvider>().conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final done = task.completed;
    final due = _due(context);
    final source = _source(context);
    final late = group == TodoGroup.overdue;
    final fresh = !late && TodoListPage.isNew(task, now: now);
    final title = OmiType.body.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: done ? OmiColors.faint : OmiColors.textPrimary,
      decoration: done ? TextDecoration.lineThrough : null,
      decorationColor: OmiColors.faint,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OmiColors.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The ring's 44 pt target starts 12 pt left of the ring, which sits on the gutter.
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: OmiCheckRing(
                done: done,
                semanticLabel: done ? l10n.markIncomplete : l10n.markComplete,
                onChanged: (value) async {
                  final saved = await context.read<ActionItemsProvider>().updateActionItemState(task, value);
                  if (!saved && context.mounted) OmiFeedback.error(context, l10n.failedToUpdateActionItem);
                },
              ),
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(-10, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showActionItemFormSheet(context, actionItem: task),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: task.description.trim()),
                          if (late || fresh)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  late ? l10n.lateTag : l10n.todoNewTag,
                                  style: OmiType.caption1.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    color: late ? OmiColors.danger : OmiColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ]),
                        style: title,
                      ),
                      if (due != null) ...[
                        const SizedBox(height: 2),
                        Text(due, style: OmiType.detail.copyWith(height: 1.4, color: OmiColors.textSecondary)),
                      ],
                      if (source != null && !done)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Semantics(
                            button: true,
                            label: source.structured.title,
                            hint: l10n.openConversation,
                            excludeSemantics: true,
                            child: GestureDetector(
                              key: ValueKey('todo_source_${task.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => openConversationDetail(context, source),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OmiGlyph(OmiGlyphs.source, size: 13, color: OmiColors.ink80),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      source.structured.title.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: OmiType.footnote.copyWith(
                                        height: 1.4,
                                        color: OmiColors.ink80,
                                        decoration: TextDecoration.underline,
                                        decorationColor: OmiColors.faint,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
