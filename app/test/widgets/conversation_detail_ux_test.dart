import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/conversation_capturing/capture_state_header.dart';
import 'package:omi/pages/conversations/capture_state_labels.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/media_viewer_page.dart';
import 'package:omi/widgets/transcript.dart';

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

TranscriptSegment _segment(String id, {int speaker = 1, bool isUser = false, double start = 0, String? stt}) {
  return TranscriptSegment(
    id: id,
    text: 'Line $id',
    speaker: 'SPEAKER_0$speaker',
    isUser: isUser,
    personId: null,
    start: start,
    end: start + 1,
    translations: [],
    sttProvider: stt,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
  });

  test('getLastTranscript numbers speakers across the whole conversation', () {
    // Speaker 1 appears only before the 50-segment window; the window's speaker is still Speaker 2.
    final segments = [
      _segment('first', speaker: 1),
      for (var i = 0; i < 60; i++) _segment('s$i', speaker: 2, start: i + 1.0),
    ];
    final text = getLastTranscript(segments, includeTimestamps: false);
    expect(text, contains('Speaker 2'));
    expect(text, isNot(contains('Speaker 1:')));
  });

  testWidgets('transcript line: no provider name, start offset, the whole line plays from there', (tester) async {
    final segments = [_segment('a', start: 65, stt: 'deepgram')];
    final played = <String>[];
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: TranscriptWidget(
            segments: segments,
            onSegmentTap: (segment) => played.add(segment.id),
            canDisplaySeconds: true,
            isConversationDetail: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Deepgram'), findsNothing);
    expect(find.text('1:05'), findsOneWidget);
    final line = find.byKey(const ValueKey('transcript_seek_a'));
    expect(line, findsOneWidget);
    expect(tester.getSize(line).height, greaterThanOrEqualTo(kOmiMinTapTarget));
    await tester.tap(line);
    expect(played, ['a']);
  });

  testWidgets('capture state header names the state with the shared labels (hub #25)', (tester) async {
    for (final (state, label) in [
      (CaptureDisplayState.listening, 'Listening'),
      (CaptureDisplayState.paused, 'Paused'),
      (CaptureDisplayState.processing, 'Processing'),
    ]) {
      await tester.pumpWidget(_app(Scaffold(appBar: ConversationStateAppBar(state: state))));
      await tester.pump();
      expect(find.text(label), findsOneWidget);
      expect(find.byType(OmiBackButton), findsOneWidget);
    }
  });

  testWidgets('the transcription-outage sentence wraps in the header instead of clipping', (tester) async {
    // A phone-sized surface: the full sentence cannot fit one title line, so
    // the header must wrap it rather than ellipsize away the promise that
    // recording continues and will be processed later.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _app(const Scaffold(appBar: ConversationStateAppBar(state: CaptureDisplayState.transcriptionUnavailable))));
    await tester.pump();

    final text = tester.widget<Text>(find.textContaining('recording continues on device'));
    expect(text.maxLines, greaterThan(1));
    expect(find.textContaining('will process later'), findsOneWidget);
    expect(tester.getSize(find.byType(ConversationStateAppBar)).height, kToolbarHeight);
  });

  testWidgets('media viewer leaves by a trailing close button, never a back arrow (nav #11)', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => MediaViewerPage.open(
                context,
                items: const [MediaViewerItem(imageUrl: 'https://example.invalid/a.png')],
                // A pre-existing caller flag that must not move the X to the leading edge.
              ),
              child: const Text('view'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('view'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OmiCloseButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.leading, isNull);
    expect(appBar.automaticallyImplyLeading, isFalse);
  });
}
