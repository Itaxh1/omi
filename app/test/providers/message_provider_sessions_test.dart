/// Ask v3: each Ask opens fresh and its first question starts a chat session; Past chats opens and
/// deletes earlier sessions, and a new chat is named once from its first exchange.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/chat_session.dart';
import 'package:omi/backend/schema/message.dart';
import 'package:omi/providers/message_provider.dart';

ServerMessage _message(String id, String text, MessageSender sender, int minute) => ServerMessage(
      id,
      DateTime(2026, 9, 28, 10, minute),
      text,
      sender,
      MessageType.text,
      null,
      false,
      [],
      [],
      [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test('a fresh Ask shows nothing, and its first question starts a session and is named once', () async {
    var created = 0;
    final titled = <String>[];
    final provider = MessageProvider()
      ..messages = [_message('old', 'an earlier thread', MessageSender.human, 1)]
      ..createChatSessionOverride = () async {
        created++;
        return ChatSessionSummary(
            id: 'session-$created', title: ChatSessionSummary.untitled, updatedAt: DateTime(2026));
      }
      ..titleChatSessionOverride = (id, messages) async {
        titled.add(id);
        return 'Decisions today';
      }
      ..replyStreamOverride = (text, {appId, filesId, context}) async* {
        yield ServerMessageChunk('r', 'Two things.', MessageChunkType.data);
        yield ServerMessageChunk('r', '', MessageChunkType.done,
            message: _message('reply', 'Two things.', MessageSender.ai, 2));
      };

    provider.startFreshChat();
    expect(provider.messages, isEmpty, reason: 'the hello and suggestions show, not the earlier thread');
    expect(provider.isFreshChat, isTrue);

    provider.addMessageLocally('What did I decide today?');
    await provider.sendMessageStreamToServer('What did I decide today?');
    await Future<void>.delayed(Duration.zero);

    expect(created, 1);
    expect(provider.chatSessionId, 'session-1');
    expect(provider.isFreshChat, isFalse);
    expect(titled, ['session-1']);

    await provider.sendMessageStreamToServer('And yesterday?');
    await Future<void>.delayed(Duration.zero);
    expect(created, 1, reason: 'later questions stay in the same session');
    expect(titled, ['session-1'], reason: 'a chat is named once');
  });

  test('opening a past chat loads its messages; deleting the open one starts fresh', () async {
    final provider = MessageProvider()
      ..sessionMessagesOverride = (id) async => [
            _message('a2', 'Sam a call.', MessageSender.ai, 2),
            _message('h1', 'What do I still owe people?', MessageSender.human, 1),
          ];
    final session = ChatSessionSummary(
      id: 'past-1',
      title: 'What do I still owe people?',
      updatedAt: DateTime(2026, 9, 27),
      messageCount: 2,
    );

    await provider.openChatSession(session);

    expect(provider.chatSessionId, 'past-1');
    expect(provider.messages.map((m) => m.id), ['h1', 'a2'], reason: 'oldest first');
    expect(provider.isLoadingMessages, isFalse);
  });

  test('a titled session reads by its title, an untitled one by its last words', () {
    expect(
      ChatSessionSummary(id: 'a', title: 'Pricing kickoff', updatedAt: DateTime(2026)).hasTitle,
      isTrue,
    );
    final untitled = ChatSessionSummary.fromJson({
      'id': 'b',
      'title': 'New Chat',
      'preview': 'Sam a call, due Wednesday.',
      'updated_at': '2026-09-28T10:00:00Z',
      'message_count': 2,
    })!;
    expect(untitled.hasTitle, isFalse);
    expect(untitled.preview, 'Sam a call, due Wednesday.');
    expect(untitled.messageCount, 2);
    expect(ChatSessionSummary.fromJson({'title': 'no id'}), isNull);
  });
}
