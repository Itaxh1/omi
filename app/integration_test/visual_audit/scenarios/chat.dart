// Ask Omi (v3): the hello and suggestions, a reply and its actions, Past chats.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/pages/chat/page.dart';
import 'package:omi/providers/message_provider.dart';
import 'package:omi/backend/schema/chat_session.dart';
import 'package:provider/provider.dart';

import '../../journeys/support/hermetic_boot.dart';
import '../harness.dart';

const _page = 'lib/pages/chat/page.dart (ChatPage)';
const _input = ValueKey('omi.chat.input');
const _send = ValueKey('omi.chat.send');

/// Sends [question] and waits for the fixture backend's deterministic reply.
Future<void> _ask(AuditRun a, String question) async {
  await a.enterText(find.byKey(_input), question);
  await a.tap(find.byKey(_send));
}

final chatScenarios = <AuditScenario>[
  AuditScenario(
    id: 'chat-ask',
    title: 'Ask Omi (v3): hello, a suggestion asked, a follow-up and copy',
    page: _page,
    state: 'No saved personal data; the fixture backend streams a fixed assistant reply',
    run: (a) async {
      a.server.assistantReplyText =
          'You agreed to send Alex the revised design notes on Friday. Start with the recording flow and memory search.';
      await a.pump(const ChatPage());
      expect(find.byKey(const Key('ask_hello')), findsOneWidget);
      expect(find.byKey(const Key('ask_suggestions')), findsOneWidget);
      await a.shot('Open Ask Omi: the hello and three suggestions over the composer', step: 'empty');
      await a.tap(find.byKey(const ValueKey('ask_suggestion_1')));
      expect(a.server.countOf('POST', '/v2/messages'), 1);
      await a.shot('Tap a suggestion: it is asked straight away and the answer comes back', step: 'reply');
      await a.enterText(find.byKey(_input), 'What did I agree to send Alex?');
      await a.shot('Compose a follow-up', step: 'draft');
      mockCommonPlatformChannels();
      await a.tester.tap(find.bySemanticsLabel('Copy Message'));
      await a.tester.pump();
      await a.tester.pump(const Duration(milliseconds: 300));
      await a.shot('Tap Copy and inspect its confirmation', step: 'copy');
    },
  ),
  AuditScenario(
    id: 'chat-past-chats',
    title: 'Past chats: New chat, then earlier chats with when they were',
    page: 'lib/pages/chat/past_chats_page.dart (PastChatsPage)',
    state: 'Four earlier chats: today, yesterday, this week and last week',
    run: (a) async {
      final now = DateTime.now();
      final messages = MessageProvider()
        ..chatSessionsOverride = () async => [
              ChatSessionSummary(
                  id: 's1',
                  title: 'What did I decide today?',
                  updatedAt: now.subtract(const Duration(hours: 1)),
                  messageCount: 2),
              ChatSessionSummary(
                  id: 's2',
                  title: 'Did Dan send the model link?',
                  updatedAt: now.subtract(const Duration(days: 1)),
                  messageCount: 4),
              ChatSessionSummary(
                  id: 's3',
                  title: 'What did Priya say about the deck?',
                  updatedAt: now.subtract(const Duration(days: 3)),
                  messageCount: 2),
              ChatSessionSummary(
                  id: 's4',
                  title: 'Summarise the pricing kickoff',
                  updatedAt: now.subtract(const Duration(days: 9)),
                  messageCount: 6),
            ];
      await a.pump(const ChatPage(), providers: [ChangeNotifierProvider<MessageProvider>.value(value: messages)]);
      await a.tap(find.byKey(const Key('chat_history')));
      await a.shot('Tap the clock in the Ask header: Past chats');
    },
  ),
  AuditScenario(
    id: 'chat-feedback',
    title: 'Not Helpful feedback sheet on a reply',
    page: _page,
    state: 'One question answered by the fixture backend',
    run: (a) async {
      a.server.assistantReplyText = 'You agreed to send Alex the revised design notes on Friday.';
      await a.pump(const ChatPage());
      await _ask(a, 'What did I agree to?');
      await a.tap(find.bySemanticsLabel('Not Helpful'));
      await a.shot('Tap Not Helpful on the reply: the feedback reason sheet');
    },
  ),
];
