// Conversations (v3): All conversations, locked rows, a folder; Daily Recaps and Offline Sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/schema/daily_summary.dart';
import 'package:omi/backend/schema/folder.dart';
import 'package:omi/backend/schema/schema.dart';
import 'package:omi/pages/conversations/auto_sync_page.dart';
import 'package:omi/pages/conversations/all_conversations_page.dart';
import 'package:omi/pages/conversations/daily_recaps_page.dart';
import 'package:omi/providers/conversation_provider.dart';
import 'package:omi/providers/folder_provider.dart';
import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/sync_provider.dart';
import 'package:omi/services/wals/wal.dart';

import '../fakes.dart';
import '../harness.dart';

const _page = 'lib/pages/conversations/all_conversations_page.dart (AllConversationsPage)';

/// A ConversationProvider already holding [items], grouped by date, whose deletes succeed locally.
List<SingleChildWidget> _listProviders(List<ServerConversation> items) {
  final provider = ConversationProvider(
    conversationListFetcher: () async => (items: items, ok: true),
    isSignedIn: () => true,
  )
    ..conversationDeleteFetcherOverride = ((_) async => true)
    ..conversations = items
    ..groupConversationsByDate();
  return [
    ChangeNotifierProvider<ConversationProvider>.value(value: provider),
    ChangeNotifierProvider(create: (_) => FolderProvider(foldersFetcher: () async => <Folder>[])),
  ];
}

