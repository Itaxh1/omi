import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/gen/phone_mic_pigeon.g.dart';
import 'package:omi/services/capture/capture_external_actions.dart';
import 'package:omi/services/capture/optimistic_processing.dart';
import '../../support/capture/capture_replay_world.dart';

class _Rows extends NoopCaptureExternalActions {
  final pending = <String, ServerConversation>{};
  final completed = <String, ServerConversation>{};
  @override
  void addProcessingConversation(ServerConversation c) => pending[c.id] = c;
  @override
  void removeProcessingConversation(String id) => pending.remove(id);
  @override
  bool hasConversation(String id) => completed.containsKey(id);
  @override
  void upsertConversation(ServerConversation c) {
    pending.remove(c.id);
    completed[c.id] = c;
  }
}

ServerConversation _server(String id, {ConversationStatus status = ConversationStatus.processing}) =>
    ServerConversation(
        id: id,
        createdAt: DateTime.utc(2026, 9, 28),
        structured: Structured('Call Sam tomorrow', 'Call Sam', emoji: '☎️'),
        status: status);

void main() {
  late Directory directory;
  late CaptureReplayWorld world;
  late _Rows rows;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('omi_draft_lifecycle_');
    rows = _Rows();
    world = await CaptureReplayWorld.boot(tempDir: directory, externalActions: rows);
  });
  tearDown(() async {
    await world.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  Future<ServerConversation> start() async {
    await world.startLiveCapture();
    world.emitNativeState(PhoneMicCaptureState.running);
    await world.settle();
    return world.controller.liveConversationDraft!;
  }

  test('recording gets a draft immediately; pause/resume retains its row', () async {
    expect(world.controller.liveConversationDraft, isNull);
    final draft = await start();
    expect(draft.status, ConversationStatus.in_progress);
    expect(draft.source, ConversationSource.phone);
    expect(OptimisticProcessingPlaceholder.isLocal(draft.id), isTrue);
    await world.controller.pauseCapture();
    expect(world.controller.liveConversationDraft, same(draft));
    await world.controller.resumeCapture();
    expect(world.controller.liveConversationDraft, same(draft));
  });
  test('Stop retains the same row while transcript and process response are in flight', () async {
    final draft = await start();
    final response = Completer<CreateConversationResponse?>();
    addTearDown(() {
      if (!response.isCompleted) response.complete(null);
    });
    world.processResult = () => response.future;
    final stop = world.controller.stopCapture();
    await world.settle();
    expect(world.processCalls, 1);
    expect(rows.pending.keys, [draft.id]);
    expect(rows.pending[draft.id]!.status, ConversationStatus.processing);
    expect(rows.pending[draft.id]!.finishedAt, isNotNull);
    expect(world.controller.liveConversationDraft, isNull);
    response.complete(CreateConversationResponse(messages: [], conversation: _server('server-1')));
    await stop;
    expect(rows.pending.keys, ['server-1']);
    expect(world.controller.liveConversationDraft, isNull);
  });
  test('two stopped recordings remain separate until each server result is ready', () async {
    final first = await start();
    world.processResult = () async => CreateConversationResponse(messages: [], conversation: _server('server-1'));
    await world.controller.stopCapture();
    final second = await start();
    expect(second.id, isNot(first.id));
    expect(rows.pending.keys, ['server-1']);
    world.processResult = () async => CreateConversationResponse(messages: [], conversation: _server('server-2'));
    await world.controller.stopCapture();
    expect(rows.pending.keys, ['server-1', 'server-2']);
  });
  test('server-confirmed empty recording removes only its own draft', () async {
    rows.addProcessingConversation(_server('older'));
    await start();
    await world.controller.stopCapture();
    expect(rows.pending.keys, ['older']);
    expect(world.controller.liveConversationDraft, isNull);
  });
  test('processing failure clears its local row and preserves older pending conversations', () async {
    rows.addProcessingConversation(_server('older'));
    await start();
    world.processResult = () async => throw StateError('network unavailable');
    await expectLater(world.controller.stopCapture(), throwsA(isA<StateError>()));
    expect(rows.pending.keys, ['older']);
  });
  test('late HTTP processing result cannot revive a websocket-completed conversation', () async {
    rows.addProcessingConversation(
        OptimisticProcessingPlaceholder.recording(recordingId: 'second', revision: 0, startedAt: world.clock.now()));
    rows.upsertConversation(_server('server-1', status: ConversationStatus.completed));
    await OptimisticProcessingPlaceholder.applyProcessResult(
      placeholderId: 'local-draft-first-0',
      result: CreateConversationResponse(messages: [], conversation: _server('server-1')),
      actions: rows,
      onCreated: (conversation, messages) async => fail('must not deliver the conversation twice'),
    );
    expect(rows.pending.keys, ['local-draft-second-0']);
    expect(rows.completed.keys, ['server-1']);
  });
}
