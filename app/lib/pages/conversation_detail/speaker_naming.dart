import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:omi/backend/schema/person.dart';
import 'package:omi/pages/conversation_detail/conversation_detail_provider.dart';
import 'package:omi/pages/conversation_detail/widgets/name_speaker_sheet.dart';
import 'package:omi/providers/connectivity_provider.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_manager.dart';

/// Names a transcript speaker: the tag-speaker sheet, then the assignment with an optimistic person
/// (a new name shows at once and is replaced by the saved person), Retry on failure.
void nameTranscriptSpeaker(
  BuildContext context,
  ConversationDetailProvider provider, {
  required String segmentId,
  required int speakerId,
}) {
  if (!context.read<ConnectivityProvider>().isConnected) {
    ConnectivityProvider.showNoInternetDialog(context);
    return;
  }
  showNameSpeakerSheet(
    context,
    speakerId: speakerId,
    segmentId: segmentId,
    segments: provider.conversation.transcriptSegments,
    onSpeakerAssigned: (speakerId, personId, personName, segmentIds, applyToSpeaker) async => _assign(
      context,
      provider,
      provider.conversation.id,
      speakerId,
      personId,
      personName,
      segmentIds,
      applyToSpeaker,
    ),
  );
}

bool _assign(
  BuildContext context,
  ConversationDetailProvider provider,
  String conversationId,
  int speakerId,
  String personId,
  String personName,
  List<String> segmentIds,
  bool applyToSpeaker,
) {
  final peopleProvider = context.read<PeopleProvider>();
  final newPerson = personId.isEmpty;
  final temporaryId = newPerson ? 'optimistic-person:${DateTime.now().microsecondsSinceEpoch}' : null;
  if (temporaryId != null) {
    peopleProvider.addOptimisticPerson(
      Person(id: temporaryId, name: personName, createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
  }
  var resolvedId = personId;
  final pending = provider.startSpeakerAssignment(
    segmentIds,
    temporaryId ?? personId,
    speakerId: applyToSpeaker ? speakerId : null,
    expectedConversationId: conversationId,
    createPerson: newPerson ? () async => (await peopleProvider.createPersonProvider(personName))?.id : null,
    onReconciled: (id) {
      resolvedId = id;
      if (temporaryId != null) peopleProvider.removeOptimisticPerson(temporaryId);
    },
    onFailed: () {
      if (temporaryId != null) peopleProvider.removeOptimisticPerson(temporaryId);
      if (!context.mounted) return;
      OmiFeedback.error(
        context,
        context.l10n.failedToSaveCheckConnection,
        actionLabel: context.l10n.retry,
        onAction: () =>
            _assign(context, provider, conversationId, speakerId, resolvedId, personName, segmentIds, applyToSpeaker),
      );
    },
  );
  if (pending == null) {
    if (temporaryId != null) peopleProvider.removeOptimisticPerson(temporaryId);
    return false;
  }
  unawaited(pending.then((saved) {
    if (temporaryId != null) peopleProvider.removeOptimisticPerson(temporaryId);
    if (saved) PlatformManager.instance.analytics.taggedSegment(resolvedId == 'user' ? 'User' : 'User Person');
  }));
  return true;
}
