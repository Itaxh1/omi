// The Memories page (v3): the graph of people and topics, the list, adding one, quick edit, and the
// list's end with Make all private and Delete all memories.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:omi/app_globals.dart';
import 'package:omi/backend/schema/memory.dart';
import 'package:omi/pages/memories/page.dart';
import 'package:omi/providers/memories_provider.dart';
import 'package:omi/ui/ui.dart';

import '../harness.dart';

const _page = 'lib/pages/memories/page.dart (MemoriesPage)';
const _preference = 'I prefer morning meetings and keep Fridays free for focused work.';

/// A small knowledge graph: the reader, three people and two topics.
Future<Map<String, dynamic>> _graph() async => {
      'nodes': [
        {'id': 'u', 'label': 'You', 'node_type': 'user'},
        {'id': 'p1', 'label': 'Priya', 'node_type': 'person'},
        {'id': 'p2', 'label': 'Alex', 'node_type': 'person'},
        {'id': 'p3', 'label': 'Sam', 'node_type': 'person'},
        {'id': 't1', 'label': 'Pricing', 'node_type': 'concept'},
        {'id': 't2', 'label': 'Battery', 'node_type': 'concept'},
      ],
      'edges': [
        {'source_id': 'u', 'target_id': 'p1'},
        {'source_id': 'u', 'target_id': 'p2'},
        {'source_id': 'p1', 'target_id': 't1'},
        {'source_id': 'p2', 'target_id': 't2'},
        {'source_id': 'u', 'target_id': 'p3'},
      ],
    };

final memoriesScenarios = <AuditScenario>[
  AuditScenario(
    id: 'memories-manual-memory',
    title: 'Memories: empty, add one, save, quick edit',
    page: _page,
    state: 'Fixture-backed MemoriesProvider on an account with no memories; one manual memory is saved during the run',
    run: (a) async {
      final tester = a.tester;
      await a.pump(const MemoriesPage(loadGraph: _graph),
          providers: [ChangeNotifierProvider(create: (_) => MemoriesProvider())]);
      await a.shot('Open Memories with an empty account', step: 'empty');
      await a.tap(find.byKey(const Key('memories_add')));
      await a.shot('Tap + in the header', step: 'create');
      expect(tester.widget<OmiButton>(find.byKey(const ValueKey('memory_save_button'))).onPressed, isNull);
      await a.enterText(find.byKey(const ValueKey('memory_content_field')), _preference);
      await a.shot('Enter a preference', step: 'draft');
      await a.tap(find.byKey(const ValueKey('memory_save_button')));
      await a.shot('Save the preference through the fixture backend', step: 'saved');
      await a.tap(find.text(_preference));
      await a.shot('Tap the memory to open quick edit', step: 'edit');
      globalNavigatorKey.currentState!.pop();
      await a.settle();
    },
  ),
  AuditScenario(
    id: 'memories-graph',
    title: 'Memories with the graph, a few memories and the list end',
    page: _page,
    state: 'Three saved memories and a knowledge graph of three people and two topics',
    run: (a) async {
      final memories = MemoriesProvider();
      await a.tester.runAsync(() async {
        await memories.createMemory('Priya owns the pricing model for the annual plan.', MemoryVisibility.private);
        await memories.createMemory('Alex is chasing the battery-drain reports.', MemoryVisibility.private);
        await memories.createMemory('Prefers morning meetings and keeps Fridays free.', MemoryVisibility.private);
      });
      await a.pump(const MemoriesPage(loadGraph: _graph),
          providers: [ChangeNotifierProvider<MemoriesProvider>.value(value: memories)]);
      await a.shot('Memories: the graph, how many there are, then each memory', step: 'list');
      await a.tap(find.text('Priya').first);
      await a.shot('Tap a name in the graph: only the memories that mention it', step: 'focus');
    },
  ),
];