final conversationsScenarios = <AuditScenario>[
  AuditScenario(
    id: 'conversations-list',
    title: 'All conversations (v3): search, days, time and title rows',
    page: _page,
    state: 'Five conversations today and two yesterday, from the pendant, the phone and glasses',
    run: (a) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      ServerConversation at(String id, String title, DateTime when, ConversationSource source) => ServerConversation(
            id: id,
            createdAt: when,
            startedAt: when,
            finishedAt: when.add(const Duration(minutes: 12)),
            structured: Structured(title, 'Overview', emoji: '', category: 'work'),
            status: ConversationStatus.completed,
            source: source,
          );
      final items = [
        at('t1', 'Call Chitapa reminder', today.add(const Duration(hours: 15, minutes: 14)), ConversationSource.omi),
        at('t2', 'App reliability and subscription concerns', today.add(const Duration(hours: 14, minutes: 43)),
            ConversationSource.phone),
        at('t3', 'App UX and battery', today.add(const Duration(hours: 14, minutes: 2)), ConversationSource.omi),
        at('t4', 'Pricing review', today.add(const Duration(hours: 11, minutes: 5)), ConversationSource.openglass),
        at('t5', 'iPhone roadmap', today.add(const Duration(hours: 9, minutes: 40)), ConversationSource.omi),
        at('y1', 'Design catch-up with Alex', today.subtract(const Duration(hours: 7)), ConversationSource.omi),
        at('y2', 'Standup with the hardware team', today.subtract(const Duration(hours: 14)), ConversationSource.omi),
      ];
      await a.pump(const AllConversationsPage(), scaffold: false, providers: _listProviders(items));
      await a.shot('All conversations: the search pill, Today and Yesterday, one row per conversation');
    },
  ),
  AuditScenario(
    id: 'conversations-locked',
    title: 'Out of free minutes: locked rows keep their title and time',
    page: _page,
    state: 'The plan ran out: two locked conversations above an unlocked one',
    run: (a) async {
      final items = [
        ServerConversation(
          id: 'l1',
          createdAt: DateTime(2026, 9, 26, 9, 40),
          startedAt: DateTime(2026, 9, 26, 9, 40),
          finishedAt: DateTime(2026, 9, 26, 9, 49),
          structured: Structured('Standup with the hardware team', 'Firmware 2.3 ships Friday.', category: 'work'),
          isLocked: true,
        ),
        ServerConversation(
          id: 'l2',
          createdAt: DateTime(2026, 9, 26, 8, 15),
          startedAt: DateTime(2026, 9, 26, 8, 15),
          finishedAt: DateTime(2026, 9, 26, 8, 39),
          structured: Structured('Coffee with Priya', '', category: 'personal'),
          isLocked: true,
        ),
        auditConversation('u1', title: 'Design catch-up with Alex'),
      ];
      await a.pump(const AllConversationsPage(), scaffold: false, providers: _listProviders(items));
      await a.shot('Locked rows: title and time; opening one offers the plan');
    },
  ),
  AuditScenario(
    id: 'conversations-folder',
    title: 'A folder: its name in the header and only its conversations',
    page: _page,
    state: 'A Work folder holding two of three conversations',
    run: (a) async {
      final work = ServerConversation(
        id: 'w1',
        createdAt: DateTime(2026, 9, 20, 10),
        structured: Structured('Design catch-up with Alex', 'Overview', category: 'work'),
        status: ConversationStatus.completed,
        folderId: 'work',
      );
      final items = [
        work,
        auditConversation('w2', title: 'Pricing review'),
        auditConversation('p1', title: 'Coffee with Priya'),
      ];
      await a.pump(const AllConversationsPage(scope: FolderScope('work', 'Work')),
          scaffold: false, providers: _listProviders(items));
      await a.shot('The Work folder');
    },
  ),
  AuditScenario(
    id: 'conversations-daily-recaps',
    title: 'Daily Recaps',
    page: 'lib/pages/conversations/daily_recaps_page.dart (DailyRecapsPage)',
    state: 'An injected fetcher returning one daily recap for 2026-09-20',
    run: (a) async {
      final summary = DailySummary(
        id: 'summary-1',
        date: '2026-09-20',
        createdAt: DateTime.utc(2026, 9, 20, 12),
        headline: 'A quiet day',
        overview: 'Nothing much happened',
        stats: DayStats(totalConversations: 5, actionItemsCount: 3),
      );
      await a.pump(
          DailyRecapsPage(fetchSummaries: ({int limit = 20, int offset = 0}) async => (items: [summary], ok: true)));
      await a.shot('Open Daily Recaps');
    },
  ),
  AuditScenario(
    id: 'conversations-offline-sync',
    title: 'Offline Sync with nothing pending',
    page: 'lib/pages/conversations/auto_sync_page.dart (AutoSyncPage)',
    state: 'Inert SyncProvider with no recordings; no device connected',
    run: (a) async {
      await a.pump(const AutoSyncPage());
      await a.shot('Open Offline Sync with no pending recordings');
    },
  ),
  AuditScenario(
    id: 'conversations-offline-sync-pending',
    title: 'Offline Sync with recordings waiting, one failed, and two synced',
    page: 'lib/pages/conversations/auto_sync_page.dart (AutoSyncPage)',
    state: 'A connected Omi pendant; four offline recordings (waiting, failed after retries, two synced)',
    run: (a) async {
      int at(int day, int hour, int minute) => DateTime(2026, 9, day, hour, minute).millisecondsSinceEpoch ~/ 1000;
      Wal wal(int start, int seconds, WalStatus status, {int retries = 0, String? conversationId}) => Wal(
            timerStart: start,
            codec: BleAudioCodec.opus,
            seconds: seconds,
            status: status,
            storage: WalStorage.sdcard,
            device: 'omi',
            retryCount: retries,
            conversationId: conversationId,
          );
      final wals = [
        wal(at(20, 11, 20), 18 * 60, WalStatus.miss),
        wal(at(20, 9, 2), 6 * 60, WalStatus.miss, retries: walMaxAutoRetries),
        wal(at(19, 18, 5), 18 * 60, WalStatus.synced, conversationId: 'c1'),
        wal(at(19, 11, 40), 42 * 60, WalStatus.synced, conversationId: 'c2'),
      ];
      final pendant = BtDevice(id: 'D1:A2:B3:C4:D5:E6', name: 'Omi', type: DeviceType.omi, rssi: -40);
      await a.pump(const AutoSyncPage(), providers: [
        ChangeNotifierProvider<SyncProvider>.value(value: _SeededSyncProvider(wals)),
        ChangeNotifierProvider<DeviceProvider>.value(value: AuditDeviceProvider(connected: true, device: pendant)),
      ]);
      await a.shot('Open Offline Sync: the pending recordings first', step: 'pending');
      await a.tap(find.text('All'));
      await a.shot('Tap All: every recording, then Storage', step: 'all');
    },
  ),
];

/// Offline recordings for the Sync page, grouped the way [SyncProvider] groups them.
class _SeededSyncProvider extends InertSyncProvider {
  _SeededSyncProvider(this.wals);

  final List<Wal> wals;

  bool _pending(Wal w) => switch (w.syncDisplayState) {
        WalSyncDisplayState.waiting || WalSyncDisplayState.retrying || WalSyncDisplayState.failed => true,
        _ => false,
      };

  @override
  List<Wal> get allWals => wals;
  @override
  List<Wal> get displaySortedWals => wals;
  @override
  List<Wal> walsForDisplayFilter(WalDisplayFilter filter) => switch (filter) {
        WalDisplayFilter.pending => wals.where(_pending).toList(),
        WalDisplayFilter.synced => wals.where((w) => w.syncDisplayState == WalSyncDisplayState.synced).toList(),
        _ => wals,
      };
  @override
  int get needsAttentionWalsCount => wals.where((w) => w.syncDisplayState == WalSyncDisplayState.failed).length;
  @override
  int get clearableWalsCount => wals.length;
  @override
  int get missingWalsInSeconds => wals.where(_pending).fold(0, (sum, w) => sum + w.seconds);
}
