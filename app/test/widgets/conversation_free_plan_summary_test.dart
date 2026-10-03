import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/backend/schema/structured.dart';
import 'package:omi/backend/schema/transcript_segment.dart';
import 'package:omi/l10n/app_localizations.dart';
import 'package:omi/pages/conversation_detail/conversation_detail_provider.dart';
import 'package:omi/pages/conversation_detail/page.dart';
import 'package:omi/pages/conversation_detail/widgets.dart';
import 'package:omi/pages/conversations/widgets/conversation_list_item.dart';
import 'package:omi/pages/conversations/widgets/date_list_item.dart';
import 'package:omi/pages/conversations/widgets/free_plan_summary.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/widgets/conversation_bottom_bar.dart';

import '../support/typed_conversation_screen.dart';

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

TranscriptSegment _segment(String text) => TranscriptSegment(
      id: 'seg',
      text: text,
      speaker: 'SPEAKER_00',
      isUser: false,
      personId: null,
      start: 0,
      end: 2,
      translations: [],
    );

/// What the server stores past the free minutes: a transcript-derived title, no overview, `none`.
ServerConversation _transcriptOnly({String id = 'transcript-only', DateTime? createdAt, bool isLocked = false}) {
  final created = createdAt ?? DateTime.now();
  return ServerConversation(
    id: id,
    createdAt: created,
    startedAt: created,
    finishedAt: created.add(const Duration(minutes: 23)),
    structured: Structured('Is the demo still on Thursday?', ''),
    transcriptSegments: [_segment('Is the demo still on Thursday?')],
    isLocked: isLocked,
    processingState: 'none',
  );
}

ServerConversation _summarized({DateTime? createdAt}) => ServerConversation(
      id: 'summarized',
      createdAt: createdAt ?? DateTime.now(),
      structured: Structured('Coffee with Maya', 'Caught up with Maya over coffee.', emoji: '☕'),
      transcriptSegments: [_segment('So when is the move?')],
    );

