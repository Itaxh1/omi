import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// A conversation's to-dos (`#cvTodo`, and the first conversation in onboarding): a ring and the
/// words; ticking one saves it.
class ConversationTodos extends StatefulWidget {
  const ConversationTodos({super.key, required this.conversation, required this.todos});

  final ServerConversation conversation;
  final List<ActionItem> todos;

  @override
  State<ConversationTodos> createState() => _ConversationTodosState();
}

class _ConversationTodosState extends State<ConversationTodos> {
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
