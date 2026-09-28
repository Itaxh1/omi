import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/schema.dart';
import 'package:omi/pages/home/widgets/home_heard_today.dart';
import 'package:omi/providers/action_items_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// Home's To-do card (v3), in the warm lower zone: a white card with a hairline and no shadow, the
/// to-do mark in a 42 pt tile, "To-do" over what needs the reader first ("Call Sam back is 2 days
/// late"), a chevron, and a red count badge on the corner for the to-dos that are late or due
/// today. Tapping it opens the To-do list.
class HomeTodoCard extends StatefulWidget {
  const HomeTodoCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  /// What the card says under "To-do": the most overdue task and how late it is; else the next
  /// task due today; else how many are open.
  static String subtitle(BuildContext context, List<ActionItemWithMetadata> open, {DateTime? now}) {
    final l10n = context.l10n;
    final late = lateTasks(open, now: now);
    if (late.isNotEmpty) {
      final task = late.first;
      return l10n.todoLate(task.description.trim(), daysLate(task, now: now));
    }
    final today = dueToday(open, now: now);
    if (today.isNotEmpty) return l10n.todoDueToday(today.first.description.trim());
    return l10n.todoOpenCount(open.length);
  }

  /// Open tasks due before today, most overdue first.
  static List<ActionItemWithMetadata> lateTasks(List<ActionItemWithMetadata> open, {DateTime? now}) {
    final start = _startOfDay(now ?? DateTime.now());
    final late = open.where((t) => t.dueAt != null && t.dueAt!.toLocal().isBefore(start)).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return late;
  }

  /// Open tasks due today, soonest first.
  static List<ActionItemWithMetadata> dueToday(List<ActionItemWithMetadata> open, {DateTime? now}) {
    final start = _startOfDay(now ?? DateTime.now());
    final end = start.add(const Duration(days: 1));
    final today = open.where((t) {
      final due = t.dueAt?.toLocal();
      return due != null && !due.isBefore(start) && due.isBefore(end);
    }).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return today;
  }

  /// Whole calendar days between the task's due day and today.
  static int daysLate(ActionItemWithMetadata task, {DateTime? now}) =>
      _startOfDay(now ?? DateTime.now()).difference(_startOfDay(task.dueAt!.toLocal())).inDays;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The card sits 14 pt inside the page gutter (`.todo1`: width calc(100% − 28px)).
  static const double inset = 14;

  @override
  State<HomeTodoCard> createState() => _HomeTodoCardState();
}

class _HomeTodoCardState extends State<HomeTodoCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ActionItemsProvider>();
      unawaited(provider.ensureHomeTodayTasksLoaded());
      unawaited(provider.ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Consumer<ActionItemsProvider>(
      builder: (context, provider, _) {
        final open = provider.incompleteItems;
        final count = HomeTodoCard.lateTasks(open).length + HomeTodoCard.dueToday(open).length;
        final subtitle = HomeTodoCard.subtitle(context, open);
        // `.todo1`: 14 pt inside the gutter, 26 pt corners, a hairline, no shadow.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: HomeTodoCard.inset),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              OmiCard(
                key: const Key('home_todo_card'),
                radius: OmiRadius.card,
                padding: const EdgeInsets.fromLTRB(15, 19, 19, 19),
                onTap: widget.onOpen,
                semanticLabel: '${l10n.todoCardTitle}. $subtitle',
                child: Row(
                  children: [
                    const OmiDeviceTile(icon: OmiGlyphs.todo, glyph: 22, radius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.todoCardTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OmiType.callout.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            key: const Key('home_todo_subtitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OmiType.cardSubtitle.copyWith(color: OmiColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: OmiSpacing.xs),
                    ExcludeSemantics(
                      child: Text('›', style: OmiType.title3.copyWith(color: OmiColors.textTertiary, height: 1.4)),
                    ),
                  ],
                ),
              ),
              // The count badge, like an app icon's: the to-dos that are late or due today. A 3 pt
              // ring in the page colour lifts it off the card's corner.
              if (count > 0)
                Positioned(
                  top: -10,
                  right: -8,
                  child: ExcludeSemantics(
                    child: Container(
                      key: const Key('home_todo_badge'),
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: OmiColors.danger,
                        borderRadius: OmiRadius.pillAll,
                        border: Border.all(color: OmiColors.surface0, width: 3),
                      ),
                      child: Text(
                        '$count',
                        style: OmiType.footnote.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