void main() {
  late UsageProvider usage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesUtil.init();
    usage = UsageProvider();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() => usage.dispose());

  Widget app(Widget body, {NavigatorObserver? observer, List<SingleChildWidget> providers = const []}) {
    return MultiProvider(
      providers: [ChangeNotifierProvider<UsageProvider>.value(value: usage), ...providers],
      child: MaterialApp(
        theme: buildOmiTheme(),
        navigatorObservers: [if (observer != null) observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(body: body),
      ),
    );
  }

  group('the server marker', () {
    test('processing_state none reads as a conversation kept without a summary', () {
      final parsed = ServerConversation.fromJson({
        ..._transcriptOnly().toJson(),
        'processing_state': 'none',
      });
      expect(parsed.processingState, 'none');
      expect(parsed.summaryUnavailableOnFreePlan, isTrue);
      expect(ServerConversation.fromJson(parsed.toJson()).summaryUnavailableOnFreePlan, isTrue);
    });

    test('a summarized, locked or desktop-pending row is not one', () {
      expect(_summarized().summaryUnavailableOnFreePlan, isFalse);
      expect(_transcriptOnly(isLocked: true).summaryUnavailableOnFreePlan, isFalse);
      final pending = ServerConversation.fromJson({..._transcriptOnly().toJson(), 'processing_state': 'local_pending'});
      expect(pending.summaryUnavailableOnFreePlan, isFalse);
    });

    test('free minutes come back on the first of next month, across the year', () {
      expect(freePlanMinutesResetDay(DateTime(2026, 10, 3, 19, 41)), DateTime(2026, 11, 1));
      expect(freePlanMinutesResetDay(DateTime(2026, 12, 31, 23, 59)), DateTime(2027, 1, 1));
    });

    test('a transcript-only conversation opens on its transcript', () {
      expect(conversationDetailInitialTab(_transcriptOnly()), ConversationTab.transcript);
    });
  });

  group('Home', () {
    testWidgets('a transcript-only row says Transcript only after its time and length', (tester) async {
      // Wide enough for the label in the test font only once it gets the row's spare room.
      tester.view.physicalSize = const Size(600, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final conversations = ConversationProvider(isSignedIn: () => false);
      addTearDown(conversations.dispose);
      final conversation = _transcriptOnly();
      await tester.pumpWidget(app(
        ListView(children: [
          ConversationListItem(conversation: conversation, date: conversation.createdAt, conversationIdx: 0)
        ]),
        providers: [ChangeNotifierProvider<ConversationProvider>.value(value: conversations)],
      ));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

      expect(find.text('Is the demo still on Thursday?'), findsOneWidget);
      expect(find.byKey(const Key('conversation_row_transcript_only')), findsOneWidget);
      expect(find.text(l10n.transcriptOnly), findsOneWidget);
      // The label is whole, not "Transcript …" beside an empty spacer.
      final label = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byKey(const Key('conversation_row_transcript_only')), matching: find.byType(RichText)));
      expect(label.didExceedMaxLines, isFalse);
      expect(find.byType(OmiLockedPreview), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Summaries are paused opens the newest day, under its date and above its rows', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = ConversationProvider(isSignedIn: () => false);
      addTearDown(provider.dispose);
      await tester.pumpWidget(await buildTypedConversationScreen(provider));
      await provider.addConversation(_summarized(createdAt: DateTime.now().subtract(const Duration(hours: 2))));
      await provider.addConversation(_transcriptOnly());
      await tester.pump();

      final header = find.byType(DateListItem);
      final paused = find.byType(SummariesPausedRow);
      final rows = find.byType(ConversationListItem);
      expect(paused, findsOneWidget);
      expect(rows, findsNWidgets(2));
      expect(tester.getBottomLeft(header.first).dy, lessThanOrEqualTo(tester.getTopLeft(paused).dy));
      expect(tester.getBottomLeft(paused).dy, lessThanOrEqualTo(tester.getTopLeft(rows.first).dy));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('no paused row when the newest day was summarized', (tester) async {
      final provider = ConversationProvider(isSignedIn: () => false);
      addTearDown(provider.dispose);
      await tester.pumpWidget(await buildTypedConversationScreen(provider));
      await provider.addConversation(_transcriptOnly(createdAt: DateTime.now().subtract(const Duration(days: 3))));
      await provider.addConversation(_summarized());
      await tester.pump();

      expect(find.byType(SummariesPausedRow), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the paused row names the reset day and opens the plan with the upgrade sheet', (tester) async {
      final routes = _Routes();
      await tester.pumpWidget(app(SummariesPausedRow(now: DateTime(2026, 10, 3)), observer: routes));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

      expect(find.text(l10n.summariesPaused), findsOneWidget);
      expect(find.text(l10n.freeMinutesBackOn('Nov 1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('summaries_paused_row')));
      final route = routes.pushed.last as MaterialPageRoute;
      final destination = route.builder(tester.element(find.byType(SummariesPausedRow)));
      expect(destination, isA<UsagePage>());
      expect((destination as UsagePage).showUpgradeDialog, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Summary tab', () {
    ConversationDetailProvider detailFor(ServerConversation conversation) {
      final detail = ConversationDetailProvider()
        ..selectedDate = conversationLocalDayKey(conversation.createdAt)
        ..setCachedConversation(conversation)
        ..titleController = TextEditingController(text: conversation.structured.title)
        ..titleFocusNode = FocusNode();
      addTearDown(detail.dispose);
      return detail;
    }

    Widget summary(ConversationDetailProvider detail, {VoidCallback? onReadTranscript, NavigatorObserver? observer}) {
      return app(
        CustomScrollView(slivers: [GetAppsWidgets(onReadTranscript: onReadTranscript)]),
        observer: observer,
        providers: [ChangeNotifierProvider<ConversationDetailProvider>.value(value: detail)],
      );
    }

    testWidgets('says what is missing and why, in place of Generate Summary', (tester) async {
      var readTranscript = 0;
      await tester.pumpWidget(summary(detailFor(_transcriptOnly()), onReadTranscript: () => readTranscript++));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

      expect(find.byKey(const Key('conversation_detail_free_plan_summary')), findsOneWidget);
      expect(find.text(l10n.noSummaryFreePlanTitle), findsOneWidget);
      expect(find.text(l10n.noSummaryFreePlanBody), findsOneWidget);
      expect(find.text(l10n.upgradeToUnlimited), findsOneWidget);
      expect(find.text(l10n.generateSummary), findsNothing);
      expect(find.text(l10n.noSummaryForConversation), findsNothing);

      await tester.tap(find.byKey(const Key('free_plan_summary_read_transcript')));
      expect(readTranscript, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Upgrade to Unlimited opens the plan with the upgrade sheet', (tester) async {
      final routes = _Routes();
      await tester.pumpWidget(summary(detailFor(_transcriptOnly()), observer: routes));
      await tester.tap(find.byKey(const Key('free_plan_summary_upgrade')));
      final route = routes.pushed.last as MaterialPageRoute;
      final destination = route.builder(tester.element(find.byType(FreePlanSummaryNotice)));
      expect(destination, isA<UsagePage>());
      expect((destination as UsagePage).showUpgradeDialog, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a summarized conversation keeps its summary', (tester) async {
      await tester.pumpWidget(summary(detailFor(_summarized())));
      expect(find.byType(FreePlanSummaryNotice), findsNothing);
      expect(find.textContaining('Caught up with Maya'), findsOneWidget);
    });
  });
}
